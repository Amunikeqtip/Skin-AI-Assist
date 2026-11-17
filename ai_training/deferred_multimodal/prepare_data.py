"""Unify local skin-image sources into one audited manifest.

The script does not download datasets. Fitzpatrick17k-C is non-commercial, and
DermNet compilations often cannot be redistributed. Point --sources at files
you already have the rights to use.

Outputs:
    manifest.jsonl   one record per kept image
    audit.json       drops, label counts, skin-tone counts, split method

Images are removed when they cannot be decoded, are smaller than 224 pixels,
fail the same Laplacian / exposure heuristics as the phone app, match a refused
or overly coarse label, or are an exact byte duplicate of an earlier image.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path

import numpy as np
import pandas as pd
from PIL import Image, UnidentifiedImageError
from sklearn.model_selection import StratifiedGroupKFold, StratifiedShuffleSplit

from schema import (
    encode_metadata,
    metadata_is_blank,
    normalize_key,
    parse_body_site,
    parse_duration,
    parse_tone,
    parse_tri_state,
)

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}
PAD_REGION = {
    "FACE": "Face",
    "NOSE": "Face",
    "EAR": "Face",
    "NECK": "Neck",
    "CHEST": "Chest",
    "BACK": "Back",
    "ARM": "Arm",
    "FOREARM": "Arm",
    "HAND": "Hand",
    "PALM": "Hand",
    "THIGH": "Leg",
    "LEG": "Leg",
    "FOOT": "Foot",
    "SOLE": "Foot",
}
PAD_DIAGNOSIS = {
    "ACK": "actinic_keratosis",
    "BCC": "basal_cell_carcinoma",
    "MEL": "melanoma",
    "NEV": "nevus",
    "SCC": "squamous_cell_carcinoma",
    "SEK": "seborrheic_keratosis",
}


def load_taxonomy(path: Path) -> dict[str, object]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    canonical = set(raw["canonical_labels"])
    aliases = {normalize_key(key): value for key, value in raw["aliases"].items()}
    unknown_targets = sorted(set(aliases.values()).difference(canonical))
    if unknown_targets:
        raise ValueError(f"Taxonomy aliases point at unknown labels: {unknown_targets}")
    return {
        "canonical": canonical,
        "aliases": aliases,
        "excluded_coarse": {normalize_key(item) for item in raw["excluded_coarse"]},
        "refused": {normalize_key(item) for item in raw["refused_not_a_photo_diagnosis"]},
    }


def classify_label(raw_label: object, taxonomy: dict[str, object]) -> tuple[str | None, str]:
    key = normalize_key(raw_label)
    if key in taxonomy["refused"]:
        return None, "refused"
    if key in taxonomy["excluded_coarse"]:
        return None, "coarse"
    aliases = taxonomy["aliases"]
    assert isinstance(aliases, dict)
    mapped = aliases.get(key)
    if mapped is None:
        return None, "unmapped"
    return str(mapped), "kept"


def clean_group(value: object) -> str | None:
    if value is None or (isinstance(value, float) and np.isnan(value)):
        return None
    text = str(value).strip()
    if text == "" or text.lower() in {"nan", "none"}:
        return None
    return text


def blank_record(source: str, image_path: Path, label: str, group_id: object) -> dict[str, object]:
    tone_group, tone_value = "Unknown", None
    group = clean_group(group_id)
    return {
        "source": source,
        "image_path": str(image_path),
        "label": label,
        "skin_tone": tone_group,
        "fitzpatrick": tone_value,
        "group_id": None if group is None else f"{source}/{group}",
        "given_split": None,
        "body_site": "Unknown",
        "itch": "unknown",
        "pain": "unknown",
        "swelling": "unknown",
        "changed": "unknown",
        "duration": "Unknown",
    }


def read_folders(source: dict[str, object], taxonomy: dict[str, object], audit: Counter) -> list[dict[str, object]]:
    root = Path(str(source["root"]))
    if not root.is_dir():
        raise FileNotFoundError(f"Missing image folder: {root}")
    grouped = bool(source.get("grouped", False))
    records: list[dict[str, object]] = []
    for class_dir in sorted(path for path in root.iterdir() if path.is_dir()):
        label, reason = classify_label(class_dir.name, taxonomy)
        if label is None:
            count = sum(1 for path in class_dir.rglob("*") if path.suffix.lower() in IMAGE_SUFFIXES)
            audit[f"label_{reason}:{class_dir.name}"] += count
            continue
        if grouped:
            for group_dir in sorted(path for path in class_dir.iterdir() if path.is_dir()):
                for image in group_dir.rglob("*"):
                    if image.suffix.lower() not in IMAGE_SUFFIXES:
                        continue
                    record = blank_record(str(source["name"]), image, label, f"{class_dir.name}/{group_dir.name}")
                    records.append(record)
        else:
            for image in class_dir.rglob("*"):
                if image.suffix.lower() not in IMAGE_SUFFIXES:
                    continue
                records.append(blank_record(str(source["name"]), image, label, None))
    return records


def read_csv(source: dict[str, object], taxonomy: dict[str, object], audit: Counter) -> list[dict[str, object]]:
    metadata_path = Path(str(source["metadata"]))
    image_root = Path(str(source["image_root"]))
    frame = pd.read_csv(metadata_path)
    label_column = str(source.get("label_column", "label"))
    path_column = str(source.get("path_column", "filepath"))
    records: list[dict[str, object]] = []
    for row in frame.to_dict(orient="records"):
        label, reason = classify_label(row.get(label_column), taxonomy)
        if label is None:
            audit[f"label_{reason}:{row.get(label_column)}"] += 1
            continue
        image_path = image_root / str(row.get(path_column, ""))
        record = blank_record(
            str(source["name"]),
            image_path,
            label,
            None if source.get("group_column") is None else str(row.get(str(source["group_column"]), "")),
        )
        tone_group, tone_value = parse_tone(row.get(str(source.get("tone_column", "fitzpatrick"))))
        record["skin_tone"] = tone_group
        record["fitzpatrick"] = tone_value
        record["given_split"] = normalize_split(row.get(str(source.get("partition_column", "partition"))))
        record.update(metadata_from_row(row))
        records.append(record)
    return records


def read_pad(source: dict[str, object], audit: Counter) -> list[dict[str, object]]:
    data_dir = Path(str(source["data_dir"]))
    metadata_path = data_dir / "metadata.csv"
    image_root = data_dir / "all_images"
    if not metadata_path.is_file() or not image_root.is_dir():
        raise FileNotFoundError("PAD-UFES-20 source needs metadata.csv and all_images/.")
    lookup = {path.name: path for path in image_root.rglob("*") if path.is_file()}
    frame = pd.read_csv(metadata_path)
    records: list[dict[str, object]] = []
    for row in frame.to_dict(orient="records"):
        diagnosis = str(row.get("diagnostic", "")).upper()
        label = PAD_DIAGNOSIS.get(diagnosis)
        if label is None:
            audit[f"label_unmapped:{diagnosis}"] += 1
            continue
        image_name = str(row.get("img_id", ""))
        image_path = lookup.get(image_name)
        if image_path is None:
            audit["missing_file"] += 1
            continue
        tone_group, tone_value = parse_tone(row.get("fitspatrick", row.get("fitzpatrick")))
        region = row.get("region")
        body_site = parse_body_site(region, PAD_REGION)
        if body_site == "Other" and region not in (None, ""):
            audit[f"region_other:{region}"] += 1
        records.append(
            {
                "source": str(source["name"]),
                "image_path": str(image_path),
                "label": label,
                "skin_tone": tone_group,
                "fitzpatrick": tone_value,
                "group_id": f"{source['name']}/{row.get('patient_id')}",
                "given_split": None,
                "body_site": body_site,
                "itch": parse_tri_state(row.get("itch")),
                "pain": parse_tri_state(row.get("hurt")),
                "swelling": "unknown",
                "changed": parse_tri_state(row.get("changed")),
                "duration": "Unknown",
            }
        )
    return records


def metadata_from_row(row: dict[str, object]) -> dict[str, str]:
    return {
        "body_site": parse_body_site(row.get("body_site", row.get("region"))),
        "itch": parse_tri_state(row.get("itch")),
        "pain": parse_tri_state(row.get("pain", row.get("hurt"))),
        "swelling": parse_tri_state(row.get("swelling")),
        "changed": parse_tri_state(row.get("changed")),
        "duration": parse_duration(row.get("duration")),
    }


def normalize_split(value: object) -> str | None:
    key = normalize_key(value)
    if key in {"train", "training"}:
        return "train"
    if key in {"val", "valid", "validation"}:
        return "val"
    if key in {"test", "testing"}:
        return "test"
    return None


def file_md5(path: Path) -> str:
    digest = hashlib.md5()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def image_quality(path: Path, min_side: int, min_sharpness: float, check_exposure: bool) -> str | None:
    try:
        with Image.open(path) as image:
            image.load()
            if min(image.size) < min_side:
                return "small"
            gray = image.convert("L")
            gray.thumbnail((96, 96))
            pixels = np.asarray(gray, dtype=np.float32)
    except (UnidentifiedImageError, OSError, ValueError):
        return "corrupt"
    if pixels.shape[0] < 3 or pixels.shape[1] < 3:
        return "small"
    center = pixels[1:-1, 1:-1]
    laplacian = 4 * center - pixels[1:-1, :-2] - pixels[1:-1, 2:] - pixels[:-2, 1:-1] - pixels[2:, 1:-1]
    if float(laplacian.var()) < min_sharpness:
        return "blurry"
    if check_exposure:
        dark = float(np.mean(pixels < 12))
        bright = float(np.mean(pixels > 250))
        if dark > 0.8 or bright > 0.8:
            return "exposure"
    return None


def filter_images(
    records: list[dict[str, object]],
    min_side: int,
    min_sharpness: float,
    check_exposure: bool,
    audit: Counter,
) -> list[dict[str, object]]:
    kept: list[dict[str, object]] = []
    seen_hash: set[str] = set()
    for index, record in enumerate(records, start=1):
        path = Path(str(record["image_path"]))
        if not path.is_file():
            audit["missing_file"] += 1
            continue
        reason = image_quality(path, min_side, min_sharpness, check_exposure)
        if reason is not None:
            audit[reason] += 1
            continue
        digest = file_md5(path)
        if digest in seen_hash:
            audit["duplicate_bytes"] += 1
            continue
        seen_hash.add(digest)
        kept.append(record)
        if index % 500 == 0:
            print(f"Checked {index} candidate images; kept {len(kept)}.")
    return kept


def drop_rare_labels(frame: pd.DataFrame, min_images: int, audit: Counter) -> pd.DataFrame:
    counts = frame["label"].value_counts()
    rare = sorted(counts[counts < min_images].index)
    for label in rare:
        audit[f"rare_label:{label}"] += int(counts[label])
    return frame.loc[~frame["label"].isin(rare)].reset_index(drop=True)


def assign_splits(frame: pd.DataFrame, allow_image_level: bool) -> tuple[pd.DataFrame, str]:
    given = frame.loc[frame["given_split"].notna()].copy()
    pending = frame.loc[frame["given_split"].isna()].copy()
    if pending.empty:
        given["split"] = given["given_split"]
        _assert_group_separation(given)
        return given, "source-partition"

    grouped = pending["group_id"].notna() & pending["group_id"].astype(str).ne("")
    if bool(grouped.all()):
        pending = _group_split(pending)
        method = "patient-or-group"
    else:
        if not allow_image_level:
            raise ValueError(
                "Some images have no patient or group id and no original split. "
                "Re-run with --allow-image-level-split only if duplicate photos across "
                "train and test are acceptable for an experiment. That split can leak."
            )
        pending = _image_split(pending)
        method = "image-level"
    if given.empty:
        _assert_group_separation(pending)
        return pending, method
    given["split"] = given["given_split"]
    combined = pd.concat([given, pending], ignore_index=True)
    _assert_group_separation(combined)
    return combined, f"mixed: kept source partitions; remaining used {method}"


def _group_split(frame: pd.DataFrame) -> pd.DataFrame:
    group_counts = frame.groupby("label")["group_id"].nunique()
    if int(group_counts.min()) < 3:
        raise ValueError(
            "Every kept label needs at least 3 patient or group ids "
            f"before a grouped split. Smallest counts: {group_counts.to_dict()}"
        )
    n_splits = int(min(5, group_counts.min()))
    outer = StratifiedGroupKFold(n_splits=n_splits, shuffle=True, random_state=42)
    train_val_idx, test_idx = next(outer.split(frame, frame["label"], groups=frame["group_id"]))
    train_val = frame.iloc[train_val_idx].reset_index(drop=True)
    test = frame.iloc[test_idx].copy()
    test["split"] = "test"
    inner_groups = int(train_val.groupby("label")["group_id"].nunique().min())
    inner = StratifiedGroupKFold(
        n_splits=max(2, min(4, inner_groups)), shuffle=True, random_state=43
    )
    train_idx, val_idx = next(inner.split(train_val, train_val["label"], groups=train_val["group_id"]))
    train = train_val.iloc[train_idx].copy()
    valid = train_val.iloc[val_idx].copy()
    train["split"] = "train"
    valid["split"] = "val"
    return pd.concat([train, valid, test], ignore_index=True)


def _image_split(frame: pd.DataFrame) -> pd.DataFrame:
    counts = frame["label"].value_counts()
    if int(counts.min()) < 6:
        raise ValueError(
            "Image-level stratified splits need at least 6 images in every kept label. "
            f"Counts: {counts.to_dict()}"
        )
    outer = StratifiedShuffleSplit(n_splits=1, test_size=0.15, random_state=42)
    train_val_idx, test_idx = next(outer.split(frame, frame["label"]))
    train_val = frame.iloc[train_val_idx].reset_index(drop=True)
    test = frame.iloc[test_idx].copy()
    test["split"] = "test"
    inner = StratifiedShuffleSplit(n_splits=1, test_size=0.1765, random_state=43)
    train_idx, val_idx = next(inner.split(train_val, train_val["label"]))
    train = train_val.iloc[train_idx].copy()
    valid = train_val.iloc[val_idx].copy()
    train["split"] = "train"
    valid["split"] = "val"
    return pd.concat([train, valid, test], ignore_index=True)


def _assert_group_separation(frame: pd.DataFrame) -> None:
    known = frame.loc[frame["group_id"].notna() & frame["group_id"].astype(str).ne("")]
    if known.empty:
        return
    for group_id, splits in known.groupby("group_id")["split"].nunique().items():
        if int(splits) > 1:
            raise ValueError(f"Group {group_id} appears in more than one split.")


def audit_frame(frame: pd.DataFrame, method: str, allow_image_level: bool, audit: Counter) -> dict[str, object]:
    blank = 0
    for row in frame.itertuples(index=False):
        vector = encode_metadata(row.body_site, row.itch, row.pain, row.swelling, row.changed, row.duration)
        blank += int(metadata_is_blank(vector))
    per_split = {
        split: {
            "images": int((frame["split"] == split).sum()),
            "labels": frame.loc[frame["split"].eq(split), "label"].value_counts().to_dict(),
            "skin_tones": frame.loc[frame["split"].eq(split), "skin_tone"].value_counts().to_dict(),
        }
        for split in ("train", "val", "test")
    }
    return {
        "split_method": method,
        "image_level_split_accepted": bool(allow_image_level and "image-level" in method),
        "healthy_present": bool((frame["label"] == "healthy").any()),
        "metadata_blank_images": blank,
        "metadata_blank_fraction": blank / max(len(frame), 1),
        "drops": dict(audit),
        "splits": per_split,
        "note": (
            "Skin tone is taken from a dataset field when one exists. "
            "It is not estimated from the photo. Unknown means the source had no tone label. "
            "Refused labels cannot be established from a photo. Coarse labels such as "
            "'skin cancer' mix different diseases and are left out."
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", type=Path, required=True)
    parser.add_argument("--taxonomy", type=Path, default=Path(__file__).with_name("taxonomy.json"))
    parser.add_argument("--output-dir", type=Path, default=Path("ai_training/deferred_multimodal/prepared"))
    parser.add_argument("--min-images", type=int, default=9)
    parser.add_argument("--min-side", type=int, default=224)
    parser.add_argument("--min-sharpness", type=float, default=18.0)
    parser.add_argument("--skip-exposure-check", action="store_true")
    parser.add_argument("--allow-image-level-split", action="store_true")
    args = parser.parse_args()

    taxonomy = load_taxonomy(args.taxonomy)
    sources = json.loads(args.sources.read_text(encoding="utf-8"))["sources"]
    audit: Counter = Counter()
    records: list[dict[str, object]] = []
    for source in sources:
        kind = source.get("kind")
        print(f"Reading {source.get('name')} ({kind}).")
        if kind == "folders":
            records.extend(read_folders(source, taxonomy, audit))
        elif kind == "csv":
            records.extend(read_csv(source, taxonomy, audit))
        elif kind == "pad_ufes":
            records.extend(read_pad(source, audit))
        else:
            raise ValueError(f"Unknown source kind: {kind}")
    if not records:
        raise ValueError("No labeled images matched the taxonomy.")

    print(f"Checking {len(records)} labeled images.")
    kept = filter_images(
        records,
        args.min_side,
        args.min_sharpness,
        not args.skip_exposure_check,
        audit,
    )
    frame = drop_rare_labels(pd.DataFrame(kept), args.min_images, audit)
    if frame["label"].nunique() < 2:
        raise ValueError("Fewer than two labels remain after filtering.")
    frame, method = assign_splits(frame, args.allow_image_level_split)
    report = audit_frame(frame, method, args.allow_image_level_split, audit)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    manifest = args.output_dir / "manifest.jsonl"
    with manifest.open("w", encoding="utf-8") as handle:
        for row in frame.to_dict(orient="records"):
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")
    (args.output_dir / "audit.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"Wrote {len(frame)} images to {manifest}")
    print(f"Healthy class present: {report['healthy_present']}")
    print(f"Images with no body-site or symptom fields: {report['metadata_blank_fraction']:.1%}")


if __name__ == "__main__":
    main()

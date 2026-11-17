"""Prepare PAD-UFES plus MSLD v2 for an 8-class image-only prototype.

PAD contributes its six lesion classes. MSLD contributes a healthy class and
one deliberately limited `OTHER_SKIN_CONDITION` class from its five infectious
conditions. MSLD fold copies are deduplicated by patient/image filename before
making one patient-grouped split across both sources.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import zipfile
from collections import Counter
from pathlib import Path

import pandas as pd
from sklearn.model_selection import StratifiedGroupKFold

PAD_CLASSES = {"ACK", "BCC", "MEL", "NEV", "SCC", "SEK"}
MSLD_CODES = {"MKP", "CHP", "MSL", "CWP", "HFMD", "HEALTHY"}
OTHER_CLASS = "OTHER_SKIN_CONDITION"
SEED = 42


def split_patient_groups(frame: pd.DataFrame) -> pd.DataFrame:
    split_frames = []
    for source in frame["source"].unique():
        source_frame = frame[frame["source"] == source]
        outer = StratifiedGroupKFold(
            n_splits=6, shuffle=True, random_state=SEED
        )
        train_val_idx, test_idx = next(
            outer.split(
                source_frame,
                source_frame["stratify_label"],
                groups=source_frame["group_id"],
            )
        )
        train_val = source_frame.iloc[train_val_idx].copy()
        test = source_frame.iloc[test_idx].copy()

        inner = StratifiedGroupKFold(
            n_splits=5, shuffle=True, random_state=SEED + 1
        )
        train_idx, val_idx = next(
            inner.split(
                train_val,
                train_val["stratify_label"],
                groups=train_val["group_id"],
            )
        )
        train = train_val.iloc[train_idx].copy()
        val = train_val.iloc[val_idx].copy()
        train["split"] = "train"
        val["split"] = "val"
        test["split"] = "test"
        split_frames.extend((train, val, test))

    split_frame = pd.concat(split_frames, ignore_index=True)

    memberships = split_frame.groupby("group_id")["split"].nunique()
    if bool((memberships > 1).any()):
        raise RuntimeError("Patient/group leakage detected across splits.")
    return split_frame


def load_pad(data_dir: Path) -> pd.DataFrame:
    metadata_path = data_dir / "metadata.csv"
    image_root = data_dir / "all_images"
    if not metadata_path.is_file() or not image_root.is_dir():
        raise FileNotFoundError("PAD path must contain metadata.csv and all_images/.")

    metadata = pd.read_csv(metadata_path)
    required = {"patient_id", "diagnostic", "img_id"}
    missing = required.difference(metadata.columns)
    if missing:
        raise ValueError(f"PAD metadata is missing columns: {sorted(missing)}")

    lookup = {path.name: path for path in image_root.rglob("*") if path.is_file()}
    metadata["image_path"] = metadata["img_id"].map(lookup)
    metadata = metadata.dropna(subset=["image_path"])
    metadata = metadata[metadata["diagnostic"].isin(PAD_CLASSES)].copy()
    metadata["label"] = metadata["diagnostic"]
    metadata["source"] = "PAD-UFES-20"
    metadata["source_class"] = metadata["diagnostic"]
    metadata["stratify_label"] = "PAD_" + metadata["diagnostic"].astype(str)
    metadata["group_id"] = "PAD_" + metadata["patient_id"].astype(str)
    return metadata[
        ["image_path", "label", "source", "source_class", "stratify_label", "group_id"]
    ]


def extract_unique_msld(zip_path: Path, output_dir: Path) -> tuple[pd.DataFrame, dict]:
    if not zip_path.is_file():
        raise FileNotFoundError(f"MSLD zip not found: {zip_path}")
    output_dir.mkdir(parents=True, exist_ok=True)
    pattern = re.compile(
        r"^(MKP|CHP|MSL|CWP|HFMD|HEALTHY)_(\d+)_(\d+)\.(jpg|jpeg|png)$",
        re.IGNORECASE,
    )

    records = []
    seen_names: set[str] = set()
    duplicate_hashes: Counter[str] = Counter()
    name_hashes: dict[str, str] = {}
    with zipfile.ZipFile(zip_path) as archive:
        for member in sorted(archive.namelist()):
            parts = member.split("/")
            if len(parts) != 4 or parts[0] != "FOLDS":
                continue
            if not re.fullmatch(r"fold\d+", parts[1], re.IGNORECASE):
                continue
            if parts[2].lower() not in {"train", "valid", "test", "val"}:
                continue

            basename = Path(parts[3]).name
            match = pattern.fullmatch(basename)
            if match is None:
                continue
            code, patient_id, _, _ = match.groups()
            code = code.upper()
            if code not in MSLD_CODES or basename in seen_names:
                continue
            seen_names.add(basename)

            image_bytes = archive.read(member)
            digest = hashlib.sha256(image_bytes).hexdigest()
            duplicate_hashes[digest] += 1
            name_hashes[basename] = digest

            target_dir = output_dir / code
            target_dir.mkdir(parents=True, exist_ok=True)
            image_path = target_dir / basename
            if not image_path.exists():
                image_path.write_bytes(image_bytes)

            records.append(
                {
                    "image_path": str(image_path),
                    "label": "HEALTHY" if code == "HEALTHY" else OTHER_CLASS,
                    "source": "MSLD-v2.0",
                    "source_class": code,
                    "stratify_label": f"MSLD_{code}",
                    # MSLD patient numbers are scoped to their disease code.
                    "group_id": f"MSLD_{code}_{patient_id}",
                }
            )

    if not records:
        raise ValueError("No original MSLD image records were found in the archive.")
    frame = pd.DataFrame(records)
    audit = {
        "source": "Mpox Skin Lesion Dataset v2.0",
        "license": "CC BY-NC 4.0; non-commercial use only",
        "dedupe_key": "class_patient_image basename across the five cross-validation folds",
        "unique_images": int(len(frame)),
        "class_counts": dict(Counter(frame["source_class"])),
        "unique_patients": int(frame["group_id"].nunique()),
        "same_content_different_name_count": int(
            sum(1 for count in Counter(name_hashes.values()).values() if count > 1)
        ),
    }
    return frame, audit


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pad-dir", type=Path, required=True)
    parser.add_argument("--msld-zip", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    pad = load_pad(args.pad_dir)
    msld, msld_audit = extract_unique_msld(
        args.msld_zip, args.output_dir / "msld_unique"
    )
    frame = split_patient_groups(pd.concat([pad, msld], ignore_index=True))

    manifest_path = args.output_dir / "manifest.jsonl"
    frame["image_path"] = frame["image_path"].astype(str)
    frame.to_json(manifest_path, orient="records", lines=True)

    labels = ["ACK", "BCC", "MEL", "NEV", "SCC", "SEK", "HEALTHY", OTHER_CLASS]
    audit = {
        "task": "eight-class educational skin-screening prototype",
        "class_order": labels,
        "split_method": "deterministic 6-fold patient-grouped test and 5-fold validation, split independently within PAD and MSLD",
        "patient_group_overlap": False,
        "msld": msld_audit,
        "splits": {},
        "warning": (
            "OTHER_SKIN_CONDITION represents only MSLD v2.0 mpox, chickenpox, "
            "measles, cowpox, and HFMD. It is not a general all-diseases class."
        ),
    }
    for split in ("train", "val", "test"):
        subset = frame[frame["split"] == split]
        audit["splits"][split] = {
            "images": int(len(subset)),
            "labels": dict(Counter(subset["label"])),
            "sources": dict(Counter(subset["source"])),
            "source_classes": dict(Counter(subset["source_class"])),
            "patients": int(subset["group_id"].nunique()),
        }
    (args.output_dir / "audit.json").write_text(
        json.dumps(audit, indent=2), encoding="utf-8"
    )
    print(f"Prepared {len(frame)} images at {manifest_path}")
    print(json.dumps(audit["splits"], indent=2))


if __name__ == "__main__":
    main()

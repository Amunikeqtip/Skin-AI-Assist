"""Add MILK10k clinical close-ups to the eight-class screening manifest.

Only `clinical: close-up` images are used; the paired dermoscopic images are a
different camera type from phone photos. Only diagnoses that match the six PAD
labels are kept. Cancer labels (BCC, MEL, SCC) also require histopathology.

The existing PAD/MSLD rows keep their original splits, so the old and new
models can be compared on the same PAD/MSLD test photos. MILK10k lists lesion
IDs but no patient IDs, so its split keeps each lesion in one split; one person
with several lesions can still appear in more than one split.

MILK10k is CC BY-NC 4.0. Cite: MILK study team. MILK10k. ISIC Archive, 2025,
doi:10.34970/648456.
"""

from __future__ import annotations

import argparse
import json
import zipfile
from collections import Counter
from pathlib import Path

import pandas as pd

from prepare_pad_screening import split_patient_groups

DIAGNOSIS_TO_LABEL = {
    "Basal cell carcinoma": "BCC",
    "Melanoma Invasive": "MEL",
    "Melanoma in situ": "MEL",
    "Squamous cell carcinoma, Invasive": "SCC",
    "Squamous cell carcinoma in situ": "SCC",
    "Solar or actinic keratosis": "ACK",
    "Nevus": "NEV",
    "Seborrheic keratosis": "SEK",
}
CANCER_LABELS = {"BCC", "MEL", "SCC"}


def load_milk(milk_dir: Path, image_dir: Path, audit: Counter, max_bcc: int | None) -> pd.DataFrame:
    metadata = pd.read_csv(milk_dir / "milk10k.csv")
    tones = pd.read_csv(milk_dir / "training_input.csv")[["isic_id", "skin_tone_class"]]
    metadata = metadata.merge(tones, on="isic_id", how="left")
    clinical = metadata[metadata["image_type"] == "clinical: close-up"].copy()
    audit["clinical_close_ups"] = int(len(clinical))

    clinical["label"] = clinical["diagnosis_3"].map(DIAGNOSIS_TO_LABEL)
    for diagnosis, count in clinical.loc[clinical["label"].isna(), "diagnosis_3"].fillna("missing").value_counts().items():
        audit[f"excluded_diagnosis:{diagnosis}"] += int(count)
    clinical = clinical.dropna(subset=["label"])

    unconfirmed = clinical["label"].isin(CANCER_LABELS) & (clinical["diagnosis_confirm_type"] != "histopathology")
    audit["excluded_cancer_without_histopathology"] = int(unconfirmed.sum())
    clinical = clinical[~unconfirmed]

    duplicated = clinical["lesion_id"].duplicated(keep="first")
    audit["excluded_second_close_up_same_lesion"] = int(duplicated.sum())
    clinical = clinical[~duplicated]

    bcc = clinical[clinical["label"] == "BCC"]
    if max_bcc is not None and len(bcc) > max_bcc:
        dropped = bcc.drop(bcc.sample(n=max_bcc, random_state=42).index).index
        audit["excluded_bcc_over_cap"] = int(len(dropped))
        clinical = clinical.drop(dropped)

    wanted = set(clinical["isic_id"])
    paths: dict[str, Path] = {}
    zip_path = milk_dir / "milk10k.zip"
    image_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as archive:
        for member in archive.namelist():
            stem = Path(member).stem
            if stem not in wanted or member.endswith("/"):
                continue
            target = image_dir / Path(member).name
            if not target.exists():
                target.write_bytes(archive.read(member))
            paths[stem] = target
    clinical["image_path"] = clinical["isic_id"].map(lambda key: str(paths[key]) if key in paths else None)
    audit["missing_image_file"] = int(clinical["image_path"].isna().sum())
    clinical = clinical.dropna(subset=["image_path"])

    clinical["source"] = "MILK10k"
    clinical["source_class"] = clinical["diagnosis_3"]
    clinical["stratify_label"] = "MILK_" + clinical["label"]
    clinical["group_id"] = "MILK_" + clinical["lesion_id"].astype(str)
    clinical["milk_skin_tone_class"] = clinical["skin_tone_class"]
    return clinical[
        ["image_path", "label", "source", "source_class", "stratify_label", "group_id", "milk_skin_tone_class"]
    ].reset_index(drop=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-manifest", type=Path, required=True)
    parser.add_argument("--milk-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument(
        "--max-bcc-lesions",
        type=int,
        default=600,
        help="Random (seed 42) cap on MILK10k BCC lesions; BCC already dominates PAD-UFES-20. Use 0 for no cap.",
    )
    args = parser.parse_args()

    base = pd.read_json(args.base_manifest, lines=True)
    audit: Counter = Counter()
    max_bcc = args.max_bcc_lesions or None
    milk = split_patient_groups(load_milk(args.milk_dir, args.output_dir / "milk10k_clinical", audit, max_bcc))
    frame = pd.concat([base, milk], ignore_index=True)
    if frame.groupby("group_id")["split"].nunique().max() != 1:
        raise RuntimeError("Group leakage detected across splits.")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    manifest = args.output_dir / "manifest.jsonl"
    frame.to_json(manifest, orient="records", lines=True)
    report = {
        "base_manifest": str(args.base_manifest),
        "base_splits_unchanged": True,
        "milk10k": {
            "license": "CC BY-NC 4.0; non-commercial use only",
            "citation": "MILK study team. MILK10k. ISIC Archive, 2025, doi:10.34970/648456.",
            "image_type": "clinical: close-up only",
            "group_key": "lesion_id; no patient id is published",
            "max_bcc_lesions": max_bcc,
            "filtering": dict(audit),
            "skin_tone_note": "milk_skin_tone_class is MILK10k's 0 (darkest) to 5 (lightest) scale, not Fitzpatrick.",
        },
        "splits": {},
    }
    for split in ("train", "val", "test"):
        subset = frame[frame["split"] == split]
        report["splits"][split] = {
            "images": int(len(subset)),
            "labels": dict(Counter(subset["label"])),
            "labels_by_source": {
                source: dict(Counter(part["label"])) for source, part in subset.groupby("source")
            },
        }
    (args.output_dir / "audit.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"Wrote {len(frame)} rows to {manifest}")
    print(json.dumps(report["splits"], indent=2))
    print(json.dumps(report["milk10k"]["filtering"], indent=2))


if __name__ == "__main__":
    main()

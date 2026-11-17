"""Validate an image-level skin-gate annotation manifest."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path

SKIN_LABELS = {"skin_present", "skin_absent", "ambiguous"}
QUALITY_LABELS = {"good", "blurry", "poor_lighting", "obstructed", "unknown"}
REVIEW_STATUSES = {"pending", "reviewed_agreement", "adjudicated"}
SPLITS = {"unassigned", "train", "val", "test"}
APPROVED_REVIEWS = {"reviewed_agreement", "adjudicated"}
REQUIRED_COLUMNS = {
    "image_id",
    "image_path",
    "source",
    "group_id",
    "capture_session_id",
    "skin_label",
    "quality_label",
    "review_status",
    "reviewer_count",
    "skin_tone_label",
    "skin_tone_method",
    "device_family",
    "body_area",
    "data_rights",
    "split",
    "sha256",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()

    manifest_path = args.manifest.resolve()
    if not manifest_path.is_file():
        raise SystemExit(f"Manifest not found: {manifest_path}")

    errors: list[str] = []
    warnings: list[str] = []
    rows: list[dict[str, str]] = []
    with manifest_path.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        columns = set(reader.fieldnames or [])
        missing_columns = sorted(REQUIRED_COLUMNS - columns)
        if missing_columns:
            raise SystemExit(
                "Manifest is missing columns: " + ", ".join(missing_columns)
            )
        rows = [
            {key: (value or "").strip() for key, value in row.items() if key}
            for row in reader
        ]

    if not rows:
        raise SystemExit("Manifest has a header but no image rows yet.")

    ids: dict[str, int] = {}
    hashes: dict[str, tuple[str, int]] = {}
    group_splits: dict[str, set[str]] = defaultdict(set)
    split_counts: Counter[str] = Counter()
    labels_by_split: dict[str, Counter[str]] = defaultdict(Counter)
    source_counts: Counter[str] = Counter()
    tone_counts: Counter[str] = Counter()
    device_counts: Counter[str] = Counter()
    quality_counts: Counter[str] = Counter()
    reviewed_count = 0

    for row_number, row in enumerate(rows, start=2):
        def value(column: str) -> str:
            return row.get(column, "")

        for column in ("image_id", "image_path", "source", "group_id", "data_rights"):
            if not value(column):
                errors.append(f"row {row_number}: {column} is required")

        image_id = value("image_id")
        if image_id:
            if image_id in ids:
                errors.append(
                    f"row {row_number}: duplicate image_id {image_id!r} "
                    f"(first used on row {ids[image_id]})"
                )
            else:
                ids[image_id] = row_number

        image_value = value("image_path")
        image_path = Path(image_value)
        if not image_path.is_absolute():
            image_path = manifest_path.parent / image_path
        if not image_path.is_file():
            errors.append(f"row {row_number}: image file not found: {image_path}")
        else:
            digest = sha256_file(image_path)
            supplied_hash = value("sha256").lower()
            if supplied_hash and supplied_hash != digest:
                errors.append(f"row {row_number}: supplied sha256 does not match file")
            if digest in hashes:
                previous_id, previous_row = hashes[digest]
                errors.append(
                    f"row {row_number}: exact duplicate image content matches "
                    f"{previous_id!r} on row {previous_row}"
                )
            else:
                hashes[digest] = (image_id or "?", row_number)

        label = value("skin_label")
        quality = value("quality_label")
        review = value("review_status")
        split = value("split")
        source = value("source") or "unknown"
        group_id = value("group_id")

        if label not in SKIN_LABELS:
            errors.append(
                f"row {row_number}: skin_label must be one of {sorted(SKIN_LABELS)}"
            )
        if quality not in QUALITY_LABELS:
            errors.append(
                f"row {row_number}: quality_label must be one of {sorted(QUALITY_LABELS)}"
            )
        if review not in REVIEW_STATUSES:
            errors.append(
                f"row {row_number}: review_status must be one of {sorted(REVIEW_STATUSES)}"
            )
        if split not in SPLITS:
            errors.append(f"row {row_number}: split must be one of {sorted(SPLITS)}")
        if not value("reviewer_count").isdigit():
            errors.append(f"row {row_number}: reviewer_count must be a whole number")
        if review == "pending" and split != "unassigned":
            errors.append(f"row {row_number}: pending labels must remain unassigned")
        if split in {"train", "val", "test"}:
            if review not in APPROVED_REVIEWS:
                errors.append(f"row {row_number}: assigned splits require reviewed labels")
            if quality != "good":
                errors.append(
                    f"row {row_number}: skin-gate splits require good-quality images; "
                    "evaluate image quality separately"
                )
            if label == "ambiguous" and split != "test":
                errors.append(
                    f"row {row_number}: ambiguous examples may be unassigned or test only"
                )
        if split != "unassigned" and source and group_id:
            group_splits[group_id].add(split)

        split_counts[split or "missing"] += 1
        labels_by_split[split or "missing"][label or "missing"] += 1
        source_counts[source] += 1
        tone_counts[value("skin_tone_label") or "unknown"] += 1
        device_counts[value("device_family") or "unknown"] += 1
        quality_counts[quality or "missing"] += 1
        if review in APPROVED_REVIEWS:
            reviewed_count += 1

    for group, splits in sorted(group_splits.items()):
        if len(splits) > 1:
            errors.append(
                f"group leakage: {group} appears in splits {sorted(splits)}"
            )

    if reviewed_count == 0:
        warnings.append("No independently reviewed/adjudicated images are present yet.")
    if not any(row.get("skin_label") == "skin_present" for row in rows):
        warnings.append("No skin_present images are present yet.")
    if not any(row.get("skin_label") == "skin_absent" for row in rows):
        warnings.append("No skin_absent images are present yet.")
    if not any(row.get("split") == "test" for row in rows):
        warnings.append("No frozen test split is assigned yet.")

    report = {
        "manifest": str(manifest_path),
        "rows": len(rows),
        "unique_image_ids": len(ids),
        "unique_sha256": len(hashes),
        "reviewed_rows": reviewed_count,
        "split_counts": dict(split_counts),
        "labels_by_split": {
            split: dict(counts) for split, counts in labels_by_split.items()
        },
        "source_counts": dict(source_counts),
        "skin_tone_counts": dict(tone_counts),
        "device_counts": dict(device_counts),
        "quality_counts": dict(quality_counts),
        "warnings": warnings,
        "errors": errors,
    }
    print(json.dumps(report, indent=2))
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2), encoding="utf-8")
    if errors:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

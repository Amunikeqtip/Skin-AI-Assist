"""Seed the skin-gate manifest from existing PAD-UFES/MSLD skin images.

These rows are source-derived positive examples only. They stay unassigned and
pending until a reviewer checks visibility and image quality. This does not
create or imply a non-skin evaluation set.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path

FIELDS = [
    "image_id",
    "image_path",
    "source",
    "source_label",
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
]
RIGHTS = {
    "PAD-UFES-20": (
        "CC BY 4.0 per the project's Hugging Face mirror; retain attribution "
        "and verify source terms before redistribution"
    ),
    "MSLD-v2.0": "CC BY-NC 4.0; non-commercial use only; retain attribution",
}


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    source_path = args.source_manifest.resolve()
    rows: list[dict[str, str]] = []
    seen_hashes: dict[str, str] = {}
    skipped_duplicates = 0
    with source_path.open("r", encoding="utf-8") as stream:
        for line_number, line in enumerate(stream, start=1):
            if not line.strip():
                continue
            item = json.loads(line)
            source = str(item.get("source", ""))
            if source not in RIGHTS:
                raise SystemExit(
                    f"Line {line_number}: unsupported source {source!r}; "
                    "add verified source rights before importing it."
                )
            image_path = Path(str(item.get("image_path", "")))
            if not image_path.is_file():
                raise SystemExit(f"Line {line_number}: missing image {image_path}")
            digest = file_sha256(image_path)
            if digest in seen_hashes:
                skipped_duplicates += 1
                continue
            seen_hashes[digest] = str(image_path)

            rows.append(
                {
                    "image_id": f"{source.lower().replace('-', '_')}_{digest[:16]}",
                    "image_path": str(image_path),
                    "source": source,
                    "source_label": str(item.get("source_class", "unknown")),
                    "group_id": str(item.get("group_id", "")),
                    "capture_session_id": "",
                    # PAD/MSLD images are skin-condition/healthy-skin source
                    # images; retain the label as pending visual QA.
                    "skin_label": "skin_present",
                    "quality_label": "unknown",
                    "review_status": "pending",
                    "reviewer_count": "0",
                    "skin_tone_label": "unknown",
                    "skin_tone_method": "",
                    "device_family": "unknown",
                    "body_area": "unknown",
                    "data_rights": RIGHTS[source],
                    "split": "unassigned",
                    "sha256": digest,
                }
            )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    print(
        json.dumps(
            {
                "output": str(args.output.resolve()),
                "rows_written": len(rows),
                "exact_duplicates_skipped": skipped_duplicates,
                "class_counts": {
                    source: sum(row["source"] == source for row in rows)
                    for source in sorted({row["source"] for row in rows})
                },
                "label_status": "source-derived skin_present; all rows pending visual QA",
                "split_status": "all unassigned",
                "warning": "No non-skin images are included by this importer.",
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()

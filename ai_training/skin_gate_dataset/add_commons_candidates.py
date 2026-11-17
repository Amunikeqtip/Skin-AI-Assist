"""Add curated Wikimedia Commons object photos as pending negative candidates."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from pathlib import Path
from urllib.request import Request, urlopen

MANIFEST_FIELDS = [
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


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--image-dir", type=Path, required=True)
    parser.add_argument(
        "--sources",
        type=Path,
        default=Path(__file__).with_name("commons_seed_sources.json"),
    )
    parser.add_argument("--attribution-output", type=Path, required=True)
    args = parser.parse_args()

    manifest_path = args.manifest.resolve()
    image_dir = args.image_dir.resolve()
    image_dir.mkdir(parents=True, exist_ok=True)
    with manifest_path.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        existing_fields = list(reader.fieldnames or [])
        missing = set(MANIFEST_FIELDS) - set(existing_fields)
        if missing:
            raise SystemExit(f"Manifest missing columns: {sorted(missing)}")
        rows = [dict(row) for row in reader]

    known_ids = {row.get("image_id", "") for row in rows}
    known_hashes = {row.get("sha256", "") for row in rows if row.get("sha256")}
    sources = json.loads(args.sources.read_text(encoding="utf-8"))
    added: list[dict[str, str]] = []
    skipped: list[str] = []
    attribution_rows: list[dict[str, str]] = []

    for item in sources:
        destination = image_dir / item["filename"]
        if not destination.is_file():
            request = Request(
                item["thumbnail_url"],
                headers={"User-Agent": "SkinAI-Assist-Prototyping/1.0 (dataset curation)"},
            )
            with urlopen(request, timeout=60) as response:
                destination.write_bytes(response.read())

        digest = sha256_file(destination)
        image_id = f"commons_{digest[:16]}"
        if image_id in known_ids or digest in known_hashes:
            skipped.append(item["filename"])
            continue

        rights = (
            f"{item['license']}; author: {item['author']}; source: {item['page_url']}; "
            "Wikimedia thumbnail (max 1280 px), no further edits; retain license attribution"
        )
        added.append(
            {
                "image_id": image_id,
                "image_path": str(destination),
                "source": "Wikimedia Commons",
                "source_label": item["candidate_type"],
                "group_id": f"WMC_{slug(item['filename'])}",
                "capture_session_id": "",
                "skin_label": "skin_absent",
                "quality_label": "unknown",
                "review_status": "pending",
                "reviewer_count": "0",
                "skin_tone_label": "unknown",
                "skin_tone_method": "",
                "device_family": "unknown",
                "body_area": "not_applicable",
                "data_rights": rights,
                "split": "unassigned",
                "sha256": digest,
            }
        )
        known_ids.add(image_id)
        known_hashes.add(digest)
        attribution_rows.append(
            {
                "local_filename": item["filename"],
                "source_title": item["source_title"],
                "author": item["author"],
                "license": item["license"],
                "license_url": item["license_url"],
                "source_page": item["page_url"],
                "downloaded_thumbnail": item["thumbnail_url"],
                "changes": "Wikimedia thumbnail, max 1280 px; no further edits",
            }
        )

    if added:
        rows.extend(added)
        with manifest_path.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=MANIFEST_FIELDS)
            writer.writeheader()
            writer.writerows(rows)

    args.attribution_output.parent.mkdir(parents=True, exist_ok=True)
    if attribution_rows:
        with args.attribution_output.open("a", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(
                stream,
                fieldnames=list(attribution_rows[0]),
            )
            if stream.tell() == 0:
                writer.writeheader()
            writer.writerows(attribution_rows)

    print(
        json.dumps(
            {
                "added_candidates": len(added),
                "skipped_existing": skipped,
                "manifest_rows": len(rows),
                "all_candidates_pending_review": True,
                "candidate_skins_absent_count": len(added),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()

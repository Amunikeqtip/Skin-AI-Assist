"""Report image-level skin-gate errors and subgroup metrics."""

from __future__ import annotations

import argparse
import csv
import json
import math
from collections import Counter, defaultdict
from pathlib import Path

TRUTH_LABELS = {"skin_present", "skin_absent", "ambiguous"}
PREDICTION_LABELS = {"skin_present", "skin_absent", "uncertain"}
REQUIRED_COLUMNS = {
    "image_id",
    "group_id",
    "source",
    "ground_truth",
    "prediction",
    "skin_score",
    "threshold",
    "split",
    "skin_tone_label",
    "device_family",
}


def rate_with_wilson(successes: int, total: int) -> dict[str, float | int | None]:
    if total == 0:
        return {"rate": None, "successes": successes, "total": total, "ci95": None}
    z = 1.959963984540054
    rate = successes / total
    denominator = 1 + z * z / total
    center = (rate + z * z / (2 * total)) / denominator
    half_width = (
        z
        * math.sqrt(rate * (1 - rate) / total + z * z / (4 * total * total))
        / denominator
    )
    return {
        "rate": rate,
        "successes": successes,
        "total": total,
        "ci95": [max(0.0, center - half_width), min(1.0, center + half_width)],
    }


def summarize(rows: list[dict[str, str]]) -> dict[str, object]:
    binary_truth = [
        row for row in rows if row["ground_truth"] in {"skin_present", "skin_absent"}
    ]
    positives = [row for row in binary_truth if row["ground_truth"] == "skin_present"]
    negatives = [row for row in binary_truth if row["ground_truth"] == "skin_absent"]
    decided = [row for row in binary_truth if row["prediction"] != "uncertain"]

    false_accepts = sum(row["prediction"] == "skin_present" for row in negatives)
    false_rejects = sum(row["prediction"] == "skin_absent" for row in positives)
    positive_abstentions = sum(row["prediction"] == "uncertain" for row in positives)
    negative_abstentions = sum(row["prediction"] == "uncertain" for row in negatives)
    detected_skin = sum(row["prediction"] == "skin_present" for row in positives)
    skin_not_passed = len(positives) - detected_skin
    correctly_rejected_non_skin = sum(
        row["prediction"] == "skin_absent" for row in negatives
    )
    correct_decisions = sum(
        row["ground_truth"] == row["prediction"] for row in decided
    )

    ambiguous = [row for row in rows if row["ground_truth"] == "ambiguous"]
    ambiguous_predictions = Counter(row["prediction"] for row in ambiguous)
    return {
        "images": len(rows),
        "unique_groups": len({row["group_id"] for row in rows if row["group_id"]}),
        "binary_labeled_images": len(binary_truth),
        "ambiguous_truth_images": len(ambiguous),
        "ambiguous_truth_predictions": dict(ambiguous_predictions),
        "skin_present_support": len(positives),
        "skin_absent_support": len(negatives),
        "false_accept_rate": rate_with_wilson(false_accepts, len(negatives)),
        "false_reject_rate": rate_with_wilson(false_rejects, len(positives)),
        "positive_abstention_rate": rate_with_wilson(
            positive_abstentions, len(positives)
        ),
        "negative_abstention_rate": rate_with_wilson(
            negative_abstentions, len(negatives)
        ),
        "skin_detection_sensitivity": rate_with_wilson(
            detected_skin, len(positives)
        ),
        "skin_not_passed_rate_including_abstentions": rate_with_wilson(
            skin_not_passed, len(positives)
        ),
        "non_skin_specificity": rate_with_wilson(
            correctly_rejected_non_skin, len(negatives)
        ),
        "decision_coverage": rate_with_wilson(len(decided), len(binary_truth)),
        "accuracy_when_decided": rate_with_wilson(
            correct_decisions, len(decided)
        ),
        "interpretation": (
            "False-accept rate counts non-skin images predicted skin_present. "
            "False-reject rate counts skin images predicted skin_absent; "
            "abstentions are reported separately. Sensitivity counts only "
            "skin_present predictions. Ambiguous ground truth is excluded from "
            "binary rates and reported separately."
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--predictions", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    prediction_path = args.predictions.resolve()
    with prediction_path.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        missing = sorted(REQUIRED_COLUMNS - set(reader.fieldnames or []))
        if missing:
            raise SystemExit("Missing prediction columns: " + ", ".join(missing))
        rows = [
            {key: (value or "").strip() for key, value in row.items() if key}
            for row in reader
        ]

    if not rows:
        raise SystemExit("Prediction file contains no rows.")

    errors: list[str] = []
    image_ids: set[str] = set()
    for row_number, row in enumerate(rows, start=2):
        if row["split"] != "test":
            errors.append(f"row {row_number}: evaluation accepts test rows only")
        if row["ground_truth"] not in TRUTH_LABELS:
            errors.append(f"row {row_number}: invalid ground_truth")
        if row["prediction"] not in PREDICTION_LABELS:
            errors.append(f"row {row_number}: invalid prediction")
        if not row["image_id"]:
            errors.append(f"row {row_number}: image_id is required")
        elif row["image_id"] in image_ids:
            errors.append(f"row {row_number}: duplicate image_id {row['image_id']!r}")
        image_ids.add(row["image_id"])

    if errors:
        raise SystemExit("\n".join(errors))

    overall = summarize(rows)
    subgroup_metrics: dict[str, dict[str, object]] = {}
    for column in ("source", "skin_tone_label", "device_family"):
        groups: dict[str, list[dict[str, str]]] = defaultdict(list)
        for row in rows:
            groups[row[column] or "unknown"].append(row)
        subgroup_metrics[column] = {
            key: summarize(group_rows)
            for key, group_rows in sorted(groups.items())
        }

    result = {
        "evaluation_set": str(prediction_path),
        "split": "test",
        "overall": overall,
        "subgroups": subgroup_metrics,
        "warning": (
            "Metrics describe this test sample only. Review confidence intervals "
            "and subgroup denominators; this is not clinical validation."
        ),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()

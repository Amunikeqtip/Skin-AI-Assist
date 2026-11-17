"""Validation-only confidence cutoff for the eight-class screening model.

Stage `sweep` scores the validation split only. It fits a temperature and writes
a coverage/accuracy/missed-cancer table with `validated: false`.

Stage `freeze` takes the cutoff you chose from that table, scores the test
split once, and writes the frozen policy. It refuses to run a second time, so
the cutoff cannot be re-picked after looking at test results.

Stage `report` scores the test split by source with no cutoff, for comparing
two models on the same test photos.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import numpy as np
import pandas as pd
import tensorflow as tf
from sklearn.metrics import classification_report, f1_score

from screening_metrics import (
    apply_temperature,
    cancer_referral_report,
    confidence_sweep,
    fit_temperature,
)
from train_pad_screening import CLASS_NAMES, load_manifest, make_dataset


def predict(model: tf.keras.Model, frame: pd.DataFrame) -> tuple[np.ndarray, np.ndarray]:
    dataset = make_dataset(frame, training=False, batch_size=32)
    probabilities = model.predict(dataset, verbose=1)
    truth = np.concatenate([labels.numpy() for _, labels in dataset])
    return probabilities, truth


def sweep(args: argparse.Namespace) -> None:
    frame = load_manifest(args.manifest)
    val = frame[frame["split"] == "val"].reset_index(drop=True)
    model = tf.keras.models.load_model(args.model)
    probabilities, truth = predict(model, val)
    temperature = fit_temperature(probabilities, truth)
    scaled = apply_temperature(probabilities, temperature)
    output = {
        "split_scored": "val",
        "validation_images": int(len(val)),
        "temperature": temperature,
        "validated": False,
        "minimum_confidence": None,
        "validation_accuracy_no_cutoff": float(np.mean(scaled.argmax(axis=1) == truth)),
        "validation_missed_cancers_no_cutoff": cancer_referral_report(truth, scaled.argmax(axis=1), CLASS_NAMES),
        "validation_sweep": confidence_sweep(scaled, truth, CLASS_NAMES),
        "selection_rule": (
            "Choose one minimum_confidence from validation_sweep, then run the freeze "
            "stage once. Do not choose it from test results."
        ),
    }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "validation_sweep.json").write_text(json.dumps(output, indent=2), encoding="utf-8")
    print(json.dumps({key: output[key] for key in ("temperature", "validation_accuracy_no_cutoff")}, indent=2))
    for row in output["validation_sweep"]:
        print(row)


def freeze(args: argparse.Namespace) -> None:
    candidate_path = args.output_dir / "validation_sweep.json"
    policy_path = args.output_dir / "uncertainty_policy.json"
    if policy_path.exists():
        raise RuntimeError(f"{policy_path} already exists. The test split has been scored once.")
    candidate = json.loads(candidate_path.read_text(encoding="utf-8"))
    thresholds = [row["minimum_confidence"] for row in candidate["validation_sweep"]]
    if args.minimum_confidence not in thresholds:
        raise ValueError(f"Choose a cutoff from the validation sweep: {thresholds}")

    frame = load_manifest(args.manifest)
    test = frame[frame["split"] == "test"].reset_index(drop=True)
    model = tf.keras.models.load_model(args.model)
    probabilities, truth = predict(model, test)
    scaled = apply_temperature(probabilities, candidate["temperature"])
    predicted = scaled.argmax(axis=1)
    labeled = scaled.max(axis=1) >= args.minimum_confidence
    labels = list(range(len(CLASS_NAMES)))
    policy = {
        "model_asset": args.model_asset,
        "temperature": candidate["temperature"],
        "minimum_confidence": args.minimum_confidence,
        "validated": True,
        "chosen_from": "validation_sweep.json",
        "test_images": int(len(test)),
        "test_without_cutoff": {
            "accuracy": float(np.mean(predicted == truth)),
            "macro_f1": float(f1_score(truth, predicted, labels=labels, average="macro", zero_division=0)),
            "missed_cancers": cancer_referral_report(truth, predicted, CLASS_NAMES),
        },
        "test_with_cutoff": {
            "photos_labeled": int(labeled.sum()),
            "photos_withheld_uncertain": int((~labeled).sum()),
            "coverage": float(labeled.mean()),
            "accuracy_when_labeled": float(np.mean(predicted[labeled] == truth[labeled])) if labeled.any() else None,
            "classification_report_when_labeled": classification_report(
                truth[labeled],
                predicted[labeled],
                labels=labels,
                target_names=CLASS_NAMES,
                output_dict=True,
                zero_division=0,
            ),
            "missed_cancers": cancer_referral_report(truth, predicted, CLASS_NAMES, labeled),
        },
        "note": (
            "Scores are temperature-scaled softmax values, not medical probabilities. "
            "An uncertain result or a non-cancer label does not rule out cancer."
        ),
    }
    policy_path.write_text(json.dumps(policy, indent=2), encoding="utf-8")
    print(json.dumps({key: policy[key] for key in ("temperature", "minimum_confidence")}, indent=2))
    print(json.dumps(policy["test_without_cutoff"]["missed_cancers"]["all_cancers"], indent=2))
    print(json.dumps({k: v for k, v in policy["test_with_cutoff"].items() if k != "classification_report_when_labeled"}, indent=2))


def report(args: argparse.Namespace) -> None:
    """Score a model on the test split by source, with no cutoff."""
    frame = load_manifest(args.manifest)
    test = frame[frame["split"] == "test"].reset_index(drop=True)
    model = tf.keras.models.load_model(args.model)
    probabilities, truth = predict(model, test)
    predicted = probabilities.argmax(axis=1)
    sources = test["source"].to_numpy()
    output = {"model": str(args.model), "manifest": str(args.manifest), "by_source": {}}
    for source in sorted(set(sources)):
        mask = sources == source
        output["by_source"][source] = {
            "images": int(mask.sum()),
            "accuracy": float(np.mean(predicted[mask] == truth[mask])),
            "missed_cancers": cancer_referral_report(truth[mask], predicted[mask], CLASS_NAMES),
        }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    path = args.output_dir / f"test_report_{Path(args.model).stem}.json"
    path.write_text(json.dumps(output, indent=2), encoding="utf-8")
    for source, values in output["by_source"].items():
        print(source, values["images"], round(values["accuracy"], 4), values["missed_cancers"]["all_cancers"])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("sweep", "freeze", "report"))
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--minimum-confidence", type=float)
    parser.add_argument(
        "--model-asset",
        default="assets/models/skinai_pad_msld_8class.tflite",
        help="App asset path the frozen policy applies to; the app ignores a policy for any other model.",
    )
    args = parser.parse_args()
    if args.stage == "sweep":
        sweep(args)
    elif args.stage == "report":
        report(args)
    else:
        if args.minimum_confidence is None:
            raise ValueError("--minimum-confidence is required for freeze.")
        freeze(args)


if __name__ == "__main__":
    main()

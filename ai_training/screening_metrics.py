"""Shared metrics for the eight-class screening prototype.

These functions use NumPy only so the training and evaluation scripts report
missed cancers, temperature, and the confidence sweep the same way.
"""

from __future__ import annotations

import numpy as np

CANCER_CLASSES = ("BCC", "MEL", "SCC")
PRECANCER_CLASSES = ("ACK",)


def outcome_group(label: str) -> str:
    if label in CANCER_CLASSES:
        return "cancer_label"
    if label in PRECANCER_CLASSES:
        return "actinic_keratosis_label"
    return "non_cancer_label"


def cancer_referral_report(
    truth: np.ndarray,
    predicted: np.ndarray,
    class_names: list[str],
    labeled: np.ndarray | None = None,
) -> dict[str, object]:
    """Count where true cancer photos went.

    `labeled` marks photos that received a label; the rest were withheld as
    uncertain. Without it, every photo is treated as labeled.
    """
    if labeled is None:
        labeled = np.ones(len(truth), dtype=bool)
    report: dict[str, object] = {}
    totals = {"photos": 0, "cancer_label": 0, "actinic_keratosis_label": 0, "non_cancer_label": 0, "withheld_uncertain": 0}
    for name in CANCER_CLASSES:
        index = class_names.index(name)
        rows = truth == index
        counts = {"photos": int(rows.sum()), "cancer_label": 0, "actinic_keratosis_label": 0, "non_cancer_label": 0, "withheld_uncertain": 0}
        for row in np.flatnonzero(rows):
            if not labeled[row]:
                counts["withheld_uncertain"] += 1
            else:
                counts[outcome_group(class_names[int(predicted[row])])] += 1
        report[name] = counts
        for key, value in counts.items():
            totals[key] += value
    report["all_cancers"] = totals
    report["definition"] = (
        "Rows are true BCC, MEL, and SCC photos. non_cancer_label means NEV, SEK, "
        "HEALTHY, or OTHER_SKIN_CONDITION; those are the misses that could falsely "
        "reassure. actinic_keratosis_label is counted separately."
    )
    return report


def apply_temperature(probabilities: np.ndarray, temperature: float) -> np.ndarray:
    logits = np.log(np.clip(probabilities, 1e-12, 1.0)) / temperature
    logits -= logits.max(axis=1, keepdims=True)
    scaled = np.exp(logits)
    return scaled / scaled.sum(axis=1, keepdims=True)


def fit_temperature(probabilities: np.ndarray, truth: np.ndarray) -> float:
    """Pick the temperature with the lowest validation negative log-likelihood."""
    best_temperature, best_nll = 1.0, float("inf")
    for temperature in np.round(np.arange(0.5, 5.001, 0.01), 2):
        scaled = apply_temperature(probabilities, float(temperature))
        nll = float(-np.mean(np.log(np.clip(scaled[np.arange(len(truth)), truth], 1e-12, 1.0))))
        if nll < best_nll:
            best_temperature, best_nll = float(temperature), nll
    return best_temperature


def confidence_sweep(
    probabilities: np.ndarray, truth: np.ndarray, class_names: list[str]
) -> list[dict[str, object]]:
    confidence = probabilities.max(axis=1)
    predicted = probabilities.argmax(axis=1)
    rows: list[dict[str, object]] = []
    for threshold in np.round(np.arange(0.30, 0.901, 0.05), 2):
        labeled = confidence >= threshold
        accuracy = float(np.mean(predicted[labeled] == truth[labeled])) if labeled.any() else None
        cancers = cancer_referral_report(truth, predicted, class_names, labeled)["all_cancers"]
        rows.append(
            {
                "minimum_confidence": float(threshold),
                "photos_labeled": int(labeled.sum()),
                "photos_total": int(len(truth)),
                "coverage": float(labeled.mean()),
                "accuracy_when_labeled": accuracy,
                "cancer_photos_labeled_non_cancer": cancers["non_cancer_label"],
                "cancer_photos_withheld_uncertain": cancers["withheld_uncertain"],
                "cancer_photos_total": cancers["photos"],
            }
        )
    return rows

"""Train an experimental per-pixel skin-colour gate from UCI Skin Segmentation.

This is a colour-pixel classifier, not a spatial image model. Pixel-level
metrics do not establish reliable image-level skin/no-skin detection.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import tensorflow as tf
from sklearn.metrics import classification_report, roc_auc_score
from sklearn.model_selection import train_test_split

SEED = 42


def make_model() -> tf.keras.Model:
    model = tf.keras.Sequential(
        [
            tf.keras.Input(shape=(3,), name="bgr_pixel_0_1"),
            tf.keras.layers.Dense(32, activation="relu"),
            tf.keras.layers.Dense(16, activation="relu"),
            tf.keras.layers.Dense(1, activation="sigmoid", name="skin_score"),
        ],
        name="skin_pixel_gate",
    )
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=1e-3),
        loss="binary_crossentropy",
        metrics=[tf.keras.metrics.BinaryAccuracy(name="accuracy")],
    )
    return model


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--epochs", type=int, default=30)
    args = parser.parse_args()

    rows = np.loadtxt(args.data, dtype=np.float32)
    if rows.ndim != 2 or rows.shape[1] != 4:
        raise ValueError("Expected four columns: B, G, R, and class.")

    # UCI labels are 1=skin and 2=non-skin. The input order is BGR.
    features = rows[:, :3] / 255.0
    labels = (rows[:, 3] == 1).astype(np.float32)
    x_train_val, x_test, y_train_val, y_test = train_test_split(
        features,
        labels,
        test_size=0.15,
        random_state=SEED,
        stratify=labels,
    )
    x_train, x_val, y_train, y_val = train_test_split(
        x_train_val,
        y_train_val,
        test_size=0.1764705882,
        random_state=SEED + 1,
        stratify=y_train_val,
    )

    class_counts = np.bincount(y_train.astype(np.int32), minlength=2)
    class_weight = {
        index: len(y_train) / (2 * int(count))
        for index, count in enumerate(class_counts)
    }

    model = make_model()
    model.fit(
        x_train,
        y_train,
        validation_data=(x_val, y_val),
        epochs=args.epochs,
        batch_size=1024,
        class_weight=class_weight,
        callbacks=[
            tf.keras.callbacks.EarlyStopping(
                monitor="val_loss",
                patience=4,
                restore_best_weights=True,
            )
        ],
        verbose=2,
    )

    probabilities = model.predict(x_test, batch_size=4096, verbose=0).reshape(-1)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    tflite_path = args.output_dir / "skin_pixel_gate.tflite"
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_path.write_bytes(converter.convert())

    report = {
        "model": "3-layer per-pixel BGR colour classifier",
        "dataset": "UCI Skin Segmentation (Bhatt and Dhall, 2009)",
        "license": "CC BY 4.0",
        "input_order": "BGR normalized to [0, 1]",
        "split": "random pixel rows; source-image/patient identifiers are unavailable",
        "instances": int(len(rows)),
        "skin_pixels": int(labels.sum()),
        "non_skin_pixels": int(len(labels) - labels.sum()),
        "test_pixels": int(len(y_test)),
        "pixel_roc_auc": float(roc_auc_score(y_test, probabilities)),
        "threshold_reports": {
            str(threshold): classification_report(
                y_test,
                probabilities >= threshold,
                labels=[0, 1],
                target_names=["non_skin", "skin"],
                output_dict=True,
                zero_division=0,
            )
            for threshold in (0.25, 0.5, 0.75)
        },
        "limitations": [
            "This model sees only BGR pixel values and has no spatial context.",
            "Random pixel splits may share source-image colour distributions.",
            "Pixel metrics do not validate whole-image skin detection.",
            "Wood, fabric, lighting, camera white balance, and darker tones may cause errors.",
            "An image-level skin-fraction threshold requires a separate image-level validation set.",
        ],
        "tflite_model": tflite_path.name,
    }
    (args.output_dir / "skin_pixel_gate_evaluation.json").write_text(
        json.dumps(report, indent=2), encoding="utf-8"
    )
    print(f"Saved model: {tflite_path}")
    print(f"Pixel ROC AUC: {report['pixel_roc_auc']:.4f}")


if __name__ == "__main__":
    main()

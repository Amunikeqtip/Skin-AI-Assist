"""Train an image-only PAD + MSLD eight-class screening prototype."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import numpy as np
import pandas as pd
import tensorflow as tf
from sklearn.metrics import classification_report, confusion_matrix, f1_score

from screening_metrics import cancer_referral_report

IMAGE_SIZE = (224, 224)
SEED = 42
CLASS_NAMES = [
    "ACK",
    "BCC",
    "MEL",
    "NEV",
    "SCC",
    "SEK",
    "HEALTHY",
    "OTHER_SKIN_CONDITION",
]


def load_manifest(path: Path) -> pd.DataFrame:
    frame = pd.read_json(path, lines=True)
    required = {"image_path", "label", "split", "group_id", "source", "source_class"}
    missing = required.difference(frame.columns)
    if missing:
        raise ValueError(f"Manifest is missing columns: {sorted(missing)}")
    if set(frame["label"].unique()) != set(CLASS_NAMES):
        raise ValueError("Manifest classes do not match the eight-class model contract.")
    if frame.groupby("group_id")["split"].nunique().max() != 1:
        raise ValueError("Patient/group leakage detected across splits.")
    missing_images = [path for path in frame["image_path"] if not Path(path).is_file()]
    if missing_images:
        raise FileNotFoundError(f"Manifest image is missing: {missing_images[0]}")
    return frame


def make_dataset(frame: pd.DataFrame, training: bool, batch_size: int) -> tf.data.Dataset:
    class_to_index = {name: index for index, name in enumerate(CLASS_NAMES)}
    paths = frame["image_path"].astype(str).to_numpy()
    labels = frame["label"].map(class_to_index).to_numpy(dtype=np.int32)

    if training:
        counts = frame["label"].value_counts()
        weights = frame["label"].map(
            lambda label: len(frame) / (len(CLASS_NAMES) * int(counts[label]))
        ).to_numpy(dtype=np.float32)
        dataset = tf.data.Dataset.from_tensor_slices((paths, labels, weights))

        def load_training(path, label, weight):
            image = _decode_resize(path)
            return image, label, weight

        dataset = dataset.shuffle(
            len(frame), seed=SEED, reshuffle_each_iteration=True
        )
        dataset = dataset.map(load_training, num_parallel_calls=tf.data.AUTOTUNE)
    else:
        dataset = tf.data.Dataset.from_tensor_slices((paths, labels))
        dataset = dataset.map(
            lambda path, label: (_decode_resize(path), label),
            num_parallel_calls=tf.data.AUTOTUNE,
        )

    return dataset.batch(batch_size).prefetch(tf.data.AUTOTUNE)


def _decode_resize(path: tf.Tensor) -> tf.Tensor:
    image = tf.io.read_file(path)
    image = tf.io.decode_image(image, channels=3, expand_animations=False)
    image.set_shape([None, None, 3])
    return tf.image.resize(image, IMAGE_SIZE, antialias=True)


def build_model() -> tuple[tf.keras.Model, tf.keras.Model]:
    inputs = tf.keras.Input(shape=(*IMAGE_SIZE, 3), dtype=tf.float32, name="image")
    augment = tf.keras.Sequential(
        [
            tf.keras.layers.RandomFlip("horizontal"),
            tf.keras.layers.RandomRotation(0.04),
            tf.keras.layers.RandomZoom(0.08),
        ],
        name="training_augmentation",
    )
    backbone = tf.keras.applications.MobileNetV3Large(
        input_shape=(*IMAGE_SIZE, 3),
        include_top=False,
        weights="imagenet",
        include_preprocessing=True,
    )
    backbone.trainable = False
    features = backbone(augment(inputs), training=False)
    features = tf.keras.layers.GlobalAveragePooling2D()(features)
    features = tf.keras.layers.Dropout(0.3)(features)
    outputs = tf.keras.layers.Dense(
        len(CLASS_NAMES), activation="softmax", name="scores"
    )(features)
    model = tf.keras.Model(inputs, outputs, name="skinai_pad_msld_screening")
    return model, backbone


def training_callbacks(validation_data: tf.data.Dataset) -> list[tf.keras.callbacks.Callback]:
    return [
        MacroF1Callback(validation_data),
        tf.keras.callbacks.EarlyStopping(
            monitor="val_macro_f1",
            mode="max",
            patience=4,
            restore_best_weights=True,
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor="val_macro_f1",
            mode="max",
            factor=0.3,
            patience=2,
            min_lr=1e-6,
        ),
    ]


class MacroF1Callback(tf.keras.callbacks.Callback):
    def __init__(self, validation_data: tf.data.Dataset):
        super().__init__()
        self.validation_data = validation_data

    def on_epoch_end(self, epoch: int, logs: dict | None = None) -> None:
        if logs is None:
            return
        probabilities = self.model.predict(self.validation_data, verbose=0)
        truth = np.concatenate([labels.numpy() for _, labels in self.validation_data])
        logs["val_macro_f1"] = f1_score(
            truth,
            probabilities.argmax(axis=1),
            labels=list(range(len(CLASS_NAMES))),
            average="macro",
            zero_division=0,
        )
        print(f" - val_macro_f1: {logs['val_macro_f1']:.4f}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--epochs", type=int, default=12)
    parser.add_argument("--batch-size", type=int, default=24)
    args = parser.parse_args()

    frame = load_manifest(args.manifest)
    train = frame[frame["split"] == "train"].reset_index(drop=True)
    val = frame[frame["split"] == "val"].reset_index(drop=True)
    test = frame[frame["split"] == "test"].reset_index(drop=True)
    if min(len(train), len(val), len(test)) == 0:
        raise ValueError("Train, validation, and test splits must all be non-empty.")

    train_data = make_dataset(train, training=True, batch_size=args.batch_size)
    val_data = make_dataset(val, training=False, batch_size=args.batch_size)
    test_data = make_dataset(test, training=False, batch_size=args.batch_size)
    model, backbone = build_model()
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=1e-3),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    model.fit(
        train_data,
        validation_data=val_data,
        epochs=args.epochs,
        verbose=2,
        callbacks=training_callbacks(val_data),
    )

    backbone.trainable = True
    for layer in backbone.layers[:-30]:
        layer.trainable = False
    for layer in backbone.layers:
        if isinstance(layer, tf.keras.layers.BatchNormalization):
            layer.trainable = False
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=1e-5),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    model.fit(
        train_data,
        validation_data=val_data,
        epochs=max(2, args.epochs // 3),
        verbose=2,
        callbacks=training_callbacks(val_data),
    )

    args.output_dir.mkdir(parents=True, exist_ok=True)
    model_path = args.output_dir / "skinai_pad_msld_8class.keras"
    tflite_path = args.output_dir / "skinai_pad_msld_8class.tflite"
    model.save(model_path)
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_path.write_bytes(converter.convert())

    probabilities = model.predict(test_data, verbose=1)
    truth = np.concatenate([labels.numpy() for _, labels in test_data])
    predictions = probabilities.argmax(axis=1)
    report = classification_report(
        truth,
        predictions,
        labels=list(range(len(CLASS_NAMES))),
        target_names=CLASS_NAMES,
        output_dict=True,
        zero_division=0,
    )
    evaluation = {
        "architecture": "MobileNetV3-Large image-only",
        "datasets": sorted(frame["source"].unique().tolist()),
        "msld_license": "CC BY-NC 4.0; non-commercial use only",
        "class_names": CLASS_NAMES,
        "other_class_scope": ["MKP", "CHP", "MSL", "CWP", "HFMD"],
        "split": "patient-grouped train/validation/test; duplicates across MSLD folds deduplicated by filename",
        "train_images": len(train),
        "validation_images": len(val),
        "test_images": len(test),
        "test_by_source_class": {
            source_class: int(count)
            for source_class, count in test["source_class"].value_counts().items()
        },
        "test_classification_report": report,
        "test_confusion_matrix": confusion_matrix(
            truth, predictions, labels=list(range(len(CLASS_NAMES)))
        ).tolist(),
        "test_missed_cancers": cancer_referral_report(truth, predictions, CLASS_NAMES),
        "test_by_source": {
            source: {
                "images": int(mask.sum()),
                "accuracy": float(np.mean(predictions[mask] == truth[mask])),
                "macro_f1_over_present_labels": float(
                    f1_score(truth[mask], predictions[mask], average="macro", zero_division=0)
                ),
                "missed_cancers": cancer_referral_report(truth[mask], predictions[mask], CLASS_NAMES)["all_cancers"],
            }
            for source in sorted(test["source"].unique())
            for mask in [test["source"].to_numpy() == source]
        },
        "limitations": [
            "HEALTHY has only 114 MSLD source images before splitting.",
            "OTHER_SKIN_CONDITION covers only five MSLD infectious conditions, not all other diseases.",
            "PAD and MSLD have different image domains and demographic coverage.",
            "This research prototype is not clinically validated.",
        ],
    }
    (args.output_dir / "evaluation.json").write_text(
        json.dumps(evaluation, indent=2), encoding="utf-8"
    )
    (args.output_dir / "labels.json").write_text(
        json.dumps(CLASS_NAMES, indent=2), encoding="utf-8"
    )
    print(f"Saved model: {tflite_path}")
    print(f"Saved evaluation: {args.output_dir / 'evaluation.json'}")


if __name__ == "__main__":
    main()

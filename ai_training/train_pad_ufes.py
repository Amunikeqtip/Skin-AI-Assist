"""Fine-tune MobileNetV3-Large on PAD-UFES-20 and export a TFLite model.

Expected dataset layout (the Hugging Face PAD-UFES-20 mirror):
    data_dir/
      metadata.csv
      all_images/...

Splits are grouped by patient_id to prevent images from one patient appearing
in both training and evaluation. This script is for an educational prototype,
not for clinical use.
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
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.metrics import classification_report, confusion_matrix, f1_score


CLASS_NAMES = ["ACK", "BCC", "MEL", "NEV", "SCC", "SEK"]
IMAGE_SIZE = (224, 224)
SEED = 42


def split_by_patient(frame: pd.DataFrame) -> tuple[pd.DataFrame, ...]:
    """Create deterministic, approximately 70/15/15 stratified patient splits."""
    outer = StratifiedGroupKFold(n_splits=6, shuffle=True, random_state=SEED)
    train_val_idx, test_idx = next(
        outer.split(frame, frame["diagnostic"], groups=frame["patient_id"])
    )
    train_val = frame.iloc[train_val_idx].reset_index(drop=True)
    test = frame.iloc[test_idx].reset_index(drop=True)

    inner = StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=SEED + 1)
    train_idx, val_idx = next(
        inner.split(
            train_val,
            train_val["diagnostic"],
            groups=train_val["patient_id"],
        )
    )
    return (
        train_val.iloc[train_idx].reset_index(drop=True),
        train_val.iloc[val_idx].reset_index(drop=True),
        test,
    )


def balance_training_frame(frame: pd.DataFrame) -> pd.DataFrame:
    """Moderately oversample rare diagnoses without altering held-out data."""
    target_per_class = min(320, int(frame["diagnostic"].value_counts().max()))
    balanced = [
        class_frame.sample(
            n=target_per_class,
            replace=len(class_frame) < target_per_class,
            random_state=SEED + index,
        )
        for index, (_, class_frame) in enumerate(
            frame.groupby("diagnostic", sort=True)
        )
    ]
    return (
        pd.concat(balanced, ignore_index=True)
        .sample(frac=1, random_state=SEED)
        .reset_index(drop=True)
    )


def make_dataset(
    frame: pd.DataFrame,
    class_to_index: dict[str, int],
    batch_size: int,
    training: bool,
) -> tf.data.Dataset:
    paths = frame["image_path"].astype(str).to_numpy()
    labels = frame["diagnostic"].map(class_to_index).to_numpy(dtype=np.int32)
    dataset = tf.data.Dataset.from_tensor_slices((paths, labels))

    def load_image(path: tf.Tensor, label: tf.Tensor):
        image = tf.io.read_file(path)
        image = tf.io.decode_image(image, channels=3, expand_animations=False)
        image.set_shape([None, None, 3])
        image = tf.image.resize(image, IMAGE_SIZE, antialias=True)
        return image, label

    dataset = dataset.map(load_image, num_parallel_calls=tf.data.AUTOTUNE)
    if training:
        dataset = dataset.shuffle(len(frame), seed=SEED, reshuffle_each_iteration=True)
    return dataset.batch(batch_size).prefetch(tf.data.AUTOTUNE)


def build_model(num_classes: int) -> tf.keras.Model:
    inputs = tf.keras.Input(shape=(*IMAGE_SIZE, 3), dtype=tf.float32, name="image")
    augmented = tf.keras.Sequential(
        [
            tf.keras.layers.RandomFlip("horizontal"),
            tf.keras.layers.RandomRotation(0.05),
            tf.keras.layers.RandomZoom(0.10),
        ],
        name="training_augmentation",
    )(inputs)
    backbone = tf.keras.applications.MobileNetV3Large(
        input_shape=(*IMAGE_SIZE, 3),
        include_top=False,
        weights="imagenet",
        include_preprocessing=True,
    )
    backbone.trainable = False
    features = backbone(augmented, training=False)
    features = tf.keras.layers.GlobalAveragePooling2D()(features)
    features = tf.keras.layers.Dropout(0.25)(features)
    outputs = tf.keras.layers.Dense(num_classes, activation="softmax", name="scores")(features)
    return tf.keras.Model(inputs, outputs, name="skinai_mobilenetv3_pad_ufes20")


class MacroF1Callback(tf.keras.callbacks.Callback):
    def __init__(self, validation_data: tf.data.Dataset):
        super().__init__()
        self.validation_data = validation_data

    def on_epoch_end(self, epoch: int, logs: dict | None = None) -> None:
        if logs is None:
            return
        probabilities = self.model.predict(self.validation_data, verbose=0)
        truth = np.concatenate(
            [labels.numpy() for _, labels in self.validation_data]
        )
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
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=Path("artifacts"))
    parser.add_argument("--epochs", type=int, default=12)
    parser.add_argument("--batch-size", type=int, default=32)
    args = parser.parse_args()

    metadata_path = args.data_dir / "metadata.csv"
    image_root = args.data_dir / "all_images"
    if not metadata_path.is_file() or not image_root.is_dir():
        raise FileNotFoundError(
            "Expected metadata.csv and all_images/ under --data-dir. "
            "Download the PAD-UFES-20 mirror before training."
        )

    metadata = pd.read_csv(metadata_path)
    required_columns = {"patient_id", "diagnostic", "img_id"}
    missing = required_columns.difference(metadata.columns)
    if missing:
        raise ValueError(f"metadata.csv is missing columns: {sorted(missing)}")

    path_lookup = {path.name: path for path in image_root.rglob("*") if path.is_file()}
    metadata["image_path"] = metadata["img_id"].map(path_lookup)
    metadata = metadata.dropna(subset=["image_path"])
    metadata = metadata[metadata["diagnostic"].isin(CLASS_NAMES)].reset_index(drop=True)
    if metadata.empty:
        raise ValueError("No labeled images were matched to metadata.csv.")

    train_frame, val_frame, test_frame = split_by_patient(metadata)
    class_to_index = {name: index for index, name in enumerate(CLASS_NAMES)}
    balanced_train_frame = balance_training_frame(train_frame)
    train_data = make_dataset(
        balanced_train_frame, class_to_index, args.batch_size, True
    )
    val_data = make_dataset(val_frame, class_to_index, args.batch_size, False)
    test_data = make_dataset(test_frame, class_to_index, args.batch_size, False)

    model = build_model(len(CLASS_NAMES))
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=1e-3),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    callbacks = [
        MacroF1Callback(val_data),
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
    model.fit(
        train_data,
        validation_data=val_data,
        epochs=args.epochs,
        shuffle=False,
        class_weight=None,
        verbose=2,
        callbacks=callbacks,
    )

    # Fine-tune the last backbone blocks with a low learning rate after the
    # new classifier head has learned a stable starting point.
    backbone = model.layers[1]
    backbone.trainable = True
    for layer in backbone.layers[:-30]:
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
        shuffle=False,
        class_weight=None,
        callbacks=callbacks,
    )

    args.output_dir.mkdir(parents=True, exist_ok=True)
    model_path = args.output_dir / "skinai_mobilenetv3_pad_ufes20.keras"
    tflite_path = args.output_dir / "skinai_mobilenetv3_pad_ufes20.tflite"
    model.save(model_path)

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_model = converter.convert()
    tflite_path.write_bytes(tflite_model)

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
    results = {
        "architecture": "MobileNetV3-Large",
        "dataset": "PAD-UFES-20",
        "split": "stratified patient-grouped approximately 70/15/15",
        "class_names": CLASS_NAMES,
        "train_images": len(train_frame),
        "balanced_training_examples_per_epoch": len(balanced_train_frame),
        "validation_images": len(val_frame),
        "test_images": len(test_frame),
        "test_classification_report": report,
        "test_confusion_matrix": confusion_matrix(
            truth, predictions, labels=list(range(len(CLASS_NAMES)))
        ).tolist(),
    }
    (args.output_dir / "evaluation.json").write_text(
        json.dumps(results, indent=2), encoding="utf-8"
    )
    (args.output_dir / "labels.json").write_text(
        json.dumps(CLASS_NAMES, indent=2), encoding="utf-8"
    )
    print(f"Saved model: {tflite_path}")
    print(f"Saved evaluation: {args.output_dir / 'evaluation.json'}")


if __name__ == "__main__":
    main()

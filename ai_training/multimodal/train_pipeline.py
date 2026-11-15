"""Train a MobileNetV3 multimodal educational classifier.

The image tower is MobileNetV3-Large. A second input is the 28-value body-site,
symptom, and duration vector from schema.py. Missing metadata stays unknown.

Augmentation stays in the data pipeline. The saved Keras model is a fixed
image-plus-metadata network. Temperature scaling is fit on the validation
split only. The uncertainty sweep is also validation-only and is not marked
validated.

This is an educational research trainer, not a medical device.
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
from sklearn.metrics import classification_report, confusion_matrix, f1_score

from focal_loss import SparseFocalLoss
from schema import (
    TONE_GROUPS,
    encode_metadata,
    feature_names,
    label_identified_by_blank_metadata,
    metadata_is_blank,
)

IMAGE_SIZE = (224, 224)
SEED = 42


def load_manifest(path: Path) -> tuple[pd.DataFrame, dict[str, object]]:
    frame = pd.read_json(path, lines=True)
    audit_path = path.with_name("audit.json")
    audit = json.loads(audit_path.read_text(encoding="utf-8")) if audit_path.is_file() else {}
    if "image-level" in str(audit.get("split_method", "")) and not audit.get("image_level_split_accepted"):
        raise ValueError("Refusing an image-level split that was not explicitly accepted.")
    required = {"image_path", "label", "split", "skin_tone", "body_site", "itch", "pain", "swelling", "changed", "duration"}
    missing = required.difference(frame.columns)
    if missing:
        raise ValueError(f"Manifest is missing columns: {sorted(missing)}")
    return frame, audit


def pack(frame: pd.DataFrame, class_to_index: dict[str, int]) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    paths = frame["image_path"].astype(str).to_numpy()
    labels = frame["label"].map(class_to_index).to_numpy(dtype=np.int32)
    meta = np.asarray(
        [
            encode_metadata(row.body_site, row.itch, row.pain, row.swelling, row.changed, row.duration)
            for row in frame.itertuples(index=False)
        ],
        dtype=np.float32,
    )
    return paths, meta, labels


def sample_weights(frame: pd.DataFrame) -> np.ndarray:
    class_counts = frame["label"].value_counts()
    class_weight = frame["label"].map(lambda label: len(frame) / (len(class_counts) * int(class_counts[label])))
    tone_weight = pd.Series(1.0, index=frame.index, dtype="float64")
    known = frame["skin_tone"].isin(TONE_GROUPS[:3])
    if bool(known.any()):
        tone_counts = frame.loc[known, "skin_tone"].value_counts()
        known_total = int(known.sum())
        tone_weight.loc[known] = frame.loc[known, "skin_tone"].map(
            lambda tone: known_total / (len(tone_counts) * int(tone_counts[tone]))
        )
    return (class_weight.to_numpy(dtype=np.float32) * tone_weight.to_numpy(dtype=np.float32))


def make_dataset(
    paths: np.ndarray,
    meta: np.ndarray,
    labels: np.ndarray,
    batch_size: int,
    training: bool,
    weights: np.ndarray | None = None,
) -> tf.data.Dataset:
    if weights is None:
        dataset = tf.data.Dataset.from_tensor_slices(((paths, meta), labels))
    else:
        dataset = tf.data.Dataset.from_tensor_slices(((paths, meta), labels, weights))

    def load_training(inputs, label, weight):
        image, metadata = _load_image(inputs, training=True)
        return (image, metadata), label, weight

    def load_eval(inputs, label):
        image, metadata = _load_image(inputs, training=False)
        return (image, metadata), label

    if training:
        dataset = dataset.shuffle(min(len(paths), 4096), seed=SEED, reshuffle_each_iteration=True)
        dataset = dataset.map(load_training, num_parallel_calls=tf.data.AUTOTUNE)
    else:
        dataset = dataset.map(load_eval, num_parallel_calls=tf.data.AUTOTUNE)
    return dataset.batch(batch_size).prefetch(tf.data.AUTOTUNE)


def _load_image(inputs, training: bool):
    path, metadata = inputs
    image = tf.io.read_file(path)
    image = tf.io.decode_image(image, channels=3, expand_animations=False)
    image.set_shape([None, None, 3])
    image = tf.image.resize(image, IMAGE_SIZE, antialias=True)
    image = tf.cast(image, tf.float32)
    if training:
        image = _augment(image)
    return image, metadata


def _augment(image: tf.Tensor) -> tf.Tensor:
    image = tf.image.random_flip_left_right(image)
    scaled = image / 255.0
    scaled = tf.image.random_saturation(scaled, 0.8, 1.2)
    scaled = tf.image.random_hue(scaled, 0.02)
    scaled = tf.image.random_brightness(scaled, 0.12)
    scaled = tf.image.random_contrast(scaled, 0.85, 1.15)
    image = tf.clip_by_value(scaled, 0.0, 1.0) * 255.0
    image = tf.cond(tf.random.uniform([]) < 0.25, lambda: _motion_blur(image), lambda: image)
    return tf.clip_by_value(image, 0.0, 255.0)


def _motion_blur(image: tf.Tensor) -> tf.Tensor:
    horizontal = tf.ones([1, 5, 3, 1], dtype=tf.float32) / 5.0
    vertical = tf.ones([5, 1, 3, 1], dtype=tf.float32) / 5.0
    kernel = tf.cond(tf.random.uniform([]) < 0.5, lambda: horizontal, lambda: vertical)
    blurred = tf.nn.depthwise_conv2d(image[None, ...], kernel, strides=[1, 1, 1, 1], padding="SAME")
    return blurred[0]


def build_model(class_count: int, meta_dim: int) -> tuple[tf.keras.Model, tf.keras.Model]:
    image = tf.keras.Input(shape=(*IMAGE_SIZE, 3), dtype=tf.float32, name="image")
    metadata = tf.keras.Input(shape=(meta_dim,), dtype=tf.float32, name="metadata")
    backbone = tf.keras.applications.MobileNetV3Large(
        input_shape=(*IMAGE_SIZE, 3),
        include_top=False,
        weights="imagenet",
        include_preprocessing=True,
    )
    backbone.trainable = False
    features = backbone(image, training=False)
    features = tf.keras.layers.GlobalAveragePooling2D()(features)
    features = tf.keras.layers.Dense(128, activation="relu")(features)
    meta = tf.keras.layers.Dense(32, activation="relu")(metadata)
    fused = tf.keras.layers.Concatenate()([features, meta])
    fused = tf.keras.layers.Dropout(0.3)(fused)
    fused = tf.keras.layers.Dense(64, activation="relu")(fused)
    logits = tf.keras.layers.Dense(class_count, name="logits")(fused)
    model = tf.keras.Model([image, metadata], logits, name="skinai_multimodal_mobilenetv3")
    return model, backbone


class ValidationMetrics(tf.keras.callbacks.Callback):
    def __init__(self, validation_data: tf.data.Dataset, truth: np.ndarray, tones: np.ndarray, class_count: int):
        super().__init__()
        self.validation_data = validation_data
        self.truth = truth
        self.tones = tones
        self.class_count = class_count

    def on_epoch_end(self, epoch: int, logs: dict | None = None) -> None:
        if logs is None:
            return
        logits = self.model.predict(self.validation_data, verbose=0)
        predicted = tf.nn.softmax(logits).numpy().argmax(axis=1)
        score = f1_score(
            self.truth,
            predicted,
            labels=list(range(self.class_count)),
            average="macro",
            zero_division=0,
        )
        logs["val_macro_f1"] = float(score)
        print(f" - val_macro_f1: {score:.4f}")
        for tone in TONE_GROUPS:
            mask = self.tones == tone
            if not mask.any():
                continue
            accuracy = float(np.mean(predicted[mask] == self.truth[mask]))
            print(f"   {tone}: validation accuracy {accuracy:.3f} on {int(mask.sum())} images")


def fit_temperature(logits: np.ndarray, truth: np.ndarray) -> float:
    temperature = tf.Variable(1.0, dtype=tf.float32)
    optimizer = tf.keras.optimizers.Adam(learning_rate=0.05)
    labels = tf.constant(truth, dtype=tf.int32)
    values = tf.constant(logits, dtype=tf.float32)
    for _ in range(200):
        with tf.GradientTape() as tape:
            scaled = values / tf.clip_by_value(temperature, 0.05, 10.0)
            nll = tf.reduce_mean(
                tf.nn.sparse_softmax_cross_entropy_with_logits(labels=labels, logits=scaled)
            )
        gradient = tape.gradient(nll, [temperature])[0]
        optimizer.apply_gradients([(gradient, temperature)])
    return float(tf.clip_by_value(temperature, 0.05, 10.0).numpy())


def uncertainty_sweep(probabilities: np.ndarray, truth: np.ndarray) -> list[dict[str, float | None]]:
    confidence = probabilities.max(axis=1)
    predicted = probabilities.argmax(axis=1)
    rows: list[dict[str, float | None]] = []
    for threshold in (0.35, 0.45, 0.55, 0.65, 0.75, 0.85):
        keep = confidence >= threshold
        accuracy = None
        if keep.any():
            accuracy = float(np.mean(predicted[keep] == truth[keep]))
        rows.append(
            {
                "minimum_confidence": float(threshold),
                "coverage": float(np.mean(keep)),
                "accuracy_when_labeled": accuracy,
            }
        )
    return rows


def evaluate_split(
    model: tf.keras.Model,
    paths: np.ndarray,
    meta: np.ndarray,
    truth: np.ndarray,
    tones: np.ndarray,
    class_names: list[str],
    temperature: float,
) -> tuple[dict[str, object], np.ndarray]:
    dataset = make_dataset(paths, meta, truth, 32, training=False)
    logits = model.predict(dataset, verbose=1)
    probabilities = tf.nn.softmax(logits / temperature).numpy()
    predicted = probabilities.argmax(axis=1)
    k = min(3, probabilities.shape[1])
    top_k = np.argsort(probabilities, axis=1)[:, -k:]
    top_k_hit = float(np.mean([truth[index] in top_k[index] for index in range(len(truth))]))
    per_tone = {}
    for tone in TONE_GROUPS:
        mask = tones == tone
        if not mask.any():
            per_tone[tone] = {"support": 0}
            continue
        per_tone[tone] = {
            "support": int(mask.sum()),
            "accuracy": float(np.mean(predicted[mask] == truth[mask])),
            "macro_f1": float(
                f1_score(
                    truth[mask],
                    predicted[mask],
                    labels=list(range(len(class_names))),
                    average="macro",
                    zero_division=0,
                )
            ),
        }
    report = {
        "top1_accuracy": float(np.mean(predicted == truth)),
        "top_k": k,
        "top_k_accuracy": top_k_hit,
        "macro_f1": float(
            f1_score(truth, predicted, labels=list(range(len(class_names))), average="macro", zero_division=0)
        ),
        "classification_report": classification_report(
            truth,
            predicted,
            labels=list(range(len(class_names))),
            target_names=class_names,
            output_dict=True,
            zero_division=0,
        ),
        "confusion_matrix": confusion_matrix(
            truth, predicted, labels=list(range(len(class_names)))
        ).tolist(),
        "skin_tone_groups": per_tone,
    }
    return report, logits


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=Path("ai_training/multimodal/run"))
    parser.add_argument("--epochs", type=int, default=8)
    parser.add_argument("--fine-tune-epochs", type=int, default=3)
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--loss", choices=("weighted", "focal"), default="weighted")
    parser.add_argument("--focal-gamma", type=float, default=2.0)
    parser.add_argument(
        "--image-only",
        action="store_true",
        help="Replace every metadata vector with zeros so body site and symptoms cannot separate classes.",
    )
    args = parser.parse_args()

    tf.keras.utils.set_random_seed(SEED)
    frame, _audit = load_manifest(args.manifest)
    class_names = sorted(frame.loc[frame["split"].eq("train"), "label"].unique())
    if len(class_names) < 2:
        raise ValueError("The training split needs at least two labels.")
    class_to_index = {name: index for index, name in enumerate(class_names)}
    splits = {}
    for name in ("train", "val", "test"):
        subset = frame.loc[frame["split"].eq(name)].reset_index(drop=True)
        if subset.empty:
            raise ValueError(f"The {name} split is empty.")
        paths, meta, labels = pack(subset, class_to_index)
        if args.image_only:
            meta = np.zeros_like(meta)
        splits[name] = (subset, paths, meta, labels)
        blank = sum(metadata_is_blank(row.tolist()) for row in meta)
        print(f"{name}: {len(subset)} images, {blank} with blank metadata, tones={subset['skin_tone'].value_counts().to_dict()}")

    if args.image_only:
        print("Image-only run: metadata is a constant zero vector and cannot separate classes.")
    else:
        train_blank = [metadata_is_blank(row.tolist()) for row in splits["train"][2]]
        separated = label_identified_by_blank_metadata(train_blank, splits["train"][0]["label"].astype(str).tolist())
        if separated is not None:
            raise ValueError(
                f"Blank metadata identifies {separated} and no other training label. "
                "The metadata tower would learn the missing questionnaire instead of the photo. "
                "Fill body site and symptoms for that class, or remove it, before training."
            )
        if len(train_blank) == sum(train_blank):
            print("Warning: training metadata is entirely unknown. The metadata tower cannot learn symptoms from this manifest.")

    train_frame, train_paths, train_meta, train_labels = splits["train"]
    _val_frame, val_paths, val_meta, val_labels = splits["val"]
    weights = sample_weights(train_frame)
    train_data = make_dataset(train_paths, train_meta, train_labels, args.batch_size, True, weights)
    val_data = make_dataset(val_paths, val_meta, val_labels, args.batch_size, False)
    model, backbone = build_model(len(class_names), train_meta.shape[1])
    loss = (
        SparseFocalLoss(args.focal_gamma)
        if args.loss == "focal"
        else tf.keras.losses.SparseCategoricalCrossentropy(from_logits=True)
    )

    def callbacks() -> list[tf.keras.callbacks.Callback]:
        return [
            ValidationMetrics(val_data, val_labels, _val_frame["skin_tone"].to_numpy(), len(class_names)),
            tf.keras.callbacks.EarlyStopping(
                monitor="val_macro_f1", mode="max", patience=3, restore_best_weights=True
            ),
            tf.keras.callbacks.ReduceLROnPlateau(
                monitor="val_macro_f1", mode="max", factor=0.3, patience=2, min_lr=1e-6
            ),
        ]

    model.compile(optimizer=tf.keras.optimizers.Adam(1e-3), loss=loss)
    model.fit(train_data, validation_data=val_data, epochs=args.epochs, callbacks=callbacks(), verbose=2)
    if args.fine_tune_epochs > 0:
        backbone.trainable = True
        for layer in backbone.layers[:-30]:
            layer.trainable = False
        for layer in backbone.layers:
            if isinstance(layer, tf.keras.layers.BatchNormalization):
                layer.trainable = False
        model.compile(optimizer=tf.keras.optimizers.Adam(1e-5), loss=loss)
        model.fit(
            train_data,
            validation_data=val_data,
            epochs=args.fine_tune_epochs,
            callbacks=callbacks(),
            verbose=2,
        )

    _val_report, val_logits = evaluate_split(
        model, val_paths, val_meta, val_labels, _val_frame["skin_tone"].to_numpy(), class_names, temperature=1.0
    )
    temperature = fit_temperature(val_logits, val_labels)
    val_probabilities = tf.nn.softmax(val_logits / temperature).numpy()
    sweep = uncertainty_sweep(val_probabilities, val_labels)

    test_frame, test_paths, test_meta, test_labels = splits["test"]
    test_report, _test_logits = evaluate_split(
        model,
        test_paths,
        test_meta,
        test_labels,
        test_frame["skin_tone"].to_numpy(),
        class_names,
        temperature=temperature,
    )
    args.output_dir.mkdir(parents=True, exist_ok=True)
    model.save(args.output_dir / "model.keras")
    (args.output_dir / "labels.json").write_text(json.dumps(class_names, indent=2), encoding="utf-8")
    (args.output_dir / "feature_layout.json").write_text(
        json.dumps({"names": feature_names(), "dim": len(feature_names())}, indent=2),
        encoding="utf-8",
    )
    (args.output_dir / "calibration.json").write_text(
        json.dumps(
            {
                "temperature": temperature,
                "validated": False,
                "minimum_confidence": None,
                "selection_rule": (
                    "Choose minimum_confidence from validation_sweep after reviewing "
                    "coverage and accuracy among the photos that still receive a label. "
                    "Set validated true only after freezing that choice. Do not pick it "
                    "from the test split."
                ),
                "validation_sweep": sweep,
                "validation_at_temperature_1": _val_report,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    (args.output_dir / "evaluation.json").write_text(
        json.dumps(
            {
                "architecture": "MobileNetV3-Large image only" if args.image_only else "MobileNetV3-Large plus metadata vector",
                "metadata_input": "constant zero" if args.image_only else "encoded questionnaire",
                "loss": args.loss,
                "temperature_applied_to_test": temperature,
                "test": test_report,
                "note": (
                    "Test metrics use the frozen validation temperature and the highest "
                    "score. They are not a diagnosis, and a benign or healthy label does "
                    "not rule out disease. Skin-tone rows with no source label are Unknown."
                ),
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"Saved run to {args.output_dir}")
    print(f"Validation temperature: {temperature:.3f}")


if __name__ == "__main__":
    main()

"""Export the multimodal Keras model to an FP16 TFLite file.

The exported network has two inputs, in this order:
    image      float32 [1, 224, 224, 3]  RGB values from 0 to 255
    metadata   float32 [1, 28]           MetadataFeatures.encode order

The output is a temperature-scaled softmax. The current Flutter lesion
classifier sends only an image, so this file is not a drop-in replacement
until the scan flow passes the metadata vector as the second input.

FP16 stores the weights in float16 and keeps the computation in float32.
Compare validation scores before replacing any model in the app.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import numpy as np
import tensorflow as tf

import focal_loss  # noqa: F401  Registers the custom loss before load_model.
from schema import feature_names


def build_calibrated(model: tf.keras.Model, temperature: float) -> tf.keras.Model:
    scaled = tf.keras.layers.Rescaling(1.0 / temperature, name="temperature")(model.output)
    scores = tf.keras.layers.Softmax(name="scores")(scaled)
    return tf.keras.Model(model.inputs, scores, name="skinai_multimodal_calibrated")


def check_interpreter(path: Path, class_count: int, meta_dim: int) -> None:
    interpreter = tf.lite.Interpreter(model_path=str(path))
    inputs = interpreter.get_input_details()
    if len(inputs) != 2:
        raise RuntimeError(f"Expected 2 inputs, found {len(inputs)}.")
    prepared: list[tuple[int, np.ndarray]] = []
    for detail in inputs:
        shape = [1 if dim is None or int(dim) < 0 else int(dim) for dim in detail["shape"]]
        tensor = np.zeros(shape, dtype=np.float32)
        if shape[-1] == 3:
            tensor[...] = 128.0
        elif shape[-1] == meta_dim:
            tensor[0, 0] = 1.0
        else:
            raise RuntimeError(f"Unexpected input shape {shape} for {detail['name']}.")
        interpreter.resize_tensor_input(detail["index"], shape, strict=True)
        prepared.append((detail["index"], tensor))
    interpreter.allocate_tensors()
    for index, tensor in prepared:
        interpreter.set_tensor(index, tensor)
    interpreter.invoke()
    output = interpreter.get_tensor(interpreter.get_output_details()[0]["index"])
    if output.shape[-1] != class_count:
        raise RuntimeError(f"Expected {class_count} scores, found shape {output.shape}.")
    if not np.isfinite(output).all():
        raise RuntimeError("TFLite output contains non-finite scores.")
    total = float(output.sum())
    if abs(total - 1.0) > 0.05:
        raise RuntimeError(f"TFLite scores sum to {total:.4f}, not about 1.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=None)
    args = parser.parse_args()

    model = tf.keras.models.load_model(args.model_dir / "model.keras", compile=False)
    labels = json.loads((args.model_dir / "labels.json").read_text(encoding="utf-8"))
    calibration = json.loads((args.model_dir / "calibration.json").read_text(encoding="utf-8"))
    temperature = float(calibration.get("temperature", 1.0))
    calibrated = build_calibrated(model, temperature)
    converter = tf.lite.TFLiteConverter.from_keras_model(calibrated)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    tflite_model = converter.convert()

    output = args.output or (args.model_dir / "skinai_multimodal_fp16.tflite")
    output.write_bytes(tflite_model)
    names = feature_names()
    metadata = {
        "format": "tflite-fp16-weights",
        "inputs": [
            {
                "index": 0,
                "name": "image",
                "type": "float32",
                "shape": [1, 224, 224, 3],
                "range": "0-255 RGB",
            },
            {
                "index": 1,
                "name": "metadata",
                "type": "float32",
                "shape": [1, len(names)],
                "names": names,
                "encoder": "retired; not present in the PAD-only app",
            },
        ],
        "output": {"name": "scores", "labels": labels},
        "temperature": temperature,
        "uncertainty_policy_validated": bool(calibration.get("validated", False)),
        "minimum_confidence": calibration.get("minimum_confidence"),
        "note": (
            "Educational scores, not a diagnosis. Do not show a condition name when "
            "the frozen minimum confidence is unmet. The current single-input lesion "
            "classifier cannot load this two-input model."
        ),
    }
    metadata_path = output.with_name(output.stem + "_metadata.json")
    metadata_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    check_interpreter(output, len(labels), len(names))
    print(f"Saved {output}")
    print(f"Saved {metadata_path}")


if __name__ == "__main__":
    main()

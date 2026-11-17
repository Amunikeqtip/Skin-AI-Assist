"""Check UCI pixel-gate acceptance on held-out positive PAD/MSLD images.

This reports positive-image acceptance only. It cannot estimate false accepts
because PAD and MSLD contain skin images and no non-skin photo controls.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd
import tensorflow as tf
from PIL import Image, ImageOps

SIDE = 32
IMAGE_BATCH = 16
THRESHOLDS = (0.01, 0.03, 0.05, 0.08, 0.10)


def image_pixels(image_path: str) -> np.ndarray:
    with Image.open(image_path) as source:
        image = ImageOps.exif_transpose(source).convert("RGB")
        image = image.resize((SIDE, SIDE), Image.Resampling.BILINEAR)
        pixels = np.asarray(image, dtype=np.float32).reshape(-1, 3)
    return pixels[:, ::-1] / 255.0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    manifest = pd.read_json(args.manifest, lines=True)
    test = manifest[manifest["split"] == "test"].reset_index(drop=True)
    interpreter = tf.lite.Interpreter(model_path=str(args.model))
    input_index = interpreter.get_input_details()[0]["index"]
    output_index = interpreter.get_output_details()[0]["index"]
    interpreter.resize_tensor_input(
        input_index, [IMAGE_BATCH * SIDE * SIDE, 3], strict=True
    )
    interpreter.allocate_tensors()
    fractions = []
    for start in range(0, len(test), IMAGE_BATCH):
        paths = test["image_path"].iloc[start : start + IMAGE_BATCH].astype(str)
        batch = [image_pixels(path) for path in paths]
        real_count = len(batch)
        batch.extend(
            [np.zeros((SIDE * SIDE, 3), dtype=np.float32)]
            * (IMAGE_BATCH - real_count)
        )
        interpreter.set_tensor(input_index, np.concatenate(batch, axis=0))
        interpreter.invoke()
        scores = interpreter.get_tensor(output_index).reshape(IMAGE_BATCH, SIDE * SIDE)
        fractions.extend((scores[:real_count] >= 0.5).mean(axis=1).tolist())
    if len(fractions) != len(test):
        raise RuntimeError("Image gate evaluation produced an unexpected result count.")
    test["skin_pixel_fraction"] = fractions

    result = {
        "dataset": "held-out patient groups from PAD-UFES-20 plus MSLD v2.0",
        "image_count": int(len(test)),
        "positive_skin_images_only": True,
        "image_resize": "Pillow bilinear, 32x32, approximates Flutter image resize",
        "skin_fraction_by_source": {
            source: {
                "images": int(len(group)),
                "p10": float(group["skin_pixel_fraction"].quantile(0.10)),
                "median": float(group["skin_pixel_fraction"].median()),
            }
            for source, group in test.groupby("source")
        },
        "acceptance_rate_by_minimum_skin_fraction": {
            str(threshold): float((test["skin_pixel_fraction"] >= threshold).mean())
            for threshold in THRESHOLDS
        },
        "per_source_acceptance_at_1_percent": {
            source: float((group["skin_pixel_fraction"] >= 0.01).mean())
            for source, group in test.groupby("source")
        },
        "limitations": [
            "All images in this check are skin photographs; false-accept rate is unknown.",
            "This is not an image-level validation of skin versus non-skin detection.",
            "The deployment preprocessing is approximated with Pillow, not Flutter's image package.",
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()

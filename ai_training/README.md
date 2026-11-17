# Skin-gate and PAD screening model training

The app analysis has two gates after the existing image-quality check:

1. A small UCI BGR pixel classifier estimates how much of a photo looks like
   skin. It is an experimental color gate, not a spatial image model.
2. A **MobileNetV3-Large** model classifies six PAD-UFES-20 lesion classes,
   plus healthy skin and a limited other-condition class from MSLD v2.0.

## Dataset

Download the [PAD-UFES-20 mirror on Hugging Face](https://huggingface.co/datasets/SalmaneExploring/pad-ufes-20)
and keep its `metadata.csv` and `all_images/` directory together. The dataset
mirror is marked CC BY 4.0 and cites the original PAD-UFES-20 paper. Preserve
that attribution with any copy of the dataset or resulting project materials.

PAD-UFES-20 has six lesion labels: ACK, BCC, MEL, NEV, SCC, and SEK. It contains
three cancers (BCC, MEL, SCC), actinic keratosis, nevus, and seborrheic
keratosis; it does not contain healthy or non-skin photos. The training code
uses patient-grouped splits.

MSLD v2.0 contributes 114 unique healthy images and 641 images across mpox,
chickenpox, measles, cowpox, and HFMD. The model's `OTHER_SKIN_CONDITION` label
means only these five MSLD classes; it is not a catch-all for all diseases.
MSLD is licensed CC BY-NC 4.0, so keep this prototype non-commercial and retain
the dataset attribution. The preparation script deduplicates fold copies and
splits by patient before training.

## Train and export

Use Python 3.10–3.13 in a GPU-enabled Kaggle or Colab session for a fast run.
Download the dataset with the Hugging Face CLI (or its dataset page), then
install TensorFlow 2.20, pandas, scikit-learn, and NumPy:

```powershell
hf download SalmaneExploring/pad-ufes-20 --repo-type dataset --local-dir data/pad-ufes-20
python -m pip install tensorflow==2.20.0 pandas scikit-learn numpy
python ai_training/train_pad_ufes.py --data-dir /path/to/pad-ufes-20 --output-dir ai_training/artifacts
```

The PAD-only output folder contains:

- `skinai_mobilenetv3_pad_ufes20.tflite` — model for on-device inference
- `skinai_mobilenetv3_pad_ufes20.keras` — reloadable training model
- `labels.json` — output index mapping
- `evaluation.json` — patient-held-out metrics and confusion matrix

The evaluation file must be reviewed before describing model performance. The
dataset is small and imbalanced, so report per-class recall and macro-F1 as well
as accuracy. In particular, do not imply that a missed or low-confidence
prediction rules out cancer.

## Prototype status

The exported model is an educational prototype, not a medical device. It is
trained on a limited Brazilian dataset and has not been clinically validated
for use in Zimbabwe or other populations. It must not be used for diagnosis,
triage decisions, or treatment recommendations. The Flutter integration should
continue to identify the app as informational and direct users to a clinician.

## Current two-stage training commands

The UCI Skin Segmentation dataset contains labeled BGR pixels (not full
images), has 245,057 samples, and is licensed CC BY 4.0. The experimental skin
gate's pixel metrics cannot establish image-level false-accept performance.
Download its `Skin_NonSkin.txt` from the [UCI dataset page](https://archive.ics.uci.edu/dataset/229/skin%2Bsegmentation).

```powershell
python ai_training/train_skin_pixel_gate.py --data D:/data/uci-skin-segmentation/Skin_NonSkin.txt --output-dir D:/data/skin-gate-run
python ai_training/prepare_pad_screening.py --pad-dir D:/data/pad-ufes-20 --msld-zip "D:/data/msld-v2/Original Images.zip" --output-dir D:/data/skinai-screening
python ai_training/train_pad_screening.py --manifest D:/data/skinai-screening/manifest.jsonl --output-dir D:/data/skinai-screening/model_run
```

Review `audit.json` and `evaluation.json` before copying model artifacts into
`assets/models/`. Report per-class recall and macro-F1 with test support. The
healthy and melanoma classes are small, and neither model is clinically
validated. A missed or low-confidence output does not rule out cancer.

The pixel gate uses a provisional 1% skin-colour-pixel cutoff. The optional
`evaluate_skin_gate_images.py` check measures only the acceptance rate on PAD
and MSLD skin photos; it has no non-skin image controls and therefore cannot
validate specificity. Collect and label representative non-skin phone photos
before treating that cutoff as a real skin/no-skin gate.

## Image-level skin-gate dataset workflow

The reviewed image-level dataset plan, CSV templates, leakage validator, and
false-accept/false-reject evaluator are in
[`skin_gate_dataset/`](skin_gate_dataset/README.md). The current UCI data is
pixel-level, and PAD/MSLD are skin-only image sources; neither measures the
false-accept rate on non-skin phone photos. The new scripts intentionally do
not train until reviewed full-photo controls and an untouched test split exist.

Keep the photos outside Git. Copy
[`skin_gate_dataset/manifest.template.csv`](skin_gate_dataset/manifest.template.csv)
to a data folder, fill it after review, and run:

```powershell
python ai_training/skin_gate_dataset/validate_manifest.py `
  --manifest D:/data/skin-gate-images/manifest.csv `
  --report D:/data/skin-gate-images/manifest_audit.json
```

The current local manifest is seeded with positive PAD/MSLD photos and nine
Wikimedia Commons non-skin candidate photos. The Commons candidates are
pending human review and must not be used as a validation set yet. Their
attribution is in `D:/data/skin-gate-images/commons_attribution.csv`.

After the whole-image gate has predictions on the frozen test split, use
`skin_gate_dataset/evaluate_predictions.py` to report error rates overall and
by source, skin-tone label, and device.

Older multimodal experiments are archived under
`ai_training/deferred_multimodal/`; they are not used by the app.

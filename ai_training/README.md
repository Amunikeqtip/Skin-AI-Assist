# PAD-UFES-20 MobileNetV3 training

This folder trains a six-class **MobileNetV3-Large** image classifier using
PAD-UFES-20 smartphone clinical photos and exports a TensorFlow Lite model for
the Flutter app. It uses ImageNet weights only to initialize the backbone; the
classification head is trained on PAD-UFES-20.

## Dataset

Download the [PAD-UFES-20 mirror on Hugging Face](https://huggingface.co/datasets/SalmaneExploring/pad-ufes-20)
and keep its `metadata.csv` and `all_images/` directory together. The dataset
mirror is marked CC BY 4.0 and cites the original PAD-UFES-20 paper. Preserve
that attribution with any copy of the dataset or resulting project materials.

The dataset has six labels: ACK, BCC, MEL, NEV, SCC, and SEK. Stratified splits
are grouped by patient ID to avoid putting photos from the same patient into
both training and evaluation sets. Training examples are balanced by
oversampling minority diagnoses, and early stopping selects by validation
macro-F1.

## Train and export

Use Python 3.10–3.13 in a GPU-enabled Kaggle or Colab session for a fast run.
Download the dataset with the Hugging Face CLI (or its dataset page), then
install TensorFlow 2.20, pandas, scikit-learn, and NumPy:

```powershell
hf download SalmaneExploring/pad-ufes-20 --repo-type dataset --local-dir data/pad-ufes-20
python -m pip install tensorflow==2.20.0 pandas scikit-learn numpy
python ai_training/train_pad_ufes.py --data-dir /path/to/pad-ufes-20 --output-dir ai_training/artifacts
```

The output folder contains:

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

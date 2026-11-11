# SkinAI Assist MobileNetV3 model card

## Purpose

This is an educational, on-device image-classification model for demonstrating
an AI workflow in the SkinAI Assist prototype. It is not a medical device and
must not be used to diagnose, rule out cancer, or decide whether care is needed.

## Model and data

- Architecture: MobileNetV3-Large, initialized with ImageNet weights and
  fine-tuned for six PAD-UFES-20 classes.
- Dataset: 2,298 smartphone clinical images from 1,373 patients.
- Dataset mirror: [PAD-UFES-20 on Hugging Face](https://huggingface.co/datasets/SalmaneExploring/pad-ufes-20),
  identified as CC BY 4.0. Cite Pacheco et al., *PAD-UFES-20: a skin lesion
  dataset composed of patient data and clinical images collected from
  smartphones*, Data in Brief, 2020, DOI: 10.1016/j.dib.2020.106221.
- Patient separation: stratified grouped train/validation/test split, with no
  patient shared between partitions.
- Training balance: minority classes oversampled in training only; early
  stopping selected by validation macro-F1.
- Input: RGB image resized to 224 × 224; float32 values in the 0–255 range.
- Output order: ACK, BCC, MEL, NEV, SCC, SEK. These are uncalibrated model
  scores, not clinical probabilities.

## Held-out evaluation

This local run used 1,531 training images, 384 validation images, and 383
patient-held-out test images. Test accuracy was 65.0% and macro-F1 was 0.549.
Recall was 44.4% for melanoma (4/9) and 15.6% for squamous cell carcinoma
(5/32). The rare cancer class sample counts are too small to establish reliable
performance. These results do not support clinical screening or triage.

## Limitations and safety

The data is small, imbalanced, and collected from a specific Brazilian care
program. This model has not been externally or clinically validated and is not
known to generalize to local populations, camera conditions, or lesion types.
A low score or a benign-looking class does not rule out cancer. Users should
consult a qualified clinician about concerning or changing lesions.

Training code and further setup notes are in `ai_training/`.

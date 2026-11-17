# SkinAI Assist staged-model prototype

## Purpose and scope

This is a non-clinical, educational prototype. It is not validated for cancer
screening, diagnosis, triage, or treatment decisions. It must not be used to
rule out cancer or delay clinical assessment.

The app runs image-quality checks, then a provisional skin-colour pixel gate,
then an eight-class image classifier. The skin gate and disease classifier
have different training data and limitations.

## Stage 1: skin-colour pixel gate

- Model: small three-layer dense network operating on individual BGR pixels.
- Dataset: [UCI Skin Segmentation](https://archive.ics.uci.edu/dataset/229/skin%2Bsegmentation),
  Bhatt and Dhall (2009), CC BY 4.0.
- Data: 245,057 labeled pixel samples; the source provides pixels, not full
  photographs. Input order is BGR normalized to 0–1.
- Test: the random pixel-row split produced ROC AUC 0.9999. Rows do not have
  image or subject identifiers, so this score does not measure generalization
  to new phone photos.
- App rule: a provisional 1% of sampled pixels must score as skin-coloured.
- Image check: 517 held-out PAD/MSLD skin photos were tested; 93.8% passed the
  1% rule. This set contains no non-skin photos, so false-accept rate is
  unknown. A colour model can mistake objects/backgrounds for skin and can
  reject real skin. It does not verify anatomy or the selected body part.

## Stage 2: PAD/MSLD classifier

- Architecture: MobileNetV3-Large, initialized from ImageNet and fine-tuned
  as an image-only, eight-class model.
- Input: 224 × 224 RGB float32 pixels in the 0–255 range.
- PAD-UFES-20: 2,298 smartphone clinical images from 1,373 patients, licensed
  CC BY 4.0. Its six classes are ACK, BCC, MEL, NEV, SCC, and SEK. BCC, MEL,
  and SCC are cancers; ACK is actinic keratosis; NEV and SEK are non-cancer
  lesion classes. PAD does not contain healthy or non-skin images.
- MSLD v2.0: 755 unique images were deduplicated by filename across folds.
  There are 114 healthy images and 641 images in five infectious-condition
  classes: mpox, chickenpox, measles, cowpox, and HFMD. The dataset license is
  CC BY-NC 4.0, so this combined artifact is for non-commercial use only and
  must retain attribution to Ali et al. and the MSLD v2.0 source.
- `HEALTHY` is learned from the small MSLD healthy class. `OTHER_SKIN_CONDITION`
  is only those five MSLD conditions; it does not mean all other skin diseases.
- Patient groups were kept separate across train, validation, and test splits.
  The final split contained 2,021 train, 515 validation, and 517 test photos.

## Held-out test results

The TFLite model achieved 66.5% accuracy and 0.607 macro-F1 on the 517-photo
test split. Per-class recall and test support:

| Class | Recall | Test images |
| --- | ---: | ---: |
| Actinic keratosis (ACK) | 68.6% | 102 |
| Basal cell carcinoma (BCC) | 60.1% | 178 |
| Melanoma (MEL) | 44.4% | 9 |
| Nevus (NEV) | 64.7% | 34 |
| Squamous cell carcinoma (SCC) | 37.5% | 32 |
| Seborrheic keratosis (SEK) | 59.0% | 39 |
| Healthy (MSLD) | 82.4% | 17 |
| Other MSLD conditions | 86.8% | 106 |

The cancer-class recall remains weak, and the melanoma test group is very
small. Overall accuracy must not hide those misses. The results do not support
reliable screening; concerning lesions still require a qualified clinician.

## Runtime interpretation

The disease model always produces one of its eight labels after the skin gate
passes. It has no calibrated refusal/uncertainty class. The pixel gate only
estimates colour prevalence. Neither gate has a validated whole-image
false-positive rate. The app shows uncalibrated model scores; they are not
medical probabilities.

The previous six-class PAD-only artifact and its evaluation are retained as
`skinai_mobilenetv3_pad_ufes20.tflite`, `pad_ufes_only_evaluation.json`, and
`PAD_UFES_ONLY_MODEL_CARD.md` for comparison. The active app uses
`skinai_pad_msld_8class.tflite` and `skin_pixel_gate.tflite`.

## Reproduction

Training and evaluation scripts are in `ai_training/`. See its README for the
dataset preparation commands and required attribution. The current gate
threshold and both models need validation on representative full phone photos,
including non-skin objects and a substantially broader healthy-skin sample,
before they can be described as reliable.

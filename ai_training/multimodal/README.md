# Multimodal training pipeline

Educational research pipeline for SkinAI Assist. It does not diagnose, rule out
disease, or replace the six-class PAD-UFES model already in the app.

The phone app asks for one of nine body areas, itch, pain, swelling, recent
change, and duration. Those fields are the metadata input. A missing field is
encoded as unknown, not as "no".

## Stages

1. `prepare_data.py` maps local datasets through `taxonomy.json`, drops corrupt,
   tiny, very blurry, and badly exposed photos, and writes a patient-aware
   manifest plus an audit. MRSA, cellulitis, impetigo, cold sores, and shingles
   are refused. A folder named only "skin cancer" is refused because it mixes
   different cancers.
2. The existing on-device photo check remains the phone gate. This disease
   model is trained only on images that passed the offline quality filter.
3. `train_pipeline.py` trains MobileNetV3-Large fused with the 28-value
   metadata vector. It logs validation accuracy for Fitzpatrick groups I–II,
   III–IV, and V–VI when the source file contains a tone label. Tone is never
   guessed from the photo.
4. Temperature scaling is fit on the validation split. The confidence sweep is
   saved with `validated: false`. The test split is scored once after that
   temperature is frozen.
5. `export_tflite.py` writes an FP16-weight TFLite file with two inputs. The
   Flutter encoder is `lib/core/services/metadata_features.dart`. The current
   scan classifier sends one image input, so do not replace that file with this
   export until the scan flow passes metadata as the second input.

EfficientNet-Lite0 is not the default. The app, the preprocessing, and the
existing trainers use MobileNetV3-Large.

## Run

```powershell
python -m pip install tensorflow==2.20.0 pandas scikit-learn numpy pillow
python ai_training/multimodal/prepare_data.py --sources ai_training/multimodal/sources.example.json --output-dir ai_training/multimodal/prepared
python ai_training/multimodal/train_pipeline.py --manifest ai_training/multimodal/prepared/manifest.jsonl --output-dir ai_training/multimodal/run
python ai_training/multimodal/export_tflite.py --model-dir ai_training/multimodal/run
```

Edit `sources.example.json` so the paths point at datasets you already have
permission to use. The scripts do not download images. Add `--loss focal` to
train with focal loss instead of class-and-tone-weighted cross-entropy.

`--allow-image-level-split` is off by default. Turn it on only for a folder
dataset that has no patient ids, and treat that result as leaky.

Read `audit.json` and `evaluation.json` before copying any file into
`assets/models/`. A healthy label is included only when a source folder or
column actually says the skin is healthy.

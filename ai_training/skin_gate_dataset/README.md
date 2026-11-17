# Image-level skin-gate dataset

This workspace defines a reviewed, image-level dataset for evaluating whether
an uploaded phone photo contains visible human skin. It replaces neither the
current UCI pixel baseline nor the PAD/MSLD classifier yet. The UCI baseline is
kept only as an experimental comparison because it was trained from labelled
pixels, not complete images.

## Goal and labels

The gate answers only: **does this image contain enough clearly visible human
skin in the intended capture area to continue?** It does not identify a body
part, a lesion, or a diagnosis. Body-area verification is a separate future
task.

Use these image labels:

- `skin_present`: visible human skin is clearly present in the intended area.
- `skin_absent`: no visible human skin is present (include skin-coloured
  objects, clothing, animals, backgrounds, and unrelated objects).
- `ambiguous`: reviewers cannot reliably decide, or the image is unsuitable
  for a skin-presence label. Keep this class for abstention evaluation; do not
  silently relabel it as skin or non-skin.

Image quality is recorded separately as `good`, `blurry`, `poor_lighting`,
`obstructed`, or `unknown`. Do not use a poor-quality image as a `skin_absent`
example. The app's existing quality gate should reject quality failures before
the skin gate.

## Pilot collection plan

1. Start with a small, consented **workflow pilot** across varied phones,
   people, skin tones, lighting, distances, body areas, and backgrounds. Include
   ordinary healthy-skin photos and skin-condition photos. For non-skin
   controls, include skin-coloured objects, clothing, pets, walls, wood, food,
   and unrelated close-ups. This pilot is for finding labeling and capture
   problems; it is not a performance validation set.
2. Keep all images from one participant in one `group_id`; use pseudonymous IDs
   such as `P0001`, never names, email addresses, or other direct identifiers.
3. Have two reviewers independently label image-level skin presence and
   quality. Resolve disagreements through a third reviewer and record
   `adjudicated`. Mark agreement as `reviewed_agreement`. Keep unresolved
   examples as `pending`/`ambiguous` and out of binary training.
4. Store source, consent/license basis, device family, body area, and optional
   skin-tone label. Skin-tone metadata is for evaluation, not a proxy for race
   and not a feature the gate should need to make its decision.
5. Deduplicate exact files by SHA-256 and inspect near-duplicates. Keep each
   participant and capture session wholly inside one split.
6. Create a frozen test set before model tuning. Do not tune thresholds on the
   test set. Report false accepts and false rejects, abstentions, and subgroup
   results with denominators and confidence intervals.

For the first pilot, prioritize coverage of the capture scenarios over a large
image count. Track the number of distinct participants and devices, and ensure
both `skin_present` and `skin_absent` examples occur in each major lighting and
background condition. Reserve whole participants for test before training;
small subgroup counts should be reported as exploratory only. Do not claim a
target clinical sensitivity from this pilot.

Do not place private photographs in Git. Put the image corpus outside the
repository (for example `D:/data/skin-gate-images/`) and set `image_path` to an
absolute path or a path relative to the manifest. Obtain informed permission
for every private image, avoid collecting faces or identifying background
details, restrict access, and delete images when the agreed retention period
ends. Public dataset use must follow that dataset's current license and terms.

## Manifest

Copy `manifest.template.csv` and fill one row per image. Required columns are:

| Column | Meaning |
| --- | --- |
| `image_id` | Unique pseudonymous image key |
| `image_path` | Absolute path or path relative to the CSV |
| `source` | Dataset or consented collection name |
| `source_label` | Original dataset class/label, if applicable |
| `group_id` | Globally unique pseudonymous participant/source-group key used to prevent leakage; prefix public IDs with their dataset name |
| `capture_session_id` | Optional session key; never a personal identifier |
| `skin_label` | `skin_present`, `skin_absent`, or `ambiguous` |
| `quality_label` | `good`, `blurry`, `poor_lighting`, `obstructed`, or `unknown` |
| `review_status` | `pending`, `reviewed_agreement`, or `adjudicated` |
| `reviewer_count` | Number of independent reviewers, normally 2 or 3 |
| `skin_tone_label` | Optional reviewed/self-reported tone group or `unknown` |
| `skin_tone_method` | Method used, or blank |
| `device_family` | Phone make/model group where known, otherwise `unknown` |
| `body_area` | Image area or `not_applicable` for non-skin controls |
| `data_rights` | Consent reference or exact dataset license/terms |
| `split` | `unassigned`, `train`, `val`, or `test` |
| `sha256` | Optional; validator computes hashes and detects duplicates |

Check a populated manifest:

```powershell
python ai_training/skin_gate_dataset/validate_manifest.py `
  --manifest D:/data/skin-gate-images/manifest.csv `
  --report D:/data/skin-gate-images/manifest_audit.json
```

## Evaluation

Run `evaluate_predictions.py` on predictions from the frozen test set. The
prediction CSV must contain the columns in `predictions.template.csv`. It
reports false-accept rate (non-skin incorrectly passed), false-reject rate
(skin incorrectly rejected), abstention rate, coverage, and subgroup counts.
Treat `ambiguous` truth labels as a separate abstention review group, not as
binary truth. Always display each metric's denominator; small subgroups are
descriptive, not proof of equal performance.

```powershell
python ai_training/skin_gate_dataset/evaluate_predictions.py `
  --predictions D:/data/skin-gate-images/test_predictions.csv `
  --output D:/data/skin-gate-images/test_metrics.json
```

The next model should be a small whole-image classifier or segmentation model
trained on complete photos, with a held-out person-level test set. The test
report must include false-accept/false-reject rates by source, tone group, and
device when sample counts permit. A good metric on a small convenience pilot
does not establish clinical performance.

## Current data status

The working manifest currently has 3,046 rows: 3,037 source-derived positive
skin photos from PAD-UFES-20/MSLD and nine Wikimedia Commons object/texture
candidate negatives (textile, wood, dog fur, fruit, leaf, wall, and keyboard).
All imported rows are pending review and unassigned. The nine negative photos
were visually screened for visible human skin, but still require your review;
they are only a tiny seed set, not enough to train or validate a gate. Their
licenses and attribution are recorded in `D:/data/skin-gate-images/commons_attribution.csv`.

The UCI file is pixel-level, and PAD/MSLD are skin-positive; those sources alone
cannot measure image-level non-skin false accepts. The local path
`E:/Skin dataset/` was not available when this workflow was prepared. Do not
train a new gate until the candidates are reviewed, more representative
non-skin and phone-photo examples are added, and an independent test split is
present.


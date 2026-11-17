import 'package:flutter/material.dart';
import 'dart:io';

import '../../../../core/services/skin_classifier.dart';
import 'image_scan_progress.dart';

class PadAnalysisResultPanel extends StatelessWidget {
  const PadAnalysisResultPanel({
    required this.prediction,
    required this.isAnalyzing,
    required this.analysisError,
    required this.analysisStage,
    required this.imagePath,
    required this.isSaving,
    required this.onSave,
    super.key,
  });

  final SkinPrediction? prediction;
  final bool isAnalyzing;
  final String? analysisError;
  final String? analysisStage;
  final String? imagePath;
  final bool isSaving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isAnalyzing) ...[
          ImageScanProgress(imagePath: imagePath),
          const SizedBox(height: 16),
        ] else if (imagePath != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.file(
              File(imagePath!),
              height: 220,
              width: double.infinity,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 16),
        ],
        Center(
          child: Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 52,
              color: Colors.teal,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Experimental skin-lesion model output',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'MobileNetV3-Large is trained on PAD-UFES-20 lesion images plus '
          'MSLD v2.0 examples. It returns the six PAD lesion labels, a small '
          'healthy-skin class, and an “other” class covering only the five '
          'infectious conditions in MSLD. Scores are not medical probabilities '
          'or a diagnosis, and “other” does not cover every skin disease.',
        ),
        const SizedBox(height: 10),
        const Text(
          'Skin verification is experimental: the gate checks pixel colours, '
          'not body structure. A pass does not confirm that a photo contains '
          'human skin, and a fail may reject a real skin photo.',
        ),
        const SizedBox(height: 16),
        const Card(
          child: ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('Research prototype only'),
            subtitle: Text(
              'The datasets are small and come from different populations '
              'and image sources. This model is not clinically validated. '
              'A low score, healthy result, or other-condition result does '
              'not rule out cancer. Consult a healthcare professional about '
              'concerning or changing lesions.',
            ),
          ),
        ),
        if (isAnalyzing) ...[
          _buildProcessingDetails(context),
        ] else if (prediction case final result?) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    'Top PAD model match: ${result.topMatch.label}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text('Uncalibrated model scores'),
                  const SizedBox(height: 12),
                  for (final item
                      in result.scores.take(3)) ...[
                    Row(
                      children: [
                        SizedBox(
                          width: 132,
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: item.score
                                .clamp(0.0, 1.0)
                                .toDouble(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                            '${(item.score * 100).round()}%'),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
          const Text(
            'The photo is analyzed on this device and is not saved to visit '
            'history or sent to a server.',
          ),
        ] else if (analysisError case final error?) ...[
          Card(
            color: Theme.of(context)
                .colorScheme
                .errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(error),
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed:
              isSaving || isAnalyzing ? null : onSave,
          child: Text(isSaving
              ? 'Saving…'
              : 'Save visit to history'),
        ),
      ],
    );
  }

  Widget _buildProcessingDetails(BuildContext context) {
    const steps = [
      (
        'quality',
        'Image quality',
        'Checking focus, lighting, and resolution'
      ),
      (
        'skin',
        'Skin-colour gate',
        'Checking sampled pixels for skin-like colour'
      ),
      (
        'classifier',
        'PAD model',
        'Running the on-device screening model'
      ),
    ];
    final activeIndex = steps
        .indexWhere((step) => step.$1 == analysisStage);
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Image processing',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium),
            const SizedBox(height: 6),
            const Text(
                'The scan runs on this device. Processing time varies by photo and phone.'),
            const SizedBox(height: 12),
            for (var index = 0;
                index < steps.length;
                index++) ...[
              if (index > 0) const SizedBox(height: 12),
              Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: index < activeIndex
                        ? Icon(Icons.check_circle,
                            color: colors.primary, size: 21)
                        : index == activeIndex
                            ? Padding(
                                padding:
                                    const EdgeInsets.all(2),
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.primary,
                                ),
                              )
                            : Icon(
                                Icons
                                    .radio_button_unchecked,
                                color: colors.outline,
                                size: 21),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(steps[index].$2,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall),
                        Text(steps[index].$3,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

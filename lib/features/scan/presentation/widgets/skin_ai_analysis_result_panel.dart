import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/services/groq_skin_classifier.dart';
import 'image_scan_progress.dart';

class SkinAiAnalysisResultPanel extends StatelessWidget {
  const SkinAiAnalysisResultPanel({
    required this.prediction,
    required this.isAnalyzing,
    required this.analysisError,
    required this.analysisStage,
    required this.imagePath,
    required this.bodyArea,
    required this.duration,
    required this.symptoms,
    required this.isSaving,
    required this.onSave,
    required this.onRetry,
    super.key,
  });

  final SkinPrediction? prediction;
  final bool isAnalyzing;
  final String? analysisError;
  final String? analysisStage;
  final String? imagePath;
  final String bodyArea;
  final String duration;
  final Map<String, bool> symptoms;
  final bool isSaving;
  final VoidCallback onSave;
  final VoidCallback onRetry;

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
          'SkinAI Assist image analysis',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'SkinAI Assist considers the photo with your selected body area, '
          'symptoms, and duration to suggest up to five possible matches. '
          'The analysis is not clinically validated for every skin '
          'condition. The list is not '
          'complete, and the scores are experimental visual-match estimates, '
          'not calibrated probabilities or diagnoses.',
        ),
        const SizedBox(height: 16),
        const Card(
          child: ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('Research prototype only'),
            subtitle: Text(
              'This prototype is not clinically validated. A low score, '
              'healthy-looking result, or other-condition result does not '
              'rule out cancer. Consult a healthcare professional about '
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
                    result.isNonSkin
                        ? 'Likely non-skin image'
                        : result.isUncertain
                            ? 'Uncertain result'
                            : 'Possible image and questionnaire matches',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    result.isNonSkin
                        ? 'The model did not identify a clear human-skin image. '
                            'This experimental result can be wrong; retake the '
                            'photo if you intended to capture skin.'
                        : result.isUncertain
                            ? 'The model could not confidently match this photo '
                                'to a listed class. This is not a reassuring '
                                'result. Have a new, changing, bleeding, or '
                                'concerning area assessed by a healthcare professional.'
                            : 'These are candidates based on the image and your answers, not a complete list. A low score or healthy-looking result cannot rule out cancer.',
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'AI-generated visual-match scores (0–100), not medical probabilities',
                  ),
                  const SizedBox(height: 12),
                  _buildQuestionnaireContext(context),
                  const SizedBox(height: 12),
                  for (final item in result.matches) ...[
                    Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.conditionName,
                                maxLines: 2,
                                overflow:
                                    TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                                '${(item.score * 100).round()}%'),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: item.score
                              .clamp(0.0, 1.0)
                              .toDouble(),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.categoryLabel,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
          const Text(
            'SkinAI Assist sends the compressed photo and your body-area, symptom, and duration answers over the internet for analysis. The app does not save the photo to Firebase or visit history.',
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
        if (!isAnalyzing &&
            imagePath != null &&
            (prediction != null ||
                analysisError != null)) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: isSaving ? null : onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry analysis'),
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

  Widget _buildQuestionnaireContext(BuildContext context) {
    String answer(String key) =>
        symptoms[key] == true ? 'Yes' : 'No';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Questionnaire context used',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Area: $bodyArea · Duration: $duration\n'
            'Itching: ${answer('itching')} · Pain: ${answer('pain')} · '
            'Swelling: ${answer('swelling')} · Recent change: '
            '${answer('recentChange')}',
          ),
        ],
      ),
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
        'analysis',
        'SkinAI Assist analysis',
        'Analyzing the photo with your questionnaire answers'
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
                'Image quality is checked on this device. When you continue, SkinAI Assist sends a compressed photo and your answers over the internet for analysis. The app does not save the photo to Firebase or visit history.'),
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

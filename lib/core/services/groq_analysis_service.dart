import 'dart:io';

import 'groq_skin_classifier.dart';
import 'image_quality_checker.dart';

/// Runs local image-quality checks followed by direct vision-model analysis.
///
/// Groq's general vision model returns experimental visual-match scores, not
/// calibrated probabilities or medical findings.
class GroqAnalysisService {
  const GroqAnalysisService({
    ImageQualityChecker qualityChecker =
        const ImageQualityChecker(),
    GroqSkinClassifier classifier =
        const GroqSkinClassifier(),
  })  : _qualityChecker = qualityChecker,
        _classifier = classifier;

  final ImageQualityChecker _qualityChecker;
  final GroqSkinClassifier _classifier;

  Future<SkinPrediction> analyze(
    File photo, {
    required String bodyArea,
    required String duration,
    required Map<String, bool> symptoms,
    void Function(String stage)? onStage,
  }) async {
    onStage?.call('quality');
    final quality = await _qualityChecker.inspect(photo);
    if (!quality.isAcceptable) {
      throw const FormatException(
        'This photo did not pass the basic image-quality checks. Retake it with better focus and lighting.',
      );
    }

    onStage?.call('analysis');
    final prediction = await _classifier.classify(
      photo,
      bodyArea: bodyArea,
      duration: duration,
      symptoms: symptoms,
    );
    onStage?.call('complete');
    return prediction;
  }
}

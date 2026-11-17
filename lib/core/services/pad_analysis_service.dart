import 'dart:io';

import 'image_quality_checker.dart';
import 'skin_pixel_gate.dart';
import 'skin_classifier.dart';

/// Coordinates the image-quality gate and the PAD-UFES lesion classifier.
///
/// PAD-UFES contains lesion images only. The pixel gate is experimental and
/// its output must not be treated as reliable skin verification.
class PadAnalysisService {
  const PadAnalysisService({
    ImageQualityChecker qualityChecker =
        const ImageQualityChecker(),
    SkinPixelGate skinGate = const SkinPixelGate(),
    SkinClassifier classifier = const SkinClassifier(),
  })  : _qualityChecker = qualityChecker,
        _skinGate = skinGate,
        _classifier = classifier;

  final ImageQualityChecker _qualityChecker;
  final SkinPixelGate _skinGate;
  final SkinClassifier _classifier;

  Future<SkinPrediction> analyze(
    File photo, {
    void Function(String stage)? onStage,
  }) async {
    onStage?.call('quality');
    final quality = await _qualityChecker.inspect(photo);
    if (!quality.isAcceptable) {
      throw const FormatException(
        'This photo did not pass the basic image-quality checks. Retake it with better focus and lighting.',
      );
    }

    onStage?.call('skin');
    final skinCheck = await _skinGate.inspect(photo);
    if (!skinCheck.containsEnoughSkin) {
      throw NoSkinDetectedException(skinCheck);
    }

    onStage?.call('classifier');
    final prediction = await _classifier.classify(photo);
    onStage?.call('complete');
    return prediction;
  }
}

import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class SkinClassScore {
  const SkinClassScore(
      {required this.label, required this.score});

  final String label;
  final double score;
}

class SkinPrediction {
  const SkinPrediction({required this.scores});

  final List<SkinClassScore> scores;

  SkinClassScore get topMatch => scores.first;
}

/// Local, experimental PAD-UFES-20 image classification.
///
/// Model scores are uncalibrated and must not be treated as diagnosis or risk.
class SkinClassifier {
  const SkinClassifier();

  static const _modelAsset =
      'assets/models/skinai_mobilenetv3_pad_ufes20.tflite';
  static const _labels = [
    'Actinic keratosis (ACK)',
    'Basal cell carcinoma (BCC)',
    'Melanoma (MEL)',
    'Nevus (NEV)',
    'Squamous cell carcinoma (SCC)',
    'Seborrheic keratosis (SEK)',
  ];
  static const _inputSize = 224;

  Future<SkinPrediction> classify(File photo) async {
    final bytes = await photo.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException(
          'The selected photo could not be decoded.');
    }

    final oriented = img.bakeOrientation(decoded);
    final resized = img.copyResize(
      oriented,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    // The exported model includes MobileNetV3's input preprocessing and
    // expects RGB float32 pixel values in the 0–255 range.
    final input = [
      List.generate(
        _inputSize,
        (y) => List.generate(
          _inputSize,
          (x) {
            final pixel = resized.getPixel(x, y);
            return [
              pixel.r.toDouble(),
              pixel.g.toDouble(),
              pixel.b.toDouble(),
            ];
          },
        ),
      ),
    ];
    final output = [List<double>.filled(_labels.length, 0)];

    final interpreter =
        await Interpreter.fromAsset(_modelAsset);
    try {
      interpreter.run(input, output);
    } finally {
      interpreter.close();
    }

    final scores = output.first
        .asMap()
        .entries
        .map(
          (entry) => SkinClassScore(
            label: _labels[entry.key],
            score: entry.value,
          ),
        )
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return SkinPrediction(scores: scores);
  }
}

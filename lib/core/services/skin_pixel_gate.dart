import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class SkinGateResult {
  const SkinGateResult({
    required this.skinPixelFraction,
    required this.minimumFraction,
  });

  final double skinPixelFraction;
  final double minimumFraction;

  bool get containsEnoughSkin =>
      skinPixelFraction >= minimumFraction;
}

class NoSkinDetectedException implements Exception {
  const NoSkinDetectedException(this.result);

  final SkinGateResult result;
}

/// Experimental pixel-colour gate trained on the UCI Skin Segmentation data.
///
/// It has no spatial context, and its image-level area cutoff is not validated.
class SkinPixelGate {
  const SkinPixelGate({this.minimumSkinFraction = 0.01});

  static const _modelAsset =
      'assets/models/skin_pixel_gate.tflite';
  static const _sampleSide = 32;
  static const _pixelThreshold = 0.5;

  final double minimumSkinFraction;

  Future<SkinGateResult> inspect(File photo) async {
    final bytes = await photo.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException(
        'The selected photo could not be decoded for the skin check.',
      );
    }

    final oriented = img.bakeOrientation(decoded);
    final sampled = img.copyResize(
      oriented,
      width: _sampleSide,
      height: _sampleSide,
      interpolation: img.Interpolation.linear,
    );
    final pixelCount = _sampleSide * _sampleSide;
    final input = List.generate(pixelCount, (index) {
      final pixel = sampled.getPixel(
          index % _sampleSide, index ~/ _sampleSide);
      // UCI's feature order is B, G, R and training normalized to [0, 1].
      return [
        pixel.b.toDouble() / 255.0,
        pixel.g.toDouble() / 255.0,
        pixel.r.toDouble() / 255.0,
      ];
    });
    final output = List.generate(
      pixelCount,
      (_) => List<double>.filled(1, 0),
    );

    final interpreter =
        await Interpreter.fromAsset(_modelAsset);
    try {
      interpreter.resizeInputTensor(0, [pixelCount, 3]);
      interpreter.allocateTensors();
      interpreter.run(input, output);
    } finally {
      interpreter.close();
    }

    final predictedSkinPixels = output
        .where((pixel) => pixel.first >= _pixelThreshold)
        .length;
    return SkinGateResult(
      skinPixelFraction: predictedSkinPixels / pixelCount,
      minimumFraction: minimumSkinFraction,
    );
  }
}

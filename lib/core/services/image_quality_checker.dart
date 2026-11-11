import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class ImageQualityReport {
  const ImageQualityReport({
    required this.width,
    required this.height,
    required this.meanBrightness,
    required this.blurScore,
    required this.issues,
  });

  final int width;
  final int height;
  final double meanBrightness;
  final double blurScore;
  final List<String> issues;

  bool get isAcceptable => issues.isEmpty;

  String get message => isAcceptable
      ? 'The photo passed basic lighting, resolution, and focus checks.'
      : 'Image quality is too low. ${issues.join(' ')} Please retake under better lighting and keep the camera steady.';
}

class ImageQualityChecker {
  const ImageQualityChecker();

  Future<ImageQualityReport> inspect(File file) async {
    final bytes = await file.readAsBytes();
    final metrics = await compute(_inspectImage, bytes);

    return ImageQualityReport(
      width: metrics['width'] as int,
      height: metrics['height'] as int,
      meanBrightness: metrics['meanBrightness'] as double,
      blurScore: metrics['blurScore'] as double,
      issues: (metrics['issues'] as List).cast<String>(),
    );
  }
}

Map<String, Object> _inspectImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return {
      'width': 0,
      'height': 0,
      'meanBrightness': 0.0,
      'blurScore': 0.0,
      'issues': ['The image could not be read.'],
    };
  }

  const sampleSize = 96;
  final luma =
      List<double>.filled(sampleSize * sampleSize, 0);
  var totalBrightness = 0.0;
  var nearlyBlackPixels = 0;
  var clippedWhitePixels = 0;

  for (var y = 0; y < sampleSize; y++) {
    final sourceY =
        ((y + 0.5) * decoded.height / sampleSize)
            .floor()
            .clamp(0, decoded.height - 1);
    for (var x = 0; x < sampleSize; x++) {
      final sourceX =
          ((x + 0.5) * decoded.width / sampleSize)
              .floor()
              .clamp(0, decoded.width - 1);
      final pixel = decoded.getPixel(sourceX, sourceY);
      final value = 0.299 * pixel.r +
          0.587 * pixel.g +
          0.114 * pixel.b;
      luma[y * sampleSize + x] = value;
      totalBrightness += value;
      if (value < 12) nearlyBlackPixels++;
      if (value > 250) clippedWhitePixels++;
    }
  }

  final sampleCount = luma.length;
  final meanBrightness = totalBrightness / sampleCount;
  final nearlyBlackRatio = nearlyBlackPixels / sampleCount;
  final clippedWhiteRatio =
      clippedWhitePixels / sampleCount;

  var laplacianSum = 0.0;
  var laplacianSquareSum = 0.0;
  var laplacianCount = 0;
  for (var y = 1; y < sampleSize - 1; y++) {
    for (var x = 1; x < sampleSize - 1; x++) {
      final index = y * sampleSize + x;
      final laplacian = 4 * luma[index] -
          luma[index - 1] -
          luma[index + 1] -
          luma[index - sampleSize] -
          luma[index + sampleSize];
      laplacianSum += laplacian;
      laplacianSquareSum += laplacian * laplacian;
      laplacianCount++;
    }
  }
  final laplacianMean = laplacianSum / laplacianCount;
  final blurScore = laplacianSquareSum / laplacianCount -
      laplacianMean * laplacianMean;

  final issues = <String>[];
  if (decoded.width < 512 || decoded.height < 512) {
    issues.add(
        'Use an image at least 512 pixels wide and tall.');
  }
  // Avoid using average brightness as a threshold: dark skin can be properly
  // exposed while having a lower average luma than light skin.
  if (nearlyBlackRatio > 0.8) {
    issues.add('The photo looks too dark.');
  } else if (clippedWhiteRatio > 0.8) {
    issues.add('The photo looks overexposed.');
  }
  if (blurScore < 18) {
    issues.add('The image may be out of focus.');
  }

  return {
    'width': decoded.width,
    'height': decoded.height,
    'meanBrightness': meanBrightness,
    'blurScore': blurScore,
    'issues': issues,
  };
}

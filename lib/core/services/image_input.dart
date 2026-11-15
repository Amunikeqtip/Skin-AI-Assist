import 'dart:io';

import 'package:image/image.dart' as img;

const modelInputSize = 224;

/// RGB float tensor in the 0–255 range, matching MobileNetV3 models that
/// include their own preprocessing.
Future<List<List<List<List<double>>>>> rgbTensorForModel(File photo) async {
  final bytes = await photo.readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('The selected photo could not be decoded.');
  }

  final oriented = img.bakeOrientation(decoded);
  final resized = img.copyResize(
    oriented,
    width: modelInputSize,
    height: modelInputSize,
    interpolation: img.Interpolation.average,
  );

  return [
    List.generate(
      modelInputSize,
      (y) => List.generate(modelInputSize, (x) {
        final pixel = resized.getPixel(x, y);
        return [pixel.r.toDouble(), pixel.g.toDouble(), pixel.b.toDouble()];
      }),
    ),
  ];
}

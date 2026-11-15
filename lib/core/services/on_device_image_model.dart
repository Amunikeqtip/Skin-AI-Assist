import 'dart:io';

import 'package:tflite_flutter/tflite_flutter.dart';

import 'class_score.dart';
import 'image_input.dart';

class OnDeviceImageModel {
  const OnDeviceImageModel({
    required this.modelAsset,
    required this.labels,
  });

  final String modelAsset;
  final List<String> labels;

  Future<List<ClassScore>> classify(File photo) async {
    final input = await rgbTensorForModel(photo);
    final output = [List<double>.filled(labels.length, 0)];
    final interpreter = await Interpreter.fromAsset(modelAsset);
    try {
      interpreter.run(input, output);
    } finally {
      interpreter.close();
    }
    return rankScores(labels, output.first);
  }
}

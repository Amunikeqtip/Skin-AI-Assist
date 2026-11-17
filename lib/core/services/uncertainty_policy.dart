import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Temperature and confidence cutoff frozen from the validation split.
///
/// The policy is ignored unless the asset exists, is marked validated, and
/// matches the model file the classifier loads.
class UncertaintyPolicy {
  const UncertaintyPolicy({
    required this.modelAsset,
    required this.temperature,
    required this.minimumConfidence,
  });

  final String modelAsset;
  final double temperature;
  final double minimumConfidence;

  static const assetPath = 'assets/models/uncertainty_policy.json';

  static Future<UncertaintyPolicy?> load(
    String modelAsset, {
    AssetBundle? bundle,
  }) async {
    final String raw;
    try {
      raw = await (bundle ?? rootBundle).loadString(assetPath);
    } on FlutterError {
      return null;
    }
    return parse(raw, modelAsset);
  }

  static UncertaintyPolicy? parse(String raw, String modelAsset) {
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic>) return null;
    final temperature = json['temperature'];
    final minimum = json['minimum_confidence'];
    if (json['validated'] != true ||
        json['model_asset'] != modelAsset ||
        temperature is! num ||
        minimum is! num ||
        temperature <= 0) {
      return null;
    }
    return UncertaintyPolicy(
      modelAsset: modelAsset,
      temperature: temperature.toDouble(),
      minimumConfidence: minimum.toDouble(),
    );
  }

  List<double> scale(List<double> probabilities) {
    final logits = [
      for (final value in probabilities)
        math.log(math.max(value, 1e-12)) / temperature,
    ];
    final maxLogit = logits.reduce(math.max);
    final exps = [for (final value in logits) math.exp(value - maxLogit)];
    final total = exps.fold<double>(0, (sum, value) => sum + value);
    return [for (final value in exps) value / total];
  }

  bool isUncertain(double topScore) => topScore < minimumConfidence;
}

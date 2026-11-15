import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'analysis_policy.dart';
import 'class_score.dart';
import 'on_device_image_model.dart';
import 'skin_classifier.dart';

class SkinAnalysis {
  const SkinAnalysis({
    required this.skinGateInstalled,
    required this.skinGate,
    required this.skinPolicy,
    required this.router,
    required this.routerPolicy,
    required this.lesionClassifier,
  });

  final bool skinGateInstalled;
  final OnDeviceImageModel? skinGate;
  final ModelPolicy skinPolicy;
  final OnDeviceImageModel? router;
  final ModelPolicy routerPolicy;
  final SkinClassifier lesionClassifier;

  static Future<SkinAnalysis> load() async {
    final skinGate = await OnDeviceModelLoader.tryLoad(
      modelAsset: 'assets/models/skin_gate.tflite',
      labelsAsset: 'assets/models/skin_gate_labels.json',
    );
    final router = await OnDeviceModelLoader.tryLoad(
      modelAsset: 'assets/models/coarse_router.tflite',
      labelsAsset:
          'assets/models/coarse_router_labels.json',
    );
    return SkinAnalysis(
      skinGateInstalled: skinGate != null,
      skinGate: skinGate,
      skinPolicy: await ModelPolicyLoader.tryLoad(
        'assets/models/skin_gate_policy.json',
        'minimum_skin_score',
      ),
      router: router,
      routerPolicy: await ModelPolicyLoader.tryLoad(
        'assets/models/coarse_router_policy.json',
        'minimum_margin',
      ),
      lesionClassifier: const SkinClassifier(),
    );
  }

  Future<AnalysisDecision> analyze(File photo) async {
    final skinActive =
        skinGate != null && skinPolicy.isActive;
    final skinScores =
        skinActive ? await skinGate!.classify(photo) : null;
    final pastSkin = !skinActive ||
        _clearsSkinGate(skinScores, skinPolicy);

    List<ClassScore>? routerScores;
    if (pastSkin && router != null) {
      routerScores = await router!.classify(photo);
    }

    List<ClassScore>? lesionScores;
    if (pastSkin &&
        shouldRunLesionModel(
          skinGateActive: skinActive,
          skinScores: skinScores,
          skinPolicy: skinPolicy,
          routerScores: routerScores,
          routerPolicy: routerPolicy,
        )) {
      lesionScores =
          (await lesionClassifier.classify(photo)).scores;
    }

    return decideAnalysis(
      skinGateInstalled: skinGateInstalled,
      skinGateActive: skinActive,
      skinScores: skinScores,
      skinPolicy: skinPolicy,
      routerScores: routerScores,
      routerPolicy: routerPolicy,
      lesionScores: lesionScores,
    );
  }
}

bool _clearsSkinGate(
    List<ClassScore>? scores, ModelPolicy policy) {
  final skin =
      scores == null ? null : scoreForLabel(scores, 'skin');
  if (skin == null) {
    throw const FormatException(
        'The skin-check model has no "skin" score.');
  }
  return skin >= policy.threshold!;
}

class OnDeviceModelLoader {
  const OnDeviceModelLoader._();

  static Future<OnDeviceImageModel?> tryLoad({
    required String modelAsset,
    required String labelsAsset,
  }) async {
    try {
      final raw = await rootBundle.loadString(labelsAsset);
      await rootBundle.load(modelAsset);
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) {
        throw FormatException(
          '$labelsAsset must be a non-empty JSON list of labels.',
        );
      }
      return OnDeviceImageModel(
        modelAsset: modelAsset,
        labels: decoded
            .map((label) => label.toString())
            .toList(),
      );
    } on FlutterError catch (error) {
      if (error.message.contains('Unable to load asset')) {
        return null;
      }
      rethrow;
    }
  }
}

class ModelPolicyLoader {
  const ModelPolicyLoader._();

  static Future<ModelPolicy> tryLoad(
      String asset, String valueKey) async {
    try {
      final decoded =
          jsonDecode(await rootBundle.loadString(asset));
      if (decoded is! Map) {
        return const ModelPolicy.inactive();
      }
      final validated = decoded['validated'] == true;
      final value = decoded[valueKey];
      if (!validated) return const ModelPolicy.inactive();
      if (value is! num) {
        throw FormatException(
          '$asset sets validated to true without a numeric $valueKey.',
        );
      }
      return ModelPolicy(
          validated: true, threshold: value.toDouble());
    } on FlutterError catch (error) {
      if (error.message.contains('Unable to load asset')) {
        return const ModelPolicy.inactive();
      }
      rethrow;
    }
  }
}

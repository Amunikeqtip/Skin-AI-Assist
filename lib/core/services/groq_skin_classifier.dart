import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;

const _groqApiKey = String.fromEnvironment('GROQ_API_KEY');
const _groqModel = 'qwen/qwen3.8-27b';

const _matchCategoryValues = [
  'PAD_UFES_20',
  'MSLD_V2',
  'OTHER_SKIN_CONDITION',
  'NON_SKIN',
  'UNCERTAIN',
];

const _matchCategories = {
  'PAD_UFES_20',
  'MSLD_V2',
  'OTHER_SKIN_CONDITION',
  'NON_SKIN',
  'UNCERTAIN',
};

const _systemPrompt =
    'You are an experimental visual matching component in a non-clinical '
    'skin screening prototype. You are not a medical professional and must '
    'not diagnose, estimate cancer risk, recommend treatment, or reassure '
    'the user that cancer is absent. Use the image as primary evidence. '
    'Consider the user\'s selected body area, symptom answers, and duration '
    'only as supplementary context; do not let them override contradictory '
    'visual evidence. Return up to five plausible visual candidates, '
    'including common conditions that are not in the project\'s datasets '
    'when appropriate. Known project categories are PAD_UFES_20 (actinic '
    'keratosis, basal cell carcinoma, melanoma, nevus, squamous cell '
    'carcinoma, seborrheic keratosis), MSLD_V2 (healthy-looking skin, '
    'mpox, chickenpox, measles, cowpox, hand-foot-and-mouth disease), '
    'NON_SKIN, and UNCERTAIN. Use OTHER_SKIN_CONDITION for any named '
    'condition outside those dataset categories; this does not mean that '
    'the app has training data for it. Never claim that the list is '
    'complete or that a condition has been ruled out. If no skin is visible, '
    'mark likely_non_skin and return a NON_SKIN match. If the photo or '
    'evidence is unclear, mark uncertain and include an UNCERTAIN match '
    'instead of forcing a condition. Give each candidate an independent '
    'subjective visual-match score from 0 to 100; these are not calibrated '
    'probabilities, must not be described as probabilities, and do not need '
    'to sum to 100. Do not claim certainty from the answers or image.';

const _responseSchema = {
  'type': 'object',
  'properties': {
    'image_assessment': {
      'type': 'string',
      'enum': [
        'likely_skin',
        'likely_non_skin',
        'uncertain'
      ],
    },
    'matches': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'condition_name': {'type': 'string'},
          'category': {
            'type': 'string',
            'enum': _matchCategoryValues,
          },
          'match_score_percent': {'type': 'integer'},
        },
        'required': [
          'condition_name',
          'category',
          'match_score_percent',
        ],
        'additionalProperties': false,
      },
    },
  },
  'required': ['image_assessment', 'matches'],
  'additionalProperties': false,
};

class SkinConditionMatch {
  const SkinConditionMatch({
    required this.conditionName,
    required this.category,
    required this.score,
  });

  final String conditionName;
  final String category;

  /// Model-generated visual-match score from 0 to 1, not a probability.
  final double score;

  String get categoryLabel => switch (category) {
        'PAD_UFES_20' =>
          'PAD-UFES-20 label family (reference only)',
        'MSLD_V2' =>
          'MSLD v2.0 label family (reference only)',
        'OTHER_SKIN_CONDITION' =>
          'Other unvalidated possibility',
        'NON_SKIN' => 'Non-skin image',
        _ => 'Uncertain or unrecognized',
      };
}

class SkinPrediction {
  const SkinPrediction({
    required this.matches,
    required this.imageAssessment,
    required this.model,
  });

  final List<SkinConditionMatch> matches;
  final String imageAssessment;
  final String model;

  bool get isUncertain => imageAssessment == 'uncertain';
  bool get isNonSkin =>
      imageAssessment == 'likely_non_skin';

  SkinConditionMatch get topMatch => matches.first;
}

/// Sends a resized temporary image and questionnaire answers directly to Groq.
/// The API key is supplied at build time and is extractable from a distributed
/// app, so this direct integration is for a private prototype only.
class GroqSkinClassifier {
  const GroqSkinClassifier();

  static const _maxUploadBytes = 5 * 1024 * 1024;

  Future<SkinPrediction> classify(
    File photo, {
    required String bodyArea,
    required String duration,
    required Map<String, bool> symptoms,
  }) async {
    final sourceBytes = await photo.readAsBytes();
    final compressedBytes =
        await compute(_compressForGroq, sourceBytes);
    if (compressedBytes.length > _maxUploadBytes) {
      throw const FormatException(
        'The photo is too large to send for analysis. Choose a smaller image.',
      );
    }

    if (_groqApiKey.isEmpty) {
      throw const FormatException(
        'Groq is not configured. Run the app with '
        '--dart-define=GROQ_API_KEY=your_key.',
      );
    }

    final questionnaire = {
      'selected_body_area': bodyArea,
      'duration': duration,
      'symptoms': {
        'itching': symptoms['itching'] ?? false,
        'pain': symptoms['pain'] ?? false,
        'swelling': symptoms['swelling'] ?? false,
        'recent_change': symptoms['recentChange'] ?? false,
      },
    };
    final response = await http
        .post(
          Uri.https(
            'api.groq.com',
            '/openai/v1/chat/completions',
          ),
          headers: {
            'Authorization': 'Bearer $_groqApiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': _groqModel,
            'temperature': 0,
            'max_completion_tokens': 700,
            'response_format': {
              'type': 'json_schema',
              'json_schema': {
                'name': 'skinai_visual_match_scores',
                'strict': true,
                'schema': _responseSchema,
              },
            },
            'messages': [
              {'role': 'system', 'content': _systemPrompt},
              {
                'role': 'user',
                'content': [
                  {
                    'type': 'text',
                    'text': 'Review the image and this user-reported '
                        'questionnaire context. Use the answers as supporting '
                        'context, not ground truth. Return up to five '
                        'plausible candidate matches and the required image '
                        'assessment. Questionnaire context: '
                        '${jsonEncode(questionnaire)}',
                  },
                  {
                    'type': 'image_url',
                    'image_url': {
                      'url': 'data:image/jpeg;base64,'
                          '${base64Encode(compressedBytes)}',
                    },
                  },
                ],
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw HttpException(
        'Groq image analysis failed (HTTP ${response.statusCode}).',
      );
    }

    final envelope = jsonDecode(response.body);
    if (envelope is! Map || envelope['choices'] is! List) {
      throw const FormatException(
        'Groq returned an invalid response.',
      );
    }
    final choices = envelope['choices'] as List;
    if (choices.isEmpty || choices.first is! Map) {
      throw const FormatException(
        'Groq returned an empty response.',
      );
    }
    final message = choices.first['message'];
    if (message is! Map || message['content'] is! String) {
      throw const FormatException(
        'Groq returned an unreadable analysis result.',
      );
    }
    final data = jsonDecode(message['content'] as String);
    if (data is! Map) {
      throw const FormatException(
        'Groq returned an invalid analysis result.',
      );
    }
    final result = Map<String, dynamic>.from(data);
    final rawMatches = result['matches'];
    if (rawMatches is! List ||
        rawMatches.isEmpty ||
        rawMatches.length > 5) {
      throw const FormatException(
        'The Groq model returned an invalid candidate list.',
      );
    }

    final matches = <SkinConditionMatch>[];
    for (final rawMatch in rawMatches) {
      if (rawMatch is! Map) {
        throw const FormatException(
          'The Groq model returned an invalid candidate.',
        );
      }
      final match = Map<String, dynamic>.from(rawMatch);
      final conditionName = match['condition_name'];
      final category = match['category'];
      final score = match['match_score_percent'];
      if (conditionName is! String ||
          conditionName.trim().isEmpty ||
          category is! String ||
          !_matchCategories.contains(category) ||
          score is! num ||
          !score.isFinite ||
          score < 0 ||
          score > 100) {
        throw const FormatException(
          'The Groq model returned an invalid candidate match.',
        );
      }
      matches.add(SkinConditionMatch(
        conditionName: conditionName,
        category: category,
        score: score / 100,
      ));
    }
    matches.sort((a, b) => b.score.compareTo(a.score));

    final assessment = result['image_assessment'];
    if (assessment is! String ||
        !const {
          'likely_skin',
          'likely_non_skin',
          'uncertain'
        }.contains(assessment)) {
      throw const FormatException(
        'The Groq model returned an unsupported image assessment.',
      );
    }
    final model = envelope['model'] is String
        ? envelope['model'] as String
        : _groqModel;

    return SkinPrediction(
      matches: matches,
      imageAssessment: assessment,
      model: model,
    );
  }
}

Uint8List _compressForGroq(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException(
        'The selected photo could not be decoded.');
  }

  final oriented = img.bakeOrientation(decoded);
  final resized = img.copyResize(
    oriented,
    width: oriented.width > 1280 ? 1280 : oriented.width,
    height: oriented.height > 1280 ? 1280 : oriented.height,
    maintainAspect: true,
    interpolation: img.Interpolation.linear,
  );
  return Uint8List.fromList(
      img.encodeJpg(resized, quality: 84));
}

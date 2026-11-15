import 'class_score.dart';

/// A threshold is active only after it has been chosen on validation data
/// and frozen. A number chosen by hand does not qualify.
class ModelPolicy {
  const ModelPolicy.inactive()
      : validated = false,
        threshold = null;

  const ModelPolicy({required this.validated, required this.threshold});

  final bool validated;
  final double? threshold;

  bool get isActive => validated && threshold != null;
}

enum AnalysisOutcome { notSkin, uncertain, educationalGroup, lesion }

class AnalysisDecision {
  const AnalysisDecision({
    required this.outcome,
    required this.headline,
    required this.detail,
    this.lookAlikes = const [],
    this.scores = const [],
    this.scoreCaption,
    this.savedPrediction,
    this.savedScore,
    this.skinCheckNote,
  });

  final AnalysisOutcome outcome;
  final String headline;
  final String detail;
  final List<String> lookAlikes;
  final List<ClassScore> scores;
  final String? scoreCaption;
  final String? savedPrediction;
  final double? savedScore;
  final String? skinCheckNote;
}

const photoLimitNote =
    'This app cannot identify bacterial infections, MRSA, cold sores, or shingles from a photo. A spreading painful red area, fever, a blistering rash, eye involvement, or a changing dark spot needs a clinician or urgent care.';

const _scoreCaption =
    'Uncalibrated scores. These are not probabilities or a diagnosis.';

const _groupOrder = [
  'rash',
  'acne_rosacea',
  'white_patches',
  'spot_or_growth',
];

String groupTitle(String id) {
  return switch (id) {
    'rash' => 'Rash-like change',
    'acne_rosacea' => 'Acne or rosacea-like change',
    'white_patches' => 'White-patch change',
    'spot_or_growth' => 'Spot or growth',
    _ => id,
  };
}

bool shouldRunLesionModel({
  required bool skinGateActive,
  required List<ClassScore>? skinScores,
  required ModelPolicy skinPolicy,
  required List<ClassScore>? routerScores,
  required ModelPolicy routerPolicy,
}) {
  if (skinGateActive && _skinScore(skinScores) < skinPolicy.threshold!) {
    return false;
  }
  if (routerScores == null) return true;
  final ranked = rankedCopy(routerScores);
  if (ranked.isEmpty) {
    throw const FormatException('The group router returned no scores.');
  }
  if (_marginRejects(ranked, routerPolicy)) return false;
  return ranked.first.label == 'spot_or_growth';
}

AnalysisDecision decideAnalysis({
  required bool skinGateInstalled,
  required bool skinGateActive,
  required List<ClassScore>? skinScores,
  required ModelPolicy skinPolicy,
  required List<ClassScore>? routerScores,
  required ModelPolicy routerPolicy,
  required List<ClassScore>? lesionScores,
}) {
  final skinCheckNote = _skinCheckNote(
    skinGateInstalled: skinGateInstalled,
    skinGateActive: skinGateActive,
    skinScores: skinScores,
    skinPolicy: skinPolicy,
  );

  if (skinGateActive && _skinScore(skinScores) < skinPolicy.threshold!) {
    return AnalysisDecision(
      outcome: AnalysisOutcome.notSkin,
      headline: 'No condition name was assigned',
      detail:
          'The skin check fell below its frozen validation threshold, so no condition label is shown.',
      skinCheckNote: skinCheckNote,
    );
  }

  if (routerScores != null) {
    final ranked = rankedCopy(routerScores);
    if (ranked.isEmpty) {
      throw const FormatException('The group router returned no scores.');
    }
    if (_marginRejects(ranked, routerPolicy)) {
      return AnalysisDecision(
        outcome: AnalysisOutcome.uncertain,
        headline: 'No condition name was assigned',
        detail:
            'The two closest educational groups were closer than the frozen validation margin, so no label is shown.',
        skinCheckNote: skinCheckNote,
      );
    }

    final top = ranked.first.label;
    if (!_groupOrder.contains(top)) {
      return AnalysisDecision(
        outcome: AnalysisOutcome.uncertain,
        headline: 'No condition name was assigned',
        detail:
            'The group router returned a label this app does not show, so no condition name is displayed.',
        skinCheckNote: skinCheckNote,
      );
    }

    if (top == 'spot_or_growth' &&
        lesionScores != null &&
        lesionScores.isNotEmpty) {
      final lesion = rankedCopy(lesionScores);
      final best = lesion.first;
      return AnalysisDecision(
        outcome: AnalysisOutcome.lesion,
        headline: 'Closest dataset label: ${best.label}',
        detail:
            'The educational router placed this photo in the spot-or-growth group. The scores below are the separate six-class lesion model. They are uncalibrated and are not a diagnosis or a cancer rule-out.',
        lookAlikes: const [
          'Actinic keratosis, basal cell carcinoma, melanoma, nevus, squamous cell carcinoma, and seborrheic keratosis are the only lesion labels.',
          'A benign-looking label does not rule out cancer.',
        ],
        scores: lesion,
        scoreCaption: _scoreCaption,
        savedPrediction: best.label,
        savedScore: best.score,
        skinCheckNote: skinCheckNote,
      );
    }

    return _groupDecision(top, ranked, skinCheckNote);
  }

  if (lesionScores == null || lesionScores.isEmpty) {
    throw const FormatException(
      'The lesion model did not return scores for this photo.',
    );
  }

  final lesion = rankedCopy(lesionScores);
  final best = lesion.first;
  return AnalysisDecision(
    outcome: AnalysisOutcome.lesion,
    headline: 'Closest dataset label: ${best.label}',
    detail:
        'No group router is installed, so this photo was scored only by the six-class lesion model. Rash, acne, rosacea, and white-patch groups are not available. Scores are uncalibrated and are not a diagnosis.',
    lookAlikes: const [
      'This model always picks one of six PAD-UFES-20 lesion labels.',
      'A benign-looking label does not rule out cancer.',
    ],
    scores: lesion,
    scoreCaption: _scoreCaption,
    savedPrediction: best.label,
    savedScore: best.score,
    skinCheckNote: skinCheckNote,
  );
}

AnalysisDecision _groupDecision(
  String top,
  List<ClassScore> ranked,
  String skinCheckNote,
) {
  final copy = _groupCopy[top]!;
  return AnalysisDecision(
    outcome: AnalysisOutcome.educationalGroup,
    headline: groupTitle(top),
    detail: copy.detail,
    lookAlikes: copy.lookAlikes,
    scores: [
      for (final score in ranked)
        ClassScore(label: groupTitle(score.label), score: score.score),
    ],
    scoreCaption: _scoreCaption,
    savedPrediction: groupTitle(top),
    skinCheckNote: skinCheckNote,
  );
}

bool _marginRejects(List<ClassScore> ranked, ModelPolicy policy) {
  if (!policy.isActive) return false;
  final margin = topTwoMargin(ranked);
  if (margin == null) return false;
  return margin < policy.threshold!;
}

double _skinScore(List<ClassScore>? scores) {
  final skin = scores == null ? null : scoreForLabel(scores, 'skin');
  if (skin == null) {
    throw const FormatException('The skin-check model has no "skin" score.');
  }
  return skin;
}

String _skinCheckNote({
  required bool skinGateInstalled,
  required bool skinGateActive,
  required List<ClassScore>? skinScores,
  required ModelPolicy skinPolicy,
}) {
  if (!skinGateInstalled) {
    return 'No skin/non-skin model is installed, so skin content was not checked.';
  }
  if (!skinGateActive || !skinPolicy.isActive) {
    return 'A skin/non-skin model file is present, but it is not used until its validation threshold is frozen.';
  }
  if (_skinScore(skinScores) < skinPolicy.threshold!) {
    return 'The skin check fell below its frozen validation threshold.';
  }
  return 'The skin check cleared the frozen threshold. That does not identify a condition.';
}

class _GroupCopy {
  const _GroupCopy({required this.detail, required this.lookAlikes});

  final String detail;
  final List<String> lookAlikes;
}

const _groupCopy = {
  'rash': _GroupCopy(
    detail:
        'This educational group is for rash-like photos. Eczema, psoriasis, and contact irritation often look alike, and a picture cannot show what the skin touched.',
    lookAlikes: [
      'Eczema-like dry, itchy patches',
      'Psoriasis-like thick, scaly plaques',
      'Contact irritation, without identifying the cause',
    ],
  ),
  'acne_rosacea': _GroupCopy(
    detail:
        'This educational group is for acne-like and rosacea-like facial photos. Redness and bumps in this group overlap, and the photo is not a diagnosis.',
    lookAlikes: [
      'Acne-like clogged follicles, pimples, or cysts',
      'Rosacea-like facial redness and bumps',
    ],
  ),
  'white_patches': _GroupCopy(
    detail:
        'This educational group is for photos with vitiligo-like loss of color. Other kinds of pigment loss can look similar.',
    lookAlikes: [
      'Vitiligo-like white patches',
      'Other pigment loss that a photo cannot separate',
    ],
  ),
  'spot_or_growth': _GroupCopy(
    detail:
        'This educational group is for a spot or growth. The separate lesion model compares only six dataset labels and does not rule out cancer.',
    lookAlikes: [
      'The lesion labels are actinic keratosis, basal cell carcinoma, melanoma, nevus, squamous cell carcinoma, and seborrheic keratosis.',
    ],
  ),
};

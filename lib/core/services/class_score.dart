class ClassScore {
  const ClassScore({required this.label, required this.score});

  final String label;
  final double score;
}

List<ClassScore> rankScores(List<String> labels, List<double> values) {
  if (labels.length != values.length) {
    throw FormatException(
      'The model returned ${values.length} scores for ${labels.length} labels.',
    );
  }

  return [
    for (var index = 0; index < labels.length; index++)
      ClassScore(label: labels[index], score: values[index]),
  ]..sort((a, b) => b.score.compareTo(a.score));
}

double? scoreForLabel(List<ClassScore> scores, String label) {
  for (final score in scores) {
    if (score.label == label) return score.score;
  }
  return null;
}

double? topTwoMargin(List<ClassScore> ranked) {
  if (ranked.length < 2) return null;
  return ranked[0].score - ranked[1].score;
}

List<ClassScore> rankedCopy(List<ClassScore> scores) {
  return [...scores]..sort((a, b) => b.score.compareTo(a.score));
}

/// Encodes the scan questionnaire in the order used by
/// `ai_training/multimodal/schema.py`.
///
/// A null symptom means the dataset did not record it. The scan screen uses
/// false when the person leaves a box unchecked, which is "no", not unknown.
class MetadataFeatures {
  const MetadataFeatures._();

  static const bodySites = [
    'Face',
    'Neck',
    'Chest',
    'Back',
    'Arm',
    'Hand',
    'Leg',
    'Foot',
    'Other',
    'Unknown',
  ];
  static const symptoms = [
    'itch',
    'pain',
    'swelling',
    'changed'
  ];
  static const states = ['no', 'yes', 'unknown'];
  static const durations = [
    'Less than a week',
    '1\u20134 weeks',
    '1\u20136 months',
    'More than 6 months',
    'Not sure',
    'Unknown',
  ];

  static int get dimension =>
      bodySites.length +
      symptoms.length * states.length +
      durations.length;

  static List<double> encode({
    String? bodySite,
    bool? itch,
    bool? pain,
    bool? swelling,
    bool? changed,
    String? duration,
  }) {
    final values = <double>[];
    final site =
        bodySites.contains(bodySite) ? bodySite : 'Unknown';
    for (final name in bodySites) {
      values.add(name == site ? 1 : 0);
    }
    for (final present in [itch, pain, swelling, changed]) {
      final state = switch (present) {
        null => 'unknown',
        true => 'yes',
        false => 'no',
      };
      for (final name in states) {
        values.add(name == state ? 1 : 0);
      }
    }
    final durationName = durations.contains(duration)
        ? duration!
        : 'Unknown';
    for (final name in durations) {
      values.add(name == durationName ? 1 : 0);
    }
    return values;
  }
}

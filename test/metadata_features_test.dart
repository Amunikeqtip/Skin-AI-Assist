import 'package:flutter_test/flutter_test.dart';
import 'package:skinai_assist/core/services/metadata_features.dart';

void main() {
  test('metadata vector matches the training layout', () {
    expect(MetadataFeatures.dimension, 28);

    final unknown = MetadataFeatures.encode();
    expect(unknown[9], 1);
    expect(unknown[12], 1);
    expect(unknown[15], 1);
    expect(unknown[18], 1);
    expect(unknown[21], 1);
    expect(unknown[27], 1);
    expect(unknown.where((value) => value == 1).length, 6);

    final specified = MetadataFeatures.encode(
      bodySite: 'Face',
      itch: true,
      pain: false,
      swelling: null,
      changed: true,
      duration: 'Less than a week',
    );
    expect(specified[0], 1);
    expect(specified[11], 1);
    expect(specified[13], 1);
    expect(specified[18], 1);
    expect(specified[20], 1);
    expect(specified[22], 1);
    expect(
        specified.where((value) => value == 1).length, 6);
  });

  test(
      'an unrecognized body area is unknown, not a guessed site',
      () {
    final encoded =
        MetadataFeatures.encode(bodySite: 'Scalp');
    expect(encoded[9], 1);
    expect(encoded[8], 0);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:skinai_assist/core/services/uncertainty_policy.dart';

const _model = 'assets/models/skinai_pad_msld_8class.tflite';

void main() {
  test('ignores a policy that is not validated', () {
    const raw = '{"model_asset": "$_model", "temperature": 1.17, '
        '"minimum_confidence": null, "validated": false}';
    expect(UncertaintyPolicy.parse(raw, _model), isNull);
  });

  test('ignores a policy frozen for a different model', () {
    const raw = '{"model_asset": "assets/models/other.tflite", '
        '"temperature": 1.17, "minimum_confidence": 0.5, "validated": true}';
    expect(UncertaintyPolicy.parse(raw, _model), isNull);
  });

  test('temperature scaling keeps order and sums to one', () {
    const raw = '{"model_asset": "$_model", "temperature": 2.0, '
        '"minimum_confidence": 0.5, "validated": true}';
    final policy = UncertaintyPolicy.parse(raw, _model)!;
    final scaled = policy.scale([0.8, 0.15, 0.05]);

    expect(scaled.reduce((a, b) => a + b), closeTo(1, 1e-9));
    expect(scaled[0], greaterThan(scaled[1]));
    expect(scaled[0], lessThan(0.8));
    expect(policy.isUncertain(0.49), isTrue);
    expect(policy.isUncertain(0.5), isFalse);
  });
}

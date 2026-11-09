import 'package:hive_ce_flutter/hive_ce_flutter.dart';

class ScanRecord {
  const ScanRecord(
      {required this.date,
      required this.area,
      required this.prediction,
      required this.confidence,
      required this.risk});
  final DateTime date;
  final String area, prediction, risk;
  final double confidence;
  Map<String, dynamic> toMap() => {
        'date': date.toIso8601String(),
        'area': area,
        'prediction': prediction,
        'confidence': confidence,
        'risk': risk
      };
  static ScanRecord fromMap(Map m) => ScanRecord(
      date: DateTime.parse(m['date']),
      area: m['area'],
      prediction: m['prediction'],
      confidence: (m['confidence'] as num).toDouble(),
      risk: m['risk']);
}

class LocalScanStore {
  Box get _box => Hive.box('scans');
  List<ScanRecord> all() => _box.values
      .map((e) => ScanRecord.fromMap(Map.from(e)))
      .toList()
      .reversed
      .toList();
  Future<void> add(ScanRecord scan) =>
      _box.add(scan.toMap());
  Future<void> deleteAt(int index) => _box.deleteAt(index);
}

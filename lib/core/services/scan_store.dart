import 'package:hive_ce_flutter/hive_ce_flutter.dart';

class ScanRecord {
  const ScanRecord({
    required this.date,
    required this.area,
    this.symptoms = const {},
    this.duration = 'Not recorded',
    this.prediction,
    this.confidence,
    this.risk,
  });

  final DateTime date;
  final String area;
  final Map<String, bool> symptoms;
  final String duration;
  final String? prediction;
  final double? confidence;
  final String? risk;

  bool get isAnalyzed => prediction != null && risk != null;

  Map<String, dynamic> toMap() => {
        'date': date.toIso8601String(),
        'area': area,
        'symptoms': symptoms,
        'duration': duration,
        'prediction': prediction,
        'confidence': confidence,
        'risk': risk,
      };

  static ScanRecord fromMap(Map<dynamic, dynamic> map) {
    final storedSymptoms = map['symptoms'];

    return ScanRecord(
      date: DateTime.parse(map['date'] as String),
      area: map['area'] as String? ?? 'Not specified',
      symptoms: storedSymptoms is Map
          ? storedSymptoms.map(
              (key, value) =>
                  MapEntry(key.toString(), value == true),
            )
          : const {},
      duration:
          map['duration'] as String? ?? 'Not recorded',
      prediction: map['prediction'] as String?,
      confidence: (map['confidence'] as num?)?.toDouble(),
      risk: map['risk'] as String?,
    );
  }
}

class StoredScanRecord {
  const StoredScanRecord(
      {required this.key, required this.record});

  final dynamic key;
  final ScanRecord record;
}

class LocalScanStore {
  Box get _box => Hive.box('scans');

  List<StoredScanRecord> all() {
    final records = _box.keys
        .map(
          (key) => StoredScanRecord(
            key: key,
            record: ScanRecord.fromMap(
              Map<dynamic, dynamic>.from(
                  _box.get(key) as Map),
            ),
          ),
        )
        .toList()
        .reversed
        .toList();

    return records;
  }

  Future<void> add(ScanRecord scan) =>
      _box.add(scan.toMap());

  Future<void> delete(dynamic key) => _box.delete(key);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:skinai_assist/core/services/scan_store.dart';
void main(){group('ScanRecord',(){test('round trips metadata map',(){final scan=ScanRecord(date:DateTime(2026,1,2),area:'Arm',prediction:'Educational result',confidence:.8,risk:'Low');final copy=ScanRecord.fromMap(scan.toMap());expect(copy.area,'Arm');expect(copy.confidence,.8);expect(copy.risk,'Low');});});}

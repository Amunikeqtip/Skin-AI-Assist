import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/scan_store.dart';
import '../services/firebase_services.dart';

final localScanStoreProvider = Provider<LocalScanStore>(
  (ref) => LocalScanStore(),
);

final scanHistoryProvider = NotifierProvider<
    ScanHistoryNotifier, List<StoredScanRecord>>(
  ScanHistoryNotifier.new,
);

class ScanHistoryNotifier
    extends Notifier<List<StoredScanRecord>> {
  late LocalScanStore _store;

  @override
  List<StoredScanRecord> build() {
    _store = ref.watch(localScanStoreProvider);
    return _store.all();
  }

  Future<void> save(ScanRecord record) async {
    await _store.add(record);
    final saved = _store.all().first;
    await FirebaseCloudStore.instance
        .syncScan(
          saved.key.toString(),
          saved.record.toMap(),
        )
        .catchError((_) {});
    state = _store.all();
  }

  Future<void> delete(dynamic key) async {
    await _store.delete(key);
    await FirebaseCloudStore.instance
        .deleteScan(key.toString())
        .catchError((_) {});
    state = _store.all();
  }
}

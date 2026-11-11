import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/scan_store.dart';

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
    state = _store.all();
  }

  Future<void> delete(dynamic key) async {
    await _store.delete(key);
    state = _store.all();
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/scan_providers.dart';
import '../../../core/services/scan_store.dart';
import '../../../core/widgets/common.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    StoredScanRecord scan,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete visit?'),
        content: const Text(
          'This removes this visit and its questionnaire answers from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !context.mounted) return;
    await ref
        .read(scanHistoryProvider.notifier)
        .delete(scan.key);
  }

  void _showDetails(BuildContext context, ScanRecord scan) {
    final symptoms = scan.symptoms.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Visit details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Date: ${DateFormat.yMMMd().add_jm().format(scan.date.toLocal())}',
              ),
              const SizedBox(height: 8),
              Text('Body area: ${scan.area}'),
              const SizedBox(height: 8),
              Text('Duration: ${scan.duration}'),
              const SizedBox(height: 8),
              Text(
                symptoms.isEmpty
                    ? 'Reported symptoms: None selected'
                    : 'Reported symptoms: ${symptoms.join(', ')}',
              ),
              const SizedBox(height: 12),
              Text(
                scan.isAnalyzed
                    ? 'Prediction: ${scan.prediction} (${((scan.confidence ?? 0) * 100).round()}%)\nRisk: ${scan.risk}'
                    : 'No AI analysis was performed. No prediction or risk was assigned.',
              ),
              const SizedBox(height: 8),
              const Text(
                'This visit is for personal tracking only and is not a diagnosis.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scans = ref.watch(scanHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Scan history')),
      body: scans.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.history, size: 56),
                    const SizedBox(height: 14),
                    Text(
                      'Your history is empty',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Saved visits and questionnaires will show up here.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const NoticeBanner(),
                const SizedBox(height: 8),
                for (final item in scans)
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.spa_outlined),
                      ),
                      title: Text(item.record.prediction ??
                          'Not analyzed'),
                      subtitle: Text(
                        '${DateFormat.yMMMd().format(item.record.date.toLocal())} · '
                        '${item.record.area} · '
                        '${item.record.risk ?? 'Risk not assessed'}',
                      ),
                      onTap: () => _showDetails(
                          context, item.record),
                      trailing: IconButton(
                        tooltip: 'Delete visit',
                        onPressed: () =>
                            _delete(context, ref, item),
                        icon: const Icon(
                            Icons.delete_outline),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

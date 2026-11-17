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
    final colors = Theme.of(context).colorScheme;
    final formattedDate = DateFormat.yMMMd()
        .add_jm()
        .format(scan.date.toLocal());

    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: colors.surface,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 24,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight:
                MediaQuery.sizeOf(dialogContext).height *
                    .86,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                    20, 18, 12, 18),
                color: colors.primaryContainer,
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: colors.surface,
                      foregroundColor: colors.primary,
                      child: const Icon(Icons.spa_outlined),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Visit summary',
                            style: Theme.of(dialogContext)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                    fontWeight:
                                        FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(formattedDate),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close visit summary',
                      onPressed: () =>
                          Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Visit details',
                        style: Theme.of(dialogContext)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                fontWeight:
                                    FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _VisitInfoTile(
                              icon: Icons.place_outlined,
                              label: 'BODY AREA',
                              value: scan.area,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _VisitInfoTile(
                              icon: Icons.schedule_outlined,
                              label: 'DURATION',
                              value: scan.duration,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Symptoms reported',
                        style: Theme.of(dialogContext)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                fontWeight:
                                    FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      if (symptoms.isEmpty)
                        const Text('No symptoms selected')
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final symptom in symptoms)
                              Chip(
                                avatar: Icon(
                                  Icons
                                      .check_circle_outline,
                                  size: 17,
                                  color: colors.primary,
                                ),
                                label: Text(symptom),
                                visualDensity:
                                    VisualDensity.compact,
                              ),
                          ],
                        ),
                      const SizedBox(height: 20),
                      _VisitResultCard(scan: scan),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors
                              .surfaceContainerHighest,
                          borderRadius:
                              BorderRadius.circular(16),
                        ),
                        child: const Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline,
                                size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'For personal tracking only. This record is not a diagnosis and does not assess medical risk.',
                                style:
                                    TextStyle(height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    20, 0, 20, 18),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(dialogContext),
                    child: const Text('Close'),
                  ),
                ),
              ),
            ],
          ),
        ),
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

class _VisitInfoTile extends StatelessWidget {
  const _VisitInfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 105),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primary, size: 20),
          const SizedBox(height: 8),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(
                  letterSpacing: .7,
                  color: colors.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _VisitResultCard extends StatelessWidget {
  const _VisitResultCard({required this.scan});

  final ScanRecord scan;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasPrediction = scan.prediction != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            colors.primaryContainer.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.primary.withValues(alpha: .15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasPrediction
                    ? Icons.auto_awesome_outlined
                    : Icons.hourglass_empty_outlined,
                color: colors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Analysis result',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(
                          fontWeight: FontWeight.w700),
                ),
              ),
              if (hasPrediction)
                const Chip(
                  label: Text('Experimental'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            scan.prediction ?? 'No AI result saved',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (scan.confidence != null)
            Text(
              'Saved visual-match score: '
              '${(scan.confidence! * 100).round()}% '
              '(not a medical probability)',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else if (hasPrediction)
            Text(
              'A visual-match score was not saved with this visit.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (scan.risk != null) ...[
            const SizedBox(height: 6),
            Text('Risk assessment: ${scan.risk}'),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/foundation.dart'
    show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/scan_providers.dart';
import '../../../core/services/firebase_services.dart';
import '../../../core/services/follow_up_reminder_service.dart';
import '../../../core/widgets/common.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() =>
      _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const _routineItems = [
    (
      'Cleanse gently',
      'Choose products that feel comfortable on your skin.'
    ),
    (
      'Moisturize as needed',
      'Keep your routine simple and comfortable.'
    ),
    (
      'Protect from the sun',
      'Use shade, clothing, and sunscreen outdoors.'
    ),
  ];

  static const _dailyTips = [
    (
      title: 'Sun protection',
      message:
          'Shade, sun-protective clothing, and sunscreen can all help reduce UV exposure outdoors.',
    ),
    (
      title: 'How to check your skin',
      message:
          'A regular look over your skin can help you notice a new or changing spot to discuss with a professional.',
    ),
    (
      title: 'Dry skin and moisturizers',
      message:
          'Moisturizers, also called emollients, can help keep moisture in the skin.',
    ),
    (
      title: 'Acne',
      message:
          'Gentle cleansing is preferable to harsh scrubbing, which can irritate skin.',
    ),
  ];

  final Set<int> _completed = {};
  late final Box _preferences;
  late final ValueListenable<Box> _preferencesListenable;
  late String _routineDate;
  DateTime? _followUpReminderAt;

  @override
  void initState() {
    super.initState();
    _preferences = Hive.box('preferences');
    _preferencesListenable = _preferences.listenable(
      keys: const ['follow_up_reminder_at'],
    )..addListener(_refreshFollowUpReminder);
    _routineDate = _todayKey;
    _loadRoutine();
    _loadFollowUpReminder();
  }

  @override
  void dispose() {
    _preferencesListenable.removeListener(
      _refreshFollowUpReminder,
    );
    super.dispose();
  }

  String get _todayKey =>
      DateTime.now().toIso8601String().split('T').first;

  void _loadRoutine() {
    final saved = _preferences.get('daily_care_routine');
    if (saved is! Map || saved['date'] != _routineDate) {
      return;
    }

    final done = saved['completed'];
    if (done is List) {
      _completed.addAll(
        done.whereType<int>().where((index) =>
            index >= 0 && index < _routineItems.length),
      );
    }
  }

  void _loadFollowUpReminder() {
    final saved = _preferences.get('follow_up_reminder_at');
    if (saved is String) {
      _followUpReminderAt = DateTime.tryParse(saved);
    }
  }

  void _refreshFollowUpReminder() {
    final saved = _preferences.get('follow_up_reminder_at');
    final reminderAt =
        saved is String ? DateTime.tryParse(saved) : null;
    if (reminderAt == _followUpReminderAt || !mounted) {
      return;
    }
    setState(() => _followUpReminderAt = reminderAt);
  }

  Future<void> _setFollowUpReminder() async {
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    final lastDate = today.add(const Duration(days: 365));
    var initialDate = _followUpReminderAt ??
        today.add(const Duration(days: 7));
    if (initialDate.isBefore(today)) initialDate = today;
    if (initialDate.isAfter(lastDate)) {
      initialDate = lastDate;
    }

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: lastDate,
      helpText: 'Choose a follow-up date',
    );
    if (date == null || !mounted) return;

    final savedTime = _followUpReminderAt;
    final time = await showTimePicker(
      context: context,
      initialTime: savedTime == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay.fromDateTime(savedTime),
      helpText: 'Choose a reminder time',
    );
    if (time == null || !mounted) return;

    final reminderAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!reminderAt.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a future date and time.'),
        ),
      );
      return;
    }

    await _preferences.put(
      'follow_up_reminder_at',
      reminderAt.toIso8601String(),
    );
    await _syncHomePreferences();
    if (!mounted) return;
    setState(() => _followUpReminderAt = reminderAt);

    var notificationScheduled = false;
    try {
      final notificationService =
          FollowUpReminderService.instance;
      final permissionGranted =
          await notificationService.requestPermission();
      await notificationService.cancel();
      if (permissionGranted) {
        await notificationService.schedule(reminderAt);
        notificationScheduled = true;
      }
    } catch (_) {
      // Keep the in-app reminder even if system notifications are unavailable.
    }

    if (!notificationScheduled) {
      try {
        await FollowUpReminderService.instance.cancel();
      } catch (_) {
        // The saved in-app reminder remains available on Home.
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          notificationScheduled
              ? 'Follow-up reminder saved.'
              : 'Reminder saved in the app. Notifications are unavailable or turned off.',
        ),
      ),
    );
  }

  Future<void> _removeFollowUpReminder() async {
    await _preferences.delete('follow_up_reminder_at');
    await _syncHomePreferences();
    try {
      await FollowUpReminderService.instance.cancel();
    } catch (_) {
      // Removing the in-app reminder should still succeed.
    }
    if (mounted) {
      setState(() => _followUpReminderAt = null);
    }
  }

  Future<void> _syncHomePreferences() async {
    await FirebaseCloudStore.instance.syncPreferences({
      'accepted':
          _preferences.get('accepted', defaultValue: false),
      'daily_care_routine':
          _preferences.get('daily_care_routine'),
      'follow_up_reminder_at':
          _preferences.get('follow_up_reminder_at'),
    }).catchError((_) {});
  }

  Future<void> _toggleRoutine(
      int index, bool? checked) async {
    final today = _todayKey;
    if (_routineDate != today) {
      setState(() {
        _routineDate = today;
        _completed.clear();
      });
    }

    setState(() {
      if (checked == true) {
        _completed.add(index);
      } else {
        _completed.remove(index);
      }
    });

    await _preferences.put('daily_care_routine', {
      'date': _routineDate,
      'completed': _completed.toList(),
    });
    await _syncHomePreferences();
  }

  @override
  Widget build(BuildContext context) {
    final scans = ref.watch(scanHistoryProvider);
    final recentScan =
        scans.isEmpty ? null : scans.first.record;
    final progress =
        _completed.length / _routineItems.length;
    final today = DateTime.now();
    final tipIndex =
        (today.year * 372 + today.month * 31 + today.day) %
            _dailyTips.length;
    final dailyTip = _dailyTips[tipIndex];
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(20, 16, 16, 12),
              child: Row(
                children: [
                  Image.asset(
                    'assets/images/skinai_logo.png',
                    width: 46,
                    height: 46,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SkinAI Assist',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  fontWeight:
                                      FontWeight.w800),
                        ),
                        Text(
                          'Your skin health companion',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Your profile',
                    onPressed: () => context.go('/profile'),
                    icon: const Icon(Icons.person_outline),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    18, 4, 18, 28),
                children: [
                  const NoticeBanner(),
                  const SizedBox(height: 16),
                  _HeroCard(
                      onStartScan: () =>
                          context.go('/scan')),
                  const SizedBox(height: 16),
                  _DailyTipCard(
                    title: dailyTip.title,
                    message: dailyTip.message,
                    onTap: () => context.go(
                      Uri(
                        path: '/learn',
                        queryParameters: {
                          'topic': dailyTip.title,
                        },
                      ).toString(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const SectionTitle('Your daily routine'),
                  const SizedBox(height: 10),
                  _RoutineCard(
                    items: _routineItems,
                    completed: _completed,
                    progress: progress,
                    onChanged: _toggleRoutine,
                  ),
                  const SizedBox(height: 16),
                  _ActivitySummaryCard(
                    savedVisits: scans.length,
                    completedItems: _completed.length,
                    totalItems: _routineItems.length,
                  ),
                  const SizedBox(height: 16),
                  _FollowUpReminderCard(
                    reminderAt: _followUpReminderAt,
                    onSetReminder: _setFollowUpReminder,
                    onRemoveReminder:
                        _removeFollowUpReminder,
                  ),
                  const SizedBox(height: 24),
                  const SectionTitle('Explore SkinAI'),
                  const SizedBox(height: 10),
                  GridView.count(
                    shrinkWrap: true,
                    physics:
                        const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.45,
                    children: [
                      _ActionCard(
                        icon: Icons.history_rounded,
                        label: 'Visit history',
                        color: const Color(0xffd9f0eb),
                        iconColor: const Color(0xff176c62),
                        onTap: () => context.go('/history'),
                      ),
                      _ActionCard(
                        icon: Icons.menu_book_rounded,
                        label: 'Skin learning hub',
                        color: const Color(0xffe8e4fa),
                        iconColor: const Color(0xff6755a3),
                        onTap: () => context.go('/learn'),
                      ),
                      _ActionCard(
                        icon:
                            Icons.health_and_safety_rounded,
                        label: 'When to get help',
                        color: const Color(0xffffeadc),
                        iconColor: const Color(0xffb45c32),
                        onTap: () =>
                            context.push('/emergency'),
                      ),
                      _ActionCard(
                        icon: Icons.person_rounded,
                        label: 'Your profile',
                        color: colors.primaryContainer,
                        iconColor: colors.primary,
                        onTap: () => context.go('/profile'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SectionTitle(
                    'Recent activity',
                    action: 'See all',
                    onTap: () => context.go('/history'),
                  ),
                  const SizedBox(height: 8),
                  _RecentVisitCard(
                    date: recentScan?.date,
                    area: recentScan?.area,
                    prediction: recentScan?.prediction,
                    onTap: () => context.go('/history'),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'If a spot is changing, bleeding, painful, or concerning, contact a healthcare professional. The experimental AI is not a diagnosis.',
                    style: TextStyle(
                        fontSize: 12.5, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyTipCard extends StatelessWidget {
  const _DailyTipCard({
    required this.title,
    required this.message,
    required this.onTap,
  });

  final String title;
  final String message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      color:
          colors.secondaryContainer.withValues(alpha: .55),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: colors.secondaryContainer,
                foregroundColor:
                    colors.onSecondaryContainer,
                child: const Icon(
                    Icons.lightbulb_outline_rounded),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TODAY’S SKIN TIP',
                      style: TextStyle(
                        color: colors.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(message),
                    const SizedBox(height: 8),
                    Text(
                      'Read the related Learn article',
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivitySummaryCard extends StatelessWidget {
  const _ActivitySummaryCard({
    required this.savedVisits,
    required this.completedItems,
    required this.totalItems,
  });

  final int savedVisits;
  final int completedItems;
  final int totalItems;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your activity',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _ActivityMetric(
                    icon: Icons.bookmark_outline_rounded,
                    value: '$savedVisits',
                    label: 'Visits recorded',
                    color: colors.primary,
                  ),
                ),
                Container(
                  height: 48,
                  width: 1,
                  color: colors.outlineVariant,
                ),
                Expanded(
                  child: _ActivityMetric(
                    icon: Icons.checklist_rounded,
                    value: '$completedItems/$totalItems',
                    label: 'Care tasks today',
                    color: colors.tertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityMetric extends StatelessWidget {
  const _ActivityMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  style:
                      Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowUpReminderCard extends StatelessWidget {
  const _FollowUpReminderCard({
    required this.reminderAt,
    required this.onSetReminder,
    required this.onRemoveReminder,
  });

  final DateTime? reminderAt;
  final VoidCallback onSetReminder;
  final VoidCallback onRemoveReminder;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDue = reminderAt != null &&
        !reminderAt!.isAfter(DateTime.now());
    final formattedReminder = reminderAt == null
        ? null
        : DateFormat('EEE, MMM d · h:mm a')
            .format(reminderAt!.toLocal());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: colors.primaryContainer,
                  foregroundColor: colors.primary,
                  child: const Icon(
                      Icons.notifications_none_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        reminderAt == null
                            ? 'Follow-up reminder'
                            : isDue
                                ? 'Your reminder is due'
                                : 'Reminder set',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formattedReminder ??
                            'Set an optional reminder to revisit a saved concern or discuss it later.',
                      ),
                      if (reminderAt != null) ...[
                        const SizedBox(height: 4),
                        const Text(
                          'This is a reminder you chose; it does not assess your health.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton.tonalIcon(
                  onPressed: onSetReminder,
                  icon: Icon(
                    reminderAt == null
                        ? Icons.add_alarm_rounded
                        : Icons.edit_calendar_outlined,
                    size: 18,
                  ),
                  label: Text(
                    reminderAt == null
                        ? 'Set reminder'
                        : 'Reschedule',
                  ),
                ),
                if (reminderAt != null)
                  TextButton.icon(
                    onPressed: onRemoveReminder,
                    icon: const Icon(Icons.close_rounded,
                        size: 18),
                    label: const Text('Dismiss'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.onStartScan});

  final VoidCallback onStartScan;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: SizedBox(
        height: 258,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/skin_care_hero.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xe60d3e43),
                    Color(0xa00d3e43),
                    Color(0x08152627),
                  ],
                  stops: [0, .58, 1],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white
                          .withValues(alpha: .18),
                      borderRadius:
                          BorderRadius.circular(30),
                    ),
                    child: const Text(
                      'CARE • LEARN • NOTICE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(
                    width: 230,
                    child: Text(
                      'A little care goes a long way',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        height: 1.12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  const SizedBox(
                    width: 230,
                    child: Text(
                      'Build gentle habits and learn what changes are worth noticing.',
                      style: TextStyle(
                          color: Colors.white, height: 1.3),
                    ),
                  ),
                  const SizedBox(height: 13),
                  FilledButton.icon(
                    onPressed: onStartScan,
                    icon: const Icon(
                        Icons.camera_alt_outlined,
                        size: 18),
                    label:
                        const Text('Start a photo check'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor:
                          const Color(0xff135d5a),
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutineCard extends StatelessWidget {
  const _RoutineCard({
    required this.items,
    required this.completed,
    required this.progress,
    required this.onChanged,
  });

  final List<(String, String)> items;
  final Set<int> completed;
  final double progress;
  final ValueChangedWithIndex onChanged;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${completed.length} of ${items.length} complete',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${(progress * 100).round()}%',
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                color: color,
                backgroundColor:
                    color.withValues(alpha: .12),
              ),
            ),
            const SizedBox(height: 6),
            for (var index = 0;
                index < items.length;
                index++)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
                controlAffinity:
                    ListTileControlAffinity.leading,
                value: completed.contains(index),
                onChanged: (value) =>
                    onChanged(index, value),
                title: Text(
                  items[index].$1,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600),
                ),
                subtitle: Text(items[index].$2),
              ),
          ],
        ),
      ),
    );
  }
}

typedef ValueChangedWithIndex = Future<void> Function(
    int index, bool? value);

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: color,
                child:
                    Icon(icon, color: iconColor, size: 22),
              ),
              Text(
                label,
                style: const TextStyle(
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentVisitCard extends StatelessWidget {
  const _RecentVisitCard({
    required this.date,
    required this.area,
    required this.prediction,
    required this.onTap,
  });

  final DateTime? date;
  final String? area;
  final String? prediction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasVisit = date != null;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 15, vertical: 5),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context)
              .colorScheme
              .primaryContainer,
          child: Icon(
            hasVisit
                ? Icons.checklist_rounded
                : Icons.spa_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(
          hasVisit
              ? prediction ?? 'Visit saved'
              : 'Your first visit',
          style:
              const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          hasVisit
              ? '${date!.toLocal().toString().split(' ').first} · ${area ?? 'Area not specified'} · AI is not a diagnosis'
              : 'Saved visits and notes will appear here.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

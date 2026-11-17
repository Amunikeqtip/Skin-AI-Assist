import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

class FollowUpReminderService {
  FollowUpReminderService._();

  static final instance = FollowUpReminderService._();
  static const _notificationId = 93001;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    final pending = _initialization;
    if (pending != null) {
      return pending;
    }

    final initialization = _initialize();
    _initialization = initialization;
    try {
      await initialization;
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  Future<void> _initialize() async {
    timezone_data.initializeTimeZones();
    final localTimezone =
        await FlutterTimezone.getLocalTimezone();
    timezone.setLocalLocation(
      timezone.getLocation(localTimezone.identifier),
    );

    await _notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings(
          '@mipmap/ic_launcher',
        ),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await initialize();

    if (Platform.isAndroid) {
      final android = _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      return await android
              ?.requestNotificationsPermission() ??
          true;
    }

    if (Platform.isIOS) {
      final ios = _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(
            alert: true,
            badge: false,
            sound: false,
          ) ??
          false;
    }

    return false;
  }

  Future<void> schedule(DateTime scheduledAt) async {
    await initialize();

    await _notifications.zonedSchedule(
      _notificationId,
      'SkinAI Assist reminder',
      'A reminder you set is due. Open SkinAI Assist to review it.',
      timezone.TZDateTime.from(scheduledAt, timezone.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'follow_up_reminders',
          'Follow-up reminders',
          channelDescription:
              'Optional reminders created by you in SkinAI Assist.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode:
          AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancel() async {
    await initialize();
    await _notifications.cancel(_notificationId);
  }
}

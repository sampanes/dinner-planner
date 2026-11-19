// Reminders and notices as Android notifications.
//
// Reminders are scheduled inexactly: Android may deliver one a few minutes
// late, which is fine for "start dinner", and in return the app needs no
// exact-alarm permission (off by default since Android 14).

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/nudges.dart';

abstract class Notifier {
  Future<void> init();

  /// Asks Android for leave to post notifications. True when allowed.
  Future<bool> askPermission();

  /// Replaces every scheduled reminder with [nudges].
  Future<void> schedule(List<Nudge> nudges);

  Future<void> show(Notice notice);
}

/// For tests and for platforms with no notifications.
class SilentNotifier implements Notifier {
  List<Nudge> scheduled = const [];
  final List<Notice> shown = [];

  @override
  Future<void> init() async {}

  @override
  Future<bool> askPermission() async => true;

  @override
  Future<void> schedule(List<Nudge> nudges) async => scheduled = nudges;

  @override
  Future<void> show(Notice notice) async => shown.add(notice);
}

class LocalNotifier implements Notifier {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const NotificationDetails _reminder = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Cooking reminders',
      channelDescription: 'The evening before, the morning of, and when to start, on the nights you cook.',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    ),
  );

  static const NotificationDetails _notice = NotificationDetails(
    android: AndroidNotificationDetails(
      'household',
      'Plan changes',
      channelDescription: 'When the other phone changes a night that concerns you.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
  );

  @override
  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } on Exception {
      // Left on UTC: reminders are scheduled from absolute instants, so they
      // still fire at the right moment.
    }
    await _plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    _ready = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> askPermission() async {
    await init();
    return await _android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> schedule(List<Nudge> nudges) async {
    await init();
    await _plugin.cancelAllPendingNotifications();
    for (final n in nudges) {
      await _plugin.zonedSchedule(
        id: n.id,
        title: n.title,
        body: n.body,
        scheduledDate: tz.TZDateTime.from(n.when, tz.local),
        notificationDetails: _reminder,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  @override
  Future<void> show(Notice notice) async {
    await init();
    // Ids below the reminders' range (day number times ten).
    final id = (notice.title + notice.body).hashCode.abs() % 100000;
    await _plugin.show(id: id, title: notice.title, body: notice.body, notificationDetails: _notice);
  }
}

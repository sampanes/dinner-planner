// Reminders and notices as Android notifications.
//
// Reminders are set as exact alarms. Android holds an inexact one back for
// up to an hour when it was set hours ahead, as every reminder here is, and
// "start dinner" an hour late is no reminder. The manifest asks for
// USE_EXACT_ALARM, which needs no tap from the owner; where Android still
// says no, the reminders fall back to inexact.
//
// A reminder's buttons all bring the app to the front, where the tap is
// carried out and shown with a way to undo it. Nothing is changed from a
// background isolate: the open app and a second writer would undo each other.

import 'dart:ui' show Color;

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

  /// Called with each tap on a reminder, or on one of its buttons, while the
  /// app is running.
  set onTap(void Function(NudgeTap tap)? handler);

  /// The tap that started the app, when a reminder did.
  Future<NudgeTap?> launchTap();
}

/// A reminder was tapped: which one, and which of its buttons (null for the
/// reminder itself).
class NudgeTap {
  const NudgeTap(this.ref, [this.button]);

  final NudgeRef ref;
  final String? button;
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

  void Function(NudgeTap tap)? _onTap;

  /// Set by a test to stand for the reminder the app was opened from.
  NudgeTap? launched;

  @override
  set onTap(void Function(NudgeTap tap)? handler) => _onTap = handler;

  @override
  Future<NudgeTap?> launchTap() async => launched;

  /// What Android does when a reminder or one of its buttons is tapped.
  void tap(NudgeTap tap) => _onTap?.call(tap);
}

class LocalNotifier implements Notifier {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// The bowl's orange, behind the small icon in the notification shade.
  static const Color _accent = Color(0xFFEF5620);

  static List<AndroidNotificationAction> _actions(List<NudgeButton> buttons) =>
      [for (final b in buttons) AndroidNotificationAction(b.id, b.label, showsUserInterface: true)];

  /// The whole text shows when the reminder is pulled open, however long the
  /// list of things still to get.
  static NotificationDetails _reminder(String body, List<NudgeButton> buttons) => NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders',
          'Cooking reminders',
          channelDescription: 'The evening before, the morning of, and when to start, on the nights you cook.',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          color: _accent,
          styleInformation: BigTextStyleInformation(body),
          actions: _actions(buttons),
        ),
      );

  static NotificationDetails _question(String body, List<NudgeButton> buttons) => NotificationDetails(
        android: AndroidNotificationDetails(
          'questions',
          'After dinner',
          channelDescription: 'A quiet question an hour after dinner, and the offer of dinners for the coming week.',
          importance: Importance.low,
          priority: Priority.low,
          color: _accent,
          styleInformation: BigTextStyleInformation(body),
          actions: _actions(buttons),
        ),
      );

  static NotificationDetails _notice(String body, List<NudgeButton> buttons) => NotificationDetails(
        android: AndroidNotificationDetails(
          'household',
          'Plan changes',
          channelDescription: 'When the other phone changes a night that concerns you.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          color: _accent,
          styleInformation: BigTextStyleInformation(body),
          actions: _actions(buttons),
        ),
      );

  void Function(NudgeTap tap)? _onTap;
  NudgeTap? _early;

  static NudgeTap? _tapOf(NotificationResponse? response) {
    final ref = NudgeRef.parse(response?.payload);
    if (ref == null) return null;
    final button = response?.actionId;
    return NudgeTap(ref, button == null || button.isEmpty ? null : button);
  }

  void _tapped(NotificationResponse response) {
    final tap = _tapOf(response);
    if (tap == null) return;
    final handler = _onTap;
    if (handler == null) {
      // Tapped before the screens were listening: kept for them.
      _early = tap;
    } else {
      handler(tap);
    }
  }

  @override
  set onTap(void Function(NudgeTap tap)? handler) {
    _onTap = handler;
    final early = _early;
    if (handler != null && early != null) {
      _early = null;
      handler(early);
    }
  }

  @override
  Future<NudgeTap?> launchTap() async {
    await init();
    final details = await _plugin.getNotificationAppLaunchDetails();
    return details != null && details.didNotificationLaunchApp ? _tapOf(details.notificationResponse) : null;
  }

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
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_dinner')),
      onDidReceiveNotificationResponse: _tapped,
    );
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
    final exact = await _android?.canScheduleExactNotifications() ?? false;
    for (final n in nudges) {
      await _plugin.zonedSchedule(
        id: n.id,
        title: n.title,
        body: n.body,
        scheduledDate: tz.TZDateTime.from(n.when, tz.local),
        notificationDetails: n.quiet ? _question(n.body, n.buttons) : _reminder(n.body, n.buttons),
        payload: n.ref?.text,
        androidScheduleMode: exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  @override
  Future<void> show(Notice notice) async {
    await init();
    // Ids below the reminders' range (day number times ten).
    final id = (notice.title + notice.body).hashCode.abs() % 100000;
    await _plugin.show(id: id, title: notice.title, body: notice.body, notificationDetails: _notice(notice.body, notice.buttons), payload: notice.ref?.text);
  }
}

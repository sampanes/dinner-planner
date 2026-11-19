// The reminders for the nights this phone's owner cooks, and the notices
// raised when the other phone changes something that concerns them.

import 'plan.dart';
import 'sync_core.dart';

/// When the three reminders fire, as minutes after midnight.
class NudgeTimes {
  const NudgeTimes({this.evening = 20 * 60, this.morning = 7 * 60 + 30, this.start = 17 * 60});

  /// The evening before: time to check the fridge and thaw.
  final int evening;

  /// The morning of.
  final int morning;

  /// Time to start cooking.
  final int start;

  Map<String, Object?> toJson() => {'evening': evening, 'morning': morning, 'start': start};

  static NudgeTimes fromJson(Object? raw) {
    const d = NudgeTimes();
    if (raw is! Map) return d;
    int pick(String k, int fallback) {
      final v = raw[k];
      return v is int && v >= 0 && v < 24 * 60 ? v : fallback;
    }

    return NudgeTimes(evening: pick('evening', d.evening), morning: pick('morning', d.morning), start: pick('start', d.start));
  }

  NudgeTimes copyWith({int? evening, int? morning, int? start}) =>
      NudgeTimes(evening: evening ?? this.evening, morning: morning ?? this.morning, start: start ?? this.start);
}

class Nudge {
  const Nudge(this.id, this.when, this.title, this.body);

  final int id;

  /// Local time.
  final DateTime when;
  final String title;
  final String body;
}

class Notice {
  const Notice(this.title, this.body);

  final String title;
  final String body;
}

int _dayNumber(DateTime day) => DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/ 86400000;

/// Every reminder still ahead for the nights [me] cooks, soonest first.
List<Nudge> planNudges({
  required String me,
  required DateTime now,
  required NudgeTimes times,
  required Plan plan,
  required String Function(String slug) recipeName,
  int days = 8,
}) {
  final out = <Nudge>[];
  for (var i = 0; i < days; i++) {
    final day = dayAfter(now, i);
    final key = dayText(day);
    if (plan.cook(key) != me) continue;
    final slug = plan.meal(key);
    final dish = slug == null ? null : recipeName(slug);
    final base = _dayNumber(day) * 10;
    DateTime at(DateTime d, int minutes) => DateTime(d.year, d.month, d.day, minutes ~/ 60, minutes % 60);

    final candidates = [
      Nudge(
        base + 1,
        at(dayAfter(day, -1), times.evening),
        dish == null ? 'You cook tomorrow' : 'You cook tomorrow: $dish',
        dish == null ? 'Nothing is picked yet. Choose a dinner tonight.' : 'Check you have everything, and move anything frozen to the fridge.',
      ),
      Nudge(
        base + 2,
        at(day, times.morning),
        "You're cooking tonight",
        dish == null ? 'Nothing is picked yet. Choose a dinner.' : '$dish. Anything still frozen comes out now.',
      ),
      Nudge(
        base + 3,
        at(day, times.start),
        'Time to start dinner',
        dish == null ? 'Nothing is picked. Choose something quick.' : '$dish. Tap to open it.',
      ),
    ];
    out.addAll(candidates.where((n) => n.when.isAfter(now)));
  }
  out.sort((a, b) => a.when.compareTo(b.when));
  return out;
}

/// What to tell [me] about changes that arrived from another phone.
List<Notice> noticesFor(
  List<Change> changes, {
  required String? me,
  required String myDev,
  required DateTime now,
  required Plan plan,
  required String Function(String slug) recipeName,
}) {
  if (me == null) return const [];
  final today = dayText(now);
  final other = people.firstWhere((p) => p != me);
  final out = <Notice>[];
  final told = <String>{};
  // Who cooks comes first: being handed a night matters more than what the
  // dinner is, and each day is only mentioned once.
  final ordered = [
    ...changes.where((c) => c.key.startsWith('cook/')),
    ...changes.where((c) => !c.key.startsWith('cook/')),
  ];
  for (final c in ordered) {
    if (c.dev == myDev) continue;
    final parts = c.key.split('/');
    if (parts.length != 2) continue;
    final day = parts[1];
    final date = parseDay(day);
    if (date == null || day.compareTo(today) < 0) continue;
    final label = dayLabel(date, now);
    final slug = plan.meal(day);
    final dish = slug == null ? null : recipeName(slug);
    if (parts[0] == 'cook') {
      if (c.after == me && told.add(day)) {
        out.add(Notice("You're cooking $label", dish ?? 'Nothing is picked yet.'));
      } else if (c.before == me && told.add(day)) {
        out.add(Notice(
          c.after == other ? '${plan.name(other)} is cooking $label' : 'Nobody is down to cook $label',
          c.after == other ? 'That night is off your list.' : 'You were, until just now.',
        ));
      }
    } else if (parts[0] == 'meal' && plan.cook(day) == me && told.add(day)) {
      out.add(Notice(
        dish == null ? 'Dinner $label was cleared' : 'Dinner $label is now $dish',
        "You're cooking that night.",
      ));
    }
  }
  return out;
}

/// A short line saying what a batch of entries is, for the relay message a
/// person may see as a notification.
({String title, String body}) headline(List<Entry> entries, Plan plan, String Function(String slug) recipeName, DateTime now) {
  if (entries.isEmpty) return (title: 'Dinner planner', body: 'In step.');
  if (entries.every((e) => e.key.startsWith('got/') || e.key.startsWith('buy/'))) {
    return (title: 'Shopping list updated', body: entries.length == 1 ? '' : '${entries.length} changes');
  }
  if (entries.length > 2) return (title: 'Dinner plan updated', body: '${entries.length} changes');
  final lines = <String>[];
  for (final e in entries) {
    final parts = e.key.split('/');
    final date = parts.length == 2 ? parseDay(parts[1]) : null;
    final v = e.value;
    if (date != null && parts[0] == 'cook') {
      lines.add(v is String && people.contains(v) ? '${plan.name(v)} cooks ${dayLabel(date, now)}' : 'No cook ${dayLabel(date, now)}');
    } else if (date != null && parts[0] == 'meal') {
      lines.add(v is String ? '${_cap(dayLabel(date, now))}: ${recipeName(v)}' : '${_cap(dayLabel(date, now))}: no dinner');
    } else {
      lines.add('Dinner plan updated');
    }
  }
  return (title: lines.first, body: lines.length > 1 ? lines[1] : '');
}

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

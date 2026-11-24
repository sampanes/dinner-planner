// The reminders for the nights this phone's owner cooks, and the notices
// raised when the other phone changes something that concerns them.
//
// A reminder says what there is to do, not that something might need doing:
// which things to thaw, what is still to buy, when to start so dinner is on
// the table at the hour the household eats. Each carries a short reference
// (what kind it is, the day, the recipe) so that tapping it, or one of its
// buttons, can do the next thing without anyone finding their way there.

import 'plan.dart';
import 'sync_core.dart';

/// When the reminders fire, as minutes after midnight.
class NudgeTimes {
  const NudgeTimes({this.evening = 20 * 60, this.morning = 7 * 60 + 30, this.eat = 18 * 60});

  /// The evening before: time to check the fridge and thaw.
  final int evening;

  /// The morning of.
  final int morning;

  /// When dinner should be on the table. "Start cooking" is counted back
  /// from here by how long the recipe takes.
  final int eat;

  Map<String, Object?> toJson() => {'evening': evening, 'morning': morning, 'eat': eat};

  static NudgeTimes fromJson(Object? raw) {
    const d = NudgeTimes();
    if (raw is! Map) return d;
    int? pick(String k) {
      final v = raw[k];
      return v is int && v >= 0 && v < 24 * 60 ? v : null;
    }

    // Before 0.9 the phone kept when to start cooking; a usual dinner then
    // lands about three quarters of an hour later.
    final start = pick('start');
    final eat = pick('eat') ?? (start == null ? d.eat : (start + 45).clamp(0, 24 * 60 - 1));
    return NudgeTimes(evening: pick('evening') ?? d.evening, morning: pick('morning') ?? d.morning, eat: eat);
  }

  NudgeTimes copyWith({int? evening, int? morning, int? eat}) =>
      NudgeTimes(evening: evening ?? this.evening, morning: morning ?? this.morning, eat: eat ?? this.eat);
}

/// A recipe with no time of its own is taken to need this long.
const int usualMinutes = 40;

/// Room for finding the pan and setting the table.
const int slackMinutes = 10;

/// How long after dinner time the "how was it?" question waits.
const int rateAfterMinutes = 60;

/// When to be at the stove, as minutes after midnight, for a dinner that
/// takes [minutes].
int startMinutes(NudgeTimes times, int? minutes) => (times.eat - (minutes ?? usualMinutes) - slackMinutes).clamp(0, 24 * 60 - 1);

/// "5:20 pm".
String clockText(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  final hour = h % 12 == 0 ? 12 : h % 12;
  return '$hour:${m.toString().padLeft(2, '0')} ${h < 12 ? 'am' : 'pm'}';
}

/// "onion", "onion and beans", "onion, beans, rice and 2 more".
String listText(List<String> names, {int most = 3}) {
  if (names.isEmpty) return '';
  final shown = names.take(most).toList();
  final more = names.length - shown.length;
  if (more > 0) return '${shown.join(', ')} and $more more';
  if (shown.length == 1) return shown.single;
  return '${shown.sublist(0, shown.length - 1).join(', ')} and ${shown.last}';
}

/// A button on a reminder.
class NudgeButton {
  const NudgeButton(this.id, this.label);

  final String id;
  final String label;
}

/// What a reminder is about, carried through Android and back when it is tapped.
class NudgeRef {
  const NudgeRef(this.kind, {this.day = '', this.slug = ''});

  /// 'eve', 'morn', 'start', 'rate' or 'week'.
  final String kind;
  final String day;
  final String slug;

  String get text => '$kind|$day|$slug';

  static NudgeRef? parse(String? text) {
    final parts = (text ?? '').split('|');
    if (parts.length != 3 || parts[0].isEmpty) return null;
    return NudgeRef(parts[0], day: parts[1], slug: parts[2]);
  }
}

class Nudge {
  const Nudge(this.id, this.when, this.title, this.body, {this.ref, this.buttons = const [], this.quiet = false});

  final int id;

  /// Local time.
  final DateTime when;
  final String title;
  final String body;
  final NudgeRef? ref;
  final List<NudgeButton> buttons;

  /// Shown without a sound: a question, not something to act on now.
  final bool quiet;
}

class Notice {
  const Notice(this.title, this.body, {this.ref, this.buttons = const []});

  final String title;
  final String body;
  final NudgeRef? ref;
  final List<NudgeButton> buttons;
}

/// What a reminder needs to know about one planned dinner.
class DinnerFacts {
  const DinnerFacts({required this.name, this.minutes, this.thaw = const [], this.missing = const []});

  final String name;

  /// Start to table, when the recipe says.
  final int? minutes;

  /// The meat and fish in it: what may be in the freezer.
  final List<String> thaw;

  /// What it needs that is not ticked as in the house, staples left out.
  final List<String> missing;
}

const NudgeButton skipButton = NudgeButton('skip', 'Not tonight');
const NudgeButton listButton = NudgeButton('list', 'Open the list');
const NudgeButton haveButton = NudgeButton('have', 'All here');
const List<NudgeButton> rateButtons = [NudgeButton('love', 'Loved it'), NudgeButton('fine', 'It was fine'), NudgeButton('never', 'Not again')];

/// The stars each answer to "how was it?" stands for.
const Map<String, int> rateStars = {'love': 5, 'fine': 3, 'never': 1};

int _dayNumber(DateTime day) => DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/ 86400000;

/// The one reminder that is not about a day: the plan is running out.
const int weekNudgeId = 5;

/// Every reminder still ahead, soonest first: three for each night [me]
/// cooks, and for every planned dinner a quiet "how was it?" afterwards.
/// [facts] says what a dinner needs; [rated] is true once this phone's owner
/// has said how that dinner was.
List<Nudge> planNudges({
  required String me,
  required DateTime now,
  required NudgeTimes times,
  required Plan plan,
  required DinnerFacts Function(String day, String slug) facts,
  bool Function(String day, String slug)? rated,
  int days = 8,
}) {
  final out = <Nudge>[];
  for (var i = 0; i < days; i++) {
    final day = dayAfter(now, i);
    final key = dayText(day);
    if (plan.off(key) != null) continue;
    final slug = plan.meal(key);
    final f = slug == null ? null : facts(key, slug);
    final base = _dayNumber(day) * 10;
    DateTime at(DateTime d, int minutes) => DateTime(d.year, d.month, d.day, minutes ~/ 60, minutes % 60);
    final candidates = <Nudge>[];

    if (plan.cook(key) == me) {
      if (f == null) {
        candidates.addAll([
          Nudge(base + 1, at(dayAfter(day, -1), times.evening), 'You cook tomorrow', 'Nothing is picked yet. Choose a dinner tonight.', ref: NudgeRef('eve', day: key)),
          Nudge(base + 2, at(day, times.morning), "You're cooking tonight", 'Nothing is picked yet. Choose a dinner.', ref: NudgeRef('morn', day: key)),
          Nudge(base + 3, at(day, startMinutes(times, null)), 'Time to start dinner', 'Nothing is picked. Choose something quick.', ref: NudgeRef('start', day: key)),
        ]);
      } else {
        final thaw = listText(f.thaw), missing = listText(f.missing);
        final start = startMinutes(times, f.minutes);
        candidates.addAll([
          Nudge(
            base + 1,
            at(dayAfter(day, -1), times.evening),
            'You cook tomorrow: ${f.name}',
            [
              if (thaw.isNotEmpty) 'If the $thaw is frozen, move it to the fridge tonight.',
              if (missing.isNotEmpty) 'Still to get: $missing.' else thaw.isEmpty ? 'Everything it needs is in the house.' : 'Everything else is in the house.',
            ].join(' '),
            ref: NudgeRef('eve', day: key, slug: slug!),
            buttons: [if (missing.isNotEmpty) ...[haveButton, listButton]],
          ),
          Nudge(
            base + 2,
            at(day, times.morning),
            "You're cooking tonight: ${f.name}",
            [
              'Start by ${clockText(start)} to eat at ${clockText(times.eat)}.',
              if (thaw.isNotEmpty) 'Take the $thaw out now if it is still frozen.',
              if (missing.isNotEmpty) 'Still to get: $missing.',
            ].join(' '),
            ref: NudgeRef('morn', day: key, slug: slug),
            buttons: [skipButton, if (missing.isNotEmpty) listButton],
          ),
          Nudge(
            base + 3,
            at(day, start),
            'Time to start: ${f.name}',
            f.minutes == null ? 'Tap to open the recipe.' : 'About ${f.minutes} minutes, so dinner is at ${clockText(times.eat)}. Tap to open the recipe.',
            ref: NudgeRef('start', day: key, slug: slug),
            buttons: const [skipButton],
          ),
        ]);
      }
    }
    if (f != null && !(rated?.call(key, slug!) ?? false)) {
      candidates.add(Nudge(
        base + 4,
        at(day, times.eat).add(const Duration(minutes: rateAfterMinutes)),
        'How was the ${f.name}?',
        'One tap. It steers what gets suggested.',
        ref: NudgeRef('rate', day: key, slug: slug!),
        buttons: rateButtons,
        quiet: true,
      ));
    }
    out.addAll(candidates.where((n) => n.when.isAfter(now)));
  }
  out.sort((a, b) => a.when.compareTo(b.when));
  return out;
}

/// True when the plan stops within two days: time to offer the next week.
bool planRunsOut(Plan plan, DateTime now) {
  for (var i = 3; i < 14; i++) {
    if (plan.meal(dayText(dayAfter(now, i))) != null) return false;
  }
  return true;
}

/// How long the offer of a new week stays quiet after it was last made.
const Duration weekAskEvery = Duration(days: 3);

/// When to offer the next week: the coming [evening], but not within
/// [weekAskEvery] of the last time ([lastAsk], which is still ahead when it
/// has been set and has not fired yet).
DateTime weekAskTime({required DateTime now, required int evening, DateTime? lastAsk}) {
  if (lastAsk != null && lastAsk.isAfter(now)) return lastAsk;
  var next = DateTime(now.year, now.month, now.day, evening ~/ 60, evening % 60);
  if (!next.isAfter(now)) next = DateTime(now.year, now.month, now.day + 1, evening ~/ 60, evening % 60);
  if (lastAsk != null) {
    final earliest = lastAsk.add(weekAskEvery);
    while (next.isBefore(earliest)) {
      next = DateTime(next.year, next.month, next.day + 1, evening ~/ 60, evening % 60);
    }
  }
  return next;
}

/// The offer itself: [nights] are the dinners it would put on the plan.
Nudge weekNudge(DateTime when, List<({DateTime date, String name})> nights) => Nudge(
      weekNudgeId,
      when,
      'Dinners for the coming week',
      '${listText([for (final n in nights) '${weekdayName(n.date)} ${n.name}'])}. Use them, or change them.',
      ref: const NudgeRef('week'),
      buttons: const [NudgeButton('use', 'Use these'), NudgeButton('change', 'Change')],
    );

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
  // A night called off comes first, then who cooks: being handed a night
  // matters more than what the dinner is, and each day is only mentioned once.
  final ordered = [
    ...changes.where((c) => c.key.startsWith('off/')),
    ...changes.where((c) => c.key.startsWith('cook/')),
    ...changes.where((c) => !c.key.startsWith('cook/') && !c.key.startsWith('off/')),
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
    if (parts[0] == 'off') {
      final why = plan.off(day);
      if (why != null && told.add(day)) {
        out.add(Notice('${offKinds[why]} $label', why == 'skip' ? 'Nobody cooks that night.' : 'Nobody cooks that night. A dinner that was planned has moved on.'));
      }
    } else if (parts[0] == 'cook') {
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

/// The kinds of entry the shopping list is made of.
const Set<String> _shopping = {'got', 'buy', 'size', 'sec', 'store', 'at', 'pos', 'code', 'extra', 'want', 'have'};

/// A short line saying what a batch of entries is, for the relay message a
/// person may see as a notification.
({String title, String body}) headline(List<Entry> entries, Plan plan, String Function(String slug) recipeName, DateTime now) {
  if (entries.isEmpty) return (title: 'Dinner planner', body: 'In step.');
  if (entries.every((e) => _shopping.contains(e.key.split('/').first))) {
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
    } else if (date != null && parts[0] == 'off') {
      lines.add(v is String && offKinds.containsKey(v) ? '${_cap(dayLabel(date, now))}: ${offKinds[v]!.toLowerCase()}' : '${_cap(dayLabel(date, now))}: dinner is back on');
    } else if ((parts.length == 2 || parts.length == 3) && parts[0] == 'note') {
      lines.add('Note on ${recipeName(parts[1])}');
    } else {
      lines.add('Dinner plan updated');
    }
  }
  return (title: lines.first, body: lines.length > 1 ? lines[1] : '');
}

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

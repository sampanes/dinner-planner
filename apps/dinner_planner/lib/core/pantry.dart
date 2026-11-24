// What is in the house.
//
// Nobody keeps an inventory, so the app keeps one from what it is told
// anyway. "in/<ingredient>" is the day an ingredient last came into the
// house: the day its line was ticked on the list, "All here" was tapped on a
// reminder, or someone said so on the "In the house" page. Both phones share
// it, so what one of them buys the other one has.
//
// From that day the app works out whether it is still there:
//
//   - Every kind of thing keeps for so long ([keepsDays]): fish for a few
//     days, sour cream for a couple of weeks, a jar of spice for a year.
//   - A dinner uses up the fresh things it asks for ([usedUp]): the beef
//     bought on Saturday for Monday's chili is not there for Thursday's
//     tacos. A bag of rice or a tub of sour cream outlasts the dinner.
//   - What the household says it always has is there until someone says it
//     has run out.
//
// It is a guess, and the app says so: the list sets such things apart as
// "probably in the house" for a look in the cupboard, and "what can I cook
// with what's here" names what it believes is missing.

import 'plan.dart';
import 'shopping.dart';
import 'sync_core.dart';

String inKey(String id) => 'in/$id';

/// How many days each section's things last once they are in the house.
const Map<String, int> keepsDays = {
  'produce': 7,
  'bakery': 5,
  'deli': 7,
  'meat': 3,
  'dairy': 12,
  'frozen': 90,
  'dry': 180,
  'canned': 365,
  'spices': 365,
  'sauces': 120,
  'snacks': 45,
  'drinks': 45,
  'other': 21,
};

/// The sections one dinner uses the whole of: the packet of beef, the can of
/// beans. The rest outlast a dinner.
const Set<String> usedUp = {'meat', 'produce', 'bakery', 'deli', 'canned'};

/// How far back a dinner can have used something up (the plan itself is kept
/// sixty days).
const int _lookBack = 60;

/// A snapshot of what the house holds, read off the shared facts once so that
/// asking about every ingredient of every recipe stays cheap.
class Pantry {
  Pantry({required SyncCore core, required this.section, required this.staple, required Iterable<({String day, Iterable<String> ids})> dinners, required DateTime now}) : today = dayText(now) {
    for (final e in core.entries) {
      final v = e.value;
      if (e.key.startsWith('in/') && v is String && parseDay(v) != null) _since[e.key.substring(3)] = v;
      if (e.key.startsWith('want/') && v == '1') _out.add(e.key.substring(5));
    }
    for (final d in dinners) {
      for (final id in d.ids) {
        (_usedOn[id] ??= []).add(d.day);
      }
    }
  }

  /// The section an ingredient is in.
  final String Function(String id) section;

  /// Whether the household always has it.
  final bool Function(String id) staple;
  final String today;

  final Map<String, String> _since = {};
  final Set<String> _out = {};
  final Map<String, List<String>> _usedOn = {};

  /// The day [id] came into the house, when the app was told and it has not
  /// been used up or gone off by today.
  String? since(String id) => _holds(id, today) ? _since[id] : null;

  /// True when nobody has ever said what is in the house.
  bool get untold => _since.isEmpty;

  /// Everything the app was told is here and believes still is, by id.
  Iterable<String> get held => [for (final id in _since.keys) if (_holds(id, today)) id];

  /// Whether [id] is in the house for a dinner on [day].
  bool has(String id, String day) => staple(id) ? !_out.contains(id) : _holds(id, day);

  bool _holds(String id, String day) {
    final since = _since[id];
    if (since == null || since.compareTo(day) > 0) return false;
    final from = parseDay(since), to = parseDay(day);
    if (from == null || to == null) return false;
    final kind = section(id);
    if (dayAfter(from, keepsDays[kind] ?? 21).isBefore(to)) return false;
    if (!usedUp.contains(kind)) return true;
    // A dinner between then and [day] took it.
    return !(_usedOn[id] ?? const <String>[]).any((d) => d.compareTo(since) >= 0 && d.compareTo(day) < 0);
  }
}

/// The dinners a pantry has to know about: every planned one from sixty days
/// back to a fortnight on, with what each uses.
List<({String day, Iterable<String> ids})> pantryDinners(Plan plan, DateTime now, Iterable<Ingredient>? Function(String slug) ingredients) => [
      for (var i = -_lookBack; i < 14; i++)
        if (plan.meal(dayText(dayAfter(now, i))) case final slug?)
          if (ingredients(slug) case final list?) (day: dayText(dayAfter(now, i)), ids: [for (final x in list) x.id]),
    ];

/// "today", "yesterday", "Saturday", or "November 10" for longer ago.
String sinceText(String day, DateTime now) {
  final date = parseDay(day);
  if (date == null) return day;
  final gap = dayAfter(now, 0).difference(date).inHours;
  if (gap < 12) return 'today';
  if (gap < 36) return 'yesterday';
  if (gap < 6 * 24 + 12) return weekdayName(date);
  return monthDay(date);
}

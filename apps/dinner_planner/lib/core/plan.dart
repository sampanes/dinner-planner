// What the shared facts mean: which dinner is on which day, who cooks it,
// and what the two people are called. The keys are the whole schema.

import 'sync_core.dart';

/// The two people, by the same keys the recipe site uses for its star ratings.
const List<String> people = ['pink', 'blue'];

String mealKey(String day) => 'meal/$day';
String cookKey(String day) => 'cook/$day';
String nameKey(String who) => 'name/$who';
String noteKey(String slug) => 'note/$slug';

/// The longest note a recipe can carry (the most one shared value can hold).
const int noteMax = 400;

const List<String> _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const List<String> _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

String weekdayName(DateTime day) => _weekdays[day.weekday - 1];

String monthDay(DateTime day) => '${_months[day.month - 1]} ${day.day}';

/// The local calendar day [offset] days after [from], at midnight.
DateTime dayAfter(DateTime from, int offset) => DateTime(from.year, from.month, from.day + offset);

DateTime? parseDay(String day) {
  final m = RegExp(r'^(\d{4})-(\d\d)-(\d\d)$').firstMatch(day);
  if (m == null) return null;
  return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
}

/// "today", "tomorrow", or the weekday.
String dayLabel(DateTime day, DateTime now) {
  final gap = dayAfter(day, 0).difference(dayAfter(now, 0)).inHours;
  if (gap.abs() < 12) return 'today';
  if (gap > 0 && gap < 36) return 'tomorrow';
  return weekdayName(day);
}

class Plan {
  const Plan(this.core);

  final SyncCore core;

  String? meal(String day) => _text(core.value(mealKey(day)));

  String? cook(String day) {
    final who = _text(core.value(cookKey(day)));
    return people.contains(who) ? who : null;
  }

  /// What the household wrote down about a recipe ("add parmesan"), or null.
  String? note(String? slug) => slug == null ? null : _text(core.value(noteKey(slug)));

  String name(String who) => _text(core.value(nameKey(who))) ?? '${who[0].toUpperCase()}${who.substring(1)}';

  static String? _text(Object? v) => v is String && v.isNotEmpty ? v : null;
}

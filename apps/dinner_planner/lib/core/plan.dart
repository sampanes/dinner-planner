// What the shared facts mean: which dinner is on which day, who cooks it,
// and what the two people are called. The keys are the whole schema.

import 'dart:convert';

import 'sync_core.dart';

/// The two people, by the same keys the recipe site uses for its star ratings.
const List<String> people = ['pink', 'blue'];

String mealKey(String day) => 'meal/$day';
String cookKey(String day) => 'cook/$day';
String nameKey(String who) => 'name/$who';
String noteKey(String slug) => 'note/$slug';

/// The longest note a recipe can carry (the most one shared value can hold).
const int noteMax = 400;

/// A note on one step is kept as `note/<slug>/<step id>` with the value
/// "how the step starts", a line break, then the note. The id is made from the step's own
/// words, so the note stays on its step when other steps are added or moved;
/// the opening words are for when the step itself has been rewritten since.
/// house.js and scripts/house_notes.py read the same form.
String stepNoteKey(String slug, String stepText) => 'note/$slug/${stepId(stepText)}';

/// The longest note on a step: [noteMax] less the room its opening words take.
const int stepNoteMax = 320;
const int _anchorMax = 60;

/// A short, stable name for a step, from its text (FNV-1a over UTF-8).
String stepId(String stepText) {
  var h = 0x811c9dc5;
  for (final b in utf8.encode(stepText)) {
    h = ((h ^ b) * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

/// How a step starts, on one line.
String stepAnchor(String stepText) {
  final flat = stepText.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= _anchorMax ? flat : flat.substring(0, _anchorMax);
}

/// One thing the household wrote on a recipe.
class NoteLine {
  const NoteLine({required this.key, required this.slug, required this.text, this.step, this.anchor});

  /// The shared key it is kept under.
  final String key;
  final String slug;
  final String text;

  /// The id of the step it is about ([stepId]); null for a note on the whole recipe.
  final String? step;

  /// How that step started when the note was written.
  final String? anchor;
}

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

  /// Everything written on a recipe: the note on the whole recipe first, then
  /// the notes on its steps, oldest first.
  List<NoteLine> notes(String slug) {
    final whole = note(slug);
    final prefix = '${noteKey(slug)}/';
    final steps = [
      for (final e in core.entries)
        if (e.key.startsWith(prefix) && _text(e.value) != null) e
    ]..sort((a, b) => a.at.compareTo(b.at));
    return [
      if (whole != null) NoteLine(key: noteKey(slug), slug: slug, text: whole),
      for (final e in steps) ?_stepNote(slug, e.key.substring(prefix.length), e.value as String),
    ];
  }

  static NoteLine? _stepNote(String slug, String step, String value) {
    final cut = value.indexOf('\n');
    final text = cut < 0 ? value : value.substring(cut + 1).trim();
    if (text.isEmpty) return null;
    return NoteLine(key: '${noteKey(slug)}/$step', slug: slug, text: text, step: step, anchor: cut <= 0 ? null : value.substring(0, cut));
  }

  String name(String who) => _text(core.value(nameKey(who))) ?? '${who[0].toUpperCase()}${who.substring(1)}';

  static String? _text(Object? v) => v is String && v.isNotEmpty ? v : null;
}

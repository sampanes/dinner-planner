// A week of dinners, drafted: one tap to accept instead of fourteen to build.
//
// The draft only fills nights that are empty. Each night gets the recipe the
// suggestion scoring likes best for the week as it then stands, so the week
// shares what it buys and does not come out all beef. Sharing must not make
// the week one dinner five times, so a near twin of a dinner already in it
// ("...Chicken Tortilla Melts" beside "...Beef Tortilla Melts") is passed
// over, and so is a third dinner of one kind. Nothing cooked in the last two
// weeks is offered. Once the household has a few weeks behind it,
// the draft follows its habits: a weekday that never has a dinner is left
// free, and each night goes to whoever usually cooks on that weekday.

import '../core/plan.dart';
import '../core/sync_core.dart';
import 'recipes.dart';
import 'suggest.dart';

/// One night of a drafted week.
class DraftNight {
  DraftNight({required this.date, required this.slug, this.cook, this.why = ''});

  final DateTime date;
  String slug;

  /// Who would cook; null leaves the night as it is (someone already has it).
  String? cook;

  /// A few words on why this recipe.
  String why;

  String get day => dayText(date);
}

/// How far back a plan must reach before its habits are trusted.
const int _habitDays = 14;

/// How many of the same weekday are looked back over.
const int _habitWeeks = 4;

const Set<String> _fillerWords = {'one', 'pan', 'pot', 'with', 'and', 'the', 'style'};

Set<String> _nameWords(Recipe r) => {
      for (final w in r.name.toLowerCase().split(RegExp(r'[^a-z]+')))
        if (w.length > 2 && !_fillerWords.contains(w)) w
    };

/// True when [a] and [b] are the same dinner with one thing swapped: their
/// names share two words or more, and those are two fifths of all the words
/// in both ("Pub-Style Shepherd's Pie", "Beef & Mushroom Shepherd's Pie").
bool nearTwins(Recipe a, Recipe b) {
  final x = _nameWords(a), y = _nameWords(b);
  final shared = x.intersection(y).length;
  return shared >= 2 && shared * 5 >= x.union(y).length * 2;
}

/// The most dinners of one kind ("Tex-Mex") a drafted week takes.
const int _mostOfAKind = 2;

/// Dinners for the empty nights from tomorrow through [days] days on.
List<DraftNight> draftWeek({
  required DateTime now,
  required Plan plan,
  required List<Recipe> recipes,
  Map<String, String> names = const {},
  int days = 7,
}) {
  if (recipes.isEmpty) return const [];
  final today = dayText(now);
  final cooked = <String, String>{}, cooks = <String, String>{};
  for (final e in plan.core.entries) {
    final v = e.value;
    if (v is! String || v.isEmpty) continue;
    if (e.key.startsWith('meal/') && e.key.substring(5).compareTo(today) < 0) cooked[e.key.substring(5)] = v;
    if (e.key.startsWith('cook/') && people.contains(v)) cooks[e.key.substring(5)] = v;
  }

  final firstDay = cooked.keys.fold<String?>(null, (a, b) => a == null || b.compareTo(a) < 0 ? b : a);
  final first = firstDay == null ? null : parseDay(firstDay);
  final settled = first != null && dayAfter(now, 0).difference(first).inDays >= _habitDays;

  // A weekday the household has not cooked on in a month of them is one it
  // keeps free.
  bool usual(DateTime date) {
    if (!settled) return true;
    for (var w = 1; w <= _habitWeeks; w++) {
      if (cooked.containsKey(dayText(dayAfter(date, -7 * w)))) return true;
    }
    return false;
  }

  String? usualCook(DateTime date) {
    final tally = <String, int>{};
    for (var w = 1; w <= _habitWeeks; w++) {
      final day = dayText(dayAfter(date, -7 * w));
      final who = cooked.containsKey(day) ? cooks[day] : null;
      if (who != null) tally[who] = (tally[who] ?? 0) + 1;
    }
    if (tally.isEmpty) return null;
    final a = tally[people[0]] ?? 0, b = tally[people[1]] ?? 0;
    return a == b ? null : (a > b ? people[0] : people[1]);
  }

  final recent = {
    for (final e in cooked.entries)
      if (e.key.compareTo(dayText(dayAfter(now, -14))) >= 0) e.value
  };
  final bySlug = {for (final r in recipes) r.slug: r};
  final ahead = <Recipe>[];
  final nights = <String, int>{for (final who in people) who: 0};
  for (var i = 0; i < 14; i++) {
    final day = dayText(dayAfter(now, i));
    if (bySlug[plan.meal(day)] case final r?) ahead.add(r);
    if (i >= 1 && i <= days) {
      if (plan.cook(day) case final who?) nights[who] = nights[who]! + 1;
    }
  }

  final out = <DraftNight>[];
  final drafted = <Recipe>[];
  var before = plan.cook(today);
  for (var i = 1; i <= days; i++) {
    final date = dayAfter(now, i);
    final day = dayText(date);
    final has = plan.cook(day);
    if (plan.meal(day) != null || plan.off(day) != null || !usual(date)) {
      before = has ?? before;
      continue;
    }
    final taken = {...recent, for (final r in ahead) r.slug, for (final r in drafted) r.slug};
    final ranked = suggest([for (final r in recipes) if (!taken.contains(r.slug)) r], planned: [...ahead, ...drafted], names: names);
    if (ranked.isEmpty) break;
    final week = [...ahead, ...drafted];
    bool fits(Recipe r) => !week.any((w) => nearTwins(w, r)) && r.tags.every((t) => week.where((w) => w.tags.contains(t)).length < _mostOfAKind);
    // With nothing varied left, the best of the rest is still a dinner.
    final pick = ranked.firstWhere((s) => fits(s.recipe), orElse: () => ranked.first);
    String? cook;
    if (has == null) {
      cook = usualCook(date);
      if (cook == null) {
        final a = nights[people[0]]!, b = nights[people[1]]!;
        // Whoever has fewer nights; level, whoever did not cook the night before.
        cook = a != b ? (a < b ? people[0] : people[1]) : (before == people[0] ? people[1] : people[0]);
      }
      nights[cook] = nights[cook]! + 1;
    }
    before = has ?? cook;
    drafted.add(pick.recipe);
    out.add(DraftNight(date: date, slug: pick.recipe.slug, cook: cook, why: pick.why.isEmpty ? '' : pick.why.first));
  }
  return out;
}

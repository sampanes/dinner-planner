// Help choosing a dinner: which recipes suit this week, and a search that
// forgives a typo.
//
// The phone knows three things the recipe site's "Can't decide?" does not:
// what is already planned, what those dinners make you buy, and so which
// recipe would use up the other half of the sour cream. A suggestion is
// scored on how the two of you rated it, on how much of it is already on the
// shopping list, and on not being the fourth beef dinner of the week, and it
// says why in a few words.

import 'dart:math';

import '../core/shopping.dart';
import '../core/store_order.dart';
import 'recipes.dart';

class Suggestion {
  const Suggestion(this.recipe, this.score, this.why);

  final Recipe recipe;
  final double score;

  /// Short reasons, the strongest first.
  final List<String> why;
}

/// In the house whatever the week holds, so sharing them saves nothing.
const Set<String> _alwaysAround = {'butter', 'garlic'};

/// What a dinner makes you buy that another dinner could share: things with
/// an amount, leaving out the spice shelf (every recipe uses oil and salt).
Set<String> _bought(Recipe r) => {
      for (final i in r.ingredients)
        if (parseAmount(i.amount).number != null && guessSection(i.id) != 'spices' && !_alwaysAround.contains(i.id)) i.id,
    };

/// [pool] ranked for a week that already has [planned] in it. Recipes that
/// are already planned are left out. [names] are the two people, by color.
List<Suggestion> suggest(Iterable<Recipe> pool, {Iterable<Recipe> planned = const [], Map<String, String> names = const {}}) {
  final taken = {for (final r in planned) r.slug};
  final buying = <String, String>{};
  final kinds = <String, int>{};
  for (final r in planned) {
    final own = _bought(r);
    for (final i in r.ingredients) {
      if (own.contains(i.id)) buying[i.id] = i.name;
    }
    if (r.categories.isNotEmpty) kinds[r.categories.first] = (kinds[r.categories.first] ?? 0) + 1;
  }

  // How many recipes use each thing: the rarer one is the better reason.
  final uses = <String, int>{};
  for (final r in pool) {
    for (final id in _bought(r)) {
      uses[id] = (uses[id] ?? 0) + 1;
    }
  }

  final out = <Suggestion>[];
  for (final r in pool) {
    if (taken.contains(r.slug)) continue;
    final stars = r.pink + r.blue;
    // Untried recipes sit level with a middling rating, so they get their turn.
    var score = stars == 0 ? 1.5 : stars * 0.3;
    final why = <String>[];

    final shared = [for (final id in _bought(r)) if (buying.containsKey(id)) id]
      ..sort((a, b) {
        final c = (uses[a] ?? 0).compareTo(uses[b] ?? 0);
        return c != 0 ? c : buying[a]!.compareTo(buying[b]!);
      });
    if (shared.isNotEmpty) {
      score += min(shared.length, 3) * 0.6;
      final more = shared.length - 2;
      why.add('Shares ${shared.take(2).map((id) => buying[id]).join(', ')}${more > 0 ? ' +$more' : ''} with this week');
    }

    if (r.pink >= 4 && r.blue >= 4) {
      why.add('You both love it');
    } else if (r.pink >= 4 || r.blue >= 4) {
      final who = r.pink >= 4 ? 'pink' : 'blue';
      why.add('${names[who] ?? (who == 'pink' ? 'Pink' : 'Blue')}\'s pick');
    } else if (stars == 0) {
      why.add('Not tried yet');
    }

    if (r.categories.isNotEmpty && taken.isNotEmpty) {
      final same = kinds[r.categories.first] ?? 0;
      score -= min(same, 3) * 0.5;
      if (same == 0) why.add('No ${r.categories.first.toLowerCase()} yet this week');
    }
    out.add(Suggestion(r, score, why));
  }
  out.sort((a, b) {
    final c = b.score.compareTo(a.score);
    return c != 0 ? c : a.recipe.name.toLowerCase().compareTo(b.recipe.name.toLowerCase());
  });
  return out;
}

/// Everything about a recipe a search should look in, lower case.
String searchText(Recipe r) => '${r.name} ${r.categories.join(' ')} ${r.tags.join(' ')} ${r.ingredients.map((i) => i.text).join(' ')}'.toLowerCase();

/// True when every word of [query] is in [text] (from [searchText]), give or
/// take a typo: "zuchini" finds zucchini, "chiken" finds chicken, and a word
/// still being typed finds what it is the start of.
bool searchMatches(String text, String query) {
  final wanted = query.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty);
  List<String>? words;
  for (final w in wanted) {
    if (text.contains(w)) continue;
    if (w.length < 4) return false;
    final slack = w.length >= 8 ? 2 : 1;
    words ??= text.split(RegExp(r'[^a-z0-9]+'));
    if (!words.any((h) => _near(h, w, slack))) return false;
  }
  return true;
}

/// Is [typed] within [slack] slips of [word], or of the start of it?
bool _near(String word, String typed, int slack) {
  if (word.length < typed.length - slack) return false;
  for (var len = typed.length - 1; len <= typed.length + 1; len++) {
    if (len < 1 || len > word.length) continue;
    if (_slips(word.substring(0, len), typed, slack) <= slack) return true;
  }
  return false;
}

/// How many letters must be added, dropped or changed to turn [a] into [b];
/// gives up (returns more than [most]) once it is clearly too many.
int _slips(String a, String b, int most) {
  if ((a.length - b.length).abs() > most) return most + 1;
  var row = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final next = List<int>.filled(b.length + 1, i);
    for (var j = 1; j <= b.length; j++) {
      final swap = row[j - 1] + (a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1);
      next[j] = min(swap, min(row[j], next[j - 1]) + 1);
    }
    row = next;
  }
  return row[b.length];
}

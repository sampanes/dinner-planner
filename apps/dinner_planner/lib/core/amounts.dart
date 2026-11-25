// What a recipe's cups and spoonfuls come to in what a store sells.
//
// A recipe asks for "1 1/2 cups" of cheese and the bag says "8 oz". The two
// meet through what a cup of the thing weighs, which is known closely enough
// for shopping: nobody needs the gram, only whether one bag will do. The
// same goes for things counted whole ("3 onions" against a 3 lb bag), through
// what one of them weighs.
//
// Both tables are guesses from the ingredient's name, checked from the top;
// the first row with a word in the name wins, so the narrow cases sit above
// the broad ones ("cream cheese" above "cheese", "tomato paste" above
// "tomato"). A row with no number means "no idea", and stops the search.

import 'shopping.dart';

// Each unit as a kind of measure and how many of that kind's base it is:
// ounces for weight, teaspoons for volume, one for things counted.
const Map<String, (String, double)> _measures = {
  'oz': ('weight', 1), 'lb': ('weight', 16), 'g': ('weight', 0.03527396), 'kg': ('weight', 35.27396),
  'tsp': ('volume', 1), 'tbsp': ('volume', 3), 'floz': ('volume', 6), 'cup': ('volume', 48), 'pt': ('volume', 96), 'qt': ('volume', 192), 'gal': ('volume', 768), 'ml': ('volume', 0.202884), 'l': ('volume', 202.884),
  '': ('count', 1), 'ct': ('count', 1),
  // A head of garlic is about ten cloves; a thumb of ginger about an ounce.
  'clove': ('count', 0.1), 'thumb': ('weight', 1),
};

const double _teaspoonsInACup = 48;

/// The kind of measure a unit is ('weight', 'volume' or 'count'), or null
/// for a unit the app cannot add up.
String? measureKind(String unit) => _measures[unit]?.$1;

// Ounces one cup weighs. The flag says the thing is sold by weight, so the
// list reads better in ounces than in cups; false is for what comes in a
// bottle marked in fluid ounces, where the number is only for the odd one
// that is not.
const List<(double?, bool, List<String>)> _cups = [
  (null, false, ['juice', 'zest', 'concentrate', 'roux', 'ravioli', 'tortelloni', 'tortellini', 'gnocchi', 'pasta', 'noodle', 'chip', 'cracker', 'crouton']),
  (9.5, false, ['peanut butter', 'almond butter', 'tomato paste', 'paste', 'ketchup', 'sriracha', 'mustard']),
  (8, true, ['cream cheese', 'butter']),
  (8.5, true, ['sour cream', 'creme fraiche', 'yogurt', 'ricotta', 'cottage cheese', 'guacamole', 'hummus']),
  (8, false, ['mayonnaise', 'crema', 'aioli']),
  (3, true, ['parmesan', 'pecorino']),
  (5, true, ['feta', 'blue cheese', 'goat cheese', 'cotija', 'queso fresco']),
  (4, true, ['cheese', 'cheddar', 'mozzarella']),
  (2, true, ['panko']),
  (4, true, ['breadcrumb']),
  (8.4, false, ['vinegar', 'sauce', 'glaze', 'dressing', 'salsa', 'stock', 'broth', 'milk', 'cream', 'water', 'wine']),
  (7.7, false, ['oil']),
  (12, true, ['honey', 'molasses']),
  (11, false, ['syrup']),
  (4, true, ['powdered sugar', 'confectioner']),
  (7.5, true, ['brown sugar']),
  (7, true, ['sugar']),
  (4.25, true, ['flour']),
  (4.5, true, ['cornstarch']),
  (6.5, true, ['rice']),
  (6, true, ['couscous', 'quinoa', 'lentil', 'barley', 'farro', 'bulgur']),
  (3.2, true, ['oat']),
  (10, true, ['salt']),
  (5, true, ['garlic powder', 'onion powder', 'sesame']),
  (1.6, true, ['italian seasoning', 'oregano', 'thyme', 'basil', 'parsley', 'dill', 'rosemary', 'herb']),
  (3, true, ['flake']),
  (4, true, ['spice', 'seasoning', 'powder', 'cumin', 'paprika', 'cinnamon', 'black pepper']),
];

// Ounces one of them weighs: the middling one in the bin.
const List<(double?, List<String>)> _eaches = [
  (1.5, ['tomato paste']),
  (0.35, ['stock concentrate']),
  (null, ['powder', 'fried onion', 'juice', 'zest', 'sauce', 'paste', 'crushed', 'diced', 'dried', 'chip', 'jack', 'flake', 'seasoning', 'spice', 'hash brown', 'soup', 'salsa', 'grape tomato', 'cherry tomato']),
  (0.5, ['scallion', 'green onion']),
  (1.5, ['shallot']),
  (8, ['onion']),
  (4, ['lemon']),
  (2.5, ['lime']),
  (3.5, ['roma tomato', 'plum tomato']),
  (5.5, ['tomato']),
  (7, ['zucchini', 'yellow squash']),
  (6, ['bell pepper']),
  (4, ['poblano']),
  (2.5, ['long green pepper', 'anaheim']),
  (0.6, ['jalapeno', 'chili pepper', 'serrano']),
  (8, ['sweet potato']),
  (6, ['potato']),
  (6.5, ['apple', 'orange', 'pear']),
  (2.5, ['carrot']),
  (3, ['mini cucumber', 'persian cucumber']),
  (10, ['cucumber']),
  (2, ['garlic']),
  (7, ['avocado']),
  (4.5, ['banana']),
  (4, ['ginger']),
];

RegExp _words(List<String> words) => RegExp('\\b(?:${words.join('|')})(?:e?s)?\\b');

final List<(double?, bool, RegExp)> _cupMatchers = [for (final (oz, dry, words) in _cups) (oz, dry, _words(words))];
final List<(double?, RegExp)> _eachMatchers = [for (final (oz, words) in _eaches) (oz, _words(words))];

String _plain(String ingredient) => ingredient.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

final Map<String, (double?, bool)> _cupOf = {};
final Map<String, double?> _eachOf = {};

(double?, bool) _cup(String ingredient) => _cupOf.putIfAbsent(ingredient, () {
      final text = _plain(ingredient);
      for (final (oz, dry, words) in _cupMatchers) {
        if (words.hasMatch(text)) return (oz, dry && oz != null);
      }
      return (null, false);
    });

/// The ounces a cup of [ingredient] (an id or a name) weighs, or null when
/// the app has no idea.
double? cupWeighs(String ingredient) => _cup(ingredient).$1;

/// True for something sold by weight that recipes measure by the cup or the
/// spoon: cheese, flour, rice, sour cream.
bool soldByWeight(String ingredient) => _cup(ingredient).$2;

/// The ounces one whole [ingredient] weighs (an onion, a lemon), or null.
double? eachWeighs(String ingredient) => _eachOf.putIfAbsent(ingredient, () {
      final text = _plain(ingredient);
      for (final (oz, words) in _eachMatchers) {
        if (words.hasMatch(text)) return oz;
      }
      return null;
    });

/// The [totals] of a list line as one number of [kind]: ounces for 'weight',
/// teaspoons for 'volume', how many for 'count'. Null when a part of it
/// cannot be turned into that kind for this [ingredient].
double? measureIn(String kind, Map<String, double> totals, String ingredient) {
  if (totals.isEmpty) return null;
  final cup = cupWeighs(ingredient), each = eachWeighs(ingredient);
  var sum = 0.0;
  for (final e in totals.entries) {
    final m = _measures[e.key];
    if (m == null) return null;
    final amount = e.value * m.$2;
    if (m.$1 == kind) {
      sum += amount;
      continue;
    }
    // Through its weight, the one thing all three kinds can be turned into.
    final double? oz = switch (m.$1) {
      'weight' => amount,
      'volume' => cup == null ? null : amount / _teaspoonsInACup * cup,
      _ => each == null ? null : amount * each,
    };
    if (oz == null) return null;
    if (kind == 'weight') {
      sum += oz;
    } else if (kind == 'volume') {
      if (cup == null) return null;
      sum += oz / cup * _teaspoonsInACup;
    } else {
      if (each == null) return null;
      sum += oz / each;
    }
  }
  return sum;
}

final RegExp _fluid = RegExp(r'^[\s\d./]*fl\.?\s*oz', caseSensitive: false);

/// A packet size as written on the shelf ("16 oz", "12 fl oz", "6 ct").
Quantity parsePack(String text) {
  final q = parseAmount(text);
  return _fluid.hasMatch(text) ? Quantity(q.number, 'floz') : q;
}

/// How many packets of [size] cover the [totals] a list line asks for, or
/// null when the two cannot be compared. Knowing the [ingredient] is what
/// lets cups of cheese meet a bag sold by weight.
int? packsNeeded(Map<String, double> totals, String size, {String ingredient = ''}) {
  final pack = parsePack(size);
  final packKind = _measures[pack.unit];
  final n = pack.number;
  if (packKind == null || n == null || n <= 0 || totals.isEmpty) return null;
  var asked = totals;
  if (pack.unit == 'floz' && totals.containsKey('oz')) {
    // A recipe's "8 oz" of something sold by the fluid ounce means those.
    asked = {
      for (final e in totals.entries)
        if (e.key != 'oz' && e.key != 'floz') e.key: e.value,
      'floz': (totals['floz'] ?? 0) + totals['oz']!,
    };
  }
  final need = measureIn(packKind.$1, asked, ingredient);
  if (need == null) return null;
  final count = (need / (n * packKind.$2) - 1e-9).ceil();
  return count < 1 ? 1 : count;
}

/// What one weighed pack of [size] ("1.05 lb") comes to against what a list
/// line needs, said in a few words; null when the two cannot be compared.
String? packNote(ShopLine line, String size, {bool byPound = false}) {
  final pack = parsePack(size);
  final kind = _measures[pack.unit];
  final n = pack.number;
  if (kind == null || kind.$1 != 'weight' || n == null || n <= 0) return null;
  final need = measureIn('weight', line.totals, line.id);
  if (need == null || need <= 0) return null;
  final have = n * kind.$2;
  final needed = formatWeight(need, byPound: byPound);
  // Half an ounce either way is the same pack.
  if (have + 0.5 >= need) return '$size covers the $needed needed.';
  return '$size, and the dinners need $needed: ${formatWeight(need - have, byPound: byPound)} short.';
}

String _trim(double n, int places) {
  final s = n.toStringAsFixed(places);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

/// [oz] as a shelf would say it: "6 oz", "1 1/2 oz", and with [byPound]
/// "1.25 lb" from a pound up, the way a meat label reads. Rounded to what a
/// shopper can use: whole ounces from ten up, halves below, quarters below
/// two.
String formatWeight(double oz, {bool byPound = false}) {
  if (byPound && oz >= 16) return '${_trim(oz / 16, 2)} lb';
  final rounded = oz >= 10 ? oz.roundToDouble() : (oz >= 2 ? (oz * 2).round() / 2 : (oz * 4).round() / 4);
  return '${formatNumber(rounded < 0.25 ? 0.25 : rounded)} oz';
}

/// What a list line says to take off the shelf, and under it what the
/// recipes asked for when that reads differently (null when it does not).
typedef ShopAmount = ({String lead, String? asked});

/// The amount of a list line in what a store sells. With the household's
/// packet [size] it is a number of packets ("2 × 8 oz"); without one, cups
/// and spoons of something sold by weight become ounces. [byPound] is for
/// the sections priced by the pound.
ShopAmount shopAmount(ShopLine line, {String? size, bool byPound = false}) {
  final asked = line.amountText;
  if (line.totals.isEmpty) return (lead: '', asked: null);
  if (size != null) {
    final packs = packsNeeded(line.totals, size, ingredient: line.id);
    if (packs != null) return (lead: '$packs × $size', asked: asked);
  }
  final kinds = {for (final unit in line.totals.keys) measureKind(unit)};
  if (kinds.length == 1 && kinds.single == 'count') return (lead: asked, asked: null);
  final oz = measureIn('weight', line.totals, line.id);
  if (oz == null) return (lead: asked, asked: null);
  // Already a weight: only said the way the shelf says it ("13.76 oz" of
  // tomatoes is a 14 oz carton).
  if (kinds.length == 1 && kinds.single == 'weight') return (lead: formatWeight(oz, byPound: byPound), asked: null);
  // What comes in a bottle stays in spoons and cups; and under an ounce any
  // jar will do, so the spoonful says more.
  if (kinds.contains('volume') && !soldByWeight(line.id) || oz < 1) return (lead: asked, asked: null);
  return (lead: formatWeight(oz, byPound: byPound), asked: asked);
}

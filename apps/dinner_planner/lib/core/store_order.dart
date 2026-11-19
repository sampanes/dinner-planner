// Where things are, and how much of them a packet holds.
//
// Nobody should have to type a store's layout. Every ingredient gets a
// section from its name (a guess the household can correct), and the order of
// a particular store is learned: while someone is shopping there, each line
// they tick is noted as coming after the one ticked before it. A couple of
// trips and the list reads in the order that person walks that store.
//
// The shared facts, all kept for good:
//   size/<ingredient>          what one packet holds ("16 oz")
//   sec/<ingredient>           its section, when the guess was wrong
//   store/<store>              a store's name
//   at/<store>/<ingredient>    a note on where it is there ("Aisle 7")
//   pos/<store>/<ingredient>   its place in the walk through that store

import 'dart:math';

import 'shopping.dart';

String sizeKey(String id) => 'size/$id';
String sectionKey(String id) => 'sec/$id';
String storeKey(String store) => 'store/$store';
String atKey(String store, String id) => 'at/$store/$id';
String posKey(String store, String id) => 'pos/$store/$id';

/// The sections, in the order a list is shown before a store's own order is
/// known.
const Map<String, String> sections = {
  'produce': 'Produce',
  'bakery': 'Bakery & bread',
  'deli': 'Deli',
  'meat': 'Meat & seafood',
  'dairy': 'Dairy & chilled',
  'frozen': 'Frozen',
  'dry': 'Pasta, rice & grains',
  'canned': 'Cans, jars & soup',
  'spices': 'Baking, oil & spices',
  'sauces': 'Sauces & condiments',
  'snacks': 'Snacks',
  'drinks': 'Drinks',
  'other': 'Somewhere else',
};

/// A short id for a store name ("Trader Joe's" -> "trader-joe-s"), or '' when the name has
/// nothing to make one from.
String storeSlug(String name) {
  final s = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return s.length > 24 ? s.substring(0, 24) : s;
}

// Checked from the top; the first rule with a word in the name wins, so the
// narrow cases sit above the broad ones ("green beans" above "beans",
// "garlic powder" above "garlic").
const List<(String, List<String>)> _rules = [
  ('produce', ['green bean', 'basil paste', 'guacamole']),
  ('frozen', ['ice cream', 'frozen', 'hash brown', 'falafel', 'pea', 'waffle']),
  ('snacks', ['chip', 'cracker', 'pretzel', 'popcorn']),
  ('bakery', ['tortilla']),
  ('dairy', ['ravioli', 'tortelloni', 'tortellini', 'gnocchi', 'fresh fusilli', 'fresh pasta']),
  ('canned', ['bean', 'chickpea', 'crushed tomato', 'diced tomato', 'tomato paste', 'tomato sauce', 'marinara', 'concentrate', 'stock', 'broth', 'fried onion', 'coconut milk', 'peanut butter', 'jam', 'soup', 'tuna', 'olive']),
  ('spices', ['spice', 'seasoning', 'powder', 'flake', 'cumin', 'salt', 'sugar', 'flour', 'panko', 'breadcrumb', 'sesame', 'honey', 'oil', 'vinegar', 'vanilla', 'baking', 'oregano', 'paprika', 'cinnamon', 'yeast', 'cornstarch', 'black pepper']),
  ('drinks', ['juice', 'soda', 'coffee', 'tea', 'water', 'wine', 'beer']),
  ('meat', ['bacon', 'beef', 'chicken', 'pork', 'turkey', 'sausage', 'steak', 'salmon', 'shrimp', 'fish', 'ham', 'lamb', 'cod', 'tilapia', 'meatball']),
  ('dairy', ['cheese', 'butter', 'cream', 'creme', 'crema', 'yogurt', 'milk', 'queso', 'egg']),
  ('sauces', ['sauce', 'dressing', 'mustard', 'mayonnaise', 'sriracha', 'glaze', 'ketchup', 'salsa', 'crouton', 'paste', 'syrup']),
  ('bakery', ['bun', 'baguette', 'bread', 'dough', 'roll', 'pita', 'naan', 'ciabatta', 'bagel']),
  ('dry', ['pasta', 'rice', 'couscous', 'spaghetti', 'grain', 'noodle', 'quinoa', 'lentil', 'penne', 'rigatoni', 'linguine', 'macaroni', 'orzo', 'oat', 'cereal']),
  ('produce', [
    'apple', 'lettuce', 'pepper', 'broccoli', 'mushroom', 'carrot', 'celery', 'chive', 'cilantro', 'corn', 'garlic', 'ginger', 'tomato', 'kale', 'lemon', 'lime', 'cucumber', 'green', 'onion', 'parsley', 'potato', 'scallion', 'shallot', 'spinach', 'thyme', 'zucchini', //
    'avocado', 'basil', 'banana', 'cabbage', 'squash', 'herb', 'jalapeno', 'orange', 'pear', 'rosemary', 'mint', 'dill', 'arugula', 'cauliflower', 'asparagus', 'eggplant', 'radish', 'beet', 'grape', 'berry',
  ]),
];

final List<(String, RegExp)> _matchers = [
  for (final (section, words) in _rules) (section, RegExp('\\b(?:${words.join('|')})(?:e?s)?\\b')),
];

final Map<String, String> _guessed = {};

/// The section an ingredient is most likely in, from its id or its name.
String guessSection(String ingredient) => _guessed.putIfAbsent(ingredient, () {
      final text = ingredient.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
      // On its own it is the grinder, not the vegetable.
      if (text == 'pepper') return 'spices';
      for (final (section, words) in _matchers) {
        if (words.hasMatch(text)) return section;
      }
      return 'other';
    });

/// What to write down when [id] is ticked in a store right after [before]
/// (null for the first line of a trip): the changed places, by ingredient.
/// [walk] is that store's places so far; a smaller number is met sooner.
///
/// A line already further along than the one before it stays where it is.
/// Anything else moves to just after the one before it, so the latest trip
/// wins where two trips disagree.
Map<String, double> learnWalk(Map<String, double> walk, String id, String? before) {
  final current = walk[id];
  final p = before == null || before == id ? null : walk[before];
  if (p == null) {
    if (current != null) return const {};
    return {id: walk.isEmpty ? 0 : walk.values.reduce(min) - 1};
  }
  if (current != null && current > p) return const {};
  double? next;
  walk.forEach((key, value) {
    if (key != id && value > p && (next == null || value < next!)) next = value;
  });
  final after = next;
  if (after == null) return {id: p + 1};
  if (after - p > 1e-6) return {id: (p + after) / 2};
  // The gap between the two has been halved away: number the walk afresh.
  final order = [for (final key in walk.keys) if (key != id) key]
    ..sort((a, b) {
      final c = walk[a]!.compareTo(walk[b]!);
      return c != 0 ? c : a.compareTo(b);
    });
  order.insert(order.indexOf(before!) + 1, id);
  return {
    for (var i = 0; i < order.length; i++)
      if (walk[order[i]] != i.toDouble()) order[i]: i.toDouble(),
  };
}

/// Some lines of the list that share a section.
class ShopGroup {
  const ShopGroup(this.section, this.lines);

  final String section;
  final List<ShopLine> lines;
}

/// The list in walking order: sections in the order [walk] has met them
/// (ones it has not met come after, in the usual order), and inside a section
/// the lines it has met first, then the rest by name.
List<ShopGroup> arrange(Iterable<ShopLine> lines, {required String Function(String id) sectionOf, Map<String, double> walk = const {}}) {
  final sums = <String, double>{}, counts = <String, int>{};
  walk.forEach((id, p) {
    final s = sectionOf(id);
    sums[s] = (sums[s] ?? 0) + p;
    counts[s] = (counts[s] ?? 0) + 1;
  });
  double? met(String s) => counts[s] == null ? null : sums[s]! / counts[s]!;
  final usual = sections.keys.toList();
  int usualPlace(String s) => usual.contains(s) ? usual.indexOf(s) : usual.length;

  final groups = <String, List<ShopLine>>{};
  for (final l in lines) {
    groups.putIfAbsent(sectionOf(l.id), () => []).add(l);
  }
  final names = groups.keys.toList()
    ..sort((a, b) {
      final pa = met(a), pb = met(b);
      if (pa != null && pb != null && pa != pb) return pa.compareTo(pb);
      if ((pa == null) != (pb == null)) return pa == null ? 1 : -1;
      return usualPlace(a).compareTo(usualPlace(b));
    });
  return [
    for (final s in names)
      ShopGroup(
        s,
        groups[s]!
          ..sort((a, b) {
            final pa = walk[a.id], pb = walk[b.id];
            if (pa != null && pb != null && pa != pb) return pa.compareTo(pb);
            if ((pa == null) != (pb == null)) return pa == null ? 1 : -1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }),
      ),
  ];
}

// Each unit as a kind of measure and how many of that kind's base it is:
// ounces for weight, teaspoons for volume, one for things counted.
const Map<String, (String, double)> _measures = {
  'oz': ('weight', 1), 'lb': ('weight', 16), 'g': ('weight', 0.03527396), 'kg': ('weight', 35.27396),
  'tsp': ('volume', 1), 'tbsp': ('volume', 3), 'floz': ('volume', 6), 'cup': ('volume', 48), 'pt': ('volume', 96), 'qt': ('volume', 192), 'gal': ('volume', 768), 'ml': ('volume', 0.202884), 'l': ('volume', 202.884),
  '': ('count', 1), 'ct': ('count', 1),
};

final RegExp _fluid = RegExp(r'^[\s\d./]*fl\.?\s*oz', caseSensitive: false);

/// A packet size as written on the shelf ("16 oz", "12 fl oz", "6 ct").
Quantity parsePack(String text) {
  final q = parseAmount(text);
  return _fluid.hasMatch(text) ? Quantity(q.number, 'floz') : q;
}

/// How many packets of [size] cover the [totals] a list line asks for, or
/// null when the two cannot be compared (cups of cheese against a bag sold
/// by weight).
int? packsNeeded(Map<String, double> totals, String size) {
  final pack = parsePack(size);
  final packKind = _measures[pack.unit];
  final n = pack.number;
  if (packKind == null || n == null || n <= 0 || totals.isEmpty) return null;
  var need = 0.0;
  for (final e in totals.entries) {
    var kind = _measures[e.key];
    // A recipe's "8 oz" of something sold by the fluid ounce means those.
    if (e.key == 'oz' && pack.unit == 'floz') kind = _measures['floz'];
    if (kind == null || kind.$1 != packKind.$1) return null;
    need += e.value * kind.$2;
  }
  final count = (need / (n * packKind.$2) - 1e-9).ceil();
  return count < 1 ? 1 : count;
}

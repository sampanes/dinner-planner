// The shopping list: the ingredients of every planned dinner, added up.
//
// Two more kinds of shared fact hang off it. "buy/<ingredient>" is what the
// household actually takes off the shelf for that ingredient (a brand, the
// name on the packet). "got/<ingredient>/<day>" says the ingredient for that
// day's dinner is in the house; it is keyed by day so that a dinner planned
// later asks for the ingredient again, and so old ticks age out with the
// days they belong to.
//
// The list also takes things no dinner asks for: milk, coffee, foil.
// "extra/<id>" is the name of one the household buys, kept so it can be put
// back with a tap or a scan; "want/<id>" is set while it is on the list.

String buyKey(String id) => 'buy/$id';
String gotKey(String id, String day) => 'got/$id/$day';
String extraKey(String id) => 'extra/$id';
String wantKey(String id) => 'want/$id';

/// `have/<id>` is '1' for something the household always has in the house and
/// '0' for something it does not, where the app guessed that it does. A staple
/// is never on the list for a dinner; it goes on when someone says it has run
/// out (`want/<id>`), and comes off again when it is bought.
String haveKey(String id) => 'have/$id';

/// What nearly every kitchen has, so nobody has to say so. `have/<id>` = '0'
/// takes one out.
const Set<String> usualStaples = {'salt', 'pepper', 'black-pepper', 'oil', 'olive-oil', 'cooking-oil', 'vegetable-oil', 'butter', 'sugar', 'flour', 'water'};

/// Whether [id] is always in the house, given what `have/<id>` holds.
bool isStaple(String id, Object? said) => said == '1' || (said != '0' && usualStaples.contains(id));

/// The id a name gets: "Dish soap" -> "dish-soap".
String slugOf(String s) {
  final slug = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.length > 48 ? slug.substring(0, 48) : slug;
}

/// One line of a recipe, as the recipe site publishes it.
class Ingredient {
  const Ingredient({required this.id, required this.name, this.amount = '', required this.text});

  /// The same for one ingredient across every recipe ("ground-beef").
  final String id;
  final String name;

  /// "2", "1/2 cup", "to taste".
  final String amount;

  /// The whole line as a person reads it ("20 ounce ground beef").
  final String text;

  Map<String, Object?> toJson() => {'id': id, 'displayName': name, 'amountText': amount, 'text': text};

  static Ingredient? fromJson(Object? raw) {
    if (raw is String && raw.isNotEmpty) return Ingredient(id: slugOf(raw), name: raw, text: raw);
    if (raw is! Map) return null;
    final text = raw['text'], name = raw['displayName'] ?? raw['canonicalName'], id = raw['id'], amount = raw['amountText'];
    final shown = name is String && name.isNotEmpty ? name : (text is String ? text : null);
    if (shown == null) return null;
    return Ingredient(
      id: id is String && id.isNotEmpty ? id : slugOf(shown),
      name: shown,
      amount: amount is String ? amount : '',
      text: text is String && text.isNotEmpty ? text : shown,
    );
  }
}

/// An amount as a number and a unit. No number means "to taste" or anything
/// else that cannot be added up.
class Quantity {
  const Quantity(this.number, this.unit);

  final double? number;

  /// '' for things counted whole, else one short form per unit ("oz").
  final String unit;
}

const Map<String, String> _units = {
  'unit': '', 'units': '', 'each': '', 'whole': '',
  'oz': 'oz', 'ounce': 'oz', 'ounces': 'oz',
  'lb': 'lb', 'lbs': 'lb', 'pound': 'lb', 'pounds': 'lb',
  'tbsp': 'tbsp', 'tablespoon': 'tbsp', 'tablespoons': 'tbsp',
  'tsp': 'tsp', 'teaspoon': 'tsp', 'teaspoons': 'tsp',
  'cup': 'cup', 'cups': 'cup',
  'clove': 'clove', 'cloves': 'clove',
  'g': 'g', 'gram': 'g', 'grams': 'g',
  'kg': 'kg', 'kilogram': 'kg', 'kilograms': 'kg',
  'ml': 'ml', 'milliliter': 'ml', 'milliliters': 'ml',
  'l': 'l', 'liter': 'l', 'liters': 'l', 'litre': 'l', 'litres': 'l',
  'pt': 'pt', 'pint': 'pt', 'pints': 'pt',
  'qt': 'qt', 'quart': 'qt', 'quarts': 'qt',
  'gal': 'gal', 'gallon': 'gal', 'gallons': 'gal',
  'ct': 'ct', 'count': 'ct', 'pk': 'ct', 'pack': 'ct', 'packs': 'ct',
};

final RegExp _amount = RegExp(r'^\s*(?:(\d+)\s*/\s*(\d+)|(\d+(?:\.\d+)?)(?:\s+(\d+)\s*/\s*(\d+))?)\s*([A-Za-z]*)');

Quantity parseAmount(String text) {
  final m = _amount.firstMatch(text);
  if (m == null) return const Quantity(null, '');
  double number;
  if (m.group(1) != null) {
    final below = int.parse(m.group(2)!);
    if (below == 0) return const Quantity(null, '');
    number = int.parse(m.group(1)!) / below;
  } else {
    number = double.parse(m.group(3)!);
    final below = m.group(5) == null ? 0 : int.parse(m.group(5)!);
    if (below != 0) number += int.parse(m.group(4)!) / below;
  }
  final word = m.group(6)!.toLowerCase();
  return Quantity(number, _units[word] ?? word);
}

/// A dinner on the plan, for the list to be built from.
class ShopDinner {
  const ShopDinner({required this.day, required this.slug, required this.ingredients});

  final String day;
  final String slug;
  final List<Ingredient> ingredients;
}

class ShopUse {
  const ShopUse(this.day, this.slug);

  final String day;
  final String slug;
}

class ShopLine {
  ShopLine(this.id, this.name, {this.extra = false});

  final String id;
  final String name;

  /// True for something no planned dinner asks for.
  final bool extra;

  /// The total per unit, in the order the units were first met.
  final Map<String, double> totals = {};

  /// The dinners that need it, in day order, once per dinner.
  final List<ShopUse> uses = [];

  /// True when nothing about it could be counted: salt, oil.
  bool get loose => totals.isEmpty && !extra;

  /// "3", "20 oz", "1 1/2 cups + 2 tbsp"; empty for a loose line.
  String get amountText => [for (final e in totals.entries) formatAmount(e.value, e.key)].join(' + ');
}

/// Every ingredient the [dinners] need, one line each, sorted by name.
/// [where] picks which ingredient-on-a-day pairs count, which is how the
/// list is split into what is still to get and what is already in the house.
List<ShopLine> shoppingList(Iterable<ShopDinner> dinners, {bool Function(String id, String day)? where}) {
  final lines = <String, ShopLine>{};
  final ordered = dinners.toList()..sort((a, b) => a.day.compareTo(b.day));
  for (final d in ordered) {
    for (final i in d.ingredients) {
      if (where != null && !where(i.id, d.day)) continue;
      final line = lines.putIfAbsent(i.id, () => ShopLine(i.id, i.name));
      if (!line.uses.any((u) => u.day == d.day)) line.uses.add(ShopUse(d.day, d.slug));
      final q = parseAmount(i.amount);
      final n = q.number;
      if (n != null && n > 0) line.totals[q.unit] = (line.totals[q.unit] ?? 0) + n;
    }
  }
  return lines.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

const Map<int, String> _fractions = {25: '1/4', 33: '1/3', 50: '1/2', 67: '2/3', 75: '3/4'};

String formatNumber(double n) {
  final whole = n.floor();
  final hundredths = ((n - whole) * 100).round();
  if (hundredths == 0) return '$whole';
  if (hundredths == 100) return '${whole + 1}';
  final part = _fractions[hundredths];
  if (part != null) return whole == 0 ? part : '$whole $part';
  return n.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
}

String formatAmount(double n, String unit) {
  final number = formatNumber(n);
  if (unit.isEmpty) return number;
  final many = n > 1 && (unit == 'cup' || unit == 'clove');
  return '$number $unit${many ? 's' : ''}';
}

// Reading a label with the camera: a price sticker on a tray of meat, a
// shelf tag, the front of a packet. The phone turns the picture into lines
// of text (on the phone itself; no picture leaves it) and this file turns
// the lines into a name and a size.
//
// It is for what a barcode cannot say. A store prints its own barcode on
// what it weighs, which no public list knows, and plenty of store brands
// are on neither list. The words are on the label all the same.

import 'package:flutter/services.dart';

import 'products.dart';

/// One line of text in a picture, and how tall its letters are there. The
/// name of a thing is nearly always the tallest words on its label.
typedef LabelLine = ({String text, double height});

/// What a label says: the lines that read like a name, from the top, and the
/// size printed on it ("1.33 lb", "8 oz", or '' when none was found).
class Label {
  const Label({this.lines = const [], this.size = ''});

  final List<LabelLine> lines;
  final String size;

  bool get isEmpty => lines.isEmpty && size.isEmpty;

  /// Every name-like word on it, for matching against ingredients.
  String get text => [for (final l in lines) l.text].join(' ');
}

const Map<String, String> _unitNames = {
  'oz': 'oz', 'ounce': 'oz', 'ounces': 'oz',
  'lb': 'lb', 'lbs': 'lb', 'pound': 'lb', 'pounds': 'lb',
  'kg': 'kg', 'g': 'g', 'gram': 'g', 'grams': 'g',
  'ml': 'ml', 'l': 'l', 'liter': 'l', 'liters': 'l',
  'ct': 'ct', 'count': 'ct', 'pk': 'ct', 'pack': 'ct',
};

// A number and a unit, with the slips a camera makes: "0Z" for "OZ", "Ib"
// and "1b" for "lb". Not a number that is part of a price or of a longer
// number, and not a unit that is the bottom of a rate ("oz/serving").
final RegExp _sized = RegExp(
  r'(?<![\$\d.,/])(\d{1,4}(?:[.,]\d{1,2})?)\s?(fl\.?\s?[o0]z|[o0]z|ounces?|[li1]bs?|pounds?|kg|grams?|g|ml|liters?|l|count|ct|pk|pack)\b(?!\s?/)',
  caseSensitive: false,
);

final RegExp _price = RegExp(r'\$\s?\d+(?:[.,]\d{1,2})?|\d+(?:[.,]\d+)?\s?[¢c]\b', caseSensitive: false);

// Lines about what is in the food, where "9 g" is fat and not a size.
final RegExp _nutrition = RegExp(r'sugars|total fat|sat(?:urated)?\.? fat|trans fat|sodium|carbohydrate|total carb|protein|dietary fiber|cholesterol|vitamin|calcium|potassium|\biron\b|daily value|serving|calories|\bper\b', caseSensitive: false);

final RegExp _weightWord = RegExp(r'\bnet\b|\bwt\b|weight', caseSensitive: false);

// Lines a label carries that are not its name.
final RegExp _notAName = RegExp(
  r'sell by|use by|use or freeze|best (?:by|before|if)|freeze by|packed|pack date|keep (?:refrigerated|frozen)|refrigerate|net\s?wt|net weight|\bweight\b|\bprice\b|\bper\b|\btare\b|safe handling|nutrition|serving|calories|distributed|manufactured|www\.|\.com\b|\bsave\b|\bsale\b|coupon|\bsku\b|\bupc\b|item\s?#|you pay|with card|\breg\b|daily value|product of|inspected|department of|thank you|\btotal\b',
  caseSensitive: false,
);

final RegExp _backOfPack = RegExp(r'^\s*(?:ingredients\b|nutrition facts|contains\s*:)', caseSensitive: false);

String _sizeIn(String line) {
  for (final m in _sized.allMatches(line)) {
    // "$ 5.99 lb" is a price however it is spaced.
    if (line.substring(0, m.start).trimRight().endsWith(r'$')) continue;
    final raw = m.group(2)!.toLowerCase().replaceAll('0', 'o').replaceAll(RegExp(r'[\s.]'), '');
    final unit = raw.startsWith('fl') ? 'fl oz' : _unitNames[raw.replaceFirst(RegExp(r'^[i1]b'), 'lb')];
    if (unit == null) continue;
    return '${m.group(1)!.replaceAll(',', '.')} $unit';
  }
  return '';
}

/// Makes a [Label] of the lines a picture was read into.
Label parseLabel(List<LabelLine> read) {
  var size = '', loose = '';
  final names = <LabelLine>[];
  var back = false;
  for (final line in read) {
    final text = line.text.trim();
    if (text.isEmpty) continue;
    if (_backOfPack.hasMatch(text)) back = true;
    if (!_nutrition.hasMatch(text)) {
      final found = _sizeIn(text);
      if (found.isNotEmpty) {
        // The one beside "NET WT" is the size; any other is second best.
        if (size.isEmpty && _weightWord.hasMatch(text)) size = found;
        if (loose.isEmpty) loose = found;
      }
    }
    // After "Ingredients:" every word is something in it, not what it is.
    if (back || _notAName.hasMatch(text) || _nutrition.hasMatch(text)) continue;
    if (','.allMatches(text).length >= 3) continue;
    final bare = text.replaceAll(_sized, ' ').replaceAll(_price, ' ').replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r"^[^A-Za-z0-9]+|[^A-Za-z0-9%)']+$"), '');
    final letters = RegExp(r'[A-Za-z]').allMatches(bare).length;
    if (letters < 3 || letters * 2 < bare.replaceAll(' ', '').length) continue;
    if (names.length < 8) names.add((text: tidy(bare), height: line.height));
  }
  return Label(lines: names, size: size.isNotEmpty ? size : loose);
}

/// What to call the thing a [label] is on. With the [ingredient] it is for,
/// that is the line saying so in the most words ("Ground Beef 80% Lean" for
/// ground beef); without one, or when no line names it, the tallest line.
String labelName(Label label, {String ingredient = ''}) {
  if (label.lines.isEmpty) return '';
  if (ingredient.isNotEmpty) {
    String? best;
    var most = 0;
    for (final line in label.lines) {
      final hits = sharedWords(line.text, ingredient);
      if (hits > most) {
        most = hits;
        best = line.text;
      }
    }
    if (best != null) return best;
  }
  var tallest = label.lines.first;
  for (final line in label.lines) {
    if (line.height > tallest.height) tallest = line;
  }
  return tallest.text;
}

/// A [label] as a product, for the screens that show what a barcode is.
/// [ingredients] (id -> name) are what it could be for. A pack the store
/// weighed keeps no size: the next one will weigh something else.
Product productFromLabel(String code, Label label, Map<String, String> ingredients) {
  final likely = matchIngredients(label.text, ingredients);
  return Product(
    code: code,
    name: labelName(label, ingredient: likely.isEmpty ? '' : ingredients[likely.first]!),
    size: weighedInStore(code) ? '' : label.size,
    read: true,
  );
}

/// The phone's part: turning a picture into lines of text.
abstract class LabelCamera {
  /// The lines of text in [picture] (a JPEG), from the top. Empty when it
  /// holds none, or when the phone cannot read text.
  Future<List<LabelLine>> read(Uint8List picture);

  /// Opens the phone's own camera for one picture and reads it. Null when
  /// the person backs out or the camera cannot be opened.
  Future<List<LabelLine>?> photograph();
}

class AndroidLabelCamera implements LabelCamera {
  static const MethodChannel _channel = MethodChannel('dinner_planner/app');

  static List<LabelLine> _lines(List<Object?>? raw) => [
        for (final line in raw ?? const <Object?>[])
          if (line is Map && line['text'] is String) (text: line['text'] as String, height: line['height'] is num ? (line['height'] as num).toDouble() : 0),
      ];

  @override
  Future<List<LabelLine>> read(Uint8List picture) async {
    try {
      return _lines(await _channel.invokeListMethod<Object?>('readText', {'picture': picture}).timeout(const Duration(seconds: 8)));
    } on Exception {
      return const [];
    }
  }

  @override
  Future<List<LabelLine>?> photograph() async {
    try {
      final raw = await _channel.invokeListMethod<Object?>('photoText');
      return raw == null ? null : _lines(raw);
    } on Exception {
      return null;
    }
  }
}

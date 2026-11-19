// What a barcode is: the name on the packet, the brand and the size, from two
// free public lists. Only the barcode is sent.
//
//   Open Food Facts   no key; names typed in by volunteers, sizes patchy
//   USDA FoodData     what US makers file themselves, so the brand and the
//   Central           packet size are reliable; a key, or ten lookups an
//                     hour on the shared demo key
//
// A packet neither list has is remembered by the household the first time it
// is scanned ("code/<barcode>" -> ingredient), so a second scan needs nobody.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

String codeKey(String code) => 'code/$code';

class Product {
  const Product({required this.code, this.name = '', this.brand = '', this.size = ''});

  final String code;
  final String name;
  final String brand;

  /// "16 oz", as printed.
  final String size;

  /// The brand and the name as one line, without saying the brand twice.
  String get shelfName {
    if (brand.isEmpty || name.toLowerCase().contains(brand.toLowerCase())) return name;
    return name.isEmpty ? brand : '$brand $name';
  }
}

/// A scanned barcode in the one form it is stored and looked up in: twelve
/// digits for the American kind however the scanner padded it. Null when
/// [raw] is not a product barcode.
///
/// A store prints its own barcode on what it weighs (meat, deli, bakery),
/// starting with 2 and ending in the price. The price part is zeroed so the
/// next pack of the same thing is recognized.
String? canonicalCode(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length != raw.trim().length || digits.length < 8 || digits.length > 14) return null;
  final bare = digits.replaceFirst(RegExp(r'^0+'), '');
  if (bare.isEmpty) return null;
  final code = bare.length <= 12 ? bare.padLeft(12, '0') : bare;
  return weighedInStore(code) ? '${code.substring(0, 6)}000000' : code;
}

/// True for a barcode a store made up for something it weighed. No public
/// list knows those.
bool weighedInStore(String code) => code.length == 12 && code.startsWith('2');

const Duration _patience = Duration(seconds: 8);

/// Looks [code] (from [canonicalCode]) up. Null when neither list has it or
/// neither could be reached.
Future<Product?> lookUpProduct(http.Client client, String code, {String usdaKey = ''}) async {
  if (weighedInStore(code)) return null;
  Future<Product?> quietly(Future<Product?> f) => f.timeout(_patience).then<Product?>((p) => p).catchError((Object _) => null);
  final found = await Future.wait([quietly(_openFoodFacts(client, code)), quietly(_usda(client, code, usdaKey))]);
  final open = found[0], usda = found[1];
  if (open == null && usda == null) return null;
  String pick(String? first, String? second) => first != null && first.isNotEmpty ? first : (second ?? '');
  final product = Product(
    code: code,
    name: pick(open?.name, usda?.name),
    brand: pick(usda?.brand, open?.brand),
    size: pick(usda?.size, open?.size),
  );
  return product.shelfName.isEmpty && product.size.isEmpty ? null : product;
}

Future<Product?> _openFoodFacts(http.Client client, String code) async {
  final res = await client.get(
    Uri.https('world.openfoodfacts.org', '/api/v2/product/$code.json', {'fields': 'product_name,brands,quantity'}),
    headers: const {'User-Agent': 'DinnerPlannerApp (Android)'},
  );
  if (res.statusCode != 200) return null;
  final body = jsonDecode(utf8.decode(res.bodyBytes));
  if (body is! Map || body['status'] != 1) return null;
  final p = body['product'];
  if (p is! Map) return null;
  String text(String key) => p[key] is String ? tidy(p[key] as String) : '';
  return Product(code: code, name: text('product_name'), brand: tidy(text('brands').split(',').first), size: text('quantity'));
}

Future<Product?> _usda(http.Client client, String code, String key) async {
  final res = await client.get(Uri.https('api.nal.usda.gov', '/fdc/v1/foods/search', {
    'api_key': key.isEmpty ? 'DEMO_KEY' : key,
    'query': code,
    'dataType': 'Branded',
    'pageSize': '5',
  }));
  if (res.statusCode != 200) return null;
  final body = jsonDecode(utf8.decode(res.bodyBytes));
  final foods = body is Map ? body['foods'] : null;
  if (foods is! List) return null;
  String bare(Object? s) => s is String ? s.replaceFirst(RegExp(r'^0+'), '') : '';
  for (final f in foods) {
    // The search is by words, so make sure it is this barcode and not a
    // number that happens to appear in a description.
    if (f is! Map || bare(f['gtinUpc']) != bare(code)) continue;
    String text(String k) => f[k] is String ? (f[k] as String).trim() : '';
    final brand = text('brandName').isNotEmpty ? text('brandName') : text('brandOwner');
    // "KROGER, NATURAL SOUR CREAM, SOUR CREAM": drop the brand and repeats.
    final parts = <String>[];
    for (final part in text('description').split(',').map((s) => s.trim())) {
      if (part.isEmpty || part.toLowerCase() == brand.toLowerCase() || parts.any((x) => x.toLowerCase() == part.toLowerCase())) continue;
      parts.add(part);
    }
    return Product(code: code, name: tidy(parts.join(', ')), brand: tidy(brand), size: text('packageWeight').split('/').first.trim());
  }
  return null;
}

/// Single spaces, and Shouting Turned Into Title Case.
String tidy(String s) {
  final t = s.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty || t != t.toUpperCase() || t == t.toLowerCase()) return t;
  return t.toLowerCase().split(' ').map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

String _stem(String word) {
  if (word.endsWith('oes')) return word.substring(0, word.length - 2);
  if (word.endsWith('s') && !word.endsWith('ss') && word.length > 3) return word.substring(0, word.length - 1);
  return word;
}

Set<String> _words(String text) => {for (final w in text.toLowerCase().split(RegExp(r'[^a-z0-9]+'))) if (w.isNotEmpty) _stem(w)};

/// The ingredients (id -> name) a packet called [productText] could be, the
/// likeliest first: the more of an ingredient's words are on the packet the
/// better, and of two equally good the more specific one leads.
List<String> matchIngredients(String productText, Map<String, String> ingredients) {
  final on = _words(productText);
  if (on.isEmpty) return const [];
  final scored = <(String, double, int)>[];
  ingredients.forEach((id, name) {
    final words = _words(name);
    final hits = words.where(on.contains).length;
    if (hits > 0) scored.add((id, hits / words.length, words.length));
  });
  scored.sort((a, b) {
    final byScore = b.$2.compareTo(a.$2);
    if (byScore != 0) return byScore;
    final bySize = b.$3.compareTo(a.$3);
    return bySize != 0 ? bySize : ingredients[a.$1]!.compareTo(ingredients[b.$1]!);
  });
  return [for (final s in scored) s.$1];
}

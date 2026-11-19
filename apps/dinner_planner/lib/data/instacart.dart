// Hands a shopping list to Instacart through its Developer Platform API
// ("create shopping list page"). Instacart answers with the address of a
// page holding the items; opened on a phone it lands in the Instacart app,
// where a person picks the products and adds them to the cart. Nothing can
// be read back: the API has no view of anyone's cart or lists.
//
// The key is a secret of the person who owns it and is typed into Settings.
// A key made for testing only works on Instacart's test address, so that is
// tried when the live address turns the key down.

import 'dart:convert';

import 'package:http/http.dart' as http;

const String instacartLive = 'https://connect.instacart.com';
const String instacartTest = 'https://connect.dev.instacart.tools';

/// Our unit names as Instacart spells them. A unit that is not here (a clove,
/// a thumb) is sent with no measurement.
const Map<String, String> _units = {'': 'each', 'oz': 'ounce', 'lb': 'pound', 'tbsp': 'tablespoon', 'tsp': 'teaspoon', 'cup': 'cup'};

class InstacartItem {
  const InstacartItem({required this.search, required this.shown, this.totals = const {}});

  /// What Instacart looks for: the name the household buys, else the
  /// ingredient.
  final String search;

  /// The line a person sees on the page.
  final String shown;
  final Map<String, double> totals;

  Map<String, Object?> toJson() => {
        'name': search,
        'display_text': shown,
        'line_item_measurements': [
          for (final e in totals.entries)
            if (_units[e.key] case final unit?) {'quantity': e.value, 'unit': unit}
        ],
      };
}

class InstacartError implements Exception {
  const InstacartError(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<Uri> createInstacartList(http.Client client, {required String key, required String title, required List<InstacartItem> items}) async {
  if (key.isEmpty) throw const InstacartError('Add an Instacart key in Settings first.');
  if (items.isEmpty) throw const InstacartError('Nothing is left to get.');
  final body = jsonEncode({
    'title': title,
    'link_type': 'shopping_list',
    'expires_in': 30,
    'line_items': [for (final i in items) i.toJson()],
  });
  late http.Response res;
  for (final host in [instacartLive, instacartTest]) {
    res = await client
        .post(
          Uri.parse('$host/idp/v1/products/products_link'),
          headers: {'Authorization': 'Bearer $key', 'Accept': 'application/json', 'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 401 && res.statusCode != 403) break;
  }
  if (res.statusCode == 401 || res.statusCode == 403) throw const InstacartError('Instacart did not accept the key.');
  if (res.statusCode ~/ 100 != 2) throw InstacartError('Instacart answered ${res.statusCode}.');
  final Object? raw;
  try {
    raw = jsonDecode(utf8.decode(res.bodyBytes));
  } on FormatException {
    throw const InstacartError('Instacart sent an answer this app cannot read.');
  }
  final url = raw is Map ? raw['products_link_url'] : null;
  final link = url is String ? Uri.tryParse(url) : null;
  if (link == null || !link.hasScheme) throw const InstacartError('Instacart sent no link.');
  return link;
}

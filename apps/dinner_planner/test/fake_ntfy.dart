// An in-memory stand-in for an ntfy server, the recipe site and the two
// product lists a barcode is looked up in, speaking the same HTTP the app
// uses.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeNtfy {
  FakeNtfy({this.keep = const Duration(hours: 12)});

  final Duration keep;
  final List<({String id, String topic, int time, String title, String message, String? priority})> messages = [];
  DateTime now = DateTime.utc(2026, 11, 19, 18);
  bool down = false;
  String? requireToken;
  int _next = 1;

  /// Stand-ins for Open Food Facts and the USDA's list: barcode -> what each
  /// says about it, in the shape the real service answers with. Every lookup
  /// is noted in [lookups].
  final Map<String, Map<String, Object?>> openFoodFacts = {};
  final Map<String, Map<String, Object?>> usda = {};
  int usdaStatus = 200;
  final List<String> lookups = [];

  /// What the recipe site serves.
  String recipesJson = jsonEncode([
    {'slug': 'beef-chili', 'displayName': 'Beef Chili', 'image': 'https://img.example/c_fill,w_1200,h_800/chili.jpg', 'categories': ['Beef'], 'tags': ['Spicy'], 'sourceStars': {'pink': 4, 'blue': 5}, 'ingredients': [
      {'id': 'ground-beef', 'displayName': 'ground beef', 'amountText': '1 lb', 'text': '1 lb ground beef'},
      {'id': 'onion', 'displayName': 'onion', 'amountText': '2', 'text': '2 onion'},
      {'id': 'salt', 'displayName': 'salt', 'amountText': 'to taste', 'text': 'salt, to taste'},
    ], 'steps': [
      {'index': 0, 'sourceStep': 1, 'displayText': 'Dice the onion.'},
      {'index': 1, 'sourceStep': 2, 'displayText': 'Brown the beef in a large pot, 5-7 minutes.'},
      {'index': 2, 'sourceStep': 2, 'displayText': 'Stir in the beans and simmer 20 minutes.'},
    ]},
    {'slug': 'shrimp-tacos', 'displayName': 'Shrimp Tacos', 'categories': ['Seafood'], 'ingredients': [{'text': '10 oz shrimp'}]},
    {'slug': 'baked-penne', 'displayName': 'Baked Penne', 'categories': ['Pasta'], 'ingredients': [
      {'id': 'penne', 'displayName': 'penne', 'amountText': '6 oz', 'text': '6 oz penne'},
      {'id': 'onion', 'displayName': 'onion', 'amountText': '1 unit', 'text': '1 onion'},
      {'id': 'ground-beef', 'displayName': 'ground beef', 'amountText': '10 ounce', 'text': '10 ounce ground beef'},
    ]},
  ]);
  String logJson = jsonEncode({'plan': {'id': 'p1', 'slugs': ['beef-chili', 'baked-penne'], 'at': '2026-11-18T00:00:00Z'}, 'cooked': [], 'rated': {}});

  http.Client client() => MockClient((request) async {
        if (down) throw http.ClientException('offline');
        final path = request.url.path;
        const json = {'content-type': 'application/json; charset=utf-8'};
        if (request.url.host == 'world.openfoodfacts.org') {
          final code = path.split('/').last.replaceAll('.json', '');
          lookups.add('off $code');
          final p = openFoodFacts[code];
          if (p == null) return http.Response(jsonEncode({'code': code, 'status': 0, 'status_verbose': 'product not found'}), 404, headers: json);
          return http.Response(jsonEncode({'code': code, 'status': 1, 'product': p}), 200, headers: json);
        }
        if (request.url.host == 'api.nal.usda.gov') {
          final code = request.url.queryParameters['query'];
          lookups.add('usda $code ${request.url.queryParameters['api_key']}');
          if (usdaStatus != 200) return http.Response('{}', usdaStatus);
          final f = usda[code];
          return http.Response(jsonEncode({'totalHits': f == null ? 0 : 1, 'foods': [?f]}), 200, headers: json);
        }
        if (path.endsWith('/data/runtime/recipes.runtime.json')) return http.Response(recipesJson, 200, headers: {'content-type': 'application/json; charset=utf-8'});
        if (path.endsWith('/data/source/log.json')) return http.Response(logJson, 200);
        if (requireToken != null && request.headers['Authorization'] != 'Bearer $requireToken') return http.Response('forbidden', 403);
        final seconds = now.millisecondsSinceEpoch ~/ 1000;
        if (request.method == 'POST') {
          final topic = path.substring(1);
          messages.add((
            id: 'm${_next++}',
            topic: topic,
            time: seconds,
            title: request.url.queryParameters['title'] ?? '',
            message: utf8.decode(request.bodyBytes),
            priority: request.url.queryParameters['priority'],
          ));
          return http.Response('{}', 200);
        }
        if (request.method == 'GET' && path.endsWith('/json')) {
          final topic = path.substring(1, path.length - '/json'.length);
          final since = int.tryParse(request.url.queryParameters['since'] ?? '') ?? 0;
          final lines = [
            for (final m in messages)
              if (m.topic == topic && m.time >= since && seconds - m.time < keep.inSeconds)
                jsonEncode({'id': m.id, 'time': m.time, 'event': 'message', 'topic': topic, 'title': m.title, 'message': m.message})
          ];
          return http.Response.bytes(utf8.encode(lines.map((l) => '$l\n').join()), 200);
        }
        return http.Response('not found', 404);
      });
}

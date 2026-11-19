// An in-memory stand-in for an ntfy server and the recipe site, speaking the
// same HTTP the app uses.

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

  /// What the recipe site serves.
  String recipesJson = jsonEncode([
    {'slug': 'beef-chili', 'displayName': 'Beef Chili', 'image': 'https://img.example/c_fill,w_1200,h_800/chili.jpg', 'categories': ['Beef'], 'ingredients': [
      {'id': 'ground-beef', 'displayName': 'ground beef', 'amountText': '1 lb', 'text': '1 lb ground beef'},
      {'id': 'onion', 'displayName': 'onion', 'amountText': '2', 'text': '2 onion'},
      {'id': 'salt', 'displayName': 'salt', 'amountText': 'to taste', 'text': 'salt, to taste'},
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

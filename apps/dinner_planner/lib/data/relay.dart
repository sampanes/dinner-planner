// The relay the phones talk through: an ntfy server and a topic only the
// household knows. ntfy.sh works out of the box; a server of your own takes
// the same messages, keeps them as long as you tell it to, and can ask for a
// token.

import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../core/sync_core.dart';

const String defaultServer = 'https://ntfy.sh';

class Household {
  const Household({required this.server, required this.topic, this.token});

  final String server;
  final String topic;
  final String? token;

  /// A fresh household on [server], with a topic nobody can guess.
  factory Household.create({String server = defaultServer, String? token, Random? random}) {
    final r = random ?? Random.secure();
    final hex = [for (var i = 0; i < 16; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
    return Household(server: _clean(server), topic: 'dp-$hex', token: _blank(token));
  }

  static String _clean(String server) => server.trim().replaceFirst(RegExp(r'/+$'), '');
  static String? _blank(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

  Map<String, Object?> toJson() => {'s': server, 't': topic, if (token != null) 'k': token};

  static Household? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final s = raw['s'], t = raw['t'], k = raw['k'];
    if (s is! String || t is! String) return null;
    final uri = Uri.tryParse(s);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http')) || uri.host.isEmpty) return null;
    if (!RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(t)) return null;
    return Household(server: _clean(s), topic: t, token: k is String ? _blank(k) : null);
  }

  /// What one phone shows and the other pastes to join.
  String get code => base64Url.encode(utf8.encode(jsonEncode(toJson()))).replaceAll('=', '');

  static Household? fromCode(String code) {
    final text = code.trim().replaceAll(RegExp(r'\s+'), '');
    if (text.isEmpty) return null;
    try {
      final padded = text.padRight((text.length + 3) ~/ 4 * 4, '=');
      return fromJson(jsonDecode(utf8.decode(base64Url.decode(padded))));
    } on FormatException {
      return null;
    }
  }
}

class RelayMessage {
  const RelayMessage(this.id, this.time, this.payload);

  final String id;

  /// Unix seconds, by the relay's clock.
  final int time;
  final String payload;
}

class Relay {
  Relay(this.client);

  final http.Client client;

  Map<String, String> _auth(Household h) => {if (h.token != null) 'Authorization': 'Bearer ${h.token}'};

  /// Publishes one message. [quiet] marks housekeeping that should not buzz a
  /// phone that also follows the topic in the ntfy app.
  Future<bool> publish(Household h, {required String title, required String body, required String payload, bool quiet = false}) async {
    final uri = Uri.parse('${h.server}/${h.topic}').replace(queryParameters: {
      'title': title,
      'tags': 'plate_with_cutlery',
      if (quiet) 'priority': '1',
    });
    final res = await client
        .post(uri, headers: {..._auth(h), 'Content-Type': 'text/plain; charset=utf-8'}, body: utf8.encode('$body\n\n$payload'))
        .timeout(const Duration(seconds: 20));
    return res.statusCode == 200;
  }

  /// The machine lines of every message since [since] (unix seconds; 0 = all
  /// the relay still has), oldest first.
  Future<List<RelayMessage>> poll(Household h, int since) async {
    final uri = Uri.parse('${h.server}/${h.topic}/json').replace(queryParameters: {'poll': '1', 'since': since <= 0 ? 'all' : '$since'});
    final res = await client.get(uri, headers: _auth(h)).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw http.ClientException('The relay answered ${res.statusCode}', uri);
    return parsePoll(utf8.decode(res.bodyBytes));
  }
}

List<RelayMessage> parsePoll(String body) {
  final out = <RelayMessage>[];
  for (final line in const LineSplitter().convert(body)) {
    Object? msg;
    try {
      msg = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (msg is! Map || msg['event'] != 'message') continue;
    final id = msg['id'], time = msg['time'], text = msg['message'];
    if (id is! String || time is! int || text is! String) continue;
    for (final part in const LineSplitter().convert(text)) {
      if (part.startsWith(wireMark)) out.add(RelayMessage(id, time, part));
    }
  }
  out.sort((a, b) => a.time.compareTo(b.time));
  return out;
}

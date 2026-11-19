// Everything the phone remembers lives in a few small JSON values. Nothing
// here is cached in memory, so the app and its background sync (which runs
// in a separate isolate) always read what the other last wrote.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract class Store {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);

  Future<Object?> readJson(String key) async {
    final text = await read(key);
    if (text == null) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  Future<void> writeJson(String key, Object? value) => write(key, value == null ? null : jsonEncode(value));
}

class PrefsStore extends Store {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  @override
  Future<String?> read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String? value) => value == null ? _prefs.remove(key) : _prefs.setString(key, value);
}

class MemoryStore extends Store {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

// Everything the phone remembers lives in a few small JSON values. Nothing
// here is cached in memory, so the app and its background sync (which runs
// in a separate isolate) always read what the other last wrote.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract class Store {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);

  /// Puts [value] where the Android side can read it without the app
  /// running: the home-screen widget's words. True when it changed.
  Future<bool> publish(String key, String value);

  /// What was shared into the app since it last looked (ShareActivity.kt
  /// writes each on a line of its own), handed over once.
  Future<List<String>> takeShared();

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

  /// The older settings file, which plain Android code can open by name.
  static const String _sharedKey = 'dp.shared';

  @override
  Future<bool> publish(String key, String value) async {
    final plain = await SharedPreferences.getInstance();
    if (plain.getString(key) == value) return false;
    await plain.setString(key, value);
    return true;
  }

  @override
  Future<List<String>> takeShared() async {
    final plain = await SharedPreferences.getInstance();
    // Written by another part of the app since this copy was read.
    await plain.reload();
    final waiting = plain.getString(_sharedKey);
    if (waiting == null || waiting.isEmpty) return const [];
    await plain.remove(_sharedKey);
    return [for (final line in waiting.split('\n')) if (line.trim().isNotEmpty) line.trim()];
  }

  @override
  Future<String?> read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String? value) => value == null ? _prefs.remove(key) : _prefs.setString(key, value);
}

class MemoryStore extends Store {
  final Map<String, String> values = {};

  /// What was published for the Android side, by key.
  final Map<String, String> published = {};

  /// What a test says was shared into the app.
  final List<String> shared = [];

  @override
  Future<bool> publish(String key, String value) async {
    if (published[key] == value) return false;
    published[key] = value;
    return true;
  }

  @override
  Future<List<String>> takeShared() async {
    final out = List<String>.of(shared);
    shared.clear();
    return out;
  }

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

// The household's shared facts and the rules that keep every phone's copy
// the same.
//
// The state is a flat map of key -> value ("cook/2026-11-19" -> "blue"). Each
// value carries when it was written and by which device; the newest write
// wins, so two phones that have seen the same writes always agree, whatever
// order the writes arrived in.
//
// Phones talk through a relay that forgets (ntfy keeps a message about twelve
// hours), so a write can be lost. To notice, every message carries a digest
// of the sender's whole state. A phone that hears a digest different from its
// own sends what the other one may be missing, and keeps doing so every few
// hours until the digests match.
//
// Nothing in this file touches the network, the clock or the disk: callers
// pass the time in and carry the messages, which is what lets the tests run a
// lossy relay in memory.

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The line that carries the machine half of a relay message.
const String wireMark = 'dp2 ';

/// Devices whose id starts with this only listen: the kitchen screen
/// (house.js on the recipe site). They are still sent what they lack, but they
/// are not "the other phone": they do not count as a phone, and one that is
/// behind does not make this phone say it is catching up.
const String listenerPrefix = 'show-';

bool isListener(String dev) => dev.startsWith(listenerPrefix);

/// A changed entry is offered to a phone that lacks it at most this often.
const Duration resendEvery = Duration(hours: 6);

/// A phone that keeps being sent what it already has says so again, but not
/// more often than this.
const Duration reannounceEvery = Duration(minutes: 10);

/// A phone not heard from for this long is forgotten (an old handset).
const Duration forgetPeerAfter = Duration(days: 30);

/// A write dated further ahead than this is refused: newest-wins would let it
/// block every real write after it.
const Duration clockSlack = Duration(minutes: 10);

/// Day-keyed entries older than this stop counting toward the digest...
const int digestDays = 30;

/// ...and are dropped once they are this old.
const int keepDays = 60;

const int _maxChunk = 3000;

final RegExp _iso = RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$');
final RegExp _dayKey = RegExp(r'/(\d{4}-\d\d-\d\d)$');

String _two(int n) => n.toString().padLeft(2, '0');

/// UTC time as fixed-width text, so that comparing the text compares the time.
String stamp(DateTime t) {
  final u = t.toUtc();
  return '${u.year.toString().padLeft(4, '0')}-${_two(u.month)}-${_two(u.day)}'
      'T${_two(u.hour)}:${_two(u.minute)}:${_two(u.second)}'
      '.${u.millisecond.toString().padLeft(3, '0')}Z';
}

/// A calendar day as "2026-11-19".
String dayText(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}';

/// One shared fact. A null [value] means "cleared".
class Entry {
  const Entry(this.key, this.value, this.at, this.dev);

  final String key;
  final Object? value;
  final String at;
  final String dev;

  bool beats(Entry other) {
    final c = at.compareTo(other.at);
    return c > 0 || (c == 0 && dev.compareTo(other.dev) > 0);
  }

  bool sameVersion(Entry other) => at == other.at && dev == other.dev;

  List<Object?> toWire() => [key, value, at, dev];

  static Entry? fromWire(Object? raw) {
    if (raw is! List || raw.length != 4) return null;
    final k = raw[0], v = raw[1], at = raw[2], dev = raw[3];
    if (k is! String || k.isEmpty || k.length > 80) return null;
    if (!(v == null || v is String || v is num || v is bool)) return null;
    if (v is String && v.length > 400) return null;
    if (at is! String || !_iso.hasMatch(at)) return null;
    if (dev is! String || dev.isEmpty || dev.length > 32) return null;
    return Entry(k, v, at, dev);
  }
}

/// What a received message changed on this phone.
class Change {
  const Change(this.key, this.before, this.after, this.dev);

  final String key;
  final Object? before;
  final Object? after;

  /// The device that wrote the new value.
  final String dev;
}

/// One message to hand to the relay.
class Outgoing {
  const Outgoing(this.payload, this.entries, this.digest);

  /// The machine line, starting with [wireMark].
  final String payload;

  /// The entries inside, for the human-readable headline.
  final List<Entry> entries;
  final String digest;
}

class _Peer {
  _Peer(this.digest, this.heardMs, this.agreedTick);

  String digest;
  int heardMs;

  /// The value of the phone's own counter when it last agreed with this peer;
  /// anything touched since then is what the peer may be missing.
  int agreedTick;
}

class SyncCore {
  SyncCore(this.dev);

  /// This phone's id.
  final String dev;

  /// Where the last poll of the relay got to (unix seconds; 0 = never).
  int cursor = 0;

  final Map<String, Entry> _entries = {};
  final Map<String, int> _touched = {};
  final Map<String, int> _sentMs = {};
  final Map<String, _Peer> _peers = {};
  final List<String> _seenIds = [];
  String? _announced;
  int _announcedMs = 0;
  int _tick = 0;
  bool _reannounce = false;

  Object? value(String key) => _entries[key]?.value;

  Entry? entry(String key) => _entries[key];

  Iterable<Entry> get entries => _entries.values;

  /// Other phones heard from; listeners (the kitchen screen) do not count.
  int get peerCount => _peers.keys.where((id) => !isListener(id)).length;

  /// True when every phone heard from holds the same state as this one.
  bool inStep(DateTime now) {
    final mine = digest(now);
    return _peers.entries.every((p) => isListener(p.key) || p.value.digest == mine);
  }

  /// Records a write made on this phone. Returns false when it changes nothing.
  bool set(String key, Object? value, DateTime now) {
    final current = _entries[key];
    if (current != null && current.value == value) return false;
    if (current == null && value == null) return false;
    var at = stamp(now);
    // A write made here always replaces what this phone is showing, even when
    // the clock is behind the phone that wrote the current value.
    if (current != null && at.compareTo(current.at) <= 0) {
      at = stamp(DateTime.parse(current.at).add(const Duration(milliseconds: 1)));
    }
    _put(Entry(key, value, at, dev));
    return true;
  }

  void _put(Entry e) {
    _entries[e.key] = e;
    _touched[e.key] = ++_tick;
    _sentMs.remove(e.key);
  }

  /// A fingerprint of the whole state: two phones with the same digest hold
  /// the same facts.
  String digest(DateTime now) {
    final cutoff = dayText(now.toUtc().subtract(const Duration(days: digestDays)));
    final keys = _entries.keys.where((k) => !_olderThan(k, cutoff)).toList()..sort();
    final text = jsonEncode([for (final k in keys) _entries[k]!.toWire()]);
    return sha256.convert(utf8.encode(text)).toString().substring(0, 16);
  }

  static bool _olderThan(String key, String cutoffDay) {
    final m = _dayKey.firstMatch(key);
    return m != null && m.group(1)!.compareTo(cutoffDay) < 0;
  }

  /// True the first time a relay message id is offered, false after that.
  bool firstSight(String messageId) {
    if (_seenIds.contains(messageId)) return false;
    _seenIds.add(messageId);
    if (_seenIds.length > 300) _seenIds.removeRange(0, _seenIds.length - 300);
    return true;
  }

  /// Folds one relay message into the state and says what it changed.
  List<Change> receive(String payload, DateTime now) {
    if (!payload.startsWith(wireMark)) return const [];
    Object? raw;
    try {
      raw = jsonDecode(payload.substring(wireMark.length));
    } on FormatException {
      return const [];
    }
    if (raw is! Map) return const [];
    final from = raw['d'], theirs = raw['g'], list = raw['s'];
    if (from is! String || from.isEmpty || from.length > 32 || from == dev) return const [];
    if (theirs is! String || theirs.length > 64) return const [];

    final latest = stamp(now.add(clockSlack));
    final changes = <Change>[];
    var carried = 0;
    if (list is List) {
      for (final item in list) {
        final e = Entry.fromWire(item);
        if (e == null || e.at.compareTo(latest) > 0) continue;
        carried++;
        final current = _entries[e.key];
        if (current != null && !e.beats(current)) continue;
        _put(e);
        // The sender plainly has this version already.
        _sentMs[e.key] = now.millisecondsSinceEpoch;
        if (current?.value != e.value) changes.add(Change(e.key, current?.value, e.value, e.dev));
      }
    }

    final nowMs = now.millisecondsSinceEpoch;
    final peer = _peers.putIfAbsent(from, () => _Peer(theirs, nowMs, 0));
    peer.digest = theirs;
    peer.heardMs = nowMs;
    // The sender is offering what this phone already has: it never heard this
    // phone say so, so say it again.
    if (carried > 0 && changes.isEmpty && theirs == digest(now) && nowMs - _announcedMs > reannounceEvery.inMilliseconds) {
      _reannounce = true;
    }
    return changes;
  }

  /// The messages this phone should publish now. Call [markSent] with each
  /// one the relay accepted.
  List<Outgoing> outbox(DateTime now) {
    _tidy(now);
    final nowMs = now.millisecondsSinceEpoch;
    final mine = digest(now);
    final behind = <String>[];
    _peers.forEach((id, p) {
      if (p.digest == mine) {
        p.agreedTick = _tick;
      } else {
        behind.add(id);
      }
    });

    final send = <String, Entry>{};
    for (final e in _entries.values) {
      if (e.dev == dev && !_sentMs.containsKey(e.key)) send[e.key] = e;
    }
    for (final id in behind) {
      final agreed = _peers[id]!.agreedTick;
      for (final e in _entries.values) {
        if ((_touched[e.key] ?? 0) <= agreed) continue;
        if (behind.length == 1 && e.dev == id) continue;
        final last = _sentMs[e.key];
        if (last == null || nowMs - last >= resendEvery.inMilliseconds) send[e.key] = e;
      }
    }

    if (send.isEmpty && mine == _announced && !_reannounce) return const [];

    final out = <Outgoing>[];
    var batch = <Entry>[];
    var size = 0;
    void flush() {
      final body = {'d': dev, 'g': mine, 's': [for (final e in batch) e.toWire()]};
      out.add(Outgoing('$wireMark${jsonEncode(body)}', batch, mine));
      batch = <Entry>[];
      size = 0;
    }

    for (final e in send.values) {
      // Bytes, not characters: ntfy's limit is in bytes, and a note may hold
      // letters that take several.
      final len = utf8.encode(jsonEncode(e.toWire())).length + 1;
      if (batch.isNotEmpty && size + len > _maxChunk) flush();
      batch.add(e);
      size += len;
    }
    if (batch.isNotEmpty || out.isEmpty) flush();
    return out;
  }

  /// Records that the relay accepted [message].
  void markSent(Outgoing message, DateTime now) {
    final nowMs = now.millisecondsSinceEpoch;
    for (final e in message.entries) {
      final current = _entries[e.key];
      if (current != null && current.sameVersion(e)) _sentMs[e.key] = nowMs;
    }
    _announced = message.digest;
    _announcedMs = nowMs;
    _reannounce = false;
  }

  void _tidy(DateTime now) {
    final nowMs = now.millisecondsSinceEpoch;
    _peers.removeWhere((_, p) => nowMs - p.heardMs > forgetPeerAfter.inMilliseconds);
    final cutoff = dayText(now.toUtc().subtract(const Duration(days: keepDays)));
    final old = _entries.keys.where((k) => _olderThan(k, cutoff)).toList();
    for (final k in old) {
      _entries.remove(k);
      _touched.remove(k);
      _sentMs.remove(k);
    }
  }

  Map<String, Object?> toJson() => {
        'dev': dev,
        'tick': _tick,
        'cursor': cursor,
        'entries': [
          for (final e in _entries.values) [...e.toWire(), _touched[e.key] ?? 0, _sentMs[e.key]]
        ],
        'peers': {
          for (final p in _peers.entries) p.key: [p.value.digest, p.value.heardMs, p.value.agreedTick]
        },
        'announced': _announced,
        'announcedMs': _announcedMs,
        'seen': _seenIds,
      };

  static SyncCore fromJson(Map<String, Object?> json) {
    final core = SyncCore(json['dev'] as String);
    core._tick = (json['tick'] as num?)?.toInt() ?? 0;
    core.cursor = (json['cursor'] as num?)?.toInt() ?? 0;
    for (final raw in (json['entries'] as List? ?? const [])) {
      if (raw is! List || raw.length != 6) continue;
      final e = Entry.fromWire(raw.sublist(0, 4));
      if (e == null) continue;
      core._entries[e.key] = e;
      core._touched[e.key] = (raw[4] as num?)?.toInt() ?? 0;
      final sent = raw[5];
      if (sent is num) core._sentMs[e.key] = sent.toInt();
    }
    final peers = json['peers'];
    if (peers is Map) {
      peers.forEach((id, raw) {
        if (id is String && raw is List && raw.length == 3) {
          core._peers[id] = _Peer(raw[0] as String, (raw[1] as num).toInt(), (raw[2] as num).toInt());
        }
      });
    }
    core._announced = json['announced'] as String?;
    core._announcedMs = (json['announcedMs'] as num?)?.toInt() ?? 0;
    core._seenIds.addAll([for (final id in (json['seen'] as List? ?? const [])) if (id is String) id]);
    return core;
  }
}

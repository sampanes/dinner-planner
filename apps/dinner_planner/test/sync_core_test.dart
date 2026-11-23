import 'dart:convert';

import 'package:dinner_planner/core/sync_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A relay that keeps messages for a while and then forgets them, like ntfy.
class FakeRelay {
  FakeRelay({this.keep = const Duration(hours: 12)});

  final Duration keep;
  final List<({int id, DateTime at, String payload})> _messages = [];
  int _next = 1;
  int published = 0;

  void publish(String payload, DateTime now) {
    _messages.add((id: _next++, at: now, payload: payload));
    published++;
  }

  List<({int id, DateTime at, String payload})> since(int cursor, DateTime now) =>
      [for (final m in _messages) if (m.id > cursor && now.difference(m.at) < keep) m];
}

class Phone {
  Phone(String dev, this.relay) : core = SyncCore(dev);

  SyncCore core;
  final FakeRelay relay;
  final List<Change> heard = [];

  /// One sync cycle: read what is new, then publish what is owed.
  void sync(DateTime now) {
    for (final m in relay.since(core.cursor, now)) {
      core.cursor = m.id;
      if (!core.firstSight('${m.id}')) continue;
      heard.addAll(core.receive(m.payload, now));
    }
    for (final out in core.outbox(now)) {
      relay.publish(out.payload, now);
      core.markSent(out, now);
    }
  }
}

void main() {
  final start = DateTime.utc(2026, 11, 19, 18);

  test('stamp is fixed width so text order is time order', () {
    expect(stamp(DateTime.utc(2026, 1, 2, 3, 4, 5, 6, 789)), '2026-01-02T03:04:05.006Z');
    expect(stamp(DateTime.utc(2026, 1, 2, 3, 4, 5)).compareTo(stamp(DateTime.utc(2026, 1, 2, 3, 4, 5, 1))), lessThan(0));
  });

  test('a write reaches the other phone and both then go quiet', () {
    final relay = FakeRelay();
    final a = Phone('aaaa', relay), b = Phone('bbbb', relay);
    a.core.set('cook/2026-11-19', 'blue', start);
    a.sync(start);
    b.sync(start.add(const Duration(minutes: 1)));
    expect(b.core.value('cook/2026-11-19'), 'blue');
    expect(b.heard.single.key, 'cook/2026-11-19');
    a.sync(start.add(const Duration(minutes: 2)));
    expect(a.core.inStep(start.add(const Duration(minutes: 2))), isTrue);

    final before = relay.published;
    for (var i = 3; i < 600; i += 7) {
      a.sync(start.add(Duration(minutes: i)));
      b.sync(start.add(Duration(minutes: i + 1)));
    }
    expect(relay.published, before, reason: 'two phones in step have nothing to say');
  });

  test('a kitchen screen that only listens is sent the plan but is not the other phone', () {
    final relay = FakeRelay();
    final a = Phone('aaaa', relay);
    a.core.set('meal/2026-11-19', 'beef-ragu-pasta-bar', start);
    a.sync(start);
    // The screen checks in holding nothing.
    relay.publish('$wireMark{"d":"show-0123abcd","g":"0000000000000000","s":[]}', start.add(const Duration(hours: 7)));
    final now = start.add(const Duration(hours: 7, minutes: 1));
    final before = relay.published;
    a.sync(now);
    expect(relay.published, greaterThan(before), reason: 'the screen is behind, so the phone sends the plan');
    expect(a.core.peerCount, 0);
    expect(a.core.inStep(now), isTrue, reason: 'a screen that is behind is not a phone to catch up with');
  });

  test('the newest write wins whatever order the writes arrive in', () {
    final relay = FakeRelay();
    final a = Phone('aaaa', relay), b = Phone('bbbb', relay);
    a.core.set('meal/2026-11-20', 'chili', start);
    b.core.set('meal/2026-11-20', 'tacos', start.add(const Duration(seconds: 5)));
    b.sync(start.add(const Duration(seconds: 6)));
    a.sync(start.add(const Duration(seconds: 7)));
    b.sync(start.add(const Duration(seconds: 8)));
    a.sync(start.add(const Duration(seconds: 9)));
    expect(a.core.value('meal/2026-11-20'), 'tacos');
    expect(b.core.value('meal/2026-11-20'), 'tacos');
    expect(a.core.digest(start), b.core.digest(start));
  });

  test('writes on both phones at once both survive', () {
    final relay = FakeRelay();
    final a = Phone('aaaa', relay), b = Phone('bbbb', relay);
    a.core.set('cook/2026-11-19', 'blue', start);
    b.core.set('meal/2026-11-19', 'chili', start);
    a.sync(start);
    b.sync(start);
    a.sync(start.add(const Duration(seconds: 1)));
    b.sync(start.add(const Duration(seconds: 2)));
    expect(a.core.value('meal/2026-11-19'), 'chili');
    expect(b.core.value('cook/2026-11-19'), 'blue');
    final before = relay.published;
    a.sync(start.add(const Duration(seconds: 3)));
    b.sync(start.add(const Duration(seconds: 4)));
    expect(relay.published, before);
  });

  test('a write the relay forgot is offered again until it lands', () {
    final relay = FakeRelay();
    final a = Phone('aaaa', relay), b = Phone('bbbb', relay);
    // The phones know each other.
    a.core.set('name/blue', 'Sam', start);
    a.sync(start);
    b.sync(start);
    a.sync(start);

    // B is off for two days; A writes and its message expires unseen.
    final written = start.add(const Duration(hours: 1));
    a.core.set('cook/2026-11-21', 'blue', written);
    a.sync(written);
    var now = written;
    for (var h = 1; h <= 48; h++) {
      now = written.add(Duration(hours: h));
      a.sync(now);
    }
    b.sync(now.add(const Duration(minutes: 30)));
    expect(b.core.value('cook/2026-11-21'), 'blue');
    a.sync(now.add(const Duration(minutes: 40)));
    expect(a.core.inStep(now.add(const Duration(minutes: 40))), isTrue);

    // A offered it every six hours, not every hour.
    expect(relay.published, lessThan(16));
  });

  test('a phone that joins late is sent everything', () {
    final relay = FakeRelay();
    final a = Phone('aaaa', relay);
    for (var d = 10; d < 24; d++) {
      a.core.set('meal/2026-11-$d', 'recipe-$d', start);
      a.core.set('cook/2026-11-$d', d.isEven ? 'blue' : 'pink', start);
    }
    a.sync(start);
    final later = start.add(const Duration(days: 3));
    final c = Phone('cccc', relay);
    c.sync(later);
    a.sync(later.add(const Duration(minutes: 1)));
    c.sync(later.add(const Duration(minutes: 2)));
    expect(c.core.entries.length, 28);
    expect(c.core.digest(later), a.core.digest(later));
  });

  test('many entries are split across messages under the relay size limit', () {
    final core = SyncCore('aaaa');
    for (var i = 0; i < 200; i++) {
      core.set('note/$i', 'x' * 100, start);
    }
    final out = core.outbox(start);
    expect(out.length, greaterThan(1));
    for (final m in out) {
      expect(m.payload.length, lessThan(4000));
    }
    expect(out.expand((m) => m.entries).length, 200);
  });

  test('the size limit counts bytes, so notes with accents still fit', () {
    final core = SyncCore('aaaa');
    for (var i = 0; i < 40; i++) {
      core.set('note/$i', String.fromCharCode(0xe9) * 400, start);
    }
    final out = core.outbox(start);
    for (final m in out) {
      expect(utf8.encode(m.payload).length, lessThan(4000));
    }
    expect(out.expand((m) => m.entries).length, 40);
  });

  test('a write dated in the future is refused', () {
    final a = SyncCore('aaaa'), b = SyncCore('bbbb');
    a.set('cook/2026-11-19', 'pink', start.add(const Duration(days: 2)));
    final out = a.outbox(start);
    expect(b.receive(out.single.payload, start), isEmpty);
    expect(b.value('cook/2026-11-19'), isNull);
  });

  test('a phone that cannot be brought in step is not flooded', () {
    final relay = FakeRelay();
    final a = Phone('aaaa', relay), b = Phone('bbbb', relay);
    // A's clock is two days fast, so B refuses what A writes.
    a.core.set('cook/2026-11-19', 'pink', start.add(const Duration(days: 2)));
    for (var m = 0; m < 24 * 60; m += 5) {
      a.sync(start.add(Duration(minutes: m)));
      b.sync(start.add(Duration(minutes: m + 1)));
    }
    expect(relay.published, lessThan(12));
  });

  test('a write on this phone replaces a value written by a faster clock', () {
    final a = SyncCore('aaaa'), b = SyncCore('bbbb');
    a.set('meal/2026-11-19', 'chili', start.add(const Duration(minutes: 5)));
    b.receive(a.outbox(start).single.payload, start);
    expect(b.set('meal/2026-11-19', 'tacos', start), isTrue);
    a.receive(b.outbox(start).single.payload, start);
    expect(a.value('meal/2026-11-19'), 'tacos');
  });

  test('the same relay message is only taken once', () {
    final core = SyncCore('aaaa');
    expect(core.firstSight('m1'), isTrue);
    expect(core.firstSight('m1'), isFalse);
  });

  test('state survives being saved and loaded', () {
    final relay = FakeRelay();
    final a = Phone('aaaa', relay), b = Phone('bbbb', relay);
    a.core.set('cook/2026-11-19', 'blue', start);
    a.sync(start);
    b.sync(start);
    a.sync(start);
    a.core = SyncCore.fromJson(a.core.toJson());
    expect(a.core.value('cook/2026-11-19'), 'blue');
    expect(a.core.digest(start), b.core.digest(start));
    final before = relay.published;
    a.sync(start.add(const Duration(minutes: 5)));
    expect(relay.published, before, reason: 'a reload must not make the phone repeat itself');
  });

  test('old days drop out of the digest and then out of the state', () {
    final core = SyncCore('aaaa');
    core.set('meal/2026-11-19', 'chili', start);
    core.set('name/blue', 'Sam', start);
    final fresh = core.digest(start);
    expect(core.digest(start.add(const Duration(days: 40))), isNot(fresh));
    core.outbox(start.add(const Duration(days: 70)));
    expect(core.value('meal/2026-11-19'), isNull);
    expect(core.value('name/blue'), 'Sam');
  });
}

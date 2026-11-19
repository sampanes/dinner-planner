// Two phones through a real ntfy server, on a throwaway topic. Skipped
// unless LIVE_RELAY names the server:
//
//   LIVE_RELAY=https://ntfy.sh flutter test test/live_relay_test.dart
//   LIVE_RELAY=http://my-machine:8080 LIVE_RELAY_TOKEN=tk_... flutter test test/live_relay_test.dart

import 'dart:io';

import 'package:dinner_planner/core/plan.dart';
import 'package:dinner_planner/data/relay.dart';
import 'package:dinner_planner/data/session.dart';
import 'package:dinner_planner/data/store.dart';
import 'package:dinner_planner/notify/notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  final server = Platform.environment['LIVE_RELAY'];

  test('a real relay carries a change from one phone to the other', () async {
    // The test framework blocks real network calls unless told otherwise.
    HttpOverrides.global = null;
    final client = http.Client();
    addTearDown(client.close);
    final house = Household.create(server: server!, token: Platform.environment['LIVE_RELAY_TOKEN']);

    Future<Session> phone(String me) async {
      final s = Session(store: MemoryStore(), client: client, notifier: SilentNotifier());
      await s.load();
      s
        ..me = me
        ..household = house;
      return s;
    }

    final his = await phone('blue'), hers = await phone('pink');
    final now = DateTime.now();
    final tomorrow = '${now.year}-${'${now.month}'.padLeft(2, '0')}-${'${now.day}'.padLeft(2, '0')}';
    his.core.set(nameKey('blue'), 'Sam (relay check)', now);
    his.core.set(cookKey(tomorrow), 'blue', now);
    expect((await his.sync(DateTime.now())).error, isNull);

    // A relay may take a moment to show a message it has just accepted.
    Future<void> until(Session s, bool Function() done) async {
      for (var i = 0; i < 20 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect((await s.sync(DateTime.now())).error, isNull);
      }
    }

    await until(hers, () => hers.plan.cook(tomorrow) == 'blue');
    expect(hers.plan.cook(tomorrow), 'blue');
    expect(hers.plan.name('blue'), 'Sam (relay check)');

    await until(his, () => his.core.peerCount == 1 && his.core.inStep(DateTime.now()));
    expect(his.core.peerCount, 1);
    expect(his.core.inStep(DateTime.now()), isTrue, reason: 'his phone heard hers say it is in step');
  }, skip: server == null, timeout: const Timeout(Duration(minutes: 1)));
}

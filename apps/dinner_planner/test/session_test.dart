import 'package:dinner_planner/core/nudges.dart';
import 'package:dinner_planner/core/plan.dart';
import 'package:dinner_planner/core/sync_core.dart';
import 'package:dinner_planner/data/recipes.dart';
import 'package:dinner_planner/data/relay.dart';
import 'package:dinner_planner/data/session.dart';
import 'package:dinner_planner/data/store.dart';
import 'package:dinner_planner/notify/notifier.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ntfy.dart';

Future<Session> phone(FakeNtfy ntfy, {required String me, Household? household}) async {
  final s = Session(store: MemoryStore(), client: ntfy.client(), notifier: SilentNotifier());
  await s.load();
  s.me = me;
  s.household = household;
  return s;
}

void main() {
  final house = Household(server: 'https://relay.example', topic: 'dp-0123456789abcdef');

  group('household code', () {
    test('round trips, with and without a token', () {
      final plain = Household.fromCode(house.code)!;
      expect((plain.server, plain.topic, plain.token), ('https://relay.example', 'dp-0123456789abcdef', null));
      final own = Household.create(server: 'http://100.64.0.7:8080/', token: ' tk_abc ');
      final back = Household.fromCode(own.code)!;
      expect(back.server, 'http://100.64.0.7:8080');
      expect(back.token, 'tk_abc');
      expect(back.topic, matches(RegExp(r'^dp-[0-9a-f]{32}$')));
    });

    test('junk is refused', () {
      expect(Household.fromCode(''), isNull);
      expect(Household.fromCode('hello there'), isNull);
      expect(Household.fromJson({'s': 'ftp://x', 't': 'dp-0123456789abcdef'}), isNull);
      expect(Household.fromJson({'s': 'https://relay.example', 't': 'a/b'}), isNull);
    });

    test('two new households never share a topic', () {
      expect(Household.create().topic, isNot(Household.create().topic));
    });
  });

  test('poll output keeps only the machine lines, oldest first', () {
    final lines = [
      '{"id":"b","time":20,"event":"message","message":"Sam cooks today\\n\\ndp2 {\\"d\\":\\"x\\"}"}',
      '{"id":"o","time":5,"event":"open"}',
      'not json',
      '{"id":"a","time":10,"event":"message","message":"hello from a person"}',
      '{"id":"c","time":15,"event":"message","message":"dp2 {\\"d\\":\\"y\\"}"}',
    ].join('\n');
    final got = parsePoll(lines);
    expect([for (final m in got) m.id], ['c', 'b']);
    expect(got.first.payload, 'dp2 {"d":"y"}');
  });

  test('a change on one phone shows on the other, with a readable headline', () async {
    final ntfy = FakeNtfy();
    final his = await phone(ntfy, me: 'blue', household: house);
    final hers = await phone(ntfy, me: 'pink', household: house);
    await his.refreshRecipes(ntfy.now);
    await hers.refreshRecipes(ntfy.now);
    final day = dayText(ntfy.now.toLocal());

    his.core.set(nameKey('blue'), 'Sam', ntfy.now);
    await his.sync(ntfy.now);
    hers.core.set(mealKey(day), 'beef-chili', ntfy.now);
    hers.core.set(cookKey(day), 'blue', ntfy.now);
    final sent = await hers.sync(ntfy.now);
    expect(sent.error, isNull);
    expect(ntfy.messages.last.title, 'Today: Beef Chili');
    expect(ntfy.messages.last.message, contains('Sam cooks today'));

    final report = await his.sync(ntfy.now);
    expect(his.plan.meal(day), 'beef-chili');
    expect(his.plan.cook(day), 'blue');
    await his.announce(report.changes, ntfy.now.toLocal());
    final shown = (his.notifier as SilentNotifier).shown;
    expect(shown.single.title, "You're cooking today");
    expect(shown.single.body, 'Beef Chili');
  });

  test('a note on a recipe reaches the other phone without a reminder', () async {
    final ntfy = FakeNtfy();
    final his = await phone(ntfy, me: 'blue', household: house);
    final hers = await phone(ntfy, me: 'pink', household: house);
    await his.refreshRecipes(ntfy.now);
    await hers.refreshRecipes(ntfy.now);

    hers.core.set(noteKey('beef-chili'), 'Add parmesan as a step', ntfy.now);
    await hers.sync(ntfy.now);
    expect(ntfy.messages.last.title, 'Note on Beef Chili');

    final report = await his.sync(ntfy.now);
    expect(his.plan.note('beef-chili'), 'Add parmesan as a step');
    expect(his.plan.note('shrimp-tacos'), isNull);
    await his.announce(report.changes, ntfy.now.toLocal());
    expect((his.notifier as SilentNotifier).shown, isEmpty, reason: 'a note is not worth a buzz');
  });

  test('a step is named by its own words, the same way on the phones, the kitchen page and the computer', () {
    // house.js and scripts/house_notes.py are tested against these same four.
    expect(stepId(''), '811c9dc5');
    expect(stepId('a'), 'e40c292c');
    expect(stepId('Brown the beef in a large pot, 5-7 minutes.'), '8b807cd6');
    expect(stepId('Sauté the onion.'), '9763783c');
    expect(stepAnchor('  Brown the beef\n in a large pot  '), 'Brown the beef in a large pot');
    expect(stepAnchor('x' * 200).length, 60);
    expect(stepNoteKey('italian-chicken-sausage-gluten-free-fusilli-rosa', 'a').length, lessThanOrEqualTo(80), reason: 'the longest recipe name still fits in a key');
  });

  test('a note on one step reaches the other phone and stays on that step', () async {
    final ntfy = FakeNtfy();
    final his = await phone(ntfy, me: 'blue', household: house);
    final hers = await phone(ntfy, me: 'pink', household: house);
    await his.refreshRecipes(ntfy.now);
    await hers.refreshRecipes(ntfy.now);
    const step = 'Brown the beef in a large pot, 5-7 minutes.';
    expect(his.recipe('beef-chili')!.steps, contains(step));

    hers.core.set(noteKey('beef-chili'), 'Double it', ntfy.now);
    hers.core.set(stepNoteKey('beef-chili', step), '${stepAnchor(step)}\nGarlic salt goes in here', ntfy.now);
    hers.core.set('note/beef-chili/deadbeef', 'Words of a step that was rewritten\nStill true', ntfy.now);
    hers.core.set('note/beef-chili-bar/8b807cd6', 'Another recipe\nNot this one', ntfy.now);
    await hers.sync(ntfy.now);
    await his.sync(ntfy.now);

    final notes = his.plan.notes('beef-chili');
    expect([for (final n in notes) n.text], ['Double it', 'Garlic salt goes in here', 'Still true']);
    expect(notes[0].step, isNull);
    expect(notes[1].step, stepId(step));
    expect(notes[1].anchor, step);
    expect(notes[1].key, 'note/beef-chili/8b807cd6');
    expect(notes[2].anchor, 'Words of a step that was rewritten');
    expect(his.plan.note('beef-chili'), 'Double it', reason: 'the note on the whole recipe is still the plain one');

    his.core.set('note/beef-chili/8b807cd6', null, ntfy.now.add(const Duration(seconds: 1)));
    expect(his.plan.notes('beef-chili').length, 2);
  });

  test('the computer that fixes the recipes clears a note, and both phones drop it', () async {
    final ntfy = FakeNtfy();
    final his = await phone(ntfy, me: 'blue', household: house);
    final hers = await phone(ntfy, me: 'pink', household: house);
    const step = 'Brown the beef in a large pot, 5-7 minutes.';
    hers.core.set(stepNoteKey('beef-chili', step), '${stepAnchor(step)}\nGarlic salt goes in here', ntfy.now);
    await hers.sync(ntfy.now);
    await his.sync(ntfy.now);
    expect(his.plan.notes('beef-chili').single.text, 'Garlic salt goes in here');

    // What scripts/house_notes.py --done sends: the note's key with nothing in
    // it, dated a millisecond after the note, from a device that only listens.
    final wrote = hers.core.entry('note/beef-chili/8b807cd6')!.at;
    final after = stamp(DateTime.parse(wrote).add(const Duration(milliseconds: 1)));
    final line = 'dp2 {"d":"show-pc-1a2b3c4d","g":"0000000000000000","s":[["note/beef-chili/8b807cd6",null,"$after","show-pc-1a2b3c4d"]]}';
    await ntfy.client().post(Uri.parse('${house.server}/${house.topic}?title=Kitchen+computer+checked+in&priority=1'), body: 'The kitchen computer is reading the notes.\n\n$line');

    final report = await his.sync(ntfy.now);
    expect(report.changes.single.after, isNull);
    expect(his.plan.notes('beef-chili'), isEmpty);
    expect(his.core.peerCount, 1, reason: 'the computer does not count as a phone');
    await hers.sync(ntfy.now);
    expect(hers.plan.notes('beef-chili'), isEmpty, reason: 'each phone reads it from the relay itself');
  });

  test('a phone that missed the computer clearing a note hears it from the other phone', () async {
    final ntfy = FakeNtfy();
    final his = await phone(ntfy, me: 'blue', household: house);
    final hers = await phone(ntfy, me: 'pink', household: house);
    hers.core.set(noteKey('beef-chili'), 'Double it', ntfy.now);
    await hers.sync(ntfy.now);
    await his.sync(ntfy.now);
    await hers.sync(ntfy.now);

    // Only his phone was around while the relay still had the message.
    final after = stamp(ntfy.now.add(const Duration(seconds: 1)));
    his.core.receive('dp2 {"d":"show-pc-1a2b3c4d","g":"0000000000000000","s":[["note/beef-chili",null,"$after","show-pc-1a2b3c4d"]]}', ntfy.now);
    expect(his.plan.note('beef-chili'), isNull);

    // His phone passes it on, though not at once: what it was handed counts as
    // just sent, and is offered again after resendEvery.
    ntfy.now = ntfy.now.add(resendEvery + const Duration(minutes: 1));
    await his.sync(ntfy.now);
    await hers.sync(ntfy.now);
    await his.sync(ntfy.now);
    await hers.sync(ntfy.now);
    expect(hers.plan.note('beef-chili'), isNull);
  });

  test('housekeeping messages are sent quietly', () async {
    final ntfy = FakeNtfy();
    final his = await phone(ntfy, me: 'blue', household: house);
    final hers = await phone(ntfy, me: 'pink', household: house);
    his.core.set(cookKey('2026-11-20'), 'blue', ntfy.now);
    await his.sync(ntfy.now);
    expect(ntfy.messages.single.priority, isNull);
    await hers.sync(ntfy.now);
    expect(ntfy.messages.last.priority, '1', reason: 'her phone only says it is in step');
  });

  test('offline changes are kept and go out when the relay is back', () async {
    final ntfy = FakeNtfy()..down = true;
    final his = await phone(ntfy, me: 'blue', household: house);
    final hers = await phone(ntfy, me: 'pink', household: house);
    his.core.set(cookKey('2026-11-21'), 'blue', ntfy.now);
    expect((await his.sync(ntfy.now)).error, isNotNull);
    ntfy.down = false;
    expect((await his.sync(ntfy.now)).error, isNull);
    await hers.sync(ntfy.now);
    expect(hers.plan.cook('2026-11-21'), 'blue');
  });

  test('a server that wants a token gets it', () async {
    final ntfy = FakeNtfy()..requireToken = 'tk_abc';
    final locked = Household(server: 'https://relay.example', topic: 'dp-0123456789abcdef', token: 'tk_abc');
    final his = await phone(ntfy, me: 'blue', household: locked);
    his.core.set(cookKey('2026-11-21'), 'blue', ntfy.now);
    expect((await his.sync(ntfy.now)).error, isNull);
    final nosy = await phone(ntfy, me: 'pink', household: house);
    expect((await nosy.sync(ntfy.now)).error, isNotNull);
  });

  test('what a phone knows survives a restart', () async {
    final ntfy = FakeNtfy();
    final store = MemoryStore();
    final first = Session(store: store, client: ntfy.client(), notifier: SilentNotifier());
    await first.load();
    first
      ..me = 'blue'
      ..household = house
      ..times = const NudgeTimes(start: 16 * 60);
    first.core.set(cookKey('2026-11-21'), 'blue', ntfy.now);
    await first.saveProfile();
    await first.saveHousehold();
    await first.saveSettings();
    await first.saveCore();
    await first.refreshRecipes(ntfy.now);

    final again = Session(store: store, client: ntfy.client(), notifier: SilentNotifier());
    await again.load();
    expect(again.core.dev, first.core.dev);
    expect(again.me, 'blue');
    expect(again.household!.topic, house.topic);
    expect(again.times.start, 16 * 60);
    expect(again.plan.cook('2026-11-21'), 'blue');
    expect(again.recipeName('beef-chili'), 'Beef Chili');
  });

  test('the background task stands down while the app is open', () async {
    final store = MemoryStore();
    final s = Session(store: store, client: FakeNtfy().client(), notifier: SilentNotifier());
    final now = DateTime(2026, 11, 19, 18);
    expect(await Session.appIsOpen(store, now), isFalse);
    await s.beat(now);
    expect(await Session.appIsOpen(store, now.add(const Duration(seconds: 30))), isTrue);
    expect(await Session.appIsOpen(store, now.add(const Duration(minutes: 5))), isFalse, reason: 'a killed app must not block sync for ever');
    await s.rest();
    expect(await Session.appIsOpen(store, now), isFalse);
  });

  group('recipes', () {
    test('the site data is trimmed to what the phone shows', () {
      final list = parseRecipes(FakeNtfy().recipesJson);
      expect([for (final r in list) r.name], ['Baked Penne', 'Beef Chili', 'Shrimp Tacos']);
      final chili = list[1];
      expect(chili.thumb, 'https://img.example/c_fill,w_300,h_200/chili.jpg');
      expect(chili.ingredients.map((i) => i.text), ['1 lb ground beef', '2 onion', 'salt, to taste']);
      expect(Recipe.fromJson(chili.toJson())!.ingredients.first.id, 'ground-beef', reason: 'the copy kept on the phone reads back the same');
      expect(Recipe.fromJson(chili.toJson())!.name, 'Beef Chili');
    });

    test('the kitchen link opens the recipe overview', () {
      expect(kitchenPage('https://site.example/dinner/', 'beef-chili').toString(), 'https://site.example/dinner/kitchen.html#/r/beef-chili');
    });
  });

  group('reminders', () {
    SyncCore core() => SyncCore('aaaa');
    String name(String slug) => slug == 'beef-chili' ? 'Beef Chili' : slug;

    test('three per cooking night: evening before, morning, start', () {
      final c = core();
      final now = DateTime(2026, 11, 19, 12);
      c.set(cookKey('2026-11-21'), 'blue', now);
      c.set(mealKey('2026-11-21'), 'beef-chili', now);
      c.set(cookKey('2026-11-22'), 'pink', now);
      final got = planNudges(me: 'blue', now: now, times: const NudgeTimes(), plan: Plan(c), recipeName: name);
      expect([for (final n in got) n.when], [DateTime(2026, 11, 20, 20), DateTime(2026, 11, 21, 7, 30), DateTime(2026, 11, 21, 17)]);
      expect(got[0].title, 'You cook tomorrow: Beef Chili');
      expect(got[2].body, 'Beef Chili. Tap to open it.');
      expect({for (final n in got) n.id}.length, 3);
    });

    test('only the ones still ahead', () {
      final c = core();
      final now = DateTime(2026, 11, 19, 12);
      c.set(cookKey('2026-11-19'), 'blue', now);
      final got = planNudges(me: 'blue', now: now, times: const NudgeTimes(), plan: Plan(c), recipeName: name);
      expect(got.single.when, DateTime(2026, 11, 19, 17));
      expect(got.single.body, 'Nothing is picked. Choose something quick.');
    });

    test('none for the other person', () {
      final c = core();
      final now = DateTime(2026, 11, 19, 12);
      c.set(cookKey('2026-11-21'), 'blue', now);
      expect(planNudges(me: 'pink', now: now, times: const NudgeTimes(), plan: Plan(c), recipeName: name), isEmpty);
    });

    test('ids stay the same from one planning to the next', () {
      final c = core();
      c.set(cookKey('2026-11-21'), 'blue', DateTime(2026, 11, 19, 12));
      List<int> ids(DateTime now) => [for (final n in planNudges(me: 'blue', now: now, times: const NudgeTimes(), plan: Plan(c), recipeName: name)) n.id];
      expect(ids(DateTime(2026, 11, 19, 12)), ids(DateTime(2026, 11, 19, 13)));
    });
  });

  group('notices', () {
    final now = DateTime(2026, 11, 19, 12);
    String name(String slug) => 'Beef Chili';

    test('being handed a night, losing one, and a changed dinner', () {
      final c = SyncCore('aaaa');
      c.set(mealKey('2026-11-20'), 'beef-chili', now);
      c.set(cookKey('2026-11-20'), 'blue', now);
      c.set(nameKey('pink'), 'Alex', now);
      List<Notice> tell(List<Change> changes) => noticesFor(changes, me: 'blue', myDev: 'aaaa', now: now, plan: Plan(c), recipeName: name);

      expect(tell([const Change('cook/2026-11-20', null, 'blue', 'bbbb')]).single.title, "You're cooking tomorrow");
      expect(tell([const Change('cook/2026-11-20', 'blue', 'pink', 'bbbb')]).single.title, 'Alex is cooking tomorrow');
      expect(tell([const Change('meal/2026-11-20', 'x', 'beef-chili', 'bbbb')]).single.title, 'Dinner tomorrow is now Beef Chili');
    });

    test('nothing for my own changes, past days, or nights that are not mine', () {
      final c = SyncCore('aaaa');
      c.set(cookKey('2026-11-20'), 'pink', now);
      List<Notice> tell(List<Change> changes) => noticesFor(changes, me: 'blue', myDev: 'aaaa', now: now, plan: Plan(c), recipeName: name);
      expect(tell([const Change('cook/2026-11-20', null, 'blue', 'aaaa')]), isEmpty);
      expect(tell([const Change('cook/2026-11-01', null, 'blue', 'bbbb')]), isEmpty);
      expect(tell([const Change('meal/2026-11-20', null, 'beef-chili', 'bbbb')]), isEmpty);
      expect(tell([const Change('name/pink', null, 'Alex', 'bbbb')]), isEmpty);
    });
  });
}

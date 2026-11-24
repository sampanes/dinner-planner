// The parts that make the plan run itself: reminders that do the next thing
// when tapped, nights that can be called off, a week that drafts itself,
// staples, a note from the stove, and "how was it?".

import 'package:dinner_planner/app_model.dart';
import 'package:dinner_planner/core/nudges.dart';
import 'package:dinner_planner/core/plan.dart';
import 'package:dinner_planner/core/shopping.dart';
import 'package:dinner_planner/core/sync_core.dart';
import 'package:dinner_planner/data/autoplan.dart';
import 'package:dinner_planner/data/recipes.dart';
import 'package:dinner_planner/data/session.dart';
import 'package:dinner_planner/data/store.dart';
import 'package:dinner_planner/main.dart';
import 'package:dinner_planner/notify/notifier.dart';
import 'package:dinner_planner/ui/shop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ntfy.dart';

/// A Thursday afternoon, before anything is due.
final DateTime thursday = DateTime(2026, 11, 19, 16, 30);
const String today = '2026-11-19', friday = '2026-11-20', saturday = '2026-11-21', sunday = '2026-11-22';

const String siteTopic = 'dinner-site-0123456789abcdef';

class Clock {
  Clock(this.now);
  DateTime now;
}

Future<AppModel> phone(FakeNtfy ntfy, {Clock? clock, List<Uri>? opened, Store? store}) async {
  final c = clock ?? Clock(thursday);
  final model = AppModel(
    Session(store: store ?? MemoryStore(), client: ntfy.client(), notifier: SilentNotifier()),
    clock: () => c.now,
    open: (page) async {
      opened?.add(page);
      return true;
    },
  );
  await model.start();
  await model.refreshRecipes();
  return model;
}

Future<void> exchange(AppModel a, AppModel b) async {
  await a.sync();
  await b.sync();
  await a.sync();
  await b.sync();
}

List<String> ids(List<ShopLine> lines) => [for (final l in lines) l.id];

SilentNotifier bell(AppModel model) => model.session.notifier as SilentNotifier;

Recipe dish(String name, String kind, {int pink = 0, int blue = 0}) => Recipe(
      slug: slugOf(name),
      name: name,
      categories: [kind],
      pink: pink,
      blue: blue,
      ingredients: [Ingredient(id: slugOf('$name sauce'), name: '$name sauce', amount: '1', text: '1 $name sauce')],
    );

final List<Recipe> nine = [
  dish('Chili', 'Beef', pink: 5, blue: 5),
  dish('Tacos', 'Seafood'),
  dish('Penne', 'Pasta', pink: 4, blue: 4),
  dish('Curry', 'Chicken'),
  dish('Burgers', 'Beef', pink: 3, blue: 3),
  dish('Soup', 'Veggie'),
  dish('Stir Fry', 'Pork'),
  dish('Pizza', 'Veggie', pink: 2, blue: 2),
  dish('Salmon', 'Seafood', pink: 5, blue: 4),
];

Future<AppModel> startApp(WidgetTester tester, FakeNtfy ntfy, {Clock? clock, List<Uri>? opened, NudgeTap? launched}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  final c = clock ?? Clock(thursday);
  final notifier = SilentNotifier()..launched = launched;
  final model = AppModel(
    Session(store: MemoryStore(), client: ntfy.client(), notifier: notifier),
    clock: () => c.now,
    open: (page) async {
      opened?.add(page);
      return true;
    },
  );
  await model.start();
  await model.refreshRecipes();
  await tester.pumpWidget(DinnerApp(model: model));
  await tester.pumpAndSettle();
  // Stops the app's timers before the test ends.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  return model;
}

Future<void> show(WidgetTester tester, Finder f) async {
  await Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await show(tester, f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Back to the top of the screen that is showing: a long list only builds
/// what is near the part in view.
Future<void> top(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 5000));
  await tester.pumpAndSettle();
}

void main() {
  group('staples', () {
    test('what is always in the house is never on the list for a dinner, until it runs out', () async {
      final ntfy = FakeNtfy();
      final his = await phone(ntfy), hers = await phone(ntfy);
      await his.setMe('blue');
      await his.startHousehold();
      await hers.joinHousehold(his.household!.code);
      await his.setMeal(friday, 'beef-chili');
      await his.setCook(friday, 'blue');
      expect(ids(his.shopping), ['ground-beef', 'onion'], reason: 'the recipe also lists salt, which every kitchen has');
      expect([for (final s in his.staples) s.id], ['salt']);

      final said = await his.setStaple('onion', true);
      expect(said.text, 'onion: always in the house, so off the list.');
      expect(ids(his.shopping), ['ground-beef']);
      final eve = bell(his).scheduled.firstWhere((n) => n.ref?.kind == 'eve');
      expect(eve.body, 'If the ground beef is frozen, move it to the fridge tonight. Still to get: ground beef.', reason: 'a reminder does not ask for a staple either');
      await said.undo();
      expect(ids(his.shopping), ['ground-beef', 'onion']);
      await his.setStaple('onion', true);

      await exchange(his, hers);
      expect(ids(hers.shopping), ['ground-beef'], reason: 'both phones agree on what is always in the house');
      expect([for (final s in hers.staples) (s.id, s.out)], [('onion', false), ('salt', false)]);

      // She uses the last one.
      await hers.ranOut('onion', true);
      await exchange(hers, his);
      expect(ids(his.shopping), ['ground-beef', 'onion']);
      await his.setGot(his.shopping.firstWhere((l) => l.id == 'onion'), true);
      expect(ids(his.shopping), ['ground-beef']);
      expect(his.staples.firstWhere((s) => s.id == 'onion').out, isFalse, reason: 'bought, so it is a quiet staple again');

      // And a staple can run out with no dinner asking for it.
      await his.setMeal(friday, null);
      await his.ranOut('salt', true);
      expect([for (final l in his.shopping) (l.id, l.extra)], [('salt', true)]);
      await his.setGot(his.shopping.single, true);
      expect(his.shopping, isEmpty);

      // Not every kitchen: the guess can be turned off.
      await his.setMeal(friday, 'beef-chili');
      await his.setStaple('salt', false);
      expect(ids(his.shopping), ['ground-beef', 'salt']);
    });
  });

  group('not tonight', () {
    test('the dinner moves to the next free night with its ticks and its cook, and can be put back', () async {
      final ntfy = FakeNtfy();
      final his = await phone(ntfy), hers = await phone(ntfy);
      await his.setMe('blue');
      await hers.setMe('pink');
      await his.startHousehold();
      await hers.joinHousehold(his.household!.code);
      await his.setMeal(today, 'beef-chili');
      await his.setCook(today, 'blue');
      await his.setMeal(friday, 'baked-penne');
      await his.setGot(his.shopping.firstWhere((l) => l.id == 'ground-beef' && l.uses.any((u) => u.day == today)), true);
      expect(his.session.needs('ground-beef', today), isFalse);
      await exchange(his, hers);
      bell(hers).shown.clear();

      expect(his.movesTo(today), saturday, reason: 'Friday has a dinner already');
      final done = await his.skipDinner(today, 'leftovers');
      expect(done.text, 'Beef Chili moved to Saturday.');
      expect((his.plan.off(today), his.plan.meal(today), his.plan.cook(today)), ('leftovers', null, null));
      expect((his.plan.meal(saturday), his.plan.cook(saturday)), ('beef-chili', 'blue'));
      expect(his.session.needs('ground-beef', saturday), isFalse, reason: 'the beef bought for it is still bought');
      expect(his.session.needs('onion', saturday), isTrue);
      expect([for (final n in bell(his).scheduled) if (n.ref?.day == today) n.title], isEmpty, reason: 'no reminders for a night nobody cooks');
      expect([for (final n in bell(his).scheduled) if (n.ref?.day == saturday && !n.quiet) n.ref!.kind], ['eve', 'morn', 'start']);

      await exchange(his, hers);
      expect(hers.plan.off(today), 'leftovers');
      expect(hers.plan.meal(saturday), 'beef-chili');
      expect(bell(hers).shown.first.title, 'Leftovers today');
      expect([for (final m in ntfy.messages) m.title], contains('Dinner plan updated'));

      await done.undo();
      expect((his.plan.off(today), his.plan.meal(today), his.plan.cook(today), his.plan.meal(saturday)), (null, 'beef-chili', 'blue', null));
      expect(his.session.needs('ground-beef', today), isFalse);

      // A night with nothing planned can be called off too, and picking a
      // dinner for a night that is off puts it back on.
      final quiet = await his.skipDinner(sunday, 'out');
      expect(quiet.text, 'Eating out it is.');
      await his.setMeal(sunday, 'shrimp-tacos');
      expect((his.plan.off(sunday), his.plan.meal(sunday)), (null, 'shrimp-tacos'));
    });
  });

  group('a drafted week', () {
    final now = DateTime(2026, 11, 19, 12);

    test('fills only the empty nights, repeats nothing, and shares the cooking', () {
      final c = SyncCore('aaaa');
      c.set(mealKey(saturday), 'penne', now);
      c.set(offKey('2026-11-23'), 'out', now);
      final nights = draftWeek(now: now, plan: Plan(c), recipes: nine);
      expect([for (final n in nights) n.day], [friday, sunday, '2026-11-24', '2026-11-25', '2026-11-26']);
      expect({for (final n in nights) n.slug}.length, 5);
      expect([for (final n in nights) n.slug], isNot(contains('penne')));
      final blue = nights.where((n) => n.cook == 'blue').length, pink = nights.where((n) => n.cook == 'pink').length;
      expect((blue - pink).abs(), lessThanOrEqualTo(1));
      expect(nights.first.why, isNotEmpty);
    });

    test('does not make the week one dinner five times over', () {
      Recipe named(String name, {List<String> tags = const []}) => Recipe(slug: slugOf(name), name: name, categories: const ['Beef'], tags: tags, pink: 5, blue: 5);
      expect(nearTwins(named('One-Pan Cheesy Chicken Tortilla Melts'), named('One-Pan Cheesy Beef Tortilla Melts')), isTrue);
      expect(nearTwins(named("Pub-Style Shepherd's Pie"), named("Beef & Mushroom Shepherd's Pie")), isTrue);
      expect(nearTwins(named('Rigatoni with Beef & Zucchini Ragu'), named('Penne with Beef & Zucchini Ragu')), isTrue);
      expect(nearTwins(named('One-Pan Baja Chicken Quesadillas'), named('One-Pan Cheesy Chicken Tortilla Melts')), isFalse);
      expect(nearTwins(named('Beef Tacos'), named('Beef Chili')), isFalse);

      final pool = [
        named('Cheesy Chicken Tortilla Melts', tags: ['Tex-Mex']),
        named('Cheesy Beef Tortilla Melts', tags: ['Tex-Mex']),
        named('Cheesy Turkey Tortilla Melts', tags: ['Tex-Mex']),
        named('Beef Enchilada Bowls', tags: ['Tex-Mex']),
        named('Fajita Skillet', tags: ['Tex-Mex']),
        named('Lemon Pasta', tags: ['Pasta']),
        named('Tomato Soup'),
      ];
      final slugs = [for (final n in draftWeek(now: now, plan: Plan(SyncCore('aaaa')), recipes: pool, days: 4)) n.slug];
      expect(slugs.where((s) => s.endsWith('tortilla-melts')).length, 1, reason: 'one of the three twins');
      expect(slugs.where((s) => {'cheesy-chicken-tortilla-melts', 'cheesy-beef-tortilla-melts', 'cheesy-turkey-tortilla-melts', 'beef-enchilada-bowls', 'fajita-skillet'}.contains(s)).length, 2, reason: 'two Tex-Mex dinners at most');
      expect(slugs, containsAll(['lemon-pasta', 'tomato-soup']));
    });

    test('follows the habits of a household that has a few weeks behind it', () {
      final c = SyncCore('aaaa');
      // Three weeks: dinners Monday to Thursday, never at the weekend.
      const cooks = ['pink', 'blue', 'pink', 'blue'];
      const eaten = ['burgers', 'soup', 'curry', 'pizza'];
      for (var week = 1; week <= 3; week++) {
        for (var d = 0; d < 4; d++) {
          // Monday 16 November 2026 is three days before "now".
          final day = dayText(DateTime(2026, 11, 16 + d - 7 * (week - 1)));
          if (day.compareTo(today) >= 0) continue;
          c.set(mealKey(day), week == 1 ? eaten[d] : 'tacos', now);
          c.set(cookKey(day), cooks[d], now);
        }
      }
      final nights = draftWeek(now: now, plan: Plan(c), recipes: nine);
      expect([for (final n in nights) (weekdayName(n.date), n.cook)], [('Monday', 'pink'), ('Tuesday', 'blue'), ('Wednesday', 'pink'), ('Thursday', 'blue')],
          reason: 'the weekend stays free, and each night goes to whoever usually has it');
      expect([for (final n in nights) n.slug], isNot(anyOf(contains('burgers'), contains('soup'), contains('curry'), contains('tacos'))), reason: 'nothing from the last two weeks');
    });

    test('is offered when the plan runs out, used with one tap, and not offered again the next evening', () async {
      final ntfy = FakeNtfy();
      final clock = Clock(thursday);
      final m = await phone(ntfy, clock: clock);
      await m.setMe('blue');
      final offer = bell(m).scheduled.firstWhere((n) => n.ref?.kind == 'week');
      expect(offer.when, DateTime(2026, 11, 19, 20));
      expect(offer.title, 'Dinners for the coming week');
      expect(offer.body, contains('Friday'));

      clock.now = DateTime(2026, 11, 20, 9);
      await m.session.replan(clock.now);
      expect(bell(m).scheduled.firstWhere((n) => n.ref?.kind == 'week').when, DateTime(2026, 11, 22, 20), reason: 'asked last night, so not tonight or tomorrow');

      await m.handleTap(const NudgeTap(NudgeRef('week'), 'use'));
      expect([for (var i = 1; i <= 3; i++) m.plan.meal(dayText(dayAfter(clock.now, i)))], everyElement(isNotNull));
      final asks = m.takeAsks();
      expect(asks.whereType<AskTab>().single.tab, 1);
      final said = asks.whereType<AskSay>().single;
      expect(said.text, '3 dinners planned. The list has what they need.');
      expect(bell(m).scheduled.where((n) => n.ref?.kind == 'week'), isEmpty, reason: 'the plan no longer runs out');
      expect(m.plan.cook(dayText(dayAfter(clock.now, 1))), isNotNull);

      await said.undo!();
      expect(m.plan.meal(dayText(dayAfter(clock.now, 1))), isNull);
      await m.handleTap(const NudgeTap(NudgeRef('week'), 'use'));
      m.takeAsks();
      await m.handleTap(const NudgeTap(NudgeRef('week'), 'use'));
      expect(m.takeAsks().whereType<AskSay>().single.text, 'The week is already planned.');
    });
  });

  group('how was it', () {
    test('an answer goes to the recipe site the way its own pages send one, without the household names', () async {
      final ntfy = FakeNtfy();
      final clock = Clock(DateTime(2026, 11, 19, 19, 30));
      final m = await phone(ntfy, clock: clock);
      await m.setMe('blue');
      await m.setName('blue', 'Sam');
      await m.setMeal(today, 'beef-chili');
      expect(bell(m).scheduled.where((n) => n.ref?.kind == 'rate' && n.ref?.day == today), isEmpty, reason: 'its hour has passed today');
      expect(m.afterDinner, isTrue);
      expect((m.ratedToday('beef-chili'), m.myStars('beef-chili')), (false, 5), reason: 'the site says five from an earlier time');

      await m.handleTap(const NudgeTap(NudgeRef('rate', day: today, slug: 'beef-chili'), 'fine'));
      await m.session.flushSite(clock.now);
      expect((m.ratedToday('beef-chili'), m.myStars('beef-chili')), (true, 3));
      final sent = [for (final x in ntfy.messages) if (x.topic == siteTopic) x];
      expect([for (final x in sent) x.title], ['Blue: 3 stars', 'Cooked tonight']);
      expect(sent.first.message, startsWith('Beef Chili\n\ndp1 {'));
      expect(sent.first.message, allOf(contains('"k":"rate"'), contains('"slug":"beef-chili"'), contains('"who":"blue"'), contains('"stars":3')));
      expect(sent.first.message, matches(RegExp(r'"at":"2026-11-\d\dT\d\d:\d\d:\d\dZ"')));
      expect([for (final x in sent) '${x.title} ${x.message}'].join(), isNot(contains('Sam')), reason: 'the topic is public');

      // Sent once, not on every sync.
      await m.session.flushSite(clock.now.add(const Duration(minutes: 30)));
      expect(ntfy.messages.where((x) => x.topic == siteTopic).length, 2);

      // A second thought replaces the first, and the dinner is not "cooked" twice.
      await m.rate('beef-chili', 4);
      await m.session.flushSite(clock.now.add(const Duration(minutes: 31)));
      expect([for (final x in ntfy.messages) if (x.topic == siteTopic) x.title], ['Blue: 3 stars', 'Cooked tonight', 'Blue: 4 stars']);

      // Once the site's data shows it, it is no longer queued.
      ntfy.recipesJson = ntfy.recipesJson.replaceFirst("\"sourceStars\":{\"pink\":4,\"blue\":5}", "\"sourceStars\":{\"pink\":4,\"blue\":4}");
      await m.refreshRecipes();
      await m.session.flushSite(clock.now.add(const Duration(minutes: 40)));
      expect([for (final e in m.session.siteQueue) e['k']], ['cooked']);

      // What was said survives a restart of the app.
      final again = Session(store: m.session.store, client: ntfy.client(), notifier: SilentNotifier());
      await again.load();
      expect(again.rated['beef-chili'], (day: today, stars: 4));
    });
  });

  group('a note from the stove', () {
    test('the link the kitchen page opens names the recipe and the step by its own words', () async {
      final m = await phone(FakeNtfy());
      const step = 'Brown the beef in a large pot, 5-7 minutes.';
      expect(stepId(step), '8b807cd6');
      expect(m.noteLink(Uri.parse('dinnerplanner://open/note?slug=beef-chili&step=8b807cd6')), (slug: 'beef-chili', place: 1, step: step), reason: 'as Android hands it over when it starts the app');
      expect(m.noteLink(Uri.parse('/note?slug=beef-chili&step=8b807cd6')), (slug: 'beef-chili', place: 1, step: step), reason: 'as Flutter passes it on when the app is already running');
      expect(m.noteLink(Uri.parse('/note?slug=beef-chili&step=ffffffff')), (slug: 'beef-chili', place: null, step: null), reason: 'a step this phone does not know: a note on the whole recipe');
      expect(m.noteLink(Uri.parse('/note?slug=beef-chili')), (slug: 'beef-chili', place: null, step: null));
      expect(m.noteLink(Uri.parse('/')), isNull);
      expect(m.noteLink(Uri.parse('/note')), isNull);
      expect(m.noteLink(Uri.parse('https://example.com/other?slug=beef-chili')), isNull);
      expect(kitchenPage('https://site.example', 'beef-chili').queryParameters['app'], '1', reason: 'the page only offers the button when the app opened it');
    });

    testWidgets('opens on that step with the keyboard up, saves, and leaves', (tester) async {
      final model = await startApp(tester, FakeNtfy());
      await model.setMe('blue');
      final left = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        left.add(call.method);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      Future<void> link(String location) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'flutter/navigation',
          const JSONMethodCodec().encodeMethodCall(MethodCall('pushRouteInformation', {'location': location, 'state': null})),
          (_) {},
        );
        await tester.pumpAndSettle();
      }

      await link('/note?slug=beef-chili&step=8b807cd6');
      expect(find.text('Step 2: Brown the beef in a large pot, 5-7 minutes.'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('stove-note-field'))).autofocus, isTrue);
      await tester.enterText(find.byKey(const ValueKey('stove-note-field')), 'Garlic salt goes in here');
      await tester.tap(find.byKey(const ValueKey('stove-note-save')));
      await tester.pumpAndSettle();
      final note = model.plan.notes('beef-chili').single;
      expect((note.step, note.text, note.anchor), ('8b807cd6', 'Garlic salt goes in here', 'Brown the beef in a large pot, 5-7 minutes.'));
      expect(left, contains('SystemNavigator.pop'), reason: 'back to the recipe in the browser');
      expect(find.byKey(const ValueKey('stove-note-field')), findsNothing);
      expect(find.text('Tonight'), findsWidgets, reason: 'the app itself is where it was');

      // The same step again carries on from the note that is there.
      await link('/note?slug=beef-chili&step=8b807cd6');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('stove-note-field'))).controller!.text, 'Garlic salt goes in here');
      await tester.enterText(find.byKey(const ValueKey('stove-note-field')), '');
      await tester.tap(find.byKey(const ValueKey('stove-note-save')));
      await tester.pumpAndSettle();
      expect(model.plan.notes('beef-chili'), isEmpty, reason: 'saved empty, it is gone');

      // A link that is not ours opens nothing and breaks nothing.
      await link('/somewhere/else');
      expect(find.text('Tonight'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('on the screens', () {
    testWidgets('Not tonight: one tap says what tonight is instead, and Undo puts the dinner back', (tester) async {
      final model = await startApp(tester, FakeNtfy());
      await model.setMe('blue');
      await model.setMeal(today, 'beef-chili');
      await model.setCook(today, 'blue');
      await model.setMeal(friday, 'baked-penne');
      await tester.pumpAndSettle();

      await tap(tester, 'not-tonight');
      expect(tester.widget<Text>(find.byKey(const ValueKey('skip-lead'))).data, 'Beef Chili moves to Saturday, with what is ticked for it. What is tonight instead?');
      await tester.tap(find.byKey(const ValueKey('skip-leftovers')));
      await tester.pumpAndSettle();
      await top(tester);
      expect(find.text('Leftovers tonight'), findsOneWidget);
      expect(find.byKey(const ValueKey('tonight-off')), findsOneWidget);
      expect(find.text('Beef Chili moved to Saturday.'), findsOneWidget);
      expect(model.plan.meal(saturday), 'beef-chili');

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      await top(tester);
      expect(find.text("You're cooking tonight"), findsOneWidget);
      expect((model.plan.meal(today), model.plan.meal(saturday)), ('beef-chili', null));

      await tap(tester, 'not-tonight');
      await tester.tap(find.byKey(const ValueKey('skip-out')));
      await tester.pumpAndSettle();
      await top(tester);
      expect(find.text('Eating out tonight'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cook-after-all')));
      await tester.pumpAndSettle();
      expect(find.text('Nothing is planned for tonight'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tapped reminder does the next thing: the recipe, the sheet, the ticks, the week', (tester) async {
      final opened = <Uri>[];
      final model = await startApp(tester, FakeNtfy(), opened: opened);
      await model.setMe('blue');
      await model.setMeal(today, 'beef-chili');
      await model.setCook(today, 'blue');
      await model.setMeal(friday, 'baked-penne');
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      // "Time to start": the recipe itself.
      bell(model).tap(const NudgeTap(NudgeRef('start', day: today, slug: 'beef-chili')));
      await tester.pumpAndSettle();
      expect(opened.single.toString(), endsWith('/kitchen.html?app=1#/r/beef-chili'));

      // "All here" on tomorrow's dinner.
      bell(model).tap(const NudgeTap(NudgeRef('eve', day: friday, slug: 'baked-penne'), 'have'));
      await tester.pumpAndSettle();
      expect(find.text('Everything for Baked Penne is ticked.'), findsOneWidget);
      expect(model.session.facts(friday, 'baked-penne').missing, isEmpty);
      expect(find.text("You're cooking tonight"), findsOneWidget, reason: 'the app came to the front on Tonight');

      // "Not tonight" from the morning reminder.
      bell(model).tap(const NudgeTap(NudgeRef('morn', day: today, slug: 'beef-chili'), 'skip'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('skip-lead')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('skip-skip')));
      await tester.pumpAndSettle();
      expect(find.text('No dinner tonight'), findsOneWidget);
      expect(model.plan.meal(saturday), 'beef-chili');

      // "Change" on the offer of a week: look it over first.
      bell(model).tap(const NudgeTap(NudgeRef('week'), 'change'));
      await tester.pumpAndSettle();
      expect(find.text('The coming week'), findsOneWidget);
      expect(find.byKey(const ValueKey('draft-$sunday')), findsOneWidget, reason: 'the one recipe left for the one night after the plan ends');
      await tester.tap(find.byKey(const ValueKey('draft-use')));
      await tester.pumpAndSettle();
      expect(model.plan.meal(sunday), 'shrimp-tacos');
      expect(find.text('1 dinner planned. The list has what they need.'), findsOneWidget);
      expect(find.text('The next two weeks'), findsOneWidget, reason: 'on the Week tab');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a reminder that started the app is carried out once the screens are up', (tester) async {
      await startApp(tester, FakeNtfy(), launched: const NudgeTap(NudgeRef('eve', day: friday, slug: 'baked-penne'), 'list'));
      expect(find.text('Shopping list'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the week: fill the empty nights, drop one, use the rest', (tester) async {
      final model = await startApp(tester, FakeNtfy());
      await model.setMe('blue');
      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      expect(find.text('Fill the 7 empty nights this week'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('draft-week')));
      await tester.pumpAndSettle();
      expect(find.text('Use these 3 dinners'), findsOneWidget, reason: 'the site has three recipes');
      await tester.tap(find.byKey(const ValueKey('draft-drop-$saturday')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('draft-use')));
      await tester.pumpAndSettle();
      expect((model.plan.meal(friday) != null, model.plan.meal(saturday), model.plan.meal(sunday) != null), (true, null, true));
      expect(model.plan.cook(friday), isNotNull);
      expect(find.text('2 dinners planned. The list has what they need.'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(model.plan.meal(friday), isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('after dinner time the card asks how it was, with five stars', (tester) async {
      final ntfy = FakeNtfy();
      final model = await startApp(tester, ntfy, clock: Clock(DateTime(2026, 11, 19, 19, 30)));
      await model.setMe('pink');
      await model.setMeal(today, 'beef-chili');
      await tester.pumpAndSettle();
      expect(find.text('How was it?'), findsOneWidget);
      expect(find.byKey(const ValueKey('tonight-timing')), findsNothing, reason: 'when to start no longer matters');
      await tap(tester, 'rate-2');
      await tester.runAsync(() => model.session.flushSite(model.now));
      await tester.pumpAndSettle();
      expect(find.text('Your stars tonight'), findsOneWidget);
      expect(tester.widget<Icon>(find.descendant(of: find.byKey(const ValueKey('rate-2')), matching: find.byType(Icon))).icon, Icons.star);
      expect(tester.widget<Icon>(find.descendant(of: find.byKey(const ValueKey('rate-3')), matching: find.byType(Icon))).icon, Icons.star_border);
      expect([for (final x in ntfy.messages) if (x.topic == siteTopic) x.title], contains('Pink: 2 stars'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('shop: hold a line to say it is always in the house; tap it when it runs out', (tester) async {
      final model = await startApp(tester, FakeNtfy());
      await model.setMe('blue');
      await model.setMeal(friday, 'beef-chili');
      await tester.tap(find.text('Shop'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('staple-hint')), findsOneWidget);

      await tester.longPress(find.byKey(const ValueKey('shop-onion')));
      await tester.pumpAndSettle();
      expect(find.text('Onion: always in the house, so off the list.'), findsOneWidget);
      expect(find.byKey(const ValueKey('shop-onion')), findsNothing);
      expect(find.byKey(const ValueKey('staple-hint')), findsNothing, reason: 'learned, so the hint goes');

      await tap(tester, 'staple-onion');
      await tester.tap(find.byKey(const ValueKey('staple-out')));
      await tester.pumpAndSettle();
      final list = find.descendant(of: find.byType(ShopScreen), matching: find.byType(Scrollable)).first;
      await tester.drag(list, const Offset(0, 5000));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('shop-onion')), findsOneWidget);

      // The sheet for what you buy has the same switch.
      await tap(tester, 'shop-edit-ground-beef');
      await tap(tester, 'shop-staple');
      await tap(tester, 'shop-buy-save');
      expect(model.staple('ground-beef'), isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}

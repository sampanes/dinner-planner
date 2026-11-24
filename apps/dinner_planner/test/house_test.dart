// What is in the house, and what follows from knowing it: a list that sets
// apart what was bought lately, "what can I cook with what's here", a
// reminder to go shopping. Then the parts that keep two phones on one
// version, and a timer that rings with the screen off.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dinner_planner/app_model.dart';
import 'package:dinner_planner/core/glance.dart';
import 'package:dinner_planner/core/nudges.dart';
import 'package:dinner_planner/core/pantry.dart';
import 'package:dinner_planner/core/plan.dart';
import 'package:dinner_planner/core/shopping.dart';
import 'package:dinner_planner/core/sync_core.dart';
import 'package:dinner_planner/data/session.dart';
import 'package:dinner_planner/data/store.dart';
import 'package:dinner_planner/data/updates.dart';
import 'package:dinner_planner/main.dart';
import 'package:dinner_planner/notify/notifier.dart';
import 'package:dinner_planner/ui/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ntfy.dart';

/// A Thursday afternoon, before anything is due.
final DateTime thursday = DateTime(2026, 11, 19, 16, 30);
const String today = '2026-11-19', friday = '2026-11-20', saturday = '2026-11-21', monday = '2026-11-23';

class Clock {
  Clock(this.now);
  DateTime now;
}

class FakeInstaller implements Installer {
  FakeInstaller(this.dir);

  final String dir;
  final List<String> installed = [];
  int steppedBack = 0;

  @override
  Future<String> folder() async => dir;

  @override
  Future<bool> install(String path) async {
    installed.add(path);
    return true;
  }

  @override
  Future<void> stepBack() async => steppedBack++;

  int redrawn = 0;

  @override
  Future<void> redrawWidget() async => redrawn++;
}

Map<String, Object?> _item(String id, String amount) => {'id': id, 'displayName': id.replaceAll('-', ' '), 'amountText': amount, 'text': '$amount ${id.replaceAll('-', ' ')}'};

/// Four dinners that overlap the way real ones do: two want the beef and the
/// sour cream, one is all cupboard.
final String fourDinners = jsonEncode([
  {'slug': 'tacos', 'displayName': 'Tacos', 'categories': ['Beef'], 'sourceStars': {'pink': 5, 'blue': 5}, 'ingredients': [_item('ground-beef', '1 lb'), _item('sour-cream', '2 tbsp'), _item('flour-tortillas', '6'), _item('salt', 'to taste')]},
  {'slug': 'chili', 'displayName': 'Chili', 'categories': ['Beef'], 'minutes': 35, 'ingredients': [_item('ground-beef', '1 lb'), _item('kidney-beans', '1'), _item('sour-cream', '2 tbsp'), _item('onion', '1')]},
  {'slug': 'pasta', 'displayName': 'Pasta', 'categories': ['Pasta'], 'ingredients': [_item('penne-pasta', '6 oz'), _item('marinara-sauce', '1'), _item('parmesan-cheese', '1 oz')]},
  {'slug': 'soup', 'displayName': 'Soup', 'categories': ['Veggie'], 'sourceStars': {'pink': 4, 'blue': 4}, 'ingredients': [_item('onion', '1'), _item('carrot', '2'), _item('veggie-stock-concentrate', '1')]},
]);

Future<AppModel> phone(FakeNtfy ntfy, {Clock? clock, Store? store, Installer? installer, List<Uri>? opened}) async {
  final c = clock ?? Clock(thursday);
  final model = AppModel(
    Session(store: store ?? MemoryStore(), client: ntfy.client(), notifier: SilentNotifier()),
    clock: () => c.now,
    open: (page) async {
      opened?.add(page);
      return true;
    },
    installer: installer,
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

Future<AppModel> startApp(WidgetTester tester, FakeNtfy ntfy, {Clock? clock, Installer? installer}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  final c = clock ?? Clock(thursday);
  final model = AppModel(Session(store: MemoryStore(), client: ntfy.client(), notifier: SilentNotifier()), clock: () => c.now, open: (_) async => true, installer: installer);
  await model.start();
  await model.refreshRecipes();
  await tester.pumpWidget(DinnerApp(model: model));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  return model;
}

String releases(String version, {String? sha, int? size}) => jsonEncode([
      {'tag_name': 'v-site-1', 'assets': []},
      {'tag_name': 'app-v$version', 'draft': false, 'prerelease': false, 'assets': [
        {'name': 'dinner-planner-$version.apk', 'size': size ?? 0, 'digest': sha == null ? null : 'sha256:$sha', 'browser_download_url': 'https://github.com/sampanes/dinner-planner/releases/download/app-v$version/dinner-planner-$version.apk'},
      ]},
      {'tag_name': 'app-v0.8.0', 'assets': [
        {'name': 'dinner-planner-0.8.0.apk', 'size': 1, 'browser_download_url': 'https://github.com/sampanes/dinner-planner/releases/download/app-v0.8.0/dinner-planner-0.8.0.apk'},
      ]},
    ]);

void main() {
  group('the pantry', () {
    Pantry pantry(Map<String, String> came, {String on = today, List<({String day, List<String> ids})> dinners = const [], Set<String> staples = const {}, Set<String> out = const {}}) {
      final core = SyncCore('aa');
      came.forEach((id, day) => core.set(inKey(id), day, thursday));
      for (final id in out) {
        core.set(wantKey(id), '1', thursday);
      }
      const kinds = {'ground-beef': 'meat', 'sour-cream': 'dairy', 'penne-pasta': 'dry', 'kidney-beans': 'canned', 'onion': 'produce'};
      return Pantry(core: core, section: (id) => kinds[id] ?? 'other', staple: staples.contains, dinners: dinners, now: parseDay(on)!);
    }

    test('fresh things go off, the cupboard keeps', () {
      final p = pantry({'ground-beef': today, 'sour-cream': today, 'penne-pasta': today});
      expect([p.has('ground-beef', today), p.has('ground-beef', '2026-11-22'), p.has('ground-beef', monday)], [true, true, false], reason: 'meat keeps three days');
      expect([p.has('sour-cream', '2026-12-01'), p.has('sour-cream', '2026-12-02')], [true, false], reason: 'dairy keeps twelve');
      expect(p.has('penne-pasta', '2027-03-01'), isTrue);
      expect(p.has('onion', today), isFalse, reason: 'nobody said there is any');
      expect(p.has('ground-beef', '2026-11-18'), isFalse, reason: 'it was not in the house before it was bought');
    });

    test('a dinner uses up the fresh things it asks for, and leaves the tub and the bag', () {
      final p = pantry({'ground-beef': today, 'sour-cream': today, 'kidney-beans': today}, dinners: [(day: friday, ids: ['ground-beef', 'sour-cream', 'kidney-beans'])]);
      expect(p.has('ground-beef', friday), isTrue, reason: 'for that dinner itself it is there');
      expect(p.has('ground-beef', saturday), isFalse, reason: "Friday's dinner took the beef");
      expect(p.has('kidney-beans', saturday), isFalse, reason: 'and the can');
      expect(p.has('sour-cream', saturday), isTrue, reason: 'a tub outlasts a dinner');
    });

    test('a staple is there until someone says it has run out', () {
      expect(pantry({}, staples: {'butter'}).has('butter', monday), isTrue);
      expect(pantry({}, staples: {'butter'}, out: {'butter'}).has('butter', monday), isFalse);
    });

    test('says when something came in, in words', () {
      expect([sinceText(today, thursday), sinceText('2026-11-18', thursday), sinceText('2026-11-15', thursday), sinceText('2026-11-02', thursday)], ['today', 'yesterday', 'Sunday', 'November 2']);
    });
  });

  group('what one phone buys, the other has', () {
    late FakeNtfy ntfy;
    late Clock clock;
    late AppModel blue, pink;

    setUp(() async {
      ntfy = FakeNtfy()..recipesJson = fourDinners;
      clock = Clock(thursday);
      blue = await phone(ntfy, clock: clock);
      pink = await phone(ntfy, clock: clock);
      await blue.setMe('blue');
      await pink.setMe('pink');
      await blue.startHousehold();
      await pink.joinHousehold(blue.household!.code);
      await exchange(blue, pink);
      // Tacos on Friday, and Blue buys everything for them.
      await blue.setMeal(friday, 'tacos');
      for (final line in blue.shopping) {
        await blue.setGot(line, true);
      }
      await exchange(blue, pink);
    });

    test('a later dinner does not ask for the sour cream again, but does ask for more beef', () async {
      expect(ids(blue.shopping), isEmpty);
      await pink.setMeal(monday, 'chili');
      expect(ids(pink.shopping), ['ground-beef', 'kidney-beans', 'onion'], reason: "Friday's tacos use up the beef; the tub of sour cream is still there on Monday");
      expect(ids(pink.shoppingLikely), ['sour-cream']);
      expect(pink.hereSince('sour-cream'), 'today');
      expect(pink.here('ground-beef'), isTrue, reason: 'in the house tonight, whatever Friday does to it');
      expect(pink.shoppingText(), isNot(contains('sour cream')));
    });

    test('seeing it in the fridge ticks it; finding it gone puts it on the list', () async {
      await pink.setMeal(monday, 'chili');
      final line = pink.shoppingLikely.single;
      await pink.setGot(line, true, fresh: false);
      expect(pink.shoppingLikely, isEmpty);
      expect(ids(pink.shoppingGot), contains('sour-cream'));
      await pink.setGot(line, false);
      expect(ids(pink.shoppingLikely), ['sour-cream'], reason: 'unticking a look in the fridge does not throw the tub away');

      final done = await pink.notHere('sour-cream');
      expect(done.text, 'sour cream is on the list to buy.');
      expect(ids(pink.shopping), contains('sour-cream'));
      expect(pink.shoppingLikely, isEmpty);
      await exchange(pink, blue);
      expect(blue.here('sour-cream'), isFalse, reason: 'both phones know it is gone');
      await done.undo();
      expect(ids(pink.shoppingLikely), ['sour-cream']);
    });

    test('by the time it would have gone off it is back on the list', () async {
      await pink.setMeal('2026-12-02', 'chili');
      expect(ids(pink.shoppingLikely), isEmpty, reason: 'thirteen days is too long for sour cream');
      expect(ids(pink.shopping), contains('sour-cream'));
    });

    test('the evening reminder asks for a look, not a trip to the store', () async {
      await pink.setMeal(monday, 'chili');
      await pink.setCook(monday, 'pink');
      final eve = bell(pink).scheduled.firstWhere((n) => n.ref?.kind == 'eve' && n.ref?.day == monday);
      expect(eve.body, 'If the ground beef is frozen, move it to the fridge tonight. Still to get: ground beef, kidney beans and onion. Check you still have the sour cream.');

      // "All here" ticks the lot and says so for other dinners too.
      await pink.handleTap(NudgeTap(eve.ref!, 'have'));
      expect(ids(pink.shopping), isEmpty);
      expect(pink.session.core.value(inKey('onion')), today);
      expect(pink.session.core.value(inKey('sour-cream')), today, reason: 'the day Blue bought it stays');
    });

    test('unticking a line the same day takes it out of the house again', () async {
      await blue.setMeal(saturday, 'soup');
      final onion = blue.shopping.firstWhere((l) => l.id == 'onion');
      await blue.setGot(onion, true);
      expect(blue.here('onion'), isTrue);
      await blue.setGot(blue.shoppingGot.firstWhere((l) => l.id == 'onion'), false);
      expect(blue.session.core.value(inKey('onion')), isNull);
    });
  });

  group("what can I cook with what's here", () {
    test('the dinners that need the least bought come first, and say what is missing', () async {
      final m = await phone(FakeNtfy()..recipesJson = fourDinners);
      await m.setMe('blue');
      expect(m.pantryUntold, isTrue);
      for (final id in ['penne-pasta', 'marinara-sauce', 'parmesan-cheese', 'onion', 'carrot', 'ground-beef']) {
        await m.setHere(id, true);
      }
      expect(m.pantryUntold, isFalse);
      final ideas = m.cookFromHere(m.recipes);
      expect([for (final i in ideas) '${i.recipe.slug}: ${i.missing.join(', ')}'], [
        'pasta: ',
        'soup: veggie stock concentrate',
        'tacos: sour cream, flour tortillas',
        'chili: kidney beans, sour cream',
      ], reason: 'salt is a staple; a tie goes to the better rated');
      expect(ideas.first.total, 3);
    });

    testWidgets('one tap from an empty night to a dinner the house can make', (tester) async {
      final model = await startApp(tester, FakeNtfy()..recipesJson = fourDinners);
      await model.setMe('blue');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cook-from-here')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('here-untold')), findsOneWidget, reason: 'nothing is known yet, and the page says how to change that');

      await tester.tap(find.byKey(const ValueKey('here-say')));
      await tester.pumpAndSettle();
      expect(find.text('Nothing marked yet.'), findsOneWidget);
      expect(find.byKey(const ValueKey('house-salt')), findsNothing, reason: 'staples are not asked about');
      for (final id in ['penne-pasta', 'marinara-sauce', 'parmesan-cheese']) {
        await tester.ensureVisible(find.byKey(ValueKey('house-$id')));
        await tester.tap(find.byKey(ValueKey('house-$id')));
        await tester.pumpAndSettle();
      }
      expect(find.text('3 marked as here.'), findsOneWidget);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('here-untold')), findsNothing);
      expect(find.text('Everything is in the house'), findsOneWidget);
      expect(find.textContaining('Have 0 of 3'), findsOneWidget, reason: 'the soup, which is all still to buy');
      await tester.tap(find.byKey(const ValueKey('idea-pasta')));
      await tester.pumpAndSettle();
      expect(model.plan.meal(today), 'pasta');
      expect(find.byKey(const ValueKey('cook-from-here')), findsNothing, reason: 'tonight has a dinner now');
    });

    testWidgets('the list sets apart what was bought lately', (tester) async {
      final model = await startApp(tester, FakeNtfy()..recipesJson = fourDinners);
      await model.setMe('blue');
      await model.setMeal(friday, 'chili');
      await model.setHere('sour-cream', true);
      await tester.tap(find.text('Shop'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('shop-sour-cream')), findsNothing);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('likely-sour-cream')), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Probably in the house'), findsOneWidget);
      expect(find.textContaining('In the house since today'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('likely-gone-sour-cream')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('likely-sour-cream')), findsNothing);
      expect(ids(model.shopping), contains('sour-cream'));
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const ValueKey('likely-sour-cream')), 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const ValueKey('likely-sour-cream')));
      await tester.pumpAndSettle();
      expect(ids(model.shoppingGot), contains('sour-cream'));
      expect(model.session.core.value(inKey('sour-cream')), today);
    });
  });

  group('a reminder to go shopping', () {
    test('comes the next morning with what there is to buy, then keeps quiet for three days', () async {
      final ntfy = FakeNtfy()..recipesJson = fourDinners;
      final clock = Clock(thursday);
      final m = await phone(ntfy, clock: clock);
      await m.setMe('blue');
      expect(bell(m).scheduled.where((n) => n.ref?.kind == 'shop'), isEmpty, reason: 'nothing planned, nothing to buy');

      await m.setMeal(saturday, 'chili');
      await m.setMeal(monday, 'pasta');
      final shop = bell(m).scheduled.firstWhere((n) => n.ref?.kind == 'shop');
      expect(shop.when, DateTime(2026, 11, 20, 7, 30));
      expect(shop.title, '7 things to buy for 2 dinners');
      expect(shop.body, 'First needed tomorrow. Ground beef, kidney beans, sour cream, onion and 3 more.');
      expect(shop.buttons.single.id, 'list');
      expect(shop.quiet, isFalse);

      // It fired; the next is three days on, and counts what is left.
      clock.now = DateTime(2026, 11, 20, 12);
      for (final line in m.shopping.where((l) => l.uses.any((u) => u.day == saturday))) {
        await m.setGot(line, true);
      }
      await m.session.replan(clock.now);
      final next = bell(m).scheduled.firstWhere((n) => n.ref?.kind == 'shop');
      expect(next.when, DateTime(2026, 11, 23, 7, 30));
      expect(next.title, '3 things to buy for 1 dinner');

      // Tapping it opens the list.
      await m.handleTap(const NudgeTap(NudgeRef('shop')));
      expect(m.takeAsks().whereType<AskTab>().single.tab, 2);

      for (final line in m.shopping) {
        await m.setGot(line, true);
      }
      await m.session.replan(clock.now);
      expect(bell(m).scheduled.where((n) => n.ref?.kind == 'shop'), isEmpty, reason: 'everything is in the house');
    });

    test("tonight's dinner is left to the cook's own reminders", () async {
      final m = await phone(FakeNtfy()..recipesJson = fourDinners);
      await m.setMe('blue');
      await m.setMeal(today, 'chili');
      expect(bell(m).scheduled.where((n) => n.ref?.kind == 'shop'), isEmpty);
    });
  });

  group('two phones, one version', () {
    test('each says which version it runs, quietly, and notices when the other is behind', () async {
      final ntfy = FakeNtfy();
      final a = await phone(ntfy), b = await phone(ntfy);
      await a.startHousehold();
      await b.joinHousehold(a.household!.code);
      await exchange(a, b);
      expect(a.session.core.value(versionKey(b.session.core.dev)), appVersion);
      expect(a.versionNote, isNull, reason: 'the same version on both');
      expect(ntfy.messages.where((m) => m.title.contains('updated')), isEmpty, reason: 'a version is not news for a person');

      // The other phone turns out to run something older, or newer.
      b.session.core.set(versionKey(b.session.core.dev), '0.9.0', thursday.add(const Duration(minutes: 1)));
      await exchange(b, a);
      expect(a.versionNote, 'The other phone has an older version (0.9.0), so some of this will not show there.');
      b.session.core.set(versionKey(b.session.core.dev), '0.20.1', thursday.add(const Duration(minutes: 2)));
      await exchange(b, a);
      expect(a.versionNote, 'The other phone has a newer version (0.20.1) than this one.');
    });

    test('a phone from before versions were said counts as older', () async {
      final ntfy = FakeNtfy();
      final a = await phone(ntfy), b = await phone(ntfy);
      await a.startHousehold();
      await b.joinHousehold(a.household!.code);
      b.session.core.set(versionKey(b.session.core.dev), null, thursday.add(const Duration(minutes: 1)));
      await exchange(b, a);
      expect(a.versionNote, startsWith('The other phone has an older version of the app'));
      expect((await phone(ntfy)).versionNote, isNull, reason: 'no other phone, nothing to compare');
    });

    test('the version in the code is the version in pubspec.yaml', () {
      final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
      expect(line.split(':')[1].trim().split('+').first, appVersion);
    });
  });

  group('a new version without a computer', () {
    test('versions compare by number, not by letter', () {
      expect(compareVersions('0.10.0', '0.9.2'), greaterThan(0));
      expect(compareVersions('0.9.0+12', '0.9.0'), 0);
      expect(compareVersions('1.0.0', '0.99.99'), greaterThan(0));
      expect(compareVersions('0.9', '0.9.1'), lessThan(0));
    });

    test('the newest app release is found among the others, and only on GitHub', () {
      final r = newestRelease(jsonDecode(releases('0.11.0', sha: 'ab' * 32, size: 5)))!;
      expect((r.version, r.size, r.sha256), ('0.11.0', 5, 'ab' * 32));
      expect(r.url, 'https://github.com/sampanes/dinner-planner/releases/download/app-v0.11.0/dinner-planner-0.11.0.apk');
      expect(newestRelease(jsonDecode('[{"tag_name": "app-v9.9.9", "assets": [{"name": "x.apk", "browser_download_url": "https://elsewhere.example/x.apk"}]}]')), isNull);
      expect(newestRelease(jsonDecode('[{"tag_name": "app-v9.9.9", "draft": true, "assets": [{"name": "x.apk", "browser_download_url": "https://github.com/a/b/x.apk"}]}]')), isNull);
      expect(releasesApi('https://sampanes.github.io/dinner-planner').toString(), 'https://api.github.com/repos/sampanes/dinner-planner/releases?per_page=20');
      expect(releasesApi('https://recipes.example/dinner'), isNull, reason: 'a site kept elsewhere has no releases to ask for');
    });

    test('the phone asks twice a day, says so once, and the card is there until it is done', () async {
      final ntfy = FakeNtfy()..releasesJson = releases(appVersion);
      final clock = Clock(thursday);
      final store = MemoryStore();
      final m = await phone(ntfy, clock: clock, store: store);
      await m.wake();
      await Future<void>.delayed(Duration.zero);
      expect(ntfy.asked, hasLength(1));
      expect(m.updateReady, isFalse, reason: 'this is the newest');
      await m.wake();
      await Future<void>.delayed(Duration.zero);
      expect(ntfy.asked, hasLength(1), reason: 'asked a moment ago');

      ntfy.releasesJson = releases('0.99.0');
      clock.now = thursday.add(const Duration(hours: 13));
      expect(await m.session.checkUpdate(clock.now), isTrue, reason: 'news');
      expect((m.updateReady, m.newestVersion), (true, '0.99.0'));
      clock.now = clock.now.add(const Duration(hours: 13));
      expect(await m.session.checkUpdate(clock.now), isFalse, reason: 'the same version is not news twice');
      expect(m.updateReady, isTrue);

      // Kept, so the background task and the next start know too.
      final again = Session(store: store, client: ntfy.client(), notifier: SilentNotifier());
      await again.load();
      expect((again.updateReady, again.newest?.version), (true, '0.99.0'));
      await m.sleep();
    });

    test('Update fetches the file, checks it is the one GitHub published, and hands it to Android', () async {
      final dir = await Directory.systemTemp.createTemp('dp-update');
      addTearDown(() => dir.delete(recursive: true));
      final apk = List<int>.generate(5000, (i) => i % 251);
      final ntfy = FakeNtfy()
        ..releasesJson = releases('0.99.0', sha: sha256.convert(apk).toString(), size: apk.length)
        ..downloads['/sampanes/dinner-planner/releases/download/app-v0.99.0/dinner-planner-0.99.0.apk'] = apk;
      final installer = FakeInstaller(dir.path);
      final m = await phone(ntfy, installer: installer);
      await m.checkForUpdate();
      expect(m.updateReady, isTrue);
      await File('${dir.path}/dinner-planner-0.1.0.apk').writeAsBytes([1, 2, 3]);

      await m.update();
      expect(m.updateError, isNull);
      expect(m.updateProgress, isNull, reason: 'done');
      expect(installer.installed.single, endsWith('dinner-planner-0.99.0.apk'));
      expect(await File(installer.installed.single).readAsBytes(), apk);
      expect(File('${dir.path}/dinner-planner-0.1.0.apk').existsSync(), isFalse, reason: 'an older download is cleared away');

      // A file that is not the one published never reaches Android.
      ntfy.downloads['/sampanes/dinner-planner/releases/download/app-v0.99.0/dinner-planner-0.99.0.apk'] = [...apk]..[7] = 0;
      installer.installed.clear();
      await m.update();
      expect(installer.installed, isEmpty);
      expect(m.updateError, 'The download did not finish. Try again on Wi-Fi.');
      expect(dir.listSync().where((f) => f.path.endsWith('.part')), isEmpty);
    });

    testWidgets('a card on Tonight and in Settings offers it', (tester) async {
      final ntfy = FakeNtfy()..releasesJson = releases('0.99.0');
      final model = await startApp(tester, ntfy);
      await model.setMe('blue');
      await tester.pumpAndSettle();
      expect(find.text('Version 0.99.0 is ready'), findsOneWidget);
      expect(find.byKey(const ValueKey('update-go')), findsOneWidget);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const ValueKey('version-line')), 300, scrollable: find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first);
      expect(find.text('Version $appVersion'), findsOneWidget);

      // The background task says so once; tapping that opens Settings.
      bell(model).tap(const NudgeTap(NudgeRef('update')));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsWidgets);
    });
  });

  group('a timer that rings with the screen off', () {
    test('the link from the recipe page sets it, moves it and stops it', () async {
      final clock = Clock(thursday);
      final store = MemoryStore();
      final ntfy = FakeNtfy();
      final m = await phone(ntfy, clock: clock, store: store);
      await m.setMe('blue');
      final end = thursday.add(const Duration(minutes: 8)).millisecondsSinceEpoch;
      final ask = m.timerLink(Uri.parse('dinnerplanner://open/timer?id=4711&end=$end&label=penne%20pasta&slug=beef-chili'))!;
      expect((ask.id, ask.label, ask.end, ask.slug), (4711, 'penne pasta', thursday.add(const Duration(minutes: 8)), 'beef-chili'));
      expect(m.timerLink(Uri.parse('/timer?id=4711&end=$end&label=bake')), isNotNull, reason: 'the form Flutter passes on when the app is running');
      expect(m.timerLink(Uri.parse('/timer?id=1&end=${thursday.add(const Duration(days: 2)).millisecondsSinceEpoch}')), isNull, reason: 'no kitchen timer runs for two days');
      expect(m.timerLink(Uri.parse('/timer?id=1&end=${thursday.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch}')), isNull);
      expect(m.timerLink(Uri.parse('/note?slug=beef-chili')), isNull);

      await m.setTimer(ask);
      final ring = bell(m).scheduled.singleWhere((n) => n.ref?.kind == 'timer');
      expect((ring.when, ring.title, ring.loud), (thursday.add(const Duration(minutes: 8)), 'Timer done: penne pasta', true));

      // It is still set after anything else rebuilds the reminders, and in
      // the background task, which starts from what is kept.
      await m.setMeal(friday, 'beef-chili');
      expect(bell(m).scheduled.where((n) => n.ref?.kind == 'timer'), hasLength(1));
      final background = Session(store: store, client: ntfy.client(), notifier: SilentNotifier());
      await background.load();
      await background.replan(clock.now);
      expect((background.notifier as SilentNotifier).scheduled.where((n) => n.ref?.kind == 'timer'), hasLength(1));

      // "+1 min" on the page sends the same timer again, later.
      await m.setTimer(m.timerLink(Uri.parse('/timer?id=4711&end=${end + 60000}&label=penne%20pasta'))!);
      expect(bell(m).scheduled.singleWhere((n) => n.ref?.kind == 'timer').when, thursday.add(const Duration(minutes: 9)));

      // Tapping the ring goes back to the recipe.
      final opened = <Uri>[];
      final n = await phone(ntfy, opened: opened);
      await n.handleTap(const NudgeTap(NudgeRef('timer', slug: 'beef-chili')));
      expect(opened.single.toString(), contains('#/r/beef-chili'));

      // Cancelled on the page: end 0.
      await m.setTimer(m.timerLink(Uri.parse('/timer?id=4711&end=0'))!);
      expect(bell(m).scheduled.where((n) => n.ref?.kind == 'timer'), isEmpty);

      // One that has rung is forgotten.
      await m.setTimer(ask);
      clock.now = thursday.add(const Duration(minutes: 9));
      await m.session.replan(clock.now);
      expect(m.session.timers, isEmpty);
    });

    testWidgets('the app says when it rings and steps back behind the recipe', (tester) async {
      final installer = FakeInstaller('');
      final model = await startApp(tester, FakeNtfy(), installer: installer);
      await model.setMe('blue');
      final end = thursday.add(const Duration(minutes: 12)).millisecondsSinceEpoch;
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/navigation',
        const JSONMethodCodec().encodeMethodCall(MethodCall('pushRouteInformation', {'location': '/timer?id=7&end=$end&label=bake&slug=beef-chili', 'state': null})),
        (_) {},
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Rings at 4:42 pm'), findsOneWidget);
      expect(find.text('bake'), findsOneWidget);
      expect(installer.steppedBack, 0);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('timer-said')), findsNothing, reason: 'it leaves on its own');
      expect(installer.steppedBack, 1, reason: 'the recipe page is in front again');
      expect(bell(model).scheduled.where((n) => n.ref?.kind == 'timer'), hasLength(1));
    });

    test('the switch in Settings stops the page handing timers over', () async {
      final opened = <Uri>[];
      final m = await phone(FakeNtfy(), opened: opened);
      await m.openRecipe('beef-chili');
      await m.setRingTimers(false);
      await m.openRecipe('beef-chili');
      expect([for (final u in opened) u.query], ['app=1&ring=1', 'app=1']);
    });
  });

  group('tonight on the home screen', () {
    test('the widget is handed a line for each coming day, and redrawn when one changes', () async {
      final store = MemoryStore();
      final installer = FakeInstaller('');
      final clock = Clock(thursday);
      final m = await phone(FakeNtfy(), clock: clock, store: store, installer: installer);
      Map<String, dynamic> days() => (jsonDecode(store.published[glanceKey]!) as Map<String, dynamic>)['days'] as Map<String, dynamic>;
      await m.setMe('blue');
      await m.setName('pink', 'Alex');
      expect(days()[today], {'title': 'Nothing planned', 'sub': 'Tap to pick a dinner'});
      expect(days().keys, hasLength(8));

      final before = installer.redrawn;
      await m.setMeal(today, 'beef-chili');
      await m.setCook(today, 'blue');
      expect(days()[today], {'title': 'Beef Chili', 'sub': 'You cook \u00b7 start by 5:15 pm'}, reason: '35 minutes and ten to spare before 6:00');
      expect(installer.redrawn, greaterThan(before));
      await m.setMeal(friday, 'baked-penne');
      await m.setCook(friday, 'pink');
      expect(days()[friday], {'title': 'Baked Penne', 'sub': 'Alex cooks \u00b7 start by 5:10 pm'}, reason: 'no time of its own, so forty minutes');
      await m.setCook(friday, null);
      expect((days()[friday] as Map)['sub'], 'Nobody is down to cook \u00b7 start by 5:10 pm');
      await m.skipDinner(today, 'leftovers');
      expect(days()[today], {'title': 'Leftovers', 'sub': 'Nobody cooks tonight'});

      // Nothing changed, nothing redrawn.
      final settled = installer.redrawn;
      await m.session.replan(clock.now);
      expect(installer.redrawn, settled);
    });
  });

  group('asking for a recipe from the phone', () {
    test('a shared link is tidied, named once, and read back as a person would say it', () {
      expect(sharedLink('Firecracker Meatballs https://www.hellofresh.com/recipes/firecracker-meatballs-5f6?utm_source=share&utm_medium=app.'), 'https://www.hellofresh.com/recipes/firecracker-meatballs-5f6');
      expect(sharedLink('https://example.com/r?id=7&fbclid=abc'), 'https://example.com/r?id=7');
      expect(sharedLink('just some words'), isNull);
      expect(askId('https://Example.com/R'), askId('https://example.com/r'));
      expect(linkLabel('https://www.hellofresh.com/recipes/firecracker-meatballs-5f6/'), 'hellofresh.com/recipes/firecracker-meatballs-5f6');
    });

    test('it waits on both phones until it is added, and can be taken back', () async {
      final ntfy = FakeNtfy();
      final store = MemoryStore();
      final a = await phone(ntfy, store: store), b = await phone(ntfy);
      await a.startHousehold();
      await b.joinHousehold(a.household!.code);
      await exchange(a, b);
      a.takeAsks();

      // Shared from the browser while the app was shut.
      store.shared.add('Look at this https://www.hellofresh.com/recipes/crispy-parmesan-chicken-5a?utm_campaign=x');
      await a.wake();
      final asks = a.takeAsks();
      expect(asks.whereType<AskTab>().single.tab, 3, reason: 'Settings, where the list of them is');
      expect(asks.whereType<AskSay>().single.text, 'Asked for: hellofresh.com/recipes/crispy-parmesan-chicken-5a. It joins the recipes once it is added at a computer.');
      expect(store.shared, isEmpty, reason: 'taken once');
      await exchange(a, b);
      expect(b.asks.single.link, 'https://www.hellofresh.com/recipes/crispy-parmesan-chicken-5a');
      expect(ntfy.messages.any((m) => m.title == 'A recipe was asked for'), isTrue);

      expect((await b.askFor('https://www.hellofresh.com/recipes/crispy-parmesan-chicken-5a'))!.text, startsWith('Already asked for'));
      expect(await b.askFor('nothing to see'), isNull);
      store.shared.add('no link here');
      await a.wake();
      expect(a.takeAsks().whereType<AskSay>().single.text, startsWith('That has no link in it'));

      await b.dropAsk(b.asks.single.id);
      await exchange(b, a);
      expect(a.asks, isEmpty);
      await a.sleep();
    });

    testWidgets('Settings lists what is waiting', (tester) async {
      final model = await startApp(tester, FakeNtfy());
      await model.setMe('blue');
      await model.askFor('https://www.hellofresh.com/recipes/crispy-parmesan-chicken-5a');
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      final list = find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.byKey(const ValueKey('ask-hint')), 300, scrollable: list);
      expect(find.text('hellofresh.com/recipes/crispy-parmesan-chicken-5a'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('ask-drop-${model.asks.single.id}')));
      await tester.pumpAndSettle();
      expect(model.asks, isEmpty);
      expect(find.text('hellofresh.com/recipes/crispy-parmesan-chicken-5a'), findsNothing);
    });
  });

  group('the week so far', () {
    testWidgets('counts the dinners eaten at home and the ones this phone cooked', (tester) async {
      final clock = Clock(thursday);
      final model = await startApp(tester, FakeNtfy(), clock: clock);
      await model.setMe('blue');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('week-tally')), findsNothing, reason: 'nothing yet this week');

      // Monday and Wednesday were cooked, Tuesday was a night out, and
      // tonight counts once dinner time has come.
      await model.setMeal('2026-11-16', 'beef-chili');
      await model.setCook('2026-11-16', 'blue');
      await model.setMeal('2026-11-18', 'baked-penne');
      await model.setCook('2026-11-18', 'pink');
      await model.skipDinner('2026-11-17', 'out');
      await model.setMeal(today, 'shrimp-tacos');
      await model.setCook(today, 'blue');
      expect(model.weekTally, (cooked: 2, mine: 1));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const ValueKey('week-tally')), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('2 dinners at home this week, 1 cooked by you.'), findsOneWidget);

      clock.now = DateTime(2026, 11, 19, 19);
      expect(model.weekTally, (cooked: 3, mine: 2));
      // Sunday is the last day of the week that started on Monday.
      clock.now = DateTime(2026, 11, 23, 9);
      expect(model.weekTally, (cooked: 0, mine: 0), reason: 'a new week');
    });
  });
}

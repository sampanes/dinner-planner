import 'package:dinner_planner/app_model.dart';
import 'package:dinner_planner/data/session.dart';
import 'package:dinner_planner/data/store.dart';
import 'package:dinner_planner/main.dart';
import 'package:dinner_planner/notify/notifier.dart';
import 'package:dinner_planner/ui/settings.dart';
import 'package:dinner_planner/ui/tonight.dart';
import 'package:dinner_planner/ui/week.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ntfy.dart';

/// A Thursday afternoon, before the "start cooking" reminder.
final DateTime thursday = DateTime(2026, 11, 19, 16, 30);

Future<AppModel> startApp(WidgetTester tester, FakeNtfy ntfy, {Store? store}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  final model = AppModel(Session(store: store ?? MemoryStore(), client: ntfy.client(), notifier: SilentNotifier()), clock: () => thursday);
  await model.start();
  await tester.pumpWidget(DinnerApp(model: model));
  await tester.pumpAndSettle();
  // Stops the app's timers before the test ends.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  return model;
}

void main() {
  testWidgets('first run: say who you are, pick dinner, take the night', (tester) async {
    final ntfy = FakeNtfy();
    final model = await startApp(tester, ntfy);
    final notifier = model.session.notifier as SilentNotifier;

    expect(find.text('Whose phone is this?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('me-blue')));
    await tester.pumpAndSettle();
    expect(find.text('Who cooks tonight?'), findsOneWidget);
    expect(find.text('Nothing is planned for tonight'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pick-tonight')));
    await tester.pumpAndSettle();
    expect(find.text('Shrimp Tacos'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ground beef');
    await tester.pumpAndSettle();
    expect(find.text('Shrimp Tacos'), findsNothing, reason: 'search looks at ingredients too');
    await tester.tap(find.byKey(const ValueKey('pick-beef-chili')));
    await tester.pumpAndSettle();
    expect(find.text('Beef Chili'), findsOneWidget);
    expect(find.byKey(const ValueKey('open-kitchen')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cook-2026-11-19-blue')));
    await tester.pumpAndSettle();
    expect(find.text("You're cooking tonight"), findsOneWidget);
    expect(notifier.scheduled.single.when, DateTime(2026, 11, 19, 17));
    expect(notifier.scheduled.single.body, 'Beef Chili. Tap to open it.');

    // Tapping the chosen name again hands the night back.
    await tester.tap(find.byKey(const ValueKey('cook-2026-11-19-blue')));
    await tester.pumpAndSettle();
    expect(find.text('Who cooks tonight?'), findsOneWidget);
    expect(notifier.scheduled, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('week: fourteen days, fill from the kitchen plan, assign a cook', (tester) async {
    final ntfy = FakeNtfy();
    final model = await startApp(tester, ntfy);
    await model.setMe('pink');
    await model.setMeal('2026-11-19', 'beef-chili');
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fill-week')));
    await tester.pumpAndSettle();
    expect(find.text('Added 1 dinner from the kitchen plan.'), findsOneWidget, reason: 'chili is already planned, so only the penne is new');
    expect(model.plan.meal('2026-11-20'), 'baked-penne');

    await tester.tap(find.byKey(const ValueKey('cook-2026-11-20-pink')));
    await tester.pumpAndSettle();
    expect(model.plan.cook('2026-11-20'), 'pink');
    final notifier = model.session.notifier as SilentNotifier;
    expect([for (final n in notifier.scheduled) n.title], ['You cook tomorrow: Baked Penne', "You're cooking tonight", 'Time to start dinner']);

    final list = find.descendant(of: find.byType(WeekScreen), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byKey(const ValueKey('day-2026-12-02')), 300, scrollable: list);
    expect(find.byKey(const ValueKey('day-2026-12-02')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sharing: one phone starts, the other joins with the code and sees the plan', (tester) async {
    final ntfy = FakeNtfy();
    final his = await startApp(tester, ntfy);
    await his.setMe('blue');
    await his.setName('blue', 'Sam');
    await his.setCook('2026-11-20', 'blue');
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('share-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('share-start')));
    await tester.pumpAndSettle();
    expect(find.text('Waiting for the other phone to join.'), findsOneWidget);
    final code = tester.widget<SelectableText>(find.byKey(const ValueKey('share-code'))).data!;
    expect(ntfy.messages, isNotEmpty, reason: 'what was planned before sharing is sent once sharing starts');

    final hers = AppModel(Session(store: MemoryStore(), client: ntfy.client(), notifier: SilentNotifier()), clock: () => thursday);
    await tester.runAsync(() async {
      await hers.start();
      expect(await hers.joinHousehold('not a code'), isFalse);
      expect(await hers.joinHousehold(code), isTrue);
      await his.sync();
    });
    expect(hers.plan.name('blue'), 'Sam');
    expect(hers.plan.cook('2026-11-20'), 'blue');
    await tester.pumpAndSettle();
    expect(find.text('Both phones show the same plan.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('start here: the steps tick themselves, lead to their tab, and can be skipped', (tester) async {
    final ntfy = FakeNtfy();
    final store = MemoryStore();
    final model = await startApp(tester, ntfy, store: store);
    final card = find.byKey(const ValueKey('start-here'));
    Future<void> go(String tab) async {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
    }

    expect(card, findsNothing, reason: 'first it asks whose phone this is');
    await model.setMe('blue');
    await tester.pumpAndSettle();
    expect(find.text('0 of 5'), findsOneWidget);
    expect(find.text('The cook gets the reminders, and what it needs goes on the list.'), findsOneWidget, reason: 'the next step says why');
    expect(find.text('The list sorts itself for each one.'), findsNothing, reason: 'later steps stay one line');

    await tester.tap(find.byKey(const ValueKey('start-plan')));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget, reason: 'the step opens the Week tab');

    await model.setMeal('2026-11-20', 'beef-chili');
    expect(model.startDone, isEmpty, reason: 'nobody cooks it yet');
    await model.setCook('2026-11-20', 'blue');
    await model.addStores(['Costco']);
    expect(model.startDone, {StartStep.plan, StartStep.stores});
    await go('Tonight');
    expect(find.text('2 of 5'), findsOneWidget);
    expect(find.text('Say once what it is. After that, scanning it ticks it off the list.'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('start-share')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-share')));
    await tester.pumpAndSettle();
    expect(find.text('The two of you'), findsOneWidget, reason: 'the step opens Settings');
    expect(find.byKey(const ValueKey('start-show')), findsNothing);

    await go('Tonight');
    await tester.ensureVisible(find.byKey(const ValueKey('start-skip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-skip')));
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    final again = Session(store: store, client: ntfy.client(), notifier: SilentNotifier());
    await again.load();
    expect(again.startHidden, isTrue, reason: 'skipped stays skipped after a restart');
    // Long enough for the "Hidden" message to leave the bottom of the screen.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await go('Settings');
    final list = find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byKey(const ValueKey('start-show')), 300, scrollable: list);
    await tester.tap(find.byKey(const ValueKey('start-show')));
    await tester.pumpAndSettle();
    await go('Tonight');
    expect(card, findsOneWidget);

    // The rest of the steps, done: the card has nothing left to say.
    await model.saveProduct('ground-beef', code: '012345000019');
    await model.shopAt('costco');
    await model.setGot(model.shopping.first, true);
    await model.startHousehold();
    await tester.pumpAndSettle();
    expect(model.startDone, StartStep.values.toSet());
    expect(card, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notes: write one on the dinner tonight, change it, delete it', (tester) async {
    final ntfy = FakeNtfy();
    final model = await startApp(tester, ntfy);
    await model.setMe('blue');
    await model.setMeal('2026-11-19', 'beef-chili');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('note-add-beef-chili')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('note-field')), '  Add parmesan as a step  ');
    await tester.tap(find.byKey(const ValueKey('note-save')));
    await tester.pumpAndSettle();
    expect(model.plan.note('beef-chili'), 'Add parmesan as a step');
    expect(find.text('Add parmesan as a step'), findsOneWidget);

    // The same note shows in the sheet of what it needs, and can be changed there.
    await tester.tap(find.byKey(const ValueKey('needs-tonight')));
    await tester.pumpAndSettle();
    expect(find.text('Add parmesan as a step'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('note-beef-chili')).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('note-field')), 'x' * 500);
    await tester.tap(find.byKey(const ValueKey('note-save')));
    await tester.pumpAndSettle();
    expect(model.plan.note('beef-chili')!.length, 400, reason: 'kept to what one shared value holds');

    await tester.tap(find.byKey(const ValueKey('note-beef-chili')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-clear')));
    await tester.pumpAndSettle();
    expect(model.plan.note('beef-chili'), isNull);
    expect(find.byKey(const ValueKey('note-add-beef-chili')), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings fit a small phone with large text', (tester) async {
    final ntfy = FakeNtfy();
    final model = await startApp(tester, ntfy);
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await model.setMe('blue');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('start-share')), 200, scrollable: find.descendant(of: find.byType(TonightScreen), matching: find.byType(Scrollable)).first);
    expect(tester.takeException(), isNull, reason: 'the start card overflows');
    await model.setMeal('2026-11-19', 'beef-chili');
    await model.setCook('2026-11-19', 'blue');
    await model.startHousehold();
    await model.setBuy('ground-beef', 'The big tray of 88/12 from the warehouse store');
    for (final tab in ['Tonight', 'Week', 'Shop', 'Settings']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$tab overflows');
    }
  });
}

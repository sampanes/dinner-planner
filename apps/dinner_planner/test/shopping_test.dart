import 'package:dinner_planner/app_model.dart';
import 'package:dinner_planner/core/shopping.dart';
import 'package:dinner_planner/data/instacart.dart';
import 'package:dinner_planner/data/recipes.dart';
import 'package:dinner_planner/data/session.dart';
import 'package:dinner_planner/data/store.dart';
import 'package:dinner_planner/main.dart';
import 'package:dinner_planner/notify/notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ntfy.dart';

final DateTime thursday = DateTime(2026, 11, 19, 16, 30);

Future<AppModel> phone(FakeNtfy ntfy) async {
  final model = AppModel(Session(store: MemoryStore(), client: ntfy.client(), notifier: SilentNotifier()), clock: () => thursday);
  await model.start();
  await model.refreshRecipes();
  return model;
}

/// A write starts its own send without waiting for it; this lets that finish
/// and then passes messages both ways.
Future<void> exchange(AppModel a, AppModel b) async {
  for (var i = 0; i < 2; i++) {
    await pumpEventQueue();
    await a.sync();
    await b.sync();
  }
}

String show(List<ShopLine> lines) => [for (final l in lines) l.loose ? l.name : '${l.amountText} ${l.name}'].join('; ');

void main() {
  group('amounts', () {
    test('are read as a number and a unit', () {
      ({double? n, String unit}) read(String s) => (n: parseAmount(s).number, unit: parseAmount(s).unit);
      expect(read('2'), (n: 2.0, unit: ''));
      expect(read('3 unit'), (n: 3.0, unit: ''));
      expect(read('1/4 ounce'), (n: 0.25, unit: 'oz'));
      expect(read('7.5 oz'), (n: 7.5, unit: 'oz'));
      expect(read('1 1/2 cup'), (n: 1.5, unit: 'cup'));
      expect(read('9 tablespoon'), (n: 9.0, unit: 'tbsp'));
      expect(read('1 tsp, grated'), (n: 1.0, unit: 'tsp'));
      expect(read('2 thumb'), (n: 2.0, unit: 'thumb'));
      expect(read('to taste'), (n: null, unit: ''));
      expect(read(''), (n: null, unit: ''));
      expect(read('1/0 cup'), (n: null, unit: ''));
    });

    test('are written the way a person would', () {
      expect(formatAmount(3, ''), '3');
      expect(formatAmount(0.5, 'cup'), '1/2 cup');
      expect(formatAmount(1.5, 'cup'), '1 1/2 cups');
      expect(formatAmount(13.76, 'oz'), '13.76 oz');
      expect(formatAmount(0.25 + 0.25 + 0.25 + 0.25, 'oz'), '1 oz');
      expect(formatAmount(1 / 3 + 1 / 3, 'cup'), '2/3 cup');
      expect(formatAmount(4, 'clove'), '4 cloves');
    });
  });

  test('the same ingredient in two dinners becomes one line', () {
    final recipes = {for (final r in parseRecipes(FakeNtfy().recipesJson)) r.slug: r};
    final lines = shoppingList([
      ShopDinner(day: '2026-11-20', slug: 'baked-penne', ingredients: recipes['baked-penne']!.ingredients),
      ShopDinner(day: '2026-11-19', slug: 'beef-chili', ingredients: recipes['beef-chili']!.ingredients),
    ]);
    expect(show(lines), '1 lb + 10 oz ground beef; 3 onion; 6 oz penne; salt');
    final onion = lines.firstWhere((l) => l.id == 'onion');
    expect([for (final u in onion.uses) '${u.day} ${u.slug}'], ['2026-11-19 beef-chili', '2026-11-20 baked-penne']);
    expect(lines.firstWhere((l) => l.id == 'salt').loose, isTrue);
  });

  test('a recipe list saved by an older version still reads', () {
    final r = Recipe.fromJson({'slug': 'x', 'name': 'X', 'ingredients': ['2 onion']})!;
    expect(r.ingredients.single.text, '2 onion');
    expect(shoppingList([ShopDinner(day: '2026-11-19', slug: 'x', ingredients: r.ingredients)]).single.loose, isTrue);
  });

  test('ticks and real names are shared, and a later dinner asks only for what is missing', () async {
    final ntfy = FakeNtfy();
    final his = await phone(ntfy), hers = await phone(ntfy);
    await his.startHousehold();
    await hers.joinHousehold(his.household!.code);
    await his.setMeal('2026-11-19', 'beef-chili');
    await exchange(his, hers);
    expect(show(hers.shopping), '1 lb ground beef; 2 onion; salt');

    // She is in the store.
    await hers.setGot(hers.shopping.firstWhere((l) => l.id == 'onion'), true);
    await hers.setBuy('ground-beef', ' Store brand 88/12, the 1 lb tray ');
    await exchange(hers, his);
    expect(show(his.shopping), '1 lb ground beef; salt');
    expect(show(his.shoppingGot), '2 onion');
    expect(his.buy('ground-beef'), 'Store brand 88/12, the 1 lb tray');
    expect(his.shoppingText(), '- 1 lb Store brand 88/12, the 1 lb tray (ground beef)\nCheck you have: salt');

    // A dinner planned afterwards needs one more onion, not three.
    await his.setMeal('2026-11-21', 'baked-penne');
    expect(show(his.shopping), '1 lb + 10 oz ground beef; 1 onion; 6 oz penne; salt');
    expect(show(his.shoppingGot), '2 onion');

    // Un-ticking puts it back.
    await his.setGot(his.shoppingGot.single, false);
    expect(show(his.shopping), contains('3 onion'));
    await his.setBuy('ground-beef', '');
    expect(his.buy('ground-beef'), isNull);
    expect((his.session.notifier as SilentNotifier).shown, isEmpty, reason: 'shopping changes raise no notice');
    await exchange(his, hers);
    expect(hers.buy('ground-beef'), isNull);
    expect((hers.session.notifier as SilentNotifier).shown, isEmpty);
    expect([for (final m in ntfy.messages) m.title], contains('Shopping list updated'));
  });

  group('Instacart', () {
    Future<AppModel> planned(FakeNtfy ntfy) async {
      final m = await phone(ntfy);
      await m.setMeal('2026-11-19', 'beef-chili');
      await m.setMeal('2026-11-20', 'baked-penne');
      return m;
    }

    test('gets what is still to buy, by the names the household uses', () async {
      final ntfy = FakeNtfy()..instacartKey = 'key-1';
      final m = await planned(ntfy);
      await m.setInstacartKey(' key-1 ');
      await m.setBuy('penne', 'Whole wheat penne');
      await m.setGot(m.shopping.firstWhere((l) => l.id == 'onion'), true);
      expect('${await m.instacartLink()}', 'https://www.instacart.com/store/shopping_lists/1');
      final sent = ntfy.instacartLists.single;
      expect(sent['link_type'], 'shopping_list');
      expect(sent['line_items'], [
        {
          'name': 'ground beef',
          'display_text': '1 lb + 10 oz ground beef',
          'line_item_measurements': [
            {'quantity': 1.0, 'unit': 'pound'},
            {'quantity': 10.0, 'unit': 'ounce'},
          ],
        },
        {
          'name': 'Whole wheat penne',
          'display_text': '6 oz penne',
          'line_item_measurements': [
            {'quantity': 6.0, 'unit': 'ounce'},
          ],
        },
      ]);
    });

    test('a test key is tried on the test address', () async {
      final ntfy = FakeNtfy()
        ..instacartKey = 'dev-key'
        ..instacartHost = 'connect.dev.instacart.tools';
      final m = await planned(ntfy);
      await m.setInstacartKey('dev-key');
      await m.instacartLink();
      expect(ntfy.instacartLists, hasLength(1));
    });

    test('a refused key, no key and an empty list each say so', () async {
      final ntfy = FakeNtfy()..instacartKey = 'right';
      final m = await planned(ntfy);
      await expectLater(m.instacartLink(), throwsA(isA<InstacartError>().having((e) => e.message, 'message', contains('Settings'))));
      await m.setInstacartKey('wrong');
      await expectLater(m.instacartLink(), throwsA(isA<InstacartError>().having((e) => e.message, 'message', 'Instacart did not accept the key.')));
      await m.setInstacartKey('right');
      for (final l in m.shopping) {
        await m.setGot(l, true);
      }
      await expectLater(m.instacartLink(), throwsA(isA<InstacartError>().having((e) => e.message, 'message', 'Nothing is left to get.')));
    });
  });

  testWidgets('shop tab: tick a line, name what you buy, copy the list', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final ntfy = FakeNtfy();
    final model = AppModel(Session(store: MemoryStore(), client: ntfy.client(), notifier: SilentNotifier()), clock: () => thursday);
    await model.start();
    await tester.pumpWidget(DinnerApp(model: model));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await model.setMe('blue');
    await tester.tap(find.text('Shop'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pick dinners for the week'), findsOneWidget);
    expect(find.byKey(const ValueKey('shop-instacart')), findsNothing);

    await model.setMeal('2026-11-19', 'beef-chili');
    await model.setMeal('2026-11-20', 'baked-penne');
    await tester.pumpAndSettle();
    expect(find.textContaining('For 2 dinners, through Friday, November 20.'), findsOneWidget);
    expect(find.text('3  Onion'), findsOneWidget);
    expect(find.text('Check you have'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('shop-onion')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shop-onion')), findsNothing);
    expect(find.byKey(const ValueKey('got-onion')), findsOneWidget);
    expect(find.text('Got'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('shop-edit-ground-beef')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('shop-buy-text')), 'Store brand 88/12');
    await tester.tap(find.byKey(const ValueKey('shop-buy-save')));
    await tester.pumpAndSettle();
    expect(find.text('1 lb + 10 oz  Store brand 88/12'), findsOneWidget);
    expect(find.text('ground beef · Beef Chili, Baked Penne'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('shop-copy')));
    await tester.pumpAndSettle();
    expect(copied, '- 1 lb + 10 oz Store brand 88/12 (ground beef)\n- 6 oz penne\nCheck you have: salt');
    expect(tester.takeException(), isNull);
  });
}

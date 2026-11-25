import 'dart:io';

import 'package:dinner_planner/app_model.dart';
import 'package:dinner_planner/core/shopping.dart';
import 'package:dinner_planner/core/store_order.dart';
import 'package:dinner_planner/data/recipes.dart';
import 'package:dinner_planner/data/session.dart';
import 'package:dinner_planner/data/store.dart';
import 'package:dinner_planner/main.dart';
import 'package:dinner_planner/notify/notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ntfy.dart';

final DateTime thursday = DateTime(2026, 11, 19, 16, 30);

/// A write starts its own send without waiting for it; this lets that finish
/// and then passes messages both ways.
Future<void> exchange(AppModel a, AppModel b) async {
  for (var i = 0; i < 2; i++) {
    await pumpEventQueue();
    await a.sync();
    await b.sync();
  }
}

String order(AppModel m) => [for (final g in m.shoppingGroups) '${g.section}: ${g.lines.map((l) => l.id).join(', ')}'].join(' | ');

void main() {
  group('sections', () {
    test('every ingredient the recipe site has today gets one', () {
      final recipes = parseRecipes(File('../../data/runtime/recipes.runtime.json').readAsStringSync());
      final ids = {for (final r in recipes) for (final i in r.ingredients) i.id};
      expect(ids.length, greaterThan(100));
      expect([for (final id in ids) if (guessSection(id) == 'other') id], isEmpty);
    });

    test('the narrow case beats the broad one', () {
      const want = {
        'onion': 'produce', 'green-beans': 'produce', 'black-beans': 'canned', 'garlic': 'produce', 'garlic-powder': 'spices',
        'garlic-herb-butter': 'dairy', 'pepper': 'spices', 'bell-pepper': 'produce', 'pepper-jack-cheese': 'dairy',
        'smoky-red-pepper-crema': 'dairy', 'chili-powder': 'spices', 'chili-pepper': 'produce', 'sweet-thai-chili-sauce': 'sauces',
        'flour': 'spices', 'flour-tortillas': 'bakery', 'blue-corn-tortilla-chips': 'snacks', 'corn': 'produce',
        'tomato': 'produce', 'crushed-tomatoes': 'canned', 'tomato-paste': 'canned', 'basil-paste': 'produce',
        'mushroom-ravioli': 'dairy', 'penne-pasta': 'dry', 'jasmine-rice': 'dry', 'chicken-thighs': 'meat', 'stock-concentrate': 'canned',
        'hash-brown-shredded-potatoes': 'frozen', 'potatoes': 'produce', 'peas': 'frozen', 'cream-sauce-base': 'dairy', 'soy-sauce': 'sauces',
        'Ground Beef': 'meat', 'dragon fruit jelly': 'other',
      };
      expect({for (final id in want.keys) id: guessSection(id)}, want);
    });
  });

  group('the walk through a store', () {
    test('is built from which line was ticked after which', () {
      expect(learnWalk({}, 'a', null), {'a': 0.0});
      expect(learnWalk({'a': 0}, 'b', 'a'), {'b': 1.0});
      expect(learnWalk({'a': 0, 'b': 1}, 'c', null), {'c': -1.0}, reason: 'new, and first into the cart');
      expect(learnWalk({'a': 0, 'b': 1, 'c': 2}, 'd', 'a'), {'d': 0.5});
      expect(learnWalk({'a': 0, 'b': 1, 'c': 2}, 'c', 'a'), isEmpty, reason: 'already further along');
      expect(learnWalk({'a': 0, 'b': 1, 'c': 2}, 'a', 'c'), {'a': 3.0}, reason: 'the latest trip wins');
      expect(learnWalk({'a': 0, 'b': 1, 'c': 2}, 'b', null), isEmpty);
      expect(learnWalk({'a': 0, 'b': 1}, 'b', 'never-placed'), isEmpty);
      expect(learnWalk({'a': 0, 'b': 1}, 'a', 'a'), isEmpty);
    });

    test('is numbered afresh when there is no room left between two lines', () {
      expect(learnWalk({'a': 0, 'b': 0.0000005, 'z': 9}, 'c', 'a'), {'c': 1.0, 'b': 2.0, 'z': 3.0});
    });

    test('orders the sections it has met, then the rest in the usual order', () {
      final lines = [ShopLine('onion', 'onion'), ShopLine('lime', 'lime'), ShopLine('apple', 'apple'), ShopLine('milk', 'milk'), ShopLine('penne', 'penne'), ShopLine('bacon', 'bacon')];
      String show(Map<String, double> walk) => [for (final g in arrange(lines, sectionOf: guessSection, walk: walk)) '${g.section}: ${g.lines.map((l) => l.id).join(', ')}'].join(' | ');
      expect(show({}), 'produce: apple, lime, onion | meat: bacon | dairy: milk | dry: penne');
      // Butter is not on today's list, but it is where the dairy is.
      expect(show({'lime': 5, 'butter': 1}), 'dairy: milk | produce: lime, apple, onion | meat: bacon | dry: penne');
    });
  });

  test('packets are counted when the recipe and the packet measure the same way', () {
    expect(packsNeeded({'oz': 26}, '16 oz'), 2);
    expect(packsNeeded({'oz': 16}, '16 oz'), 1);
    expect(packsNeeded({'lb': 1, 'oz': 10}, '1 lb'), 2);
    expect(packsNeeded({'oz': 32}, '454 g'), 2);
    expect(packsNeeded({'oz': 13.76}, '14.5 oz/411 g'), 1);
    expect(packsNeeded({'': 8}, '6 ct'), 2);
    expect(packsNeeded({'tbsp': 21}, '16 fl oz'), 1);
    expect(packsNeeded({'tbsp': 40}, '16 FL OZ (1 PT) 473 mL'), 2);
    expect(packsNeeded({'oz': 20}, '12 fl oz'), 2, reason: 'a recipe says oz for liquids too');
    expect(packsNeeded({'cup': 2}, '16 oz'), isNull, reason: 'cups of cheese against a bag sold by weight');
    expect(packsNeeded({'': 2, 'oz': 26.8}, '15 oz'), isNull);
    expect(packsNeeded({'oz': 8}, 'the big one'), isNull);
    expect(packsNeeded({'oz': 8}, ''), isNull);
    expect(packsNeeded({}, '16 oz'), isNull);
  });

  test('a store is learned from the ticks made in it, and both phones get the order', () async {
    final ntfy = FakeNtfy();
    var t = thursday;
    Future<AppModel> phone() async {
      final model = AppModel(Session(store: MemoryStore(), client: ntfy.client(), notifier: SilentNotifier()), clock: () => t);
      await model.start();
      await model.refreshRecipes();
      return model;
    }

    final his = await phone(), hers = await phone();
    await his.startHousehold();
    await hers.joinHousehold(his.household!.code);
    await his.setMeal('2026-11-19', 'beef-chili');
    await his.setMeal('2026-11-20', 'baked-penne');
    await his.addStores(["Trader Joe's", 'Costco', '  ', "trader joe's"]);
    await exchange(his, hers);
    expect([for (final s in hers.stores) '${s.id}=${s.name}'], ['costco=Costco', "trader-joe-s=Trader Joe's"]);
    expect(order(his), 'produce: onion | meat: ground-beef | dry: penne');

    Future<void> tick(AppModel m, String id) => m.setGot(m.shopping.firstWhere((l) => l.id == id), true);
    Future<void> putBack(AppModel m) async {
      for (final l in m.shoppingGot) {
        await m.setGot(l, false);
      }
    }

    // At home nothing is learned.
    await tick(his, 'penne');
    await putBack(his);
    expect(his.session.core.entries.where((e) => e.key.startsWith('pos/')), isEmpty);

    // He walks Trader Joe's: pasta aisle, then the meat, then produce on the way out.
    await his.shopAt('trader-joe-s');
    for (final id in ['penne', 'ground-beef', 'onion']) {
      t = t.add(const Duration(minutes: 4));
      await tick(his, id);
    }
    await putBack(his);
    expect(order(his), 'dry: penne | meat: ground-beef | produce: onion');

    await exchange(his, hers);
    expect(his.inStep && hers.inStep, isTrue, reason: 'the places are numbers; both phones must write them the same way');
    expect(order(hers), 'produce: onion | meat: ground-beef | dry: penne', reason: 'she is not in a store');
    await hers.shopAt('trader-joe-s');
    expect(order(hers), 'dry: penne | meat: ground-beef | produce: onion');
    await hers.shopAt('costco');
    expect(order(hers), 'produce: onion | meat: ground-beef | dry: penne', reason: 'another store, another walk');

    // Two hours after the last tick the phone no longer counts as in the store.
    t = t.add(const Duration(hours: 2, minutes: 1));
    expect(his.shoppingAt, isNull);
    expect(order(his), 'produce: onion | meat: ground-beef | dry: penne');

    // Next week he goes round the other way; the latest trip wins.
    await his.shopAt('trader-joe-s');
    await tick(his, 'onion');
    await tick(his, 'penne');
    await putBack(his);
    expect(order(his), 'meat: ground-beef | produce: onion | dry: penne');

    // The shop he is in is remembered across a restart of the app.
    final again = AppModel(Session(store: his.session.store, client: ntfy.client(), notifier: SilentNotifier()), clock: () => t);
    await again.start();
    expect(again.shoppingAt, 'trader-joe-s');

    await his.removeStore('trader-joe-s');
    expect(his.shoppingAt, isNull);
    await exchange(his, hers);
    expect([for (final s in hers.stores) s.name], ['Costco']);
    expect((hers.session.notifier as SilentNotifier).shown, isEmpty, reason: 'shopping changes raise no notice');
    expect({for (final m in ntfy.messages) m.title}.difference({'Dinner planner', 'Dinner plan updated', 'Today: Beef Chili', 'Tomorrow: Baked Penne'}), {'Shopping list updated'});
  });

  test('what you buy: the size, the section and where it is are shared, part by part', () async {
    final ntfy = FakeNtfy();
    Future<AppModel> phone() async {
      final model = AppModel(Session(store: MemoryStore(), client: ntfy.client(), notifier: SilentNotifier()), clock: () => thursday);
      await model.start();
      await model.refreshRecipes();
      return model;
    }

    final his = await phone(), hers = await phone();
    await his.startHousehold();
    await hers.joinHousehold(his.household!.code);
    await his.setMeal('2026-11-19', 'beef-chili');
    await his.setMeal('2026-11-20', 'baked-penne');
    await his.addStores(['Costco']);
    await his.saveProduct('ground-beef', buy: ' Store brand 88/12 ', size: '1 lb', section: 'meat', at: {'costco': 'Back wall'});
    expect(his.session.core.value(sectionKey('ground-beef')), isNull, reason: 'the guess already says meat');
    await exchange(his, hers);
    final beef = hers.shopping.firstWhere((l) => l.id == 'ground-beef');
    expect((hers.buy('ground-beef'), hers.size('ground-beef'), hers.packs(beef), hers.at('costco', 'ground-beef')), ('Store brand 88/12', '1 lb', 2, 'Back wall'));

    // She moves it to the deli and leaves the rest alone; he changes the size meanwhile.
    await hers.saveProduct('ground-beef', section: 'deli');
    await his.saveProduct('ground-beef', size: '3 lb');
    await exchange(his, hers);
    for (final m in [his, hers]) {
      expect((m.section('ground-beef'), m.size('ground-beef'), m.buy('ground-beef')), ('deli', '3 lb', 'Store brand 88/12'));
    }
    expect(order(his), 'produce: onion | deli: ground-beef | dry: penne');
    await his.saveProduct('ground-beef', size: '', at: {'costco': ''});
    expect((his.size('ground-beef'), his.at('costco', 'ground-beef'), his.packs(beef)), (null, null, null));
  });

  testWidgets('shop tab: add stores, shop in one, fill in what you buy', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final model = AppModel(Session(store: MemoryStore(), client: FakeNtfy().client(), notifier: SilentNotifier()), clock: () => thursday);
    await model.start();
    await tester.pumpWidget(DinnerApp(model: model));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
    Future<void> tap(String key) async {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
    }

    double top(String key) => tester.getTopLeft(find.byKey(ValueKey(key))).dy;

    await model.setMe('blue');
    await model.setMeal('2026-11-19', 'beef-chili');
    await model.setMeal('2026-11-20', 'baked-penne');
    await tester.tap(find.text('Shop'));
    await tester.pumpAndSettle();
    expect(find.text('Produce'), findsOneWidget);
    expect(find.text('Meat & seafood'), findsOneWidget);
    expect(top('shop-onion'), lessThan(top('shop-penne')));

    await tap('store-add');
    await tap('store-idea-costco');
    await tester.enterText(find.byKey(const ValueKey('store-name')), 'Corner market');
    await tap('store-save');
    expect([for (final s in model.stores) s.name], ['Corner market', 'Costco']);
    expect(find.textContaining('In a store?'), findsOneWidget);

    await tap('store-costco');
    expect(find.textContaining('In the order you walk Costco.'), findsOneWidget);
    await tap('shop-penne');
    await tap('shop-onion');
    await tap('got-onion');
    await tap('got-penne');
    expect(top('shop-penne'), lessThan(top('shop-onion')), reason: 'the order he ticked them in');
    expect(top('shop-onion'), lessThan(top('shop-ground-beef')), reason: 'a section the walk has not met comes after');

    await tap('shop-edit-ground-beef');
    expect(find.text('What do you buy for ground beef?'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('shop-buy-text')), 'Store brand 88/12');
    await tester.enterText(find.byKey(const ValueKey('shop-size-text')), '1 lb');
    await tester.enterText(find.byKey(const ValueKey('shop-at-costco')), 'Back wall');
    await tap('shop-section');
    await tester.tap(find.text('Deli').last);
    await tester.pumpAndSettle();
    await tap('shop-buy-save');
    expect(find.text('2 × 1 lb  Store brand 88/12'), findsOneWidget);
    expect(find.text('ground beef · 1 lb + 10 oz · Back wall · Beef Chili, Baked Penne'), findsOneWidget);
    expect(find.text('Deli'), findsOneWidget);
    expect(model.section('ground-beef'), 'deli');
    expect(tester.takeException(), isNull);
  });
}

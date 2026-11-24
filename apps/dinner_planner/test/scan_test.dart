import 'package:dinner_planner/app_model.dart';
import 'package:dinner_planner/data/products.dart';
import 'package:dinner_planner/data/session.dart';
import 'package:dinner_planner/data/store.dart';
import 'package:dinner_planner/main.dart';
import 'package:dinner_planner/notify/notifier.dart';
import 'package:dinner_planner/ui/scan.dart';
import 'package:dinner_planner/ui/shop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ntfy.dart';

final DateTime thursday = DateTime(2026, 11, 19, 16, 30);

// Made-up barcodes and products.
const String penneCode = '012345000019';
const String beefCode = '012345000026';
const String nobodyKnows = '099999000011';

FakeNtfy lists() => FakeNtfy()
  ..openFoodFacts[penneCode] = {'product_name': 'Penne Rigate', 'brands': 'Pasta Co, Somebody Else', 'quantity': '30 g'}
  ..usda[penneCode] = {'gtinUpc': '0012345000019', 'description': 'PASTA CO, PENNE RIGATE, PENNE RIGATE', 'brandName': 'PASTA CO', 'brandOwner': 'Pasta Company Inc.', 'packageWeight': '16 oz/1 lbs/454 g'}
  ..openFoodFacts[beefCode] = {'product_name': 'Ground Beef 88% Lean', 'brands': 'Ranch Hand', 'quantity': '1 lb'};

void main() {
  test('a barcode is put in one form however the scanner padded it', () {
    expect(canonicalCode('012345000019'), '012345000019');
    expect(canonicalCode('0012345000019'), '012345000019', reason: 'the same packet read as thirteen digits');
    expect(canonicalCode(' 12345000019 '), '012345000019');
    expect(canonicalCode('5012345678900'), '5012345678900', reason: 'a European code keeps its thirteen');
    expect(canonicalCode('96385074'), '000096385074');
    expect(canonicalCode('212345604997'), '212345000000', reason: 'weighed in the store: the price part is dropped');
    expect(canonicalCode('212345612344'), '212345000000');
    expect(canonicalCode('https://example.com/1234567890'), isNull);
    expect(canonicalCode('1234'), isNull);
    expect(canonicalCode('00000000'), isNull);
    expect(canonicalCode(''), isNull);
  });

  group('looking a barcode up', () {
    test('takes the name from one list and the brand and size from the other', () async {
      final ntfy = lists();
      final p = (await lookUpProduct(ntfy.client(), penneCode, usdaKey: 'my-key'))!;
      expect((p.name, p.brand, p.size, p.shelfName), ('Penne Rigate', 'Pasta Co', '16 oz', 'Pasta Co Penne Rigate'));
      expect(ntfy.lookups, unorderedEquals(['off $penneCode', 'usda $penneCode my-key']));
    });

    test('makes do with whichever list answers', () async {
      final ntfy = lists();
      final beef = (await lookUpProduct(ntfy.client(), beefCode))!;
      expect((beef.shelfName, beef.size), ('Ranch Hand Ground Beef 88% Lean', '1 lb'));
      expect(ntfy.lookups, contains('usda $beefCode DEMO_KEY'), reason: 'no key: the shared demo key');

      ntfy.openFoodFacts.remove(penneCode);
      final penne = (await lookUpProduct(ntfy.client(), penneCode))!;
      expect((penne.shelfName, penne.size), ('Pasta Co Penne Rigate', '16 oz'), reason: 'shouting and repeats tidied');

      // Out of lookups for the hour.
      ntfy.usdaStatus = 429;
      expect(await lookUpProduct(ntfy.client(), penneCode), isNull);
      expect((await lookUpProduct(ntfy.client(), beefCode))!.shelfName, 'Ranch Hand Ground Beef 88% Lean');
    });

    test('says nothing rather than guess', () async {
      final ntfy = lists();
      expect(await lookUpProduct(ntfy.client(), nobodyKnows), isNull);
      // The search is by words: a different product that mentions the number is not it.
      ntfy.usda[nobodyKnows] = {'gtinUpc': '077777000011', 'description': 'SOMETHING ELSE', 'packageWeight': '1 lb'};
      expect(await lookUpProduct(ntfy.client(), nobodyKnows), isNull);
      ntfy.down = true;
      expect(await lookUpProduct(ntfy.client(), penneCode), isNull);
      ntfy
        ..down = false
        ..lookups.clear();
      expect(await lookUpProduct(ntfy.client(), '212345000000'), isNull);
      expect(ntfy.lookups, isEmpty, reason: 'a store-weighed pack is on no public list');
    });
  });

  test('the likeliest ingredient for a packet leads', () {
    const names = {
      'sour-cream': 'sour cream', 'cream-cheese': 'cream cheese', 'cream-sauce-base': 'cream sauce base', 'tomato': 'tomato',
      'crushed-tomatoes': 'crushed tomatoes', 'tomato-paste': 'tomato paste', 'onion': 'onion', 'red-onion': 'red onion', 'penne-pasta': 'penne pasta',
    };
    expect(matchIngredients('Kroger Natural Sour Cream', names), ['sour-cream', 'cream-cheese', 'cream-sauce-base']);
    expect(matchIngredients('Crushed Tomatoes in Puree', names), ['crushed-tomatoes', 'tomato', 'tomato-paste']);
    expect(matchIngredients('Red Onions 3 lb bag', names), ['red-onion', 'onion']);
    expect(matchIngredients('Penne Rigate', names), ['penne-pasta']);
    expect(matchIngredients('Dish Soap', names), isEmpty);
    expect(matchIngredients('', names), isEmpty);
  });

  group('on the Shop tab', () {
    late FakeNtfy ntfy;
    late AppModel model;
    // What the stand-in camera reports its barcodes to.
    late ValueChanged<String> camera;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final real = buildCamera;
      buildCamera = (context, onCode) {
        camera = onCode;
        return const SizedBox.expand();
      };
      addTearDown(() => buildCamera = real);
      ntfy = lists();
      model = AppModel(Session(store: MemoryStore(), client: ntfy.client(), notifier: SilentNotifier()), clock: () => thursday);
      await model.start();
      await tester.pumpWidget(DinnerApp(model: model));
      await tester.pumpAndSettle();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
      await model.setMe('blue');
      await model.setMeal('2026-11-19', 'beef-chili');
      await model.setMeal('2026-11-20', 'baked-penne');
      await tester.tap(find.text('Shop'));
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, String key) async {
      if (find.byKey(ValueKey(key)).evaluate().isEmpty) {
        // The list is built as it scrolls: go back to the top for its buttons.
        await tester.drag(find.descendant(of: find.byType(ShopScreen), matching: find.byType(Scrollable)).first, const Offset(0, 5000));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
    }

    /// The camera reads a barcode.
    Future<void> see(WidgetTester tester, String code) async {
      camera(code);
      await tester.pumpAndSettle();
    }

    /// The number is put in by hand instead.
    Future<void> type(WidgetTester tester, String digits) async {
      await tap(tester, 'scan-type');
      await tester.enterText(find.byKey(const ValueKey('scan-number')), digits);
      await tap(tester, 'scan-number-use');
    }

    String field(WidgetTester tester, String key) => tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;
    String said(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('scan-said'))).data!;
    List<String> toBuy() => [for (final l in model.shopping) l.id];
    List<String> got() => [for (final l in model.shoppingGot) l.id];

    testWidgets('scan from a line: the packet fills in what you buy', (tester) async {
      await open(tester);
      await tap(tester, 'shop-edit-ground-beef');
      await tap(tester, 'shop-scan-packet');
      await see(tester, beefCode);
      expect(field(tester, 'shop-buy-text'), 'Ranch Hand Ground Beef 88% Lean', reason: 'one barcode and the camera closes');
      expect(field(tester, 'shop-size-text'), '1 lb');
      expect(find.textContaining('From the barcode.'), findsOneWidget);
      await tap(tester, 'shop-buy-save');
      expect(model.buy('ground-beef'), 'Ranch Hand Ground Beef 88% Lean');
      expect(model.ingredientForCode(beefCode), 'ground-beef');
      expect(find.byKey(const ValueKey('shop-ground-beef')), findsOneWidget, reason: 'naming it does not tick it');
      expect(find.textContaining('2 × 1 lb'), findsOneWidget);

      // Backing out of the camera changes nothing.
      await tap(tester, 'shop-edit-onion');
      await tap(tester, 'shop-scan-packet');
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('shop-scan-note')), findsNothing);
      // A packet nobody has on file, its number typed in: still remembered once it is named.
      await tap(tester, 'shop-scan-packet');
      await type(tester, nobodyKnows);
      expect(find.textContaining('Neither list knows that barcode.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('shop-buy-text')), 'Yellow onions, the 3 lb bag');
      await tap(tester, 'shop-buy-save');
      expect(model.ingredientForCode(nobodyKnows), 'onion');
      expect(tester.takeException(), isNull);
    });

    testWidgets('keep scanning: say once what a packet is, after that it ticks itself', (tester) async {
      await open(tester);
      await tap(tester, 'shop-scan');
      expect(said(tester), startsWith('Hold a barcode in view.'));
      await see(tester, penneCode);
      expect(find.text('Which ingredient is this?'), findsOneWidget);
      expect(find.text('Pasta Co Penne Rigate'), findsOneWidget);
      expect(find.text('Most likely'), findsOneWidget);
      await tap(tester, 'match-penne');
      expect(find.text('What do you buy for penne?'), findsOneWidget);
      expect(field(tester, 'shop-buy-text'), 'Pasta Co Penne Rigate');
      expect(field(tester, 'shop-size-text'), '16 oz');
      await tap(tester, 'shop-buy-save');
      expect((model.buy('penne'), model.size('penne'), model.ingredientForCode(penneCode)), ('Pasta Co Penne Rigate', '16 oz', 'penne'));
      expect(got(), contains('penne'), reason: 'it is in the hand, so it is ticked');
      expect(said(tester), 'Got: Pasta Co Penne Rigate', reason: 'and the camera is still open');

      await tap(tester, 'scan-undo');
      expect(said(tester), 'Undone.');
      expect(toBuy(), contains('penne'));
      // The packet is still in front of the camera: it is not taken again.
      await see(tester, penneCode);
      expect(said(tester), 'Undone.');
      expect(toBuy(), contains('penne'));

      // A number the camera will not read is typed; a known packet needs no questions.
      final asked = ntfy.lookups.length;
      await type(tester, '1234');
      expect(find.text('A barcode has 8 to 14 digits.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('scan-number')), '0 12345 00001 9');
      await tap(tester, 'scan-number-use');
      expect(said(tester), 'Got: Pasta Co Penne Rigate');
      expect(ntfy.lookups.length, asked);
      await type(tester, penneCode);
      expect(said(tester), 'Pasta Co Penne Rigate: not on the list right now.');

      // A packet neither list knows: find the ingredient, name it once.
      await see(tester, nobodyKnows);
      expect(find.byKey(const ValueKey('match-unknown')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('match-filter')), 'oni');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('match-penne')), findsNothing);
      await tap(tester, 'match-onion');
      await tester.enterText(find.byKey(const ValueKey('shop-buy-text')), 'Yellow onions');
      await tap(tester, 'shop-buy-save');
      expect(model.ingredientForCode(nobodyKnows), 'onion');
      expect(said(tester), 'Got: Yellow onions');

      // Backing out of the question leaves things as they were, camera still on.
      await see(tester, beefCode);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(model.ingredientForCode(beefCode), isNull);
      expect(said(tester), 'Got: Yellow onions');
      expect(find.text('Done (4)'), findsOneWidget);

      await tap(tester, 'scan-done');
      expect(find.byKey(const ValueKey('got-onion')), findsOneWidget);
      expect(find.byKey(const ValueKey('got-penne')), findsOneWidget);
      expect(find.byKey(const ValueKey('shop-ground-beef')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('extras: typed in, scanned in, and back on the list when they run out', (tester) async {
      await open(tester);
      await tap(tester, 'shop-add');
      await tester.enterText(find.byKey(const ValueKey('extra-text')), 'Milk, dish soap');
      await tap(tester, 'extra-add');
      expect(find.byKey(const ValueKey('shop-milk')), findsOneWidget);
      expect(find.byKey(const ValueKey('shop-dish-soap')), findsOneWidget);
      expect((model.section('milk'), model.section('dish-soap')), ('dairy', 'other'));
      expect(model.shoppingText(), contains('- Milk'));

      await tap(tester, 'shop-milk');
      expect(find.byKey(const ValueKey('got-milk')), findsOneWidget);
      expect(toBuy(), isNot(contains('milk')));
      // It is offered again next time, and can be forgotten.
      await tap(tester, 'shop-add');
      expect(find.byKey(const ValueKey('extra-idea-dish-soap')), findsNothing, reason: 'already on the list');
      await tap(tester, 'extra-idea-milk');
      await tap(tester, 'extra-add');
      expect(toBuy(), contains('milk'));
      expect(got(), isNot(contains('milk')));

      // A packet that is not for any recipe.
      const coffeeCode = '012345000033';
      ntfy.openFoodFacts[coffeeCode] = {'product_name': 'Ground Coffee', 'brands': 'Bean Barn', 'quantity': '12 oz'};
      await tap(tester, 'shop-scan');
      await see(tester, coffeeCode);
      await tap(tester, 'match-extra');
      expect(field(tester, 'extra-name'), 'Ground Coffee');
      await tester.enterText(find.byKey(const ValueKey('extra-name')), 'Coffee');
      await tap(tester, 'extra-want');
      expect(said(tester), 'On the list: Coffee');
      expect((model.extras['coffee'], model.buy('coffee'), model.size('coffee'), model.ingredientForCode(coffeeCode)), ('Coffee', 'Bean Barn Ground Coffee', '12 oz', 'coffee'));
      expect(toBuy(), contains('coffee'));

      // In the cart: one scan. Run out at home: one scan puts it back.
      await type(tester, coffeeCode);
      expect(said(tester), 'Got: Bean Barn Ground Coffee');
      expect(got(), contains('coffee'));
      await type(tester, coffeeCode);
      expect(said(tester), 'On the list: Bean Barn Ground Coffee');
      await tap(tester, 'scan-undo');
      expect(toBuy(), isNot(contains('coffee')));
      // In a store, something not on the list is left alone.
      await model.addStores(['Costco']);
      await model.shopAt('costco');
      await type(tester, coffeeCode);
      expect(said(tester), 'Bean Barn Ground Coffee: not on the list right now.');

      // A second brand of the same thing is matched to the extra already known.
      await see(tester, nobodyKnows);
      await tester.enterText(find.byKey(const ValueKey('match-filter')), 'coff');
      await tester.pumpAndSettle();
      await tap(tester, 'match-coffee');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tap(tester, 'scan-done');

      await tap(tester, 'shop-add');
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('extra-idea-coffee')), matching: find.byTooltip('Forget it')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('extra-idea-coffee')), findsNothing);
      expect(model.extras.keys, isNot(contains('coffee')));
      expect(tester.takeException(), isNull);
    });
  });

  test('extras are one list on both phones, and a tick for dinner covers the house', () async {
    final ntfy = lists();
    AppModel phone() => AppModel(Session(store: MemoryStore(), client: ntfy.client(), notifier: SilentNotifier()), clock: () => thursday);
    final his = phone(), hers = phone();
    await his.start();
    await hers.start();
    await his.startHousehold();
    await hers.joinHousehold(his.household!.code);
    await his.refreshRecipes();
    await hers.refreshRecipes();

    expect(await his.addExtra('  '), isNull);
    expect(await his.addExtra('Paper towels'), 'paper-towels');
    await pumpEventQueue();
    await his.sync();
    await hers.sync();
    expect([for (final l in hers.shopping) (l.id, l.name, l.extra)], [('paper-towels', 'Paper towels', true)]);

    await hers.setGot(hers.shopping.single, true);
    await pumpEventQueue();
    await hers.sync();
    await his.sync();
    expect(his.shopping, isEmpty);
    expect([for (final l in his.shoppingGot) l.id], ['paper-towels']);
    expect(his.extras, {'paper-towels': 'Paper towels'}, reason: 'still known, to put back with a tap');

    // Onions for the house, and then a dinner that needs onions too: one line.
    await his.addExtra('Onion');
    await his.setMeal('2026-11-19', 'beef-chili');
    final onion = his.shopping.where((l) => l.id == 'onion').toList();
    expect(onion.length, 1);
    expect((onion.single.extra, his.wantedToo('onion')), (false, true));
    await his.setGot(onion.single, true);
    expect(his.wantedToo('onion'), isFalse);
    expect([for (final l in his.shopping) l.id], isNot(contains('onion')));
  });
}

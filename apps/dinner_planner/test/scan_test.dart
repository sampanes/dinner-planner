import 'package:dinner_planner/app_model.dart';
import 'package:dinner_planner/data/products.dart';
import 'package:dinner_planner/data/session.dart';
import 'package:dinner_planner/data/store.dart';
import 'package:dinner_planner/main.dart';
import 'package:dinner_planner/notify/notifier.dart';
import 'package:dinner_planner/ui/scan.dart';
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
    String? next;

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final camera = scanCode;
      scanCode = (_) async => next;
      addTearDown(() => scanCode = camera);
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
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
    }

    String field(WidgetTester tester, String key) => tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

    testWidgets('scan from a line: the packet fills in what you buy', (tester) async {
      await open(tester);
      await tap(tester, 'shop-edit-ground-beef');
      next = beefCode;
      await tap(tester, 'shop-scan-packet');
      expect(field(tester, 'shop-buy-text'), 'Ranch Hand Ground Beef 88% Lean');
      expect(field(tester, 'shop-size-text'), '1 lb');
      expect(find.textContaining('From the barcode.'), findsOneWidget);
      await tap(tester, 'shop-buy-save');
      expect(model.buy('ground-beef'), 'Ranch Hand Ground Beef 88% Lean');
      expect(model.ingredientForCode(beefCode), 'ground-beef');
      expect(find.byKey(const ValueKey('shop-ground-beef')), findsOneWidget, reason: 'naming it does not tick it');
      expect(find.textContaining('2 × 1 lb'), findsOneWidget);

      // Backing out of the camera changes nothing.
      await tap(tester, 'shop-edit-onion');
      next = null;
      await tap(tester, 'shop-scan-packet');
      expect(find.byKey(const ValueKey('shop-scan-note')), findsNothing);
      // A packet nobody has on file is still remembered once it is named.
      next = nobodyKnows;
      await tap(tester, 'shop-scan-packet');
      expect(find.textContaining('Neither list knows that barcode.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('shop-buy-text')), 'Yellow onions, the 3 lb bag');
      await tap(tester, 'shop-buy-save');
      expect(model.ingredientForCode(nobodyKnows), 'onion');
      expect(tester.takeException(), isNull);
    });

    testWidgets('scan anything: say once what a packet is, after that it ticks itself', (tester) async {
      await open(tester);
      next = penneCode;
      await tap(tester, 'shop-scan');
      expect(find.text('Which ingredient is this?'), findsOneWidget);
      expect(find.text('Pasta Co Penne Rigate'), findsOneWidget);
      expect(find.text('Most likely'), findsOneWidget);
      await tap(tester, 'match-penne');
      expect(find.text('What do you buy for penne?'), findsOneWidget);
      expect(field(tester, 'shop-buy-text'), 'Pasta Co Penne Rigate');
      expect(field(tester, 'shop-size-text'), '16 oz');
      await tap(tester, 'shop-buy-save');
      expect((model.buy('penne'), model.size('penne'), model.ingredientForCode(penneCode)), ('Pasta Co Penne Rigate', '16 oz', 'penne'));
      expect(find.byKey(const ValueKey('got-penne')), findsOneWidget, reason: 'it is in the hand, so it is ticked');
      expect(find.text('Got: Pasta Co Penne Rigate'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('shop-penne')), findsOneWidget);

      // The second time needs no list and no questions.
      final asked = ntfy.lookups.length;
      await tap(tester, 'shop-scan');
      expect(find.byKey(const ValueKey('got-penne')), findsOneWidget);
      expect(ntfy.lookups.length, asked);
      await tap(tester, 'shop-scan');
      expect(find.text('Pasta Co Penne Rigate: not on the list right now.'), findsOneWidget);

      // A packet neither list knows: find the ingredient, name it once.
      next = nobodyKnows;
      await tap(tester, 'shop-scan');
      expect(find.byKey(const ValueKey('match-unknown')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('match-filter')), 'oni');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('match-penne')), findsNothing);
      await tap(tester, 'match-onion');
      await tester.enterText(find.byKey(const ValueKey('shop-buy-text')), 'Yellow onions');
      await tap(tester, 'shop-buy-save');
      expect(model.ingredientForCode(nobodyKnows), 'onion');
      expect(find.byKey(const ValueKey('got-onion')), findsOneWidget);
      expect(find.text('Got: Yellow onions'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Got: Yellow onions'), findsNothing, reason: 'the message leaves on its own, Undo button or not');

      // Backing out anywhere leaves things as they were.
      next = beefCode;
      await tap(tester, 'shop-scan');
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(model.ingredientForCode(beefCode), isNull);
      expect(find.byKey(const ValueKey('shop-ground-beef')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

import 'dart:convert';

import 'package:dinner_planner/app_model.dart';
import 'package:dinner_planner/data/labels.dart';
import 'package:dinner_planner/data/session.dart';
import 'package:dinner_planner/data/store.dart';
import 'package:dinner_planner/main.dart';
import 'package:dinner_planner/notify/notifier.dart';
import 'package:dinner_planner/ui/scan.dart';
import 'package:dinner_planner/ui/shop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_labels.dart';
import 'fake_ntfy.dart';

final DateTime thursday = DateTime(2026, 11, 19, 16, 30);

// What a phone reads off three made-up labels.
final List<LabelLine> meatSticker = lines([
  ('CORNER MARKET', 22), ('GROUND BEEF', 54), ('80% LEAN 20% FAT', 26), ('KEEP REFRIGERATED', 14), ('SELL BY 11/24/26', 16), ('NET WT', 14), ('1.33 Ib', 30),
  ('UNIT PRICE', 14), (r'$5.99/lb', 28), ('TOTAL PRICE', 14), (r'$7.97', 40), ('SAFE HANDLING INSTRUCTIONS', 10),
]);
final List<LabelLine> shelfTag = lines([('MEADOW FARM SHREDDED SHARP CHEDDAR CHEESE 8 OZ', 22), (r'$2.49', 80), ('31.1¢ PER OZ', 14), ('UPC 0001234500019', 10)]);
final List<LabelLine> backOfPack = lines([
  ('Nutrition Facts', 30), ('Serving size 2 Tbsp (30g)', 14), ('Total Fat 5g', 14), ('Protein 1g', 14), ('INGREDIENTS: CULTURED CREAM, SALT, ONION POWDER.', 12), ('DISTRIBUTED BY SOMEBODY FOODS', 10),
]);
final List<LabelLine> onionBag = lines([('Meadow Farm', 30), ('YELLOW ONIONS', 60), ('NET WT 3 LB (1.36 kg)', 20), ('PRODUCT OF USA', 12)]);

void main() {
  group('reading a label', () {
    test('a price sticker on meat: the name is the tall words, the weight is not the price', () {
      final label = parseLabel(meatSticker);
      expect([for (final l in label.lines) l.text], ['Corner Market', 'Ground Beef', '80% Lean 20% Fat']);
      expect(label.size, '1.33 lb', reason: 'the camera read "Ib"');
      expect(labelName(label), 'Ground Beef');
      expect(labelName(label, ingredient: 'ground beef'), 'Ground Beef');
    });

    test('a shelf tag: the size comes off the end of the name', () {
      final label = parseLabel(shelfTag);
      expect([for (final l in label.lines) l.text], ['Meadow Farm Shredded Sharp Cheddar Cheese']);
      expect(label.size, '8 oz');
      expect(labelName(label, ingredient: 'cheddar cheese'), 'Meadow Farm Shredded Sharp Cheddar Cheese');
    });

    test('the back of a packet names nothing', () {
      final label = parseLabel(backOfPack);
      expect(label.isEmpty, isTrue, reason: '5 g of fat is not a size, and an ingredient is not what it is');
    });

    test('the size beside "NET WT" beats any other', () {
      expect(parseLabel(onionBag).size, '3 lb');
      expect(parseLabel(lines([('2 LB BAG', 20), ('NET WT 32 0Z (2 LB) 907g', 12)])).size, '32 oz', reason: 'a zero read for the O');
      expect(parseLabel(lines([('SPARKLING WATER', 30), ('12 FL OZ CANS', 14), ('8 PACK', 20)])).size, '12 fl oz');
      expect(parseLabel(lines([('LARGE EGGS', 30), ('12 CT', 20)])).size, '12 ct');
      expect(parseLabel(lines([('CHICKEN THIGHS', 30), (r'$ 3.49 lb', 20)])).size, '', reason: 'a price by the pound');
      expect(parseLabel(lines([('CHICKEN THIGHS', 30), ('2,15 lb', 20)])).size, '2.15 lb');
      expect(parseLabel(const []).isEmpty, isTrue);
    });

    test('as a product: named for the ingredient it matches, and a weighed pack keeps no size', () {
      const names = {'ground-beef': 'ground beef', 'cheddar-cheese': 'cheddar cheese', 'onion': 'onion'};
      final beef = productFromLabel('212345000000', parseLabel(meatSticker), names);
      expect((beef.shelfName, beef.size, beef.read), ('Ground Beef', '', true));
      final cheese = productFromLabel('012345000019', parseLabel(shelfTag), names);
      expect((cheese.shelfName, cheese.size), ('Meadow Farm Shredded Sharp Cheddar Cheese', '8 oz'));
      final onions = productFromLabel('', parseLabel(onionBag), names);
      expect((onions.shelfName, onions.size), ('Yellow Onions', '3 lb'));
      final unknown = productFromLabel('', parseLabel(lines([('Bean Barn', 20), ('GROUND COFFEE', 50)])), names);
      expect(unknown.shelfName, 'Ground Coffee', reason: 'no ingredient matches: the tallest line');
    });
  });

  group('on the Shop tab', () {
    late FakeNtfy ntfy;
    late FakeLabels labels;
    late AppModel model;
    late OnSeen camera;

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
      Map<String, Object?> item(String id, String amount) => {'id': id, 'displayName': id.replaceAll('-', ' '), 'amountText': amount, 'text': '$amount ${id.replaceAll('-', ' ')}'};
      ntfy = FakeNtfy()
        ..recipesJson = jsonEncode([
          {'slug': 'beef-tacos', 'displayName': 'Beef Tacos', 'categories': ['Beef'], 'ingredients': [
            item('ground-beef', '1 lb'), item('cheddar-cheese', '1 1/2 cup'), item('sour-cream', '4 tablespoon'), item('chili-flakes', '1 teaspoon'), item('lime', '2 unit'), item('yellow-onion', '1 unit'),
          ]},
          {'slug': 'cheese-melts', 'displayName': 'Cheese Melts', 'categories': ['Veggie'], 'ingredients': [item('ground-beef', '10 ounce'), item('cheddar-cheese', '1 cup'), item('yellow-onion', '2 unit')]},
        ]);
      labels = FakeLabels();
      model = AppModel(Session(store: MemoryStore(), client: ntfy.client(), notifier: SilentNotifier()), clock: () => thursday, labels: labels);
      await model.start();
      await tester.pumpWidget(DinnerApp(model: model));
      await tester.pumpAndSettle();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
      await model.setMe('blue');
      await model.setMeal('2026-11-19', 'beef-tacos');
      await model.setMeal('2026-11-20', 'cheese-melts');
      await tester.tap(find.text('Shop'));
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, String key) async {
      if (find.byKey(ValueKey(key)).evaluate().isEmpty) {
        await tester.drag(find.descendant(of: find.byType(ShopScreen), matching: find.byType(Scrollable)).first, const Offset(0, 5000));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
    }

    String field(WidgetTester tester, String key) => tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;
    String said(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('scan-said'))).data!;

    testWidgets('the list reads in ounces and packets, with the cups underneath', (tester) async {
      await open(tester);
      expect(find.text('10 oz  Cheddar cheese'), findsOneWidget, reason: '2 1/2 cups of shredded cheese');
      expect(find.text('2 1/2 cups · Beef Tacos, Cheese Melts'), findsOneWidget);
      expect(find.text('2 oz  Sour cream'), findsOneWidget);
      expect(find.text('4 tbsp · Beef Tacos'), findsOneWidget);
      expect(find.text('1.63 lb  Ground beef'), findsOneWidget, reason: 'the meat counter reads in pounds');
      expect(find.text('2  Lime'), findsOneWidget);
      expect(model.shoppingText().split('\n'), containsAll(['- 10 oz cheddar cheese', '- 1 tsp chili flakes', '- 2 lime']), reason: 'a spoonful of a spice stays a spoonful: any jar will do');

      // Say what the household buys, and it is a number of packets.
      await model.saveProduct('cheddar-cheese', size: '8 oz');
      await model.saveProduct('yellow-onion', size: '3 lb');
      await tester.pumpAndSettle();
      expect(find.text('2 × 8 oz  Cheddar cheese'), findsOneWidget);
      expect(find.text('2 1/2 cups · Beef Tacos, Cheese Melts'), findsOneWidget);
      expect(find.text('1 × 3 lb  Yellow onion'), findsOneWidget, reason: 'three onions out of a three pound bag');
      expect(find.text('3 · Beef Tacos, Cheese Melts'), findsOneWidget);
      expect(model.shoppingText(), contains('- 2 × 8 oz cheddar cheese'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a pack the store weighed: the label says what it is and whether it is enough', (tester) async {
      await open(tester);
      labels.frames[1] = meatSticker;
      await tap(tester, 'shop-scan');
      camera('212345000000', picture: frame(1));
      await tester.pumpAndSettle();
      expect(find.text('Which ingredient is this?'), findsOneWidget);
      expect(find.byKey(const ValueKey('match-read-said')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('match-found'))).data, 'Ground Beef');
      expect(find.text('Most likely'), findsOneWidget);
      expect(ntfy.lookups, isEmpty, reason: 'no public list is asked about a store-made barcode');
      await tap(tester, 'match-ground-beef');
      expect(field(tester, 'shop-buy-text'), 'Ground Beef');
      expect(field(tester, 'shop-size-text'), '', reason: 'the next pack will weigh something else');
      expect(find.textContaining('Read off the label.'), findsOneWidget);
      await tap(tester, 'shop-buy-save');
      expect(said(tester), 'Got: Ground Beef. 1.33 lb, and the dinners need 1.63 lb: 4 1/2 oz short.');
      expect(model.ingredientForCode('212345000000'), 'ground-beef');
      expect(model.size('ground-beef'), isNull);

      // Another pack of the same thing needs no questions, only its weight read.
      await tap(tester, 'scan-undo');
      await tap(tester, 'scan-done');
      labels.frames[2] = lines([('GROUND BEEF', 54), ('1.75 lb', 30), (r'$10.48', 40)]);
      await tap(tester, 'shop-scan');
      camera('212345000000', picture: frame(2));
      await tester.pumpAndSettle();
      expect(said(tester), 'Got: Ground Beef. 1.75 lb covers the 1.63 lb needed.');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a barcode no list knows: the label is read instead of typed', (tester) async {
      await open(tester);
      // The frame the barcode was seen in is the back of the bag.
      labels.frames[3] = backOfPack;
      await tap(tester, 'shop-scan');
      camera('099999000011', picture: frame(3));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('match-unknown')), findsOneWidget);

      // Backing out of the phone's camera changes nothing.
      await tap(tester, 'match-read');
      expect(find.byKey(const ValueKey('match-unknown')), findsOneWidget);
      // A picture with no words in it says so.
      labels.photos.add(const []);
      await tap(tester, 'match-read');
      expect(tester.widget<Text>(find.byKey(const ValueKey('match-read-note'))).data, startsWith('No words could be read'));
      // The front of the bag.
      labels.photos.add(onionBag);
      await tap(tester, 'match-read');
      expect(tester.widget<Text>(find.byKey(const ValueKey('match-found'))).data, 'Yellow Onions');
      expect(find.text('3 lb'), findsOneWidget);
      expect(find.text('Most likely'), findsOneWidget);
      await tap(tester, 'match-yellow-onion');
      expect((field(tester, 'shop-buy-text'), field(tester, 'shop-size-text')), ('Yellow Onions', '3 lb'));
      await tap(tester, 'shop-buy-save');
      expect(said(tester), 'Got: Yellow Onions');
      expect((model.buy('yellow-onion'), model.size('yellow-onion'), model.ingredientForCode('099999000011')), ('Yellow Onions', '3 lb', 'yellow-onion'));
      expect(labels.photographed, 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('from a line: read the shelf tag for the name and the packet size', (tester) async {
      await open(tester);
      await tap(tester, 'shop-edit-cheddar-cheese');
      await tap(tester, 'shop-read-label');
      expect(field(tester, 'shop-buy-text'), '', reason: 'backed out of the camera');
      labels.photos.add(shelfTag);
      await tap(tester, 'shop-read-label');
      expect((field(tester, 'shop-buy-text'), field(tester, 'shop-size-text')), ('Meadow Farm Shredded Sharp Cheddar Cheese', '8 oz'));
      expect(find.textContaining('Read off the label.'), findsOneWidget);
      await tap(tester, 'shop-buy-save');
      expect(find.text('2 × 8 oz  Meadow Farm Shredded Sharp Cheddar Cheese'), findsOneWidget);
      expect(find.text('cheddar cheese · 2 1/2 cups · Beef Tacos, Cheese Melts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

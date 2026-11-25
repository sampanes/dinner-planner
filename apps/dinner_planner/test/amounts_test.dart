import 'package:dinner_planner/core/amounts.dart';
import 'package:dinner_planner/core/shopping.dart';
import 'package:flutter_test/flutter_test.dart';

ShopLine line(String id, Map<String, double> totals) => ShopLine(id, id.replaceAll('-', ' '))..totals.addAll(totals);

void main() {
  test('every ingredient the recipes measure by the cup or the spoon has a weight', () {
    // What the recipe site asked for by volume on 2026-11-24.
    const byVolume = [
      'blackening-spice', 'bulgogi-sauce', 'butter', 'cheddar-cheese', 'chili-flakes', 'chili-powder', 'cream-cheese', 'creme-fraiche', 'cumin', 'dijon-mustard', 'fajita-spice-blend', 'feta-cheese', 'flour',
      'fry-seasoning', 'garlic-herb-butter', 'garlic-powder', 'guacamole', 'honey', 'hot-sauce', 'italian-cheese-blend', 'italian-seasoning', 'jasmine-rice', 'korean-chili-flakes', 'mayonnaise',
      'mexican-cheese-blend', 'mexican-spice-blend', 'monterey-jack-cheese', 'mozzarella-cheese', 'oil', 'panko-breadcrumbs', 'parmesan-cheese', 'pepper-jack-cheese', 'romesco-sauce', 'salt', 'sesame-seeds',
      'smoky-red-pepper-crema', 'sour-cream', 'southwest-spice-blend', 'soy-sauce', 'sriracha', 'sugar', 'sweet-soy-glaze', 'thyme', 'tuscan-heat-spice', 'white-rice', 'yogurt',
    ];
    expect([for (final id in byVolume) if (cupWeighs(id) == null) id], isEmpty);
  });

  test('a cup weighs what the thing is, and the narrow name wins', () {
    expect(cupWeighs('cheddar-cheese'), 4);
    expect(cupWeighs('Parmesan Cheese'), 3);
    expect(cupWeighs('cream-cheese'), 8, reason: 'not shredded cheese');
    expect(cupWeighs('garlic-herb-butter'), 8);
    expect(cupWeighs('peanut-butter'), 9.5, reason: 'not butter');
    expect(cupWeighs('panko-breadcrumbs'), 2);
    expect(cupWeighs('sour-cream'), 8.5, reason: 'not cream');
    expect(cupWeighs('jasmine-rice'), 6.5);
    expect(cupWeighs('rice-vinegar'), 8.4, reason: 'not rice');
    expect(cupWeighs('cheese-roux-concentrate'), isNull);
    expect(cupWeighs('lime'), isNull);
    expect((soldByWeight('cheddar-cheese'), soldByWeight('soy-sauce'), soldByWeight('lime')), (true, false, false));
  });

  test('one of a thing weighs what the thing is', () {
    expect(eachWeighs('yellow-onion'), 8);
    expect(eachWeighs('scallions'), 0.5, reason: 'not an onion');
    expect(eachWeighs('crispy-fried-onions'), isNull);
    expect(eachWeighs('roma-tomato'), 3.5);
    expect(eachWeighs('grape-tomatoes'), isNull);
    expect(eachWeighs('tomato-paste'), 1.5);
    expect(eachWeighs('green-bell-pepper'), 6);
    expect(eachWeighs('pepper-jack-cheese'), isNull);
    expect(eachWeighs('potatoes'), 6);
    expect(eachWeighs('hash-brown-shredded-potatoes'), isNull);
    expect(eachWeighs('black-beans'), isNull);
  });

  test('cups and spoons meet a packet sold by weight', () {
    expect(packsNeeded({'cup': 2}, '8 oz', ingredient: 'cheddar-cheese'), 1);
    expect(packsNeeded({'cup': 2.25}, '8 oz', ingredient: 'cheddar-cheese'), 2);
    expect(packsNeeded({'oz': 8, 'cup': 1}, '16 oz', ingredient: 'mozzarella-cheese'), 1, reason: 'ounces and cups of the same thing add up');
    expect(packsNeeded({'tbsp': 5}, '5 lb', ingredient: 'flour'), 1);
    expect(packsNeeded({'tbsp': 40}, '16 oz', ingredient: 'sour-cream'), 2);
    expect(packsNeeded({'tbsp': 9}, '2.5 oz', ingredient: 'southwest-spice-blend'), 1);
    expect(packsNeeded({'tsp': 6}, '12 oz', ingredient: 'honey'), 1);
    expect(packsNeeded({'cup': 2}, '16 oz', ingredient: 'mystery-thing'), isNull, reason: 'nothing known about it');
    // Spoons against a bottle marked in fluid ounces never needed a weight.
    expect(packsNeeded({'tbsp': 2}, '16.9 fl oz', ingredient: 'oil'), 1);
  });

  test('things counted whole meet a bag sold by weight', () {
    expect(packsNeeded({'': 3}, '3 lb', ingredient: 'yellow-onion'), 1);
    expect(packsNeeded({'': 8}, '3 lb', ingredient: 'yellow-onion'), 2);
    expect(packsNeeded({'': 6}, '2 lb', ingredient: 'lemon'), 1);
    expect(packsNeeded({'clove': 12}, '1 ct', ingredient: 'garlic'), 2, reason: 'about ten cloves to a head');
    expect(packsNeeded({'clove': 7}, '3 ct', ingredient: 'garlic'), 1);
    expect(packsNeeded({'': 2, 'oz': 3}, '6 oz', ingredient: 'tomato-paste'), 1);
    expect(packsNeeded({'': 14}, '17.5 oz', ingredient: 'flour-tortillas'), isNull, reason: 'no guessing how many are in a pack');
    expect(packsNeeded({'': 2}, '15 oz', ingredient: 'black-beans'), isNull);
  });

  test('a list line reads in what the store sells', () {
    ShopAmount of(String id, Map<String, double> totals, {String? size, bool byPound = false}) => shopAmount(line(id, totals), size: size, byPound: byPound);
    expect(of('cheddar-cheese', {'cup': 1.5}), (lead: '6 oz', asked: '1 1/2 cups'));
    expect(of('cheddar-cheese', {'cup': 1.5}, size: '8 oz'), (lead: '1 × 8 oz', asked: '1 1/2 cups'));
    expect(of('cheddar-cheese', {'cup': 3}, size: '8 oz'), (lead: '2 × 8 oz', asked: '3 cups'));
    expect(of('sour-cream', {'tbsp': 4}), (lead: '2 oz', asked: '4 tbsp'));
    expect(of('jasmine-rice', {'cup': 1.5}), (lead: '10 oz', asked: '1 1/2 cups'));
    expect(of('mozzarella-cheese', {'oz': 8, 'cup': 1}), (lead: '12 oz', asked: '8 oz + 1 cup'));
    // A spoonful of a spice: any jar will do.
    expect(of('chili-flakes', {'tsp': 2}), (lead: '2 tsp', asked: null));
    expect(of('butter', {'tbsp': 1}), (lead: '1 tbsp', asked: null));
    // What comes in a bottle stays in spoons.
    expect(of('soy-sauce', {'tbsp': 4}), (lead: '4 tbsp', asked: null));
    // Counted things stay counted, until the bag they come in is known.
    expect(of('lime', {'': 3}), (lead: '3', asked: null));
    expect(of('yellow-onion', {'': 3}, size: '3 lb'), (lead: '1 × 3 lb', asked: '3'));
    expect(of('black-beans', {'': 2}, size: '15 oz'), (lead: '2', asked: null));
    // Weights read the way the label does: pounds at the meat counter.
    expect(of('ground-beef', {'oz': 20}, byPound: true), (lead: '1.25 lb', asked: null));
    expect(of('ground-beef', {'lb': 1, 'oz': 10}, byPound: true), (lead: '1.63 lb', asked: null));
    expect(of('ground-beef', {'oz': 12}, byPound: true), (lead: '12 oz', asked: null));
    expect(of('penne-pasta', {'oz': 20}), (lead: '20 oz', asked: null));
    expect(of('penne-pasta', {'lb': 1, 'oz': 4}), (lead: '20 oz', asked: null));
    expect(of('crushed-tomatoes', {'oz': 13.76}), (lead: '14 oz', asked: null), reason: 'nobody shops by the hundredth of an ounce');
    expect(of('parsley', {'oz': 0.25}, byPound: true), (lead: '1/4 oz', asked: null));
    expect(of('salt', {}), (lead: '', asked: null));
    expect(of('ginger', {'thumb': 2}, size: '4 oz'), (lead: '1 × 4 oz', asked: '2 thumb'));
  });

  test('a weighed pack is held against what the dinners need', () {
    final beef = line('ground-beef', {'lb': 1, 'oz': 10});
    expect(packNote(beef, '1.33 lb', byPound: true), '1.33 lb, and the dinners need 1.63 lb: 4 1/2 oz short.');
    expect(packNote(beef, '1.75 lb', byPound: true), '1.75 lb covers the 1.63 lb needed.');
    expect(packNote(beef, '1.6 lb', byPound: true), '1.6 lb covers the 1.63 lb needed.', reason: 'half an ounce is nothing');
    expect(packNote(line('cheddar-cheese', {'cup': 3}), '8 oz'), '8 oz, and the dinners need 12 oz: 4 oz short.');
    expect(packNote(line('ground-beef', {'oz': 60}), '1.33 lb', byPound: true), '1.33 lb, and the dinners need 3.75 lb: 2.42 lb short.');
    expect(packNote(beef, '6 ct'), isNull);
    expect(packNote(beef, ''), isNull);
    expect(packNote(line('flour-tortillas', {'': 6}), '17.5 oz'), isNull);
  });

  test('weights are said the way a shelf says them', () {
    expect(formatWeight(6), '6 oz');
    expect(formatWeight(1.4), '1 1/2 oz');
    expect(formatWeight(0.1), '1/4 oz');
    expect(formatWeight(0.7), '3/4 oz');
    expect(formatWeight(2.3), '2 1/2 oz');
    expect(formatWeight(11.6), '12 oz');
    expect(formatWeight(24), '24 oz');
    expect(formatWeight(24, byPound: true), '1.5 lb');
    expect(formatWeight(32, byPound: true), '2 lb');
    expect(formatWeight(18, byPound: true), '1.13 lb');
  });
}

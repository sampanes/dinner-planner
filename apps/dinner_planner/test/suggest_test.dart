import 'dart:io';

import 'package:dinner_planner/app_model.dart';
import 'package:dinner_planner/core/shopping.dart';
import 'package:dinner_planner/data/recipes.dart';
import 'package:dinner_planner/data/session.dart';
import 'package:dinner_planner/data/store.dart';
import 'package:dinner_planner/data/suggest.dart';
import 'package:dinner_planner/main.dart';
import 'package:dinner_planner/notify/notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ntfy.dart';

final DateTime thursday = DateTime(2026, 11, 19, 16, 30);

Recipe recipe(String name, {String kind = 'Beef', int pink = 0, int blue = 0, Map<String, String> needs = const {}}) => Recipe(
      slug: name.toLowerCase().replaceAll(' ', '-'),
      name: name,
      categories: [kind],
      pink: pink,
      blue: blue,
      ingredients: [for (final e in needs.entries) Ingredient(id: e.key.replaceAll(' ', '-'), name: e.key, amount: e.value, text: '${e.value} ${e.key}')],
    );

String show(List<Suggestion> list) => [for (final s in list) '${s.recipe.name}: ${s.why.join('; ')}'].join(' | ');

void main() {
  group('suggestions', () {
    test('favorites lead, and an untried recipe gets its turn ahead of a poor one', () {
      final pool = [recipe('Meh', pink: 1, blue: 1), recipe('Untried'), recipe('Loved', pink: 5, blue: 4), recipe('Hers', pink: 5, blue: 2)];
      expect(show(suggest(pool, names: {'pink': 'Alex', 'blue': 'Sam'})), "Loved: You both love it | Hers: Alex's pick | Untried: Not tried yet | Meh: ");
    });

    test('a recipe that uses what the week already buys moves up, and says so', () {
      final chili = recipe('Chili', needs: {'sour cream': '4 tablespoon', 'cheddar cheese': '1 cup', 'oil': '1 tablespoon', 'salt': 'to taste', 'butter': '1 tablespoon'});
      final pool = [
        chili,
        recipe('Plain', kind: 'Chicken', pink: 3, blue: 3, needs: {'oil': '2 tablespoon', 'salt': 'to taste', 'rice': '1 cup', 'butter': '2 tablespoon'}),
        recipe('Tostadas', kind: 'Chicken', pink: 3, blue: 2, needs: {'sour cream': '2 tablespoon', 'cheddar cheese': '1/2 cup', 'oil': '1 tablespoon'}),
      ];
      final ranked = suggest(pool, planned: [chili]);
      expect(show(ranked), 'Tostadas: Shares cheddar cheese, sour cream with this week; No chicken yet this week | Plain: No chicken yet this week');
      expect(ranked.map((s) => s.recipe.slug), isNot(contains('chili')), reason: 'already on the week');
    });

    test('a week that is already all beef pulls something else forward', () {
      final beef = [recipe('Chili'), recipe('Meatballs'), recipe('Tostadas')];
      final ranked = suggest([recipe('Burgers', pink: 4, blue: 4), recipe('Scampi', kind: 'Seafood', pink: 4, blue: 3)], planned: beef);
      expect(ranked.first.recipe.name, 'Scampi');
      expect(ranked.first.why, contains('No seafood yet this week'));
    });
  });

  test('search forgives a typo and a word half typed', () {
    final text = searchText(recipe('Beef & Zucchini Baked Penne', needs: {'ground beef': '10 ounce', 'zucchini': '1 unit', 'chicken stock': '1 unit'}));
    for (final q in ['zucchini', 'zuc', 'zuchini', 'zuchinni', 'zuchi', 'chiken', 'beaf', 'BEEF penne', 'baked  zuchini', 'groud beef', '']) {
      expect(searchMatches(text, q), isTrue, reason: q);
    }
    for (final q in ['shrimp', 'xyz', 'grnd', 'zucchini shrimp', 'pork']) {
      expect(searchMatches(text, q), isFalse, reason: q);
    }
  });

  test('a recipe list saved before kinds and ratings were kept is fetched again', () async {
    final ntfy = FakeNtfy();
    final store = MemoryStore();
    await store.writeJson('dp.recipes', {'at': thursday.millisecondsSinceEpoch, 'list': [{'slug': 'beef-chili', 'name': 'Beef Chili', 'categories': ['Beef'], 'ingredients': []}]});
    final model = AppModel(Session(store: store, client: ntfy.client(), notifier: SilentNotifier()), clock: () => thursday);
    await model.start();
    expect(model.recipes.single.tags, isEmpty);
    expect(model.session.recipesAt, isNull, reason: 'so the app refreshes when it opens');
    await model.refreshRecipes();
    final chili = model.recipes.firstWhere((r) => r.slug == 'beef-chili');
    expect(chili.tags, ['Spicy']);
    expect((chili.pink, chili.blue), (4, 5));
    final again = AppModel(Session(store: store, client: ntfy.client(), notifier: SilentNotifier()), clock: () => thursday);
    await again.start();
    expect(again.session.recipesAt, thursday);
    expect(again.recipes.firstWhere((r) => r.slug == 'beef-chili').blue, 5);
  });

  testWidgets('picking a dinner: suggestions, a kind, a misspelled search', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final ntfy = FakeNtfy()..recipesJson = File('../../data/runtime/recipes.runtime.json').readAsStringSync();
    final model = AppModel(Session(store: MemoryStore(), client: ntfy.client(), notifier: SilentNotifier()), clock: () => thursday);
    await model.start();
    await tester.pumpWidget(DinnerApp(model: model));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
    await model.setMe('blue');
    await model.refreshRecipes();
    await tester.pumpAndSettle();
    List<String> ideas() => [for (final e in find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('idea-') && w is ListTile).evaluate()) (e.widget.key! as ValueKey<String>).value.substring(5)];

    await tester.tap(find.byKey(const ValueKey('pick-tonight')));
    await tester.pumpAndSettle();
    expect(find.text('Good this week'), findsOneWidget);
    expect(find.text('All ${model.recipes.length} recipes'), findsOneWidget);
    final first = ideas();
    expect(first, [for (final s in model.suggestFor('2026-11-19', model.recipes).take(3)) s.recipe.slug]);
    await tester.tap(find.byKey(const ValueKey('idea-more')));
    await tester.pumpAndSettle();
    expect(ideas().toSet().intersection(first.toSet()), isEmpty);

    // One chip narrows both the suggestions and the list.
    // The chips are one row that scrolls sideways.
    // Find the row once: the chip it is found by scrolls out of view on the way.
    final chipRow = find.byWidget(tester.widget(find.ancestor(of: find.byKey(const ValueKey('kind-fav')), matching: find.byType(Scrollable)).first));
    await tester.scrollUntilVisible(find.byKey(const ValueKey('kind-Pasta')), 120, scrollable: chipRow);
    await tester.ensureVisible(find.byKey(const ValueKey('kind-Pasta')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('kind-Pasta')));
    await tester.pumpAndSettle();
    final pasta = model.recipes.where((r) => r.tags.contains('Pasta')).length;
    expect(find.text('$pasta of ${model.recipes.length} recipes'), findsOneWidget);
    expect(ideas().every((slug) => model.session.recipe(slug)!.tags.contains('Pasta')), isTrue);
    await tester.tap(find.byKey(const ValueKey('kind-Pasta')));
    await tester.pumpAndSettle();

    // Typing hides the suggestions and finds things despite the spelling.
    await tester.enterText(find.byType(TextField), 'zuchini baked');
    await tester.pumpAndSettle();
    expect(find.text('Good this week'), findsNothing);
    expect(find.byKey(const ValueKey('pick-beef-zucchini-baked-penne')), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('idea-${first.first}')));
    await tester.pumpAndSettle();
    expect(model.plan.meal('2026-11-19'), first.first);

    // The next day's suggestions know what tonight already buys.
    final tomorrow = model.suggestFor('2026-11-20', model.recipes);
    expect(tomorrow.map((s) => s.recipe.slug), isNot(contains(first.first)));
    expect(tomorrow.take(6).any((s) => s.why.any((w) => w.startsWith('Shares '))), isTrue);
    expect(tester.takeException(), isNull);
  });
}

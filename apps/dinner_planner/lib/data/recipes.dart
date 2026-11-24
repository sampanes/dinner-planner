// Recipes come from the recipe site's generated data file; the phone keeps
// only the fields it shows.

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/shopping.dart';

class Recipe {
  const Recipe({required this.slug, required this.name, this.image, this.categories = const [], this.tags = const [], this.pink = 0, this.blue = 0, this.ingredients = const [], this.steps = const [], this.minutes});

  final String slug;
  final String name;
  final String? image;

  /// The main thing in it ("Beef", "Veggie").
  final List<String> categories;

  /// The kind of dinner it is ("Tex-Mex", "Creamy").
  final List<String> tags;

  /// How each of the two rated it on the recipe site, 0 (not yet) to 5.
  final int pink;
  final int blue;
  final List<Ingredient> ingredients;

  /// What to do, one short piece at a time, numbered as the kitchen page
  /// numbers them ("Step 7 of 17").
  final List<String> steps;

  /// Start to table, when the recipe site knows.
  final int? minutes;

  /// The photo at list size. HelloFresh image urls carry their crop size.
  String? get thumb => image?.replaceFirst(RegExp(r'w_\d+,h_\d+'), 'w_300,h_200');

  Map<String, Object?> toJson() => {'slug': slug, 'name': name, 'image': image, 'categories': categories, 'tags': tags, 'sourceStars': {'pink': pink, 'blue': blue}, 'ingredients': [for (final i in ingredients) i.toJson()], 'steps': steps, 'minutes': ?minutes};

  static Recipe? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final slug = raw['slug'], name = raw['displayName'] ?? raw['name'];
    if (slug is! String || slug.isEmpty || name is! String) return null;
    List<String> texts(Object? list) => [
          if (list is List)
            for (final item in list)
              if (item is String) item else if (item is Map && item['text'] is String) item['text'] as String
        ];
    final stars = raw['sourceStars'];
    int star(String who) => stars is Map && stars[who] is num ? (stars[who] as num).round().clamp(0, 5) : 0;
    return Recipe(
      slug: slug,
      name: name,
      image: raw['image'] is String ? raw['image'] as String : null,
      categories: texts(raw['categories']),
      tags: texts(raw['tags']),
      pink: star('pink'),
      blue: star('blue'),
      ingredients: [
        if (raw['ingredients'] is List)
          for (final item in raw['ingredients'] as List) ?Ingredient.fromJson(item)
      ],
      steps: [
        if (raw['steps'] is List)
          for (final item in raw['steps'] as List)
            if (item is String) item else if (item is Map && item['displayText'] is String) item['displayText'] as String
      ],
      minutes: raw['minutes'] is num && (raw['minutes'] as num) > 0 ? (raw['minutes'] as num).round() : null,
    );
  }
}

List<Recipe> parseRecipes(String body) {
  final raw = jsonDecode(body);
  final list = raw is Map ? raw['recipes'] : raw;
  final out = <Recipe>[
    if (list is List)
      for (final item in list) ?Recipe.fromJson(item)
  ];
  out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

String _trim(String site) => site.replaceFirst(RegExp(r'/+$'), '');

Future<List<Recipe>> fetchRecipes(http.Client client, String site) async {
  final res = await client.get(Uri.parse('${_trim(site)}/data/runtime/recipes.runtime.json')).timeout(const Duration(seconds: 30));
  if (res.statusCode != 200) throw http.ClientException('The recipe site answered ${res.statusCode}');
  return parseRecipes(utf8.decode(res.bodyBytes));
}

/// The recipes in the site's current weekly plan, in order; empty when there
/// is no plan.
Future<List<String>> fetchKitchenPlan(http.Client client, String site) async {
  final res = await client.get(Uri.parse('${_trim(site)}/data/source/log.json')).timeout(const Duration(seconds: 30));
  if (res.statusCode != 200) throw http.ClientException('The recipe site answered ${res.statusCode}');
  final raw = jsonDecode(utf8.decode(res.bodyBytes));
  final plan = raw is Map ? raw['plan'] : null;
  final slugs = plan is Map ? plan['slugs'] : null;
  return [
    if (slugs is List)
      for (final s in slugs)
        if (s is String) s
  ];
}

/// The page that walks through a recipe step by step. "app=1" tells the page
/// it was opened from the phone app, so it offers "Note" on each step, which
/// comes back here ([noteLink]).
Uri kitchenPage(String site, String slug) => Uri.parse('${_trim(site)}/kitchen.html?app=1#/r/${Uri.encodeComponent(slug)}');

/// The topic the recipe site's own changes travel on (ratings, "we cooked
/// this"); the site's hourly job folds them into its data. Null when the site
/// names none.
Future<String?> fetchSiteTopic(http.Client client, String site) async {
  final res = await client.get(Uri.parse('${_trim(site)}/data/source/kitchen.json')).timeout(const Duration(seconds: 30));
  if (res.statusCode != 200) return null;
  final raw = jsonDecode(utf8.decode(res.bodyBytes));
  final topic = raw is Map ? raw['ntfyTopic'] : null;
  return topic is String && RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(topic) ? topic : null;
}

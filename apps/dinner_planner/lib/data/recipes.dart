// Recipes come from the recipe site's generated data file; the phone keeps
// only the fields it shows.

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/shopping.dart';

class Recipe {
  const Recipe({required this.slug, required this.name, this.image, this.categories = const [], this.ingredients = const []});

  final String slug;
  final String name;
  final String? image;
  final List<String> categories;
  final List<Ingredient> ingredients;

  /// The photo at list size. HelloFresh image urls carry their crop size.
  String? get thumb => image?.replaceFirst(RegExp(r'w_\d+,h_\d+'), 'w_300,h_200');

  Map<String, Object?> toJson() => {'slug': slug, 'name': name, 'image': image, 'categories': categories, 'ingredients': [for (final i in ingredients) i.toJson()]};

  static Recipe? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final slug = raw['slug'], name = raw['displayName'] ?? raw['name'];
    if (slug is! String || slug.isEmpty || name is! String) return null;
    List<String> texts(Object? list) => [
          if (list is List)
            for (final item in list)
              if (item is String) item else if (item is Map && item['text'] is String) item['text'] as String
        ];
    return Recipe(
      slug: slug,
      name: name,
      image: raw['image'] is String ? raw['image'] as String : null,
      categories: texts(raw['categories']),
      ingredients: [
        if (raw['ingredients'] is List)
          for (final item in raw['ingredients'] as List) ?Ingredient.fromJson(item)
      ],
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

/// The page that walks through a recipe step by step.
Uri kitchenPage(String site, String slug) => Uri.parse('${_trim(site)}/kitchen.html#/r/${Uri.encodeComponent(slug)}');

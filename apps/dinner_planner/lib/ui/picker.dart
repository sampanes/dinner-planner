import 'package:flutter/material.dart';

import '../app_model.dart';
import '../data/recipes.dart';
import '../data/suggest.dart';
import 'parts.dart';

/// The kinds of dinner, in the order the chips show them; anything else the
/// recipes carry comes after.
const List<String> _kindOrder = ['Kid-ready', 'Tex-Mex', 'Pasta', 'Cheesy', 'Creamy', 'Spicy', 'Handhelds', 'Bowls & soups', 'Asian', 'Beef', 'Chicken', 'Pork & sausage', 'Turkey', 'Seafood', 'Veggie'];

/// With fewer recipes than this there is nothing to suggest between.
const int _enoughToSuggest = 6;

/// A full-screen list to choose a dinner from: three suggestions for the
/// week as it stands, one row of chips to narrow by kind, and a search.
/// Pops with the recipe's slug, with '' to clear the day, or with null when
/// backed out of.
class RecipePicker extends StatefulWidget {
  const RecipePicker({super.key, required this.model, required this.title, this.day, this.current});

  final AppModel model;
  final String title;

  /// The day being chosen for, so the other days count as "already planned".
  final String? day;
  final String? current;

  static Future<String?> open(BuildContext context, AppModel model, {required String title, String? day, String? current}) =>
      Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => RecipePicker(model: model, title: title, day: day, current: current)));

  @override
  State<RecipePicker> createState() => _RecipePickerState();
}

class _RecipePickerState extends State<RecipePicker> {
  String _query = '';
  String? _kind;
  int _turn = 0;
  final Map<String, String> _text = {};

  bool _is(Recipe r, String kind) => switch (kind) {
        'fav' => r.pink + r.blue >= 8,
        'new' => r.pink + r.blue == 0,
        _ => r.tags.contains(kind) || r.categories.contains(kind),
      };

  List<(String, String)> _chips(List<Recipe> all) {
    final kinds = {for (final r in all) ...r.tags, for (final r in all) ...r.categories}.toList()
      ..sort((a, b) {
        final ia = _kindOrder.indexOf(a), ib = _kindOrder.indexOf(b);
        if (ia != ib) return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
        return a.compareTo(b);
      });
    final rated = all.any((r) => r.pink + r.blue > 0);
    return [
      if (all.any((r) => _is(r, 'fav'))) ('fav', 'Favorites'),
      if (rated && all.any((r) => _is(r, 'new'))) ('new', 'Not tried yet'),
      for (final k in kinds) (k, k),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final theme = Theme.of(context);
        final faded = theme.colorScheme.onSurfaceVariant;
        final all = model.recipes;
        final chips = _chips(all);
        final kind = chips.any((c) => c.$1 == _kind) ? _kind : null;
        final ofKind = [for (final r in all) if (kind == null || _is(r, kind)) r];
        final searching = _query.trim().isNotEmpty;
        final list = searching ? [for (final r in ofKind) if (searchMatches(_text.putIfAbsent(r.slug, () => searchText(r)), _query)) r] : ofKind;

        final ranked = !searching && all.length >= _enoughToSuggest ? model.suggestFor(widget.day, ofKind) : const <Suggestion>[];
        // "Show others" walks down the ranking three at a time, then starts over.
        final ideas = ranked.skip(ranked.isEmpty ? 0 : (_turn % (ranked.length / 3).ceil()) * 3).take(3).toList();

        Widget label(String text, {Widget? action}) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: faded))),
                  ?action,
                ],
              ),
            );
        Widget tile(Recipe r, {String? why}) => ListTile(
              key: ValueKey('${why == null ? 'pick' : 'idea'}-${r.slug}'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: RecipePhoto(url: r.thumb, width: 84, height: 56)),
              title: Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: why != null
                  ? Text(why, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.colorScheme.primary))
                  : (r.categories.isEmpty && r.tags.isEmpty ? null : Text([...r.categories, ...r.tags].join(', '), maxLines: 1, overflow: TextOverflow.ellipsis)),
              selected: r.slug == widget.current,
              onTap: () => Navigator.of(context).pop(r.slug),
            );

        return Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Name or ingredient', border: OutlineInputBorder()),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              if (chips.isNotEmpty)
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: chips.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => Center(
                      child: FilterChip(
                        key: ValueKey('kind-${chips[i].$1}'),
                        label: Text(chips[i].$2),
                        showCheckmark: false,
                        selected: kind == chips[i].$1,
                        onSelected: (on) => setState(() {
                          _kind = on ? chips[i].$1 : null;
                          _turn = 0;
                        }),
                      ),
                    ),
                  ),
                ),
              if (all.isEmpty)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: model.loadingRecipes
                          ? const CircularProgressIndicator()
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(model.recipeError == null ? 'No recipes yet.' : 'Could not load the recipes.', textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                FilledButton(onPressed: model.refreshRecipes, child: const Text('Try again')),
                              ],
                            ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    children: [
                      if (widget.current != null)
                        ListTile(
                          leading: const Icon(Icons.clear),
                          title: const Text('No dinner this day'),
                          onTap: () => Navigator.of(context).pop(''),
                        ),
                      if (ideas.isNotEmpty) ...[
                        label(
                          'Good this week',
                          action: ranked.length > 3 ? TextButton(key: const ValueKey('idea-more'), onPressed: () => setState(() => _turn++), child: const Text('Show others')) : null,
                        ),
                        for (final s in ideas) tile(s.recipe, why: s.why.isEmpty ? 'Worth a turn' : s.why.take(2).join(' · ')),
                        label(kind == null ? 'All ${all.length} recipes' : '${ofKind.length} of ${all.length} recipes'),
                      ],
                      for (final r in list) tile(r),
                      if (list.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Nothing matches.'))),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Opens the picker for [day] and applies the choice.
Future<void> pickDinner(BuildContext context, AppModel model, String day, String title) async {
  final choice = await RecipePicker.open(context, model, title: title, day: day, current: model.plan.meal(day));
  if (choice == null) return;
  await model.setMeal(day, choice.isEmpty ? null : choice);
}

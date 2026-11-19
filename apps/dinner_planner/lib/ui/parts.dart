// Pieces the screens share.

import 'package:flutter/material.dart';

import '../app_model.dart';
import '../core/plan.dart';
import '../data/recipes.dart';

const Map<String, Color> personColors = {'pink': Color(0xFFD6497F), 'blue': Color(0xFF2F7FC1)};

/// A recipe photo that stays a tidy box while loading or when offline.
class RecipePhoto extends StatelessWidget {
  const RecipePhoto({super.key, required this.url, this.width, this.height});

  final String? url;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final blank = Container(
      width: width,
      height: height,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.restaurant, color: Theme.of(context).colorScheme.outline),
    );
    final src = url;
    if (src == null) return blank;
    return Image.network(
      src,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => blank,
      loadingBuilder: (_, child, progress) => progress == null ? child : blank,
    );
  }
}

/// Two chips, one per person. Tapping the chosen one clears it.
class CookPicker extends StatelessWidget {
  const CookPicker({super.key, required this.model, required this.day, this.compact = false});

  final AppModel model;
  final String day;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cook = model.plan.cook(day);
    return Wrap(
      spacing: 8,
      children: [
        for (final who in people)
          ChoiceChip(
            key: ValueKey('cook-$day-$who'),
            label: Text(compact ? model.plan.name(who).characters.first.toUpperCase() : model.plan.name(who)),
            tooltip: '${model.plan.name(who)} cooks',
            selected: cook == who,
            showCheckmark: !compact,
            selectedColor: personColors[who]!.withValues(alpha: 0.28),
            side: BorderSide(color: personColors[who]!.withValues(alpha: cook == who ? 0.9 : 0.4)),
            onSelected: (_) => model.setCook(day, cook == who ? null : who),
          ),
      ],
    );
  }
}

/// A full-screen list to choose a dinner from. Pops with the recipe's slug,
/// with '' to clear the day, or with null when backed out of.
class RecipePicker extends StatefulWidget {
  const RecipePicker({super.key, required this.model, required this.title, this.current});

  final AppModel model;
  final String title;
  final String? current;

  static Future<String?> open(BuildContext context, AppModel model, {required String title, String? current}) =>
      Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => RecipePicker(model: model, title: title, current: current)));

  @override
  State<RecipePicker> createState() => _RecipePickerState();
}

class _RecipePickerState extends State<RecipePicker> {
  String _query = '';

  bool _matches(Recipe r) {
    final words = _query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final hay = '${r.name} ${r.categories.join(' ')} ${r.ingredients.map((i) => i.text).join(' ')}'.toLowerCase();
    return words.every(hay.contains);
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final list = model.recipes.where(_matches).toList();
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
              if (model.recipes.isEmpty)
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
                      for (final r in list)
                        ListTile(
                          key: ValueKey('pick-${r.slug}'),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: RecipePhoto(url: r.thumb, width: 84, height: 56)),
                          title: Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: r.categories.isEmpty ? null : Text(r.categories.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis),
                          selected: r.slug == widget.current,
                          onTap: () => Navigator.of(context).pop(r.slug),
                        ),
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
  final choice = await RecipePicker.open(context, model, title: title, current: model.plan.meal(day));
  if (choice == null) return;
  await model.setMeal(day, choice.isEmpty ? null : choice);
}

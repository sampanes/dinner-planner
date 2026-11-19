import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_model.dart';
import '../core/plan.dart';
import '../core/sync_core.dart';
import '../data/recipes.dart';
import 'parts.dart';

class TonightScreen extends StatelessWidget {
  const TonightScreen({super.key, required this.model, required this.onOpenWeek});

  final AppModel model;
  final VoidCallback onOpenWeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = model.now;
    final day = model.today();
    final me = model.me;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text('${weekdayName(now)}, ${monthDay(now)}', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(_headline(day), style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        if (me == null) _WhoAreYou(model: model) else _TonightCard(model: model, day: day),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: Text('Coming up', style: theme.textTheme.titleLarge)),
            TextButton(onPressed: onOpenWeek, child: const Text('Plan the week')),
          ],
        ),
        for (var i = 1; i <= 4; i++) _UpcomingRow(model: model, date: dayAfter(now, i)),
        const SizedBox(height: 16),
        _ShareLine(model: model),
      ],
    );
  }

  String _headline(String day) {
    final cook = model.plan.cook(day);
    if (model.me == null) return 'Dinner tonight';
    if (cook == null) return 'Who cooks tonight?';
    return cook == model.me ? "You're cooking tonight" : '${model.plan.name(cook)} is cooking tonight';
  }
}

class _WhoAreYou extends StatelessWidget {
  const _WhoAreYou({required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Whose phone is this?', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('Reminders go to the person who is cooking. You can change the names in Settings.'),
            const SizedBox(height: 16),
            for (final who in people)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.tonal(
                  key: ValueKey('me-$who'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  onPressed: () async {
                    await model.setMe(who);
                    await model.allowNotifications();
                  },
                  child: Text(model.plan.name(who), style: const TextStyle(fontSize: 18)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TonightCard extends StatelessWidget {
  const _TonightCard({required this.model, required this.day});

  final AppModel model;
  final String day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slug = model.plan.meal(day);
    final Recipe? recipe = model.session.recipe(slug);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (slug != null) AspectRatio(aspectRatio: 3 / 2, child: RecipePhoto(url: recipe?.image)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  slug == null ? 'Nothing is planned for tonight' : model.session.recipeName(slug),
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Cooking:', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(width: 12),
                    Expanded(child: CookPicker(model: model, day: day)),
                  ],
                ),
                const SizedBox(height: 16),
                if (slug != null)
                  FilledButton.icon(
                    key: const ValueKey('open-kitchen'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Open the recipe', style: TextStyle(fontSize: 18)),
                    onPressed: () => launchUrl(kitchenPage(model.site, slug), mode: LaunchMode.externalApplication),
                  ),
                if (recipe != null && recipe.ingredients.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const ValueKey('needs-tonight'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => showNeeds(context, model, recipe, 'Tonight'),
                    child: const Text('What it needs'),
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const ValueKey('pick-tonight'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () => pickDinner(context, model, day, 'Dinner tonight'),
                  child: Text(slug == null ? 'Pick dinner' : 'Change dinner'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({required this.model, required this.date});

  final AppModel model;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = dayText(date);
    final slug = model.plan.meal(day);
    final cook = model.plan.cook(day);
    final mine = cook != null && cook == model.me;
    final recipe = model.session.recipe(slug);
    return ListTile(
      key: ValueKey('upcoming-$day'),
      contentPadding: EdgeInsets.zero,
      onTap: recipe == null ? null : () => showNeeds(context, model, recipe, weekdayName(date)),
      leading: CircleAvatar(
        backgroundColor: cook == null ? theme.colorScheme.surfaceContainerHighest : personColors[cook]!.withValues(alpha: 0.28),
        child: Text(cook == null ? '?' : model.plan.name(cook).characters.first.toUpperCase()),
      ),
      title: Text(slug == null ? 'Nothing planned' : model.session.recipeName(slug), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${weekdayName(date)}${cook == null ? '' : mine ? ', you cook' : ', ${model.plan.name(cook)} cooks'}',
        style: mine ? TextStyle(fontWeight: FontWeight.w700, color: theme.colorScheme.primary) : null,
      ),
    );
  }
}

class _ShareLine extends StatelessWidget {
  const _ShareLine({required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String text;
    if (model.household == null) {
      text = 'Only on this phone. Share it from Settings.';
    } else if (model.syncError != null) {
      text = 'Could not reach the other phone just now. Changes are kept and sent later.';
    } else if (model.otherPhones == 0) {
      text = 'Shared, waiting for the other phone to join.';
    } else {
      text = model.inStep ? 'Both phones show the same plan.' : 'Catching up with the other phone.';
    }
    return Text(text, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant));
  }
}

/// A sheet listing what a dinner needs, for checking the fridge the evening
/// before.
Future<void> showNeeds(BuildContext context, AppModel model, Recipe recipe, String when) {
  final theme = Theme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        // Clear of the system's buttons, which are drawn over the sheet.
        padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          Text(when, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text(recipe.name, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          for (final line in recipe.ingredients)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(line, style: theme.textTheme.titleMedium),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Open the recipe'),
            onPressed: () => launchUrl(kitchenPage(model.site, recipe.slug), mode: LaunchMode.externalApplication),
          ),
        ],
      ),
    ),
  );
}

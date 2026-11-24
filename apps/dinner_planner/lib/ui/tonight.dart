import 'package:flutter/material.dart';

import '../app_model.dart';
import '../core/nudges.dart';
import '../core/plan.dart';
import '../core/sync_core.dart';
import '../data/recipes.dart';
import 'parts.dart';

class TonightScreen extends StatelessWidget {
  const TonightScreen({super.key, required this.model, required this.onOpen});

  final AppModel model;

  /// Switches to another tab, by its place in the bar.
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = model.now;
    final day = model.today();
    final me = model.me;
    final off = model.plan.off(day);
    final start = me != null && !model.startHidden && model.startDone.length < StartStep.values.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text('${weekdayName(now)}, ${monthDay(now)}', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(_headline(day), style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        if (me == null)
          _WhoAreYou(model: model)
        else if (off != null)
          _OffCard(model: model, day: day, off: off)
        else
          _TonightCard(model: model, day: day),
        // Under tonight's dinner, which stays the first thing on the screen.
        if (start) ...[const SizedBox(height: 12), _StartHere(model: model, onOpen: onOpen)],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: Text('Coming up', style: theme.textTheme.titleLarge)),
            TextButton(onPressed: () => onOpen(1), child: const Text('Plan the week')),
          ],
        ),
        for (var i = 1; i <= 4; i++) _UpcomingRow(model: model, date: dayAfter(now, i)),
        const SizedBox(height: 16),
        _ShareLine(model: model),
      ],
    );
  }

  String _headline(String day) {
    final off = model.plan.off(day);
    if (off != null) return '${offKinds[off]} tonight';
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

/// Each first step: what to do, why, and the tab it happens on.
const Map<StartStep, ({String title, String why, int tab})> _startSteps = {
  StartStep.plan: (title: 'Pick a dinner and who cooks it', why: 'The cook gets the reminders, and what it needs goes on the list.', tab: 1),
  StartStep.stores: (title: 'Add the stores you shop at', why: 'The list sorts itself for each one.', tab: 2),
  StartStep.scan: (title: 'Scan a packet from your kitchen', why: 'Say once what it is. After that, scanning it ticks it off the list.', tab: 2),
  StartStep.walk: (title: 'Tick the list as you walk a store', why: 'Tap its name first, and the list learns your route.', tab: 2),
  StartStep.share: (title: 'Share with the other phone', why: 'One plan and one list for both of you.', tab: 3),
};

/// The first steps as a list that ticks itself. The next one says why it is
/// worth doing; tapping a step opens where it happens.
class _StartHere extends StatelessWidget {
  const _StartHere({required this.model, required this.onOpen});

  final AppModel model;
  final ValueChanged<int> onOpen;

  void _skip(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    model.hideStart(true);
    say(messenger, 'Hidden. Settings can bring it back.', () => model.hideStart(false));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faded = theme.colorScheme.onSurfaceVariant;
    final done = model.startDone;
    final next = StartStep.values.firstWhere((s) => !done.contains(s));
    return Card.outlined(
      key: const ValueKey('start-here'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
              child: Row(
                children: [
                  Expanded(child: Text('Start here', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                  Text('${done.length} of ${StartStep.values.length}', style: theme.textTheme.bodySmall?.copyWith(color: faded)),
                  TextButton(key: const ValueKey('start-skip'), onPressed: () => _skip(context), child: const Text('Skip')),
                ],
              ),
            ),
            for (final step in StartStep.values)
              ListTile(
                key: ValueKey('start-${step.name}'),
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: done.contains(step)
                    ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                    : Icon(Icons.radio_button_unchecked, color: step == next ? theme.colorScheme.primary : faded),
                title: Text(
                  _startSteps[step]!.title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: done.contains(step) ? faded : null,
                    fontWeight: step == next ? FontWeight.w600 : null,
                  ),
                ),
                subtitle: step == next ? Text(_startSteps[step]!.why) : null,
                trailing: step == next ? const Icon(Icons.chevron_right) : null,
                onTap: done.contains(step) ? null : () => onOpen(_startSteps[step]!.tab),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tonight was called off: what it is instead, and the way back.
class _OffCard extends StatelessWidget {
  const _OffCard({required this.model, required this.day, required this.off});

  final AppModel model;
  final String day;
  final String off;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('tonight-off'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nobody is cooking tonight.', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('No reminders, and nothing on the list for tonight.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            OutlinedButton(
              key: const ValueKey('cook-after-all'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => model.cookAfterAll(day),
              child: const Text('Cooking after all'),
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
    final faded = theme.colorScheme.onSurfaceVariant;
    final slug = model.plan.meal(day);
    final Recipe? recipe = model.session.recipe(slug);
    final minutes = recipe?.minutes;
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
                if (minutes != null && !model.afterDinner) ...[
                  const SizedBox(height: 4),
                  Text(
                    'About $minutes minutes. Start by ${clockText(startMinutes(model.times, minutes))}.',
                    key: const ValueKey('tonight-timing'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: faded),
                  ),
                ],
                if (slug != null && model.afterDinner) ...[const SizedBox(height: 4), _RateRow(model: model, slug: slug)],
                if (slug != null) ...[const SizedBox(height: 8), RecipeNotes(model: model, slug: slug)],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Cooking:', style: theme.textTheme.titleMedium?.copyWith(color: faded)),
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
                    onPressed: () => model.openRecipe(slug),
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
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('pick-tonight'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        onPressed: () => pickDinner(context, model, day, 'Dinner tonight'),
                        child: Text(slug == null ? 'Pick dinner' : 'Change dinner'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('not-tonight'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        onPressed: () => showSkip(context, model, day),
                        child: const Text('Not tonight'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "How was it?", once dinner time has come: five stars, one tap. The answer
/// goes to the recipe site, where it steers what gets suggested.
class _RateRow extends StatelessWidget {
  const _RateRow({required this.model, required this.slug});

  final AppModel model;
  final String slug;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final said = model.ratedToday(slug);
    final stars = said ? model.myStars(slug) : 0;
    return Row(
      key: const ValueKey('rate-row'),
      children: [
        Expanded(child: Text(said ? 'Your stars tonight' : 'How was it?', style: theme.textTheme.titleMedium)),
        for (var n = 1; n <= 5; n++)
          IconButton(
            key: ValueKey('rate-$n'),
            tooltip: '$n star${n == 1 ? '' : 's'}',
            visualDensity: VisualDensity.compact,
            icon: Icon(n <= stars ? Icons.star : Icons.star_border, color: n <= stars ? theme.colorScheme.primary : theme.colorScheme.outline),
            onPressed: () => model.rate(slug, n),
          ),
      ],
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
    final off = model.plan.off(day);
    final mine = cook != null && cook == model.me;
    final recipe = model.session.recipe(slug);
    return ListTile(
      key: ValueKey('upcoming-$day'),
      contentPadding: EdgeInsets.zero,
      onTap: recipe == null ? null : () => showNeeds(context, model, recipe, weekdayName(date)),
      leading: CircleAvatar(
        backgroundColor: cook == null ? theme.colorScheme.surfaceContainerHighest : personColors[cook]!.withValues(alpha: 0.28),
        child: Text(cook == null ? (off == null ? '?' : '-') : model.plan.name(cook).characters.first.toUpperCase()),
      ),
      title: Text(slug != null ? model.session.recipeName(slug) : (off == null ? 'Nothing planned' : offKinds[off]!), maxLines: 1, overflow: TextOverflow.ellipsis),
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

/// "Not tonight": one tap says what tonight is instead. The planned dinner
/// moves to the next free night, with what was ticked for it, and the change
/// can be undone from the message that follows.
Future<void> showSkip(BuildContext context, AppModel model, String day) async {
  final theme = Theme.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final slug = model.plan.meal(day);
  final to = model.movesTo(day);
  final String lead;
  if (slug == null) {
    lead = 'What is tonight instead?';
  } else if (to == null) {
    lead = '${model.session.recipeName(slug)} comes off the plan: the next two weeks are full. What is tonight instead?';
  } else {
    lead = '${model.session.recipeName(slug)} moves to ${dayLabel(parseDay(to)!, model.now)}, with what is ticked for it. What is tonight instead?';
  }
  const kinds = {'leftovers': (Icons.kitchen_outlined, 'Leftovers'), 'out': (Icons.storefront_outlined, 'Eating out'), 'skip': (Icons.bedtime_outlined, 'Just not cooking')};
  final why = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Not tonight', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(lead, key: const ValueKey('skip-lead'), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          for (final k in kinds.entries)
            ListTile(
              key: ValueKey('skip-${k.key}'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: Icon(k.value.$1),
              title: Text(k.value.$2, style: theme.textTheme.titleMedium),
              onTap: () => Navigator.of(context).pop(k.key),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (why == null) return;
  final done = await model.skipDinner(day, why);
  say(messenger, done.text, done.undo);
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
      // Rebuilt when the note changes, which happens while the sheet is open.
      builder: (context, scroll) => ListenableBuilder(
        listenable: model,
        builder: (context, _) => ListView(
          controller: scroll,
          // Clear of the system's buttons, which are drawn over the sheet.
          padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.paddingOf(context).bottom),
          children: [
            Text(when, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            Text(recipe.name, style: theme.textTheme.headlineSmall),
            if (recipe.minutes != null) Text('About ${recipe.minutes} minutes', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            RecipeNotes(model: model, slug: recipe.slug),
            const SizedBox(height: 12),
            for (final line in recipe.ingredients.map((i) => i.text))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(line, style: theme.textTheme.titleMedium),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Open the recipe'),
              onPressed: () => model.openRecipe(recipe.slug),
            ),
          ],
        ),
      ),
    ),
  );
}

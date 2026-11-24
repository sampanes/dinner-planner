import 'package:flutter/material.dart';

import '../app_model.dart';
import '../core/plan.dart';
import '../core/sync_core.dart';
import '../data/autoplan.dart';
import 'parts.dart';

class WeekScreen extends StatelessWidget {
  const WeekScreen({super.key, required this.model});

  final AppModel model;

  Future<void> _fill(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    String text;
    try {
      final n = await model.fillFromKitchenPlan();
      text = n == 0 ? 'Nothing to add: the kitchen plan is empty or already here.' : 'Added $n dinner${n == 1 ? '' : 's'} from the kitchen plan.';
    } on Exception {
      text = 'Could not read the kitchen plan.';
    }
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = model.now;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Row(
          children: [
            Expanded(child: Text('The next two weeks', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
            IconButton(
              key: const ValueKey('fill-week'),
              tooltip: 'Add dinners from the kitchen plan',
              icon: const Icon(Icons.playlist_add),
              onPressed: () => _fill(context),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text('Tap a day to pick dinner. Tap a name to say who cooks.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        if (model.emptyNights >= 2 && model.recipes.isNotEmpty) ...[
          FilledButton.tonalIcon(
            key: const ValueKey('draft-week'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.auto_awesome),
            label: Text('Fill the ${model.emptyNights} empty nights this week'),
            onPressed: () => showDraft(context, model),
          ),
          const SizedBox(height: 12),
        ],
        for (var i = 0; i < 14; i++) _DayCard(model: model, date: dayAfter(now, i), first: i == 0),
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.model, required this.date, required this.first});

  final AppModel model;
  final DateTime date;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = dayText(date);
    final slug = model.plan.meal(day);
    final off = model.plan.off(day);
    final mine = model.me != null && model.plan.cook(day) == model.me;
    return Card(
      key: ValueKey('day-$day'),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: mine ? BorderSide(color: theme.colorScheme.primary, width: 2) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => pickDinner(context, model, day, '${weekdayName(date)}, ${monthDay(date)}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      first ? 'Today' : '${weekdayName(date)}, ${monthDay(date)}',
                      style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      slug != null ? model.session.recipeName(slug) : (off == null ? 'Pick dinner' : offKinds[off]!),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(color: slug == null ? theme.colorScheme.outline : null),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CookPicker(model: model, day: day, compact: true),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows a drafted week: a dinner and a cook for each empty night. A night
/// can be swapped for another recipe or dropped; one button takes the rest.
Future<void> showDraft(BuildContext context, AppModel model) async {
  final messenger = ScaffoldMessenger.of(context);
  final nights = model.draft();
  if (nights.isEmpty) {
    say(messenger, 'Nothing to fill: the coming week is planned.');
    return;
  }
  final chosen = await showModalBottomSheet<List<DraftNight>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _DraftSheet(model: model, nights: nights),
  );
  if (chosen == null || chosen.isEmpty) return;
  final done = await model.useDraft(chosen);
  if (done != null) say(messenger, done.text, done.undo);
}

class _DraftSheet extends StatefulWidget {
  const _DraftSheet({required this.model, required this.nights});

  final AppModel model;
  final List<DraftNight> nights;

  @override
  State<_DraftSheet> createState() => _DraftSheetState();
}

class _DraftSheetState extends State<_DraftSheet> {
  late final List<DraftNight> _nights = List.of(widget.nights);

  Future<void> _swap(DraftNight night) async {
    final model = widget.model;
    final slug = await RecipePicker.open(context, model, title: '${weekdayName(night.date)}, ${monthDay(night.date)}', day: night.day);
    if (slug == null || slug.isEmpty || !mounted) return;
    setState(() {
      night.slug = slug;
      night.why = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final model = widget.model;
    final faded = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsets.fromLTRB(0, 0, 0, 16 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('The coming week', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('Picked to share what they buy and not repeat the last two weeks. Tap one to swap it.', style: theme.textTheme.bodyMedium?.copyWith(color: faded)),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final n in _nights)
                  ListTile(
                    key: ValueKey('draft-${n.day}'),
                    contentPadding: const EdgeInsets.fromLTRB(20, 2, 8, 2),
                    leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: RecipePhoto(url: model.session.recipe(n.slug)?.thumb, width: 72, height: 48)),
                    title: Text(model.session.recipeName(n.slug), maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text([weekdayName(n.date), if (n.cook != null) '${model.plan.name(n.cook!)} cooks'].join(' · '), style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                        if (n.why.isNotEmpty) Text(n.why, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                    trailing: IconButton(
                      key: ValueKey('draft-drop-${n.day}'),
                      tooltip: 'Leave this night empty',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _nights.remove(n)),
                    ),
                    onTap: () => _swap(n),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: FilledButton(
              key: const ValueKey('draft-use'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _nights.isEmpty ? null : () => Navigator.of(context).pop(_nights),
              child: Text(_nights.isEmpty ? 'Nothing left to plan' : 'Use these ${_nights.length} dinner${_nights.length == 1 ? '' : 's'}'),
            ),
          ),
        ],
      ),
    );
  }
}

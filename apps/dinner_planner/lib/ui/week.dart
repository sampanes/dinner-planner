import 'package:flutter/material.dart';

import '../app_model.dart';
import '../core/plan.dart';
import '../core/sync_core.dart';
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
                      slug == null ? 'Pick dinner' : model.session.recipeName(slug),
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

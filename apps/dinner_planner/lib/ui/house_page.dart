import 'package:flutter/material.dart';

import '../app_model.dart';
import '../core/store_order.dart';

/// "What's in the house": everything the recipes use, by section, to tap on
/// or off. Ticks on the shopping list keep it up from day to day; this page
/// is for the first walk round the kitchen, and for putting the app right
/// when it has guessed wrong.
class HousePage extends StatelessWidget {
  const HousePage({super.key, required this.model});

  final AppModel model;

  static Future<void> open(BuildContext context, AppModel model) =>
      Navigator.of(context).push<void>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => HousePage(model: model)));

  static String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: model,
        builder: (context, _) {
          final theme = Theme.of(context);
          final faded = theme.colorScheme.onSurfaceVariant;
          final groups = model.houseItems;
          final count = [for (final g in groups) ...g.items.where((i) => i.here)].length;
          return Scaffold(
            appBar: AppBar(title: const Text("What's in the house")),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                Text(
                  'Tap what is in the kitchen right now. Both phones see it. From here on, ticking the shopping list keeps it up, and the app lets fresh things go after a few days.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: faded),
                ),
                const SizedBox(height: 8),
                Text(count == 0 ? 'Nothing marked yet.' : '$count marked as here.', key: const ValueKey('house-count'), style: theme.textTheme.titleSmall),
                for (final g in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 18, 0, 6),
                    child: Text(sections[g.section] ?? g.section, style: theme.textTheme.titleMedium?.copyWith(color: faded)),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final i in g.items)
                        FilterChip(
                          key: ValueKey('house-${i.id}'),
                          label: Text(_cap(i.name)),
                          selected: i.here,
                          onSelected: (on) => model.setHere(i.id, on),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                Text('Salt, oil, butter and the like are under "Always in the house" on the shopping list.', style: theme.textTheme.bodySmall?.copyWith(color: faded)),
              ],
            ),
          );
        },
      );
}

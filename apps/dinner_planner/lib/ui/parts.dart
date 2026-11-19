// Pieces the screens share.

import 'package:flutter/material.dart';

import '../app_model.dart';
import '../core/plan.dart';

export 'picker.dart';

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

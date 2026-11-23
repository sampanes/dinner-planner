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

/// The household's note on a recipe ("add parmesan at the end"), tap to
/// change it; or, with no note yet, a button to write one. Notes are shared
/// like the plan: the other phone and a linked kitchen screen see them.
class RecipeNote extends StatelessWidget {
  const RecipeNote({super.key, required this.model, required this.slug});

  final AppModel model;
  final String slug;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = model.plan.note(slug);
    if (note == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: ValueKey('note-add-$slug'),
          icon: const Icon(Icons.edit_note),
          label: const Text('Add a note'),
          onPressed: () => editNote(context, model, slug),
        ),
      );
    }
    return Material(
      color: theme.colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey('note-$slug'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => editNote(context, model, slug),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.sticky_note_2_outlined, color: theme.colorScheme.onSecondaryContainer),
              const SizedBox(width: 10),
              Expanded(child: Text(note, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSecondaryContainer))),
              Icon(Icons.edit, size: 18, color: theme.colorScheme.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for the note on a recipe and saves it; an empty note clears it.
Future<void> editNote(BuildContext context, AppModel model, String slug) async {
  final text = await showDialog<String>(
    context: context,
    builder: (context) => _NoteDialog(title: model.session.recipeName(slug), start: model.plan.note(slug) ?? ''),
  );
  if (text != null) await model.setNote(slug, text);
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.title, required this.start});

  final String title;
  final String start;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final TextEditingController _text = TextEditingController(text: widget.start);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('note-field'),
        controller: _text,
        autofocus: true,
        minLines: 2,
        maxLines: 6,
        maxLength: noteMax,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Add parmesan at the end',
          helperText: 'The other phone and the kitchen screen see it too.',
          helperMaxLines: 2,
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        if (widget.start.isNotEmpty)
          TextButton(key: const ValueKey('note-clear'), onPressed: () => Navigator.pop(context, ''), child: const Text('Delete')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(key: const ValueKey('note-save'), onPressed: () => Navigator.pop(context, _text.text), child: const Text('Save')),
      ],
    );
  }
}

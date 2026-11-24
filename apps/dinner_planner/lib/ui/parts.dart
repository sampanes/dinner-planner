// Pieces the screens share.

import 'package:flutter/material.dart';

import '../app_model.dart';
import '../core/plan.dart';

export 'picker.dart';

const Map<String, Color> personColors = {'pink': Color(0xFFD6497F), 'blue': Color(0xFF2F7FC1)};

/// Says what was just done in a bar at the bottom, with Undo when it can be
/// taken back. It leaves on its own.
void say(ScaffoldMessengerState messenger, String text, [Future<void> Function()? undo]) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      persist: false,
      action: undo == null ? null : SnackBarAction(label: 'Undo', onPressed: () => undo()),
    ));
}

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

/// What the household wrote on a recipe: "add parmesan at the end" on the
/// whole recipe, or "garlic salt goes in here" on one step. Tap a note to
/// change it; the button adds another. Notes are shared like the plan: the
/// other phone, a linked kitchen screen and scripts/house_notes.py on a
/// computer see them, and they stay until someone deletes them or the recipe
/// is fixed at the computer.
class RecipeNotes extends StatelessWidget {
  const RecipeNotes({super.key, required this.model, required this.slug});

  final AppModel model;
  final String slug;

  @override
  Widget build(BuildContext context) {
    final steps = model.session.recipe(slug)?.steps ?? const <String>[];
    final ids = [for (final s in steps) stepId(s)];
    // Where a note sits: -1 the whole recipe, then its step, then steps that
    // have been rewritten since.
    int place(NoteLine n) {
      if (n.step == null) return -1;
      final i = ids.indexOf(n.step!);
      return i < 0 ? steps.length : i;
    }

    final notes = model.plan.notes(slug);
    final order = {for (var i = 0; i < notes.length; i++) notes[i].key: i};
    notes.sort((a, b) {
      final c = place(a).compareTo(place(b));
      return c != 0 ? c : order[a.key]!.compareTo(order[b.key]!);
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final n in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _NoteTile(note: n, where: _where(n, place(n), steps), onTap: () => editNote(context, model, n)),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: ValueKey('note-add-$slug'),
            icon: const Icon(Icons.edit_note),
            label: Text(notes.isEmpty ? 'Add a note' : 'Add another note'),
            onPressed: () => addNote(context, model, slug),
          ),
        ),
      ],
    );
  }

  /// The line above a note on a step, saying which step.
  static String? _where(NoteLine n, int place, List<String> steps) {
    if (n.step == null) return null;
    if (place < steps.length) return 'Step ${place + 1}: ${steps[place]}';
    return n.anchor == null ? 'A step that has changed since' : 'A step that has changed since: ${n.anchor}';
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note, required this.where, required this.onTap});

  final NoteLine note;
  final String? where;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSecondaryContainer;
    return Material(
      color: theme.colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey(note.step == null ? 'note-${note.slug}' : 'note-${note.slug}-${note.step}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.sticky_note_2_outlined, color: ink),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (where != null)
                      Text(where!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: ink.withValues(alpha: 0.75))),
                    Text(note.text, style: theme.textTheme.bodyLarge?.copyWith(color: ink)),
                  ],
                ),
              ),
              Icon(Icons.edit, size: 18, color: ink),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for a new note on a recipe: what it says and, when the recipe's steps
/// are known, which step it is about. Choosing a place that already has a
/// note changes that note.
Future<void> addNote(BuildContext context, AppModel model, String slug) async {
  final steps = model.session.recipe(slug)?.steps ?? const <String>[];
  final ids = [for (final s in steps) stepId(s)];
  final there = <int, String>{};
  for (final n in model.plan.notes(slug)) {
    final at = n.step == null ? -1 : ids.indexOf(n.step!);
    if (n.step == null || at >= 0) there[at] = n.text;
  }
  final made = await showDialog<({int place, String text})>(
    context: context,
    builder: (context) => _NoteDialog(title: model.session.recipeName(slug), steps: steps, there: there),
  );
  if (made != null) await model.setNote(slug, made.text, step: made.place < 0 ? null : steps[made.place]);
}

/// Asks for new words for a note that is already there; none deletes it.
Future<void> editNote(BuildContext context, AppModel model, NoteLine note) async {
  final steps = model.session.recipe(note.slug)?.steps ?? const <String>[];
  final at = note.step == null ? -1 : [for (final s in steps) stepId(s)].indexOf(note.step!);
  final made = await showDialog<({int place, String text})>(
    context: context,
    builder: (context) => _NoteDialog(
      title: model.session.recipeName(note.slug),
      steps: steps,
      there: {at: note.text},
      fixed: at,
      fixedLine: note.step == null
          ? null
          : at >= 0
              ? 'Step ${at + 1}: ${steps[at]}'
              : 'A step that has changed since${note.anchor == null ? '' : ': ${note.anchor}'}',
    ),
  );
  if (made != null) await model.changeNote(note, made.text);
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.title, required this.steps, required this.there, this.fixed, this.fixedLine});

  final String title;
  final List<String> steps;

  /// The notes already on the recipe, by place: -1 the whole recipe, else the
  /// step's position.
  final Map<int, String> there;

  /// Set when changing one note: its place cannot be moved.
  final int? fixed;
  final String? fixedLine;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late int _place = widget.fixed ?? -1;
  late final TextEditingController _text = TextEditingController(text: widget.there[_place] ?? '');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _pick(int place) {
    final had = widget.there[_place] ?? '';
    setState(() {
      // What was typed moves with the choice; a note already at the new place
      // shows only when nothing was typed.
      if (_text.text.trim().isEmpty || _text.text == had) _text.text = widget.there[place] ?? '';
      _place = place;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faded = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final choosing = widget.fixed == null && widget.steps.isNotEmpty;
    final onStep = _place >= 0 || widget.fixedLine != null;
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (choosing) ...[
              Text('What is it about?', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 2,
                children: [
                  ChoiceChip(
                    key: const ValueKey('note-place-all'),
                    label: const Text('The whole recipe'),
                    selected: _place < 0,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => _pick(-1),
                  ),
                  for (var i = 0; i < widget.steps.length; i++)
                    ChoiceChip(
                      key: ValueKey('note-place-${i + 1}'),
                      label: Text('${i + 1}'),
                      tooltip: 'Step ${i + 1}',
                      selected: _place == i,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _pick(i),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _place < 0 ? 'Or tap the number of the step it belongs to.' : 'Step ${_place + 1}: ${widget.steps[_place]}',
                key: const ValueKey('note-place-text'),
                style: faded,
              ),
              const SizedBox(height: 12),
            ],
            if (widget.fixedLine != null) ...[
              Text(widget.fixedLine!, style: faded),
              const SizedBox(height: 12),
            ],
            TextField(
              key: const ValueKey('note-field'),
              controller: _text,
              autofocus: true,
              minLines: 2,
              maxLines: 6,
              maxLength: onStep ? stepNoteMax : noteMax,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: onStep ? 'Garlic salt goes in here' : 'Add parmesan at the end',
                helperText: 'The other phone and the kitchen screen see it too.',
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.there.containsKey(_place))
          TextButton(key: const ValueKey('note-clear'), onPressed: () => Navigator.pop(context, (place: _place, text: '')), child: const Text('Delete')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(key: const ValueKey('note-save'), onPressed: () => Navigator.pop(context, (place: _place, text: _text.text)), child: const Text('Save')),
      ],
    );
  }
}

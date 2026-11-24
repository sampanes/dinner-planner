import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_model.dart';
import '../core/plan.dart';

/// A note written from the stove. The kitchen page's "Note" button on a step
/// opens the app here, with that step named and the keyboard up; Save puts
/// the person back on the recipe they were cooking from.
class NotePage extends StatefulWidget {
  const NotePage({super.key, required this.model, required this.target});

  final AppModel model;
  final NoteTarget target;

  @override
  State<NotePage> createState() => _NotePageState();
}

class _NotePageState extends State<NotePage> {
  late final NoteLine? _there = _find();
  late final TextEditingController _text = TextEditingController(text: _there?.text ?? '');

  /// The note already on this step (or on the whole recipe), to carry on from.
  NoteLine? _find() {
    final t = widget.target;
    final id = t.step == null ? null : stepId(t.step!);
    for (final n in widget.model.plan.notes(t.slug)) {
      if (n.step == id) return n;
    }
    return null;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Back to the recipe: this page goes, and so does the app from in front
  /// of the browser it was opened over.
  void _leave() {
    Navigator.of(context).pop();
    SystemNavigator.pop();
  }

  Future<void> _save() async {
    final t = widget.target, there = _there;
    if (there != null) {
      await widget.model.changeNote(there, _text.text);
    } else {
      await widget.model.setNote(t.slug, _text.text, step: t.step);
    }
    if (mounted) _leave();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = widget.target;
    final onStep = t.step != null;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(key: const ValueKey('stove-note-back'), tooltip: 'Back to the recipe', icon: const Icon(Icons.close), onPressed: _leave),
        title: Text(widget.model.session.recipeName(t.slug), maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              onStep ? 'Step ${t.place! + 1}: ${t.step}' : 'A note on the whole recipe',
              key: const ValueKey('stove-note-where'),
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('stove-note-field'),
              controller: _text,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              maxLength: onStep ? stepNoteMax : noteMax,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: onStep ? 'Garlic salt goes in here' : 'Add parmesan at the end',
                helperText: 'Both phones and the kitchen screen show it, until the recipe is fixed.',
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('stove-note-save'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              onPressed: _save,
              child: Text(_there == null ? 'Save, and back to the recipe' : 'Save the change, and back to the recipe', style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}

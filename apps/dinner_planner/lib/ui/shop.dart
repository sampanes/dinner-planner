import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_model.dart';
import '../core/plan.dart';
import '../core/shopping.dart';
import '../core/sync_core.dart';
import '../data/instacart.dart';

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key, required this.model, required this.onOpenWeek});

  final AppModel model;
  final VoidCallback onOpenWeek;

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: model.shoppingText()));
    messenger.showSnackBar(const SnackBar(content: Text('List copied.')));
  }

  Future<void> _instacart(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await launchUrl(await model.instacartLink(), mode: LaunchMode.externalApplication);
    } on InstacartError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on Exception {
      messenger.showSnackBar(const SnackBar(content: Text('Could not reach Instacart.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = model.now;
    final lines = model.shopping;
    final todo = [for (final l in lines) if (!l.loose) l];
    final check = [for (final l in lines) if (l.loose) l];
    final done = model.shoppingGot;
    final days = [for (var i = 0; i < 14; i++) dayText(dayAfter(now, i))];
    final planned = [for (final d in days) if (model.plan.meal(d) != null) d];
    final soft = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 4),
          child: Text(text, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        );

    final String lead;
    if (planned.isEmpty) {
      lead = 'Pick dinners for the week and what they need is added up here.';
    } else if (lines.isEmpty && done.isEmpty) {
      lead = 'The recipes have not loaded yet.';
    } else {
      final last = parseDay(planned.last)!;
      lead = 'For ${planned.length} dinner${planned.length == 1 ? '' : 's'}, through ${weekdayName(last)}, ${monthDay(last)}. Tap a line when it is in the house.';
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Row(
          children: [
            Expanded(child: Text('Shopping list', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
            if (todo.isNotEmpty || check.isNotEmpty)
              IconButton(key: const ValueKey('shop-copy'), tooltip: 'Copy the list', icon: const Icon(Icons.copy), onPressed: () => _copy(context)),
          ],
        ),
        const SizedBox(height: 4),
        Text(lead, style: soft),
        if (planned.isEmpty) ...[
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: FilledButton.tonal(onPressed: onOpenWeek, child: const Text('Plan the week'))),
        ],
        if (model.instacartKey.isNotEmpty && todo.isNotEmpty) ...[
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            key: const ValueKey('shop-instacart'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open the list in Instacart'),
            onPressed: () => _instacart(context),
          ),
        ],
        const SizedBox(height: 8),
        for (final l in todo) _ShopTile(model: model, line: l, got: false),
        if (todo.isEmpty && done.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('Everything is in the house.', style: theme.textTheme.titleMedium)),
        if (check.isNotEmpty) heading('Check you have'),
        for (final l in check) _ShopTile(model: model, line: l, got: false),
        if (done.isNotEmpty) heading('Got'),
        for (final l in done) _ShopTile(model: model, line: l, got: true),
      ],
    );
  }
}

class _ShopTile extends StatelessWidget {
  const _ShopTile({required this.model, required this.line, required this.got});

  final AppModel model;
  final ShopLine line;
  final bool got;

  Future<void> _edit(BuildContext context) async {
    final text = await showDialog<String>(context: context, builder: (_) => _BuyDialog(name: line.name, current: model.buy(line.id) ?? ''));
    if (text != null) await model.setBuy(line.id, text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buy = model.buy(line.id);
    final faded = theme.colorScheme.onSurfaceVariant;
    final dinners = {for (final u in line.uses) model.session.recipeName(u.slug)}.join(', ');
    final strike = got ? TextDecoration.lineThrough : null;
    return InkWell(
      key: ValueKey('${got ? 'got' : 'shop'}-${line.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => model.setGot(line, !got),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 12, 0),
              child: Icon(got ? Icons.check_circle : Icons.radio_button_unchecked, color: got ? theme.colorScheme.primary : faded),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(children: [
                      if (!line.loose) TextSpan(text: '${line.amountText}  ', style: TextStyle(color: got ? faded : theme.colorScheme.primary, fontWeight: FontWeight.w700)),
                      TextSpan(text: buy ?? _cap(line.name)),
                    ]),
                    style: theme.textTheme.titleMedium?.copyWith(decoration: strike, color: got ? faded : null),
                  ),
                  Text(
                    buy == null ? dinners : '${line.name} · $dinners',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: faded),
                  ),
                ],
              ),
            ),
            IconButton(
              key: ValueKey('${got ? 'got' : 'shop'}-edit-${line.id}'),
              tooltip: 'What you actually buy',
              icon: Icon(buy == null ? Icons.sell_outlined : Icons.sell, color: buy == null ? faded : theme.colorScheme.primary),
              onPressed: () => _edit(context),
            ),
          ],
        ),
      ),
    );
  }
}

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

class _BuyDialog extends StatefulWidget {
  const _BuyDialog({required this.name, required this.current});

  final String name;
  final String current;

  @override
  State<_BuyDialog> createState() => _BuyDialogState();
}

class _BuyDialogState extends State<_BuyDialog> {
  late final TextEditingController _text = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('What do you buy for ${widget.name}?'),
        content: TextField(
          key: const ValueKey('shop-buy-text'),
          controller: _text,
          autofocus: true,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Brand, or the name on the shelf', helperText: 'Both phones see it. Leave empty to clear.', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('shop-buy-save'), onPressed: () => Navigator.of(context).pop(_text.text), child: const Text('Save')),
        ],
      );
}

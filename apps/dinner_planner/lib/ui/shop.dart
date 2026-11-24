import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_model.dart';
import '../core/plan.dart';
import '../core/shopping.dart';
import '../core/store_order.dart';
import '../core/sync_core.dart';
import '../data/products.dart';
import 'house_page.dart';
import 'match.dart';
import 'parts.dart' show say;
import 'scan.dart';

/// Offered when adding a store, so the usual ones are a tap rather than typing.
const List<String> storeIdeas = ['Albertsons', 'Aldi', 'Costco', "Fry's", 'Kroger', 'Safeway', 'Sprouts', 'Target', "Trader Joe's", 'Walmart', 'Whole Foods'];

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key, required this.model, required this.onOpenWeek});

  final AppModel model;
  final VoidCallback onOpenWeek;

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: model.shoppingText()));
    messenger.showSnackBar(const SnackBar(content: Text('List copied.')));
  }

  /// One barcode of a scanning session. In the store it ticks the line; at
  /// the pantry shelf it teaches the app what the household buys; and an
  /// extra that has run out goes back on the list.
  Future<ScanOutcome?> _scanned(BuildContext context, String code) async {
    var names = model.itemNames;
    var id = model.ingredientForCode(code);
    if (id == null || !names.containsKey(id)) {
      // A packet the household has not scanned before: say what it is for.
      final picked = await Navigator.of(context).push<({String? id, Product? found})>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => MatchPage(model: model, code: code)));
      if (picked == null || !context.mounted) return null;
      final found = picked.found;
      if (picked.id == null) {
        final made = await showDialog<({String name, bool want})>(context: context, builder: (_) => _NewExtraDialog(found: found));
        if (made == null) return null;
        final madeId = await model.addExtra(made.name, want: made.want, code: code, buy: found?.shelfName, size: found?.size);
        if (madeId == null) return null;
        final name = model.itemNames[madeId] ?? made.name;
        return made.want ? (text: 'On the list: $name', undo: () => model.wantExtra(madeId, false)) : (text: 'Saved: $name', undo: null);
      }
      id = picked.id!;
      // Then look over what was found.
      if (!await editProduct(context, model, id: id, name: names[id] ?? id, found: found, code: code)) return null;
      names = model.itemNames;
    }
    final item = id;
    final name = model.buy(item) ?? _cap(names[item] ?? item);
    final line = [for (final l in [...model.shopping, ...model.shoppingLikely]) if (l.id == item) l].firstOrNull;
    if (line == null) {
      // Out of a store, scanning an extra means it has run out.
      if (model.extras.containsKey(item) && model.shoppingAt == null) {
        await model.wantExtra(item, true);
        return (text: 'On the list: $name', undo: () => model.wantExtra(item, false));
      }
      // A packet from the shelf at home that no dinner is waiting for: now
      // the app knows it is there.
      if (model.ingredientNames.containsKey(item) && !model.staple(item) && !model.here(item)) {
        await model.setHere(item, true);
        return (text: 'In the house: $name', undo: () => model.setHere(item, false));
      }
      return (text: '$name: not on the list right now.', undo: null);
    }
    await model.setGot(line, true);
    return (text: 'Got: $name', undo: () => model.setGot(line, false));
  }

  Future<void> _add(BuildContext context) async {
    final names = await showDialog<List<String>>(context: context, builder: (_) => _AddDialog(model: model));
    for (final name in names ?? const <String>[]) {
      await model.addExtra(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = model.now;
    final groups = model.shoppingGroups;
    final check = [for (final l in model.shopping) if (l.loose) l];
    final likely = model.shoppingLikely;
    final done = model.shoppingGot;
    final store = model.shoppingAt;
    final days = [for (var i = 0; i < 14; i++) dayText(dayAfter(now, i))];
    final planned = [for (final d in days) if (model.plan.meal(d) != null) d];
    final soft = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final any = groups.isNotEmpty || check.isNotEmpty || done.isNotEmpty || likely.isNotEmpty;

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 4),
          child: Text(text, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        );

    final String lead;
    if (planned.isEmpty) {
      lead = 'Pick dinners for the week and what they need is added up here.';
    } else if (model.recipes.isEmpty) {
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
            if (model.recipes.isNotEmpty)
              IconButton(key: const ValueKey('shop-house'), tooltip: 'What is in the house', icon: const Icon(Icons.kitchen_outlined), onPressed: () => HousePage.open(context, model)),
            IconButton(key: const ValueKey('shop-add'), tooltip: 'Add something else', icon: const Icon(Icons.add), onPressed: () => _add(context)),
            if (model.recipes.isNotEmpty)
              IconButton(key: const ValueKey('shop-scan'), tooltip: 'Scan packets', icon: const Icon(Icons.qr_code_scanner), onPressed: () => scanMany(context, _scanned)),
            if (groups.isNotEmpty || check.isNotEmpty)
              IconButton(key: const ValueKey('shop-copy'), tooltip: 'Copy the list', icon: const Icon(Icons.copy), onPressed: () => _copy(context)),
          ],
        ),
        const SizedBox(height: 4),
        Text(lead, style: soft),
        if (planned.isEmpty) ...[
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: FilledButton.tonal(onPressed: onOpenWeek, child: const Text('Plan the week'))),
        ],
        if (any) ...[
          const SizedBox(height: 12),
          _StoreBar(model: model),
          if (store != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('In the order you walk ${model.storeName(store)}. Tick things as they go in the cart and the list learns the way round.', style: soft),
            )
          else if (model.stores.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('In a store? Tap its name and the list follows the way you walk it.', style: soft)),
        ],
        if (groups.isNotEmpty && !model.staplesTaught)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Always have something in the house? Press and hold its line, and no dinner will ask for it again.', key: const ValueKey('staple-hint'), style: soft),
          ),
        for (final g in groups) ...[
          heading(sections[g.section] ?? g.section),
          for (final l in g.lines) _ShopTile(model: model, line: l, got: false),
        ],
        if (groups.isEmpty && likely.isEmpty && done.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('Everything is in the house.', style: theme.textTheme.titleMedium)),
        if (likely.isNotEmpty) ...[
          heading('Probably in the house'),
          Text('The app believes these are still there, so they are not on the list to buy. Tap one when you have seen it; the cross if it is gone.', key: const ValueKey('likely-hint'), style: soft),
          for (final l in likely) _LikelyTile(model: model, line: l),
        ],
        if (check.isNotEmpty) heading('Check you have'),
        for (final l in check) _ShopTile(model: model, line: l, got: false),
        if (done.isNotEmpty) heading('Got'),
        for (final l in done) _ShopTile(model: model, line: l, got: true),
        if (planned.isNotEmpty && model.staples.isNotEmpty) ...[
          heading('Always in the house'),
          Text('No dinner puts these on the list. Tap one the day it runs out.', style: soft),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in model.staples)
                ActionChip(
                  key: ValueKey('staple-${s.id}'),
                  avatar: Icon(s.out ? Icons.shopping_basket_outlined : Icons.check, size: 18),
                  label: Text(_cap(s.name)),
                  onPressed: () => _staple(context, s),
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// One staple: it has run out, or it is not a staple after all.
  Future<void> _staple(BuildContext context, ({String id, String name, bool out}) s) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = _cap(s.name);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('staple-out'),
              leading: Icon(s.out ? Icons.check : Icons.add_shopping_cart),
              title: Text(s.out ? '$name is back in the house' : 'We are out of ${s.name}'),
              subtitle: Text(s.out ? 'Take it off the list.' : 'On the list until it is bought.'),
              onTap: () => Navigator.of(context).pop('out'),
            ),
            ListTile(
              key: const ValueKey('staple-not'),
              leading: const Icon(Icons.remove_circle_outline),
              title: Text('$name is not always in the house'),
              subtitle: const Text('Dinners that need it put it on the list again.'),
              onTap: () => Navigator.of(context).pop('not'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == 'out') {
      await model.ranOut(s.id, !s.out);
      say(messenger, s.out ? '$name is off the list.' : '$name is on the list.', () => model.ranOut(s.id, s.out));
    } else if (choice == 'not') {
      final done = await model.setStaple(s.id, false, name: name);
      say(messenger, done.text, done.undo);
    }
  }
}

/// The household's stores as chips. The chosen one is where this phone's
/// owner is shopping now.
class _StoreBar extends StatelessWidget {
  const _StoreBar({required this.model});

  final AppModel model;

  Future<void> _add(BuildContext context) async {
    final names = await showDialog<List<String>>(context: context, builder: (_) => _StoreDialog(have: {for (final s in model.stores) s.id}));
    if (names != null) await model.addStores(names);
  }

  Future<void> _remove(BuildContext context, ({String id, String name}) store) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Take ${store.name} off the list of stores?'),
        content: const Text('On both phones. What it learned about the store is kept in case you add it again.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Take it off')),
        ],
      ),
    );
    if (yes == true) await model.removeStore(store.id);
  }

  @override
  Widget build(BuildContext context) {
    final stores = model.stores, here = model.shoppingAt;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final s in stores)
          GestureDetector(
            onLongPress: () => _remove(context, s),
            child: ChoiceChip(
              key: ValueKey('store-${s.id}'),
              avatar: here == s.id ? null : const Icon(Icons.storefront_outlined, size: 18),
              label: Text(s.name),
              selected: here == s.id,
              onSelected: (on) => model.shopAt(on ? s.id : null),
            ),
          ),
        ActionChip(
          key: const ValueKey('store-add'),
          avatar: const Icon(Icons.add, size: 18),
          label: Text(stores.isEmpty ? 'Add your stores' : 'Store'),
          onPressed: () => _add(context),
        ),
      ],
    );
  }
}

class _StoreDialog extends StatefulWidget {
  const _StoreDialog({required this.have});

  /// The stores already listed, by id.
  final Set<String> have;

  @override
  State<_StoreDialog> createState() => _StoreDialogState();
}

class _StoreDialogState extends State<_StoreDialog> {
  final TextEditingController _text = TextEditingController();
  final Set<String> _picked = {};

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Where do you shop?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final name in storeIdeas)
                    if (!widget.have.contains(storeSlug(name)))
                      FilterChip(
                        key: ValueKey('store-idea-${storeSlug(name)}'),
                        label: Text(name),
                        selected: _picked.contains(name),
                        onSelected: (on) => setState(() => on ? _picked.add(name) : _picked.remove(name)),
                      ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('store-name'),
                controller: _text,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Another store', helperText: 'Both phones see the list of stores.', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('store-save'), onPressed: () => Navigator.of(context).pop([..._picked, _text.text]), child: const Text('Add')),
        ],
      );
}

class _ShopTile extends StatelessWidget {
  const _ShopTile({required this.model, required this.line, required this.got});

  final AppModel model;
  final ShopLine line;
  final bool got;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buy = model.buy(line.id), size = model.size(line.id), packs = got ? null : model.packs(line);
    final store = model.shoppingAt;
    final faded = theme.colorScheme.onSurfaceVariant;
    final dinners = {for (final u in line.uses) model.session.recipeName(u.slug)}.join(', ');
    final asWell = !line.extra && !got && model.wantedToo(line.id);
    final strike = got ? TextDecoration.lineThrough : null;
    final known = buy != null || size != null;
    final small = [
      if (buy != null) line.name,
      if (size != null) packs == null ? size : '$packs × $size',
      if (store != null) ?model.at(store, line.id),
      if (dinners.isNotEmpty) dinners,
      if (asWell) 'and for the house',
    ].join(' · ');
    return InkWell(
      key: ValueKey('${got ? 'got' : 'shop'}-${line.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => model.setGot(line, !got),
      // Held: "we always have this". Not for the things no dinner asks for.
      onLongPress: got || line.extra
          ? null
          : () async {
              final messenger = ScaffoldMessenger.of(context);
              final done = await model.setStaple(line.id, true, name: _cap(line.name));
              say(messenger, done.text, done.undo);
            },
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
                      if (line.totals.isNotEmpty) TextSpan(text: '${line.amountText}  ', style: TextStyle(color: got ? faded : theme.colorScheme.primary, fontWeight: FontWeight.w700)),
                      TextSpan(text: buy ?? _cap(line.name)),
                    ]),
                    style: theme.textTheme.titleMedium?.copyWith(decoration: strike, color: got ? faded : null),
                  ),
                  if (small.isNotEmpty) Text(small, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: faded)),
                ],
              ),
            ),
            IconButton(
              key: ValueKey('${got ? 'got' : 'shop'}-edit-${line.id}'),
              tooltip: 'What you actually buy',
              icon: Icon(known ? Icons.sell : Icons.sell_outlined, color: known ? theme.colorScheme.primary : faded),
              onPressed: () => editProduct(context, model, id: line.id, name: line.name),
            ),
          ],
        ),
      ),
    );
  }
}

/// A line the app believes is already in the house: bought lately for
/// another dinner, or said to be there. A tap agrees; the cross says it is
/// gone and puts it on the list to buy.
class _LikelyTile extends StatelessWidget {
  const _LikelyTile({required this.model, required this.line});

  final AppModel model;
  final ShopLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faded = theme.colorScheme.onSurfaceVariant;
    final since = model.hereSince(line.id);
    final dinners = {for (final u in line.uses) model.session.recipeName(u.slug)}.join(', ');
    final name = model.buy(line.id) ?? _cap(line.name);
    return InkWell(
      key: ValueKey('likely-${line.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final messenger = ScaffoldMessenger.of(context);
        await model.setGot(line, true, fresh: false);
        say(messenger, '$name: ticked for $dinners.', () => model.setGot(line, false));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(4, 2, 12, 0), child: Icon(Icons.kitchen_outlined, color: faded)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(children: [
                      if (line.totals.isNotEmpty) TextSpan(text: '${line.amountText}  ', style: TextStyle(color: faded, fontWeight: FontWeight.w700)),
                      TextSpan(text: name),
                    ]),
                    style: theme.textTheme.titleMedium,
                  ),
                  Text([if (since != null) 'In the house since $since', if (dinners.isNotEmpty) dinners].join(' \u00b7 '), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: faded)),
                ],
              ),
            ),
            IconButton(
              key: ValueKey('likely-gone-${line.id}'),
              tooltip: 'It is gone: put it on the list',
              icon: Icon(Icons.close, color: faded),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final done = await model.notHere(line.id, name: name);
                say(messenger, done.text, done.undo);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// A scanned packet that is not for a recipe: what to call it on the list.
class _NewExtraDialog extends StatefulWidget {
  const _NewExtraDialog({this.found});

  final Product? found;

  @override
  State<_NewExtraDialog> createState() => _NewExtraDialogState();
}

class _NewExtraDialogState extends State<_NewExtraDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.found?.name ?? '');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _close(bool want) {
    if (_name.text.trim().isNotEmpty) Navigator.of(context).pop((name: _name.text.trim(), want: want));
  }

  @override
  Widget build(BuildContext context) {
    final shelf = widget.found?.shelfName ?? '';
    return AlertDialog(
      title: const Text('What do you call it?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (shelf.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(shelf)),
          TextField(
            key: const ValueKey('extra-name'),
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Short name for the list', hintText: 'Milk', border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(key: const ValueKey('extra-keep'), onPressed: () => _close(false), child: const Text('Just remember it')),
        FilledButton(key: const ValueKey('extra-want'), onPressed: () => _close(true), child: const Text('Put it on the list')),
      ],
    );
  }
}

/// Something to buy that no dinner asks for: typed, or picked from the
/// extras the household has bought before.
class _AddDialog extends StatefulWidget {
  const _AddDialog({required this.model});

  final AppModel model;

  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  final TextEditingController _text = TextEditingController();
  final Set<String> _picked = {};
  late final Set<String> _onList = {for (final l in widget.model.shopping) l.id};

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final known = widget.model.extras.entries.where((e) => !_onList.contains(e.key)).toList()..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return AlertDialog(
      title: const Text('Something else to buy'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('extra-text'),
              controller: _text,
              autofocus: known.isEmpty,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Milk, coffee, foil', helperText: 'Commas between several.', border: OutlineInputBorder()),
            ),
            if (known.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Bought before', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final e in known)
                    FilterChip(
                      key: ValueKey('extra-idea-${e.key}'),
                      label: Text(e.value),
                      selected: _picked.contains(e.value),
                      onSelected: (on) => setState(() => on ? _picked.add(e.value) : _picked.remove(e.value)),
                      deleteButtonTooltipMessage: 'Forget it',
                      onDeleted: () async {
                        _picked.remove(e.value);
                        await widget.model.forgetExtra(e.key);
                        if (mounted) setState(() {});
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('extra-add'),
          onPressed: () => Navigator.of(context).pop([..._picked, for (final part in _text.text.split(',')) if (part.trim().isNotEmpty) part.trim()]),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

/// Opens the sheet for one ingredient and saves what comes back. [found] and
/// [code] are a packet that was just scanned for it. False when the person
/// backed out.
Future<bool> editProduct(BuildContext context, AppModel model, {required String id, required String name, Product? found, String? code}) async {
  final edit = await showModalBottomSheet<ProductEdit>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ProductSheet(model: model, id: id, name: name, found: found, code: code),
  );
  if (edit == null) return false;
  await model.saveProduct(id, buy: edit.buy, size: edit.size, section: edit.section, at: edit.at, code: edit.code, always: edit.always);
  return true;
}

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// What the sheet below hands back when it is saved.
typedef ProductEdit = ({String buy, String size, String section, Map<String, String> at, String? code, bool? always});

/// Everything the household records about what it buys for one ingredient:
/// the name on the shelf, the packet size, its section, and a note per store
/// on where it is.
class ProductSheet extends StatefulWidget {
  const ProductSheet({super.key, required this.model, required this.id, required this.name, this.found, this.code});

  final AppModel model;
  final String id;
  final String name;

  /// A packet scanned for this ingredient before the sheet opened: its
  /// barcode, and what the public lists said it is (null when they did not
  /// know it).
  final Product? found;
  final String? code;

  @override
  State<ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<ProductSheet> {
  late final TextEditingController _buy = TextEditingController(text: widget.model.buy(widget.id) ?? '');
  late final TextEditingController _size = TextEditingController(text: widget.model.size(widget.id) ?? '');
  late final Map<String, TextEditingController> _at = {
    for (final s in widget.model.stores) s.id: TextEditingController(text: widget.model.at(s.id, widget.id) ?? ''),
  };
  late String _section = widget.model.section(widget.id);

  /// Only something a recipe uses can be "always in the house".
  late final bool _canBeStaple = widget.model.ingredientNames.containsKey(widget.id);
  late bool _always = widget.model.staple(widget.id);
  late String? _code = widget.code;
  String? _note;
  bool _looking = false;

  @override
  void initState() {
    super.initState();
    if (widget.code != null) _fill(widget.found);
  }

  /// Puts what a scan found into the fields, keeping what is there where the
  /// scan has nothing better.
  void _fill(Product? p) {
    final name = p?.shelfName ?? '', size = p?.size ?? '';
    if (name.isNotEmpty) _buy.text = name;
    if (size.isNotEmpty) _size.text = size;
    _note = name.isEmpty && size.isEmpty
        ? 'Neither list knows that barcode. Type the name once; the app will know the packet from now on.'
        : 'From the barcode. Change anything that is off.';
  }

  Future<void> _scan() async {
    final code = await scanOne(context);
    if (code == null || !mounted) return;
    setState(() => _looking = true);
    final found = await widget.model.lookUp(code);
    if (!mounted) return;
    setState(() {
      _looking = false;
      _code = code;
      _fill(found);
    });
  }

  @override
  void dispose() {
    _buy.dispose();
    _size.dispose();
    for (final c in _at.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() => Navigator.of(context).pop((buy: _buy.text, size: _size.text, section: _section, at: {for (final e in _at.entries) e.key: e.value.text}, code: _code, always: _canBeStaple ? _always : null));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const gap = SizedBox(height: 12);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('What do you buy for ${widget.name}?', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Both phones see it. Every part is optional.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                key: const ValueKey('shop-scan-packet'),
                onPressed: _looking ? null : _scan,
                icon: _looking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.qr_code_scanner),
                label: Text(_looking ? 'Looking it up' : (_code == null ? 'Scan the packet' : 'Scan another')),
              ),
            ),
            if (_note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_note!, key: const ValueKey('shop-scan-note'), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary))),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('shop-buy-text'),
              controller: _buy,
              minLines: 1,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Brand, or the name on the shelf', border: OutlineInputBorder()),
            ),
            gap,
            TextField(
              key: const ValueKey('shop-size-text'),
              controller: _size,
              decoration: const InputDecoration(labelText: 'Packet size', hintText: '16 oz, 1 lb, 6 ct', border: OutlineInputBorder()),
            ),
            gap,
            DropdownButtonFormField<String>(
              key: const ValueKey('shop-section'),
              initialValue: _section,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Section', border: OutlineInputBorder()),
              items: [for (final s in sections.entries) DropdownMenuItem(value: s.key, child: Text(s.value))],
              onChanged: (s) => setState(() => _section = s ?? _section),
            ),
            for (final s in widget.model.stores) ...[
              gap,
              TextField(
                key: ValueKey('shop-at-${s.id}'),
                controller: _at[s.id],
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: 'Where in ${s.name}', hintText: 'Aisle 7, by the eggs', border: const OutlineInputBorder()),
              ),
            ],
            if (_canBeStaple)
              SwitchListTile(
                key: const ValueKey('shop-staple'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Always in the house'),
                subtitle: const Text('No dinner puts it on the list. Say when it runs out.'),
                value: _always,
                onChanged: (on) => setState(() => _always = on),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(key: const ValueKey('shop-buy-save'), onPressed: _save, child: const Text('Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

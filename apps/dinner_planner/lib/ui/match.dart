import 'package:flutter/material.dart';

import '../app_model.dart';
import '../data/products.dart';

/// After a packet the household has not scanned before: which ingredient is
/// it? The likeliest are on top, so most of the time it is one tap.
class MatchPage extends StatefulWidget {
  const MatchPage({super.key, required this.model, required this.code});

  final AppModel model;
  final String code;

  @override
  State<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends State<MatchPage> {
  late final Future<Product?> _lookup = widget.model.lookUp(widget.code);
  late final Map<String, String> _names = widget.model.ingredientNames;
  late final Set<String> _onList = {for (final l in widget.model.shopping) l.id};
  final TextEditingController _filter = TextEditingController();
  Product? _found;
  bool _looking = true;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _lookup.then((p) {
      if (mounted) {
        setState(() {
          _found = p;
          _looking = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _pick(String id) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    // A tap made before the answer came still gets the answer.
    final found = await _lookup;
    if (mounted) Navigator.of(context).pop((id: id, found: found));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faded = theme.colorScheme.onSurfaceVariant;
    final found = _found;
    final wanted = _filter.text.trim().toLowerCase();
    bool shown(String id) => wanted.isEmpty || _names[id]!.toLowerCase().contains(wanted);

    final likely = found == null ? const <String>[] : matchIngredients(found.shelfName, _names).take(6).toList();
    final rest = [for (final id in _names.keys) if (!likely.contains(id)) id]
      ..sort((a, b) {
        final la = _onList.contains(a), lb = _onList.contains(b);
        if (la != lb) return la ? -1 : 1;
        return _names[a]!.toLowerCase().compareTo(_names[b]!.toLowerCase());
      });

    Widget tile(String id) => ListTile(
          key: ValueKey('match-$id'),
          title: Text(_cap(_names[id]!)),
          subtitle: _onList.contains(id) ? const Text('On the list') : null,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _pick(id),
        );
    Widget label(String text) => Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: faded)));

    final top = [for (final id in likely) if (shown(id)) id], others = [for (final id in rest) if (shown(id)) id];
    return Scaffold(
      appBar: AppBar(title: const Text('Which ingredient is this?')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_looking || _leaving) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: _looking
                ? Text('Looking the barcode up...', style: theme.textTheme.bodyLarge)
                : found == null
                    ? Text('Neither list knows this barcode. Say what it is and the app will know the packet from now on.', key: const ValueKey('match-unknown'), style: theme.textTheme.bodyLarge)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(found.shelfName.isEmpty ? 'A packet with no name on file' : found.shelfName, key: const ValueKey('match-found'), style: theme.textTheme.titleLarge),
                          if (found.size.isNotEmpty) Text(found.size, style: theme.textTheme.bodyLarge?.copyWith(color: faded)),
                        ],
                      ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const ValueKey('match-filter'),
              controller: _filter,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Find an ingredient', border: OutlineInputBorder(), isDense: true),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (top.isNotEmpty) label('Most likely'),
                for (final id in top) tile(id),
                if (others.isNotEmpty) label(top.isEmpty ? 'Every ingredient the recipes use' : 'Everything else'),
                for (final id in others) tile(id),
                if (top.isEmpty && others.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text('No recipe uses an ingredient called that.', style: theme.textTheme.bodyLarge)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

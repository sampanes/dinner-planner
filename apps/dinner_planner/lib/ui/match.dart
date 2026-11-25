import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_model.dart';
import '../data/labels.dart';
import '../data/products.dart';

/// After a packet the household has not scanned before: which ingredient is
/// it? The likeliest are on top, so most of the time it is one tap. Pops with
/// the ingredient's id, or with a null id for "not for a recipe".
class MatchPage extends StatefulWidget {
  const MatchPage({super.key, required this.model, required this.code, this.picture});

  final AppModel model;
  final String code;

  /// The camera frame the barcode was seen in: when no list knows the
  /// barcode, the words on the label around it are read instead.
  final Uint8List? picture;

  @override
  State<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends State<MatchPage> {
  late final Future<Product?> _lookup = widget.model.identify(widget.code, picture: widget.picture);
  late final Map<String, String> _names = widget.model.itemNames;
  late final Set<String> _onList = {for (final l in widget.model.shopping) l.id};
  final TextEditingController _filter = TextEditingController();
  Product? _found;
  bool _looking = true;
  bool _leaving = false;
  bool _reading = false;

  /// Every name-like word of a label photographed here, to match on.
  String? _labelText;
  String? _readNote;

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

  Future<void> _pick(String? id) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    // A tap made before the answer came still gets the answer.
    final found = await _lookup;
    if (mounted) Navigator.of(context).pop((id: id, found: _found ?? found));
  }

  /// A picture of the front of the packet, or of its shelf tag.
  Future<void> _read() async {
    setState(() {
      _reading = true;
      _readNote = null;
    });
    final label = await widget.model.photographLabel();
    if (!mounted) return;
    setState(() {
      _reading = false;
      if (label == null) return;
      if (label.isEmpty) {
        _readNote = 'No words could be read from that picture. Closer, and square on, usually does it.';
      } else {
        _found = productFromLabel(widget.code, label, _names);
        _labelText = label.text;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faded = theme.colorScheme.onSurfaceVariant;
    final found = _found;
    final wanted = _filter.text.trim().toLowerCase();
    bool shown(String id) => wanted.isEmpty || _names[id]!.toLowerCase().contains(wanted);

    final likely = found == null ? const <String>[] : matchIngredients(_labelText ?? found.shelfName, _names).take(6).toList();
    final canRead = !_looking && !_leaving && (found == null || found.read);
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
          if (_looking || _leaving || _reading) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: _looking
                ? Text('Looking the barcode up...', style: theme.textTheme.bodyLarge)
                : found == null
                    ? Text('Neither list knows this barcode. Say what it is and the app will know the packet from now on.', key: const ValueKey('match-unknown'), style: theme.textTheme.bodyLarge)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (found.read) Text('Read off the label', key: const ValueKey('match-read-said'), style: theme.textTheme.labelLarge?.copyWith(color: faded)),
                          Text(found.shelfName.isEmpty ? (found.read ? 'No name could be read' : 'A packet with no name on file') : found.shelfName, key: const ValueKey('match-found'), style: theme.textTheme.titleLarge),
                          if (found.size.isNotEmpty) Text(found.size, style: theme.textTheme.bodyLarge?.copyWith(color: faded)),
                        ],
                      ),
          ),
          if (canRead)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('match-read'),
                    onPressed: _reading ? null : _read,
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: Text(found == null ? 'Read the label instead' : 'Read the label again'),
                  ),
                  Text(_readNote ?? 'Photograph the front of the packet or its shelf tag: the app reads the name and the size.', key: const ValueKey('match-read-note'), style: theme.textTheme.bodySmall?.copyWith(color: faded)),
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
                if (wanted.isEmpty)
                  ListTile(
                    key: const ValueKey('match-extra'),
                    leading: const Icon(Icons.add_shopping_cart),
                    title: const Text('Not for a recipe'),
                    subtitle: const Text('Milk, coffee, foil: it goes on the list as its own thing.'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _pick(null),
                  ),
                if (top.isNotEmpty) label('Most likely'),
                for (final id in top) tile(id),
                if (others.isNotEmpty) label(top.isEmpty ? 'Everything the app knows' : 'Everything else'),
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

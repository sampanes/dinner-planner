import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_model.dart';
import '../core/plan.dart';
import '../data/relay.dart';
import 'parts.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
          child: Text(text, style: theme.textTheme.titleLarge),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text('Settings', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        heading('The two of you'),
        for (final who in people) _PersonRow(model: model, who: who),
        heading('Reminders on your nights'),
        _TimeRow(
          label: 'The evening before',
          hint: 'Check the fridge, start thawing',
          minutes: model.times.evening,
          onPicked: (m) => model.setTimes(model.times.copyWith(evening: m)),
        ),
        _TimeRow(
          label: 'That morning',
          hint: 'Last call for anything frozen',
          minutes: model.times.morning,
          onPicked: (m) => model.setTimes(model.times.copyWith(morning: m)),
        ),
        _TimeRow(
          label: 'Start cooking',
          hint: 'When you should be at the stove',
          minutes: model.times.start,
          onPicked: (m) => model.setTimes(model.times.copyWith(start: m)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(onPressed: model.allowNotifications, child: const Text('Allow notifications')),
            OutlinedButton(onPressed: model.testReminder, child: const Text('Show me one')),
          ],
        ),
        heading('Sharing'),
        _Sharing(model: model),
        heading('Recipes'),
        _SiteField(model: model),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                model.recipeError != null && model.recipes.isEmpty
                    ? 'Could not load the recipes.'
                    : '${model.recipes.length} recipes on this phone${model.recipeError != null ? ' (could not refresh just now)' : ''}',
              ),
            ),
            model.loadingRecipes
                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : TextButton(onPressed: model.refreshRecipes, child: const Text('Refresh')),
          ],
        ),
        heading('Scanning packets'),
        const Text('A scanned barcode is looked up in Open Food Facts and in the USDA\'s list of branded foods; only the barcode is sent. The USDA answers ten lookups an hour without a key. A free key from api.data.gov lifts that, and stays on this phone.'),
        const SizedBox(height: 12),
        _CommitField(key: const ValueKey('usda-key'), value: model.usdaKey, label: 'USDA key (optional)', onCommit: model.setUsdaKey),
        if (model.startHidden && model.startDone.length < StartStep.values.length) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(key: const ValueKey('start-show'), onPressed: () => model.hideStart(false), child: const Text('Show the "start here" steps again')),
          ),
        ],
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.model, required this.who});

  final AppModel model;
  final String who;

  @override
  Widget build(BuildContext context) {
    final isMe = model.me == who;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Row(
        children: [
          CircleAvatar(radius: 10, backgroundColor: personColors[who]),
          const SizedBox(width: 12),
          Expanded(
            child: _CommitField(
              key: ValueKey('name-$who'),
              value: model.plan.name(who),
              label: 'Name',
              onCommit: (text) => model.setName(who, text),
            ),
          ),
          const SizedBox(width: 12),
          // The same width either way, so the two name fields line up.
          SizedBox(
            width: 112,
            child: ChoiceChip(
              key: ValueKey('is-me-$who'),
              label: SizedBox(width: double.infinity, child: Text(isMe ? 'This is me' : 'Me?', textAlign: TextAlign.center)),
              showCheckmark: false,
              selected: isMe,
              onSelected: (_) => model.setMe(who),
            ),
          ),
        ],
      ),
    );
  }
}

/// A text field that saves when you leave it or press done, and takes on a
/// new value that arrives from the other phone while it is not being edited.
class _CommitField extends StatefulWidget {
  const _CommitField({super.key, required this.value, required this.label, required this.onCommit, this.keyboardType});

  final String value;
  final String label;
  final ValueChanged<String> onCommit;
  final TextInputType? keyboardType;

  @override
  State<_CommitField> createState() => _CommitFieldState();
}

class _CommitFieldState extends State<_CommitField> {
  late final TextEditingController _text = TextEditingController(text: widget.value);
  late final FocusNode _focus = FocusNode()..addListener(_onFocus);

  void _onFocus() {
    if (!_focus.hasFocus && _text.text != widget.value) widget.onCommit(_text.text);
  }

  @override
  void didUpdateWidget(_CommitField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value && !_focus.hasFocus) _text.text = widget.value;
  }

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _text,
        focusNode: _focus,
        keyboardType: widget.keyboardType,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(labelText: widget.label, border: const OutlineInputBorder(), isDense: true),
        onSubmitted: (_) => _focus.unfocus(),
      );
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.label, required this.hint, required this.minutes, required this.onPicked});

  final String label;
  final String hint;
  final int minutes;
  final ValueChanged<int> onPicked;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(hint),
      trailing: FilledButton.tonal(
        onPressed: () async {
          final picked = await showTimePicker(context: context, initialTime: time);
          if (picked != null) onPicked(picked.hour * 60 + picked.minute);
        },
        child: Text(MaterialLocalizations.of(context).formatTimeOfDay(time, alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))),
      ),
    );
  }
}

class _Sharing extends StatelessWidget {
  const _Sharing({required this.model});

  final AppModel model;

  Future<void> _join(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final code = await showDialog<String>(context: context, builder: (_) => const _TextDialog(title: 'Paste the code from the other phone', label: 'Code', action: 'Join'));
    if (code == null) return;
    final ok = await model.joinHousehold(code);
    if (!ok) messenger.showSnackBar(const SnackBar(content: Text('That is not a sharing code.')));
  }

  Future<void> _scanToJoin(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _ScanHouseholdCode()));
    if (code == null) return;
    final ok = await model.joinHousehold(code);
    messenger.showSnackBar(SnackBar(content: Text(ok ? 'Joined. The plan arrives in a few seconds.' : 'That is not a sharing code.')));
  }

  Future<void> _startOnOwnServer(BuildContext context) async {
    final server = await showDialog<String>(
      context: context,
      builder: (_) => const _TextDialog(title: 'Your ntfy server', label: 'Address, like https://ntfy.example.com', action: 'Next'),
    );
    if (server == null || server.trim().isEmpty || !context.mounted) return;
    final token = await showDialog<String>(
      context: context,
      builder: (_) => const _TextDialog(title: 'Access token', label: 'Leave empty if the server needs none', action: 'Start'),
    );
    if (token == null) return;
    await model.startHousehold(server: server, token: token);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final h = model.household;
    if (h == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Share the plan with the other phone: who cooks, what is for dinner, and the names above. One of you starts, the other joins with the code.'),
          const SizedBox(height: 12),
          FilledButton(key: const ValueKey('share-start'), onPressed: model.startHousehold, child: const Text('Start sharing')),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            key: const ValueKey('share-scan'),
            onPressed: () => _scanToJoin(context),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text("Scan the other phone's code"),
          ),
          const SizedBox(height: 8),
          OutlinedButton(key: const ValueKey('share-join'), onPressed: () => _join(context), child: const Text('Join with a code')),
          TextButton(onPressed: () => _startOnOwnServer(context), child: const Text('Start on my own server')),
        ],
      );
    }
    final String status;
    if (model.syncError != null) {
      status = 'Cannot reach ${Uri.parse(h.server).host} just now. Changes are kept and sent later.';
    } else if (model.otherPhones == 0) {
      status = 'Waiting for the other phone to join.';
    } else {
      status = model.inStep ? 'Both phones show the same plan.' : 'Catching up with the other phone.';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(status),
        const SizedBox(height: 4),
        Text('Through ${Uri.parse(h.server).host}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        const Text("On the other phone choose \"Scan the other phone's code\" and point it here:"),
        const SizedBox(height: 12),
        Center(
          child: Container(
            // Black on white whatever the theme: scanners read that best.
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: QrImageView(key: const ValueKey('share-qr'), data: h.code, size: 220, backgroundColor: Colors.white, padding: EdgeInsets.zero),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Or choose "Join with a code" and paste this:'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
          child: SelectableText(h.code, key: const ValueKey('share-code'), style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: h.code));
                messenger.showSnackBar(const SnackBar(content: Text('Code copied.')));
              },
              child: const Text('Copy the code'),
            ),
            TextButton(onPressed: model.leaveHousehold, child: const Text('Stop sharing on this phone')),
          ],
        ),
      ],
    );
  }
}

class _SiteField extends StatelessWidget {
  const _SiteField({required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) => _CommitField(
        key: const ValueKey('site'),
        value: model.site,
        label: 'Recipe site',
        keyboardType: TextInputType.url,
        onCommit: model.setSite,
      );
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.label, required this.action});

  final String title;
  final String label;
  final String action;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _text,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(labelText: widget.label, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(_text.text), child: Text(widget.action)),
        ],
      );
}

/// The camera, looking for the QR code another phone shows under Sharing.
/// Pops with the household code once it sees one.
class _ScanHouseholdCode extends StatefulWidget {
  const _ScanHouseholdCode();

  @override
  State<_ScanHouseholdCode> createState() => _ScanHouseholdCodeState();
}

class _ScanHouseholdCodeState extends State<_ScanHouseholdCode> {
  final MobileScannerController _camera = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  void _seen(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final code = b.rawValue;
      if (code == null || Household.fromCode(code) == null) continue;
      _done = true;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(code);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text("Scan the other phone's code")),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: MobileScanner(
              controller: _camera,
              onDetect: _seen,
              errorBuilder: (context, error) => Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                        ? "The camera is not allowed. Allow it for Dinner Planner in the phone's settings, or go back and paste the code."
                        : 'The camera would not start. Go back and paste the code instead.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('On the other phone open Settings; the code is under Sharing.', textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}

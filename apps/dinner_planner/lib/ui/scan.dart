import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/products.dart';

/// A barcode the camera read, in the form [canonicalCode] makes, and the
/// picture it was read in when there is one: the label around the bars,
/// whose words say what a barcode alone may not.
typedef Seen = ({String code, Uint8List? picture});

/// What the camera calls with each product barcode it reads.
typedef OnSeen = void Function(String code, {Uint8List? picture});

/// Draws the live camera and calls [onCode] with each barcode.
typedef CameraBuilder = Widget Function(BuildContext context, OnSeen onCode);

/// How the app sees a barcode. Tests put a stand-in here; the camera itself
/// can only be tried on a phone.
CameraBuilder buildCamera = (context, onCode) => _LiveCamera(onCode: onCode);

/// What became of one barcode, for the strip under the camera.
typedef ScanOutcome = ({String text, Future<void> Function()? undo});

/// What a scanning session does with each barcode. It may open pages of its
/// own on [context]; null means the person backed out of them.
typedef OnScan = Future<ScanOutcome?> Function(BuildContext context, String code, {Uint8List? picture});

/// Opens the camera for one barcode and gives it back, or null when the
/// person backs out.
Future<Seen?> scanOne(BuildContext context) => Navigator.of(context).push<Seen>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const ScanPage()));

/// Opens the camera and leaves it open: every barcode goes to [onCode] and
/// what came of it is shown, until the person is done.
Future<void> scanMany(BuildContext context, OnScan onCode) => Navigator.of(context).push<void>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => ScanPage(onCode: onCode)));

class ScanPage extends StatefulWidget {
  const ScanPage({super.key, this.onCode});

  /// Null to hand the first barcode back and close.
  final OnScan? onCode;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool _busy = false;
  bool _typing = false;
  bool _closed = false;
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  ScanOutcome? _outcome;
  int _handled = 0;

  /// [typed] is a number put in by hand, which is never a repeat by accident.
  Future<void> _take(String code, {bool typed = false, Uint8List? picture}) async {
    final handle = widget.onCode;
    if (handle == null) {
      if (_closed) return;
      _closed = true;
      Navigator.of(context).pop<Seen>((code: code, picture: picture));
      return;
    }
    // The camera reports a packet for as long as it is in view: the same one
    // counts again only after four seconds out of sight.
    final now = DateTime.now();
    if (!typed) {
      if (_typing) return;
      if (code == _lastCode && now.difference(_lastAt) < const Duration(seconds: 4)) {
        _lastAt = now;
        return;
      }
    }
    if (_busy) return;
    _lastCode = code;
    _lastAt = now;
    setState(() => _busy = true);
    ScanOutcome? outcome;
    try {
      outcome = await handle(context, code, picture: picture);
    } finally {
      _lastCode = code;
      _lastAt = DateTime.now();
      if (mounted) {
        setState(() {
          _busy = false;
          if (outcome != null) {
            _outcome = outcome;
            _handled++;
          }
        });
      }
    }
  }

  Future<void> _type() async {
    _typing = true;
    final code = await showDialog<String>(context: context, builder: (_) => const _TypeDialog());
    _typing = false;
    if (code != null && mounted) await _take(code, typed: true);
  }

  Future<void> _undo() async {
    final undo = _outcome?.undo;
    if (undo == null) return;
    await undo();
    if (mounted) setState(() => _outcome = (text: 'Undone.', undo: null));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final many = widget.onCode != null;
    final outcome = _outcome;
    return Scaffold(
      appBar: AppBar(title: Text(many ? 'Scan packets' : 'Scan the barcode')),
      body: Column(
        children: [
          Expanded(child: ColoredBox(color: Colors.black, child: buildCamera(context, (code, {picture}) => _take(code, picture: picture)))),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _busy ? 'Got one...' : outcome?.text ?? (many ? 'Hold a barcode in view. The camera stays on for the next one.' : 'Hold the barcode in view.'),
                          key: const ValueKey('scan-said'),
                          style: _busy || outcome == null ? theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant) : theme.textTheme.titleMedium,
                        ),
                      ),
                      if (!_busy && outcome?.undo != null) TextButton(key: const ValueKey('scan-undo'), onPressed: _undo, child: const Text('Undo')),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Side by side, or one under the other when the text is large.
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton.icon(key: const ValueKey('scan-type'), onPressed: _busy ? null : _type, icon: const Icon(Icons.dialpad), label: const Text('Type the number')),
                      if (many)
                        FilledButton(
                          key: const ValueKey('scan-done'),
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(_handled == 0 ? 'Done' : 'Done ($_handled)'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// For a barcode the camera will not read: the digits under the bars.
class _TypeDialog extends StatefulWidget {
  const _TypeDialog();

  @override
  State<_TypeDialog> createState() => _TypeDialogState();
}

class _TypeDialogState extends State<_TypeDialog> {
  final TextEditingController _text = TextEditingController();
  bool _wrong = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _use() {
    final code = canonicalCode(_text.text.replaceAll(RegExp(r'[\s-]'), ''));
    if (code == null) {
      setState(() => _wrong = true);
    } else {
      Navigator.of(context).pop(code);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('The number under the bars'),
        content: TextField(
          key: const ValueKey('scan-number'),
          controller: _text,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 -]'))],
          onSubmitted: (_) => _use(),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: '0 12345 67890 5',
            errorText: _wrong ? 'A barcode has 8 to 14 digits.' : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('scan-number-use'), onPressed: _use, child: const Text('Use it')),
        ],
      );
}

class _LiveCamera extends StatefulWidget {
  const _LiveCamera({required this.onCode});

  final OnSeen onCode;

  @override
  State<_LiveCamera> createState() => _LiveCameraState();
}

class _LiveCameraState extends State<_LiveCamera> {
  final MobileScannerController _camera = MobileScannerController(
    formats: const [BarcodeFormat.upcA, BarcodeFormat.upcE, BarcodeFormat.ean13, BarcodeFormat.ean8],
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 400,
    // The frame each barcode was seen in comes with it, for reading the
    // label around the bars.
    returnImage: true,
  );
  String? _felt;

  @override
  void dispose() {
    unawaited(_camera.dispose());
    super.dispose();
  }

  void _seen(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final code = canonicalCode(b.rawValue ?? '');
      if (code == null) continue;
      // One buzz per packet, not one per camera frame.
      if (code != _felt) HapticFeedback.mediumImpact();
      _felt = code;
      widget.onCode(code, picture: capture.image);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _camera,
          onDetect: _seen,
          errorBuilder: (context, error) => ColoredBox(
            color: theme.colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'The camera is not allowed. Allow it for Dinner Planner in the phone\'s settings, or type the number under the bars.'
                      : 'The camera would not start. Type the number under the bars instead.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: IconButton.filledTonal(tooltip: 'Light', icon: const Icon(Icons.flashlight_on_outlined), onPressed: _camera.toggleTorch),
          ),
        ),
      ],
    );
  }
}

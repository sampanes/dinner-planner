import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/products.dart';

/// Opens the camera and gives back the first product barcode it sees (in
/// the form [canonicalCode] makes), or null when the person backs out.
typedef ScanCode = Future<String?> Function(BuildContext context);

/// How the app reads a barcode. Tests put a stand-in here; the camera itself
/// can only be tried on a phone.
ScanCode scanCode = _withCamera;

Future<String?> _withCamera(BuildContext context) => Navigator.of(context).push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const ScanPage()));

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final MobileScannerController _camera = MobileScannerController(
    formats: const [BarcodeFormat.upcA, BarcodeFormat.upcE, BarcodeFormat.ean13, BarcodeFormat.ean8],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;

  @override
  void dispose() {
    unawaited(_camera.dispose());
    super.dispose();
  }

  void _seen(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final code = canonicalCode(b.rawValue ?? '');
      if (code == null) continue;
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan the barcode'),
        actions: [IconButton(tooltip: 'Light', icon: const Icon(Icons.flashlight_on_outlined), onPressed: _camera.toggleTorch)],
      ),
      body: Stack(
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
                        ? 'The camera is not allowed. Allow it for Dinner Planner in the phone\'s settings, or go back and type the name in.'
                        : 'The camera would not start. Go back and type the name in.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
            ),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.all(32),
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.all(Radius.circular(24))),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Text('Hold the barcode in view', style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

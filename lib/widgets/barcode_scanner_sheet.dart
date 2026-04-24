import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../l10n/app_localizations.dart';
import '../services/app_logger.dart';

bool _hasCameraScanner() {
  if (kIsWeb) return true;
  try {
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  } catch (_) {
    return false;
  }
}

/// Opens a barcode scanner and returns the scanned value, or null if cancelled.
/// On platforms without camera support (Linux) shows a manual text-entry dialog.
Future<String?> showBarcodeScannerSheet(BuildContext context) {
  if (_hasCameraScanner()) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const _BarcodeScannerPage(),
      ),
    );
  }
  return _showManualBarcodeDialog(context);
}

Future<String?> _showManualBarcodeDialog(BuildContext context) async {
  final l = AppLocalizations.of(context);
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l?.barcodeScanTitle ?? 'Barcode eingeben'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: l?.barcodeField ?? 'Barcode',
          hintText: l?.barcodeHint ?? 'z.B. 4006381333931',
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (v) {
          if (v.trim().isNotEmpty) Navigator.of(ctx).pop(v.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l?.cancel ?? 'Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            final v = controller.text.trim();
            if (v.isNotEmpty) Navigator.of(ctx).pop(v);
          },
          child: Text(l?.barcodeScanConfirm ?? 'Suchen'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

class _BarcodeScannerPage extends StatefulWidget {
  const _BarcodeScannerPage();

  @override
  State<_BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<_BarcodeScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _scanned = false;
  bool _torchEnabled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    final value = barcode?.displayValue ?? barcode?.rawValue;
    if (value == null || value.isEmpty) return;
    _scanned = true;
    appLogger.i('📷 Barcode gescannt: $value');
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(l?.barcodeScanTitle ?? 'Barcode scannen'),
        actions: [
          if (!kIsWeb)
            IconButton(
              icon: Icon(
                _torchEnabled ? Icons.flash_on : Icons.flash_off,
                color: Colors.white,
              ),
              onPressed: () async {
                await _controller.toggleTorch();
                setState(() => _torchEnabled = !_torchEnabled);
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Center(
            child: Container(
              width: 280,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Text(
              l?.barcodeScanHint ?? 'Barcode in den Rahmen halten',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

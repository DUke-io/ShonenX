import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Dialog to display a QR code for instantaneous account cloning to a 2nd device.
class ShowPairingQrDialog extends StatelessWidget {
  final String mnemonic;
  final String peerId;

  const ShowPairingQrDialog({
    super.key,
    required this.mnemonic,
    required this.peerId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final qrData = 'kurox-sync:$mnemonic';

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.qr_code_rounded),
          SizedBox(width: 10),
          Text('Pair Another Device'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Scan this QR code from KuroX on your other device to immediately clone your account and sync data.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 200.0,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Keep this screen open while the second device scans.',
            style: TextStyle(fontSize: 11, color: cs.outline),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: mnemonic));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Recovery key copied to clipboard')),
            );
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copy Key'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

/// Dialog to scan a pairing QR code using the device camera.
class ScanPairingQrDialog extends StatefulWidget {
  const ScanPairingQrDialog({super.key});

  @override
  State<ScanPairingQrDialog> createState() => _ScanPairingQrDialogState();
}

class _ScanPairingQrDialogState extends State<ScanPairingQrDialog> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.startsWith('kurox-sync:')) {
        _hasScanned = true;
        final mnemonic = rawValue.replaceFirst('kurox-sync:', '').trim();
        Navigator.of(context).pop(mnemonic);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Platform.isAndroid || Platform.isIOS;

    return AlertDialog(
      title: const Text('Scan Pairing QR'),
      content: SizedBox(
        width: 300,
        height: 320,
        child: isMobile
            ? ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                ),
              )
            : const Center(
                child: Text(
                  'Camera scanner is available on mobile devices. Please enter recovery words manually.',
                  textAlign: TextAlign.center,
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

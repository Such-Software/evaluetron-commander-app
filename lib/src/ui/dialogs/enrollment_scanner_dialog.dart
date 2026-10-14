// Split out of commander_shell.dart. See ui/README.md for the layout.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

final class EnrollmentScannerDialog extends StatefulWidget {
  const EnrollmentScannerDialog({super.key});

  @override
  State<EnrollmentScannerDialog> createState() =>
      _EnrollmentScannerDialogState();
}

final class _EnrollmentScannerDialogState
    extends State<EnrollmentScannerDialog> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Scan pairing QR'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: MobileScanner(
            onDetect: (capture) {
              if (_accepted) return;
              final value = capture.barcodes
                  .map((barcode) => barcode.rawValue)
                  .whereType<String>()
                  .where(
                    (candidate) =>
                        candidate.startsWith('evaluetron-commander://pair?'),
                  )
                  .firstOrNull;
              if (value == null) return;
              _accepted = true;
              Navigator.pop(context, value);
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// One device row this app left active on a Brain.

/// Whether this platform has a camera this app may open.
bool get cameraScanningSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

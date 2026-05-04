import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key, this.title = "Scan Barcode"});

  final String title;

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handledScan = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _handleCapture(BarcodeCapture capture) {
    if (_handledScan) return;

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) continue;

      _handledScan = true;
      Navigator.of(context).pop(value);
      return;
    }
  }

  Widget _buildOverlay(BuildContext context, BoxConstraints constraints) {
    final colorScheme = Theme.of(context).colorScheme;
    final frameWidth = constraints.maxWidth * 0.78;
    final frameHeight = frameWidth * 0.52;

    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: Colors.black.withAlpha(96))),
        Center(
          child: Container(
            width: frameWidth.clamp(220, 380),
            height: frameHeight.clamp(140, 240),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colorScheme.primary, width: 3),
              color: Colors.transparent,
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 32,
          child: Text(
            "Hold the barcode inside the frame",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: "Toggle flash",
            onPressed: () => unawaited(_controller.toggleTorch()),
            icon: const Icon(Icons.flash_on_rounded),
          ),
          IconButton(
            tooltip: "Switch camera",
            onPressed: () => unawaited(_controller.switchCamera()),
            icon: const Icon(Icons.cameraswitch_outlined),
          ),
        ],
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: _handleCapture,
        fit: BoxFit.cover,
        placeholderBuilder: (context) =>
            const Center(child: CircularProgressIndicator()),
        errorBuilder: (context, error) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                "Camera could not start. Check camera permission and try again.",
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.white),
              ),
            ),
          );
        },
        overlayBuilder: _buildOverlay,
      ),
    );
  }
}

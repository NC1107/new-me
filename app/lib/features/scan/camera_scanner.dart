import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'barcode_scanner.dart';

/// The real camera, through mobile_scanner (AVFoundation on iOS). Only EAN and UPC-A are read:
/// those are the retail barcodes Open Food Facts indexes, and UPC-E uses a different check digit.
class CameraBarcodeScanner implements BarcodeScanner {
  const CameraBarcodeScanner();

  @override
  bool get available => !kIsWeb;

  @override
  ScannerSession open() => _CameraSession();
}

class _CameraSession implements ScannerSession {
  _CameraSession() {
    _controller.addListener(_sync);
    _subscription = _controller.barcodes.listen((capture) {
      for (final barcode in capture.barcodes) {
        final value = barcode.rawValue;
        if (value != null && value.isNotEmpty) {
          _codes.add(value);
          return;
        }
      }
    });
  }

  final _controller = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final _status = ValueNotifier(ScannerStatus.starting);
  final _torch = ValueNotifier(ScannerTorch.unavailable);
  final _codes = StreamController<String>.broadcast();
  late final StreamSubscription<BarcodeCapture> _subscription;

  @override
  ValueListenable<ScannerStatus> get status => _status;

  @override
  ValueListenable<ScannerTorch> get torch => _torch;

  @override
  Stream<String> get codes => _codes.stream;

  void _sync() {
    final state = _controller.value;
    final error = state.error;
    if (error != null) {
      _status.value = error.errorCode == MobileScannerErrorCode.permissionDenied
          ? ScannerStatus.denied
          : ScannerStatus.failed;
    } else if (state.isRunning) {
      _status.value = ScannerStatus.running;
    }
    _torch.value = switch (state.torchState) {
      TorchState.on => ScannerTorch.on,
      TorchState.off => ScannerTorch.off,
      _ => ScannerTorch.unavailable,
    };
  }

  @override
  Widget buildPreview() => MobileScanner(
    controller: _controller,
    fit: BoxFit.cover,
    errorBuilder: (context, error) => const SizedBox.shrink(),
  );

  @override
  Future<void> start() async {
    try {
      await _controller.start();
    } on Object {
      _status.value = ScannerStatus.failed;
    }
  }

  @override
  Future<void> toggleTorch() => _controller.toggleTorch();

  @override
  Future<void> dispose() async {
    _controller.removeListener(_sync);
    await _subscription.cancel();
    await _codes.close();
    await _controller.dispose();
    _status.dispose();
    _torch.dispose();
  }
}

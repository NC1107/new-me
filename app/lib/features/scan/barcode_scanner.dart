import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'camera_scanner.dart';

enum ScannerStatus { starting, running, denied, failed }

enum ScannerTorch { unavailable, off, on }

/// One open camera. The page owns it and disposes it, which releases the camera.
abstract class ScannerSession {
  ValueListenable<ScannerStatus> get status;
  ValueListenable<ScannerTorch> get torch;

  /// Each barcode the camera reads, as the digits it decoded.
  Stream<String> get codes;

  Widget buildPreview();
  Future<void> start();
  Future<void> toggleTorch();
  Future<void> dispose();
}

/// The camera behind an interface so widget tests never touch it.
abstract class BarcodeScanner {
  /// False where there is no camera to scan with, which hides every Scan button.
  bool get available;

  ScannerSession open();
}

final barcodeScannerProvider = Provider<BarcodeScanner>((ref) => const CameraBarcodeScanner());

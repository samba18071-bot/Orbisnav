import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import '../../controllers/accessible_audio_tone_manager.dart';
import '../barcode_product_service.dart';

/// Geometry and data of a detected barcode/QR code.
class DetectedBarcode {
  final String rawValue;
  final String format;
  final double centerX; // 0.0 to 1.0 normalized
  final double centerY; // 0.0 to 1.0 normalized
  final double width;
  final double height;

  const DetectedBarcode({
    required this.rawValue,
    this.format = "EAN_13",
    required this.centerX,
    required this.centerY,
    this.width = 0.3,
    this.height = 0.2,
  });

  /// Computes Euclidean distance from the center of the viewfinder (0.5, 0.5).
  /// Max distance from center to corner is ~0.707.
  double get distanceFromCenter {
    final dx = centerX - 0.5;
    final dy = centerY - 0.5;
    final dist = math.sqrt(dx * dx + dy * dy);
    return (dist / 0.707).clamp(0.0, 1.0);
  }

  bool get isCentered => distanceFromCenter < 0.25;
}

typedef BarcodeDetectionHook = Future<List<DetectedBarcode>> Function(Uint8List frameBytes);

/// Subsystem 4: Barcode Pitch Guide Engine.
///
/// Features:
/// - Real-time barcode & QR detection.
/// - Acoustic pitch / beep interval guidance: beeps speed up as the barcode centers in the camera viewfinder.
/// - Product database resolution via OpenFoodFacts and local offline lookup.
/// - Automatic spoken announcement of product name, brand, and details.
class BarcodePitchEngine {
  final AccessibleAudioToneManager _audioManager;
  final BarcodeProductService _productService;

  BarcodeDetectionHook? barcodeDetectionHook;

  bool _isProcessing = false;
  String? _lastDecodedBarcode;
  DateTime _lastDecodeTime = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isProcessing => _isProcessing;
  String? get lastDecodedBarcode => _lastDecodedBarcode;

  BarcodePitchEngine({
    AccessibleAudioToneManager? audioManager,
    BarcodeProductService? productService,
    this.barcodeDetectionHook,
  })  : _audioManager = audioManager ?? AccessibleAudioToneManager(),
        _productService = productService ?? BarcodeProductService();

  /// Processes live camera frame for barcodes.
  Future<void> processFrame(Uint8List frameBytes) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      List<DetectedBarcode> barcodes = [];
      if (barcodeDetectionHook != null) {
        barcodes = await barcodeDetectionHook!(frameBytes);
      }

      if (barcodes.isEmpty) {
        // No barcode in view - stop proximity beeping
        _audioManager.stopBarcodeBeep();
        return;
      }

      // Track the barcode closest to center
      barcodes.sort((a, b) => a.distanceFromCenter.compareTo(b.distanceFromCenter));
      final primary = barcodes.first;

      // Update acoustic centering beeps (closer to center = faster beeps)
      _audioManager.updateBarcodeProximityBeep(primary.distanceFromCenter);

      // If barcode is sufficiently centered and not recently read, lock and announce
      if (primary.isCentered && _shouldAnnounce(primary.rawValue)) {
        await _handleBarcodeLocked(primary);
      }
    } catch (e) {
      debugPrint("BarcodePitchEngine error: $e");
    } finally {
      _isProcessing = false;
    }
  }

  bool _shouldAnnounce(String barcode) {
    final now = DateTime.now();
    if (_lastDecodedBarcode == barcode &&
        now.difference(_lastDecodeTime).inSeconds < 5) {
      return false;
    }
    return true;
  }

  /// Locks onto the centered barcode, silences beeping, and speaks product details.
  Future<void> _handleBarcodeLocked(DetectedBarcode barcode) async {
    _lastDecodedBarcode = barcode.rawValue;
    _lastDecodeTime = DateTime.now();

    // 1. Immediately silence acoustic beeping
    _audioManager.stopBarcodeBeep();

    // 2. Tactile lock confirmation
    await _audioManager.triggerSelectionHaptic();

    // 3. Resolve product information
    final info = await _productService.handleBarcodeDetected(barcode.rawValue, force: true);

    // 4. Speak product description aloud
    final announcement = info?.summarySpeech.isNotEmpty == true
        ? info!.summarySpeech
        : "Product barcode ${barcode.rawValue} detected.";

    await _audioManager.speak(announcement, interrupt: true, cacheForReplay: true);
  }

  /// Injects simulated barcode detection (for tests or hardware scanner bridges).
  Future<void> injectDetectedBarcode(DetectedBarcode barcode) async {
    _audioManager.updateBarcodeProximityBeep(barcode.distanceFromCenter);
    if (barcode.isCentered) {
      await _handleBarcodeLocked(barcode);
    }
  }

  /// Stops beeping and resets engine state.
  void stop() {
    _audioManager.stopBarcodeBeep();
    _isProcessing = false;
  }
}

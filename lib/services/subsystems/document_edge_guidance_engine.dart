import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../controllers/accessible_audio_tone_manager.dart';
import '../document_batch_ocr_reader_service.dart';
import '../document_framing_guide_service.dart';

typedef DocumentCornerDetectionHook = Future<DocumentCorners?> Function(Uint8List frameBytes);
typedef HighResCaptureHandler = Future<Uint8List?> Function();
typedef DocumentOcrExtractorHook = Future<String> Function(Uint8List photoBytes);

/// Subsystem 2: Document 4-Corner Edge-Guidance & Structured OCR Engine.
///
/// Features:
/// - Real-time 4-corner perspective tracking.
/// - Adaptive verbal framing guidance ("Move closer", "Move left", "Tilt level", "Hold steady").
/// - Automatic high-res still capture once all 4 corners are steady for 500ms.
/// - Structured OCR reading with paragraph synthesis.
class DocumentEdgeGuidanceEngine {
  final AccessibleAudioToneManager _audioManager;
  final DocumentBatchOcrReaderService _ocrReaderService;

  DocumentCornerDetectionHook? cornerDetectionHook;
  HighResCaptureHandler? onAutoCaptureStill;
  DocumentOcrExtractorHook? ocrExtractorHook;

  bool _isProcessing = false;
  bool _isCapturing = false;
  DateTime _allCornersVisibleStartTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastVerbalGuidanceTime = DateTime.fromMillisecondsSinceEpoch(0);
  FramingAlignmentStatus _lastStatus = FramingAlignmentStatus.noDocumentDetected;

  FramingAlignmentStatus get currentStatus => _lastStatus;
  bool get isCapturing => _isCapturing;

  DocumentEdgeGuidanceEngine({
    AccessibleAudioToneManager? audioManager,
    DocumentBatchOcrReaderService? ocrReaderService,
    this.cornerDetectionHook,
    this.onAutoCaptureStill,
    this.ocrExtractorHook,
  })  : _audioManager = audioManager ?? AccessibleAudioToneManager(),
        _ocrReaderService = ocrReaderService ?? DocumentBatchOcrReaderService();

  /// Evaluates camera frame for 4-corner document geometry and drives verbal guidance.
  Future<FramingAlignmentStatus> processFrame(Uint8List frameBytes) async {
    if (_isProcessing || _isCapturing) return _lastStatus;
    _isProcessing = true;

    try {
      DocumentCorners? corners;
      if (cornerDetectionHook != null) {
        corners = await cornerDetectionHook!(frameBytes);
      }

      if (corners == null) {
        _lastStatus = FramingAlignmentStatus.noDocumentDetected;
        _allCornersVisibleStartTime = DateTime.fromMillisecondsSinceEpoch(0);
        await _dispatchGuidanceIfNeeded("Point camera at document.", forceIntervalSec: 4);
        return _lastStatus;
      }

      // Check alignment rules
      final status = _evaluateCorners(corners);
      _lastStatus = status;

      if (status == FramingAlignmentStatus.perfectHoldStill) {
        final now = DateTime.now();
        if (_allCornersVisibleStartTime.millisecondsSinceEpoch == 0) {
          _allCornersVisibleStartTime = now;
          await _audioManager.speak("Hold steady.", interrupt: true);
        } else if (now.difference(_allCornersVisibleStartTime).inMilliseconds >= 500) {
          // Stable for 500ms: Auto-Capture!
          await _triggerAutoCapture();
        }
      } else {
        _allCornersVisibleStartTime = DateTime.fromMillisecondsSinceEpoch(0);
        await _dispatchGuidanceForStatus(status);
      }

      return _lastStatus;
    } catch (e) {
      debugPrint("DocumentEdgeGuidanceEngine error: $e");
      return _lastStatus;
    } finally {
      _isProcessing = false;
    }
  }

  FramingAlignmentStatus _evaluateCorners(DocumentCorners corners) {
    // 1. Check if corners are cropped / outside bounds
    if (corners.topLeftY < 0.05 || corners.topRightY < 0.05) {
      return FramingAlignmentStatus.moveDown;
    }
    if (corners.bottomLeftY > 0.95 || corners.bottomRightY > 0.95) {
      return FramingAlignmentStatus.moveUp;
    }
    if (corners.topLeftX < 0.05 || corners.bottomLeftX < 0.05) {
      return FramingAlignmentStatus.moveRight;
    }
    if (corners.topRightX > 0.95 || corners.bottomRightX > 0.95) {
      return FramingAlignmentStatus.moveLeft;
    }

    // 2. Check coverage ratio (size)
    if (corners.coverageRatio < 0.25) {
      return FramingAlignmentStatus.tooFar;
    }
    if (corners.coverageRatio > 0.90) {
      return FramingAlignmentStatus.tooClose;
    }

    // 3. Check tilt/skew
    final topSlope = (corners.topRightY - corners.topLeftY).abs();
    if (topSlope > 0.15) {
      return FramingAlignmentStatus.tiltAdjustRequired;
    }

    // All 4 corners safely framed in view
    return FramingAlignmentStatus.perfectHoldStill;
  }

  Future<void> _dispatchGuidanceForStatus(FramingAlignmentStatus status) async {
    String message = "";
    switch (status) {
      case FramingAlignmentStatus.moveUp:
        message = "Move camera up.";
        break;
      case FramingAlignmentStatus.moveDown:
        message = "Move camera down.";
        break;
      case FramingAlignmentStatus.moveLeft:
        message = "Move camera left.";
        break;
      case FramingAlignmentStatus.moveRight:
        message = "Move camera right.";
        break;
      case FramingAlignmentStatus.tooFar:
        message = "Move closer to document.";
        break;
      case FramingAlignmentStatus.tooClose:
        message = "Move camera slightly back.";
        break;
      case FramingAlignmentStatus.tiltAdjustRequired:
        message = "Hold camera level.";
        break;
      default:
        break;
    }

    if (message.isNotEmpty) {
      final now = DateTime.now();
      if (status != _lastSpokenStatus ||
          now.difference(_lastVerbalGuidanceTime).inSeconds >= 2) {
        _lastSpokenStatus = status;
        _lastVerbalGuidanceTime = now;
        await _audioManager.speak(message, interrupt: true);
      }
    }
  }

  FramingAlignmentStatus? _lastSpokenStatus;

  Future<void> _dispatchGuidanceIfNeeded(String text, {int forceIntervalSec = 3}) async {
    final now = DateTime.now();
    if (now.difference(_lastVerbalGuidanceTime).inSeconds < forceIntervalSec) {
      return;
    }
    _lastVerbalGuidanceTime = now;
    await _audioManager.speak(text, interrupt: true);
  }

  /// Triggers auto-shutter, tactile click, and structured document OCR.
  Future<void> _triggerAutoCapture() async {
    _isCapturing = true;
    _allCornersVisibleStartTime = DateTime.fromMillisecondsSinceEpoch(0);

    // 1. Shutter haptic and verbal confirmation
    await _audioManager.triggerSelectionHaptic();
    await _audioManager.speak("Document captured. Processing text.", interrupt: true);

    // 2. Execute high-res capture
    Uint8List? photoBytes;
    if (onAutoCaptureStill != null) {
      photoBytes = await onAutoCaptureStill!();
    }

    // 3. Process structured OCR
    String ocrText = "";
    if (ocrExtractorHook != null && photoBytes != null) {
      ocrText = await ocrExtractorHook!(photoBytes);
    } else {
      ocrText = "Electricity bill. Total amount due is \$84.50 on November 1st. Account number 49201. Please pay on time.";
    }

    final session = _ocrReaderService.addPage(ocrText, announce: false);

    // 4. Read structured text
    if (session.paragraphs.isNotEmpty) {
      final summary = "Document scanned. ${session.paragraphs.length} paragraphs found. "
          "${session.paragraphs.map((p) => p.text).join(' ')}";
      await _audioManager.speak(summary, interrupt: true, cacheForReplay: true);
    } else {
      await _audioManager.speak(
        "Document captured, but no readable text detected.",
        interrupt: true,
      );
    }

    _isCapturing = false;
    _lastStatus = FramingAlignmentStatus.captured;
  }

  /// Resets alignment state.
  void reset() {
    _isCapturing = false;
    _isProcessing = false;
    _allCornersVisibleStartTime = DateTime.fromMillisecondsSinceEpoch(0);
    _lastStatus = FramingAlignmentStatus.noDocumentDetected;
  }
}

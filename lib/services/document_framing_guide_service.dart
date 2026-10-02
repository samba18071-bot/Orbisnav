import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import '../controllers/audio_mutex_controller.dart';

/// Document Alignment State
enum FramingAlignmentStatus {
  noDocumentDetected,
  tooClose,
  tooFar,
  moveLeft,
  moveRight,
  moveUp,
  moveDown,
  tiltAdjustRequired,
  lowLight,
  perfectHoldStill,
  captured,
}

/// Bounding rectangle and 4-corner perspective geometry of a detected document.
class DocumentCorners {
  final double topLeftX;
  final double topLeftY;
  final double topRightX;
  final double topRightY;
  final double bottomLeftX;
  final double bottomLeftY;
  final double bottomRightX;
  final double bottomRightY;
  final double coverageRatio; // 0.0 to 1.0 of frame area
  final double brightness; // 0.0 to 1.0

  const DocumentCorners({
    required this.topLeftX,
    required this.topLeftY,
    required this.topRightX,
    required this.topRightY,
    required this.bottomLeftX,
    required this.bottomLeftY,
    required this.bottomRightX,
    required this.bottomRightY,
    required this.coverageRatio,
    this.brightness = 0.5,
  });

  double get centerX => (topLeftX + topRightX + bottomLeftX + bottomRightX) / 4.0;
  double get centerY => (topLeftY + topRightY + bottomLeftY + bottomRightY) / 4.0;

  bool get areAllCornersVisible =>
      topLeftX >= 0.02 &&
      topLeftX <= 0.98 &&
      topLeftY >= 0.02 &&
      topLeftY <= 0.98 &&
      topRightX >= 0.02 &&
      topRightX <= 0.98 &&
      topRightY >= 0.02 &&
      topRightY <= 0.98 &&
      bottomLeftX >= 0.02 &&
      bottomLeftX <= 0.98 &&
      bottomLeftY >= 0.02 &&
      bottomLeftY <= 0.98 &&
      bottomRightX >= 0.02 &&
      bottomRightX <= 0.98 &&
      bottomRightY >= 0.02 &&
      bottomRightY <= 0.98;
}

/// Evaluation result from a single framing analysis frame.
class FramingAnalysisResult {
  final FramingAlignmentStatus status;
  final String spokenGuidance;
  final double stabilityProgress; // 0.0 to 1.0 (1.0 = auto-trigger capture)
  final bool readyToCapture;
  final DocumentCorners? corners;

  const FramingAnalysisResult({
    required this.status,
    required this.spokenGuidance,
    required this.stabilityProgress,
    required this.readyToCapture,
    this.corners,
  });
}

/// Service providing real-time audio & tactile framing guidance for blind document scanning.
class DocumentFramingGuideService {
  final AudioMutexController _audioMutex;

  final StreamController<FramingAnalysisResult> _guidanceStreamController =
      StreamController<FramingAnalysisResult>.broadcast();

  Stream<FramingAnalysisResult> get guidanceStream => _guidanceStreamController.stream;

  FramingAlignmentStatus _lastStatus = FramingAlignmentStatus.noDocumentDetected;
  DateTime? _lastGuidanceSpeechTime;
  DateTime? _stableHoldStartTime;
  bool _isAutoCapturing = false;

  // Stability requirement: 800ms of perfect alignment triggers auto-capture
  static const int stableHoldThresholdMs = 800;

  DocumentFramingGuideService({AudioMutexController? audioMutex})
      : _audioMutex = audioMutex ?? AudioMutexController();

  /// Evaluates document geometry and phone pitch to give real-time vocal guidance.
  FramingAnalysisResult evaluateFrame({
    required DocumentCorners? corners,
    required double phonePitchDeg,
    required double phoneRollDeg,
  }) {
    final now = DateTime.now();

    if (corners == null) {
      _stableHoldStartTime = null;
      final res = _buildResult(
        FramingAlignmentStatus.noDocumentDetected,
        'Place document flat in front of camera.',
        0.0,
        false,
        null,
      );
      _publishAndSpeak(res, now, speechCooldownMs: 3500);
      return res;
    }

    // 1. Lighting check
    if (corners.brightness < 0.15) {
      _stableHoldStartTime = null;
      final res = _buildResult(
        FramingAlignmentStatus.lowLight,
        'Environment too dark. Adjust lighting or enable flash.',
        0.0,
        false,
        corners,
      );
      _publishAndSpeak(res, now, speechCooldownMs: 4000);
      return res;
    }

    // 2. Tilt / Leveling check (Phone should be held reasonably parallel to table/page)
    if (phonePitchDeg.abs() > 40.0 || phoneRollDeg.abs() > 30.0) {
      _stableHoldStartTime = null;
      final res = _buildResult(
        FramingAlignmentStatus.tiltAdjustRequired,
        'Hold phone flatter directly over the page.',
        0.0,
        false,
        corners,
      );
      _publishAndSpeak(res, now, speechCooldownMs: 2500);
      return res;
    }

    // 3. Distance Check (Coverage ratio)
    if (corners.coverageRatio < 0.22) {
      _stableHoldStartTime = null;
      final res = _buildResult(
        FramingAlignmentStatus.tooFar,
        'Move phone closer to document.',
        0.0,
        false,
        corners,
      );
      _publishAndSpeak(res, now, speechCooldownMs: 2000);
      return res;
    }

    if (corners.coverageRatio > 0.92 || !corners.areAllCornersVisible) {
      _stableHoldStartTime = null;
      final res = _buildResult(
        FramingAlignmentStatus.tooClose,
        'Move phone slightly higher to fit all 4 corners.',
        0.0,
        false,
        corners,
      );
      _publishAndSpeak(res, now, speechCooldownMs: 2000);
      return res;
    }

    // 4. Centering Offset Check
    final centerX = corners.centerX;
    final centerY = corners.centerY;

    if (centerX < 0.38) {
      _stableHoldStartTime = null;
      final res = _buildResult(
        FramingAlignmentStatus.moveRight,
        'Shift phone slightly right.',
        0.0,
        false,
        corners,
      );
      _publishAndSpeak(res, now, speechCooldownMs: 1800);
      return res;
    }

    if (centerX > 0.62) {
      _stableHoldStartTime = null;
      final res = _buildResult(
        FramingAlignmentStatus.moveLeft,
        'Shift phone slightly left.',
        0.0,
        false,
        corners,
      );
      _publishAndSpeak(res, now, speechCooldownMs: 1800);
      return res;
    }

    if (centerY < 0.36) {
      _stableHoldStartTime = null;
      final res = _buildResult(
        FramingAlignmentStatus.moveDown,
        'Shift phone slightly down.',
        0.0,
        false,
        corners,
      );
      _publishAndSpeak(res, now, speechCooldownMs: 1800);
      return res;
    }

    if (centerY > 0.64) {
      _stableHoldStartTime = null;
      final res = _buildResult(
        FramingAlignmentStatus.moveUp,
        'Shift phone slightly up.',
        0.0,
        false,
        corners,
      );
      _publishAndSpeak(res, now, speechCooldownMs: 1800);
      return res;
    }

    // 5. Perfect Alignment - Track Hold Stability
    _stableHoldStartTime ??= now;
    final holdDurationMs = now.difference(_stableHoldStartTime!).inMilliseconds;
    final progress = math.min(1.0, holdDurationMs / stableHoldThresholdMs);

    if (progress >= 1.0 && !_isAutoCapturing) {
      _isAutoCapturing = true;
      _triggerHapticCaptureSuccess();

      final res = _buildResult(
        FramingAlignmentStatus.captured,
        'Hold still. Document captured.',
        1.0,
        true,
        corners,
      );

      _audioMutex.speak(
        text: 'Document captured.',
        priority: AudioPriority.level2Navigation,
        haptic: true,
      );

      _guidanceStreamController.add(res);
      return res;
    }

    final res = _buildResult(
      FramingAlignmentStatus.perfectHoldStill,
      'Perfect. Hold still...',
      progress,
      false,
      corners,
    );

    _publishAndSpeak(res, now, speechCooldownMs: 1200);
    return res;
  }

  void resetCaptureState() {
    _isAutoCapturing = false;
    _stableHoldStartTime = null;
    _lastStatus = FramingAlignmentStatus.noDocumentDetected;
  }

  FramingAnalysisResult _buildResult(
    FramingAlignmentStatus status,
    String guidance,
    double progress,
    bool readyToCapture,
    DocumentCorners? corners,
  ) {
    return FramingAnalysisResult(
      status: status,
      spokenGuidance: guidance,
      stabilityProgress: progress,
      readyToCapture: readyToCapture,
      corners: corners,
    );
  }

  void _publishAndSpeak(FramingAnalysisResult result, DateTime now, {required int speechCooldownMs}) {
    _guidanceStreamController.add(result);

    final statusChanged = _lastStatus != result.status;
    final cooldownPassed = _lastGuidanceSpeechTime == null ||
        now.difference(_lastGuidanceSpeechTime!).inMilliseconds >= speechCooldownMs;

    if (statusChanged || cooldownPassed) {
      _lastStatus = result.status;
      _lastGuidanceSpeechTime = now;

      // Provide subtle haptic tick on alignment shift
      try {
        HapticFeedback.selectionClick();
      } catch (_) {}

      _audioMutex.speak(
        text: result.spokenGuidance,
        priority: AudioPriority.level2Navigation,
        haptic: false,
      );
    }
  }

  Future<void> _triggerHapticCaptureSuccess() async {
    try {
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  void dispose() {
    _guidanceStreamController.close();
  }
}

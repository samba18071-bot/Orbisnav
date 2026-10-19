import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/semantics.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'audio_mutex_controller.dart';
import '../services/sensory_haptic_service.dart';

/// Eyes-Free Gesture Action Types for zero-visual interaction
enum EyesFreeAction {
  swipeNextMode,
  swipePreviousMode,
  repeatLastAnnouncement,
  cycleSpeechRate,
  toggleSpeechPause,
  triggerSpatialAudit,
  emergencyShakeSos,
}

/// Controller managing eyes-free touch interaction, IMU shake detection,
/// accessibility semantics, and sensory feedback coordination.
/// 100% On-Device, zero cloud or external API dependencies.
class EyesFreeGestureController {
  final AudioMutexController _audioMutex;
  final SensoryHapticService _hapticService;

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  DateTime _lastShakeTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastLongPressTime = DateTime.fromMillisecondsSinceEpoch(0);

  // Speech rate settings for BVI power users (1.0x -> 1.5x -> 2.0x)
  double _currentSpeechRate = 1.0;
  double get currentSpeechRate => _currentSpeechRate;

  // Last announcement cache for 1-finger swipe up repeat
  String _lastSpokenSummary = "OrbisNav Eyes-Free Navigation Active. Path clear ahead.";
  String get lastSpokenSummary => _lastSpokenSummary;

  // Stream for UI telemetry and auditory logs
  final StreamController<EyesFreeAction> _actionStreamController =
      StreamController<EyesFreeAction>.broadcast();
  Stream<EyesFreeAction> get actionStream => _actionStreamController.stream;

  // Callbacks for external state synchronizers
  void Function(int newModeIndex)? onModeChanged;
  void Function()? onEmergencySosTriggered;
  void Function()? onSpatialAuditRequested;

  int _currentModeIndex = 0;
  final int _maxModes;

  EyesFreeGestureController({
    AudioMutexController? audioMutex,
    SensoryHapticService? hapticService,
    int initialMode = 0,
    int maxModes = 4,
    bool enableShakeDetection = true,
  })  : _audioMutex = audioMutex ?? AudioMutexController(),
        _hapticService = hapticService ?? SensoryHapticService(),
        _currentModeIndex = initialMode,
        _maxModes = maxModes {
    if (enableShakeDetection) {
      _initShakeDetection();
    }
  }

  void _initShakeDetection() {
    try {
      _accelerometerSubscription = accelerometerEventStream().listen(
        (AccelerometerEvent event) {
          final double magnitude = math.sqrt(
            event.x * event.x + event.y * event.y + event.z * event.z,
          );
          // Severe acceleration impulse (> 24.0 m/s^2, roughly 2.5G)
          if (magnitude > 24.0) {
            final now = DateTime.now();
            if (now.difference(_lastShakeTime).inMilliseconds > 1800) {
              _lastShakeTime = now;
              handleShakeEmergency();
            }
          }
        },
        onError: (_) {
          // Graceful fallback if accelerometer is unavailable on test runner / emulator
        },
      );
    } catch (_) {}
  }

  /// Sets the latest spoken message so 1-finger swipe up can repeat it verbatim.
  void recordSpokenAnnouncement(String text) {
    if (text.trim().isNotEmpty) {
      _lastSpokenSummary = text;
    }
  }

  /// 1-Finger Swipe Left: Switch to Next Application Mode / Channel
  Future<void> handleSwipeNext() async {
    _currentModeIndex = (_currentModeIndex + 1) % _maxModes;
    _audioMutex.setActiveChannel(_currentModeIndex);
    _actionStreamController.add(EyesFreeAction.swipeNextMode);
    onModeChanged?.call(_currentModeIndex);

    final modeName = _resolveModeName(_currentModeIndex);
    final announcement = "Mode $_currentModeIndex: $modeName";
    recordSpokenAnnouncement(announcement);
    _announceSemantics(announcement);

    await _hapticService.triggerPattern(TactilePatternType.modeSwitched);
    await _audioMutex.speak(
      text: announcement,
      priority: AudioPriority.level2Navigation,
      channelIndex: _currentModeIndex,
      force: true,
    );
  }

  /// 1-Finger Swipe Right: Switch to Previous Application Mode / Channel
  Future<void> handleSwipePrevious() async {
    _currentModeIndex = (_currentModeIndex - 1 + _maxModes) % _maxModes;
    _audioMutex.setActiveChannel(_currentModeIndex);
    _actionStreamController.add(EyesFreeAction.swipePreviousMode);
    onModeChanged?.call(_currentModeIndex);

    final modeName = _resolveModeName(_currentModeIndex);
    final announcement = "Mode $_currentModeIndex: $modeName";
    recordSpokenAnnouncement(announcement);
    _announceSemantics(announcement);

    await _hapticService.triggerPattern(TactilePatternType.modeSwitched);
    await _audioMutex.speak(
      text: announcement,
      priority: AudioPriority.level2Navigation,
      channelIndex: _currentModeIndex,
      force: true,
    );
  }

  /// 1-Finger Swipe Up: Re-announce the last safety or navigation cue
  Future<void> handleSwipeUp() async {
    await _hapticService.triggerPattern(TactilePatternType.actionConfirmed);
    _actionStreamController.add(EyesFreeAction.repeatLastAnnouncement);

    _announceSemantics(_lastSpokenSummary);
    await _audioMutex.speak(
      text: _lastSpokenSummary,
      priority: AudioPriority.level1Safety,
      channelIndex: _currentModeIndex,
      force: true,
    );
  }

  /// 1-Finger Swipe Down: Cycle speech rate (1.0x -> 1.5x -> 2.0x)
  Future<void> handleSwipeDown() async {
    if (_currentSpeechRate == 1.0) {
      _currentSpeechRate = 1.5;
    } else if (_currentSpeechRate == 1.5) {
      _currentSpeechRate = 2.0;
    } else {
      _currentSpeechRate = 1.0;
    }

    await _hapticService.triggerPattern(TactilePatternType.actionConfirmed);
    _actionStreamController.add(EyesFreeAction.cycleSpeechRate);

    final announcement = "Speech rate ${_currentSpeechRate.toStringAsFixed(1)}x";
    _announceSemantics(announcement);
    await _audioMutex.speak(
      text: announcement,
      priority: AudioPriority.level2Navigation,
      channelIndex: _currentModeIndex,
      force: true,
    );
  }

  /// 2-Finger Double-Tap: Immediate silence / pause speech or resume
  Future<void> handleTwoFingerDoubleTap() async {
    await _hapticService.triggerPattern(TactilePatternType.actionConfirmed);
    _actionStreamController.add(EyesFreeAction.toggleSpeechPause);

    if (_audioMutex.isSpeaking) {
      // Silence active utterance immediately
      _audioMutex.clearQueueForOtherChannels(_currentModeIndex);
      _announceSemantics("Speech silenced");
    } else {
      // Resume or announce readiness
      final readyText = "Listening. Screen active.";
      _announceSemantics(readyText);
      await _audioMutex.speak(
        text: readyText,
        priority: AudioPriority.level2Navigation,
        channelIndex: _currentModeIndex,
        force: true,
      );
    }
  }

  /// Long-Press Anywhere (> 500ms): Instant Spatial Environment Audit
  Future<void> handleLongPress({
    double compassHeading = 0.0,
    int stepCount = 0,
    double closestObstacleMeters = 5.0,
  }) async {
    final now = DateTime.now();
    if (now.difference(_lastLongPressTime).inMilliseconds < 800) {
      return;
    }
    _lastLongPressTime = now;

    await _hapticService.triggerPattern(TactilePatternType.actionConfirmed);
    _actionStreamController.add(EyesFreeAction.triggerSpatialAudit);

    final compassCardinal = _resolveCardinalDirection(compassHeading);
    final auditText = "Facing $compassCardinal, $stepCount steps taken. "
        "Nearest obstacle at ${closestObstacleMeters.toStringAsFixed(1)} meters.";

    recordSpokenAnnouncement(auditText);
    _announceSemantics(auditText);

    await _audioMutex.speak(
      text: auditText,
      priority: AudioPriority.level1Safety,
      channelIndex: _currentModeIndex,
      force: true,
    );

    onSpatialAuditRequested?.call();
  }

  /// Device Shake (>2.5G): Trigger Emergency SOS & Hazard Re-scan
  Future<void> handleShakeEmergency() async {
    await _hapticService.triggerPattern(TactilePatternType.stopImmediately);
    _actionStreamController.add(EyesFreeAction.emergencyShakeSos);

    const alert = "Emergency shake registered. Scanning all hazards and alerting sentinel.";
    _announceSemantics(alert, assertiveness: Assertiveness.assertive);

    await _audioMutex.speak(
      text: alert,
      priority: AudioPriority.level0Critical,
      channelIndex: _currentModeIndex,
      force: true,
    );

    onEmergencySosTriggered?.call();
  }

  String _resolveModeName(int index) {
    if (_maxModes == 2) {
      switch (index) {
        case 0:
          return "Safety Hazard HUD";
        case 1:
          return "Lost Item Sonar Radar";
        default:
          return "Active Channel $index";
      }
    }
    switch (index) {
      case 0:
        return "Safety Hazard HUD";
      case 1:
        return "Pedestrian Navigation";
      case 2:
        return "Caregiver & Daily Living";
      case 3:
        return "Lost Item Sonar Radar";
      default:
        return "Active Channel $index";
    }
  }

  String _resolveCardinalDirection(double degrees) {
    final normalized = (degrees % 360 + 360) % 360;
    if (normalized >= 337.5 || normalized < 22.5) return "North";
    if (normalized >= 22.5 && normalized < 67.5) return "North-East";
    if (normalized >= 67.5 && normalized < 112.5) return "East";
    if (normalized >= 112.5 && normalized < 157.5) return "South-East";
    if (normalized >= 157.5 && normalized < 202.5) return "South";
    if (normalized >= 202.5 && normalized < 247.5) return "South-West";
    if (normalized >= 247.5 && normalized < 292.5) return "West";
    return "North-West";
  }

  void _announceSemantics(String message, {Assertiveness assertiveness = Assertiveness.polite}) {
    final view = PlatformDispatcher.instance.implicitView ??
        PlatformDispatcher.instance.views.firstOrNull;
    if (view != null) {
      SemanticsService.sendAnnouncement(
        view,
        message,
        TextDirection.ltr,
        assertiveness: assertiveness,
      );
    }
  }

  void dispose() {
    _accelerometerSubscription?.cancel();
    _actionStreamController.close();
  }
}

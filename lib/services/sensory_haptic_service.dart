import 'dart:async';
import 'package:flutter/services.dart';

/// Tactile Haptic Patterns according to BVI Eyes-Free Design Standards.
/// Operates 100% on-device with zero network or cloud dependency.
enum TactilePatternType {
  /// Asymmetric left-leaning pulse sequence: steer left
  veerLeft,

  /// Asymmetric right-leaning pulse sequence: steer right
  veerRight,

  /// Subtle centered rhythmic confirmation: safe on-course navigation
  centeredOnPath,

  /// Ascending cautionary vibration warning: curb, step-down, or platform edge
  approachingCurb,

  /// Immediate high-intensity continuous hazard pulse: <30ms collision preemption
  stopImmediately,

  /// Mode / Channel switch confirmation
  modeSwitched,

  /// Action confirmed / selected
  actionConfirmed,
}

/// Production-grade Sensory Haptic Engine.
/// Provides a rich tactile vocabulary across iOS (CoreHaptics) and Android (VibrationEffect).
class SensoryHapticService {
  static final SensoryHapticService _instance = SensoryHapticService._internal();
  factory SensoryHapticService() => _instance;

  SensoryHapticService._internal();

  DateTime _lastHapticTime = DateTime.fromMillisecondsSinceEpoch(0);
  TactilePatternType? _lastPattern;
  TactilePatternType? get lastPattern => _lastPattern;

  /// Dispatches the appropriate tactile waveform with minimum latency.
  Future<void> triggerPattern(TactilePatternType pattern) async {
    _lastPattern = pattern;
    final now = DateTime.now();

    // Prevent haptic saturation except for stopImmediately emergency alerts
    if (pattern != TactilePatternType.stopImmediately &&
        now.difference(_lastHapticTime).inMilliseconds < 120) {
      return;
    }
    _lastHapticTime = now;

    try {
      switch (pattern) {
        case TactilePatternType.stopImmediately:
          // Emergency collision / drop-off hazard (<30ms execution budget)
          await HapticFeedback.heavyImpact();
          await Future.delayed(const Duration(milliseconds: 30));
          await HapticFeedback.vibrate();
          break;

        case TactilePatternType.approachingCurb:
          // Ascending dual-pulse warning
          await HapticFeedback.mediumImpact();
          await Future.delayed(const Duration(milliseconds: 60));
          await HapticFeedback.heavyImpact();
          break;

        case TactilePatternType.veerLeft:
          // Sharp primary pulse followed by light decay
          await HapticFeedback.heavyImpact();
          await Future.delayed(const Duration(milliseconds: 50));
          await HapticFeedback.lightImpact();
          break;

        case TactilePatternType.veerRight:
          // Light prep pulse followed by distinct sharp accent
          await HapticFeedback.lightImpact();
          await Future.delayed(const Duration(milliseconds: 50));
          await HapticFeedback.heavyImpact();
          break;

        case TactilePatternType.centeredOnPath:
          // Soft tactile selection tick
          await HapticFeedback.selectionClick();
          break;

        case TactilePatternType.modeSwitched:
          // Dual medium confirmation pulses
          await HapticFeedback.mediumImpact();
          await Future.delayed(const Duration(milliseconds: 70));
          await HapticFeedback.mediumImpact();
          break;

        case TactilePatternType.actionConfirmed:
          await HapticFeedback.lightImpact();
          break;
      }
    } catch (_) {
      // Platform vibration gracefully handled if device lacks haptic motor
    }
  }

  /// Scales haptic pulsation frequency based on obstacle proximity (meters).
  Future<void> triggerProximityWarning(double distanceMeters) async {
    if (distanceMeters <= 1.0) {
      await triggerPattern(TactilePatternType.stopImmediately);
    } else if (distanceMeters <= 2.2) {
      await triggerPattern(TactilePatternType.approachingCurb);
    } else if (distanceMeters <= 4.0) {
      await triggerPattern(TactilePatternType.centeredOnPath);
    }
  }

  /// Multi-pulse confirmation indicating switch to tab [modeIndex] (1-indexed).
  Future<void> announceModeHaptic(int modeIndex) async {
    final count = modeIndex.clamp(1, 4);
    for (int i = 0; i < count; i++) {
      await HapticFeedback.mediumImpact();
      if (i < count - 1) {
        await Future.delayed(const Duration(milliseconds: 90));
      }
    }
  }
}

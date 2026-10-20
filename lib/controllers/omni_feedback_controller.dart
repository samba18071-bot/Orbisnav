import 'dart:async';
import 'package:flutter/services.dart';

/// Controller coordinating acoustic sonar pitch oscillator feedback,
/// rhythmic loading ticks, shutter effects, and rich tactile waveforms.
class OmniFeedbackController {
  static final OmniFeedbackController _instance =
      OmniFeedbackController._internal();
  factory OmniFeedbackController() => _instance;

  OmniFeedbackController._internal();

  // Cloud Waiting Sonar Tick Timer
  Timer? _cloudWaitingTimer;
  bool _isWaitingForCloud = false;
  bool get isWaitingForCloud => _isWaitingForCloud;

  // Barcode Centering Beep Debounce
  DateTime _lastBarcodeBeepTime = DateTime.fromMillisecondsSinceEpoch(0);

  // Pitch telemetry for UI or audio oscillator
  double _activePitchHz = 440.0;
  double get activePitchHz => _activePitchHz;

  double _ambientLuminance = 0.5;
  double get ambientLuminance => _ambientLuminance;

  bool _isPitchToneActive = false;
  bool get isPitchToneActive => _isPitchToneActive;

  // Callbacks for custom platform synthesizer or tests
  void Function(double pitchHz, double durationMs)? onPlaySynthesizedTone;
  void Function()? onShutterSound;

  /// Starts rhythmic sonar tick and gentle haptic pulse while waiting for Cloud AI.
  void startCloudWaitingCue() {
    if (_isWaitingForCloud) return;
    _isWaitingForCloud = true;

    _cloudWaitingTimer?.cancel();
    // Emit immediate first pulse
    _emitWaitingPulse();

    _cloudWaitingTimer =
        Timer.periodic(const Duration(milliseconds: 650), (timer) {
      if (!_isWaitingForCloud) {
        timer.cancel();
        return;
      }
      _emitWaitingPulse();
    });
  }

  void _emitWaitingPulse() {
    try {
      HapticFeedback.selectionClick();
      // Optional subtle synthesized tick
      onPlaySynthesizedTone?.call(880.0, 30.0);
    } catch (_) {}
  }

  /// Stops rhythmic cloud waiting cues.
  void stopCloudWaitingCue() {
    _isWaitingForCloud = false;
    _cloudWaitingTimer?.cancel();
    _cloudWaitingTimer = null;
  }

  /// Plays rapid sonar beeps that increase in pitch as the barcode centers in the frame.
  void playBarcodeCenteringTone({
    required double pitchHz,
    required double alignmentScore,
  }) {
    _activePitchHz = pitchHz;
    _isPitchToneActive = true;

    final now = DateTime.now();
    // Sonar repetition interval scales from 350ms (periphery) down to 75ms (bullseye dead center)
    final intervalMs = (75 + ((1.0 - alignmentScore.clamp(0.0, 1.0)) * 275)).toInt();

    if (now.difference(_lastBarcodeBeepTime).inMilliseconds >= intervalMs) {
      _lastBarcodeBeepTime = now;

      // Tactile tick when approaching dead center (> 70% aligned)
      if (alignmentScore > 0.70) {
        try {
          HapticFeedback.selectionClick();
        } catch (_) {}
      }

      onPlaySynthesizedTone?.call(pitchHz, 40.0);
    }
  }

  /// Updates pitch for continuous light sensing mode.
  void updateContinuousLightPitch(double pitchHz, double luminance) {
    _activePitchHz = pitchHz;
    _ambientLuminance = luminance;
    _isPitchToneActive = true;
    onPlaySynthesizedTone?.call(pitchHz, 50.0);
  }

  /// Halts active pitch tone.
  void stopPitchTone() {
    _isPitchToneActive = false;
  }

  /// Plays camera shutter sound effect and tactile pulse for 4-corner document lock.
  void playShutterClick() {
    try {
      SystemSound.play(SystemSoundType.click);
    } catch (_) {}
    onShutterSound?.call();
  }

  /// Tactile alert for barcode decode confirmation.
  Future<void> vibrateBarcodeFound() async {
    try {
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 40));
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// Tactile alert for 4-corner document lock and auto-capture.
  Future<void> vibrateDocumentCaptured() async {
    try {
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 60));
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Tactile feedback for instant short text reading.
  Future<void> vibrateTextRead() async {
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// Standard selection click for UI gestures (Single Tap).
  Future<void> vibrateSelectionClick() async {
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  void dispose() {
    stopCloudWaitingCue();
    stopPitchTone();
  }
}

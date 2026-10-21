import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../controllers/accessible_audio_tone_manager.dart';

/// Subsystem 6: Light Detector Engine.
///
/// Features:
/// - Real-time luminance extraction from raw camera frames.
/// - Frequency modulation: continuous audible tone (200Hz to 2400Hz; higher pitch = brighter light).
/// - Spoken verbal brightness percentage and qualitative room description.
/// - Low-light detection thresholding.
class LightDetectorEngine {
  final AccessibleAudioToneManager _audioManager;

  double _currentLuminance = 0.5;
  int _lastSpokenPercent = -1;
  DateTime _lastSpokenTime = DateTime.fromMillisecondsSinceEpoch(0);

  double get currentLuminance => _currentLuminance;
  int get lightLevelPercent => (_currentLuminance * 100).round().clamp(0, 100);

  LightDetectorEngine({
    AccessibleAudioToneManager? audioManager,
  }) : _audioManager = audioManager ?? AccessibleAudioToneManager();

  /// Ingests live frame luminance and updates continuous audio tone.
  void processFrame(Uint8List frameBytes, double luminance) {
    _currentLuminance = luminance.clamp(0.0, 1.0);
    // Update continuous audio pitch oscillator
    _audioManager.setLightDetectorFrequency(_currentLuminance);
  }

  /// Returns qualitative description of ambient light conditions.
  String get qualitativeDescription {
    final percent = lightLevelPercent;
    if (percent < 5) return "Pitch black. Very dark.";
    if (percent < 25) return "Dim, low light.";
    if (percent < 60) return "Moderate indoor lighting.";
    if (percent < 85) return "Brightly lit.";
    return "Very bright, direct light source.";
  }

  /// Announces current brightness percentage aloud via TTS.
  Future<void> announceLightLevel({bool forced = false}) async {
    final percent = lightLevelPercent;
    final now = DateTime.now();

    // Prevent repeated vocal announcements unless forced or significant change occurred
    if (!forced &&
        (percent - _lastSpokenPercent).abs() < 10 &&
        now.difference(_lastSpokenTime).inSeconds < 4) {
      return;
    }

    _lastSpokenPercent = percent;
    _lastSpokenTime = now;

    final speech = "Light level $percent percent. $qualitativeDescription";
    await _audioManager.speak(speech, interrupt: true, cacheForReplay: true);
  }

  /// Stops continuous audio tone oscillator.
  void stop() {
    _audioManager.stopLightDetectorTone();
  }

  /// Manually sets luminance (for tests or sensor injections).
  void setLuminanceForTesting(double luminance) {
    _currentLuminance = luminance.clamp(0.0, 1.0);
    _audioManager.setLightDetectorFrequency(_currentLuminance);
  }
}

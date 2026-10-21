import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

typedef SpeechResultCallback = void Function(String recognizedWords);
typedef SpeechErrorCallback = void Function(String error);

/// Production Accessible Audio, Earcon Tone, and Haptics Manager.
///
/// Implements WCAG AAA compliant eyes-free sonic feedback:
/// - Native Text-to-Speech (TTS) with instant interrupt.
/// - Speech-to-Text (STT) lifecycle and listening audio cues.
/// - Dynamic acoustic frequency oscillator (for light meter and barcode centering).
/// - Multi-tier haptic feedback patterns (flashlight toggle, cloud AI sonar ticks).
/// - Announcement caching for two-finger repeat gestures.
class AccessibleAudioToneManager extends ChangeNotifier {
  static final AccessibleAudioToneManager _instance =
      AccessibleAudioToneManager._internal();
  factory AccessibleAudioToneManager() => _instance;

  /// Headless testing flag
  static bool testMode = false;

  final FlutterTts _tts;

  // TTS State
  bool _isSpeaking = false;
  String? _currentUtterance;
  String _lastSpokenAnnouncement =
      "OrbisNav Visual Cortex ready. Double tap to toggle flashlight, or tap and speak your requirement.";
  double _speechRate = 1.0;

  bool get isSpeaking => _isSpeaking;
  String? get currentUtterance => _currentUtterance;
  String get lastSpokenAnnouncement => _lastSpokenAnnouncement;
  double get speechRate => _speechRate;

  // STT State
  bool _isListening = false;
  String _lastRecognizedText = "";
  bool get isListening => _isListening;
  String get lastRecognizedText => _lastRecognizedText;

  // External STT hook for platform plugin injection
  Future<void> Function(SpeechResultCallback onResult, SpeechErrorCallback onError)?
      onStartListeningHook;
  Future<void> Function()? onStopListeningHook;

  // Acoustic Frequency Oscillator State
  double _activeToneFrequency = 0.0;
  bool _isOscillatorActive = false;
  Timer? _barcodeBeepTimer;
  Timer? _cloudWaitingPulseTimer;

  double get activeToneFrequency => _activeToneFrequency;
  bool get isOscillatorActive => _isOscillatorActive;

  AccessibleAudioToneManager._internal({FlutterTts? tts})
      : _tts = tts ?? FlutterTts() {
    _initTts();
  }

  AccessibleAudioToneManager.withCustomTts({FlutterTts? tts})
      : _tts = tts ?? FlutterTts() {
    _initTts();
  }

  void _initTts() {
    if (testMode) return;
    try {
      _tts.setLanguage("en-US").catchError((_) => null);
      _tts.setSpeechRate(0.5).catchError((_) => null); // 1.0x standard rate
      _tts.setVolume(1.0).catchError((_) => null);
      _tts.setPitch(1.0).catchError((_) => null);

      _tts.setStartHandler(() {
        _isSpeaking = true;
        notifyListeners();
      });

      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        _currentUtterance = null;
        notifyListeners();
      });

      _tts.setCancelHandler(() {
        _isSpeaking = false;
        _currentUtterance = null;
        notifyListeners();
      });

      _tts.setErrorHandler((msg) {
        _isSpeaking = false;
        _currentUtterance = null;
        notifyListeners();
      });
    } catch (e) {
      debugPrint("TTS Init notice: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // 1. Text-to-Speech (TTS) Methods
  // ---------------------------------------------------------------------------

  /// Speaks the given text aloud. If [interrupt] is true, immediately stops any ongoing speech.
  Future<void> speak(
    String text, {
    bool interrupt = true,
    bool cacheForReplay = true,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    if (cacheForReplay) {
      _lastSpokenAnnouncement = cleanText;
    }

    if (interrupt && _isSpeaking) {
      await stopSpeech();
    }

    _currentUtterance = cleanText;
    _isSpeaking = true;
    notifyListeners();

    if (testMode) return;

    try {
      await _tts.speak(cleanText);
    } catch (e) {
      debugPrint("TTS speak failed: $e");
      _isSpeaking = false;
      notifyListeners();
    }
  }

  /// Instantly cuts off current speech.
  Future<void> stopSpeech() async {
    _isSpeaking = false;
    _currentUtterance = null;
    notifyListeners();

    if (testMode) return;

    try {
      await _tts.stop();
    } catch (e) {
      debugPrint("TTS stop error: $e");
    }
  }

  /// Repeats the last spoken announcement (WCAG AAA gesture).
  Future<void> repeatLastAnnouncement() async {
    await triggerSelectionHaptic();
    await speak(_lastSpokenAnnouncement, interrupt: true, cacheForReplay: false);
  }

  /// Cycles speech rate: 1.0x -> 1.5x -> 2.0x.
  Future<void> cycleSpeechRate() async {
    if (_speechRate == 1.0) {
      _speechRate = 1.5;
      if (!testMode) await _tts.setSpeechRate(0.65);
      await speak("Speech rate 1.5 times", interrupt: true);
    } else if (_speechRate == 1.5) {
      _speechRate = 2.0;
      if (!testMode) await _tts.setSpeechRate(0.85);
      await speak("Speech rate 2.0 times", interrupt: true);
    } else {
      _speechRate = 1.0;
      if (!testMode) await _tts.setSpeechRate(0.5);
      await speak("Speech rate normal", interrupt: true);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 2. Speech-to-Text (STT) Voice Requirement Input
  // ---------------------------------------------------------------------------

  /// Starts listening for the user's spoken requirement.
  Future<void> startListening({
    required SpeechResultCallback onResult,
    required SpeechErrorCallback onError,
  }) async {
    // 1. Immediately cut off any speaking TTS to avoid recording own voice
    await stopSpeech();

    // 2. Tactile and sonic listening chime
    await triggerListeningStartHaptic();
    _isListening = true;
    notifyListeners();

    if (onStartListeningHook != null) {
      await onStartListeningHook!(onResult, onError);
    } else {
      // In default headless/simulator mode without external STT bridge,
      // simulate listening state until external trigger or test input is provided.
      debugPrint("STT Listening active. Waiting for speech input...");
    }
  }

  /// Stops listening for voice input.
  Future<void> stopListening() async {
    _isListening = false;
    await triggerListeningStopHaptic();
    notifyListeners();

    if (onStopListeningHook != null) {
      await onStopListeningHook!();
    }
  }

  /// Injects recognized speech result (used by STT hooks, tests, and simulated voice prompts).
  void handleSpeechRecognized(String recognizedText) {
    _lastRecognizedText = recognizedText;
    _isListening = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 3. Audio Frequency Oscillator (Light Meter, Barcode Beeps, Sonar Ticks)
  // ---------------------------------------------------------------------------

  /// Sets continuous tone frequency (200Hz - 2400Hz) mapped from 0.0 - 1.0 luminance.
  void setLightDetectorFrequency(double luminance) {
    final clamped = luminance.clamp(0.0, 1.0);
    // Exponential pitch curve for clear human perception of light gradients
    _activeToneFrequency = 200.0 + (math.pow(clamped, 1.2) * 2200.0);
    _isOscillatorActive = true;
    notifyListeners();
  }

  /// Stops the light meter continuous tone.
  void stopLightDetectorTone() {
    _activeToneFrequency = 0.0;
    _isOscillatorActive = false;
    notifyListeners();
  }

  /// Starts pulsing beeps for barcode proximity.
  /// Distance from center (0.0 = centered, 1.0 = edge of screen).
  void updateBarcodeProximityBeep(double distanceNormalized) {
    _barcodeBeepTimer?.cancel();
    final intervalMs = (100 + (distanceNormalized * 600)).round().clamp(80, 800);

    _barcodeBeepTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      HapticFeedback.selectionClick();
      SystemSound.play(SystemSoundType.click);
    });
  }

  /// Stops barcode beeping.
  void stopBarcodeBeep() {
    _barcodeBeepTimer?.cancel();
    _barcodeBeepTimer = null;
  }

  /// Starts rhythmic haptic pulses and subtle audio sonar ticks while waiting for Cloud AI.
  void startCloudWaitingSonar() {
    _cloudWaitingPulseTimer?.cancel();
    _cloudWaitingPulseTimer =
        Timer.periodic(const Duration(milliseconds: 700), (_) {
      HapticFeedback.lightImpact();
      SystemSound.play(SystemSoundType.click);
    });
  }

  /// Stops cloud waiting sonar ticks.
  void stopCloudWaitingSonar() {
    _cloudWaitingPulseTimer?.cancel();
    _cloudWaitingPulseTimer = null;
  }

  // ---------------------------------------------------------------------------
  // 4. Haptic Feedback Engine (WCAG AAA Tactile Vocab)
  // ---------------------------------------------------------------------------

  /// Distinct double-click haptic confirmation for Flashlight toggle.
  Future<void> triggerFlashlightHaptic() async {
    if (testMode) return;
    try {
      await HapticFeedback.mediumImpact();
      await Future.delayed(const Duration(milliseconds: 70));
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Listening start earcon & haptic.
  Future<void> triggerListeningStartHaptic() async {
    try {
      await HapticFeedback.mediumImpact();
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }

  /// Listening stop confirmation.
  Future<void> triggerListeningStopHaptic() async {
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }

  /// Subtle touch feedback.
  Future<void> triggerSelectionHaptic() async {
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  @override
  void dispose() {
    _barcodeBeepTimer?.cancel();
    _cloudWaitingPulseTimer?.cancel();
    super.dispose();
  }
}

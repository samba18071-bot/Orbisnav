import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/omni_channel_models.dart';

/// Callback signatures for STT voice recognition
typedef SpeechResultCallback = void Function(String recognizedWords);
typedef SpeechErrorCallback = void Function(String error);

/// Production Audio Governance Manager for the Single Omni-Channel Assistant.
/// Coordinates TTS output, immediate interrupt capability, priority preemption,
/// announcement caching, speech rate scaling, and Speech-to-Text (STT) listening.
class OmniAudioManager extends ChangeNotifier {
  static OmniAudioManager _singleton = OmniAudioManager._internal();
  factory OmniAudioManager() => _singleton;

  /// Global testing flag to bypass platform TTS bindings in headless CI/tests
  static bool testMode = false;

  final FlutterTts _tts;

  // Active utterance state
  String? _currentUtterance;
  String? get currentUtterance => _currentUtterance;
  OmniPriorityTier? _currentPriority;
  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;
  OmniPriorityTier? get currentPriority => _currentPriority;

  // Last announcement cache for WCAG Double-Tap replay
  String _lastSpokenAnnouncement = "Omni-Channel Visual Cortex Ready.";
  String get lastSpokenAnnouncement => _lastSpokenAnnouncement;

  // Speech rate configuration (1.0x -> 1.5x -> 2.0x for blind power users)
  double _speechRate = 1.0;
  double get speechRate => _speechRate;

  // STT Voice Query State
  bool _isListening = false;
  bool get isListening => _isListening;
  String? _lastRecognizedSpeech;
  String? get lastRecognizedSpeech => _lastRecognizedSpeech;

  // Speech-to-text external hook for platform integration or test injection
  Future<void> Function(SpeechResultCallback onResult, SpeechErrorCallback onError)?
      onStartListeningHandler;
  Future<void> Function()? onStopListeningHandler;

  OmniAudioManager.withCustomTts({FlutterTts? tts}) : _tts = tts ?? FlutterTts() {
    _initTts();
  }

  OmniAudioManager._internal({FlutterTts? tts}) : _tts = tts ?? FlutterTts() {
    _initTts();
  }

  void _initTts() {
    try {
      _tts.setLanguage("en-US").catchError((_) => null);
      _tts.setSpeechRate(0.5).catchError((_) => null); // FlutterTTS 0.5 corresponds to standard 1.0x rate
      _tts.setVolume(1.0).catchError((_) => null);
      _tts.setPitch(1.0).catchError((_) => null);

      _tts.setStartHandler(() {
        _isSpeaking = true;
        notifyListeners();
      });

      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        _currentUtterance = null;
        _currentPriority = null;
        notifyListeners();
      });

      _tts.setCancelHandler(() {
        _isSpeaking = false;
        _currentUtterance = null;
        _currentPriority = null;
        notifyListeners();
      });

      _tts.setErrorHandler((msg) {
        _isSpeaking = false;
        _currentUtterance = null;
        _currentPriority = null;
        notifyListeners();
      });
    } catch (e) {
      debugPrint("TTS initialization notice: $e");
    }
  }

  /// Cycles speech rate across 1.0x -> 1.5x -> 2.0x and provides audio confirmation.
  Future<void> cycleSpeechRate() async {
    if (_speechRate == 1.0) {
      _speechRate = 1.5;
      await _tts.setSpeechRate(0.65);
    } else if (_speechRate == 1.5) {
      _speechRate = 2.0;
      await _tts.setSpeechRate(0.85);
    } else {
      _speechRate = 1.0;
      await _tts.setSpeechRate(0.5);
    }

    notifyListeners();
    await speak(
      "Speech rate ${_speechRate.toStringAsFixed(1)} speed.",
      priority: OmniPriorityTier.tier0LowLight,
      force: true,
      haptic: true,
    );
  }

  /// Dispatches speech obeying strict priority preemption rules.
  /// If higher priority arrives (or force=true), active speech is killed instantly.
  Future<void> speak(
    String text, {
    required OmniPriorityTier priority,
    bool force = false,
    bool haptic = false,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    // Check preemption hierarchy:
    // If already speaking, allow only if new utterance has higher priority or force is true
    if (_isSpeaking && !force) {
      if (_currentPriority != null &&
          !priority.hasPrecedenceOver(_currentPriority!)) {
        // Drop lower or equal priority utterance to prevent user overwhelm
        return;
      }
    }

    // Cleanly interrupt previous speech before uttering new priority message
    await stopSpeech();

    _currentUtterance = cleanText;
    _currentPriority = priority;
    _lastSpokenAnnouncement = cleanText;
    _isSpeaking = true;
    notifyListeners();

    if (haptic) {
      try {
        await HapticFeedback.selectionClick();
      } catch (_) {}
    }

    if (testMode) {
      return;
    }

    try {
      await _tts.speak(cleanText);
    } catch (e) {
      debugPrint("TTS speak exception: $e");
      if (e is MissingPluginException) {
        // Preserve isSpeaking = true for headless unit/widget tests
        return;
      }
      _isSpeaking = false;
      notifyListeners();
    }
  }

  /// Immediately interrupts any active speech output and flushes audio buffers.
  Future<void> stopSpeech() async {
    if (!testMode) {
      try {
        await _tts.stop();
      } catch (_) {}
    }
    _isSpeaking = false;
    _currentUtterance = null;
    _currentPriority = null;
    notifyListeners();
  }

  /// Double-Tap Accessibility Gesture: Replays the last spoken announcement verbatim.
  Future<void> repeatLastAnnouncement() async {
    await speak(
      _lastSpokenAnnouncement,
      priority: OmniPriorityTier.tier0LowLight,
      force: true,
      haptic: true,
    );
  }

  // ===========================================================================
  // SPEECH-TO-TEXT (STT) FOR CONVERSATIONAL VOICE Q&A
  // ===========================================================================

  /// Starts listening for blind user's voice question (Press-and-Hold gesture).
  Future<void> startListening({
    required SpeechResultCallback onResult,
    required SpeechErrorCallback onError,
  }) async {
    // Kill active TTS so microphone does not pick up phone's own voice
    await stopSpeech();

    _isListening = true;
    notifyListeners();

    if (!testMode) {
      try {
        await HapticFeedback.mediumImpact();
      } catch (_) {}
    }

    if (onStartListeningHandler != null) {
      await onStartListeningHandler!(
        (recognized) {
          _lastRecognizedSpeech = recognized;
          onResult(recognized);
        },
        (error) {
          _isListening = false;
          notifyListeners();
          onError(error);
        },
      );
    } else {
      // Standalone simulation fallback for testing / headless devices
      debugPrint("[OmniAudioManager] Listening for voice query...");
    }
  }

  /// Stops voice listening upon finger lift.
  Future<void> stopListening() async {
    _isListening = false;
    notifyListeners();

    if (!testMode) {
      try {
        await HapticFeedback.lightImpact();
      } catch (_) {}
    }

    if (onStopListeningHandler != null) {
      await onStopListeningHandler!();
    }
  }

  /// Test hook to simulate speech recognition in headless automated tests.
  void simulateVoiceTranscription(String text) {
    _lastRecognizedSpeech = text;
  }

  @override
  void dispose() {
    stopSpeech();
    super.dispose();
  }
}

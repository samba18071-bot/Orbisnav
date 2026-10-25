import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/hybrid_voice_search_models.dart';
import '../services/offline_spatial_speech_formatter.dart';

/// Pluggable audio backend interface for TTS output and testing.
abstract class SpokenTtsBackend {
  Future<void> speak(String text, {required double rate});
  Future<void> stop();
  void setCallbacks({
    VoidCallback? onStart,
    VoidCallback? onDone,
    ValueChanged<String>? onError,
  });
}

/// Production implementation of [SpokenTtsBackend] backed by FlutterTts.
class FlutterTtsBackend implements SpokenTtsBackend {
  final FlutterTts _tts;

  FlutterTtsBackend({FlutterTts? tts}) : _tts = tts ?? FlutterTts() {
    _init();
  }

  void _init() {
    try {
      _tts.setLanguage('en-US');
      _tts.setPitch(1.0);
      _tts.awaitSpeakCompletion(true);
    } catch (e) {
      debugPrint('[FlutterTtsBackend] Initialization error: $e');
    }
  }

  @override
  Future<void> speak(String text, {required double rate}) async {
    try {
      await _tts.setSpeechRate(rate);
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[FlutterTtsBackend] speak error: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('[FlutterTtsBackend] stop error: $e');
    }
  }

  @override
  void setCallbacks({
    VoidCallback? onStart,
    VoidCallback? onDone,
    ValueChanged<String>? onError,
  }) {
    try {
      _tts.setStartHandler(() {
        onStart?.call();
      });
      _tts.setCompletionHandler(() {
        onDone?.call();
      });
      _tts.setErrorHandler((msg) {
        onError?.call(msg.toString());
      });
    } catch (e) {
      debugPrint('[FlutterTtsBackend] setCallbacks error: $e');
    }
  }
}

/// In-memory mock backend for headless CI/unit tests.
class MockSpokenTtsBackend implements SpokenTtsBackend {
  final List<String> spokenHistory = [];
  final List<double> rateHistory = [];
  bool isSpeaking = false;
  int stopCalls = 0;

  VoidCallback? _onStart;
  VoidCallback? _onDone;

  @override
  Future<void> speak(String text, {required double rate}) async {
    isSpeaking = true;
    spokenHistory.add(text);
    rateHistory.add(rate);
    _onStart?.call();
    await Future.microtask(() {});
    isSpeaking = false;
    _onDone?.call();
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    isSpeaking = false;
    _onDone?.call();
  }

  @override
  void setCallbacks({
    VoidCallback? onStart,
    VoidCallback? onDone,
    ValueChanged<String>? onError,
  }) {
    _onStart = onStart;
    _onDone = onDone;
  }
}

/// Smart Voice Cadence & Anti-Spam TTS Manager.
///
/// Prevents TTS lag and utterance overlap using a 3-tier priority matrix:
/// - CRITICAL: Immediately flushes ongoing speech and speaks right away.
/// - NAVIGATION: Spoken every 2.0s OR immediately if clock-face sector changes >= 1 hour.
/// - CONTEXT: Spoken once when target is locked, or on explicit request.
///
/// Enforces dynamic speech rate in range 1.15x - 1.25x for responsive micro-prompts.
class SpokenGuidanceCadenceController extends ChangeNotifier {
  final SpokenTtsBackend _ttsBackend;

  double _speechRate = 1.20;
  double get speechRate => _speechRate;

  SpeechPriority? _currentPriority;
  SpeechPriority? get currentPriority => _currentPriority;

  SpeechPriority? _lastSpokenPriority;
  SpeechPriority? get lastSpokenPriority => _lastSpokenPriority;

  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  DateTime? _lastSpokenTime;
  DateTime? get lastSpokenTime => _lastSpokenTime;

  int? _lastSpokenClockHour;
  int? get lastSpokenClockHour => _lastSpokenClockHour;

  String? _lastSpokenText;
  String? get lastSpokenText => _lastSpokenText;

  String? _activeTargetId;
  String? get activeTargetId => _activeTargetId;

  bool _hasSpokenContextForActiveTarget = false;
  bool get hasSpokenContextForActiveTarget => _hasSpokenContextForActiveTarget;

  DateTime? _lastTargetLostAlertTime;

  SpokenGuidanceCadenceController({
    SpokenTtsBackend? ttsBackend,
    double initialSpeechRate = 1.20,
  }) : _ttsBackend = ttsBackend ?? FlutterTtsBackend() {
    _speechRate = initialSpeechRate.clamp(1.15, 1.25);
    _ttsBackend.setCallbacks(
      onStart: () {
        _isSpeaking = true;
        notifyListeners();
      },
      onDone: () {
        _isSpeaking = false;
        _currentPriority = null;
        notifyListeners();
      },
      onError: (err) {
        _isSpeaking = false;
        _currentPriority = null;
        notifyListeners();
      },
    );
  }

  /// Sets TTS speech rate, clamped to the high-efficiency blind user range (1.15x - 1.25x).
  void setSpeechRate(double rate) {
    _speechRate = rate.clamp(1.15, 1.25);
    notifyListeners();
  }

  /// CRITICAL INTERRUPT: Hard-flushes TTS and speaks immediately.
  /// Used for: Target within grabbing reach, sudden obstacle, or rapid camera shake.
  Future<void> speakCritical(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return;

    // Hard flush any in-progress or queued speech
    await _ttsBackend.stop();
    _currentPriority = SpeechPriority.critical;
    _lastSpokenPriority = SpeechPriority.critical;
    _lastSpokenText = clean;
    _lastSpokenTime = DateTime.now();

    notifyListeners();
    await _ttsBackend.speak(clean, rate: _speechRate);
  }

  /// NAVIGATION CADENCE: Directional micro-corrections and clock announcements.
  /// Governed by:
  /// 1. Minimum 2.0-second interval, OR
  /// 2. Immediate interrupt if the clock sector changes by >= 1 hour (e.g. 2 o'clock -> 12 o'clock), OR
  /// 3. Explicit force flag.
  Future<bool> speakNavigation({
    required String text,
    required int clockHour,
    bool force = false,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return false;

    // Critical speech takes absolute precedence
    if (_isSpeaking && _currentPriority == SpeechPriority.critical) {
      return false;
    }

    final now = DateTime.now();
    final bool sectorChanged =
        (_lastSpokenClockHour == null || _lastSpokenClockHour != clockHour);
    final bool cadenceElapsed = (_lastSpokenTime == null ||
        now.difference(_lastSpokenTime!).inMilliseconds >= 2000);

    final bool shouldSpeak = force || sectorChanged || cadenceElapsed;
    if (!shouldSpeak) {
      return false;
    }

    // Stop current lower priority or obsolete navigation speech
    await _ttsBackend.stop();

    _currentPriority = SpeechPriority.navigation;
    _lastSpokenPriority = SpeechPriority.navigation;
    _lastSpokenClockHour = clockHour;
    _lastSpokenText = clean;
    _lastSpokenTime = now;

    notifyListeners();
    await _ttsBackend.speak(clean, rate: _speechRate);
    return true;
  }

  /// CONTEXT SEMANTIC SPEECH: Cloud landmark details (e.g., "On the wooden table next to the laptop").
  /// Spoken once per target lock, or when explicitly requested via user double-tap.
  Future<bool> speakContext({
    required String targetId,
    required String text,
    bool force = false,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return false;

    // Do not preempt higher priorities
    if (_isSpeaking &&
        (_currentPriority == SpeechPriority.critical ||
            _currentPriority == SpeechPriority.navigation)) {
      return false;
    }

    if (!force) {
      if (_activeTargetId == targetId && _hasSpokenContextForActiveTarget) {
        return false;
      }
    }

    _activeTargetId = targetId;
    _hasSpokenContextForActiveTarget = true;
    _currentPriority = SpeechPriority.context;
    _lastSpokenPriority = SpeechPriority.context;
    _lastSpokenText = clean;
    _lastSpokenTime = DateTime.now();

    notifyListeners();
    await _ttsBackend.speak(clean, rate: _speechRate);
    return true;
  }

  /// Updates active locked target ID and resets single-announcement context state.
  void notifyActiveTargetChanged(String? newTargetId) {
    if (newTargetId != _activeTargetId) {
      _activeTargetId = newTargetId;
      _hasSpokenContextForActiveTarget = false;
      _lastSpokenClockHour = null;
      notifyListeners();
    }
  }

  /// TARGET LOST RECOVERY: Triggered when actively tracked target leaves the camera view.
  /// Uses Kalman velocity vector (vx, vy) to speak recovery guidance with zero latency.
  Future<void> notifyTargetLost({
    required String targetItem,
    required double vx,
    required double vy,
  }) async {
    final now = DateTime.now();
    // Throttle lost target alerts to once every 1500ms to avoid audio flutter
    if (_lastTargetLostAlertTime != null &&
        now.difference(_lastTargetLostAlertTime!).inMilliseconds < 1500) {
      return;
    }

    _lastTargetLostAlertTime = now;
    final recoverySpeech = OfflineSpatialSpeechFormatter.formatLostTargetRecovery(
      targetItem: targetItem,
      vx: vx,
      vy: vy,
    );

    await speakCritical(recoverySpeech);
  }

  /// Stops TTS engine and clears active state.
  Future<void> stop() async {
    await _ttsBackend.stop();
    _isSpeaking = false;
    _currentPriority = null;
    notifyListeners();
  }

  /// Resets all state for a new search session.
  Future<void> reset() async {
    await stop();
    _lastSpokenTime = null;
    _lastSpokenClockHour = null;
    _lastSpokenText = null;
    _activeTargetId = null;
    _hasSpokenContextForActiveTarget = false;
    _lastTargetLostAlertTime = null;
    notifyListeners();
  }
}

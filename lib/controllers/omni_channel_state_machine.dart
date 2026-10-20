import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import '../models/omni_channel_models.dart';
import 'omni_audio_manager.dart';
import 'omni_feedback_controller.dart';

/// Text deduplication sliding cache with Levenshtein similarity.
class TextDeduplicationMemory {
  final Duration ttl;
  final double similarityThreshold;
  final Map<String, DateTime> _seenTexts = {};

  TextDeduplicationMemory({
    this.ttl = const Duration(seconds: 7),
    this.similarityThreshold = 0.80,
  });

  /// Returns true if [text] has already been spoken recently within [ttl].
  bool isDuplicate(String text) {
    _purgeExpired();
    final normalized = _normalize(text);
    if (normalized.isEmpty) return true;

    for (final entry in _seenTexts.entries) {
      if (entry.key == normalized) return true;
      final similarity = _calculateSimilarity(entry.key, normalized);
      if (similarity >= similarityThreshold) {
        return true;
      }
    }
    return false;
  }

  /// Records that [text] was spoken.
  void record(String text) {
    _purgeExpired();
    final normalized = _normalize(text);
    if (normalized.isNotEmpty) {
      _seenTexts[normalized] = DateTime.now();
    }
  }

  void clear() => _seenTexts.clear();

  void _purgeExpired() {
    final now = DateTime.now();
    _seenTexts.removeWhere((_, time) => now.difference(time) > ttl);
  }

  String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim();

  double _calculateSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final longer = s1.length >= s2.length ? s1 : s2;
    final shorter = s1.length < s2.length ? s1 : s2;

    final distance = _levenshteinDistance(longer, shorter);
    return (longer.length - distance) / longer.length.toDouble();
  }

  int _levenshteinDistance(String a, String b) {
    List<int> v0 = List<int>.generate(b.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(b.length + 1, 0);

    for (int i = 0; i < a.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < b.length; j++) {
        final cost = a[i] == b[j] ? 0 : 1;
        v1[j + 1] = math.min(
          v1[j] + 1,
          math.min(v0[j + 1] + 1, v0[j] + cost),
        );
      }
      for (int j = 0; j < v0.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[b.length];
  }
}

/// Barcode deduplication sliding cache.
class BarcodeDeduplicationMemory {
  final Duration cooldown;
  final Map<String, DateTime> _seenBarcodes = {};

  BarcodeDeduplicationMemory({this.cooldown = const Duration(seconds: 5)});

  bool isDuplicate(String code) {
    final now = DateTime.now();
    final lastTime = _seenBarcodes[code];
    if (lastTime == null) return false;
    return now.difference(lastTime) < cooldown;
  }

  void record(String code) {
    _seenBarcodes[code] = DateTime.now();
  }

  void clear() => _seenBarcodes.clear();
}

/// OmniChannelStateMachine: Single Omni-Channel Core Router.
/// Automatically evaluates live frame telemetry, manages priority routing across
/// Low-Light (P0), Barcode (P1), Document (P2), Short Text (P3), and Conversational/Scene (P4).
class OmniChannelStateMachine extends ChangeNotifier {
  final OmniAudioManager _audioManager;
  final OmniFeedbackController _feedbackController;
  final TextDeduplicationMemory _textDeduplicator;
  final BarcodeDeduplicationMemory _barcodeDeduplicator;

  // External Hardware & Camera Hook Callbacks
  Future<void> Function(bool torchOn)? onTorchToggleRequested;
  Future<Uint8List?> Function()? onCaptureHighResPhoto;
  Future<void> Function(Uint8List photoBytes)? onDocumentCapturedForCloudReading;
  Future<void> Function(Uint8List? frameBytes, String? optionalPrompt)?
      onCloudSceneSummaryRequested;

  // Current State
  OmniChannelState _state = OmniChannelState.initial();
  OmniChannelState get state => _state;

  // Luminance Hysteresis & Debounce
  static const double kLowLightThreshold = 0.20;
  static const double kAdequateLightThreshold = 0.35;
  DateTime _lastTorchChangeTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastLowLightAnnounceTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isTorchOn = false;
  bool _isContinuousLightPitchEnabled = false;

  // Document 4-Corner Stability Tracking
  int _documentStableHoldDurationMs = 0;
  DateTime _lastDocumentGuidanceTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isDocumentCaptureTriggered = false;

  // Short Text Hold Tracking
  String? _candidateShortText;
  int _shortTextSteadyHoldDurationMs = 0;
  DateTime? _firstShortTextTime;

  // Concurrency & Processing flags
  bool _isDisposed = false;

  OmniChannelStateMachine({
    OmniAudioManager? audioManager,
    OmniFeedbackController? feedbackController,
    TextDeduplicationMemory? textDeduplicator,
    BarcodeDeduplicationMemory? barcodeDeduplicator,
  })  : _audioManager = audioManager ?? OmniAudioManager(),
        _feedbackController =
            feedbackController ?? OmniFeedbackController(),
        _textDeduplicator =
            textDeduplicator ?? TextDeduplicationMemory(),
        _barcodeDeduplicator =
            barcodeDeduplicator ?? BarcodeDeduplicationMemory() {
    _audioManager.addListener(_onAudioStateChanged);
  }

  void _onAudioStateChanged() {
    if (_isDisposed) return;
    if (_state.isSpeaking != _audioManager.isSpeaking) {
      _state = _state.copyWith(isSpeaking: _audioManager.isSpeaking);
      notifyListeners();
    }
  }

  /// Toggles continuous audio-pitch light-sensing mode on or off.
  void toggleContinuousLightPitch() {
    _isContinuousLightPitchEnabled = !_isContinuousLightPitchEnabled;
    _state = _state.copyWith(
      isContinuousLightPitchEnabled: _isContinuousLightPitchEnabled,
    );
    notifyListeners();

    if (_isContinuousLightPitchEnabled) {
      _audioManager.speak(
        "Light sensing tone enabled. Sweep camera to hear light levels.",
        priority: OmniPriorityTier.tier0LowLight,
        haptic: true,
      );
    } else {
      _feedbackController.stopPitchTone();
      _audioManager.speak(
        "Light sensing tone disabled.",
        priority: OmniPriorityTier.tier0LowLight,
        haptic: true,
      );
    }
  }

  /// The primary frame ingestion entrypoint.
  /// Consumes live telemetry bundle from local on-device ML (ML Kit / Vision / TFLite)
  /// and dynamically routes feedback adhering strictly to Section 2 Priority State Machine.
  void processFrame(FramePerceptionBundle bundle) {
    if (_isDisposed) return;

    final now = DateTime.now();

    // =========================================================================
    // PRIORITY 0: LOW-LIGHT / OBSCURED CHECK (CONTINUOUS)
    // =========================================================================
    _handleLowLightContinuous(bundle.luminance, now);

    // If waiting for cloud reasoning, preserve loading sonar ticks and skip lower tiers
    if (_state.isWaitingForCloud) {
      return;
    }

    // =========================================================================
    // PRIORITY 1: BARCODE PROXIMITY
    // =========================================================================
    if (bundle.barcode != null && bundle.barcode!.rawValue.isNotEmpty) {
      _handleBarcodeProximity(bundle.barcode!, now);
      return;
    }

    // =========================================================================
    // PRIORITY 2: DOCUMENT AUTO-CAPTURE (4-CORNER STABILITY)
    // =========================================================================
    if (bundle.document != null && bundle.document!.areAll4CornersVisible) {
      _handleDocumentFraming(bundle.document!, bundle.frameBytes, now);
      return;
    } else {
      // Reset document stability if document lost or corners broken
      _documentStableHoldDurationMs = 0;
      _isDocumentCaptureTriggered = false;
    }

    // =========================================================================
    // PRIORITY 3: INSTANT SHORT TEXT (< 15 WORDS)
    // =========================================================================
    if (bundle.shortText != null &&
        bundle.shortText!.rawText.trim().isNotEmpty &&
        bundle.shortText!.wordCount > 0 &&
        bundle.shortText!.wordCount <= 15 &&
        bundle.shortText!.isCentered) {
      _handleShortTextReading(bundle.shortText!, now);
      return;
    } else {
      // Reset short text hold duration when text leaves center
      _shortTextSteadyHoldDurationMs = 0;
      _candidateShortText = null;
      _firstShortTextTime = null;
    }

    // =========================================================================
    // PRIORITY 4: PASSIVE MONITORING (PEOPLE & SCENE READY)
    // =========================================================================
    _handlePassiveMonitoring(bundle);
  }

  // ---------------------------------------------------------------------------
  // Priority 0: Low-Light Implementation
  // ---------------------------------------------------------------------------
  void _handleLowLightContinuous(LuminanceDetection luminance, DateTime now) {
    final lum = luminance.luminance;

    // Optional continuous audio-pitch light sensing
    if (_isContinuousLightPitchEnabled) {
      // Frequency maps from 250 Hz (pitch dark) to 2200 Hz (blinding bright)
      final pitch = 250.0 + (lum * 1950.0);
      _feedbackController.updateContinuousLightPitch(pitch, lum);
      _state = _state.copyWith(
        currentPitchHz: pitch,
        currentLuminance: lum,
      );
    }

    // Low-light auto-torch hysteresis:
    // Only turn on if lum < 0.20 and torch currently OFF and at least 1.5s since last change
    if (lum < kLowLightThreshold && !_isTorchOn) {
      if (now.difference(_lastTorchChangeTime).inMilliseconds > 1500) {
        _isTorchOn = true;
        _lastTorchChangeTime = now;
        onTorchToggleRequested?.call(true);

        if (now.difference(_lastLowLightAnnounceTime).inMilliseconds > 10000) {
          _lastLowLightAnnounceTime = now;
          _audioManager.speak(
            "Low light, turning on flashlight.",
            priority: OmniPriorityTier.tier0LowLight,
            haptic: true,
          );
        }

        _state = _state.copyWith(
          isTorchActive: true,
          mode: OmniChannelMode.lowLightTriggered,
          statusMessage: "Low light. Flashlight active.",
        );
        notifyListeners();
      }
    } else if (lum > kAdequateLightThreshold && _isTorchOn) {
      // Automatically extinguish torch once bright ambient light is restored
      if (now.difference(_lastTorchChangeTime).inMilliseconds > 3000) {
        _isTorchOn = false;
        _lastTorchChangeTime = now;
        onTorchToggleRequested?.call(false);
        _state = _state.copyWith(isTorchActive: false);
        notifyListeners();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Priority 1: Barcode Proximity Implementation
  // ---------------------------------------------------------------------------
  void _handleBarcodeProximity(BarcodeDetection barcode, DateTime now) {
    // 1. Emit rapid acoustic sonar centering beeps
    _feedbackController.playBarcodeCenteringTone(
      pitchHz: barcode.pitchHz,
      alignmentScore: barcode.alignmentScore,
    );

    // 2. Check if decoded and ready for announcement
    if (barcode.isDecoded && barcode.rawValue.isNotEmpty) {
      final code = barcode.rawValue;

      if (!_barcodeDeduplicator.isDuplicate(code)) {
        _barcodeDeduplicator.record(code);

        // Vibrate to signal successful physical lock
        _feedbackController.vibrateBarcodeFound();

        final speechText = barcode.summarySpeech ??
            (barcode.productName != null
                ? "Barcode decoded: ${barcode.productName}"
                : "Barcode $code detected.");

        _audioManager.speak(
          speechText,
          priority: OmniPriorityTier.tier1BarcodeProximity,
          haptic: true,
        );

        _state = _state.copyWith(
          mode: OmniChannelMode.barcodeDecoded,
          activeTier: OmniPriorityTier.tier1BarcodeProximity,
          activeBarcode: code,
          activeProductName: barcode.productName,
          statusMessage: "Barcode found: $speechText",
          lastSpokenAnnouncement: speechText,
        );
        notifyListeners();
        return;
      }
    }

    _state = _state.copyWith(
      mode: OmniChannelMode.barcodeProximityActive,
      activeTier: OmniPriorityTier.tier1BarcodeProximity,
      statusMessage: "Centering barcode (Score: ${(barcode.alignmentScore * 100).toInt()}%)",
      currentPitchHz: barcode.pitchHz,
    );
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Priority 2: Document Auto-Capture (4-Corner Stability) Implementation
  // ---------------------------------------------------------------------------
  void _handleDocumentFraming(
    DocumentFramingDetection doc,
    Uint8List? frameBytes,
    DateTime now,
  ) {
    if (_isDocumentCaptureTriggered) return;

    // Check if hold is steady
    if (doc.isHoldSteady && doc.areAll4CornersVisible) {
      _documentStableHoldDurationMs += 200; // Simulated frame cadence slice

      if (_documentStableHoldDurationMs >= 1000) {
        // All 4 corners stable for 1.0 second -> AUTO-CAPTURE TRIGGER!
        _isDocumentCaptureTriggered = true;
        _documentStableHoldDurationMs = 0;

        _feedbackController.playShutterClick();
        _feedbackController.vibrateDocumentCaptured();

        _audioManager.speak(
          "Document captured. Reading with cloud AI.",
          priority: OmniPriorityTier.tier2DocumentCapture,
          haptic: true,
        );

        _state = _state.copyWith(
          mode: OmniChannelMode.documentCapturing,
          activeTier: OmniPriorityTier.tier2DocumentCapture,
          activeDocument: doc,
          isWaitingForCloud: true,
          statusMessage: "Document captured. Analyzing structure...",
        );
        notifyListeners();

        // Start waiting loading cues (rhythmic sonar tick + subtle pulse)
        _feedbackController.startCloudWaitingCue();

        // Delegate to high-res photo capture and cloud pipeline
        _triggerDocumentCloudProcessing(frameBytes);
        return;
      }
    } else {
      _documentStableHoldDurationMs = 0;
    }

    // Verbal edge guidance with cooldown (every 1800ms max to prevent audio stutter)
    if (doc.verbalGuidance.isNotEmpty &&
        now.difference(_lastDocumentGuidanceTime).inMilliseconds >= 1800) {
      _lastDocumentGuidanceTime = now;
      _audioManager.speak(
        doc.verbalGuidance,
        priority: OmniPriorityTier.tier2DocumentCapture,
        haptic: false,
      );
    }

    _state = _state.copyWith(
      mode: OmniChannelMode.documentFramingActive,
      activeTier: OmniPriorityTier.tier2DocumentCapture,
      activeDocument: doc,
      statusMessage: doc.verbalGuidance.isNotEmpty
          ? doc.verbalGuidance
          : "Aligning document (${(_documentStableHoldDurationMs / 10).toInt()}%)",
    );
    notifyListeners();
  }

  Future<void> _triggerDocumentCloudProcessing(Uint8List? fallbackBytes) async {
    try {
      Uint8List? capturedBytes = await onCaptureHighResPhoto?.call();
      capturedBytes ??= fallbackBytes;

      if (capturedBytes != null && onDocumentCapturedForCloudReading != null) {
        await onDocumentCapturedForCloudReading!(capturedBytes);
      }
    } catch (e) {
      debugPrint("Error capturing document for cloud reading: $e");
    } finally {
      _feedbackController.stopCloudWaitingCue();
      _isDocumentCaptureTriggered = false;
      _state = _state.copyWith(isWaitingForCloud: false);
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Priority 3: Instant Short Text (<15 words) Implementation
  // ---------------------------------------------------------------------------
  void _handleShortTextReading(ShortTextDetection textItem, DateTime now) {
    final text = textItem.rawText.trim();
    final isSteady = textItem.steadyHoldDurationMs >= 500;

    if (_candidateShortText == text) {
      final elapsed = _firstShortTextTime != null
          ? now.difference(_firstShortTextTime!).inMilliseconds
          : 0;
      _shortTextSteadyHoldDurationMs = elapsed;
    } else {
      _candidateShortText = text;
      _firstShortTextTime = now;
      _shortTextSteadyHoldDurationMs = 0;
    }

    // Must be held steady in center for at least 500ms
    if (isSteady || _shortTextSteadyHoldDurationMs >= 500) {
      if (!_textDeduplicator.isDuplicate(text)) {
        _textDeduplicator.record(text);
        _feedbackController.vibrateTextRead();

        _audioManager.speak(
          text,
          priority: OmniPriorityTier.tier3InstantShortText,
          haptic: true,
        );

        _state = _state.copyWith(
          mode: OmniChannelMode.shortTextReading,
          activeTier: OmniPriorityTier.tier3InstantShortText,
          activeShortText: text,
          statusMessage: "Read: $text",
          lastSpokenAnnouncement: text,
        );
        notifyListeners();
        return;
      }
    }

    _state = _state.copyWith(
      mode: OmniChannelMode.shortTextDetected,
      activeTier: OmniPriorityTier.tier3InstantShortText,
      activeShortText: text,
      statusMessage: "Reading steady text...",
    );
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Priority 4: Passive Monitoring (Scene & People)
  // ---------------------------------------------------------------------------
  void _handlePassiveMonitoring(FramePerceptionBundle bundle) {
    if (_state.mode == OmniChannelMode.lowLightTriggered) {
      return;
    }
    if (_state.mode != OmniChannelMode.monitoring) {
      _state = _state.copyWith(
        mode: OmniChannelMode.monitoring,
        activeTier: OmniPriorityTier.tier4SceneAndVoiceQA,
        statusMessage: bundle.people.isNotEmpty
            ? "${bundle.people.length} person(s) in view"
            : "Scanning surroundings...",
      );
      notifyListeners();
    }
  }

  // ===========================================================================
  // ON-DEMAND ACCESSIBILITY TRIGGERS (GESTURE INTEGRATION)
  // ===========================================================================

  /// Triggered on Single Tap when TTS is not speaking.
  /// Captures current frame and asks Cloud Multimodal AI for an instant spatial summary.
  Future<void> triggerOnDemandSpatialSummary(Uint8List? frameBytes) async {
    _audioManager.stopSpeech();
    _feedbackController.vibrateSelectionClick();

    _audioManager.speak(
      "Analyzing view...",
      priority: OmniPriorityTier.tier4SceneAndVoiceQA,
      haptic: true,
    );

    _state = _state.copyWith(
      mode: OmniChannelMode.cloudProcessing,
      isWaitingForCloud: true,
      statusMessage: "Querying Cloud Visual Cortex...",
    );
    notifyListeners();

    _feedbackController.startCloudWaitingCue();

    try {
      Uint8List? imageBytes = await onCaptureHighResPhoto?.call();
      imageBytes ??= frameBytes;

      if (onCloudSceneSummaryRequested != null) {
        await onCloudSceneSummaryRequested!(imageBytes, null);
      }
    } catch (e) {
      _audioManager.speak(
        "Network connection error. Please try again.",
        priority: OmniPriorityTier.tier4SceneAndVoiceQA,
        haptic: true,
      );
    } finally {
      _feedbackController.stopCloudWaitingCue();
      _state = _state.copyWith(isWaitingForCloud: false);
      notifyListeners();
    }
  }

  /// Triggered on Press-and-Hold Voice Question.
  Future<void> submitVoiceQuery({
    required String question,
    Uint8List? frameBytes,
  }) async {
    if (question.trim().isEmpty) return;

    _audioManager.stopSpeech();
    _feedbackController.vibrateSelectionClick();

    _state = _state.copyWith(
      mode: OmniChannelMode.cloudProcessing,
      isWaitingForCloud: true,
      activeVoiceQuery: question,
      statusMessage: 'Answering: "$question"',
    );
    notifyListeners();

    _feedbackController.startCloudWaitingCue();

    try {
      Uint8List? imageBytes = await onCaptureHighResPhoto?.call();
      imageBytes ??= frameBytes;

      if (onCloudSceneSummaryRequested != null) {
        await onCloudSceneSummaryRequested!(imageBytes, question);
      }
    } catch (e) {
      _audioManager.speak(
        "Unable to reach visual cortex. Check your internet connection.",
        priority: OmniPriorityTier.tier4SceneAndVoiceQA,
        haptic: true,
      );
    } finally {
      _feedbackController.stopCloudWaitingCue();
      _state = _state.copyWith(
        isWaitingForCloud: false,
        activeVoiceQuery: null,
      );
      notifyListeners();
    }
  }

  /// Updates state after a cloud multimodal response is spoken.
  void recordCloudAnnouncement(String text) {
    _state = _state.copyWith(
      lastSpokenAnnouncement: text,
      statusMessage: text,
      mode: OmniChannelMode.announcing,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _audioManager.removeListener(_onAudioStateChanged);
    _feedbackController.stopPitchTone();
    _feedbackController.stopCloudWaitingCue();
    super.dispose();
  }
}

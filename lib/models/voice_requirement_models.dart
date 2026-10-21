
/// The 6 core functional subsystems activated exclusively via the Voice Requirement Router.
enum VoiceSubsystem {
  /// 1. Short Text Engine: Zero-latency on-device OCR for reading signs, labels, and text.
  shortText,

  /// 2. Document Engine: 4-corner edge guidance, verbal framing, and high-res structured reading.
  document,

  /// 3. Scene & QA Engine: Deep spatial perception, room layout, and cloud multimodal Q&A.
  sceneQa,

  /// 4. Barcode Engine: Rapid acoustic pitch guidance and product catalog identification.
  barcode,

  /// 5. Currency & Person Engine: Banknote identification and person distance/clock-face locator.
  currencyPerson,

  /// 6. Light Detector Engine: Continuous pitch oscillator mapping ambient luminance to frequency.
  lightDetector,

  /// Idle / Standby: No active vision subsystem running (conserves CPU/battery).
  none,
}

/// Extension providing human-readable titles, vocal prompts, and accessibility labels.
extension VoiceSubsystemExtension on VoiceSubsystem {
  String get displayName {
    switch (this) {
      case VoiceSubsystem.shortText:
        return "Short Text Reader";
      case VoiceSubsystem.document:
        return "Document Scanner";
      case VoiceSubsystem.sceneQa:
        return "Scene & Visual Q&A";
      case VoiceSubsystem.barcode:
        return "Barcode Scanner";
      case VoiceSubsystem.currencyPerson:
        return "Currency & Person Locator";
      case VoiceSubsystem.lightDetector:
        return "Light Level Detector";
      case VoiceSubsystem.none:
        return "Standby";
    }
  }

  String get spokenConfirmation {
    switch (this) {
      case VoiceSubsystem.shortText:
        return "Short text reader active. Point camera at text.";
      case VoiceSubsystem.document:
        return "Document scanner active. Hold camera over document.";
      case VoiceSubsystem.sceneQa:
        return "Scene description active. Analyzing view.";
      case VoiceSubsystem.barcode:
        return "Barcode scanner active. Listening for beeps.";
      case VoiceSubsystem.currencyPerson:
        return "Currency and person locator active.";
      case VoiceSubsystem.lightDetector:
        return "Light detector active. Pitch indicates brightness.";
      case VoiceSubsystem.none:
        return "Standing by. Tap and hold to speak a requirement.";
    }
  }
}

/// Result of evaluating a user's spoken requirement through the Voice Intent Router.
class VoiceIntentResult {
  final VoiceSubsystem subsystem;
  final double confidence;
  final String rawQuery;
  final String cleanQuery;
  final String intentType;
  final String matchedPattern;
  final Map<String, dynamic> parameters;
  final bool isCloudFallbackRequired;
  final int latencyMs;

  const VoiceIntentResult({
    required this.subsystem,
    required this.confidence,
    required this.rawQuery,
    required this.cleanQuery,
    required this.intentType,
    required this.matchedPattern,
    this.parameters = const {},
    this.isCloudFallbackRequired = false,
    required this.latencyMs,
  });

  factory VoiceIntentResult.fallback(String query, {int latencyMs = 0}) {
    return VoiceIntentResult(
      subsystem: VoiceSubsystem.sceneQa,
      confidence: 0.85,
      rawQuery: query,
      cleanQuery: query.trim(),
      intentType: "USER_QUESTION",
      matchedPattern: "FALLBACK_SCENE_QA",
      parameters: {"query": query.trim()},
      isCloudFallbackRequired: true,
      latencyMs: latencyMs,
    );
  }

  @override
  String toString() {
    return 'VoiceIntentResult(subsystem: $subsystem, confidence: ${confidence.toStringAsFixed(2)}, latency: ${latencyMs}ms, intent: $intentType)';
  }
}

/// Complete reactive state of the Voice Requirement Router and Camera Screen.
class VoiceRouterState {
  final VoiceSubsystem activeSubsystem;
  final bool isListening;
  final bool isProcessingIntent;
  final bool isSpeaking;
  final bool isWaitingForCloud;
  final bool torchActive;
  final double luminance;
  final bool isLowLight;
  final String lastRecognizedVoice;
  final String lastSpokenAnnouncement;
  final String statusDescription;
  final Map<String, dynamic> telemetry;

  const VoiceRouterState({
    required this.activeSubsystem,
    required this.isListening,
    required this.isProcessingIntent,
    required this.isSpeaking,
    required this.isWaitingForCloud,
    required this.torchActive,
    required this.luminance,
    required this.isLowLight,
    required this.lastRecognizedVoice,
    required this.lastSpokenAnnouncement,
    required this.statusDescription,
    this.telemetry = const {},
  });

  factory VoiceRouterState.initial() => const VoiceRouterState(
        activeSubsystem: VoiceSubsystem.none,
        isListening: false,
        isProcessingIntent: false,
        isSpeaking: false,
        isWaitingForCloud: false,
        torchActive: false,
        luminance: 0.5,
        isLowLight: false,
        lastRecognizedVoice: "",
        lastSpokenAnnouncement: "OrbisNav Visual Cortex ready. Double-tap for flashlight, or tap and speak your requirement.",
        statusDescription: "Ready. Zero-Visual Touch Active.",
        telemetry: {},
      );

  VoiceRouterState copyWith({
    VoiceSubsystem? activeSubsystem,
    bool? isListening,
    bool? isProcessingIntent,
    bool? isSpeaking,
    bool? isWaitingForCloud,
    bool? torchActive,
    double? luminance,
    bool? isLowLight,
    String? lastRecognizedVoice,
    String? lastSpokenAnnouncement,
    String? statusDescription,
    Map<String, dynamic>? telemetry,
  }) {
    return VoiceRouterState(
      activeSubsystem: activeSubsystem ?? this.activeSubsystem,
      isListening: isListening ?? this.isListening,
      isProcessingIntent: isProcessingIntent ?? this.isProcessingIntent,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      isWaitingForCloud: isWaitingForCloud ?? this.isWaitingForCloud,
      torchActive: torchActive ?? this.torchActive,
      luminance: luminance ?? this.luminance,
      isLowLight: isLowLight ?? this.isLowLight,
      lastRecognizedVoice: lastRecognizedVoice ?? this.lastRecognizedVoice,
      lastSpokenAnnouncement:
          lastSpokenAnnouncement ?? this.lastSpokenAnnouncement,
      statusDescription: statusDescription ?? this.statusDescription,
      telemetry: telemetry ?? this.telemetry,
    );
  }
}

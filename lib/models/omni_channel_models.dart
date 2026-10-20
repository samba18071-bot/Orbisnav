import 'dart:math' as math;
import 'dart:typed_data';

/// The 5-Tier Priority Hierarchy for the Omni-Channel Visual Assistant.
/// Defines preemption order so that high-urgency physical cues override conversational or ambient cues.
enum OmniPriorityTier {
  /// Priority 0 / Continuous: Luminance dropped, lens obscured, auto-torch.
  tier0LowLight(0),

  /// Priority 1: Barcode entered viewfinder; acoustic centering pitch and decode.
  tier1BarcodeProximity(1),

  /// Priority 2: Document edges / dense text detected; verbal 4-corner guidance & auto-shutter.
  tier2DocumentCapture(2),

  /// Priority 3: Short text (<15 words, signs/labels) held steady in center for 0.5s.
  tier3InstantShortText(3),

  /// Priority 4 / On-Demand: Scene perception, people count/faces, currency & voice Q&A.
  tier4SceneAndVoiceQA(4);

  final int value;
  const OmniPriorityTier(this.value);

  bool hasPrecedenceOver(OmniPriorityTier other) => value < other.value;
}

/// Operational status of the unified visual cortex state machine.
enum OmniChannelMode {
  idle,
  monitoring,
  lowLightTriggered,
  barcodeProximityActive,
  barcodeDecoded,
  documentFramingActive,
  documentCapturing,
  shortTextDetected,
  shortTextReading,
  cloudProcessing,
  voiceListening,
  announcing,
}

/// Ambient illumination detection data.
class LuminanceDetection {
  final double luminance; // 0.0 (pitch black) to 1.0 (pure white)
  final bool isLowLight;
  final bool isLensObscured;
  final bool torchActive;
  final DateTime timestamp;

  const LuminanceDetection({
    required this.luminance,
    required this.isLowLight,
    this.isLensObscured = false,
    this.torchActive = false,
    required this.timestamp,
  });

  factory LuminanceDetection.initial() => LuminanceDetection(
        luminance: 0.5,
        isLowLight: false,
        isLensObscured: false,
        torchActive: false,
        timestamp: DateTime.now(),
      );

  LuminanceDetection copyWith({
    double? luminance,
    bool? isLowLight,
    bool? isLensObscured,
    bool? torchActive,
    DateTime? timestamp,
  }) {
    return LuminanceDetection(
      luminance: luminance ?? this.luminance,
      isLowLight: isLowLight ?? this.isLowLight,
      isLensObscured: isLensObscured ?? this.isLensObscured,
      torchActive: torchActive ?? this.torchActive,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// Barcode proximity and centering spatial geometry.
class BarcodeDetection {
  final String rawValue;
  final double xMin;
  final double yMin;
  final double xMax;
  final double yMax;
  final double centerX;
  final double centerY;
  final double alignmentScore; // 0.0 (edge) to 1.0 (dead center crosshair)
  final double pitchHz; // Frequency for acoustic sonar centering
  final bool isDecoded;
  final String? productName;
  final String? brand;
  final String? summarySpeech;
  final DateTime timestamp;

  const BarcodeDetection({
    required this.rawValue,
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
    required this.centerX,
    required this.centerY,
    required this.alignmentScore,
    required this.pitchHz,
    required this.isDecoded,
    this.productName,
    this.brand,
    this.summarySpeech,
    required this.timestamp,
  });

  factory BarcodeDetection.fromCoordinates({
    required String rawValue,
    required double xMin,
    required double yMin,
    required double xMax,
    required double yMax,
    bool isDecoded = false,
    String? productName,
    String? brand,
    String? summarySpeech,
  }) {
    final cx = ((xMin + xMax) / 2.0).clamp(0.0, 1.0);
    final cy = ((yMin + yMax) / 2.0).clamp(0.0, 1.0);
    final distFromCenter = math.sqrt(math.pow(cx - 0.5, 2) + math.pow(cy - 0.5, 2));
    final score = (1.0 - (distFromCenter * 2.0)).clamp(0.0, 1.0);

    // Audio pitch scales from 450 Hz (periphery) to 1950 Hz (bullseye center)
    final pitch = 450.0 + (score * 1500.0);

    return BarcodeDetection(
      rawValue: rawValue,
      xMin: xMin,
      yMin: yMin,
      xMax: xMax,
      yMax: yMax,
      centerX: cx,
      centerY: cy,
      alignmentScore: score,
      pitchHz: pitch,
      isDecoded: isDecoded,
      productName: productName,
      brand: brand,
      summarySpeech: summarySpeech,
      timestamp: DateTime.now(),
    );
  }
}

/// 4-Corner document geometry and alignment status.
class DocumentFramingDetection {
  final double topLeftX;
  final double topLeftY;
  final double topRightX;
  final double topRightY;
  final double bottomLeftX;
  final double bottomLeftY;
  final double bottomRightX;
  final double bottomRightY;
  final double coverageRatio; // Fraction of screen area covered by document (0.0 to 1.0)
  final bool areAll4CornersVisible;
  final bool isHoldSteady;
  final int stableHoldDurationMs;
  final String verbalGuidance;
  final DateTime timestamp;

  const DocumentFramingDetection({
    required this.topLeftX,
    required this.topLeftY,
    required this.topRightX,
    required this.topRightY,
    required this.bottomLeftX,
    required this.bottomLeftY,
    required this.bottomRightX,
    required this.bottomRightY,
    required this.coverageRatio,
    required this.areAll4CornersVisible,
    required this.isHoldSteady,
    required this.stableHoldDurationMs,
    required this.verbalGuidance,
    required this.timestamp,
  });

  factory DocumentFramingDetection.unframed() => DocumentFramingDetection(
        topLeftX: 0,
        topLeftY: 0,
        topRightX: 0,
        topRightY: 0,
        bottomLeftX: 0,
        bottomLeftY: 0,
        bottomRightX: 0,
        bottomRightY: 0,
        coverageRatio: 0,
        areAll4CornersVisible: false,
        isHoldSteady: false,
        stableHoldDurationMs: 0,
        verbalGuidance: "",
        timestamp: DateTime.now(),
      );

  double get centerX => (topLeftX + topRightX + bottomLeftX + bottomRightX) / 4.0;
  double get centerY => (topLeftY + topRightY + bottomLeftY + bottomRightY) / 4.0;
}

/// Instant short text block (<15 words) held steady in viewfinder.
class ShortTextDetection {
  final String rawText;
  final int wordCount;
  final double xMin;
  final double yMin;
  final double xMax;
  final double yMax;
  final bool isCentered;
  final int steadyHoldDurationMs;
  final DateTime timestamp;

  const ShortTextDetection({
    required this.rawText,
    required this.wordCount,
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
    required this.isCentered,
    required this.steadyHoldDurationMs,
    required this.timestamp,
  });

  bool get isEligibleForInstantReading =>
      rawText.trim().isNotEmpty &&
      wordCount > 0 &&
      wordCount <= 15 &&
      isCentered &&
      steadyHoldDurationMs >= 500;
}

/// Person and face telemetry data.
class PersonFaceDetection {
  final int personCount;
  final double distanceMeters;
  final String clockPosition;
  final String facialExpression;
  final bool isLookingAtCamera;

  const PersonFaceDetection({
    required this.personCount,
    required this.distanceMeters,
    required this.clockPosition,
    this.facialExpression = "neutral",
    this.isLookingAtCamera = true,
  });
}

/// Complete Tier 1 live frame analysis package delivered to the State Machine.
class FramePerceptionBundle {
  final Uint8List? frameBytes;
  final int frameWidth;
  final int frameHeight;
  final LuminanceDetection luminance;
  final BarcodeDetection? barcode;
  final DocumentFramingDetection? document;
  final ShortTextDetection? shortText;
  final List<PersonFaceDetection> people;
  final DateTime timestamp;

  FramePerceptionBundle({
    this.frameBytes,
    this.frameWidth = 640,
    this.frameHeight = 480,
    required this.luminance,
    this.barcode,
    this.document,
    this.shortText,
    this.people = const [],
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Snapshot of the complete Omni-Channel system state.
class OmniChannelState {
  final OmniChannelMode mode;
  final OmniPriorityTier activeTier;
  final String statusMessage;
  final String lastSpokenAnnouncement;
  final bool isSpeaking;
  final bool isTorchActive;
  final bool isContinuousLightPitchEnabled;
  final double currentPitchHz;
  final double currentLuminance;
  final String? activeBarcode;
  final String? activeProductName;
  final String? activeShortText;
  final DocumentFramingDetection? activeDocument;
  final bool isWaitingForCloud;
  final String? activeVoiceQuery;
  final DateTime updatedAt;

  const OmniChannelState({
    required this.mode,
    required this.activeTier,
    required this.statusMessage,
    required this.lastSpokenAnnouncement,
    required this.isSpeaking,
    required this.isTorchActive,
    required this.isContinuousLightPitchEnabled,
    required this.currentPitchHz,
    required this.currentLuminance,
    this.activeBarcode,
    this.activeProductName,
    this.activeShortText,
    this.activeDocument,
    required this.isWaitingForCloud,
    this.activeVoiceQuery,
    required this.updatedAt,
  });

  factory OmniChannelState.initial() => OmniChannelState(
        mode: OmniChannelMode.monitoring,
        activeTier: OmniPriorityTier.tier4SceneAndVoiceQA,
        statusMessage: "Omni-Channel Assistant Active. Ready.",
        lastSpokenAnnouncement: "Omni-Channel Visual Cortex Ready.",
        isSpeaking: false,
        isTorchActive: false,
        isContinuousLightPitchEnabled: false,
        currentPitchHz: 440.0,
        currentLuminance: 0.5,
        isWaitingForCloud: false,
        updatedAt: DateTime.now(),
      );

  OmniChannelState copyWith({
    OmniChannelMode? mode,
    OmniPriorityTier? activeTier,
    String? statusMessage,
    String? lastSpokenAnnouncement,
    bool? isSpeaking,
    bool? isTorchActive,
    bool? isContinuousLightPitchEnabled,
    double? currentPitchHz,
    double? currentLuminance,
    String? activeBarcode,
    String? activeProductName,
    String? activeShortText,
    DocumentFramingDetection? activeDocument,
    bool? isWaitingForCloud,
    String? activeVoiceQuery,
    DateTime? updatedAt,
  }) {
    return OmniChannelState(
      mode: mode ?? this.mode,
      activeTier: activeTier ?? this.activeTier,
      statusMessage: statusMessage ?? this.statusMessage,
      lastSpokenAnnouncement:
          lastSpokenAnnouncement ?? this.lastSpokenAnnouncement,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      isTorchActive: isTorchActive ?? this.isTorchActive,
      isContinuousLightPitchEnabled:
          isContinuousLightPitchEnabled ?? this.isContinuousLightPitchEnabled,
      currentPitchHz: currentPitchHz ?? this.currentPitchHz,
      currentLuminance: currentLuminance ?? this.currentLuminance,
      activeBarcode: activeBarcode ?? this.activeBarcode,
      activeProductName: activeProductName ?? this.activeProductName,
      activeShortText: activeShortText ?? this.activeShortText,
      activeDocument: activeDocument ?? this.activeDocument,
      isWaitingForCloud: isWaitingForCloud ?? this.isWaitingForCloud,
      activeVoiceQuery: activeVoiceQuery ?? this.activeVoiceQuery,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

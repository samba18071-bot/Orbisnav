import 'dart:math' as math;

/// Priority tier for the Spoken Guidance Cadence Controller
enum SpeechPriority {
  /// Stop/Safety prompts, target centered and grab-ready, or severe pan velocity warnings
  critical(0),

  /// Directional nudges, clock-face orientation, and distance updates (2.0s or >= 1hr delta)
  navigation(1),

  /// Cloud landmark semantic context (spoken once per target lock, or on double-tap)
  context(2);

  final int level;
  const SpeechPriority(this.level);
}

/// Normalized bounding box representation [ymin, xmin, ymax, xmax] in [0.0, 1.0].
class NormalizedBoundingBox {
  final double ymin;
  final double xmin;
  final double ymax;
  final double xmax;

  const NormalizedBoundingBox({
    required this.ymin,
    required this.xmin,
    required this.ymax,
    required this.xmax,
  });

  factory NormalizedBoundingBox.fromMilliCoords(List<dynamic> coords) {
    if (coords.length < 4) {
      return const NormalizedBoundingBox(ymin: 0, xmin: 0, ymax: 0, xmax: 0);
    }
    final y1 = ((coords[0] as num).toDouble() / 1000.0).clamp(0.0, 1.0);
    final x1 = ((coords[1] as num).toDouble() / 1000.0).clamp(0.0, 1.0);
    final y2 = ((coords[2] as num).toDouble() / 1000.0).clamp(0.0, 1.0);
    final x2 = ((coords[3] as num).toDouble() / 1000.0).clamp(0.0, 1.0);

    return NormalizedBoundingBox(
      ymin: math.min(y1, y2),
      xmin: math.min(x1, x2),
      ymax: math.max(y1, y2),
      xmax: math.max(x1, x2),
    );
  }

  double get width => (xmax - xmin).clamp(0.0, 1.0);
  double get height => (ymax - ymin).clamp(0.0, 1.0);
  double get area => width * height;

  double get cx => (xmin + xmax) / 2.0;
  double get cy => (ymin + ymax) / 2.0;

  double get distanceFromCenter {
    final dx = cx - 0.5;
    final dy = cy - 0.5;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Calculates Intersection over Union (IoU) with another bounding box.
  double computeIoU(NormalizedBoundingBox other) {
    final interLeft = math.max(xmin, other.xmin);
    final interTop = math.max(ymin, other.ymin);
    final interRight = math.min(xmax, other.xmax);
    final interBottom = math.min(ymax, other.ymax);

    if (interRight <= interLeft || interBottom <= interTop) {
      return 0.0;
    }

    final interArea = (interRight - interLeft) * (interBottom - interTop);
    final unionArea = area + other.area - interArea;
    if (unionArea <= 0.0) return 0.0;
    return interArea / unionArea;
  }

  List<int> toMilliCoords() {
    return [
      (ymin * 1000).round().clamp(0, 1000),
      (xmin * 1000).round().clamp(0, 1000),
      (ymax * 1000).round().clamp(0, 1000),
      (xmax * 1000).round().clamp(0, 1000),
    ];
  }

  NormalizedBoundingBox copyWith({
    double? ymin,
    double? xmin,
    double? ymax,
    double? xmax,
  }) {
    return NormalizedBoundingBox(
      ymin: ymin ?? this.ymin,
      xmin: xmin ?? this.xmin,
      ymax: ymax ?? this.ymax,
      xmax: xmax ?? this.xmax,
    );
  }

  @override
  String toString() =>
      'BBox(ymin: ${ymin.toStringAsFixed(2)}, xmin: ${xmin.toStringAsFixed(2)}, ymax: ${ymax.toStringAsFixed(2)}, xmax: ${xmax.toStringAsFixed(2)})';
}

/// Represents a persistent tracked instance of an object in camera view.
class TrackedItemInstance {
  final String trackId;
  final String targetLabel;
  final NormalizedBoundingBox bbox;
  final double confidence;
  final String clockDirection;
  final String estimatedDistance;

  // Local Offline Attributes (Extracted in <100ms on NPU/CPU)
  final String? offlineColor;
  final String? offlineOcrText;

  // Asynchronous Cloud Semantic Attributes (Enriched in ~600ms via Multimodal API)
  final String? cloudDistinctLabel;
  final String? cloudLandmarkPosition;
  final String? cloudSpokenLocationSentence;
  final bool isCloudEnriched;

  final int lastSeenTimestampMs;
  final int missedFramesCount;

  const TrackedItemInstance({
    required this.trackId,
    required this.targetLabel,
    required this.bbox,
    required this.confidence,
    required this.clockDirection,
    required this.estimatedDistance,
    this.offlineColor,
    this.offlineOcrText,
    this.cloudDistinctLabel,
    this.cloudLandmarkPosition,
    this.cloudSpokenLocationSentence,
    this.isCloudEnriched = false,
    required this.lastSeenTimestampMs,
    this.missedFramesCount = 0,
  });

  /// Alias for backward compatibility
  String? get cloudLandmarkContext => cloudLandmarkPosition;

  /// The highest-fidelity distinctive label available.
  String get distinctiveLabel {
    if (cloudDistinctLabel != null && cloudDistinctLabel!.isNotEmpty) {
      return cloudDistinctLabel!;
    }
    final buffer = StringBuffer();
    if (offlineColor != null && offlineColor!.isNotEmpty) {
      buffer.write('$offlineColor ');
    }
    buffer.write(targetLabel);
    if (offlineOcrText != null && offlineOcrText!.isNotEmpty) {
      buffer.write(' marked $offlineOcrText');
    }
    return buffer.toString().trim();
  }

  TrackedItemInstance copyWith({
    String? trackId,
    String? targetLabel,
    NormalizedBoundingBox? bbox,
    double? confidence,
    String? clockDirection,
    String? estimatedDistance,
    String? offlineColor,
    String? offlineOcrText,
    String? cloudDistinctLabel,
    String? cloudLandmarkPosition,
    String? cloudSpokenLocationSentence,
    bool? isCloudEnriched,
    int? lastSeenTimestampMs,
    int? missedFramesCount,
  }) {
    return TrackedItemInstance(
      trackId: trackId ?? this.trackId,
      targetLabel: targetLabel ?? this.targetLabel,
      bbox: bbox ?? this.bbox,
      confidence: confidence ?? this.confidence,
      clockDirection: clockDirection ?? this.clockDirection,
      estimatedDistance: estimatedDistance ?? this.estimatedDistance,
      offlineColor: offlineColor ?? this.offlineColor,
      offlineOcrText: offlineOcrText ?? this.offlineOcrText,
      cloudDistinctLabel: cloudDistinctLabel ?? this.cloudDistinctLabel,
      cloudLandmarkPosition: cloudLandmarkPosition ?? this.cloudLandmarkPosition,
      cloudSpokenLocationSentence: cloudSpokenLocationSentence ?? this.cloudSpokenLocationSentence,
      isCloudEnriched: isCloudEnriched ?? this.isCloudEnriched,
      lastSeenTimestampMs: lastSeenTimestampMs ?? this.lastSeenTimestampMs,
      missedFramesCount: missedFramesCount ?? this.missedFramesCount,
    );
  }
}

/// Network health and latency status for Cloud vs Edge gating.
class NetworkHealthStatus {
  final bool isOnline;
  final int latencyMs;
  final bool isCloudAvailable;
  final DateTime lastChecked;

  const NetworkHealthStatus({
    required this.isOnline,
    required this.latencyMs,
    required this.isCloudAvailable,
    required this.lastChecked,
  });

  factory NetworkHealthStatus.offline() {
    return NetworkHealthStatus(
      isOnline: false,
      latencyMs: 9999,
      isCloudAvailable: false,
      lastChecked: DateTime.now(),
    );
  }

  factory NetworkHealthStatus.online({required int latencyMs}) {
    return NetworkHealthStatus(
      isOnline: true,
      latencyMs: latencyMs,
      isCloudAvailable: latencyMs <= 1200,
      lastChecked: DateTime.now(),
    );
  }
}

/// Instance parsed from Cloud Grounder JSON response.
class CloudGroundingInstance {
  final String? trackId;
  final NormalizedBoundingBox bbox;
  final String clockDirection;
  final String estimatedDistance;
  final String distinctLabel;
  final String landmarkPosition;
  final String spokenLocationSentence;

  const CloudGroundingInstance({
    this.trackId,
    required this.bbox,
    required this.clockDirection,
    required this.estimatedDistance,
    required this.distinctLabel,
    required this.landmarkPosition,
    this.spokenLocationSentence = '',
  });

  /// Alias for backward compatibility
  String get landmarkContext => landmarkPosition;

  factory CloudGroundingInstance.fromJson(Map<String, dynamic> json) {
    final rawBbox = json['bbox'] as List<dynamic>? ?? [0, 0, 0, 0];
    final landmark = json['landmark_position']?.toString() ??
        json['landmark_context']?.toString() ??
        '';
    final spokenSentence = json['spoken_location_sentence']?.toString() ?? '';

    return CloudGroundingInstance(
      trackId: json['track_id']?.toString(),
      bbox: NormalizedBoundingBox.fromMilliCoords(rawBbox),
      clockDirection: json['clock_direction']?.toString() ?? "12 o'clock",
      estimatedDistance: json['estimated_distance']?.toString() ?? 'ahead',
      distinctLabel: json['distinct_label']?.toString() ?? '',
      landmarkPosition: landmark,
      spokenLocationSentence: spokenSentence,
    );
  }
}

/// Complete Grounding and Disambiguation result from Cloud Multimodal API.
class CloudGroundingResult {
  final bool found;
  final List<CloudGroundingInstance> instances;
  final String multiItemSummarySpeech;

  const CloudGroundingResult({
    required this.found,
    required this.instances,
    required this.multiItemSummarySpeech,
  });

  /// Alias for backward compatibility
  String get summaryGuidance => multiItemSummarySpeech;

  factory CloudGroundingResult.empty({String guidance = ''}) {
    return CloudGroundingResult(
      found: false,
      instances: const [],
      multiItemSummarySpeech: guidance,
    );
  }

  factory CloudGroundingResult.fromJson(Map<String, dynamic> json) {
    final instancesJson = json['instances'] as List<dynamic>? ?? [];
    final summary = json['multi_item_summary_speech']?.toString() ??
        json['summary_guidance']?.toString() ??
        '';

    return CloudGroundingResult(
      found: json['found'] == true,
      instances: instancesJson
          .map((i) => CloudGroundingInstance.fromJson(i as Map<String, dynamic>))
          .toList(),
      multiItemSummarySpeech: summary,
    );
  }
}

/// State bundle emitted by the disambiguator to the audio/haptic layer.
class DisambiguationBundle {
  final String targetItem;
  final String? activeTargetId;
  final List<TrackedItemInstance> instances;
  final String spokenOfflineAnnouncement;
  final String? spokenEnrichedAnnouncement;
  final bool isMultiObject;

  const DisambiguationBundle({
    required this.targetItem,
    this.activeTargetId,
    required this.instances,
    required this.spokenOfflineAnnouncement,
    this.spokenEnrichedAnnouncement,
    required this.isMultiObject,
  });

  TrackedItemInstance? get activeInstance {
    if (activeTargetId == null) return null;
    return instances.firstWhere(
      (i) => i.trackId == activeTargetId,
      orElse: () => instances.first,
    );
  }
}

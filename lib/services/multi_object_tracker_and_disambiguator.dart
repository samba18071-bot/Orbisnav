import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../models/hybrid_voice_search_models.dart';
import 'offline_spatial_speech_formatter.dart';

/// Lightweight 2D Kalman Filter for persistent bounding box state estimation.
/// State vector: [cx, cy, width, height, vx, vy, vwidth, vheight]
class KalmanBoxTracker {
  double cx;
  double cy;
  double w;
  double h;

  double vx = 0.0;
  double vy = 0.0;
  double vw = 0.0;
  double vh = 0.0;

  KalmanBoxTracker(NormalizedBoundingBox box)
      : cx = box.cx,
        cy = box.cy,
        w = box.width,
        h = box.height;

  /// Predicts next bounding box using velocity state
  NormalizedBoundingBox predict() {
    cx += vx;
    cy += vy;
    w = (w + vw).clamp(0.01, 1.0);
    h = (h + vh).clamp(0.01, 1.0);

    return _toBox();
  }

  /// Updates state with a matched detection using steady-state Kalman gain
  void update(NormalizedBoundingBox measurement) {
    const double kGainPos = 0.65;
    const double kGainVel = 0.35;

    final double measuredCx = measurement.cx;
    final double measuredCy = measurement.cy;
    final double measuredW = measurement.width;
    final double measuredH = measurement.height;

    final double errCx = measuredCx - cx;
    final double errCy = measuredCy - cy;
    final double errW = measuredW - w;
    final double errH = measuredH - h;

    cx += kGainPos * errCx;
    cy += kGainPos * errCy;
    w += kGainPos * errW;
    h += kGainPos * errH;

    vx += kGainVel * errCx;
    vy += kGainVel * errCy;
    vw += kGainVel * errW;
    vh += kGainVel * errH;
  }

  NormalizedBoundingBox _toBox() {
    final xmin = (cx - (w / 2.0)).clamp(0.0, 1.0);
    final ymin = (cy - (h / 2.0)).clamp(0.0, 1.0);
    final xmax = (cx + (w / 2.0)).clamp(0.0, 1.0);
    final ymax = (cy + (h / 2.0)).clamp(0.0, 1.0);
    return NormalizedBoundingBox(ymin: ymin, xmin: xmin, ymax: ymax, xmax: xmax);
  }
}

/// Internal state for a single track managed by ByteTrack/Kalman
class _ActiveTrack {
  final String trackId;
  final String targetLabel;
  final KalmanBoxTracker kalman;
  NormalizedBoundingBox bbox;
  double confidence;
  int missedFrames;
  int lastSeenMs;

  String? offlineColor;
  String? offlineOcrText;
  String? cloudDistinctLabel;
  String? cloudLandmarkPosition;
  String? cloudSpokenLocationSentence;
  bool isCloudEnriched;

  _ActiveTrack({
    required this.trackId,
    required this.targetLabel,
    required this.bbox,
    required this.confidence,
    required this.lastSeenMs,
    this.offlineColor,
    this.cloudDistinctLabel,
    this.cloudLandmarkPosition,
    this.cloudSpokenLocationSentence,
    this.isCloudEnriched = false,
  })  : missedFrames = 0,
        kalman = KalmanBoxTracker(bbox);

  TrackedItemInstance toInstance() {
    return TrackedItemInstance(
      trackId: trackId,
      targetLabel: targetLabel,
      bbox: bbox,
      confidence: confidence,
      clockDirection: OfflineSpatialSpeechFormatter.formatClockDirection(bbox.cx),
      estimatedDistance: OfflineSpatialSpeechFormatter.formatDistanceAndReach(
        bbox.area,
        bbox.cx >= 0.45 && bbox.cx <= 0.55,
      ),
      offlineColor: offlineColor,
      offlineOcrText: offlineOcrText,
      cloudDistinctLabel: cloudDistinctLabel,
      cloudLandmarkPosition: cloudLandmarkPosition,
      cloudSpokenLocationSentence: cloudSpokenLocationSentence,
      isCloudEnriched: isCloudEnriched,
      lastSeenTimestampMs: lastSeenMs,
      missedFramesCount: missedFrames,
    );
  }
}

/// Raw detection input from on-device YOLO / MobileNet
class RawDetection {
  final String label;
  final NormalizedBoundingBox bbox;
  final double confidence;

  const RawDetection({
    required this.label,
    required this.bbox,
    required this.confidence,
  });
}

/// ByteTrack / Kalman MOT Engine with Local Crop Disambiguation and Target Cycling.
class MultiObjectTrackerAndDisambiguator {
  int _nextIdCounter = 1;
  final Map<String, _ActiveTrack> _tracks = {};
  String? _activeTargetId;

  // Velocity of the active track at the moment it was lost from view
  double _lastActiveLostVx = 0.0;
  double _lastActiveLostVy = 0.0;
  bool _hasActiveTargetJustBeenLost = false;

  String? get activeTargetId => _activeTargetId;
  bool get hasActiveTargetJustBeenLost => _hasActiveTargetJustBeenLost;
  double get lastActiveLostVx => _lastActiveLostVx;
  double get lastActiveLostVy => _lastActiveLostVy;

  List<TrackedItemInstance> get currentTrackedInstances =>
      _tracks.values.where((t) => t.missedFrames == 0).map((t) => t.toInstance()).toList();

  /// Resets tracker state between new item searches.
  void reset() {
    _tracks.clear();
    _activeTargetId = null;
    _nextIdCounter = 1;
    _hasActiveTargetJustBeenLost = false;
    _lastActiveLostVx = 0.0;
    _lastActiveLostVy = 0.0;
  }

  /// Clears the target-lost flag after it has been consumed by the cadence controller.
  void consumeActiveTargetLostEvent() {
    _hasActiveTargetJustBeenLost = false;
  }

  /// Updates all active tracks with new frame detections at 30 FPS.
  DisambiguationBundle updateFrame({
    required String targetItem,
    required List<RawDetection> detections,
    Uint8List? rawFrameBytes,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _hasActiveTargetJustBeenLost = false;

    // Record previous active track before updating
    final previousActiveTrack = (_activeTargetId != null) ? _tracks[_activeTargetId] : null;
    final int previousMissedFrames = previousActiveTrack?.missedFrames ?? 0;

    // 1. Filter detections to target query (case-insensitive substring match)
    final query = targetItem.trim().toLowerCase();
    final matchingDetections = detections.where((d) {
      final l = d.label.toLowerCase();
      return l.contains(query) || query.contains(l);
    }).toList();

    // 2. Kalman prediction step for existing tracks
    for (final track in _tracks.values) {
      track.bbox = track.kalman.predict();
      track.missedFrames++;
    }

    // 3. IoU Association (ByteTrack style)
    final List<bool> matchedDetections = List.filled(matchingDetections.length, false);

    // Prioritize existing tracks with highest IoU
    for (final track in _tracks.values) {
      double bestIoU = 0.15; // Association threshold allowing fast pan
      int bestIdx = -1;

      for (int i = 0; i < matchingDetections.length; i++) {
        if (matchedDetections[i]) continue;
        final iou = track.bbox.computeIoU(matchingDetections[i].bbox);
        if (iou > bestIoU) {
          bestIoU = iou;
          bestIdx = i;
        }
      }

      if (bestIdx != -1) {
        matchedDetections[bestIdx] = true;
        track.kalman.update(matchingDetections[bestIdx].bbox);
        track.bbox = matchingDetections[bestIdx].bbox;
        track.confidence = matchingDetections[bestIdx].confidence;
        track.missedFrames = 0;
        track.lastSeenMs = now;

        // Perform fast offline crop color disambiguation if not yet extracted
        if (track.offlineColor == null && rawFrameBytes != null) {
          track.offlineColor = extractDominantColorFromCrop(rawFrameBytes, track.bbox);
        }
      }
    }

    // 4. Create new tracks for unassociated detections
    for (int i = 0; i < matchingDetections.length; i++) {
      if (!matchedDetections[i]) {
        final newId = "ID_$_nextIdCounter";
        _nextIdCounter++;

        String? color;
        if (rawFrameBytes != null) {
          color = extractDominantColorFromCrop(rawFrameBytes, matchingDetections[i].bbox);
        }

        _tracks[newId] = _ActiveTrack(
          trackId: newId,
          targetLabel: matchingDetections[i].label,
          bbox: matchingDetections[i].bbox,
          confidence: matchingDetections[i].confidence,
          lastSeenMs: now,
          offlineColor: color,
        );
      }
    }

    // Check if the previously stable active track just became lost from camera view
    if (previousActiveTrack != null && previousMissedFrames == 0 && previousActiveTrack.missedFrames > 0) {
      _lastActiveLostVx = previousActiveTrack.kalman.vx;
      _lastActiveLostVy = previousActiveTrack.kalman.vy;
      _hasActiveTargetJustBeenLost = true;
    }

    // 5. Purge expired tracks (missed for > 15 consecutive frames)
    _tracks.removeWhere((id, track) => track.missedFrames > 15);

    // 6. Spatial Sorting (Clock direction left-to-right, then distance to center)
    // Only includes actively visible detections in current frame
    final sortedInstances = _tracks.values
        .where((t) => t.missedFrames == 0)
        .map((t) => t.toInstance())
        .toList();

    sortedInstances.sort((a, b) {
      // Primary sort: horizontal clock direction (cx)
      final xComp = a.bbox.cx.compareTo(b.bbox.cx);
      if ((a.bbox.cx - b.bbox.cx).abs() > 0.15) {
        return xComp;
      }
      // Secondary sort: closest to center
      return a.bbox.distanceFromCenter.compareTo(b.bbox.distanceFromCenter);
    });

    // 7. Auto-lock center-most target if none selected or previous lost
    if (sortedInstances.isNotEmpty) {
      final activeExists = sortedInstances.any((i) => i.trackId == _activeTargetId);
      if (!activeExists) {
        // Find instance closest to center (0.5, 0.5)
        sortedInstances.sort((a, b) =>
            a.bbox.distanceFromCenter.compareTo(b.bbox.distanceFromCenter));
        _activeTargetId = sortedInstances.first.trackId;

        // Re-sort spatially left-to-right for consistent user navigation
        sortedInstances.sort((a, b) => a.bbox.cx.compareTo(b.bbox.cx));
      }
    } else {
      _activeTargetId = null;
    }

    // 8. Generate immediate offline and enriched announcement strings
    final offlineSpeech = OfflineSpatialSpeechFormatter.formatMultiItemDisambiguation(
      targetItem: targetItem,
      instances: sortedInstances,
      activeTargetId: _activeTargetId,
    );
    final enrichedSpeech = _buildEnrichedDisambiguation(sortedInstances);

    return DisambiguationBundle(
      targetItem: targetItem,
      activeTargetId: _activeTargetId,
      instances: sortedInstances,
      spokenOfflineAnnouncement: offlineSpeech,
      spokenEnrichedAnnouncement: enrichedSpeech,
      isMultiObject: sortedInstances.length > 1,
    );
  }

  /// Seeds a new bounding box returned by the Cloud Vision Grounder into the local 30 FPS MOT.
  void seedBoundingBox({
    required NormalizedBoundingBox bbox,
    required String targetLabel,
    String? distinctLabel,
    String? landmarkContext,
    String? spokenLocationSentence,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final newId = "ID_$_nextIdCounter";
    _nextIdCounter++;

    final newTrack = _ActiveTrack(
      trackId: newId,
      targetLabel: targetLabel,
      bbox: bbox,
      confidence: 0.99,
      lastSeenMs: now,
      cloudDistinctLabel: distinctLabel,
      cloudLandmarkPosition: landmarkContext,
      cloudSpokenLocationSentence: spokenLocationSentence,
      isCloudEnriched: true,
    );

    _tracks[newId] = newTrack;
    _activeTargetId = newId;
  }

  /// Merges asynchronous cloud landmark enrichment into locally tracked instances.
  void mergeCloudEnrichment(List<CloudGroundingInstance> cloudInstances) {
    for (final cloud in cloudInstances) {
      if (cloud.trackId != null && _tracks.containsKey(cloud.trackId)) {
        final track = _tracks[cloud.trackId]!;
        track.cloudDistinctLabel = cloud.distinctLabel;
        track.cloudLandmarkPosition = cloud.landmarkPosition;
        track.cloudSpokenLocationSentence = cloud.spokenLocationSentence;
        track.isCloudEnriched = true;
        continue;
      }

      // Match by spatial IoU
      for (final track in _tracks.values) {
        if (track.bbox.computeIoU(cloud.bbox) > 0.30) {
          track.cloudDistinctLabel = cloud.distinctLabel;
          track.cloudLandmarkPosition = cloud.landmarkPosition;
          track.cloudSpokenLocationSentence = cloud.spokenLocationSentence;
          track.isCloudEnriched = true;
          break;
        }
      }
    }
  }

  /// Cycles to next tracked object in the sorted list (Swipe Right or 'Next').
  TrackedItemInstance? cycleNext() {
    final instances = currentTrackedInstances;
    if (instances.isEmpty) return null;
    instances.sort((a, b) => a.bbox.cx.compareTo(b.bbox.cx));

    int currentIndex = instances.indexWhere((i) => i.trackId == _activeTargetId);
    if (currentIndex == -1 || currentIndex >= instances.length - 1) {
      _activeTargetId = instances.first.trackId;
    } else {
      _activeTargetId = instances[currentIndex + 1].trackId;
    }
    return instances.firstWhere((i) => i.trackId == _activeTargetId);
  }

  /// Cycles to previous tracked object in the sorted list (Swipe Left or 'Previous').
  TrackedItemInstance? cyclePrevious() {
    final instances = currentTrackedInstances;
    if (instances.isEmpty) return null;
    instances.sort((a, b) => a.bbox.cx.compareTo(b.bbox.cx));

    int currentIndex = instances.indexWhere((i) => i.trackId == _activeTargetId);
    if (currentIndex <= 0) {
      _activeTargetId = instances.last.trackId;
    } else {
      _activeTargetId = instances[currentIndex - 1].trackId;
    }
    return instances.firstWhere((i) => i.trackId == _activeTargetId);
  }

  /// Matches spoken voice query against offline attributes and cloud descriptions.
  TrackedItemInstance? filterByVoiceAttribute(String voiceQuery) {
    final query = voiceQuery.trim().toLowerCase();
    if (query.isEmpty) return null;

    final instances = currentTrackedInstances;
    TrackedItemInstance? bestMatch;
    int highestScore = 0;

    for (final inst in instances) {
      int score = 0;

      // Check cloud description
      final desc = (inst.cloudDistinctLabel ?? '').toLowerCase();
      if (desc.isNotEmpty && query.contains(desc)) score += 5;
      for (final word in query.split(' ')) {
        if (word.length > 2 && desc.contains(word)) score += 2;
      }

      // Check offline color
      final color = (inst.offlineColor ?? '').toLowerCase();
      if (color.isNotEmpty && query.contains(color)) score += 4;

      // Check spatial clock direction
      final clock = inst.clockDirection.toLowerCase();
      if (query.contains(clock) ||
          (query.contains('left') && inst.bbox.cx < 0.4) ||
          (query.contains('right') && inst.bbox.cx > 0.6) ||
          (query.contains('middle') && inst.bbox.cx >= 0.4 && inst.bbox.cx <= 0.6)) {
        score += 3;
      }

      if (score > highestScore) {
        highestScore = score;
        bestMatch = inst;
      }
    }

    if (bestMatch != null && highestScore >= 2) {
      _activeTargetId = bestMatch.trackId;
      return bestMatch;
    }
    return null;
  }

  String? _buildEnrichedDisambiguation(List<TrackedItemInstance> instances) {
    final enriched = instances.where((i) => i.isCloudEnriched).toList();
    if (enriched.isEmpty) return null;

    final buffer = StringBuffer();
    for (final inst in enriched) {
      if (inst.cloudSpokenLocationSentence != null &&
          inst.cloudSpokenLocationSentence!.isNotEmpty) {
        buffer.write('${inst.cloudSpokenLocationSentence} ');
      } else if (inst.cloudDistinctLabel != null &&
          inst.cloudDistinctLabel!.isNotEmpty) {
        final landmark = (inst.cloudLandmarkPosition != null &&
                inst.cloudLandmarkPosition!.isNotEmpty)
            ? ' on/near ${inst.cloudLandmarkPosition}'
            : '';
        buffer.write(
            'The ${inst.clockDirection} item is ${inst.cloudDistinctLabel}$landmark. ');
      }
    }
    return buffer.toString().trim();
  }

  // ===========================================================================
  // STATIC UTILITY HELPERS (OFFLINE COLOR & SPATIAL GEOMETRY)
  // ===========================================================================

  /// Extracts dominant color from bounding box crop using HSV quantization.
  static String extractDominantColorFromCrop(
      Uint8List imageBytes, NormalizedBoundingBox box) {
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return 'object';

      final cropX = (box.xmin * decoded.width).round().clamp(0, decoded.width - 1);
      final cropY = (box.ymin * decoded.height).round().clamp(0, decoded.height - 1);
      final cropW = (box.width * decoded.width).round().clamp(1, decoded.width - cropX);
      final cropH = (box.height * decoded.height).round().clamp(1, decoded.height - cropY);

      final cropped = img.copyCrop(decoded, x: cropX, y: cropY, width: cropW, height: cropH);

      double rSum = 0, gSum = 0, bSum = 0;
      int sampleCount = 0;

      for (int y = 0; y < cropped.height; y += 4) {
        for (int x = 0; x < cropped.width; x += 4) {
          final pixel = cropped.getPixel(x, y);
          rSum += pixel.r;
          gSum += pixel.g;
          bSum += pixel.b;
          sampleCount++;
        }
      }

      if (sampleCount == 0) return 'neutral';

      final avgR = rSum / sampleCount;
      final avgG = gSum / sampleCount;
      final avgB = bSum / sampleCount;

      return classifyRgbToHsvColor(avgR, avgG, avgB);
    } catch (_) {
      return 'neutral';
    }
  }

  static String classifyRgbToHsvColor(double r, double g, double b) {
    final max = math.max(r, math.max(g, b));
    final min = math.min(r, math.min(g, b));
    final delta = max - min;

    // Value/Brightness
    final v = max / 255.0;
    // Saturation
    final s = max == 0 ? 0.0 : delta / max;

    if (v < 0.18) return 'black';
    if (s < 0.15 && v > 0.80) return 'white';
    if (s < 0.18) return 'grey';

    // Hue in degrees [0, 360]
    double h = 0.0;
    if (delta != 0) {
      if (max == r) {
        h = 60 * (((g - b) / delta) % 6);
      } else if (max == g) {
        h = 60 * (((b - r) / delta) + 2);
      } else {
        h = 60 * (((r - g) / delta) + 4);
      }
    }
    if (h < 0) h += 360;

    if (h < 18 || h >= 340) return 'red';
    if (h < 45) return 'orange';
    if (h < 70) return 'yellow';
    if (h < 165) return 'green';
    if (h < 195) return 'cyan';
    if (h < 260) return 'blue';
    if (h < 305) return 'purple';
    return 'pink';
  }
}

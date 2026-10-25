import '../models/hybrid_voice_search_models.dart';

/// Pure on-device spatial-to-speech converter that translates bounding boxes
/// and Kalman velocity into natural spoken directional guidance.
class OfflineSpatialSpeechFormatter {
  /// Converts normalized horizontal center cx into standard clock-face direction.
  /// 0.00 - 0.16 -> "9 o'clock (far left)"
  /// 0.17 - 0.33 -> "10 o'clock (left)"
  /// 0.34 - 0.44 -> "11 o'clock (slightly left)"
  /// 0.45 - 0.55 -> "12 o'clock (straight ahead)"
  /// 0.56 - 0.66 -> "1 o'clock (slightly right)"
  /// 0.67 - 0.83 -> "2 o'clock (right)"
  /// 0.84 - 1.00 -> "3 o'clock (far right)"
  static String formatClockDirection(double cx) {
    if (cx <= 0.16) return "9 o'clock (far left)";
    if (cx <= 0.33) return "10 o'clock (left)";
    if (cx <= 0.44) return "11 o'clock (slightly left)";
    if (cx <= 0.55) return "12 o'clock (straight ahead)";
    if (cx <= 0.66) return "1 o'clock (slightly right)";
    if (cx <= 0.83) return "2 o'clock (right)";
    return "3 o'clock (far right)";
  }

  /// Short clock direction for micro-prompts (e.g., "12 o'clock")
  static String formatShortClockDirection(double cx) {
    if (cx <= 0.16) return "9 o'clock";
    if (cx <= 0.33) return "10 o'clock";
    if (cx <= 0.44) return "11 o'clock";
    if (cx <= 0.55) return "12 o'clock";
    if (cx <= 0.66) return "1 o'clock";
    if (cx <= 0.83) return "2 o'clock";
    return "3 o'clock";
  }

  /// Returns raw hour integer (9, 10, 11, 12, 1, 2, 3) for sector delta checks.
  static int getClockHour(double cx) {
    if (cx <= 0.16) return 9;
    if (cx <= 0.33) return 10;
    if (cx <= 0.44) return 11;
    if (cx <= 0.55) return 12;
    if (cx <= 0.66) return 1;
    if (cx <= 0.83) return 2;
    return 3;
  }

  /// Converts normalized vertical center cy into elevation guidance.
  /// cy < 0.30 -> "high up, tilt camera up"
  /// 0.30 <= cy <= 0.70 -> "at chest/table level"
  /// cy > 0.70 -> "low down, tilt camera down"
  static String formatVerticalTilt(double cy) {
    if (cy < 0.30) return "high up, tilt camera up";
    if (cy > 0.70) return "low down, tilt camera down";
    return "at chest/table level";
  }

  /// Estimates distance and reach based on bounding box area ratio A.
  /// A < 0.04 -> "about 6 to 8 feet away, walk forward"
  /// 0.04 <= A < 0.12 -> "about 3 to 4 feet away, take one step closer"
  /// 0.12 <= A < 0.25 -> "within arm's reach, extend your hand"
  /// A >= 0.25 and centered -> "directly in front of your hand, grab it now"
  static String formatDistanceAndReach(double area, bool isCentered) {
    if (area >= 0.25 && isCentered) {
      return "directly in front of your hand, grab it now";
    }
    if (area >= 0.12) {
      return "within arm's reach, extend your hand";
    }
    if (area >= 0.04) {
      return "about 3 to 4 feet away, take one step closer";
    }
    return "about 6 to 8 feet away, walk forward";
  }

  /// Short distance phrase for summaries (e.g. "3 feet away", "arm's length away")
  static String formatShortDistance(double area) {
    if (area >= 0.25) return "in grabbing reach";
    if (area >= 0.12) return "arm's length away";
    if (area >= 0.04) return "about 3 feet away";
    return "about 6 feet away";
  }

  /// Generates real-time micro-correction spoken commands as user pans/walks.
  /// Crisp, non-overlapping adjustments:
  /// - "Pan slightly left" / "Pan slightly right"
  /// - "Tilt camera up" / "Tilt camera down"
  /// - "Centered, walk two steps forward"
  /// - "Within arm's reach, reach your hand straight out"
  static String formatMicroCorrection(NormalizedBoundingBox bbox) {
    final cx = bbox.cx;
    final cy = bbox.cy;
    final area = bbox.area;
    final isCentered = (cx >= 0.45 && cx <= 0.55);

    if (area >= 0.25 && isCentered) {
      return "Within arm's reach, reach your hand straight out and grab it.";
    }

    if (cx < 0.40) {
      return "Pan slightly left.";
    }
    if (cx > 0.60) {
      return "Pan slightly right.";
    }

    if (cy < 0.30) {
      return "Tilt camera up.";
    }
    if (cy > 0.70) {
      return "Tilt camera down.";
    }

    if (area >= 0.12) {
      return "Centered, reach your hand forward.";
    }
    return "Centered, walk two steps forward.";
  }

  /// Generates initial comprehensive spoken location sentence.
  /// E.g. "Found your keys at 2 o'clock, about 4 feet away, on the wooden table next to the water bottle."
  static String formatInitialLocation({
    required String targetItem,
    required NormalizedBoundingBox bbox,
    String? color,
    String? landmark,
  }) {
    final clock = formatClockDirection(bbox.cx);
    final isCentered = (bbox.cx >= 0.45 && bbox.cx <= 0.55);
    final distance = formatDistanceAndReach(bbox.area, isCentered);
    final colorStr = (color != null && color.isNotEmpty) ? "$color " : "";
    final landmarkStr = (landmark != null && landmark.isNotEmpty) ? ", $landmark" : "";

    return "Found your $colorStr$targetItem at $clock, $distance$landmarkStr.";
  }

  /// Multi-Item Spoken Disambiguation Summary:
  /// Speaks left-to-right spatial announcements of all items and announces active target lock.
  /// E.g. "Found 3 bottles: a red Advil bottle at 10 o'clock, a blue water bottle straight ahead at 12 o'clock, and a green bottle at 3 o'clock. Guiding you to the blue bottle at 12 o'clock."
  static String formatMultiItemDisambiguation({
    required String targetItem,
    required List<TrackedItemInstance> instances,
    required String? activeTargetId,
  }) {
    if (instances.isEmpty) {
      return "Scanning for $targetItem. Pan camera slowly.";
    }

    if (instances.length == 1) {
      return formatInitialLocation(
        targetItem: targetItem,
        bbox: instances.first.bbox,
        color: instances.first.offlineColor,
        landmark: instances.first.cloudLandmarkPosition,
      );
    }

    // Sort instances left-to-right
    final sorted = List<TrackedItemInstance>.from(instances)
      ..sort((a, b) => a.bbox.cx.compareTo(b.bbox.cx));

    final count = sorted.length;
    final buffer = StringBuffer();
    buffer.write("Found $count ${targetItem}s: ");

    for (int i = 0; i < sorted.length; i++) {
      final inst = sorted[i];
      final distinctName = inst.distinctiveLabel;
      final clock = formatShortClockDirection(inst.bbox.cx);
      final dist = formatShortDistance(inst.bbox.area);

      if (i > 0 && i == sorted.length - 1) {
        buffer.write(", and ");
      } else if (i > 0) {
        buffer.write(", ");
      }

      buffer.write("a $distinctName at $clock, $dist");
    }

    // Identify active target
    final active = sorted.firstWhere(
      (i) => i.trackId == activeTargetId,
      orElse: () => sorted.first,
    );
    final activeName = active.distinctiveLabel;
    final activeClock = formatShortClockDirection(active.bbox.cx);

    buffer.write(". Guiding you to the $activeName at $activeClock.");
    return buffer.toString();
  }

  /// Spoken confirmation when switching between multiple identical items.
  /// E.g. "Switched to white mug at 10 o'clock, 3 feet away. Pan left to center it."
  static String formatTargetSwitched(TrackedItemInstance newTarget) {
    final label = newTarget.distinctiveLabel;
    final clock = formatShortClockDirection(newTarget.bbox.cx);
    final dist = formatShortDistance(newTarget.bbox.area);

    String nudge = "Keep camera steady.";
    if (newTarget.bbox.cx < 0.40) {
      nudge = "Pan left to center it.";
    } else if (newTarget.bbox.cx > 0.60) {
      nudge = "Pan right to center it.";
    } else if (newTarget.bbox.cy < 0.30) {
      nudge = "Tilt camera up to center it.";
    } else if (newTarget.bbox.cy > 0.70) {
      nudge = "Tilt camera down to center it.";
    } else {
      nudge = "Centered straight ahead.";
    }

    return "Switched to $label at $clock, $dist. $nudge";
  }

  /// Translates last-known Kalman velocity vector into target recovery prompts.
  /// If vx is negative, target moved left relative to frame (user panned right).
  /// If vx is positive, target moved right relative to frame (user panned left).
  static String formatLostTargetRecovery({
    required String targetItem,
    required double vx,
    required double vy,
  }) {
    if (vx < -0.012) {
      return "Lost view of $targetItem—you panned too far right, move camera back to the left.";
    }
    if (vx > 0.012) {
      return "Lost view of $targetItem—you panned too far left, move camera back to the right.";
    }
    if (vy < -0.012) {
      return "Lost view of $targetItem—tilt camera back down.";
    }
    if (vy > 0.012) {
      return "Lost view of $targetItem—tilt camera back up.";
    }
    return "$targetItem out of view, pan camera back slowly.";
  }
}

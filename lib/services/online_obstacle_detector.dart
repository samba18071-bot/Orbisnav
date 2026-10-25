import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../controllers/audio_mutex_controller.dart';
import 'kinematic_motion_tracker.dart';

/// Represents an individual obstacle detected with metric distance, clock direction, and dynamic motion kinematics.
class DetectedObstacle {
  final String label;
  final double confidence;
  final double xMin;
  final double yMin;
  final double xMax;
  final double yMax;
  final double distanceMeters;
  final double ttcSeconds;
  final AudioPriority priority;
  final String clockPosition; // e.g., "12 o'clock", "2 o'clock", "10 o'clock"
  final ObjectMotionType motionType;
  final String detailedDescription;
  final double velocityMps; // Radial velocity in m/s (negative = approaching, positive = receding)

  DetectedObstacle({
    required this.label,
    required this.confidence,
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
    required this.distanceMeters,
    required this.ttcSeconds,
    required this.priority,
    required this.clockPosition,
    this.motionType = ObjectMotionType.stationaryAhead,
    String? detailedDescription,
    this.velocityMps = 0.0,
  }) : detailedDescription = detailedDescription ?? "$label ahead";

  bool get isHazard =>
      priority == AudioPriority.level0Critical ||
      priority == AudioPriority.level1Safety;

  bool get isMoving =>
      motionType == ObjectMotionType.approachingTowardsUser ||
      motionType == ObjectMotionType.movingAwayFromUser ||
      motionType == ObjectMotionType.crossingLeftToRight ||
      motionType == ObjectMotionType.crossingRightToLeft;

  String get formattedMotionBadge {
    switch (motionType) {
      case ObjectMotionType.approachingTowardsUser:
        return "APPROACHING (${velocityMps.abs().toStringAsFixed(1)}m/s)";
      case ObjectMotionType.movingAwayFromUser:
        return "MOVING AWAY (+${velocityMps.abs().toStringAsFixed(1)}m/s)";
      case ObjectMotionType.crossingLeftToRight:
        return "CROSSING (L→R)";
      case ObjectMotionType.crossingRightToLeft:
        return "CROSSING (R→L)";
      case ObjectMotionType.overheadHazard:
        return "OVERHEAD HAZARD";
      case ObjectMotionType.stationaryAhead:
        return "STATIONARY";
    }
  }

  /// Full speech announcement with rich dynamic motion detail (e.g. "A person is walking towards you at 12 o'clock, 2.1 meters.")
  String get speechAnnouncement {
    if (detailedDescription.isNotEmpty) {
      return "$detailedDescription at $clockPosition, ${distanceMeters.toStringAsFixed(1)} meters.";
    }
    return "$label at $clockPosition, ${distanceMeters.toStringAsFixed(1)} meters.";
  }

  /// Concise object name, position, and distance for fast, easy navigation cues (detailed narration in Scene Analyser)
  String get conciseSpeech => "$label at $clockPosition, ${distanceMeters.toStringAsFixed(1)} meters.";

  /// Comprehensive natural language explanation for visually impaired users
  /// explaining what the object is, its precise location, motion characteristics,
  /// and clear walking advice for safe traversal.
  String get comprehensiveExplanation {
    final name = label.toLowerCase();
    final clock = clockPosition;
    final dist = distanceMeters.toStringAsFixed(1);

    String objectNature;
    if (['person', 'pedestrian'].contains(name)) {
      objectNature = "A person in your walking path";
    } else if (['car', 'truck', 'bus', 'motorcycle', 'bicycle'].contains(name)) {
      objectNature = "A vehicle presenting active traffic risk";
    } else if (['chair', 'couch', 'sofa', 'armchair'].contains(name)) {
      objectNature = "A seating chair with protruding legs";
    } else if (['dining table', 'desk', 'table'].contains(name)) {
      objectNature = "A table blocking the walking corridor at waist level";
    } else if (['bed'].contains(name)) {
      objectNature = "A bed acting as a low ground obstacle";
    } else if (['toilet', 'sink'].contains(name)) {
      objectNature = "A bathroom fixture directly in front of you";
    } else if (['stairs', 'step', 'curb', 'escalator'].contains(name)) {
      objectNature = "An elevation step change requiring careful foot placement";
    } else if (['door', 'entrance'].contains(name)) {
      objectNature = "A doorway opening for passage";
    } else if (['pole', 'post', 'tree', 'traffic light', 'fire hydrant'].contains(name)) {
      objectNature = "A vertical street obstacle in the walking envelope";
    } else if (['dog', 'cat', 'animal', 'pet'].contains(name)) {
      objectNature = "A domestic animal moving at floor level";
    } else if (['bottle', 'cup', 'glass'].contains(name)) {
      objectNature = "A beverage container placed on a surface";
    } else if (['backpack', 'handbag', 'suitcase', 'bag'].contains(name)) {
      objectNature = "Luggage or a bag resting in the walking area";
    } else if (['laptop', 'cell phone', 'keyboard', 'mouse', 'book'].contains(name)) {
      objectNature = "A personal work device placed on a surface";
    } else {
      objectNature = "A $name";
    }

    String movementDetail;
    switch (motionType) {
      case ObjectMotionType.approachingTowardsUser:
        movementDetail = "moving towards you at ${velocityMps.abs().toStringAsFixed(1)} m/s";
        break;
      case ObjectMotionType.movingAwayFromUser:
        movementDetail = "moving away from you";
        break;
      case ObjectMotionType.crossingLeftToRight:
        movementDetail = "crossing from your left to right";
        break;
      case ObjectMotionType.crossingRightToLeft:
        movementDetail = "crossing from your right to left";
        break;
      case ObjectMotionType.overheadHazard:
        movementDetail = "at head or shoulder elevation";
        break;
      case ObjectMotionType.stationaryAhead:
        movementDetail = "currently stationary";
        break;
    }

    String safeAction;
    if (distanceMeters < 0.8) {
      if (clock.contains("12")) {
        safeAction = "Immediate action: Stop and take one step right or left to avoid contact.";
      } else if (clock.contains("9") || clock.contains("10") || clock.contains("11")) {
        safeAction = "Keep to your right side to maintain safe clearance.";
      } else {
        safeAction = "Keep to your left side to maintain safe clearance.";
      }
    } else if (distanceMeters < 2.0) {
      if (clock.contains("12")) {
        safeAction = "Safe corridor: Veer slightly right towards 1 or 2 o'clock to bypass.";
      } else {
        safeAction = "Safe corridor: Forward walking path is open; maintain current line.";
      }
    } else {
      safeAction = "Safe corridor: Ample walking distance ahead.";
    }

    return "$objectNature located at $clock, $dist meters away ($movementDetail). $safeAction";
  }

  /// Natural language description of the obstacle (nature, clock position, distance, and movement)
  /// Used for obstacles > 1.5m away to inform the blind user of their surroundings without intrusive steering advice.
  String get obstacleDescription {
    final name = label.toLowerCase();
    final clock = clockPosition;
    final dist = distanceMeters.toStringAsFixed(1);

    String objectNature;
    if (['person', 'pedestrian'].contains(name)) {
      objectNature = "A person in your walking path";
    } else if (['car', 'truck', 'bus', 'motorcycle', 'bicycle'].contains(name)) {
      objectNature = "A vehicle presenting active traffic risk";
    } else if (['chair', 'couch', 'sofa', 'armchair'].contains(name)) {
      objectNature = "A seating chair with protruding legs";
    } else if (['dining table', 'desk', 'table'].contains(name)) {
      objectNature = "A table blocking the walking corridor at waist level";
    } else if (['bed'].contains(name)) {
      objectNature = "A bed acting as a low ground obstacle";
    } else if (['toilet', 'sink'].contains(name)) {
      objectNature = "A bathroom fixture directly in front of you";
    } else if (['stairs', 'step', 'curb', 'escalator'].contains(name)) {
      objectNature = "An elevation step change requiring careful foot placement";
    } else if (['door', 'entrance'].contains(name)) {
      objectNature = "A doorway opening for passage";
    } else if (['pole', 'post', 'tree', 'traffic light', 'fire hydrant'].contains(name)) {
      objectNature = "A vertical street obstacle in the walking envelope";
    } else if (['dog', 'cat', 'animal', 'pet'].contains(name)) {
      objectNature = "A domestic animal moving at floor level";
    } else if (['bottle', 'cup', 'glass'].contains(name)) {
      objectNature = "A beverage container placed on a surface";
    } else if (['backpack', 'handbag', 'suitcase', 'bag'].contains(name)) {
      objectNature = "Luggage or a bag resting in the walking area";
    } else if (['laptop', 'cell phone', 'keyboard', 'mouse', 'book'].contains(name)) {
      objectNature = "A personal work device placed on a surface";
    } else {
      objectNature = "A $name";
    }

    String movementDetail;
    switch (motionType) {
      case ObjectMotionType.approachingTowardsUser:
        movementDetail = "moving towards you at ${velocityMps.abs().toStringAsFixed(1)} m/s";
        break;
      case ObjectMotionType.movingAwayFromUser:
        movementDetail = "moving away from you";
        break;
      case ObjectMotionType.crossingLeftToRight:
        movementDetail = "crossing from your left to right";
        break;
      case ObjectMotionType.crossingRightToLeft:
        movementDetail = "crossing from your right to left";
        break;
      case ObjectMotionType.overheadHazard:
        movementDetail = "at head or shoulder elevation";
        break;
      case ObjectMotionType.stationaryAhead:
        movementDetail = "currently stationary";
        break;
    }

    return "$objectNature located at $clock, $dist meters away ($movementDetail).";
  }

  /// Compact safe walking bypass recommendation

  String get bypassRecommendation {
    if (distanceMeters < 0.8) {
      if (clockPosition.contains("12")) return "Stop / Step Back or Sideways";
      if (clockPosition.contains("10") || clockPosition.contains("11") || clockPosition.contains("9")) return "Keep Right";
      return "Keep Left";
    }
    if (distanceMeters < 2.0) {
      if (clockPosition.contains("12")) return "Veer Right (2 o'clock)";
      return "Maintain Center Path";
    }
    return "Clear Path Ahead";
  }
}

/// Real-Time Optimal Navigation Corridor Direction
enum OptimalCorridorDirection {
  straightAhead, // 12 o'clock
  veerLeft,       // 10 o'clock
  veerRight,      // 2 o'clock
  blockedHold,    // Path completely obstructed
}

/// Real-Time Optimal Navigation Path calculated across spatial vision corridors
class OptimalPathRecommendation {
  final OptimalCorridorDirection direction;
  final String clockDirection; // "12 o'clock", "10 o'clock", "2 o'clock", "Hold"
  final String voiceInstruction; // e.g. "Veer right towards 2 o'clock - path clear"
  final double clearanceMeters;
  final bool isPathBlocked;

  const OptimalPathRecommendation({
    required this.direction,
    required this.clockDirection,
    required this.voiceInstruction,
    required this.clearanceMeters,
    required this.isPathBlocked,
  });

  /// Formats the optimal safe walking route with clearance and step guidance
  String get safeWalkingRouteSummary {
    switch (direction) {
      case OptimalCorridorDirection.straightAhead:
        return "Optimal Walking Route: Forward corridor at 12 o'clock is clear for ${clearanceMeters.toStringAsFixed(1)}m. Walk straight at normal pace.";
      case OptimalCorridorDirection.veerLeft:
        return "Optimal Walking Route: Veer left towards 10 o'clock. Safe corridor open for ${clearanceMeters.toStringAsFixed(1)}m to bypass center obstacle.";
      case OptimalCorridorDirection.veerRight:
        return "Optimal Walking Route: Veer right towards 2 o'clock. Safe corridor open for ${clearanceMeters.toStringAsFixed(1)}m to bypass center obstacle.";
      case OptimalCorridorDirection.blockedHold:
        return "Optimal Walking Route: Path fully blocked (${clearanceMeters.toStringAsFixed(1)}m clearance). Stop and wait or turn around.";
    }
  }

  /// Step-by-step pedestrian walking advice
  List<String> get stepByStepGuidance {
    switch (direction) {
      case OptimalCorridorDirection.straightAhead:
        return [
          "Maintain current heading forward along 12 o'clock corridor.",
          "Direct path has ${clearanceMeters.toStringAsFixed(1)}m collision-free clearance ahead.",
          "Walking speed: Natural, unobstructed stride.",
        ];
      case OptimalCorridorDirection.veerLeft:
        return [
          "Shift trajectory 15° to the left (10 o'clock vector).",
          "Take 1 to 2 paces to your left to circumvent central obstacle.",
          "Corridor provides ${clearanceMeters.toStringAsFixed(1)}m of safe clearance.",
        ];
      case OptimalCorridorDirection.veerRight:
        return [
          "Shift trajectory 15° to the right (2 o'clock vector).",
          "Take 1 to 2 paces to your right to circumvent central obstacle.",
          "Corridor provides ${clearanceMeters.toStringAsFixed(1)}m of safe clearance.",
        ];
      case OptimalCorridorDirection.blockedHold:
        return [
          "Halt immediately — forward and flank paths are obstructed.",
          "Nearest barrier is within ${clearanceMeters.toStringAsFixed(1)}m buffer.",
          "Use white cane or rotate 90° to acquire alternate open path.",
        ];
    }
  }

  /// Computes the optimal collision-free clearance path from active detected obstacles
  static OptimalPathRecommendation computeOptimalPath(List<DetectedObstacle> obstacles) {
    if (obstacles.isEmpty) {
      return const OptimalPathRecommendation(
        direction: OptimalCorridorDirection.straightAhead,
        clockDirection: "12 o'clock",
        voiceInstruction: "Path clear ahead. Continue straight.",
        clearanceMeters: 6.0,
        isPathBlocked: false,
      );
    }

    double leftClearance = 6.0;
    double centerClearance = 6.0;
    double rightClearance = 6.0;

    for (final obs in obstacles) {
      final normX = (obs.xMin + obs.xMax) / 2.0;
      final dist = obs.distanceMeters;

      if (normX < 0.38 || obs.clockPosition == "9 o'clock" || obs.clockPosition == "10 o'clock") {
        if (dist < leftClearance) leftClearance = dist;
      } else if (normX > 0.62 || obs.clockPosition == "2 o'clock" || obs.clockPosition == "3 o'clock") {
        if (dist < rightClearance) rightClearance = dist;
      } else {
        if (dist < centerClearance) centerClearance = dist;
      }

    }

    // 1. Center direct path blocked or narrowed (< 2.5m)
    if (centerClearance < 2.5) {
      if (leftClearance > rightClearance && leftClearance >= 1.8) {
        return OptimalPathRecommendation(
          direction: OptimalCorridorDirection.veerLeft,
          clockDirection: "10 o'clock",
          voiceInstruction: "Step left towards 10 o'clock to bypass.",
          clearanceMeters: leftClearance,
          isPathBlocked: true,
        );
      } else if (rightClearance >= 1.8) {
        return OptimalPathRecommendation(
          direction: OptimalCorridorDirection.veerRight,
          clockDirection: "2 o'clock",
          voiceInstruction: "Step right towards 2 o'clock to bypass.",
          clearanceMeters: rightClearance,
          isPathBlocked: true,
        );
      } else if (leftClearance >= 1.3) {
        return OptimalPathRecommendation(
          direction: OptimalCorridorDirection.veerLeft,
          clockDirection: "10 o'clock",
          voiceInstruction: "Caution. Narrow passage on left at 10 o'clock.",
          clearanceMeters: leftClearance,
          isPathBlocked: true,
        );
      } else if (rightClearance >= 1.3) {
        return OptimalPathRecommendation(
          direction: OptimalCorridorDirection.veerRight,
          clockDirection: "2 o'clock",
          voiceInstruction: "Caution. Narrow passage on right at 2 o'clock.",
          clearanceMeters: rightClearance,
          isPathBlocked: true,
        );
      } else {
        return const OptimalPathRecommendation(
          direction: OptimalCorridorDirection.blockedHold,
          clockDirection: "Hold",
          voiceInstruction: "Path completely obstructed. Please stop and pause.",
          clearanceMeters: 0.8,
          isPathBlocked: true,
        );
      }
    }

    // 2. Center direct path is open (>= 2.5m)
    if (leftClearance < 1.8 && rightClearance >= 2.0) {
      return OptimalPathRecommendation(
        direction: OptimalCorridorDirection.straightAhead,
        clockDirection: "12 o'clock",
        voiceInstruction: "Obstacle on left. Maintain center at 12 o'clock.",
        clearanceMeters: centerClearance,
        isPathBlocked: false,
      );
    } else if (rightClearance < 1.8 && leftClearance >= 2.0) {
      return OptimalPathRecommendation(
        direction: OptimalCorridorDirection.straightAhead,
        clockDirection: "12 o'clock",
        voiceInstruction: "Obstacle on right. Maintain center at 12 o'clock.",
        clearanceMeters: centerClearance,
        isPathBlocked: false,
      );
    }

    return OptimalPathRecommendation(
      direction: OptimalCorridorDirection.straightAhead,
      clockDirection: "12 o'clock",
      voiceInstruction: "Path directly ahead is clear.",
      clearanceMeters: centerClearance,
      isPathBlocked: false,
    );
  }
}

/// Result of an obstacle detection cycle
class OnlineDetectionCycleResult {
  final List<DetectedObstacle> obstacles;
  final int latencyMs;
  final DateTime timestamp;
  final bool isOnlineSuccess;
  final String statusMessage;
  final OptimalPathRecommendation optimalPath;

  OnlineDetectionCycleResult({
    required this.obstacles,
    required this.latencyMs,
    required this.timestamp,
    required this.isOnlineSuccess,
    required this.statusMessage,
    OptimalPathRecommendation? optimalPath,
  }) : optimalPath = optimalPath ?? OptimalPathRecommendation.computeOptimalPath(obstacles);

  DetectedObstacle? get highestHazard {
    if (obstacles.isEmpty) return null;
    final hazards = obstacles.where((o) => o.isHazard).toList();
    if (hazards.isEmpty) return obstacles.first;
    hazards.sort((a, b) {
      final pComp = a.priority.value.compareTo(b.priority.value);
      if (pComp != 0) return pComp;
      return a.distanceMeters.compareTo(b.distanceMeters);
    });
    return hazards.first;
  }
}

/// HTTP API Client for detection (optional/fallback)
class OnlineObstacleDetector {
  static const String _defaultUrl = "http://127.0.0.1:8000/detect";
  final String apiUrl;
  final http.Client _client = http.Client();

  OnlineObstacleDetector({this.apiUrl = _defaultUrl});

  Future<OnlineDetectionCycleResult> detectObstacles(
    Uint8List imageBytes, {
    double devicePitchDeg = 0.0,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final uri = Uri.parse(apiUrl);
      final request = http.MultipartRequest("POST", uri);
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        imageBytes,
        filename: 'frame.jpg',
      ));
      request.fields['pitch_deg'] = devicePitchDeg.toStringAsFixed(2);

      final streamedResponse = await request.send().timeout(const Duration(seconds: 4));
      final response = await http.Response.fromStream(streamedResponse);
      stopwatch.stop();

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rawList = data['obstacles'] as List<dynamic>? ?? [];

        final obstacles = rawList.map((item) {
          final m = item as Map<String, dynamic>;
          final prioInt = (m['priority'] as num?)?.toInt() ?? 1;
          final priority = AudioPriority.values.firstWhere(
            (p) => p.value == prioInt,
            orElse: () => AudioPriority.level1Safety,
          );

          return DetectedObstacle(
            label: m['label']?.toString() ?? "Obstacle",
            confidence: (m['confidence'] as num?)?.toDouble() ?? 0.85,
            xMin: (m['x_min'] as num?)?.toDouble() ?? 0.2,
            yMin: (m['y_min'] as num?)?.toDouble() ?? 0.2,
            xMax: (m['x_max'] as num?)?.toDouble() ?? 0.8,
            yMax: (m['y_max'] as num?)?.toDouble() ?? 0.8,
            distanceMeters: (m['distance_m'] as num?)?.toDouble() ?? 2.0,
            ttcSeconds: (m['ttc_s'] as num?)?.toDouble() ?? 1.8,
            priority: priority,
            clockPosition: m['clock_position']?.toString() ?? "12 o'clock",
          );
        }).toList();

        final enriched = KinematicMotionTracker().enrichWithKinematics(obstacles);

        return OnlineDetectionCycleResult(
          obstacles: enriched,
          latencyMs: stopwatch.elapsedMilliseconds,
          timestamp: DateTime.now(),
          isOnlineSuccess: true,
          statusMessage: "${enriched.length} obstacles detected (${stopwatch.elapsedMilliseconds}ms)",
        );
      } else {
        return OnlineDetectionCycleResult(
          obstacles: [],
          latencyMs: stopwatch.elapsedMilliseconds,
          timestamp: DateTime.now(),
          isOnlineSuccess: false,
          statusMessage: "Server HTTP ${response.statusCode}",
        );
      }
    } catch (e) {
      stopwatch.stop();
      return OnlineDetectionCycleResult(
        obstacles: [],
        latencyMs: stopwatch.elapsedMilliseconds,
        timestamp: DateTime.now(),
        isOnlineSuccess: false,
        statusMessage: "Detection unavailable: $e",
      );
    }
  }

  void dispose() {
    _client.close();
  }
}

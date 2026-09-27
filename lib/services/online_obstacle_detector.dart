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

  /// Full speech announcement with rich dynamic detail (e.g. "Person is walking towards you at 12 o'clock, 2.1 meters")
  String get speechAnnouncement {
    if (detailedDescription.isNotEmpty && !detailedDescription.endsWith("ahead")) {
      return "$detailedDescription at $clockPosition, ${distanceMeters.toStringAsFixed(1)} meters.";
    }
    return "$label at $clockPosition, ${distanceMeters.toStringAsFixed(1)} meters.";
  }
}

/// Result of an obstacle detection cycle
class OnlineDetectionCycleResult {
  final List<DetectedObstacle> obstacles;
  final int latencyMs;
  final DateTime timestamp;
  final bool isOnlineSuccess;
  final String statusMessage;

  OnlineDetectionCycleResult({
    required this.obstacles,
    required this.latencyMs,
    required this.timestamp,
    required this.isOnlineSuccess,
    required this.statusMessage,
  });

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

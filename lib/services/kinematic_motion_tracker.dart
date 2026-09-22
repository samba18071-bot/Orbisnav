import '../controllers/audio_mutex_controller.dart';
import 'online_obstacle_detector.dart';

/// Motion Dynamics Classification
enum ObjectMotionType {
  approachingTowardsUser, // Closing in rapidly (e.g., person walking towards you, car approaching)
  movingAwayFromUser,     // Moving away (e.g., person walking away)
  overheadHazard,         // Low-hanging branch / awning / head-level protrusion
  stationaryAhead,        // Static obstacle in path (e.g., chair, table, pole)
}

/// Historical observation snapshot for velocity & trajectory estimation
class _TrackHistoryPoint {
  final double distanceMeters;
  final double xCenter;
  final double yMin;
  final double bboxHeight;
  final DateTime timestamp;

  _TrackHistoryPoint({
    required this.distanceMeters,
    required this.xCenter,
    required this.yMin,
    required this.bboxHeight,
    required this.timestamp,
  });
}

/// KinematicMotionTracker: Computes real-time motion vectors, radial velocities,
/// approach trajectories, and vertical obstacle levels across video frames.
class KinematicMotionTracker {
  static final KinematicMotionTracker _instance =
      KinematicMotionTracker._internal();
  factory KinematicMotionTracker() => _instance;

  KinematicMotionTracker._internal();

  // Track map: trackKey -> List of historical points
  final Map<String, List<_TrackHistoryPoint>> _tracks = {};

  /// Updates and enriches obstacles with dynamic motion kinematics and descriptive phrases.
  List<DetectedObstacle> enrichWithKinematics(List<DetectedObstacle> rawObstacles) {
    final now = DateTime.now();
    final enriched = <DetectedObstacle>[];

    // Cleanup old tracks (> 3.5 seconds absent)
    _tracks.removeWhere((_, history) {
      if (history.isEmpty) return true;
      return now.difference(history.last.timestamp).inMilliseconds > 3500;
    });

    for (final obs in rawObstacles) {
      final trackKey = "${obs.label.toLowerCase().trim()}_${obs.clockPosition.toLowerCase().trim()}";

      final currentPoint = _TrackHistoryPoint(
        distanceMeters: obs.distanceMeters,
        xCenter: (obs.xMin + obs.xMax) / 2.0,
        yMin: obs.yMin,
        bboxHeight: (obs.yMax - obs.yMin).abs(),
        timestamp: now,
      );

      final history = _tracks.putIfAbsent(trackKey, () => <_TrackHistoryPoint>[]);
      history.add(currentPoint);

      // Keep recent 6 observations (~1.5 to 2.5 seconds window)
      if (history.length > 6) {
        history.removeAt(0);
      }

      // Compute velocity (meters per second)
      double velocityMps = 0.0;
      double bboxGrowthRate = 0.0;

      if (history.length >= 2) {
        final oldest = history.first;
        final deltaSeconds = now.difference(oldest.timestamp).inMilliseconds / 1000.0;

        if (deltaSeconds > 0.25) {
          // Negative velocity = closing distance (approaching)
          // Positive velocity = increasing distance (moving away)
          velocityMps = (currentPoint.distanceMeters - oldest.distanceMeters) / deltaSeconds;
          bboxGrowthRate = (currentPoint.bboxHeight - oldest.bboxHeight) / deltaSeconds;
        }
      }

      // Classify motion dynamics & generate rich descriptive speech
      final motionResult = _classifyMotion(
        label: obs.label,
        distanceMeters: obs.distanceMeters,
        yMin: obs.yMin,
        yMax: obs.yMax,
        velocityMps: velocityMps,
        bboxGrowthRate: bboxGrowthRate,
        currentPriority: obs.priority,
      );

      enriched.add(DetectedObstacle(
        label: obs.label,
        confidence: obs.confidence,
        xMin: obs.xMin,
        yMin: obs.yMin,
        xMax: obs.xMax,
        yMax: obs.yMax,
        distanceMeters: obs.distanceMeters,
        ttcSeconds: motionResult.computedTtc,
        priority: motionResult.priority,
        clockPosition: obs.clockPosition,
        motionType: motionResult.motionType,
        detailedDescription: motionResult.detailedDescription,
      ));
    }

    return enriched;
  }

  /// Classify motion state and formulate detailed assistive phrase
  _MotionClassificationResult _classifyMotion({
    required String label,
    required double distanceMeters,
    required double yMin,
    required double yMax,
    required double velocityMps,
    required double bboxGrowthRate,
    required AudioPriority currentPriority,
  }) {
    final lower = label.toLowerCase();
    final isPerson = lower.contains("person") || lower.contains("pedestrian") || lower.contains("man") || lower.contains("woman");
    final isVehicle = lower.contains("car") || lower.contains("vehicle") || lower.contains("bus") || lower.contains("truck") || lower.contains("motorcycle") || lower.contains("bicycle");
    final isBranchOrOverhead = lower.contains("branch") || lower.contains("tree") || lower.contains("plant") || (yMin < 0.22 && yMax < 0.60);

    ObjectMotionType motionType = ObjectMotionType.stationaryAhead;
    String motionPhrase = "";
    AudioPriority priority = currentPriority;
    double computedTtc = distanceMeters / 1.1;

    // 1. Detect Overhead / Low-Hanging Branch Hazards
    if (isBranchOrOverhead && yMin < 0.20 && distanceMeters < 3.0) {
      motionType = ObjectMotionType.overheadHazard;
      motionPhrase = "Low-hanging branch overhead";
      priority = AudioPriority.level0Critical;
    }
    // 2. Approaching Dynamics (Closing distance faster than 0.25 m/s or expanding bbox)
    else if (velocityMps < -0.28 || bboxGrowthRate > 0.08) {
      motionType = ObjectMotionType.approachingTowardsUser;
      final approachSpeed = velocityMps.abs();
      computedTtc = approachSpeed > 0.1 ? (distanceMeters / approachSpeed) : (distanceMeters / 1.5);

      if (isPerson) {
        motionPhrase = "Person is walking towards you";
        priority = distanceMeters < 3.0 ? AudioPriority.level0Critical : AudioPriority.level1Safety;
      } else if (isVehicle) {
        motionPhrase = "Vehicle is approaching you";
        priority = AudioPriority.level0Critical;
      } else {
        motionPhrase = "$label approaching";
        priority = distanceMeters < 2.0 ? AudioPriority.level0Critical : AudioPriority.level1Safety;
      }
    }
    // 3. Moving Away Dynamics (Distance increasing faster than 0.25 m/s)
    else if (velocityMps > 0.28) {
      motionType = ObjectMotionType.movingAwayFromUser;
      if (isPerson) {
        motionPhrase = "Person is walking away";
        priority = AudioPriority.level2Navigation;
      } else if (isVehicle) {
        motionPhrase = "Vehicle is moving away";
        priority = AudioPriority.level2Navigation;
      } else {
        motionPhrase = "$label moving away";
        priority = AudioPriority.level2Navigation;
      }
    }
    // 4. Stationary / Standard Proximity
    else {
      motionType = ObjectMotionType.stationaryAhead;
      if (isPerson) {
        motionPhrase = "Person standing ahead";
      } else if (isVehicle) {
        motionPhrase = "Stationary vehicle ahead";
      } else {
        motionPhrase = "$label ahead";
      }
    }

    return _MotionClassificationResult(
      motionType: motionType,
      detailedDescription: motionPhrase,
      priority: priority,
      computedTtc: double.parse(computedTtc.clamp(0.2, 10.0).toStringAsFixed(1)),
    );
  }

  void reset() {
    _tracks.clear();
  }
}

class _MotionClassificationResult {
  final ObjectMotionType motionType;
  final String detailedDescription;
  final AudioPriority priority;
  final double computedTtc;

  _MotionClassificationResult({
    required this.motionType,
    required this.detailedDescription,
    required this.priority,
    required this.computedTtc,
  });
}

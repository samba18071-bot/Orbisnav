import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/controllers/audio_mutex_controller.dart';
import 'package:orbisnav/services/kinematic_motion_tracker.dart';
import 'package:orbisnav/services/online_obstacle_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Channel 1: Obstacle >1.5m Description vs <1.5m Optimal Route Speech Tests', () {
    test('DetectedObstacle provides descriptive explanation when > 1.5m', () {
      final farObstacle = DetectedObstacle(
        label: 'chair',
        confidence: 0.9,
        xMin: 0.2,
        yMin: 0.3,
        xMax: 0.4,
        yMax: 0.7,
        distanceMeters: 2.4, // > 1.5m
        ttcSeconds: 99.0,
        priority: AudioPriority.level1Safety,
        clockPosition: "11 o'clock",
        motionType: ObjectMotionType.stationaryAhead,
      );

      expect(farObstacle.distanceMeters, greaterThan(1.5));
      final desc = farObstacle.obstacleDescription;
      expect(desc, contains("A seating chair with protruding legs"));
      expect(desc, contains("11 o'clock"));
      expect(desc, contains("2.4 meters away"));
      expect(desc, contains("currently stationary"));
    });

    test('DetectedObstacle description includes motion dynamics when moving at distance', () {
      final movingPersonFar = DetectedObstacle(
        label: 'person',
        confidence: 0.95,
        xMin: 0.45,
        yMin: 0.2,
        xMax: 0.55,
        yMax: 0.8,
        distanceMeters: 3.2, // > 1.5m
        ttcSeconds: 2.6,
        priority: AudioPriority.level1Safety,
        clockPosition: "12 o'clock",
        motionType: ObjectMotionType.approachingTowardsUser,
        velocityMps: -1.2,
      );

      expect(movingPersonFar.distanceMeters, greaterThan(1.5));
      final desc = movingPersonFar.obstacleDescription;
      expect(desc, contains("A person in your walking path"));
      expect(desc, contains("12 o'clock"));
      expect(desc, contains("3.2 meters away"));
      expect(desc, contains("moving towards you at 1.2 m/s"));
    });

    test('OptimalPathRecommendation generates safe route when obstacle is < 1.5m', () {
      final nearObstacle = DetectedObstacle(
        label: 'table',
        confidence: 0.92,
        xMin: 0.4,
        yMin: 0.3,
        xMax: 0.6,
        yMax: 0.8,
        distanceMeters: 1.1, // < 1.5m
        ttcSeconds: 1.0,
        priority: AudioPriority.level0Critical,
        clockPosition: "12 o'clock",
      );

      final optPath = OptimalPathRecommendation.computeOptimalPath([nearObstacle]);
      expect(nearObstacle.distanceMeters, lessThanOrEqualTo(1.5));
      expect(optPath.isPathBlocked, isTrue);
      // Path must give optimal routing direction (e.g. bypass left or right)
      expect(optPath.voiceInstruction, isNotEmpty);
      expect(
        optPath.voiceInstruction,
        anyOf([
          contains("Step left"),
          contains("Step right"),
          contains("Narrow passage"),
          contains("obstructed"),
        ]),
      );
    });

    test('Channel 1 provides concise object name and optimal route voice output', () {
      final obstacle = DetectedObstacle(
        label: 'bicycle',
        confidence: 0.94,
        xMin: 0.4,
        yMin: 0.3,
        xMax: 0.6,
        yMax: 0.7,
        distanceMeters: 1.2,
        ttcSeconds: 1.1,
        priority: AudioPriority.level0Critical,
        clockPosition: "12 o'clock",
      );

      final opt = OptimalPathRecommendation.computeOptimalPath([obstacle]);

      // Easy and concise voice output format (object name and optimal route):
      final isCritical = obstacle.priority == AudioPriority.level0Critical || obstacle.distanceMeters <= 1.0;
      final prefix = isCritical ? "Caution! " : "";
      final speech = "$prefix${obstacle.label} at ${obstacle.clockPosition}, ${obstacle.distanceMeters.toStringAsFixed(1)} meters. Optimal route: ${opt.voiceInstruction}.";

      expect(speech, contains("Caution!"));
      expect(speech, contains("bicycle at 12 o'clock, 1.2 meters."));
      expect(speech, contains("Optimal route:"));
      expect(speech, contains(opt.voiceInstruction));
      // Detailed narration is reserved for Scene Analyser
      expect(obstacle.obstacleDescription, contains("A vehicle presenting active traffic risk"));
    });
  });
}

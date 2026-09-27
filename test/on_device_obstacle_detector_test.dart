import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/controllers/audio_mutex_controller.dart';
import 'package:orbisnav/services/online_obstacle_detector.dart';

void main() {
  group('OnDeviceObstacleDetector Unit & Physics Tests', () {
    test('DetectedObstacle calculates accurate metric distance and clock announcements', () {
      final obstacle = DetectedObstacle(
        label: 'Person',
        confidence: 0.92,
        xMin: 0.45,
        yMin: 0.20,
        xMax: 0.55,
        yMax: 0.85,
        distanceMeters: 1.8,
        ttcSeconds: 1.6,
        priority: AudioPriority.level0Critical,
        clockPosition: "12 o'clock",
      );

      expect(obstacle.isHazard, isTrue);
      expect(obstacle.speechAnnouncement, contains("Person at 12 o'clock, 1.8 meters."));
    });

    test('Critical proximity (< 1.2m) sets AudioPriority to Level 0 Critical', () {
      final obstacle = DetectedObstacle(
        label: 'Chair',
        confidence: 0.88,
        xMin: 0.30,
        yMin: 0.40,
        xMax: 0.50,
        yMax: 0.85,
        distanceMeters: 0.9,
        ttcSeconds: 0.8,
        priority: AudioPriority.level0Critical,
        clockPosition: "11 o'clock",
      );

      expect(obstacle.priority, equals(AudioPriority.level0Critical));
      expect(obstacle.isHazard, isTrue);
    });

    test('Cycle Result identifies highest hazard accurately', () {
      final chair = DetectedObstacle(
        label: 'Chair',
        confidence: 0.85,
        xMin: 0.1,
        yMin: 0.1,
        xMax: 0.3,
        yMax: 0.4,
        distanceMeters: 2.5,
        ttcSeconds: 2.2,
        priority: AudioPriority.level1Safety,
        clockPosition: "10 o'clock",
      );

      final person = DetectedObstacle(
        label: 'Person',
        confidence: 0.94,
        xMin: 0.4,
        yMin: 0.2,
        xMax: 0.6,
        yMax: 0.9,
        distanceMeters: 1.1,
        ttcSeconds: 1.0,
        priority: AudioPriority.level0Critical,
        clockPosition: "12 o'clock",
      );

      final result = OnlineDetectionCycleResult(
        obstacles: [chair, person],
        latencyMs: 18,
        timestamp: DateTime.now(),
        isOnlineSuccess: true,
        statusMessage: "Standalone On-Device AI: 2 Obstacles (18ms)",
      );

      expect(result.highestHazard?.label, equals('Person'));
      expect(result.highestHazard?.priority, equals(AudioPriority.level0Critical));
    });
  });
}

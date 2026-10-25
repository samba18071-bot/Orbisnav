import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/services/multi_item_disambiguator.dart';
import 'package:orbisnav/services/online_obstacle_detector.dart';
import 'package:orbisnav/controllers/audio_mutex_controller.dart';

void main() {
  group('MultiItemDisambiguator Tests', () {
    test('Correctly pluralizes object labels', () {
      expect(MultiItemDisambiguator.pluralize('chair', 1), equals('chair'));
      expect(MultiItemDisambiguator.pluralize('chair', 2), equals('chairs'));
      expect(MultiItemDisambiguator.pluralize('person', 3), equals('people'));
      expect(MultiItemDisambiguator.pluralize('glass', 2), equals('glasses'));
      expect(MultiItemDisambiguator.pluralize('footwear', 2), equals('footwear'));
    });

    test('Disambiguates multiple items of the same type with index, role, and HUD badge', () {
      final chair1 = DetectedObstacle(
        label: 'Chair',
        confidence: 0.90,
        xMin: 0.1,
        yMin: 0.3,
        xMax: 0.35,
        yMax: 0.8,
        distanceMeters: 2.5,
        ttcSeconds: 4.0,
        priority: AudioPriority.level2Navigation,
        clockPosition: "10 o'clock",
      );

      final chair2 = DetectedObstacle(
        label: 'Chair',
        confidence: 0.95,
        xMin: 0.45,
        yMin: 0.3,
        xMax: 0.55,
        yMax: 0.8,
        distanceMeters: 1.1, // Closer!
        ttcSeconds: 2.0,
        priority: AudioPriority.level1Safety,
        clockPosition: "12 o'clock",
      );

      final chair3 = DetectedObstacle(
        label: 'Chair',
        confidence: 0.88,
        xMin: 0.7,
        yMin: 0.3,
        xMax: 0.9,
        yMax: 0.8,
        distanceMeters: 3.2,
        ttcSeconds: 5.0,
        priority: AudioPriority.level2Navigation,
        clockPosition: "2 o'clock",
      );

      final disambiguated = MultiItemDisambiguator.disambiguateObstacles([chair1, chair2, chair3]);

      expect(disambiguated.length, equals(3));
      // First sorted should be chair2 (1.1m)
      expect(disambiguated[0].obstacle.distanceMeters, equals(1.1));
      expect(disambiguated[0].index, equals(1));
      expect(disambiguated[0].spatialRole, equals('Nearest'));
      expect(disambiguated[0].hudBadge, equals('CHAIR #1 (NEAREST)'));

      // Second is chair1 (2.5m, xMin=0.1 -> Left)
      expect(disambiguated[1].obstacle.distanceMeters, equals(2.5));
      expect(disambiguated[1].index, equals(2));
      expect(disambiguated[1].spatialRole, equals('Left'));
      expect(disambiguated[1].hudBadge, equals('CHAIR #2 (LEFT)'));

      // Third is chair3 (3.2m, xMin=0.7 -> Right)
      expect(disambiguated[2].obstacle.distanceMeters, equals(3.2));
      expect(disambiguated[2].index, equals(3));
      expect(disambiguated[2].spatialRole, equals('Right'));
      expect(disambiguated[2].hudBadge, equals('CHAIR #3 (RIGHT)'));
    });

    test('Synthesizes non-repetitive aggregated speech for mixed obstacles', () {
      final chair1 = DetectedObstacle(
        label: 'Chair',
        confidence: 0.9,
        xMin: 0.4,
        yMin: 0.3,
        xMax: 0.6,
        yMax: 0.8,
        distanceMeters: 1.2,
        ttcSeconds: 3.0,
        priority: AudioPriority.level1Safety,
        clockPosition: "12 o'clock",
      );

      final chair2 = DetectedObstacle(
        label: 'Chair',
        confidence: 0.85,
        xMin: 0.7,
        yMin: 0.3,
        xMax: 0.9,
        yMax: 0.8,
        distanceMeters: 2.4,
        ttcSeconds: 5.0,
        priority: AudioPriority.level2Navigation,
        clockPosition: "2 o'clock",
      );

      final table = DetectedObstacle(
        label: 'Table',
        confidence: 0.91,
        xMin: 0.1,
        yMin: 0.4,
        xMax: 0.3,
        yMax: 0.8,
        distanceMeters: 1.8,
        ttcSeconds: 4.0,
        priority: AudioPriority.level2Navigation,
        clockPosition: "10 o'clock",
      );

      final speech = MultiItemDisambiguator.synthesizeAggregatedSpeech([chair1, chair2, table]);

      // Should indicate 3 objects, aggregate the 2 chairs, and mention the table without repetition
      expect(speech, startsWith('3 objects:'));
      expect(speech, contains('2 chairs'));
      expect(speech, contains('closest is at 12 o\'clock, 1.2 meters'));
      expect(speech, contains('Table at 10 o\'clock, 1.8 meters'));
    });

    test('Disambiguates voice queries for multiple items of same type', () {
      final bottle1 = DetectedObstacle(
        label: 'Bottle',
        confidence: 0.9,
        xMin: 0.4,
        yMin: 0.4,
        xMax: 0.5,
        yMax: 0.7,
        distanceMeters: 0.9,
        ttcSeconds: 2.0,
        priority: AudioPriority.level2Navigation,
        clockPosition: "12 o'clock",
      );
      final bottle2 = DetectedObstacle(
        label: 'Bottle',
        confidence: 0.88,
        xMin: 0.7,
        yMin: 0.4,
        xMax: 0.8,
        yMax: 0.7,
        distanceMeters: 2.1,
        ttcSeconds: 4.0,
        priority: AudioPriority.level2Navigation,
        clockPosition: "2 o'clock",
      );

      final answer = MultiItemDisambiguator.disambiguateVoiceQuery(
        targetCategory: 'bottle',
        matches: [bottle1, bottle2],
      );

      expect(answer, contains('Found 2 bottles'));
      expect(answer, contains('closest is at 12 o\'clock, 0.9 meters'));
      expect(answer, contains('Another is at 2 o\'clock, 2.1 meters'));
      expect(answer, contains('Guiding you to the closest one'));
    });
  });
}

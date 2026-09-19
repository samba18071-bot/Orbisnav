import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/services/spatial_debouncer.dart';

void main() {
  group('SpatialDebouncer Tests', () {
    late SpatialDebouncer debouncer;

    setUp(() {
      debouncer = SpatialDebouncer(
        cooldownDuration: const Duration(milliseconds: 100),
        criticalDistanceThreshold: 1.5,
      );
    });

    test('First alert in a clock zone should speak', () {
      final shouldSpeak = debouncer.shouldSpeak(
        label: 'Obstacle',
        clockZone: "12 o'clock",
        isCritical: false,
        distanceMeters: 2.5,
      );
      expect(shouldSpeak, isTrue);

      debouncer.recordSpoken(
        label: 'Obstacle',
        clockZone: "12 o'clock",
        distanceMeters: 2.5,
      );
    });

    test('Duplicate alert within cooldown window should be suppressed', () {
      debouncer.recordSpoken(
        label: 'Chair',
        clockZone: "1 o'clock",
        distanceMeters: 3.0,
      );

      final shouldSpeak = debouncer.shouldSpeak(
        label: 'Chair',
        clockZone: "1 o'clock",
        isCritical: false,
        distanceMeters: 2.9,
      );
      expect(shouldSpeak, isFalse, reason: 'Duplicate alert should be debounced within cooldown');
    });

    test('Alert in different clock zone should not be blocked', () {
      debouncer.recordSpoken(
        label: 'Chair',
        clockZone: "1 o'clock",
        distanceMeters: 3.0,
      );

      final shouldSpeakOtherZone = debouncer.shouldSpeak(
        label: 'Chair',
        clockZone: "11 o'clock",
        isCritical: false,
        distanceMeters: 3.0,
      );
      expect(shouldSpeakOtherZone, isTrue, reason: 'Different clock zone must be announced');
    });

    test('Critical hazard (<1.5m or isCritical: true) bypasses cooldown', () {
      debouncer.recordSpoken(
        label: 'Barrier',
        clockZone: "12 o'clock",
        distanceMeters: 3.0,
      );

      // Same object/zone, but distance drops to critical < 1.5m
      final shouldSpeakCritical = debouncer.shouldSpeak(
        label: 'Barrier',
        clockZone: "12 o'clock",
        isCritical: true,
        distanceMeters: 1.2,
      );
      expect(shouldSpeakCritical, isTrue, reason: 'Critical hazard must bypass debouncing');
    });

    test('Alert permitted after cooldown expires', () async {
      debouncer.recordSpoken(
        label: 'Pedestrian',
        clockZone: "2 o'clock",
        distanceMeters: 4.0,
      );

      expect(debouncer.shouldSpeak(
        label: 'Pedestrian',
        clockZone: "2 o'clock",
        distanceMeters: 4.0,
      ), isFalse);

      await Future.delayed(const Duration(milliseconds: 120));

      expect(debouncer.shouldSpeak(
        label: 'Pedestrian',
        clockZone: "2 o'clock",
        distanceMeters: 4.0,
      ), isTrue, reason: 'Alert should be permitted after cooldown duration');
    });

    test('clearZone resets debouncing for specific clock zone', () {
      debouncer.recordSpoken(
        label: 'Vehicle',
        clockZone: "12 o'clock",
        distanceMeters: 4.0,
      );

      debouncer.clearZone("12 o'clock");

      expect(debouncer.shouldSpeak(
        label: 'Vehicle',
        clockZone: "12 o'clock",
        distanceMeters: 4.0,
      ), isTrue);
    });
  });
}

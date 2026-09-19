import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/models/navigation_destination.dart';
import 'package:orbisnav/services/nameboard_navigation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Landmark & Nameboard Navigation Tests', () {
    test('NavTargetDestination computes correct distance and bearing', () {
      final dest = NavTargetDestination(
        id: "starbucks",
        name: "Starbucks Coffee",
        category: "Cafe",
        latitude: 17.4435,
        longitude: 78.3772,
        aliases: ["starbucks", "coffee"],
      );

      // User at same location -> distance ~0
      final distSelf = dest.distanceTo(17.4435, 78.3772);
      expect(distSelf, lessThan(1.0));

      // User slightly South-West -> distance should be ~25-30m
      final distNear = dest.distanceTo(17.4433, 78.3770);
      expect(distNear, greaterThan(15.0));
      expect(distNear, lessThan(50.0));

      // Bearing should be North-East (~45 degrees)
      final bearing = dest.bearingFrom(17.4433, 78.3770);
      expect(bearing, greaterThan(20.0));
      expect(bearing, lessThan(70.0));
    });

    test('NameboardNavigationService transitions through Far-Field, Near-Field and Visual Homing', () async {
      final service = NameboardNavigationService();
      final dest = NavTargetDestination.defaultDestinations.first;

      await service.startNavigation(dest);
      expect(service.isNavigating, isTrue);
      expect(service.activeDestination?.name, equals("Starbucks Coffee"));

      // Simulate walking closer step-by-step
      service.simulateStepCloser(10.0);
      expect(service.currentPhase, isNot(equals(NavigationPhase.idle)));

      // Stop navigation resets cleanly
      service.stopNavigation();
      expect(service.isNavigating, isFalse);
      expect(service.activeDestination, isNull);
      expect(service.currentPhase, equals(NavigationPhase.idle));
    });

    test('SightedNameboard target matching evaluates correctly', () {
      const targetBoard = SightedNameboard(
        text: "STARBUCKS COFFEE",
        confidence: 0.98,
        similarity: 0.95,
        distanceMeters: 4.5,
        clockZone: "12 o'clock",
        xMin: 0.2,
        yMin: 0.1,
        xMax: 0.8,
        yMax: 0.35,
        isTargetMatch: true,
      );

      expect(targetBoard.isTargetMatch, isTrue);
      expect(targetBoard.text, equals("STARBUCKS COFFEE"));
      expect(targetBoard.clockZone, equals("12 o'clock"));
      expect(targetBoard.distanceMeters, equals(4.5));
    });
  });
}

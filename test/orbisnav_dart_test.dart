import 'package:test/test.dart';
import '../lib/orbisnav_controller.dart';

void main() {
  group('OrbisNav Dart FFI Master Lifecycle Verification', () {
    late OrbisNavController controller;

    setUpAll(() {
      controller = OrbisNavController();
    });

    tearDownAll(() {
      controller.shutdown();
    });

    test('Phase 1: Cold Boot & Zero-Heap Memory Footprint', () {
      final success = controller.initialize();
      expect(success, isTrue);
      expect(controller.bootDurationMs, lessThan(500));
      expect(controller.isMemoryCompliant, isTrue);
      expect(controller.memoryUsedBytes, lessThanOrEqualTo(180 * 1024 * 1024));
    });

    test('Phase 2: Thermal Throttling Transitions', () {
      controller.setTemperature(37.0);
      expect(controller.thermalState, equals(ThermalState.nominal));
      expect(controller.targetFps, equals(30));

      controller.setTemperature(41.0);
      expect(controller.thermalState, equals(ThermalState.warm));
      expect(controller.targetFps, equals(20));

      controller.setTemperature(44.0);
      expect(controller.thermalState, equals(ThermalState.hot));
      expect(controller.targetFps, equals(15));

      controller.setTemperature(48.0);
      expect(controller.thermalState, equals(ThermalState.critical));
      expect(controller.targetFps, equals(10));

      controller.setTemperature(35.0);
    });

    test('Phase 3 & 5: Hazard Detection & Conversational Suspension/Auto-Resume', () {
      controller.startDialogue("Where is the auditorium?", "Proceed down corridor A.");
      expect(controller.isConversationSuspended, isFalse);

      // Ingest critical obstacle (<1.5m)
      controller.ingestDetection(
        xMin: 0.3,
        yMin: 0.1,
        xMax: 0.7,
        yMax: 0.95,
        confidence: 0.98,
        classId: 1, // Stairs
        timestampNs: 1000000000,
      );

      expect(controller.isHazardActive, isTrue);
      expect(controller.isConversationSuspended, isTrue);

      // Clear hazard
      controller.ingestDetection(
        xMin: 0.0,
        yMin: 0.0,
        xMax: 0.0,
        yMax: 0.0,
        confidence: 0.0,
        classId: 0,
        timestampNs: 1500000000,
      );

      // Less than 1.5s -> should remain suspended
      controller.updateConversationLifecycle(2000000000);
      expect(controller.isConversationSuspended, isTrue);

      // Path clear >= 1.5s -> auto-resumed!
      controller.updateConversationLifecycle(3200000000);
      expect(controller.isConversationSuspended, isFalse);
    });

    test('Phase 4: A* Pathfinding and Levenshtein Snap', () {
      controller.addMapNode(
        id: 10,
        name: "North Wing",
        x: 0.0,
        y: 0.0,
        plaqueLabel: "North Gate",
      );
      controller.addMapNode(
        id: 20,
        name: "Research Lab 1",
        x: 15.0,
        y: 0.0,
        plaqueLabel: "Lab 101",
      );
      controller.addMapEdge(10, 20, 15.0);

      final path = controller.computePath(10, 20);
      expect(path, equals([10, 20]));

      // Test fuzzy Levenshtein snap
      final snapped = controller.snapOcr("Lab 1O1"); // 'O' instead of '1'
      expect(snapped, isTrue);
    });

    test('Phase 6: Low Battery Override', () {
      controller.setBattery(12); // <= 15%
      expect(controller.targetFps, equals(10));
    });
  });
}

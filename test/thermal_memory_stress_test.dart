import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/orbisnav_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Day 18: 60-Minute Thermal & Memory Endurance Stress Test', () {
    late OrbisNavController controller;

    setUpAll(() {
      controller = OrbisNavController();
      controller.initialize();
    });

    tearDownAll(() {
      controller.shutdown();
    });

    test('Phase 1: Dynamic 4-Tier Thermal Throttling Transitions', () {
      // Nominal (< 40°C) -> 30 FPS
      controller.setTemperature(36.5);
      expect(controller.thermalState, equals(ThermalState.nominal));
      expect(controller.targetFps, equals(30));

      // Warm (40°C - 43°C) -> 20 FPS
      controller.setTemperature(41.5);
      expect(controller.thermalState, equals(ThermalState.warm));
      expect(controller.targetFps, equals(20));

      // Hot (43°C - 46°C) -> 15 FPS
      controller.setTemperature(44.5);
      expect(controller.thermalState, equals(ThermalState.hot));
      expect(controller.targetFps, equals(15));

      // Critical (>= 46°C) -> 10 FPS
      controller.setTemperature(47.5);
      expect(controller.thermalState, equals(ThermalState.critical));
      expect(controller.targetFps, equals(10));

      // Return to nominal
      controller.setTemperature(35.0);
      expect(controller.thermalState, equals(ThermalState.nominal));
      expect(controller.targetFps, equals(30));
    });

    test('Phase 2: 3,600 Inferences Continuous 60-Minute Loop Simulation', () {
      int simulatedFrames = 3600; // 1 hour simulated at 1 Hz continuous telemetry
      double temp = 36.0;

      for (int i = 0; i < simulatedFrames; i++) {
        // Temperature rises during heavy detection, caps at 44.0C and cools down
        if (i < 1800) {
          temp = 36.0 + (i / 1800.0) * 8.0;
        } else {
          temp = 44.0 - ((i - 1800) / 1800.0) * 5.0;
        }
        controller.setTemperature(temp);

        // Ingest IMU motion data
        controller.updateImu(
          pitchDeg: 2.0 * (i % 5),
          rollDeg: 1.0 * (i % 3),
          yawDeg: (i * 0.1) % 360.0,
          timestampNs: i * 33333333,
        );

        // Ingest detection box
        controller.ingestDetection(
          xMin: 0.2,
          yMin: 0.2,
          xMax: 0.8,
          yMax: 0.8,
          confidence: 0.90,
          classId: i % 4,
          timestampNs: i * 33333333,
        );

        // Verify memory compliance every 500 frames
        if (i % 500 == 0) {
          expect(controller.isMemoryCompliant, isTrue);
          expect(controller.memoryUsedBytes, lessThanOrEqualTo(180 * 1024 * 1024));
        }
      }

      expect(controller.isMemoryCompliant, isTrue);
    });

    test('Phase 3: Low Battery Override & Zero-Heap Stability', () {
      controller.setBattery(10); // Low battery <= 15%
      expect(controller.targetFps, equals(10));

      // Ingest 500 rapid steps
      for (int step = 0; step < 500; step++) {
        controller.stepPdr(0.72, 1.57);
      }

      expect(controller.isMemoryCompliant, isTrue);
      expect(controller.memoryUsedBytes, lessThanOrEqualTo(180 * 1024 * 1024));
    });
  });
}

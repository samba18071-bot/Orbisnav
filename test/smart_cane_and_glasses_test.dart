import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/controllers/audio_mutex_controller.dart';
import 'package:orbisnav/services/smart_cane_ble_service.dart';
import 'package:orbisnav/services/smart_glasses_bridge_service.dart';
import 'package:orbisnav/services/online_obstacle_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('10/10 Hardware Ecosystem: Smart Cane BLE & Smart Glasses Tests', () {
    late SmartWhiteCaneBleService caneService;
    late SmartGlassesBridgeService glassesService;

    setUp(() {
      caneService = SmartWhiteCaneBleService();
      glassesService = SmartGlassesBridgeService();
    });

    tearDown(() {
      caneService.dispose();
      glassesService.dispose();
    });

    test('Smart White Cane BLE connection and battery telemetry', () async {
      expect(caneService.currentState.connectionStatus, equals(CaneConnectionStatus.disconnected));

      caneService.connectToSmartCane('WeWALK Smart Cane Pro');
      expect(caneService.currentState.connectionStatus, equals(CaneConnectionStatus.scanning));

      await Future.delayed(const Duration(milliseconds: 350));
      expect(caneService.currentState.connectionStatus, equals(CaneConnectionStatus.connected));
      expect(caneService.currentState.deviceName, equals('WeWALK Smart Cane Pro'));
      expect(caneService.currentState.batteryLevelPercent, greaterThan(80));

      caneService.disconnect();
      expect(caneService.currentState.connectionStatus, equals(CaneConnectionStatus.disconnected));
    });

    test('Smart White Cane ultrasonic distance ingestion and ground sensor fusion', () async {
      caneService.connectToSmartCane();
      await Future.delayed(const Duration(milliseconds: 350));

      // 1. Ingest safe ground reading (2.5 meters)
      caneService.ingestUltrasonicReading(2.5);
      expect(caneService.currentState.hasGroundObstacle, isFalse);

      // 2. Ingest low ground obstacle (< 1.2 meters)
      caneService.ingestUltrasonicReading(0.8);
      expect(caneService.currentState.hasGroundObstacle, isTrue);

      // 3. Sensor Fusion: Camera obstacles + Smart Cane ground sensor
      final cameraObs = [
        DetectedObstacle(
          label: 'person',
          confidence: 0.92,
          distanceMeters: 3.0,
          xMin: 0.2,
          yMin: 0.2,
          xMax: 0.5,
          yMax: 0.8,
          ttcSeconds: 2.5,
          priority: AudioPriority.level3Context,
          clockPosition: "12 o'clock",
        ),
      ];

      final fused = caneService.fuseObstaclesWithCane(cameraObstacles: cameraObs);
      expect(fused.length, equals(2));
      expect(fused.any((o) => o.label == 'ground_obstacle_cane'), isTrue);
    });

    test('Smart White Cane handle touchpad gesture navigation', () async {
      final emittedGestures = <CaneTouchGesture>[];
      final sub = caneService.gestureStream.listen(emittedGestures.add);

      caneService.ingestCaneGesture(CaneTouchGesture.singleTap);
      caneService.ingestCaneGesture(CaneTouchGesture.swipeForward);
      caneService.ingestCaneGesture(CaneTouchGesture.longPressSos);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(emittedGestures, contains(CaneTouchGesture.singleTap));
      expect(emittedGestures, contains(CaneTouchGesture.swipeForward));
      expect(emittedGestures, contains(CaneTouchGesture.longPressSos));

      await sub.cancel();
    });

    test('Smart Glasses Eye-Wear connection and perspective calibration', () {
      expect(glassesService.currentState.isConnected, isFalse);
      expect(glassesService.activeMountMode, equals(CameraMountMode.handheld));

      glassesService.connectGlasses('Ray-Ban Meta Frame');
      expect(glassesService.currentState.isConnected, isTrue);
      expect(glassesService.currentState.modelName, equals('Ray-Ban Meta Frame'));
      expect(glassesService.activeMountMode, equals(CameraMountMode.smartGlasses));
      expect(glassesService.currentState.openEarAudioActive, isTrue);

      // Switch to chest lanyard
      glassesService.setMountMode(CameraMountMode.chestLanyard);
      expect(glassesService.activeMountMode, equals(CameraMountMode.chestLanyard));

      glassesService.disconnect();
      expect(glassesService.currentState.isConnected, isFalse);
      expect(glassesService.activeMountMode, equals(CameraMountMode.handheld));
    });

    test('Smart Glasses head-height overhead hazard detection (e.g. low branches/awnings)', () {
      glassesService.connectGlasses();

      final mixedObstacles = [
        // Low hanging branch at eye/head level (top half of frame yMin < 0.40, distance 1.5m)
        DetectedObstacle(
          label: 'branch',
          confidence: 0.88,
          distanceMeters: 1.5,
          xMin: 0.3,
          yMin: 0.1,
          xMax: 0.7,
          yMax: 0.35,
          ttcSeconds: 1.2,
          priority: AudioPriority.level1Safety,
          clockPosition: "12 o'clock",
        ),
        // Distant car at 10m
        DetectedObstacle(
          label: 'car',
          confidence: 0.95,
          distanceMeters: 10.0,
          xMin: 0.1,
          yMin: 0.5,
          xMax: 0.4,
          yMax: 0.9,
          ttcSeconds: 8.0,
          priority: AudioPriority.level3Context,
          clockPosition: "11 o'clock",
        ),
      ];

      final filtered = glassesService.filterHeadHeightHazards(mixedObstacles);
      expect(filtered.length, equals(2));
      final headHazard = filtered.firstWhere((o) => o.label.contains('HEAD_HAZARD'));
      expect(headHazard.isHazard, isTrue);
      expect(headHazard.label, equals('HEAD_HAZARD_BRANCH'));
    });

    test('Smart Glasses temple touch gestures handling', () async {
      final gestures = <GlassesTempleGesture>[];
      final sub = glassesService.gestureStream.listen(gestures.add);

      glassesService.ingestTempleGesture(GlassesTempleGesture.doubleTap);
      glassesService.ingestTempleGesture(GlassesTempleGesture.swipeForward);
      glassesService.ingestTempleGesture(GlassesTempleGesture.longPressAction);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(gestures, contains(GlassesTempleGesture.doubleTap));
      expect(gestures, contains(GlassesTempleGesture.swipeForward));
      expect(gestures, contains(GlassesTempleGesture.longPressAction));

      await sub.cancel();
    });
  });
}

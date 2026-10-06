import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/controllers/audio_mutex_controller.dart';
import 'package:orbisnav/services/online_obstacle_detector.dart';
import 'package:orbisnav/services/kinematic_motion_tracker.dart';
import 'package:orbisnav/services/document_framing_guide_service.dart';
import 'package:orbisnav/services/currency_recognition_service.dart';
import 'package:orbisnav/services/tactile_haptic_map_service.dart';
import 'package:orbisnav/services/smart_cane_ble_service.dart';
import 'package:orbisnav/services/smart_glasses_bridge_service.dart';
import 'package:orbisnav/services/global_standards_service.dart';
import 'package:orbisnav/services/transit_sentinel_service.dart';
import 'package:orbisnav/services/object_finder_sonar_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Blind & Visually Impaired Accessibility (A11y) Verification Suite', () {
    late AudioMutexController audioMutex;

    setUp(() {
      audioMutex = AudioMutexController();
    });

    tearDown(() {
      audioMutex.hardStop();
    });

    // -------------------------------------------------------------------------
    // Test 1: Priority-Based Audio Mutex & Immediate Hazard Preemption
    // -------------------------------------------------------------------------
    test('Audio Mutex Controller immediately preempts background speech when critical hazard strikes', () {
      // 1. Background scene description
      audioMutex.speak(
        text: "You are standing in a wide corridor with tiled floors.",
        priority: AudioPriority.level3Context,
        haptic: false,
      );
      expect(audioMutex.currentActivePriority, equals(AudioPriority.level3Context));

      // 2. Immediate Critical Hazard strikes (Level 0)
      audioMutex.speak(
        text: "Caution! A car is approaching you at 12 o'clock, 2.5 meters.",
        priority: AudioPriority.level0Critical,
        haptic: true,
        force: true,
      );

      // Level 0 must instantly preempt Level 3
      expect(audioMutex.currentActivePriority, equals(AudioPriority.level0Critical));
    });

    // -------------------------------------------------------------------------
    // Test 2: Kinematic Motion & Directional Clock Vocalization
    // -------------------------------------------------------------------------
    test('Spatial Clock & Motion Tracker provides intuitive voice guidance without visual feedback', () {
      final tracker = KinematicMotionTracker();
      tracker.reset();

      // Pedestrian walking towards user at 12 o'clock
      final obstacle = DetectedObstacle(
        label: 'Person',
        detailedDescription: 'A person is walking towards you',
        confidence: 0.94,
        xMin: 0.45,
        yMin: 0.20,
        xMax: 0.55,
        yMax: 0.85,
        distanceMeters: 2.1,
        ttcSeconds: 1.4,
        priority: AudioPriority.level0Critical,
        clockPosition: "12 o'clock",
        motionType: ObjectMotionType.approachingTowardsUser,
      );

      expect(obstacle.speechAnnouncement, equals("A person is walking towards you at 12 o'clock, 2.1 meters."));
      expect(obstacle.isHazard, isTrue);
      expect(obstacle.isMoving, isTrue);

      // Tree obstacle ahead
      final tree = DetectedObstacle(
        label: 'Tree',
        detailedDescription: 'A tree ahead',
        confidence: 0.97,
        xMin: 0.30,
        yMin: 0.10,
        xMax: 0.70,
        yMax: 0.90,
        distanceMeters: 3.2,
        ttcSeconds: 2.8,
        priority: AudioPriority.level1Safety,
        clockPosition: "12 o'clock",
      );

      expect(tree.speechAnnouncement, equals("A tree ahead at 12 o'clock, 3.2 meters."));
    });

    // -------------------------------------------------------------------------
    // Test 3: Document Framing Voice Guidance for Non-Sighted Reading
    // -------------------------------------------------------------------------
    test('Document Framing Guide provides real-time directional voice commands to align camera', () async {
      final framingService = DocumentFramingGuideService(audioMutex: audioMutex);

      // Document not detected
      final result1 = framingService.evaluateFrame(
        corners: null,
        phonePitchDeg: 0.0,
        phoneRollDeg: 0.0,
      );
      expect(result1.status, equals(FramingAlignmentStatus.noDocumentDetected));
      expect(result1.readyToCapture, isFalse);
      expect(result1.spokenGuidance, contains('Place document flat'));

      // Document in view - prompt user to hold still
      const goodCorners = DocumentCorners(
        topLeftX: 0.15,
        topLeftY: 0.15,
        topRightX: 0.85,
        topRightY: 0.15,
        bottomLeftX: 0.15,
        bottomLeftY: 0.85,
        bottomRightX: 0.85,
        bottomRightY: 0.85,
        coverageRatio: 0.60,
      );

      final result2 = framingService.evaluateFrame(
        corners: goodCorners,
        phonePitchDeg: 0.0,
        phoneRollDeg: 0.0,
      );
      expect(result2.status, equals(FramingAlignmentStatus.perfectHoldStill));
      expect(result2.spokenGuidance, contains('Perfect. Hold still'));

      // After 900ms hold (exceeding 800ms stable threshold), auto-capture triggers
      await Future.delayed(const Duration(milliseconds: 900));
      final result3 = framingService.evaluateFrame(
        corners: goodCorners,
        phonePitchDeg: 0.0,
        phoneRollDeg: 0.0,
      );
      expect(result3.status, equals(FramingAlignmentStatus.captured));
      expect(result3.readyToCapture, isTrue);

      framingService.dispose();
    });

    // -------------------------------------------------------------------------
    // Test 4: Offline Currency Recognition for Financial Autonomy
    // -------------------------------------------------------------------------
    test('Offline Currency Recognizer identifies banknotes with confidence scoring and tactile feedback', () async {
      final currencyService = CurrencyRecognitionService(audioMutex: audioMutex);
      currencyService.setCurrency(CurrencyCode.usd);

      final scanResult = await currencyService.processVisualTokens(
        detectedTexts: ['100', 'ONE', 'HUNDRED', 'DOLLARS', 'FEDERAL'],
        confidence: 0.95,
      );

      expect(scanResult.isIdentified, isTrue);
      expect(scanResult.denomination?.value, equals(100));
      expect(scanResult.denomination?.spokenText, contains('100 US Dollars'));

      currencyService.dispose();
    });

    // -------------------------------------------------------------------------
    // Test 5: Tactile Touchscreen Haptic Map for Zero-Sight Spatial Exploration
    // -------------------------------------------------------------------------
    test('Tactile Haptic Map converts touch screen exploration into distinct vibration cues', () {
      final tactileService = TactileHapticMapService(audioMutex: audioMutex);

      final sampleObstacles = [
        DetectedObstacle(
          label: 'door',
          confidence: 0.90,
          distanceMeters: 2.0,
          xMin: 0.4,
          yMin: 0.1,
          xMax: 0.6,
          yMax: 0.3,
          ttcSeconds: 2.0,
          priority: AudioPriority.level1Safety,
          clockPosition: "12 o'clock",
        ),
      ];

      tactileService.updateObstacleGrid(sampleObstacles);

      // Inspect clear corridor
      final clearPoint = tactileService.inspectScreenPoint(0.5, 0.8);
      expect(clearPoint.cellType, equals(TactileCellType.clearCorridor));
      expect(clearPoint.shouldVibrate, isFalse);

      // Inspect door obstacle
      final doorPoint = tactileService.inspectScreenPoint(0.5, 0.2);
      expect(doorPoint.cellType, equals(TactileCellType.doorwayOrGoal));
      expect(doorPoint.shouldVibrate, isTrue);

      tactileService.dispose();
    });

    // -------------------------------------------------------------------------
    // Test 6: Smart White Cane BLE & Ground Drop-off Sentinel
    // -------------------------------------------------------------------------
    test('Smart White Cane BLE service triggers ground obstacle alerts and touchpad gestures', () async {
      final caneService = SmartWhiteCaneBleService();

      caneService.connectToSmartCane('WeWALK Smart Cane Pro');
      await Future.delayed(const Duration(milliseconds: 350));

      // 1. Safe ground reading
      caneService.ingestUltrasonicReading(2.5);
      expect(caneService.currentState.hasGroundObstacle, isFalse);

      // 2. Drop-off / Low ground obstacle (< 1.2m)
      caneService.ingestUltrasonicReading(0.8);
      expect(caneService.currentState.hasGroundObstacle, isTrue);

      // 3. Touchpad swipe interaction
      final gestures = <CaneTouchGesture>[];
      final sub = caneService.gestureStream.listen(gestures.add);
      caneService.ingestCaneGesture(CaneTouchGesture.singleTap);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(gestures, contains(CaneTouchGesture.singleTap));

      await sub.cancel();
      caneService.dispose();
    });

    // -------------------------------------------------------------------------
    // Test 7: Smart Glasses Overhead Hazard Guard (Eye-level branches/awnings)
    // -------------------------------------------------------------------------
    test('Smart Glasses Bridge detects eye-level tree branches and overhead overhangs', () {
      final glassesService = SmartGlassesBridgeService();
      glassesService.connectGlasses();

      final mixedObstacles = [
        DetectedObstacle(
          label: 'tree branch',
          confidence: 0.91,
          distanceMeters: 1.4,
          xMin: 0.3,
          yMin: 0.1, // Head level
          xMax: 0.7,
          yMax: 0.35,
          ttcSeconds: 1.1,
          priority: AudioPriority.level1Safety,
          clockPosition: "12 o'clock",
        ),
      ];

      final filtered = glassesService.filterHeadHeightHazards(mixedObstacles);
      expect(filtered.length, equals(1));
      expect(filtered.first.label.toLowerCase(), contains('tree branch'));

      glassesService.dispose();
    });

    // -------------------------------------------------------------------------
    // Test 8: International Standards, Multi-Language & Emergency Dispatch
    // -------------------------------------------------------------------------
    test('Global Standards Service localizes units and maps universal emergency numbers', () {
      final standards = GlobalStandardsService();

      // Switch to Metric
      standards.setMeasurementSystem(MeasurementSystem.metric);
      expect(standards.formatDistance(2.5), equals("3 meters"));

      // Switch to Imperial
      standards.setMeasurementSystem(MeasurementSystem.imperial);
      expect(standards.formatDistance(2.5), equals("8 feet"));

      // Emergency dispatch mapping
      standards.setEmergencyCountry('US');
      expect(standards.emergencyProfile.emergencyNumber, equals('911'));

      standards.setEmergencyCountry('GB');
      expect(standards.emergencyProfile.emergencyNumber, equals('999'));

      standards.setEmergencyCountry('EU');
      expect(standards.emergencyProfile.emergencyNumber, equals('112'));
    });

    // -------------------------------------------------------------------------
    // Test 9: Public Transit Sentinel Platform Edge & Bus Approaching
    // -------------------------------------------------------------------------
    test('Transit Sentinel warns blind users of platform drop-offs and identifies oncoming buses', () {
      final transitService = TransitSentinelService(audioMutex: audioMutex);

      final alert = transitService.processBusHeadsign(
        ocrLines: ["METRO TRANSIT", "42 EXPRESS", "DOWNTOWN"],
        distanceMeters: 12.0,
        confidence: 0.95,
      );

      expect(alert.type, equals(TransitEventType.busApproaching));
      expect(alert.busRouteNumber, equals("42"));
      expect(alert.description, contains("Bus 42"));

      transitService.dispose();
    });

    // -------------------------------------------------------------------------
    // Test 10: Object Finder Spatial Sonar Audio Guidance
    // -------------------------------------------------------------------------
    test('Object Finder Sonar guides blind users toward tabletop objects using directional pan & ping', () {
      final finderService = ObjectFinderSonarService(audioMutex: audioMutex);
      finderService.startSearch("keys");

      final mockKeys = [
        DetectedObstacle(
          label: "keys",
          confidence: 0.92,
          xMin: 0.65,
          yMin: 0.40,
          xMax: 0.85,
          yMax: 0.60,
          distanceMeters: 1.2,
          ttcSeconds: 3.0,
          priority: AudioPriority.level2Navigation,
          clockPosition: "2 o'clock",
        ),
      ];

      final res = finderService.updateVisionCandidates(mockKeys);
      expect(res.isFound, isTrue);
      expect(res.clockPosition, equals("2 o'clock"));
      expect(res.stereoPan, greaterThan(0.0)); // Panned right to direct the user's hand
      expect(res.guidanceCue, contains("2 o'clock"));

      finderService.dispose();
    });
  });
}

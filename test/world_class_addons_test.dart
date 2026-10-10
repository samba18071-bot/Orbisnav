import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/controllers/audio_mutex_controller.dart';
import 'package:orbisnav/services/transit_sentinel_service.dart';
import 'package:orbisnav/services/object_finder_sonar_service.dart';
import 'package:orbisnav/services/tactile_haptic_map_service.dart';
import 'package:orbisnav/services/emergency_sos_sentinel_service.dart';
import 'package:orbisnav/services/wearable_wrist_haptic_service.dart';
import 'package:orbisnav/services/online_obstacle_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('World-Class Assistive Add-Ons Comprehensive Test Suite', () {
    late AudioMutexController audioMutex;
    late TransitSentinelService transitService;
    late ObjectFinderSonarService finderService;
    late TactileHapticMapService tactileService;
    late EmergencySosSentinelService emergencyService;
    late WearableWristHapticService wristService;

    setUp(() {
      audioMutex = AudioMutexController();
      transitService = TransitSentinelService(audioMutex: audioMutex);
      finderService = ObjectFinderSonarService(audioMutex: audioMutex);
      tactileService = TactileHapticMapService(audioMutex: audioMutex);
      emergencyService = EmergencySosSentinelService(audioMutex: audioMutex);
      wristService = WearableWristHapticService(audioMutex: audioMutex);
    });

    tearDown(() {
      transitService.dispose();
      finderService.dispose();
      tactileService.dispose();
      emergencyService.dispose();
      wristService.dispose();
      audioMutex.hardStop();
    });

    // -------------------------------------------------------------
    // Add-On 1: Public Transit Sentinel & Platform Edge Safety
    // -------------------------------------------------------------
    test('Transit Sentinel: Recognizes approaching bus number and destination', () {
      final ocrLines = [
        "METRO TRANSIT",
        "42 EXPRESS",
        "CIVIC CENTER DOWNTOWN",
      ];

      final alert = transitService.processBusHeadsign(
        ocrLines: ocrLines,
        distanceMeters: 14.5,
        confidence: 0.95,
      );

      expect(alert.type, equals(TransitEventType.busApproaching));
      expect(alert.busRouteNumber, equals("42"));
      expect(alert.description, contains("Bus 42"));
      expect(alert.distanceMeters, equals(14.5));
    });

    test('Transit Sentinel: Level 0 critical alert for subway platform edge drop-off', () {
      final alert = transitService.evaluatePlatformEdgeSafety(
        tactilePavingVisible: true,
        platformDropOffVisible: true,
        dropOffDistanceMeters: 1.1,
        trainPresent: false,
      );

      expect(alert.type, equals(TransitEventType.platformEdgeHazard));
      expect(alert.isEmergencyEdgeHazard, isTrue);
      expect(alert.description, contains("DANGER! Platform edge drop-off"));
    });

    test('Transit Sentinel: Tactile paving detection warning underfoot', () {
      final alert = transitService.evaluatePlatformEdgeSafety(
        tactilePavingVisible: true,
        platformDropOffVisible: false,
        dropOffDistanceMeters: 2.5,
        trainPresent: false,
      );

      expect(alert.type, equals(TransitEventType.tactilePavingDetected));
      expect(alert.isEmergencyEdgeHazard, isFalse);
      expect(alert.description, contains("Tactile warning paving detected"));
    });

    // -------------------------------------------------------------
    // Add-On 2: Personal Object Finder & Directional Audio Sonar
    // -------------------------------------------------------------
    test('Object Finder: Locates keys with stereo pan, ping interval and clock position', () {
      finderService.startSearch("keys");
      expect(finderService.isSearching, isTrue);

      final mockObstacles = [
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

      final res = finderService.updateVisionCandidates(mockObstacles);
      expect(res.isFound, isTrue);
      expect(res.clockPosition, equals("2 o'clock"));
      expect(res.stereoPan, greaterThan(0.0)); // panned to the right
      expect(res.sonarPingIntervalMs, lessThan(800)); // fast ping
      expect(res.guidanceCue, contains("2 o'clock"));
    });

    test('Object Finder: Reaching distance guidance (< 0.7m)', () {
      finderService.startSearch("water bottle");

      final closeBottle = [
        DetectedObstacle(
          label: "water bottle",
          confidence: 0.95,
          xMin: 0.45,
          yMin: 0.35,
          xMax: 0.55,
          yMax: 0.65,
          distanceMeters: 0.55,
          ttcSeconds: 2.0,
          priority: AudioPriority.level2Navigation,
          clockPosition: "12 o'clock",
        ),
      ];

      final res = finderService.updateVisionCandidates(closeBottle);
      expect(res.isFound, isTrue);
      expect(res.alignmentScore, greaterThan(0.7)); // well centered
      expect(res.distanceMeters, lessThan(0.7));
    });

    test('Object Finder: Matches everyday items via COCO proxies (keys -> remote, wallet -> handbag)', () {
      finderService.startSearch("keys");
      final proxyKeys = [
        DetectedObstacle(
          label: "remote",
          confidence: 0.88,
          xMin: 0.40,
          yMin: 0.35,
          xMax: 0.60,
          yMax: 0.65,
          distanceMeters: 0.9,
          ttcSeconds: 3.0,
          priority: AudioPriority.level2Navigation,
          clockPosition: "12 o'clock",
        ),
      ];
      final resKeys = finderService.updateVisionCandidates(proxyKeys);
      expect(resKeys.isFound, isTrue);

      finderService.startSearch("wallet");
      final proxyWallet = [
        DetectedObstacle(
          label: "handbag",
          confidence: 0.90,
          xMin: 0.20,
          yMin: 0.35,
          xMax: 0.40,
          yMax: 0.65,
          distanceMeters: 1.1,
          ttcSeconds: 3.0,
          priority: AudioPriority.level2Navigation,
          clockPosition: "10 o'clock",
        ),
      ];
      final resWallet = finderService.updateVisionCandidates(proxyWallet);
      expect(resWallet.isFound, isTrue);
    });

    // -------------------------------------------------------------
    // Add-On 3: Tactile Screen Map Explorer
    // -------------------------------------------------------------
    test('Tactile Map: Distinct haptic feedback for clear path, walls, and doorways', () {
      final obstacles = [
        DetectedObstacle(
          label: "Exit Door",
          confidence: 0.96,
          xMin: 0.40,
          yMin: 0.10,
          xMax: 0.60,
          yMax: 0.30,
          distanceMeters: 4.0,
          ttcSeconds: 5.0,
          priority: AudioPriority.level2Navigation,
          clockPosition: "12 o'clock",
        ),
        DetectedObstacle(
          label: "Descending Stairs",
          confidence: 0.94,
          xMin: 0.70,
          yMin: 0.50,
          xMax: 0.90,
          yMax: 0.80,
          distanceMeters: 1.8,
          ttcSeconds: 1.5,
          priority: AudioPriority.level0Critical,
          clockPosition: "2 o'clock",
        ),
      ];

      tactileService.updateObstacleGrid(obstacles);

      // 1. Touch clear floor (bottom center: 0.5, 0.8)
      final floorPoint = tactileService.inspectScreenPoint(0.5, 0.8);
      expect(floorPoint.cellType, equals(TactileCellType.clearCorridor));
      expect(floorPoint.shouldVibrate, isFalse);

      // 2. Touch Exit Door (0.5, 0.2)
      final doorPoint = tactileService.inspectScreenPoint(0.5, 0.2);
      expect(doorPoint.cellType, equals(TactileCellType.doorwayOrGoal));
      expect(doorPoint.shouldVibrate, isTrue);
      expect(doorPoint.hapticPatternMs, equals([100, 100]));

      // 3. Touch Descending Stairs (0.8, 0.6)
      final stairsPoint = tactileService.inspectScreenPoint(0.8, 0.6);
      expect(stairsPoint.cellType, equals(TactileCellType.hazardOrDropOff));
      expect(stairsPoint.shouldVibrate, isTrue);
      expect(stairsPoint.hapticPatternMs.length, equals(4)); // rapid alarm buzz

      // 4. Touch Wall Boundary on outer edge (0.02, 0.5)
      final wallPoint = tactileService.inspectScreenPoint(0.02, 0.5);
      expect(wallPoint.cellType, equals(TactileCellType.wallBoundary));
      expect(wallPoint.shouldVibrate, isTrue);
    });

    // -------------------------------------------------------------
    // Add-On 4: Emergency SOS & Fall Sentinel
    // -------------------------------------------------------------
    test('Emergency SOS: Detects severe fall impact (> 2.8G) and initiates countdown', () {
      expect(emergencyService.currentState.status, equals(FallDetectionStatus.monitoring));

      // Simulate heavy fall impact (x=0, y=0, z=18.0 m/s^2 -> ~3.3G)
      emergencyService.ingestAccelerometer(x: 0.0, y: 0.0, z: 18.0);

      expect(emergencyService.currentState.status, equals(FallDetectionStatus.fallDetectedCountdown));
      expect(emergencyService.currentState.countdownRemainingSeconds, equals(30));

      // User cancels emergency alert
      emergencyService.cancelEmergency();
      expect(emergencyService.currentState.status, equals(FallDetectionStatus.cancelledByUser));
    });

    // -------------------------------------------------------------
    // Add-On 5: Wearable Wrist Haptic & Chest Lanyard Companion
    // -------------------------------------------------------------
    test('Wearable Haptics: Clock directions generate distinct wrist patterns', () {
      // 12 o'clock -> Straight ahead (1 gentle pulse)
      final straight = wristService.dispatchWristCueForClockDirection(12);
      expect(straight.command, equals(WristHapticCommand.straightAhead));
      expect(straight.patternMs, equals([80]));

      // 10 o'clock -> Slight left (1 quick tap)
      final slightLeft = wristService.dispatchWristCueForClockDirection(10);
      expect(slightLeft.command, equals(WristHapticCommand.turnSlightLeft));
      expect(slightLeft.patternMs, equals([120]));

      // 2 o'clock -> Slight right (1 long tap)
      final slightRight = wristService.dispatchWristCueForClockDirection(2);
      expect(slightRight.command, equals(WristHapticCommand.turnSlightRight));
      expect(slightRight.patternMs, equals([250]));

      // Emergency STOP
      final stop = wristService.dispatchEmergencyStop();
      expect(stop.command, equals(WristHapticCommand.emergencyStopHazard));
      expect(stop.patternMs.length, greaterThanOrEqualTo(5));
    });

    test('Wearable Haptics: Chest lanyard calibration compensates camera pitch angle', () {
      expect(wristService.isChestLanyardModeEnabled, isFalse);

      wristService.setChestLanyardMode(true, currentPitchDeg: 25.0);
      expect(wristService.isChestLanyardModeEnabled, isTrue);
      expect(wristService.calibratedPitchOffsetDeg, equals(25.0));

      final correctedY = wristService.compensateYForLanyardTilt(0.70);
      expect(correctedY, lessThan(0.70)); // Adjusted upward to compensate for downward chest tilt
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/controllers/audio_mutex_controller.dart';
import 'package:orbisnav/services/pedestrian_navigation_service.dart';
import 'package:orbisnav/services/indoor_self_mapping_service.dart';
import 'package:orbisnav/services/spatial_binaural_earcon_service.dart';
import 'package:orbisnav/services/trusted_angels_call_service.dart';
import 'package:orbisnav/services/online_obstacle_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Days 11–17: Full Navigation, Wearables & Caregiver Call Test Suite', () {
    late AudioMutexController audioMutex;
    late PedestrianNavigationService pedNavService;
    late IndoorSelfMappingService indoorMapService;
    late SpatialBinauralEarconService earconService;
    late TrustedAngelsCallService angelsService;

    setUp(() {
      audioMutex = AudioMutexController();
      pedNavService = PedestrianNavigationService(audioMutex: audioMutex);
      indoorMapService = IndoorSelfMappingService(audioMutex: audioMutex);
      earconService = SpatialBinauralEarconService(audioMutex: audioMutex);
      angelsService = TrustedAngelsCallService(audioMutex: audioMutex);
    });

    tearDown(() {
      audioMutex.hardStop();
      pedNavService.dispose();
      indoorMapService.dispose();
      earconService.dispose();
      angelsService.dispose();
    });

    // -------------------------------------------------------------
    // Day 11 & 12: Pedestrian Navigation & Crosswalk Vision
    // -------------------------------------------------------------
    test('Day 11: Calculates remaining distance and advances pedestrian waypoints', () {
      final waypoints = [
        const PedestrianWaypoint(
          latitude: 37.7749,
          longitude: -122.4194,
          instruction: 'Proceed 20 meters straight ahead.',
          relativeClockDirection: 12,
          distanceMeters: 20.0,
        ),
        const PedestrianWaypoint(
          latitude: 37.7751,
          longitude: -122.4194,
          instruction: 'Turn 2 o\'clock onto the crosswalk.',
          relativeClockDirection: 2,
          distanceMeters: 15.0,
          isCrosswalk: true,
        ),
      ];

      pedNavService.startPedestrianRoute(
        destinationName: 'Metro Station',
        waypoints: waypoints,
      );

      expect(pedNavService.currentState.isNavigating, isTrue);
      expect(pedNavService.currentState.destinationName, equals('Metro Station'));
      expect(pedNavService.currentState.remainingDistanceMeters, equals(35.0));
      expect(pedNavService.currentState.clockDirection, equals(12));

      // Simulate walking to first waypoint (<8m)
      pedNavService.updateUserLocation(
        userLat: 37.774902,
        userLng: -122.419401,
        compassHeadingDeg: 0.0,
      );

      // Advances to second waypoint
      expect(pedNavService.currentState.currentTurnInstruction, contains("2 o'clock"));
      expect(pedNavService.currentState.clockDirection, equals(2));
    });

    test('Day 12: Detects zebra crosswalk and Walk / Don\'t Walk signals', () {
      // 1. Walk Signal
      pedNavService.processCrosswalkVision(
        zebraCrossingDetected: true,
        distanceMeters: 3.5,
        lightState: TrafficLightState.walkSignal,
      );

      expect(pedNavService.currentState.crosswalkStatus.crosswalkDetected, isTrue);
      expect(pedNavService.currentState.crosswalkStatus.lightState, equals(TrafficLightState.walkSignal));
      expect(pedNavService.currentState.crosswalkStatus.spokenAlert, contains('Safe to cross'));

      // 2. Don't Walk Signal
      pedNavService.processCrosswalkVision(
        zebraCrossingDetected: true,
        distanceMeters: 2.0,
        lightState: TrafficLightState.dontWalkSignal,
      );

      expect(pedNavService.currentState.crosswalkStatus.lightState, equals(TrafficLightState.dontWalkSignal));
      expect(pedNavService.currentState.crosswalkStatus.spokenAlert, contains('Stop. Don\'t Walk'));
    });

    // -------------------------------------------------------------
    // Day 13 & 14: Indoor A* PDR & Levenshtein OCR Landmark Snapping
    // -------------------------------------------------------------
    test('Day 13 & 14: Accumulates PDR step drift and resets drift on OCR plaque snap', () {
      final sampleMap = IndoorVenueMap(
        venueName: 'Engineering Building',
        createdAt: DateTime.now(),
        nodes: const [
          IndoorNode(id: 'n0', name: 'Entrance', xMeters: 0.0, yMeters: 0.0, ocrPlaqueText: 'Main Entrance'),
          IndoorNode(id: 'n1', name: 'Room 204', xMeters: 0.0, yMeters: 10.0, ocrPlaqueText: 'Room 204'),
        ],
      );

      indoorMapService.loadVenueMap(sampleMap);
      indoorMapService.startIndoorRouteToNode('n1');

      // Simulate 10 steps (accumulating drift)
      for (int i = 0; i < 10; i++) {
        indoorMapService.onPdrStep(stepLengthMeters: 0.75, headingDeg: 0.0);
      }

      expect(indoorMapService.currentState.currentY, greaterThan(7.0));
      expect(indoorMapService.currentState.accumulatedDriftMeters, greaterThan(0.5));

      // OCR camera reads fuzzy plaque "Room 2O4" (O instead of 0)
      final snapped = indoorMapService.attemptOcrLandmarkSnap('Room 2O4');

      expect(snapped, isTrue);
      expect(indoorMapService.currentState.accumulatedDriftMeters, equals(0.0)); // Drift eliminated!
      expect(indoorMapService.currentState.currentY, equals(10.0)); // Position locked to ground truth node!
      expect(indoorMapService.currentState.lastSnappedLandmark, equals('Room 204'));
    });

    // -------------------------------------------------------------
    // Day 15: "Record & Walk" Self-Mapping Mode
    // -------------------------------------------------------------
    test('Day 15: Records landmark nodes and exports self-mapped JSON map', () {
      indoorMapService.startRecordingMap('City Library');
      expect(indoorMapService.currentState.isRecordingMap, isTrue);

      // Walk 5 steps and record Room 101
      indoorMapService.onPdrStep(stepLengthMeters: 1.0, headingDeg: 0.0);
      indoorMapService.addLandmarkPlaqueDuringRecording(
        plaqueName: 'Circulation Desk',
        detectedOcrText: 'Circulation Desk & Checkout',
      );

      final exported = indoorMapService.stopRecordingAndExportMap();

      expect(exported.venueName, equals('City Library'));
      expect(exported.nodes.length, equals(2));
      expect(exported.nodes[1].name, equals('Circulation Desk'));

      final jsonStr = exported.toJsonString();
      final loaded = IndoorVenueMap.fromJsonString(jsonStr);
      expect(loaded.venueName, equals('City Library'));
      expect(loaded.nodes.length, equals(2));
    });

    // -------------------------------------------------------------
    // Day 16: 3D Binaural Spatial Earcons & 3-Zone Hazard Classification
    // -------------------------------------------------------------
    test('Day 16: Dispatches High-Pitch Head Earcon and Low-Pitch Drop-Off Earcon', () {
      // 1. Head-Level Hazard (e.g. Tree Branch)
      final headObs = DetectedObstacle(
        label: 'Tree Branch',
        confidence: 0.94,
        xMin: 0.1,
        yMin: 0.1,
        xMax: 0.4,
        yMax: 0.4,
        distanceMeters: 1.6,
        ttcSeconds: 1.4,
        priority: AudioPriority.level0Critical,
        clockPosition: "10 o'clock",
      );

      final headCue = earconService.dispatchSpatialEarcon(
        obstacle: headObs,
        estimatedElevationMeters: 1.8, // Head level
      );

      expect(headCue.zone, equals(HazardElevationZone.headLevel));
      expect(headCue.pitchMultiplier, equals(1.8));
      expect(headCue.panStereo, lessThan(0.0)); // Panned left

      // 2. Drop-Off Hazard (e.g. Downward Stairs)
      final dropObs = DetectedObstacle(
        label: 'Stairs',
        confidence: 0.92,
        xMin: 0.6,
        yMin: 0.7,
        xMax: 0.9,
        yMax: 0.95,
        distanceMeters: 1.2,
        ttcSeconds: 1.0,
        priority: AudioPriority.level0Critical,
        clockPosition: "2 o'clock",
      );

      final dropCue = earconService.dispatchSpatialEarcon(
        obstacle: dropObs,
        estimatedElevationMeters: 0.2, // Drop-off level
      );

      expect(dropCue.zone, equals(HazardElevationZone.dropOff));
      expect(dropCue.pitchMultiplier, equals(0.6));
      expect(dropCue.panStereo, greaterThan(0.0)); // Panned right
    });

    // -------------------------------------------------------------
    // Day 17: "Trusted Angels" 1-Tap Caregiver Video Call
    // -------------------------------------------------------------
    test('Day 17: Connects 1-Tap caregiver call and tracks session state', () async {
      expect(angelsService.contacts.length, greaterThanOrEqualTo(2));

      await angelsService.startCall();

      expect(angelsService.currentSession.status, equals(TrustedAngelCallStatus.connected));
      expect(angelsService.currentSession.activeContact?.name, contains('Sarah'));

      angelsService.endCall();
      expect(angelsService.currentSession.status, equals(TrustedAngelCallStatus.idle));
    });
  });
}

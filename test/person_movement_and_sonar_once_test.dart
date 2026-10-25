import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/controllers/audio_mutex_controller.dart';
import 'package:orbisnav/services/object_finder_sonar_service.dart';
import 'package:orbisnav/services/online_obstacle_detector.dart';
import 'package:orbisnav/services/kinematic_motion_tracker.dart';

class MockAudioMutexController implements AudioMutexController {
  final List<String> spokenTexts = [];

  @override
  Future<bool> speak({
    required String text,
    required AudioPriority priority,
    int? channelIndex,
    bool haptic = true,
    bool force = false,
  }) async {
    spokenTexts.add(text);
    return true;
  }

  @override
  int get activeChannelIndex => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Person Movement in Safety HUD & Channel 4 Speak Once Tests', () {
    test('Channel 4 speaks object found ONLY ONCE instead of repeating', () {
      final mockAudio = MockAudioMutexController();
      final sonar = ObjectFinderSonarService(audioMutex: mockAudio);

      sonar.startSearch("bag");
      mockAudio.spokenTexts.clear();

      final bagObstacle = [
        DetectedObstacle(
          label: "bag",
          confidence: 0.92,
          xMin: 0.45,
          yMin: 0.30,
          xMax: 0.65,
          yMax: 0.70,
          distanceMeters: 0.7,
          ttcSeconds: 3.0,
          priority: AudioPriority.level1Safety,
          clockPosition: "12 o'clock",
        ),
      ];

      // Frame 1: Object found
      sonar.updateVisionCandidates(bagObstacle);
      expect(mockAudio.spokenTexts.length, equals(1));
      expect(mockAudio.spokenTexts.first, contains("Bag found!"));

      // Frame 2: Object still in view
      sonar.updateVisionCandidates(bagObstacle);
      expect(mockAudio.spokenTexts.length, equals(1), reason: "Must NOT repeat announcement while object is continuously tracked");

      // Frame 3: Object still in view
      sonar.updateVisionCandidates(bagObstacle);
      expect(mockAudio.spokenTexts.length, equals(1), reason: "Still exactly 1 announcement");
    });

    test('Safety HUD person movement descriptions accurately convey dynamic and stationary movements', () {
      // Test Person walking towards user
      final approachingPerson = DetectedObstacle(
        label: "person",
        confidence: 0.90,
        xMin: 0.40,
        yMin: 0.20,
        xMax: 0.60,
        yMax: 0.80,
        distanceMeters: 1.8,
        ttcSeconds: 1.5,
        priority: AudioPriority.level0Critical,
        clockPosition: "12 o'clock",
        motionType: ObjectMotionType.approachingTowardsUser,
        detailedDescription: "A person is walking towards you",
      );

      expect(approachingPerson.speechAnnouncement, contains("A person is walking towards you at 12 o'clock, 1.8 meters."));
      expect(approachingPerson.formattedMotionBadge, contains("APPROACHING"));

      // Test Person walking to right
      final crossingRightPerson = DetectedObstacle(
        label: "person",
        confidence: 0.88,
        xMin: 0.50,
        yMin: 0.20,
        xMax: 0.70,
        yMax: 0.80,
        distanceMeters: 2.2,
        ttcSeconds: 2.5,
        priority: AudioPriority.level1Safety,
        clockPosition: "1 o'clock",
        motionType: ObjectMotionType.crossingLeftToRight,
        detailedDescription: "A person is walking to your right",
      );

      expect(crossingRightPerson.speechAnnouncement, contains("A person is walking to your right at 1 o'clock, 2.2 meters."));
      expect(crossingRightPerson.formattedMotionBadge, contains("CROSSING (L→R)"));

      // Test Person walking to left
      final crossingLeftPerson = DetectedObstacle(
        label: "person",
        confidence: 0.88,
        xMin: 0.20,
        yMin: 0.20,
        xMax: 0.40,
        yMax: 0.80,
        distanceMeters: 2.0,
        ttcSeconds: 2.5,
        priority: AudioPriority.level1Safety,
        clockPosition: "11 o'clock",
        motionType: ObjectMotionType.crossingRightToLeft,
        detailedDescription: "A person is walking to your left",
      );

      expect(crossingLeftPerson.speechAnnouncement, contains("A person is walking to your left at 11 o'clock, 2.0 meters."));
      expect(crossingLeftPerson.formattedMotionBadge, contains("CROSSING (R→L)"));

      // Test Person standing / stationary
      final standingPerson = DetectedObstacle(
        label: "person",
        confidence: 0.89,
        xMin: 0.45,
        yMin: 0.20,
        xMax: 0.55,
        yMax: 0.80,
        distanceMeters: 1.5,
        ttcSeconds: 4.0,
        priority: AudioPriority.level1Safety,
        clockPosition: "12 o'clock",
        motionType: ObjectMotionType.stationaryAhead,
        detailedDescription: "A person standing",
      );

      expect(standingPerson.speechAnnouncement, contains("A person standing at 12 o'clock, 1.5 meters."));
      expect(standingPerson.formattedMotionBadge, contains("STATIONARY"));
    });
  });
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/controllers/audio_mutex_controller.dart';
import 'package:orbisnav/services/on_device_obstacle_detector.dart';
import 'package:orbisnav/services/online_obstacle_detector.dart';
import 'package:orbisnav/services/spatial_binaural_earcon_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AI Scene Explanation Exclusivity & Continuous Detection Tests', () {
    late AudioMutexController audioMutex;
    late SpatialBinauralEarconService earconService;
    late OnDeviceObstacleDetector detector;

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.orbisnav.orbisnav/audio_mutex'),
        (MethodCall methodCall) async {
          if (methodCall.method == 'speak') return true;
          if (methodCall.method == 'stop') return true;
          return null;
        },
      );
      audioMutex = AudioMutexController();
      earconService = SpatialBinauralEarconService(audioMutex: audioMutex);
      detector = OnDeviceObstacleDetector();
    });

    tearDown(() {
      audioMutex.setSceneExplanationExclusive(false);
      audioMutex.hardStop();
    });

    test('Exclusive scene explanation mode suppresses all other speech', () async {
      audioMutex.setSceneExplanationExclusive(true);
      expect(audioMutex.isSceneExplanationExclusive, isTrue);

      // Attempt Level 0 critical obstacle speech while scene explanation is active
      final spokeCritical = await audioMutex.speak(
        text: 'Caution! Chair at 12 o\'clock, 1.0 meters.',
        priority: AudioPriority.level0Critical,
        force: true,
      );
      expect(spokeCritical, isFalse, reason: 'Level 0 speech must be suppressed during scene explanation');

      // Attempt Level 1 safety speech
      final spokeSafety = await audioMutex.speak(
        text: 'Person moving towards you at 1 o\'clock.',
        priority: AudioPriority.level1Safety,
        force: true,
      );
      expect(spokeSafety, isFalse, reason: 'Level 1 speech must be suppressed during scene explanation');

      // Attempt Level 2 navigation speech
      final spokeNav = await audioMutex.speak(
        text: 'Path clear. Continuing forward.',
        priority: AudioPriority.level2Navigation,
        force: true,
      );
      expect(spokeNav, isFalse, reason: 'Level 2 speech must be suppressed during scene explanation');

      // Release exclusivity
      audioMutex.setSceneExplanationExclusive(false);
      expect(audioMutex.isSceneExplanationExclusive, isFalse);

      // Normal speech should now succeed
      final spokeNormal = await audioMutex.speak(
        text: 'Path clear.',
        priority: AudioPriority.level2Navigation,
        force: true,
      );
      expect(spokeNormal, isTrue);
    });

    test('Spatial Earcons are muted when exclusive scene explanation is active', () {
      audioMutex.setSceneExplanationExclusive(true);

      final obstacle = DetectedObstacle(
        label: 'Low Tree Branch',
        confidence: 0.92,
        xMin: 0.4,
        yMin: 0.1,
        xMax: 0.6,
        yMax: 0.5,
        distanceMeters: 1.4,
        ttcSeconds: 1.0,
        priority: AudioPriority.level0Critical,
        clockPosition: "12 o'clock",
      );

      final cue = earconService.dispatchSpatialEarcon(
        obstacle: obstacle,
        estimatedElevationMeters: 1.8,
      );

      // Must return silent pulseCount 0 cue
      expect(cue.pulseCount, equals(0), reason: 'Earcon must be muted during scene explanation');

      audioMutex.setSceneExplanationExclusive(false);
      final activeCue = earconService.dispatchSpatialEarcon(
        obstacle: obstacle,
        estimatedElevationMeters: 1.8,
      );
      expect(activeCue.pulseCount, greaterThan(0));
    });

    test('Detection stays enabled and functional during scene explanation', () {
      expect(detector.isEnabled, isTrue);

      audioMutex.setSceneExplanationExclusive(true);
      // Ensure detector is NOT disabled
      expect(detector.isEnabled, isTrue, reason: 'Detector must keep working as long as app is open');

      audioMutex.setSceneExplanationExclusive(false);
      expect(detector.isEnabled, isTrue);
    });
  });
}

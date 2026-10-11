import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:orbisnav/controllers/audio_mutex_controller.dart';
import 'package:orbisnav/services/color_and_light_perception_service.dart';
import 'package:orbisnav/services/object_finder_sonar_service.dart';
import 'package:orbisnav/services/online_obstacle_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Microsoft Seeing AI Perception Engine Tests', () {
    late ColorAndLightPerceptionService perceptionService;

    setUp(() {
      perceptionService = ColorAndLightPerceptionService();
    });

    Uint8List createSolidImageBytes(int r, int g, int b, {int width = 64, int height = 64}) {
      final image = img.Image(width: width, height: height);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          image.setPixelRgba(x, y, r, g, b, 255);
        }
      }
      return Uint8List.fromList(img.encodePng(image));
    }

    test('Estimates Primary Colors Accurately (Red, Green, Blue)', () {
      final redBytes = createSolidImageBytes(230, 20, 20);
      expect(perceptionService.estimateDominantColor(redBytes), equals('Red'));

      final greenBytes = createSolidImageBytes(20, 220, 20);
      expect(perceptionService.estimateDominantColor(greenBytes), equals('Green'));

      final blueBytes = createSolidImageBytes(20, 20, 230);
      expect(perceptionService.estimateDominantColor(blueBytes), equals('Blue'));
    });

    test('Estimates Extreme Luminance (Black, White, Gray)', () {
      final blackBytes = createSolidImageBytes(10, 10, 10);
      expect(perceptionService.estimateDominantColor(blackBytes), equals('Black'));

      final whiteBytes = createSolidImageBytes(245, 245, 245);
      expect(perceptionService.estimateDominantColor(whiteBytes), equals('White'));

      final grayBytes = createSolidImageBytes(120, 120, 120);
      expect(perceptionService.estimateDominantColor(grayBytes), equals('Gray'));
    });

    test('Estimates Light Level Percentage & Natural Description', () {
      final darkBytes = createSolidImageBytes(30, 30, 30);
      final darkLevel = perceptionService.estimateLightLevel(darkBytes);
      expect(darkLevel, lessThan(25));
      expect(perceptionService.getLightDescription(darkLevel), contains('Dark'));

      final brightBytes = createSolidImageBytes(240, 240, 240);
      final brightLevel = perceptionService.estimateLightLevel(brightBytes);
      expect(brightLevel, greaterThan(80));
      expect(perceptionService.getLightDescription(brightLevel), contains('Very bright'));

      final normalBytes = createSolidImageBytes(140, 140, 140);
      final normalLevel = perceptionService.estimateLightLevel(normalBytes);
      expect(normalLevel, inInclusiveRange(25, 80));
      expect(perceptionService.getLightDescription(normalLevel), contains('Good indoor illumination'));
    });

    test('Combines Color and Light in single pass analysis', () {
      final bytes = createSolidImageBytes(220, 200, 20);
      final result = perceptionService.analyzeColorAndLight(bytes);
      expect(result.dominantColor, equals('Yellow'));
      expect(result.lightLevelPercent, greaterThan(50));
      expect(result.lightDescription, isNotEmpty);
    });
  });

  group('Channel 4: Lost Item Sonar Dynamic Radar Tests', () {
    late AudioMutexController audioMutex;
    late ObjectFinderSonarService sonarService;

    setUp(() {
      audioMutex = AudioMutexController();
      sonarService = ObjectFinderSonarService(audioMutex: audioMutex);
    });

    tearDown(() {
      sonarService.dispose();
      audioMutex.hardStop();
    });

    test('Accelerates Sonar Ping interval as user gets closer to target item', () {
      sonarService.startSearch("keys");

      // Far obstacle (2.5m away)
      final farObstacle = [
        DetectedObstacle(
          label: "keys",
          confidence: 0.90,
          xMin: 0.45,
          yMin: 0.35,
          xMax: 0.55,
          yMax: 0.65,
          distanceMeters: 2.5,
          ttcSeconds: 6.0,
          priority: AudioPriority.level2Navigation,
          clockPosition: "12 o'clock",
        ),
      ];
      final farState = sonarService.updateVisionCandidates(farObstacle);

      // Close obstacle (0.4m away)
      final closeObstacle = [
        DetectedObstacle(
          label: "keys",
          confidence: 0.95,
          xMin: 0.45,
          yMin: 0.35,
          xMax: 0.55,
          yMax: 0.65,
          distanceMeters: 0.4,
          ttcSeconds: 1.0,
          priority: AudioPriority.level2Navigation,
          clockPosition: "12 o'clock",
        ),
      ];
      final closeState = sonarService.updateVisionCandidates(closeObstacle);

      expect(closeState.sonarPingIntervalMs, lessThan(farState.sonarPingIntervalMs));
      expect(closeState.isFound, isTrue);
      expect(closeState.alignmentScore, greaterThan(0.8));
    });

    test('Calculates stereo panning left and right based on frame x-coordinate', () {
      sonarService.startSearch("wallet");

      // Item on the left side of frame (xMin: 0.05, xMax: 0.25)
      final leftObstacle = [
        DetectedObstacle(
          label: "wallet",
          confidence: 0.88,
          xMin: 0.05,
          yMin: 0.30,
          xMax: 0.25,
          yMax: 0.50,
          distanceMeters: 1.5,
          ttcSeconds: 4.0,
          priority: AudioPriority.level2Navigation,
          clockPosition: "10 o'clock",
        ),
      ];
      final leftState = sonarService.updateVisionCandidates(leftObstacle);
      expect(leftState.stereoPan, lessThan(-0.3));
      expect(leftState.guidanceCue, contains("To your left"));

      // Item on the right side of frame (xMin: 0.75, xMax: 0.95)
      final rightObstacle = [
        DetectedObstacle(
          label: "wallet",
          confidence: 0.88,
          xMin: 0.75,
          yMin: 0.30,
          xMax: 0.95,
          yMax: 0.50,
          distanceMeters: 1.5,
          ttcSeconds: 4.0,
          priority: AudioPriority.level2Navigation,
          clockPosition: "2 o'clock",
        ),
      ];
      final rightState = sonarService.updateVisionCandidates(rightObstacle);
      expect(rightState.stereoPan, greaterThan(0.3));
      expect(rightState.guidanceCue, contains("To your right"));
    });
  });
}

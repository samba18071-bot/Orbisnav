import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/controllers/audio_mutex_controller.dart';
import 'package:orbisnav/services/cloud_ai_vision_service.dart';
import 'package:orbisnav/services/online_obstacle_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AI Scene Analyzer Real-Time Situation Explanation Tests', () {
    late CloudAIVisionService sceneAnalyzer;

    setUp(() {
      sceneAnalyzer = CloudAIVisionService();
    });

    test('Explains clear open pathway situation when no obstacles detected', () async {
      final dummyBytes = Uint8List(10);
      final result = await sceneAnalyzer.analyzeScene(
        dummyBytes,
        currentObstacles: [],
        devicePitchDeg: 0.0,
        speakResult: false,
        force: true,
      );

      expect(result.isSuccess, isTrue);
      expect(result.pathwayStatus, contains("Clear Path Ahead"));
      expect(result.sceneSummary, contains("clear of obstacles"));
      expect(result.recommendedAction, contains("Continue forward"));
    });

    test('Explains obstructed pathway and recommends bypass direction', () async {
      final dummyBytes = Uint8List(10);
      final obstacles = [
        DetectedObstacle(
          label: 'Chair',
          confidence: 0.90,
          xMin: 0.45,
          yMin: 0.40,
          xMax: 0.55,
          yMax: 0.85,
          distanceMeters: 1.2,
          ttcSeconds: 1.0,
          priority: AudioPriority.level0Critical,
          clockPosition: "12 o'clock",
        ),
      ];

      final result = await sceneAnalyzer.analyzeScene(
        dummyBytes,
        currentObstacles: obstacles,
        devicePitchDeg: 0.0,
        speakResult: false,
        force: true,
      );

      expect(result.isSuccess, isTrue);
      expect(result.pathwayStatus, equals("Path Obstructed"));
      expect(result.sceneSummary, contains("Chair directly ahead at 1.2 meters"));
      expect(result.recommendedAction, contains("Step slightly"));
    });

    test('Infers workstation environment when laptop, mouse, and table are present', () async {
      final dummyBytes = Uint8List(10);
      final obstacles = [
        DetectedObstacle(
          label: 'Laptop',
          confidence: 0.95,
          xMin: 0.40,
          yMin: 0.50,
          xMax: 0.60,
          yMax: 0.75,
          distanceMeters: 0.6,
          ttcSeconds: 0.5,
          priority: AudioPriority.level2Navigation,
          clockPosition: "12 o'clock",
        ),
        DetectedObstacle(
          label: 'Bottle',
          confidence: 0.88,
          xMin: 0.70,
          yMin: 0.50,
          xMax: 0.80,
          yMax: 0.70,
          distanceMeters: 0.7,
          ttcSeconds: 0.6,
          priority: AudioPriority.level3Context,
          clockPosition: "2 o'clock",
        ),
      ];

      final result = await sceneAnalyzer.analyzeScene(
        dummyBytes,
        currentObstacles: obstacles,
        devicePitchDeg: 0.0,
        speakResult: false,
        force: true,
      );

      expect(result.environmentType, equals("Workstation / Office Desk"));
      expect(result.sceneSummary, contains("On your right at 2 o'clock: Bottle"));
    });
  });
}

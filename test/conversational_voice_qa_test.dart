import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/services/conversational_voice_qa_service.dart';
import 'package:orbisnav/services/online_obstacle_detector.dart';
import 'package:orbisnav/controllers/audio_mutex_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Day 6 & 7: Conversational Voice Q&A Assistant Tests', () {
    late ConversationalVoiceQAService qaService;
    late AudioMutexController audioMutex;

    setUp(() {
      audioMutex = AudioMutexController();
      qaService = ConversationalVoiceQAService.internal(audioMutex: audioMutex);
    });

    test('Synthesizes clear path answer when no obstacles are visible', () async {
      final exchange = await qaService.askQuestion(
        question: 'What is in front of me?',
        activeObstacles: [],
        phonePitchDeg: 0.0,
      );

      expect(exchange.question, equals('What is in front of me?'));
      expect(exchange.answer, contains('open and clear'));
      expect(exchange.isFromCloud, isFalse);
    });

    test('Identifies chairs and seats with distance and clock direction', () async {
      final sampleObstacles = [
        DetectedObstacle(
          label: 'Chair',
          confidence: 0.92,
          xMin: 0.6,
          yMin: 0.4,
          xMax: 0.8,
          yMax: 0.8,
          distanceMeters: 1.8,
          ttcSeconds: 3.5,
          priority: AudioPriority.level2Navigation,
          clockPosition: "2 o'clock",
        ),
      ];

      final exchange = await qaService.askQuestion(
        question: 'Is there an empty seat or chair near me?',
        activeObstacles: sampleObstacles,
        phonePitchDeg: 0.0,
      );

      expect(exchange.answer, contains('Chair'));
      expect(exchange.answer, contains('1.8 meters'));
      expect(exchange.answer, contains("2 o'clock"));
    });

    test('Identifies people count and closest person position', () async {
      final samplePeople = [
        DetectedObstacle(
          label: 'Person',
          confidence: 0.89,
          xMin: 0.4,
          yMin: 0.2,
          xMax: 0.6,
          yMax: 0.9,
          distanceMeters: 2.1,
          ttcSeconds: 4.0,
          priority: AudioPriority.level2Navigation,
          clockPosition: "12 o'clock",
        ),
        DetectedObstacle(
          label: 'Person',
          confidence: 0.82,
          xMin: 0.1,
          yMin: 0.3,
          xMax: 0.3,
          yMax: 0.8,
          distanceMeters: 3.4,
          ttcSeconds: 6.0,
          priority: AudioPriority.level2Navigation,
          clockPosition: "10 o'clock",
        ),
      ];

      final exchange = await qaService.askQuestion(
        question: 'Is there anyone in front of me?',
        activeObstacles: samplePeople,
        phonePitchDeg: 0.0,
      );

      expect(exchange.answer, contains('2 people'));
      expect(exchange.answer, contains('2.1 meters'));
      expect(exchange.answer, contains("12 o'clock"));
    });

    test('Tracks question and answer history correctly', () async {
      await qaService.askQuestion(
        question: 'Where is the doorway?',
        activeObstacles: [
          DetectedObstacle(
            label: 'Door',
            confidence: 0.95,
            xMin: 0.5,
            yMin: 0.1,
            xMax: 0.7,
            yMax: 0.9,
            distanceMeters: 2.8,
            ttcSeconds: 5.0,
            priority: AudioPriority.level2Navigation,
            clockPosition: "1 o'clock",
          ),
        ],
        phonePitchDeg: 0.0,
      );

      expect(qaService.history.length, greaterThanOrEqualTo(1));
      expect(qaService.history.last.answer, contains('Doorway'));
      expect(qaService.history.last.answer, contains("1 o'clock"));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/models/voice_requirement_models.dart';
import 'package:orbisnav/router/voice_intent_router.dart';

void main() {
  late VoiceIntentRouter router;

  setUp(() {
    router = VoiceIntentRouter();
  });

  group('VoiceIntentRouter Accuracy & Sub-50ms Benchmarks', () {
    test('routes 1: Short Text Engine correctly', () {
      final inputs = [
        "Read text",
        "Read this sign",
        "What does this say?",
        "Read label",
        "What is written here?",
        "Instant OCR",
      ];

      for (final text in inputs) {
        final result = router.route(text);
        expect(result.subsystem, equals(VoiceSubsystem.shortText), reason: 'Failed for: $text');
        expect(result.confidence, greaterThanOrEqualTo(0.5));
        expect(result.latencyMs, lessThan(50), reason: 'Latency must be < 50ms');
      }
    });

    test('routes 2: Document Engine with 4-corner edge detection intent', () {
      final inputs = [
        "Scan document",
        "Read this letter",
        "Scan this bill",
        "Read receipt",
        "Batch OCR this page",
      ];

      for (final text in inputs) {
        final result = router.route(text);
        expect(result.subsystem, equals(VoiceSubsystem.document), reason: 'Failed for: $text');
        expect(result.latencyMs, lessThan(50));
      }
    });

    test('routes 3: Barcode Engine with acoustic centering', () {
      final inputs = [
        "Scan barcode",
        "Check this barcode",
        "What product is this?",
        "Scan QR code",
        "Identify product",
      ];

      for (final text in inputs) {
        final result = router.route(text);
        expect(result.subsystem, equals(VoiceSubsystem.barcode), reason: 'Failed for: $text');
        expect(result.latencyMs, lessThan(50));
      }
    });

    test('routes 4: Currency & Person Engine with parameter extraction', () {
      final currencyInputs = [
        "Count money",
        "How much cash is this?",
        "Identify rupees",
        "Count currency",
      ];

      for (final text in currencyInputs) {
        final result = router.route(text);
        expect(result.subsystem, equals(VoiceSubsystem.currencyPerson), reason: 'Failed for: $text');
        expect(result.parameters['targetFocus'], equals('currency'));
        expect(result.latencyMs, lessThan(50));
      }

      final personInputs = [
        "Who is in front of me?",
        "Recognize person",
        "Who is here?",
      ];

      for (final text in personInputs) {
        final result = router.route(text);
        expect(result.subsystem, equals(VoiceSubsystem.currencyPerson), reason: 'Failed for: $text');
        expect(result.parameters['targetFocus'], equals('person'));
        expect(result.latencyMs, lessThan(50));
      }
    });

    test('routes 5: Light Detector Engine with frequency pitch intent', () {
      final inputs = [
        "Check light",
        "Is the light on?",
        "How bright is it?",
        "Light level",
      ];

      for (final text in inputs) {
        final result = router.route(text);
        expect(result.subsystem, equals(VoiceSubsystem.lightDetector), reason: 'Failed for: $text');
        expect(result.latencyMs, lessThan(50));
      }
    });

    test('routes 6: Scene & Visual QA Engine with object parameter extraction', () {
      final sceneInputs = [
        "Describe scene",
        "What is in front of me?",
        "Look around",
        "Describe the room",
      ];

      for (final text in sceneInputs) {
        final result = router.route(text);
        expect(result.subsystem, equals(VoiceSubsystem.sceneQa), reason: 'Failed for: $text');
        expect(result.latencyMs, lessThan(50));
      }

      // Object search extraction
      final findResult = router.route("Find my keys");
      expect(findResult.subsystem, equals(VoiceSubsystem.sceneQa));
      expect(findResult.parameters['targetObject'], equals('keys'));
    });

    test('routes arbitrary conversational question to Cloud Multimodal Fallback', () {
      final fallbackResult = router.route("Can you tell me if this milk is expired or not?");
      expect(fallbackResult.subsystem, equals(VoiceSubsystem.sceneQa));
      expect(fallbackResult.isCloudFallbackRequired, isTrue);
      expect(fallbackResult.latencyMs, lessThan(50));
    });

    test('handles empty utterance cleanly', () {
      final emptyResult = router.route("   ");
      expect(emptyResult.subsystem, equals(VoiceSubsystem.none));
      expect(emptyResult.confidence, equals(0.0));
    });
  });
}

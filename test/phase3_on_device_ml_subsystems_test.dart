import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/controllers/accessible_audio_tone_manager.dart';
import 'package:orbisnav/controllers/voice_requirement_state_machine.dart';
import 'package:orbisnav/models/voice_requirement_models.dart';
import 'package:orbisnav/router/voice_intent_router.dart';
import 'package:orbisnav/services/document_framing_guide_service.dart';
import 'package:orbisnav/services/subsystems/barcode_pitch_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AccessibleAudioToneManager audioManager;
  late VoiceIntentRouter router;
  late VoiceRequirementStateMachine stateMachine;

  setUp(() {
    AccessibleAudioToneManager.testMode = true;
    audioManager = AccessibleAudioToneManager();
    router = VoiceIntentRouter();
    stateMachine = VoiceRequirementStateMachine.withDependencies(
      router: router,
      audioManager: audioManager,
    );
  });

  group('Phase 3: Subsystem 1 - Short Text Instant OCR Engine', () {
    test('extracts, speaks, and debounces repeated text', () async {
      final engine = stateMachine.shortTextEngine;
      engine.ocrDetectionHook = (bytes) async => ["Room 304", "Conference Hall"];

      // 1. Process frame with text
      final results = await engine.processFrame(Uint8List(50));
      expect(results, equals(["Room 304", "Conference Hall"]));
      expect(audioManager.currentUtterance, equals("Room 304 Conference Hall"));
      expect(engine.lastSpokenText, equals("Room 304 Conference Hall"));
      expect(engine.totalWordsRead, equals(4));

      // 2. Process frame with same text within debounce window (must NOT speak again)
      audioManager.handleSpeechRecognized(""); // clear test state
      await engine.processFrame(Uint8List(50));
      // Voice utterance must remain unchanged because of debouncing
      expect(audioManager.currentUtterance, equals("Room 304 Conference Hall"));

      // 3. Process frame with new text (must immediately speak new text)
      engine.ocrDetectionHook = (bytes) async => ["Exit to Street"];
      await engine.processFrame(Uint8List(50));
      expect(audioManager.currentUtterance, equals("Exit to Street"));
      expect(engine.totalWordsRead, equals(7));
    });
  });

  group('Phase 3: Subsystem 6 - Light Detector Engine', () {
    test('converts luminance into continuous frequency and announces percent', () async {
      final engine = stateMachine.lightDetectorEngine;

      // 1. Test pitch dark luminance
      engine.setLuminanceForTesting(0.02);
      expect(engine.lightLevelPercent, equals(2));
      expect(engine.qualitativeDescription, contains("Pitch black"));
      expect(audioManager.activeToneFrequency, closeTo(200.0, 50.0));

      // 2. Test bright outdoor luminance
      engine.setLuminanceForTesting(0.80);
      expect(engine.lightLevelPercent, equals(80));
      expect(engine.qualitativeDescription, contains("Brightly lit"));
      expect(audioManager.activeToneFrequency, greaterThan(1500.0));

      // 3. Test vocal announcement
      await engine.announceLightLevel(forced: true);
      expect(audioManager.currentUtterance, contains("Light level 80 percent"));
      expect(audioManager.currentUtterance, contains("Brightly lit"));

      // 4. Stop oscillator
      engine.stop();
      expect(audioManager.isOscillatorActive, isFalse);
    });
  });

  group('Phase 3: Subsystem 4 - Barcode Pitch Guide Engine', () {
    test('computes distance from center, drives acoustic beeps, and speaks product on center', () async {
      final engine = stateMachine.barcodePitchEngine;

      // 1. Barcode far from center (e.g., top-left corner: (0.1, 0.1))
      final offCenterBarcode = const DetectedBarcode(
        rawValue: "012000000133",
        centerX: 0.1,
        centerY: 0.1,
      );
      expect(offCenterBarcode.distanceFromCenter, greaterThan(0.6));
      expect(offCenterBarcode.isCentered, isFalse);

      await engine.injectDetectedBarcode(offCenterBarcode);
      // Barcode not centered -> should not speak product yet
      expect(engine.lastDecodedBarcode, isNull);

      // 2. Barcode perfectly centered (0.5, 0.5)
      final centeredBarcode = const DetectedBarcode(
        rawValue: "012000000133",
        centerX: 0.5,
        centerY: 0.5,
      );
      expect(centeredBarcode.distanceFromCenter, equals(0.0));
      expect(centeredBarcode.isCentered, isTrue);

      await engine.injectDetectedBarcode(centeredBarcode);
      expect(engine.lastDecodedBarcode, equals("012000000133"));
      expect(audioManager.currentUtterance, contains("Pepsi"));
    });
  });

  group('Phase 3: Subsystem 2 - Document 4-Corner Edge Guidance Engine', () {
    test('gives directional verbal cues for misaligned documents', () async {
      final engine = stateMachine.documentEdgeEngine;

      // 1. Document cut off at top (top Y < 0.05) -> Move camera down
      engine.cornerDetectionHook = (bytes) async => const DocumentCorners(
            topLeftX: 0.2,
            topLeftY: 0.01,
            topRightX: 0.8,
            topRightY: 0.01,
            bottomLeftX: 0.2,
            bottomLeftY: 0.8,
            bottomRightX: 0.8,
            bottomRightY: 0.8,
            coverageRatio: 0.6,
          );

      final status1 = await engine.processFrame(Uint8List(20));
      expect(status1, equals(FramingAlignmentStatus.moveDown));
      expect(audioManager.currentUtterance, equals("Move camera down."));

      // 2. Document too far away (coverage < 0.25) -> Move closer
      engine.cornerDetectionHook = (bytes) async => const DocumentCorners(
            topLeftX: 0.4,
            topLeftY: 0.4,
            topRightX: 0.6,
            topRightY: 0.4,
            bottomLeftX: 0.4,
            bottomLeftY: 0.6,
            bottomRightX: 0.6,
            bottomRightY: 0.6,
            coverageRatio: 0.15,
          );

      final status2 = await engine.processFrame(Uint8List(20));
      expect(status2, equals(FramingAlignmentStatus.tooFar));
      expect(audioManager.currentUtterance, equals("Move closer to document."));
    });

    test('detects all 4 corners, holds steady for 500ms, and auto-captures structured OCR', () async {
      final engine = stateMachine.documentEdgeEngine;
      bool captureCalled = false;

      engine.onAutoCaptureStill = () async {
        captureCalled = true;
        return Uint8List.fromList([1, 2, 3, 4]);
      };

      engine.ocrExtractorHook = (bytes) async {
        return "Invoice 1042. Total due is \$45.00. Paid in full.";
      };

      // Perfectly framed document corners
      engine.cornerDetectionHook = (bytes) async => const DocumentCorners(
            topLeftX: 0.15,
            topLeftY: 0.15,
            topRightX: 0.85,
            topRightY: 0.15,
            bottomLeftX: 0.15,
            bottomLeftY: 0.85,
            bottomRightX: 0.85,
            bottomRightY: 0.85,
            coverageRatio: 0.65,
          );

      // Frame 1: First time all 4 corners visible -> "Hold steady."
      final status1 = await engine.processFrame(Uint8List(20));
      expect(status1, equals(FramingAlignmentStatus.perfectHoldStill));
      expect(audioManager.currentUtterance, equals("Hold steady."));
      expect(captureCalled, isFalse);

      // Wait 550ms for steady hold
      await Future.delayed(const Duration(milliseconds: 550));

      // Frame 2: Still steady after 550ms -> Auto-captures and reads structured text!
      final status2 = await engine.processFrame(Uint8List(20));
      expect(status2, equals(FramingAlignmentStatus.captured));
      expect(captureCalled, isTrue);
      expect(audioManager.currentUtterance, contains("Invoice 1042"));
      expect(audioManager.currentUtterance, contains("\$45.00"));
    });
  });

  group('Phase 3: Integration with Voice Requirement State Machine', () {
    test('routes spoken requirement dynamically to active engine', () async {
      // 1. Spoken requirement: "What does this sign say?"
      await stateMachine.handleVoiceRequirement("What does this sign say?");
      expect(stateMachine.state.activeSubsystem, equals(VoiceSubsystem.shortText));

      // Simulate frame with text
      stateMachine.shortTextEngine.ocrDetectionHook =
          (bytes) async => ["Department of Ophthalmology"];
      await stateMachine.processCameraFrame(Uint8List(20), 0.5);
      expect(audioManager.currentUtterance, equals("Department of Ophthalmology"));

      // 2. Spoken requirement: "Scan this document"
      await stateMachine.handleVoiceRequirement("Scan this document");
      expect(stateMachine.state.activeSubsystem, equals(VoiceSubsystem.document));

      // 3. Spoken requirement: "Check the light level"
      await stateMachine.handleVoiceRequirement("Check the light level");
      expect(stateMachine.state.activeSubsystem, equals(VoiceSubsystem.lightDetector));
      expect(audioManager.isOscillatorActive, isTrue);
    });
  });
}

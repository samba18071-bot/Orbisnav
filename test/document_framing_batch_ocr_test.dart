import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/services/document_framing_guide_service.dart';
import 'package:orbisnav/services/document_batch_ocr_reader_service.dart';
import 'package:orbisnav/controllers/audio_mutex_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Day 3: Document Edge Detector & Audio Framing Guide Tests', () {
    late DocumentFramingGuideService framingService;
    late AudioMutexController audioMutex;

    setUp(() {
      audioMutex = AudioMutexController();
      framingService = DocumentFramingGuideService(audioMutex: audioMutex);
    });

    tearDown(() {
      framingService.dispose();
    });

    test('Prompts when no document is detected in the frame', () {
      final result = framingService.evaluateFrame(
        corners: null,
        phonePitchDeg: 0.0,
        phoneRollDeg: 0.0,
      );

      expect(result.status, equals(FramingAlignmentStatus.noDocumentDetected));
      expect(result.readyToCapture, isFalse);
      expect(result.spokenGuidance, contains('Place document flat'));
    });

    test('Detects when phone is held at severe tilt angle', () {
      const corners = DocumentCorners(
        topLeftX: 0.1,
        topLeftY: 0.1,
        topRightX: 0.9,
        topRightY: 0.1,
        bottomLeftX: 0.1,
        bottomLeftY: 0.9,
        bottomRightX: 0.9,
        bottomRightY: 0.9,
        coverageRatio: 0.65,
      );

      final result = framingService.evaluateFrame(
        corners: corners,
        phonePitchDeg: -48.0, // High tilt
        phoneRollDeg: 5.0,
      );

      expect(result.status, equals(FramingAlignmentStatus.tiltAdjustRequired));
      expect(result.spokenGuidance, contains('Hold phone flatter'));
    });

    test('Detects when document is too far away (low coverage)', () {
      const smallCorners = DocumentCorners(
        topLeftX: 0.4,
        topLeftY: 0.4,
        topRightX: 0.6,
        topRightY: 0.4,
        bottomLeftX: 0.4,
        bottomLeftY: 0.6,
        bottomRightX: 0.6,
        bottomRightY: 0.6,
        coverageRatio: 0.12, // Too small
      );

      final result = framingService.evaluateFrame(
        corners: smallCorners,
        phonePitchDeg: 0.0,
        phoneRollDeg: 0.0,
      );

      expect(result.status, equals(FramingAlignmentStatus.tooFar));
      expect(result.spokenGuidance, contains('Move phone closer'));
    });

    test('Guides horizontal and vertical directional centering shifts', () {
      // Offset to the left side (centerX = 0.25)
      const leftCorners = DocumentCorners(
        topLeftX: 0.1,
        topLeftY: 0.3,
        topRightX: 0.4,
        topRightY: 0.3,
        bottomLeftX: 0.1,
        bottomLeftY: 0.7,
        bottomRightX: 0.4,
        bottomRightY: 0.7,
        coverageRatio: 0.50,
      );

      final result = framingService.evaluateFrame(
        corners: leftCorners,
        phonePitchDeg: 0.0,
        phoneRollDeg: 0.0,
      );

      expect(result.status, equals(FramingAlignmentStatus.moveRight));
      expect(result.spokenGuidance, contains('Shift phone slightly right'));
    });

    test('Triggers auto-capture when alignment is held stable', () async {
      const perfectCorners = DocumentCorners(
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

      // Frame 1
      final r1 = framingService.evaluateFrame(
        corners: perfectCorners,
        phonePitchDeg: 0.0,
        phoneRollDeg: 0.0,
      );
      expect(r1.status, equals(FramingAlignmentStatus.perfectHoldStill));
      expect(r1.readyToCapture, isFalse);

      // Wait 900ms to exceed the 800ms stable threshold
      await Future.delayed(const Duration(milliseconds: 900));

      // Frame 2
      final r2 = framingService.evaluateFrame(
        corners: perfectCorners,
        phonePitchDeg: 0.0,
        phoneRollDeg: 0.0,
      );
      expect(r2.status, equals(FramingAlignmentStatus.captured));
      expect(r2.readyToCapture, isTrue);
      expect(r2.stabilityProgress, equals(1.0));
    });
  });

  group('Day 4: Batch OCR Document Reader & Paragraph Navigation Tests', () {
    late DocumentBatchOcrReaderService readerService;
    late AudioMutexController audioMutex;

    setUp(() {
      audioMutex = AudioMutexController();
      readerService = DocumentBatchOcrReaderService(audioMutex: audioMutex);
    });

    tearDown(() {
      readerService.dispose();
    });

    test('Parses multi-paragraph raw OCR text into structured sections', () {
      const sampleOcr = '''
      PRESCRIPTION DETAILS:

      Take 1 tablet of Amoxicillin 500mg by mouth twice daily with meals for 7 days.

      WARNING:
      Finish full course of medication even if symptoms subside.
      ''';

      final session = readerService.addPage(sampleOcr);

      expect(session.totalPages, equals(1));
      expect(session.paragraphs.length, greaterThanOrEqualTo(3));
      expect(session.paragraphs[0].text, contains('PRESCRIPTION DETAILS'));
      expect(session.paragraphs[0].isHeading, isTrue);
      expect(session.paragraphs[1].text, contains('Amoxicillin'));
    });

    test('Controls paragraph navigation and speed', () {
      const sampleOcr = '''
      Paragraph 1: Introduction to OrbisNav navigation engine.

      Paragraph 2: Features include micro-latency collision avoidance.

      Paragraph 3: Complete on-device edge AI processing.
      ''';

      readerService.addPage(sampleOcr);
      readerService.startReading();

      expect(readerService.currentSession.isPlaying, isTrue);
      expect(readerService.currentSession.currentParagraphIndex, equals(0));

      // Next paragraph
      readerService.nextParagraph();
      expect(readerService.currentSession.currentParagraphIndex, equals(1));
      expect(readerService.currentSession.currentParagraph?.text, contains('Paragraph 2'));

      // Previous paragraph
      readerService.previousParagraph();
      expect(readerService.currentSession.currentParagraphIndex, equals(0));

      // Adjust speed
      readerService.setPlaybackSpeed(1.5);
      expect(readerService.currentSession.playbackSpeed, equals(1.5));

      // Pause & Resume
      readerService.pauseReading();
      expect(readerService.currentSession.isPaused, isTrue);

      readerService.resumeReading();
      expect(readerService.currentSession.isPlaying, isTrue);

      readerService.stopReading();
      expect(readerService.currentSession.status, equals(ReaderPlaybackStatus.idle));
    });

    test('Accumulates multi-page batch scans correctly', () {
      readerService.addPage('Page 1 Content: Hospital Discharge Summary.');
      expect(readerService.currentSession.totalPages, equals(1));

      readerService.addPage('Page 2 Content: Follow up appointment in 2 weeks.');
      expect(readerService.currentSession.totalPages, equals(2));
      expect(readerService.currentSession.paragraphs.length, equals(2));
      expect(readerService.currentSession.paragraphs[1].pageNumber, equals(2));
    });
  });
}

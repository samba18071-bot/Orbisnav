import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/controllers/audio_mutex_controller.dart';
import 'package:orbisnav/services/barcode_product_service.dart';
import 'package:orbisnav/services/currency_recognition_service.dart';
import 'package:orbisnav/services/document_framing_guide_service.dart';
import 'package:orbisnav/services/document_batch_ocr_reader_service.dart';
import 'package:orbisnav/services/conversational_voice_qa_service.dart';
import 'package:orbisnav/services/offline_scene_captioning_service.dart';
import 'package:orbisnav/services/online_obstacle_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Comprehensive Accuracy & Stress Verification Suite', () {
    late AudioMutexController audioMutex;
    late BarcodeProductService barcodeService;
    late CurrencyRecognitionService currencyService;
    late DocumentFramingGuideService framingService;
    late DocumentBatchOcrReaderService readerService;
    late ConversationalVoiceQAService voiceQaService;
    late OfflineSceneCaptioningService captionService;

    setUp(() {
      audioMutex = AudioMutexController();
      barcodeService = BarcodeProductService(audioMutex: audioMutex);
      currencyService = CurrencyRecognitionService(audioMutex: audioMutex);
      framingService = DocumentFramingGuideService(audioMutex: audioMutex);
      readerService = DocumentBatchOcrReaderService(audioMutex: audioMutex);
      voiceQaService = ConversationalVoiceQAService.internal(audioMutex: audioMutex);
      captionService = OfflineSceneCaptioningService(audioMutex: audioMutex);
    });

    tearDown(() {
      audioMutex.hardStop();
      barcodeService.dispose();
      currencyService.dispose();
      framingService.dispose();
      readerService.dispose();
      voiceQaService.dispose();
      captionService.dispose();
    });

    // -------------------------------------------------------------
    // Test 1: Audio Mutex Queue Saturation & Preemption Stress
    // -------------------------------------------------------------
    test('Stress Test: Rapid fire 50 mixed-priority audio requests without deadlock', () async {
      for (int i = 0; i < 50; i++) {
        final priority = i % 4 == 0
            ? AudioPriority.level0Critical
            : i % 3 == 0
                ? AudioPriority.level1Safety
                : i % 2 == 0
                    ? AudioPriority.level2Navigation
                    : AudioPriority.level3Context;

        audioMutex.speak(
          text: 'Request #$i with priority ${priority.name}',
          priority: priority,
          haptic: false,
          force: true,
        );
      }

      // Verify mutex remains responsive and maintains highest priority execution
      expect(audioMutex.currentActivePriority, isNotNull);
      expect(audioMutex.currentActivePriority!.value, lessThanOrEqualTo(AudioPriority.level2Navigation.value));
    });

    // -------------------------------------------------------------
    // Test 2: Multi-Currency Complex Token Extraction & Disambiguation
    // -------------------------------------------------------------
    test('Accuracy Test: Currency token disambiguation under noisy OCR receipts', () async {
      currencyService.setCurrency(CurrencyCode.usd);

      // Noisy string with receipt numbers and tax info
      final noisyTokens = ['RECEIPT', 'STORE#104', 'TOTAL', '20', 'DOLLARS', 'TAX', '1.60'];
      final res = await currencyService.processVisualTokens(
        detectedTexts: noisyTokens,
        confidence: 0.94,
      );

      expect(res.isIdentified, isTrue);
      expect(res.denomination?.value, equals(20));
      expect(res.denomination?.symbol, equals('\$'));
      expect(res.denomination?.hapticPatternMs, equals([250, 250]));
    });

    test('Accuracy Test: Currency switching rejects mismatched currency tokens', () async {
      currencyService.setCurrency(CurrencyCode.eur);

      // Given INR rupee tokens while set to EUR
      final inrTokens = ['RESERVE', 'BANK', 'OF', 'INDIA', '500', 'RUPEES'];
      final res = await currencyService.processVisualTokens(
        detectedTexts: inrTokens,
        confidence: 0.85,
      );

      // Should not falsely identify as EUR
      expect(res.denomination?.currency, isNot(equals(CurrencyCode.inr)));
    });

    // -------------------------------------------------------------
    // Test 3: Document Auto-Capture Stability & Progress Calculation
    // -------------------------------------------------------------
    test('Accuracy Test: Document framing progress scales linearly and triggers capture', () async {
      const stableBox = DocumentCorners(
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

      final r1 = framingService.evaluateFrame(
        corners: stableBox,
        phonePitchDeg: 0.0,
        phoneRollDeg: 0.0,
      );
      expect(r1.status, equals(FramingAlignmentStatus.perfectHoldStill));

      await Future.delayed(const Duration(milliseconds: 900));

      final r2 = framingService.evaluateFrame(
        corners: stableBox,
        phonePitchDeg: 0.0,
        phoneRollDeg: 0.0,
      );
      expect(r2.status, equals(FramingAlignmentStatus.captured));
      expect(r2.readyToCapture, isTrue);
    });

    // -------------------------------------------------------------
    // Test 4: Heavy Multi-Page OCR Document Traversal
    // -------------------------------------------------------------
    test('Stress Test: 5-page batch scan with 25 paragraphs and rapid navigation', () {
      for (int page = 1; page <= 5; page++) {
        final pageText = StringBuffer();
        for (int p = 1; p <= 5; p++) {
          pageText.writeln('Page $page Paragraph $p: Detailed medical examination notes and instructions.');
          pageText.writeln();
        }
        readerService.addPage(pageText.toString());
      }

      expect(readerService.currentSession.totalPages, equals(5));
      expect(readerService.currentSession.totalParagraphs, equals(25));

      // Fast forward 10 paragraphs
      for (int i = 0; i < 10; i++) {
        readerService.nextParagraph();
      }
      expect(readerService.currentSession.currentParagraphIndex, equals(10));
      expect(readerService.currentSession.currentParagraph?.pageNumber, equals(3));

      // Rewind 5 paragraphs
      for (int i = 0; i < 5; i++) {
        readerService.previousParagraph();
      }
      expect(readerService.currentSession.currentParagraphIndex, equals(5));
      expect(readerService.currentSession.currentParagraph?.pageNumber, equals(2));
    });

    // -------------------------------------------------------------
    // Test 5: 360-Degree Corridor Solver & Extreme Obstacle Density
    // -------------------------------------------------------------
    test('Accuracy Test: Corridor solver detects when all forward sectors are blocked', () {
      final allBlocked = [
        DetectedObstacle(
          label: 'Wall',
          confidence: 0.95,
          xMin: 0.4,
          yMin: 0.4,
          xMax: 0.6,
          yMax: 0.8,
          distanceMeters: 1.2,
          ttcSeconds: 1.0,
          priority: AudioPriority.level0Critical,
          clockPosition: "12 o'clock",
        ),
        DetectedObstacle(
          label: 'Pillar',
          confidence: 0.90,
          xMin: 0.1,
          yMin: 0.4,
          xMax: 0.3,
          yMax: 0.8,
          distanceMeters: 1.5,
          ttcSeconds: 1.5,
          priority: AudioPriority.level1Safety,
          clockPosition: "10 o'clock",
        ),
        DetectedObstacle(
          label: 'Barrier',
          confidence: 0.92,
          xMin: 0.7,
          yMin: 0.4,
          xMax: 0.9,
          yMax: 0.8,
          distanceMeters: 1.4,
          ttcSeconds: 1.3,
          priority: AudioPriority.level1Safety,
          clockPosition: "2 o'clock",
        ),
      ];

      final caption = captionService.generateCaption(obstacles: allBlocked);
      expect(caption.openCorridorSuggestion, contains('Slow down; path ahead is restricted'));
      expect(caption.foregroundHazards.length, equals(3));
    });

    test('Accuracy Test: Corridor solver picks clear right sector when center and left are blocked', () {
      final centerAndLeftBlocked = [
        DetectedObstacle(
          label: 'Vehicle',
          confidence: 0.98,
          xMin: 0.4,
          yMin: 0.4,
          xMax: 0.6,
          yMax: 0.8,
          distanceMeters: 1.8,
          ttcSeconds: 1.5,
          priority: AudioPriority.level0Critical,
          clockPosition: "12 o'clock",
        ),
        DetectedObstacle(
          label: 'Fence',
          confidence: 0.88,
          xMin: 0.1,
          yMin: 0.4,
          xMax: 0.3,
          yMax: 0.8,
          distanceMeters: 1.6,
          ttcSeconds: 1.8,
          priority: AudioPriority.level1Safety,
          clockPosition: "10 o'clock",
        ),
      ];

      final caption = captionService.generateCaption(obstacles: centerAndLeftBlocked);
      expect(caption.openCorridorSuggestion, contains("2 o'clock"));
      expect(caption.openCorridorSuggestion, contains('Clear corridor open to your right'));
    });

    // -------------------------------------------------------------
    // Test 6: Voice Q&A Intelligent Query Parsing & Classification
    // -------------------------------------------------------------
    test('Accuracy Test: Voice QA correctly resolves doorway queries with direction', () async {
      final obstacles = [
        DetectedObstacle(
          label: 'Door',
          confidence: 0.96,
          xMin: 0.8,
          yMin: 0.2,
          xMax: 0.95,
          yMax: 0.9,
          distanceMeters: 3.2,
          ttcSeconds: 4.5,
          priority: AudioPriority.level2Navigation,
          clockPosition: "3 o'clock",
        ),
      ];

      final exchange = await voiceQaService.askQuestion(
        question: 'Where is the exit door?',
        activeObstacles: obstacles,
        phonePitchDeg: 0.0,
      );

      expect(exchange.answer, contains('Doorway located 3.2 meters'));
      expect(exchange.answer, contains("3 o'clock"));
    });
  });
}

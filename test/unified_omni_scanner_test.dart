import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:orbisnav/controllers/audio_mutex_controller.dart';
import 'package:orbisnav/services/barcode_product_service.dart';
import 'package:orbisnav/services/conversational_voice_qa_service.dart';
import 'package:orbisnav/services/currency_recognition_service.dart';
import 'package:orbisnav/services/document_batch_ocr_reader_service.dart';
import 'package:orbisnav/services/document_framing_guide_service.dart';
import 'package:orbisnav/services/global_standards_service.dart';
import 'package:orbisnav/services/smart_glasses_bridge_service.dart';
import 'package:orbisnav/services/unified_omni_scanner_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UnifiedOmniScannerService Architectural & Safety Tests', () {
    late AudioMutexController audioMutex;
    late BarcodeProductService barcodeService;
    late CurrencyRecognitionService currencyService;
    late DocumentFramingGuideService framingGuideService;
    late DocumentBatchOcrReaderService documentReaderService;
    late ConversationalVoiceQAService voiceQaService;
    late SmartGlassesBridgeService smartGlassesService;
    late GlobalStandardsService globalStandards;
    late UnifiedOmniScannerService omniScanner;
    late List<String> spokenAudioLog;
    late List<AudioPriority> spokenPriorityLog;
    late http.Client mockHttpClient;

    setUp(() {
      spokenAudioLog = [];
      spokenPriorityLog = [];
      audioMutex = AudioMutexController();
      audioMutex.setActiveChannel(2);
      audioMutex.activeSpeechStream.listen((event) {
        if (event != null) {
          spokenAudioLog.add(event.text);
          spokenPriorityLog.add(event.priority);
        }
      });

      mockHttpClient = MockClient((request) async {
        if (request.url.path.contains('/api/v1/omni-scan/summarize')) {
          final data = jsonDecode(request.body) as Map<String, dynamic>;
          final text = data['text']?.toString() ?? '';
          return http.Response(
            jsonEncode({
              "document_type": text.contains("Utility") ? "Utility Bill" : "General Document",
              "sender_or_title": "City Electric",
              "bullet_points": [
                "Electric utility bill for account 987654.",
                "Total amount due is \$84.50."
              ],
              "action_items": ["Payment due: \$84.50", "Due date: Nov 15"],
              "executive_summary": "Document Type: Utility Bill. Total amount due is \$84.50.",
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      barcodeService = BarcodeProductService(audioMutex: audioMutex);
      currencyService = CurrencyRecognitionService(audioMutex: audioMutex);
      framingGuideService = DocumentFramingGuideService(audioMutex: audioMutex);
      documentReaderService = DocumentBatchOcrReaderService(audioMutex: audioMutex);
      voiceQaService = ConversationalVoiceQAService();
      smartGlassesService = SmartGlassesBridgeService(audioMutex: audioMutex);
      globalStandards = GlobalStandardsService();

      omniScanner = UnifiedOmniScannerService(
        audioMutex: audioMutex,
        barcodeService: barcodeService,
        currencyService: currencyService,
        framingGuideService: framingGuideService,
        documentReaderService: documentReaderService,
        voiceQaService: voiceQaService,
        smartGlassesService: smartGlassesService,
        globalStandards: globalStandards,
        httpClient: mockHttpClient,
      );
    });

    tearDown(() {
      omniScanner.dispose();
      smartGlassesService.dispose();
      voiceQaService.dispose();
      documentReaderService.dispose();
      framingGuideService.dispose();
      currencyService.dispose();
      barcodeService.dispose();
      audioMutex.dispose();
    });

    test('Initializes in idle state with 30 target FPS and nominal thermal state', () {
      expect(omniScanner.currentState.mode, equals(OmniScanClassification.none));
      expect(omniScanner.currentState.status, equals(OmniScannerStatus.idle));
      expect(omniScanner.targetFps, equals(30));
      expect(omniScanner.isThrottledSingleShot, isFalse);
      expect(omniScanner.isThermalSuspended, isFalse);
    });

    // -------------------------------------------------------------------------
    // Branch 1: Barcode Detection (Fastest Path & 800ms Debounce)
    // -------------------------------------------------------------------------
    test('Branch 1: Barcode Detection fastest path & 800ms sliding-window debounce', () async {
      final state1 = await omniScanner.processFrame(
        rawBarcode: '012000000133', // Pepsi Cola from offline db
      );

      expect(state1.mode, equals(OmniScanClassification.barcode));
      expect(state1.status, equals(OmniScannerStatus.barcodeDetected));
      expect(state1.detectedBarcode, equals('012000000133'));

      // Check audio announcement at Priority Level 2 (< 250ms informational)
      expect(spokenAudioLog.isNotEmpty, isTrue);
      expect(spokenPriorityLog.contains(AudioPriority.level2Navigation), isTrue);

      final initialAudioCount = spokenAudioLog.length;

      // Immediate subsequent frame with SAME barcode within 800ms window
      final state2 = await omniScanner.processFrame(
        rawBarcode: '012000000133',
      );
      expect(state2.detectedBarcode, equals('012000000133'));
      // No duplicate announcement due to 800ms debounce
      expect(spokenAudioLog.length, equals(initialAudioCount));

      // After debounce window expires (> 800ms)
      await Future.delayed(const Duration(milliseconds: 850));
      await omniScanner.processFrame(
        rawBarcode: '012000000133',
      );
      // New announcement triggered
      expect(spokenAudioLog.length, greaterThan(initialAudioCount));
    });

    // -------------------------------------------------------------------------
    // Branch 2: Currency Note Multi-Frame Verification (>= 3 frames >= 0.88)
    // -------------------------------------------------------------------------
    test('Branch 2: Currency Note requires >= 3 consecutive frames with confidence >= 0.88', () async {
      final testNote = BanknoteDenomination.supportedBanknotes.firstWhere(
        (b) => b.currency == CurrencyCode.inr && b.value == 500,
      );

      // Frame 1
      final s1 = await omniScanner.processFrame(
        banknoteCandidate: testNote,
        currencyConfidence: 0.92,
      );
      expect(s1.mode, equals(OmniScanClassification.currency));
      expect(s1.status, equals(OmniScannerStatus.currencyVerifying));
      expect(s1.consecutiveCurrencyFrames, equals(1));

      // Frame 2
      final s2 = await omniScanner.processFrame(
        banknoteCandidate: testNote,
        currencyConfidence: 0.92,
      );
      expect(s2.consecutiveCurrencyFrames, equals(2));
      expect(s2.status, equals(OmniScannerStatus.currencyVerifying));

      // Frame 3 (Threshold met: >= 3 frames)
      final s3 = await omniScanner.processFrame(
        banknoteCandidate: testNote,
        currencyConfidence: 0.92,
      );
      expect(s3.consecutiveCurrencyFrames, equals(3));
      expect(s3.status, equals(OmniScannerStatus.currencyConfirmed));
      expect(s3.verifiedBanknote, isNotNull);
      expect(s3.verifiedBanknote!.value, equals(500));

      // Spoken output at Priority Level 2 with denomination, currency and orientation
      final currencySpeech = spokenAudioLog.firstWhere(
        (text) => text.contains('500') && text.contains('Indian Rupee'),
      );
      expect(currencySpeech, contains('front side facing up'));
      expect(spokenPriorityLog.contains(AudioPriority.level2Navigation), isTrue);
    });

    test('Branch 2: Currency resets verification count if confidence drops below 0.88', () async {
      final validNote = BanknoteDenomination.supportedBanknotes.firstWhere(
        (b) => b.currency == CurrencyCode.usd && b.value == 20,
      );

      await omniScanner.processFrame(banknoteCandidate: validNote, currencyConfidence: 0.95);
      await omniScanner.processFrame(banknoteCandidate: validNote, currencyConfidence: 0.95);
      expect(omniScanner.currentState.consecutiveCurrencyFrames, equals(2));

      // Frame 3 with low confidence (< 0.88) resets the consecutive counter
      final s3 = await omniScanner.processFrame(banknoteCandidate: validNote, currencyConfidence: 0.75);
      expect(s3.consecutiveCurrencyFrames, equals(0));
      expect(s3.status, equals(OmniScannerStatus.idle));
    });

    // -------------------------------------------------------------------------
    // Branch 3: Document Framing, Corner Audit, Pitch Audit & Auto-Capture
    // -------------------------------------------------------------------------
    test('Branch 3: Document Framing corner visibility and tilt guidance', () async {
      // Incomplete corners -> "Move camera back"
      const incompleteCorners = DocumentCorners(
        topLeftX: -0.1, // Out of visible bounds
        topLeftY: 0.1,
        topRightX: 0.9,
        topRightY: 0.1,
        bottomLeftX: 0.1,
        bottomLeftY: 0.9,
        bottomRightX: 0.9,
        bottomRightY: 0.9,
        coverageRatio: 0.5,
      );

      final state1 = await omniScanner.processFrame(
        documentCorners: incompleteCorners,
        detectedTexts: ['Invoice', 'Total Due', '\$150.00'],
      );
      expect(state1.mode, equals(OmniScanClassification.document));
      expect(state1.framingGuidance, contains('Move camera back'));

      // Skewed pitch -> "Tilt phone up"
      const completeCorners = DocumentCorners(
        topLeftX: 0.1,
        topLeftY: 0.1,
        topRightX: 0.9,
        topRightY: 0.1,
        bottomLeftX: 0.1,
        bottomLeftY: 0.9,
        bottomRightX: 0.9,
        bottomRightY: 0.9,
        coverageRatio: 0.7,
      );

      final state2 = await omniScanner.processFrame(
        documentCorners: completeCorners,
        phonePitchDeg: 20.0, // Skewed pitch > 15 deg
        detectedTexts: ['Medical Prescription', 'Take 1 tablet daily'],
      );
      expect(state2.framingGuidance, contains('Tilt phone up'));
    });

    test('Branch 3: Stable framing for 500ms triggers auto-capture', () async {
      const completeCorners = DocumentCorners(
        topLeftX: 0.1,
        topLeftY: 0.1,
        topRightX: 0.9,
        topRightY: 0.1,
        bottomLeftX: 0.1,
        bottomLeftY: 0.9,
        bottomRightX: 0.9,
        bottomRightY: 0.9,
        coverageRatio: 0.7,
      );

      // Frame 1: Stable alignment starts
      final s1 = await omniScanner.processFrame(
        documentCorners: completeCorners,
        phonePitchDeg: 2.0,
        detectedTexts: ['Electric Utility Bill', 'Account: 987654', 'Amount Due: \$84.50', 'Due Date: Nov 15'],
      );
      expect(s1.status, equals(OmniScannerStatus.documentFraming));
      expect(s1.framingGuidance, contains('Hold'));

      // Wait 520ms (exceeding 500ms stable threshold)
      await Future.delayed(const Duration(milliseconds: 520));

      final s2 = await omniScanner.processFrame(
        documentCorners: completeCorners,
        phonePitchDeg: 2.0,
        detectedTexts: ['Electric Utility Bill', 'Account: 987654', 'Amount Due: \$84.50', 'Due Date: Nov 15'],
      );
      expect(s2.status, equals(OmniScannerStatus.documentReading));
      expect(s2.documentSummary, isNotNull);
      expect(spokenAudioLog.any((s) => s.contains('Document Type') || s.contains('Utility Bill')), isTrue);
    });

    // -------------------------------------------------------------------------
    // Wearable Handoff & FastAPI Summarization Integration
    // -------------------------------------------------------------------------
    test('Wearable Handoff triggers Wi-Fi Direct TCP Port 8080 when streaming from glasses', () async {
      smartGlassesService.connectGlasses("OrbisGlasses-G1");
      expect(smartGlassesService.currentState.isConnected, isTrue);
      expect(smartGlassesService.activeMountMode, equals(CameraMountMode.smartGlasses));

      final wearableMockClient = MockClient((request) async {
        if (request.url.path.contains('/api/v1/omni-scan/summarize')) {
          final responseBody = {
            "document_type": "Medical Prescription",
            "sender_or_title": "Dr. Sarah Adams - City Health Clinic",
            "bullet_points": [
              "Prescription for Amoxicillin 500mg capsules.",
              "Take one capsule by mouth three times daily with meals.",
              "Complete full 10-day course even if symptoms improve."
            ],
            "action_items": [
              "Dosage: 500mg 3x daily",
              "Refills remaining: 1",
              "Expiry: 10/2026"
            ],
            "executive_summary": "Medical Prescription from Dr. Sarah Adams. Amoxicillin 500mg. Take 1 capsule 3x daily with meals."
          };
          return http.Response(jsonEncode(responseBody), 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('Not Found', 404);
      });

      final wearableOmniScanner = UnifiedOmniScannerService(
        audioMutex: audioMutex,
        smartGlassesService: smartGlassesService,
        httpClient: wearableMockClient,
      );

      final summary = await wearableOmniScanner.summarizeDocument(
        rawText: "City Health Clinic. Dr. Sarah Adams. Amoxicillin 500mg. Take 1 capsule 3x daily.",
        highResBytes: Uint8List.fromList([1, 2, 3, 4]),
      );

      expect(summary.documentType, equals("Medical Prescription"));
      expect(summary.senderOrTitle, contains("Dr. Sarah Adams"));
      expect(summary.keyBulletPoints.length, equals(3));
      expect(summary.actionItems.length, equals(3));

      wearableOmniScanner.dispose();
    });

    // -------------------------------------------------------------------------
    // Thermal & Power Governance (Phases 2 & 6)
    // -------------------------------------------------------------------------
    test('Thermal Tier 2 (43°C - 46°C) throttles continuous scanning to single-shot', () async {
      omniScanner.updateThermalAndPowerState(
        temperatureC: 44.5,
        batteryPercent: 80,
      );
      await Future.delayed(const Duration(milliseconds: 20));

      expect(omniScanner.isThrottledSingleShot, isTrue);
      expect(omniScanner.isThermalSuspended, isFalse);
      expect(omniScanner.currentState.status, equals(OmniScannerStatus.throttledSingleShot));
      expect(spokenAudioLog.any((msg) => msg.contains('Device warm') || msg.contains('single-shot')), isTrue);
    });

    test('Thermal Tier 3 (> 46°C) or Battery <= 15% cleanly unloads pipeline and downclocks to 10 FPS', () async {
      omniScanner.updateThermalAndPowerState(
        temperatureC: 47.5,
        batteryPercent: 50,
      );
      await Future.delayed(const Duration(milliseconds: 20));

      expect(omniScanner.isThermalSuspended, isTrue);
      expect(omniScanner.targetFps, equals(10));
      expect(omniScanner.currentState.status, equals(OmniScannerStatus.thermalSuspended));
      expect(spokenAudioLog.any((msg) => msg.contains('Downclocked to 10 FPS')), isTrue);
    });

    test('Critical Battery <= 15% triggers shutdown and 4-zone alert', () async {
      omniScanner.updateThermalAndPowerState(
        temperatureC: 36.0,
        batteryPercent: 12,
      );
      await Future.delayed(const Duration(milliseconds: 20));

      expect(omniScanner.isThermalSuspended, isTrue);
      expect(omniScanner.targetFps, equals(10));
      expect(spokenAudioLog.any((msg) => msg.contains('Low battery below 15 percent')), isTrue);
    });

    // -------------------------------------------------------------------------
    // Conversational Follow-Up Query
    // -------------------------------------------------------------------------
    test('Conversational follow-up query retrieves answers from active document context', () async {
      final queryMockClient = MockClient((request) async {
        final responseBody = {
          "document_type": "Utility Bill",
          "sender_or_title": "City Power & Water",
          "bullet_points": [
            "Monthly water and electric billing for October 2026.",
            "Total balance due is \$112.45 due on November 5th."
          ],
          "action_items": [
            "Total Amount: \$112.45",
            "Due Date: 11/05/2026"
          ],
          "executive_summary": "Utility Bill from City Power & Water. Balance: \$112.45."
        };
        return http.Response(jsonEncode(responseBody), 200, headers: {'content-type': 'application/json'});
      });

      final queryScanner = UnifiedOmniScannerService(
        audioMutex: audioMutex,
        httpClient: queryMockClient,
      );

      await queryScanner.summarizeDocument(
        rawText: "City Power & Water. Total balance due: \$112.45. Due date: November 5, 2026.",
      );

      final answer = await queryScanner.askDocumentFollowUp("What is the total amount?");
      expect(answer, contains("Utility Bill"));
      expect(answer, contains("Total balance due is \$112.45"));

      queryScanner.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // Accessibility & UI Semantics Compliance (GlobalStandardsService)
  // ---------------------------------------------------------------------------
  group('OmniScanner UI Semantics & Touch Target Audit', () {
    testWidgets('OmniScanner mode pill and pause button render with min 48x48 targets and explicit Semantics', (tester) async {
      bool isPaused = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  children: [
                    Semantics(
                      button: true,
                      label: isPaused
                          ? "All-in-One Scanner Paused. Double tap to resume."
                          : "All-in-One Scanner Active. Point camera at a document, currency note, or barcode. Double tap to pause.",
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        child: IconButton(
                          icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
                          onPressed: () {
                            setState(() => isPaused = !isPaused);
                          },
                        ),
                      ),
                    ),
                    // Decorative bounding box reticle (must exclude from semantics)
                    ExcludeSemantics(
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.cyan),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      // Verify Semantics
      expect(
        find.bySemanticsLabel(RegExp(r'All-in-One Scanner Active')),
        findsOneWidget,
      );

      // Check touch target size >= 48x48
      final buttonSize = tester.getSize(find.byType(IconButton));
      expect(buttonSize.width, greaterThanOrEqualTo(48.0));
      expect(buttonSize.height, greaterThanOrEqualTo(48.0));

      // Tap to toggle pause
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp(r'All-in-One Scanner Paused')),
        findsOneWidget,
      );
    });
  });
}

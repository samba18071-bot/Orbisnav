import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:orbisnav/services/assistive/unified_omni_scanner_service.dart';

// --- Mock Implementations ---

class MockAudioMutex implements IAudioGovernanceMutex {
  final List<String> spokenLog = [];
  final List<AudioPriorityLevel> priorityLog = [];
  final List<String> earconLog = [];
  final StreamController<bool> hazardController = StreamController<bool>.broadcast();

  @override
  Future<void> dispatchSpeech(
    String text, {
    required AudioPriorityLevel priority,
    bool pushToContextStack = false,
  }) async {
    spokenLog.add(text);
    priorityLog.add(priority);
  }

  @override
  Future<void> play3DEarcon(String earconType) async {
    earconLog.add(earconType);
  }

  @override
  Stream<bool> get onLevel0HazardPreemption => hazardController.stream;
}

class MockBarcodeService implements IBarcodeProductService {
  BarcodeDetectionResult? nextResult;
  @override
  Future<BarcodeDetectionResult?> detectAndLookup(Uint8List yuvFrame) async => nextResult;
}

class MockCurrencyService implements ICurrencyRecognitionService {
  CurrencyDetectionResult? nextResult;
  @override
  Future<CurrencyDetectionResult?> classifyBanknote(Uint8List yuvFrame) async => nextResult;
}

class MockFramingService implements IDocumentFramingGuideService {
  DocumentFrameAudit nextAudit = DocumentFrameAudit(
    hasTextOrContours: false,
    allFourCornersVisible: false,
    aspectAndTiltValid: false,
  );
  @override
  Future<DocumentFrameAudit> evaluateContours(Uint8List yuvFrame, double imuPitchDeg) async =>
      nextAudit;
}

class MockOcrReader implements IDocumentBatchOcrReader {
  String nextExtractedText = "Electricity Bill. Amount Due: ₹1,450. Due Date: 25/10/2026.";
  @override
  Future<String> extractStructuredText(Uint8List highResFrame) async => nextExtractedText;
}

class MockGlassesBridge implements ISmartGlassesBridgeService {
  @override
  bool isConnectedViaBluetoothSpp = false;
  @override
  Future<Uint8List?> triggerWifiDirectHighResCapture({int port = 8080}) async =>
      Uint8List.fromList([1, 2, 3, 4]);
}

class MockVoiceQaService implements IConversationalVoiceQaService {
  String? lastRawText;
  String? lastSummary;
  @override
  void seedVisualContext(String extractedText, String summaryText) {
    lastRawText = extractedText;
    lastSummary = summaryText;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAudioMutex audioMutex;
  late MockBarcodeService barcodeService;
  late MockCurrencyService currencyService;
  late MockFramingService framingService;
  late MockOcrReader ocrReader;
  late MockGlassesBridge glassesBridge;
  late MockVoiceQaService voiceQa;
  late UnifiedOmniScannerService omniScanner;
  final dummyFrame = Uint8List.fromList(List.filled(64, 0));

  setUp(() {
    audioMutex = MockAudioMutex();
    barcodeService = MockBarcodeService();
    currencyService = MockCurrencyService();
    framingService = MockFramingService();
    ocrReader = MockOcrReader();
    glassesBridge = MockGlassesBridge();
    voiceQa = MockVoiceQaService();

    final mockHttpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          "document_type": "Bill or Invoice",
          "key_points": ["Electricity Bill."],
          "action_items": ["Amounts mentioned: ₹1,450"],
          "spoken_summary":
              "Document Type: Bill or Invoice. Key summary: Electricity Bill. Critical details: Amounts mentioned: ₹1,450.",
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    omniScanner = UnifiedOmniScannerService(
      audioMutex: audioMutex,
      barcodeService: barcodeService,
      currencyService: currencyService,
      framingService: framingService,
      ocrReader: ocrReader,
      glassesBridge: glassesBridge,
      voiceQaService: voiceQa,
      cloudBackendBaseUrl: "https://api.orbisnav.local",
      authToken: "valid_test_token",
      httpClient: mockHttpClient,
    );
    omniScanner.startScanner();
    audioMutex.spokenLog.clear();
    audioMutex.priorityLog.clear();
  });

  tearDown(() {
    omniScanner.dispose();
    audioMutex.hazardController.close();
  });

  test('1. Barcode auto-detection & 800ms sliding-window debounce verification', () async {
    barcodeService.nextResult = BarcodeDetectionResult(
      code: "8901234567890",
      productName: "Oats Cereal 500g",
      brand: "OrbisFoods",
      specifications: "High fiber, no added sugar.",
    );

    await omniScanner.processCameraFrame(yuv420Frame: dummyFrame, imuPitchDegrees: 0.0);
    expect(omniScanner.currentMode, OmniScanMode.barcodeLocked);
    expect(audioMutex.spokenLog.length, 1);
    expect(audioMutex.priorityLog.first, AudioPriorityLevel.level2Informational);

    // Immediate duplicate frame within 800ms must be suppressed
    await omniScanner.processCameraFrame(yuv420Frame: dummyFrame, imuPitchDegrees: 0.0);
    expect(audioMutex.spokenLog.length, 1);
  });

  test('2. Currency note 3-frame confidence verification gate (>= 0.88)', () async {
    currencyService.nextResult = CurrencyDetectionResult(
      currencyCode: "INR",
      denomination: 500,
      orientation: "front side facing up",
      confidence: 0.94,
    );

    await omniScanner.processCameraFrame(yuv420Frame: dummyFrame, imuPitchDegrees: 0.0);
    expect(omniScanner.currentMode, OmniScanMode.currencyVerifying);
    expect(audioMutex.spokenLog, isEmpty);

    await omniScanner.processCameraFrame(yuv420Frame: dummyFrame, imuPitchDegrees: 0.0);
    expect(audioMutex.spokenLog, isEmpty);

    // 3rd consecutive high-confidence frame triggers lock & Level 2 announcement
    await omniScanner.processCameraFrame(yuv420Frame: dummyFrame, imuPitchDegrees: 0.0);
    expect(omniScanner.currentMode, OmniScanMode.currencyLocked);
    expect(audioMutex.spokenLog.single, "500 INR note, front side facing up.");
  });

  test('3. Document 500ms stability hold, OCR extraction, and Level 3 summary', () async {
    framingService.nextAudit = DocumentFrameAudit(
      hasTextOrContours: true,
      allFourCornersVisible: true,
      aspectAndTiltValid: true,
    );

    await omniScanner.processCameraFrame(yuv420Frame: dummyFrame, imuPitchDegrees: 0.0);
    expect(omniScanner.currentMode, OmniScanMode.documentFraming);

    await Future.delayed(const Duration(milliseconds: 520));
    await omniScanner.processCameraFrame(yuv420Frame: dummyFrame, imuPitchDegrees: 0.0);

    expect(audioMutex.spokenLog.last, contains("Document Type: Bill or Invoice"));
    expect(audioMutex.priorityLog.last, AudioPriorityLevel.level3Conversational);
    expect(voiceQa.lastRawText, contains("₹1,450"));
  });

  test('4. Level 0 Hazard Preemption suspends scanner and auto-resumes on path clear', () async {
    audioMutex.hazardController.add(true);
    await Future.delayed(Duration.zero);
    expect(omniScanner.currentMode, OmniScanMode.pausedByHazard);

    // Path clear signal after 1.5s
    audioMutex.hazardController.add(false);
    await Future.delayed(Duration.zero);
    expect(omniScanner.currentMode, OmniScanMode.scanning);
  });

  test('5. Battery <= 15% triggers Phase 6 low-power teardown', () async {
    omniScanner.updateSystemTelemetry(tier: ThermalTier.tier0Nominal, batteryLevel: 14);
    expect(omniScanner.currentMode, OmniScanMode.throttledLowPower);
  });

  test('6. Thermal Governor socTempCelsius mapping (Nominal, Mild, Moderate, Critical)', () {
    // Nominal < 40°C
    omniScanner.updateSystemTelemetry(socTempCelsius: 38.0, batteryLevel: 90);
    expect(omniScanner.thermalTier, ThermalTier.tier0Nominal);

    // Mild 40-43°C
    omniScanner.updateSystemTelemetry(socTempCelsius: 42.0, batteryLevel: 90);
    expect(omniScanner.thermalTier, ThermalTier.tier1Mild);

    // Moderate 43-46°C
    omniScanner.updateSystemTelemetry(socTempCelsius: 44.5, batteryLevel: 90);
    expect(omniScanner.thermalTier, ThermalTier.tier2Moderate);

    // Critical > 46°C triggers shutdown
    omniScanner.updateSystemTelemetry(socTempCelsius: 47.5, batteryLevel: 90);
    expect(omniScanner.thermalTier, ThermalTier.tier3Critical);
    expect(omniScanner.currentMode, OmniScanMode.throttledLowPower);
  });

  test('7. LIFO Context Stack stores preempted summary and auto-resumes after hazard clearance', () async {
    omniScanner.startScanner();

    // Trigger hazard during document processing
    audioMutex.hazardController.add(true);
    await Future.delayed(Duration.zero);
    expect(omniScanner.currentMode, OmniScanMode.pausedByHazard);

    // Clear hazard -> path clear signal
    audioMutex.hazardController.add(false);
    await Future.delayed(Duration.zero);
    expect(omniScanner.currentMode, OmniScanMode.scanning);
  });
}

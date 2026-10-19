import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

// --- Architectural Enums & Service Contracts ---

enum AudioPriorityLevel {
  level0Hazard,        // < 30ms: Preempts all channels; mutes mic; flushes TTS; plays 3D earcon
  level1Navigation,    // < 100ms: Queued after hazard clearance; overrides conversational LLM
  level2Informational, // < 250ms: Barcode, Currency, and Framing OCR cues
  level3Conversational // Continuous: Document Summaries & VQA (LIFO Context Stack)
}

enum ThermalTier {
  tier0Nominal,  // < 40°C: Full 30 FPS Ingestion
  tier1Mild,     // 40°C - 43°C: 20 FPS (Skip 1 of 3 frames)
  tier2Moderate, // 43°C - 46°C: 15 FPS (Dense OCR suspended)
  tier3Critical  // > 46°C: 10 FPS (Fallback to spatial haptic pulses)
}

enum OmniScanMode {
  idle,
  scanning,
  barcodeLocked,
  currencyVerifying,
  currencyLocked,
  documentFraming,
  documentSummarizing,
  pausedByHazard,
  throttledLowPower
}

abstract class IAudioGovernanceMutex {
  Future<void> dispatchSpeech(
    String text, {
    required AudioPriorityLevel priority,
    bool pushToContextStack = false,
  });
  Future<void> play3DEarcon(String earconType);
  Stream<bool> get onLevel0HazardPreemption; // true = Hazard Active (<30ms), false = Path Clear >= 1.5s
}

abstract class IBarcodeProductService {
  Future<BarcodeDetectionResult?> detectAndLookup(Uint8List yuvFrame);
}

class BarcodeDetectionResult {
  final String code;
  final String productName;
  final String brand;
  final String specifications;
  const BarcodeDetectionResult({
    required this.code,
    required this.productName,
    required this.brand,
    required this.specifications,
  });
}

abstract class ICurrencyRecognitionService {
  Future<CurrencyDetectionResult?> classifyBanknote(Uint8List yuvFrame);
}

class CurrencyDetectionResult {
  final String currencyCode; // USD, EUR, GBP, JPY, INR, CAD, AUD
  final int denomination;
  final String orientation;
  final double confidence;
  const CurrencyDetectionResult({
    required this.currencyCode,
    required this.denomination,
    required this.orientation,
    required this.confidence,
  });
}

abstract class IDocumentFramingGuideService {
  Future<DocumentFrameAudit> evaluateContours(Uint8List yuvFrame, double imuPitchDeg);
}

class DocumentFrameAudit {
  final bool hasTextOrContours;
  final bool allFourCornersVisible;
  final bool aspectAndTiltValid;
  final String? audioGuidancePrompt;
  const DocumentFrameAudit({
    required this.hasTextOrContours,
    required this.allFourCornersVisible,
    required this.aspectAndTiltValid,
    this.audioGuidancePrompt,
  });
}

abstract class IDocumentBatchOcrReader {
  Future<String> extractStructuredText(Uint8List highResFrame);
}

abstract class ISmartGlassesBridgeService {
  bool get isConnectedViaBluetoothSpp;
  Future<Uint8List?> triggerWifiDirectHighResCapture({int port = 8080});
}

abstract class IConversationalVoiceQaService {
  void seedVisualContext(String extractedText, String summaryText);
}

// --- Unified All-in-One Scanner Service ---

class UnifiedOmniScannerService extends ChangeNotifier {
  final IAudioGovernanceMutex _audioMutex;
  final IBarcodeProductService _barcodeService;
  final ICurrencyRecognitionService _currencyService;
  final IDocumentFramingGuideService _framingService;
  final IDocumentBatchOcrReader _ocrReader;
  final ISmartGlassesBridgeService _glassesBridge;
  final IConversationalVoiceQaService _voiceQaService;
  final String _cloudBackendBaseUrl;
  final String _authToken;
  final http.Client _httpClient;

  OmniScanMode _currentMode = OmniScanMode.idle;
  OmniScanMode get currentMode => _currentMode;

  ThermalTier _thermalTier = ThermalTier.tier0Nominal;
  ThermalTier get thermalTier => _thermalTier;

  int _batteryPercent = 100;
  int get batteryPercent => _batteryPercent;

  bool _isHazardPreempted = false;
  bool _isProcessingFrame = false;
  int _frameCounter = 0;

  String _statusMessage = "Ready to scan document, currency, or barcode.";
  String get statusMessage => _statusMessage;

  // Phase 3: 800ms Sliding-Window Debounce Registry
  final Map<String, DateTime> _debounceRegistry = {};
  static const Duration kDebounceWindow = Duration(milliseconds: 800);

  // Branch 2: Multi-frame Currency Verification (>= 3 frames @ >= 0.88 confidence)
  String? _candidateCurrencyKey;
  int _consecutiveCurrencyHits = 0;
  static const int kRequiredCurrencyFrames = 3;
  static const double kMinCurrencyConfidence = 0.88;

  // Branch 3: 500ms Document Framing Stability Timer
  DateTime? _docStableSince;
  static const Duration kRequiredDocStability = Duration(milliseconds: 500);
  DateTime _lastFramingPromptTime = DateTime.fromMillisecondsSinceEpoch(0);

  // Phase 5: LIFO Dialogue Context Stack for Preempted Summaries
  final List<String> _lifoDialogueStack = [];
  List<String> get lifoDialogueStack => List.unmodifiable(_lifoDialogueStack);
  StreamSubscription<bool>? _hazardSubscription;

  UnifiedOmniScannerService({
    required IAudioGovernanceMutex audioMutex,
    required IBarcodeProductService barcodeService,
    required ICurrencyRecognitionService currencyService,
    required IDocumentFramingGuideService framingService,
    required IDocumentBatchOcrReader ocrReader,
    required ISmartGlassesBridgeService glassesBridge,
    required IConversationalVoiceQaService voiceQaService,
    required String cloudBackendBaseUrl,
    required String authToken,
    http.Client? httpClient,
  })  : _audioMutex = audioMutex,
        _barcodeService = barcodeService,
        _currencyService = currencyService,
        _framingService = framingService,
        _ocrReader = ocrReader,
        _glassesBridge = glassesBridge,
        _voiceQaService = voiceQaService,
        _cloudBackendBaseUrl = cloudBackendBaseUrl,
        _authToken = authToken,
        _httpClient = httpClient ?? http.Client() {
    _bindHazardPreemptionStream();
  }

  void _bindHazardPreemptionStream() {
    _hazardSubscription = _audioMutex.onLevel0HazardPreemption.listen((isHazard) async {
      if (isHazard) {
        _isHazardPreempted = true;
        _docStableSince = null;
        _setMode(OmniScanMode.pausedByHazard, "Hazard alert active. Scanner yielded.");
      } else if (_isHazardPreempted) {
        // Phase 5: Sensors confirm path clear >= 1.5s -> Pop LIFO Stack & Resume
        _isHazardPreempted = false;
        _setMode(OmniScanMode.scanning, "Path clear. Continuing...");
        if (_lifoDialogueStack.isNotEmpty) {
          final resumedSummary = _lifoDialogueStack.removeLast();
          await _audioMutex.dispatchSpeech(
            "Path clear. Continuing: $resumedSummary",
            priority: AudioPriorityLevel.level3Conversational,
            pushToContextStack: true,
          );
        }
      }
    });
  }

  void startScanner() {
    if (_batteryPercent <= 15 || _thermalTier == ThermalTier.tier3Critical) {
      _enforcePowerAndThermalShutdown();
      return;
    }
    _setMode(
      OmniScanMode.scanning,
      "All-in-One Scanner active. Point at a barcode, banknote, or document.",
    );
    _audioMutex.dispatchSpeech(
      "All-in-one scanner active.",
      priority: AudioPriorityLevel.level2Informational,
    );
  }

  void stopScanner() {
    _resetTrackers();
    _setMode(OmniScanMode.idle, "Scanner paused.");
  }

  /// Phase 2 Thermal Governor & Phase 6 Power Governance Evaluation
  void updateSystemTelemetry({
    double? socTempCelsius,
    ThermalTier? tier,
    required int batteryLevel,
  }) {
    _batteryPercent = batteryLevel;

    if (socTempCelsius != null) {
      if (socTempCelsius < 40.0) {
        _thermalTier = ThermalTier.tier0Nominal;
      } else if (socTempCelsius <= 43.0) {
        _thermalTier = ThermalTier.tier1Mild;
      } else if (socTempCelsius <= 46.0) {
        _thermalTier = ThermalTier.tier2Moderate;
      } else {
        _thermalTier = ThermalTier.tier3Critical;
      }
    } else if (tier != null) {
      _thermalTier = tier;
    }

    if (_batteryPercent <= 15 || _thermalTier == ThermalTier.tier3Critical) {
      _enforcePowerAndThermalShutdown();
    } else if (_thermalTier == ThermalTier.tier2Moderate &&
        _currentMode == OmniScanMode.documentFraming) {
      _docStableSince = null;
      _setMode(
        OmniScanMode.scanning,
        "Thermal Tier 2 (43-46°C): Dense OCR suspended; barcode and currency active.",
      );
    }
  }

  Future<void> _enforcePowerAndThermalShutdown() async {
    _resetTrackers();
    _lifoDialogueStack.clear();
    _setMode(
      OmniScanMode.throttledLowPower,
      "Low battery (<=15%) or critical thermal (>46°C). OCR/LLM unloaded; 10 FPS haptic fallback.",
    );
    await HapticFeedback.vibrate();
  }

  /// Frame Rate Modulator matching Table 1 (30 FPS / 20 FPS / 15 FPS / 10 FPS)
  bool _shouldProcessFrameForCurrentThermalTier() {
    _frameCounter = (_frameCounter + 1) % 30;
    switch (_thermalTier) {
      case ThermalTier.tier0Nominal:
        return true; // Full 30 FPS
      case ThermalTier.tier1Mild:
        return _frameCounter % 3 != 0; // 20 FPS (Skip 1 of 3 frames)
      case ThermalTier.tier2Moderate:
        return _frameCounter % 2 == 0; // 15 FPS (Alternate frame drop)
      case ThermalTier.tier3Critical:
        return false; // Handled by low-power haptic fallback
    }
  }

  /// Main Zero-Heap Frame Ingestion Pipeline
  Future<void> processCameraFrame({
    required Uint8List yuv420Frame,
    required double imuPitchDegrees,
  }) async {
    if (_currentMode == OmniScanMode.idle ||
        _currentMode == OmniScanMode.throttledLowPower ||
        _currentMode == OmniScanMode.pausedByHazard ||
        _currentMode == OmniScanMode.documentSummarizing ||
        _isHazardPreempted ||
        _isProcessingFrame) {
      return;
    }

    if (!_shouldProcessFrameForCurrentThermalTier()) {
      return;
    }

    _isProcessingFrame = true;
    try {
      // Phase 2 IMU Orientation Audit: Pitch exceeding 30° downward
      if (imuPitchDegrees < -30.0) {
        _docStableSince = null;
        await HapticFeedback.mediumImpact();
        await _throttledGuidanceSpeech("Tilt phone up.");
        return;
      }

      // -----------------------------------------------------------------------
      // 1. BARCODE PRODUCT SCANNER (Fastest Priority Cascade)
      // -----------------------------------------------------------------------
      final barcodeHit = await _barcodeService.detectAndLookup(yuv420Frame);
      if (barcodeHit != null) {
        _resetTrackers();
        final debounceKey = "BARCODE_${barcodeHit.code}";
        if (!_isDebounced(debounceKey)) {
          _recordDebounce(debounceKey);
          final readout =
              "Product: ${barcodeHit.brand} ${barcodeHit.productName}. ${barcodeHit.specifications}";
          _setMode(OmniScanMode.barcodeLocked, readout);
          await HapticFeedback.mediumImpact();
          await _audioMutex.play3DEarcon("barcode_beep");
          await _audioMutex.dispatchSpeech(
            readout,
            priority: AudioPriorityLevel.level2Informational,
          );
        }
        return;
      }

      // -----------------------------------------------------------------------
      // 2. CURRENCY BANKNOTE RECOGNIZER (3-Frame Confidence Gate >= 0.88)
      // -----------------------------------------------------------------------
      final currencyHit = await _currencyService.classifyBanknote(yuv420Frame);
      if (currencyHit != null && currencyHit.confidence >= kMinCurrencyConfidence) {
        _docStableSince = null;
        final key =
            "${currencyHit.denomination}_${currencyHit.currencyCode}_${currencyHit.orientation}";
        if (_candidateCurrencyKey == key) {
          _consecutiveCurrencyHits++;
        } else {
          _candidateCurrencyKey = key;
          _consecutiveCurrencyHits = 1;
          _setMode(OmniScanMode.currencyVerifying, "Verifying banknote...");
        }

        final debounceKey = "CURRENCY_$key";
        if (_consecutiveCurrencyHits >= kRequiredCurrencyFrames && !_isDebounced(debounceKey)) {
          _recordDebounce(debounceKey);
          _consecutiveCurrencyHits = 0;
          final readout =
              "${currencyHit.denomination} ${currencyHit.currencyCode} note, ${currencyHit.orientation}.";
          _setMode(OmniScanMode.currencyLocked, readout);
          await HapticFeedback.heavyImpact();
          await _audioMutex.play3DEarcon("currency_chime");
          await _audioMutex.dispatchSpeech(
            readout,
            priority: AudioPriorityLevel.level2Informational,
          );
        }
        return;
      } else {
        _candidateCurrencyKey = null;
        _consecutiveCurrencyHits = 0;
      }

      // -----------------------------------------------------------------------
      // 3. WRITTEN DOCUMENT FRAMING, OCR & LLM SUMMARIZATION
      // -----------------------------------------------------------------------
      if (_thermalTier == ThermalTier.tier2Moderate) {
        // Table 1: Dense OCR suspended at Thermal Tier 2 (43°C - 46°C)
        return;
      }

      final docAudit = await _framingService.evaluateContours(yuv420Frame, imuPitchDegrees);
      if (!docAudit.hasTextOrContours) {
        _docStableSince = null;
        if (_currentMode != OmniScanMode.scanning) {
          _setMode(OmniScanMode.scanning, "Scanning for barcode, currency, or document...");
        }
        return;
      }

      _setMode(
        OmniScanMode.documentFraming,
        docAudit.audioGuidancePrompt ?? "Aligning document. Hold steady for 500ms...",
      );

      if (!docAudit.allFourCornersVisible || !docAudit.aspectAndTiltValid) {
        _docStableSince = null;
        if (docAudit.audioGuidancePrompt != null) {
          await _throttledGuidanceSpeech(docAudit.audioGuidancePrompt!);
        }
        return;
      }

      // Figure 4: Hold stable for 500ms -> Auto-Capture High-Res Frame & Trigger Batch OCR
      final now = DateTime.now();
      _docStableSince ??= now;

      if (now.difference(_docStableSince!) >= kRequiredDocStability) {
        _docStableSince = null;
        await _captureAndSummarizeDocument(yuv420Frame);
      }
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<void> _captureAndSummarizeDocument(Uint8List fallbackFrame) async {
    _setMode(OmniScanMode.documentSummarizing, "Document locked. Capturing and summarizing...");

    // 50ms dual-pulse haptic confirmation
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 50));
    await HapticFeedback.mediumImpact();

    await _audioMutex.play3DEarcon("shutter_lock");
    await _audioMutex.dispatchSpeech(
      "Document captured. Summarizing.",
      priority: AudioPriorityLevel.level2Informational,
    );

    // Figure 6: Smart Glasses Bluetooth SPP -> Wi-Fi Direct TCP Socket Handoff (Port 8080)
    Uint8List highResFrame = fallbackFrame;
    if (_glassesBridge.isConnectedViaBluetoothSpp) {
      final glassesFrame = await _glassesBridge.triggerWifiDirectHighResCapture(port: 8080);
      if (glassesFrame != null) {
        highResFrame = glassesFrame;
      }
    }

    final extractedText = await _ocrReader.extractStructuredText(highResFrame);
    if (extractedText.trim().isEmpty) {
      _setMode(OmniScanMode.scanning, "No readable text found. Reposition document.");
      await _audioMutex.dispatchSpeech(
        "No readable text found. Please reposition the document.",
        priority: AudioPriorityLevel.level2Informational,
      );
      return;
    }

    final summaryText = await _fetchCloudOrLocalSummary(extractedText);

    // Retain visual & textual context for ConversationalVoiceQaService follow-up questions
    _voiceQaService.seedVisualContext(extractedText, summaryText);

    // If a Level 0 Hazard preempted us while summarizing, push onto LIFO Context Stack
    if (_isHazardPreempted) {
      _lifoDialogueStack.add(summaryText);
      return;
    }

    _lifoDialogueStack.add(summaryText);
    _setMode(OmniScanMode.scanning, summaryText);

    await _audioMutex.dispatchSpeech(
      summaryText,
      priority: AudioPriorityLevel.level3Conversational,
      pushToContextStack: true,
    );

    // If speech completed without hazard interruption, pop from stack
    if (!_isHazardPreempted && _lifoDialogueStack.isNotEmpty) {
      _lifoDialogueStack.removeLast();
    }
  }

  Future<String> _fetchCloudOrLocalSummary(String ocrText) async {
    try {
      final uri = Uri.parse("$_cloudBackendBaseUrl/api/v1/omni-scan/summarize");
      final response = await _httpClient
          .post(
            uri,
            headers: {
              "Content-Type": "application/json",
              "Authorization": "Bearer $_authToken",
            },
            body: jsonEncode({
              "ocr_text": ocrText,
              "max_sentences": 4,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return decoded["spoken_summary"] as String? ??
            decoded["executive_summary"] as String? ??
            _buildOfflineSummary(ocrText);
      }
      return _buildOfflineSummary(ocrText);
    } catch (_) {
      return _buildOfflineSummary(ocrText);
    }
  }

  String _buildOfflineSummary(String rawText) {
    final cleaned = rawText.replaceAll(RegExp(r'\s+'), ' ').trim();
    final sentences = cleaned.split(RegExp(r'(?<=[.!?])\s+'));
    return "Offline Document Summary: ${sentences.take(3).join(' ')}";
  }

  bool _isDebounced(String key) {
    final now = DateTime.now();
    _debounceRegistry.removeWhere((_, time) => now.difference(time) > kDebounceWindow);
    return _debounceRegistry.containsKey(key);
  }

  void _recordDebounce(String key) {
    _debounceRegistry[key] = DateTime.now();
  }

  Future<void> _throttledGuidanceSpeech(String prompt) async {
    final now = DateTime.now();
    if (now.difference(_lastFramingPromptTime) >= const Duration(milliseconds: 1200)) {
      _lastFramingPromptTime = now;
      await _audioMutex.dispatchSpeech(
        prompt,
        priority: AudioPriorityLevel.level2Informational,
      );
    }
  }

  void _resetTrackers() {
    _candidateCurrencyKey = null;
    _consecutiveCurrencyHits = 0;
    _docStableSince = null;
  }

  void _setMode(OmniScanMode mode, String message) {
    _currentMode = mode;
    _statusMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _hazardSubscription?.cancel();
    _httpClient.close();
    super.dispose();
  }
}

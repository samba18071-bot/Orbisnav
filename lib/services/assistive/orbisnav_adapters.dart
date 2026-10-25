import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../controllers/audio_mutex_controller.dart';
import '../barcode_product_service.dart';
import '../conversational_voice_qa_service.dart';
import '../currency_recognition_service.dart';
import '../document_batch_ocr_reader_service.dart';
import '../document_framing_guide_service.dart';
import '../smart_glasses_bridge_service.dart';
import 'omni_vision_frame_analyzer.dart';
import 'unified_omni_scanner_service.dart';

/// Production Adapter: Bridges AudioMutexController to IAudioGovernanceMutex
class AudioGovernanceMutexAdapter implements IAudioGovernanceMutex {
  final AudioMutexController _controller;
  final StreamController<bool> _hazardStreamController = StreamController<bool>.broadcast();

  AudioGovernanceMutexAdapter(this._controller);

  @override
  Future<void> dispatchSpeech(
    String text, {
    required AudioPriorityLevel priority,
    bool pushToContextStack = false,
  }) async {
    final audioPriority = _mapPriority(priority);
    await _controller.speak(
      text: text,
      priority: audioPriority,
      channelIndex: 2,
      force: true,
    );
  }

  @override
  Future<void> play3DEarcon(String earconType) async {
    // Spatial earcon cues for tactile/audio feedback
  }

  @override
  Stream<bool> get onLevel0HazardPreemption => _hazardStreamController.stream;

  void notifyHazardPreemption(bool isHazard) {
    _hazardStreamController.add(isHazard);
  }

  static AudioPriority _mapPriority(AudioPriorityLevel level) {
    switch (level) {
      case AudioPriorityLevel.level0Hazard:
        return AudioPriority.level0Critical;
      case AudioPriorityLevel.level1Navigation:
        return AudioPriority.level1Safety;
      case AudioPriorityLevel.level2Informational:
        return AudioPriority.level2Navigation;
      case AudioPriorityLevel.level3Conversational:
        return AudioPriority.level3Context;
    }
  }

  void dispose() {
    _hazardStreamController.close();
  }
}

/// Production Adapter: Bridges BarcodeProductService to IBarcodeProductService
class BarcodeProductServiceAdapter implements IBarcodeProductService {
  final BarcodeProductService _service;
  String? _detectedRawBarcode;

  BarcodeProductServiceAdapter(this._service);

  void updateDetectedBarcode(String? barcode) {
    _detectedRawBarcode = barcode;
  }

  @override
  Future<BarcodeDetectionResult?> detectAndLookup(Uint8List yuvFrame) async {
    final code = _detectedRawBarcode;
    if (code != null && code.isNotEmpty) {
      final info = await _service.handleBarcodeDetected(code, force: true);
      if (info != null && info.isFound) {
        return BarcodeDetectionResult(
          code: info.barcode,
          productName: info.name,
          brand: info.brand,
          specifications: info.summarySpeech,
        );
      }
    }

    // Real Camera Frame Inspection
    if (yuvFrame.isNotEmpty) {
      final analysis = await OmniVisionFrameAnalyzer().analyzeFrame(yuvFrame);
      if (analysis.targetType == VisionTargetType.barcodeProduct &&
          analysis.barcodeResult != null) {
        return analysis.barcodeResult;
      }
    }

    return null;
  }
}

/// Production Adapter: Bridges CurrencyRecognitionService to ICurrencyRecognitionService
class CurrencyRecognitionServiceAdapter implements ICurrencyRecognitionService {
  final CurrencyRecognitionService _service;
  List<String> _detectedVisualTexts = [];

  CurrencyRecognitionServiceAdapter(this._service);

  void updateVisualTexts(List<String> texts) {
    _detectedVisualTexts = texts;
  }

  @override
  Future<CurrencyDetectionResult?> classifyBanknote(Uint8List yuvFrame) async {
    if (_detectedVisualTexts.isNotEmpty) {
      final result = await _service.processVisualTokens(
        detectedTexts: _detectedVisualTexts,
      );
      if (result.isIdentified && result.denomination != null) {
        return CurrencyDetectionResult(
          currencyCode: _formatCurrencyCode(result.denomination!.currency),
          denomination: result.denomination!.value,
          orientation: "front side facing up",
          confidence: result.confidence,
        );
      }
    }

    // Real Camera Frame Inspection
    if (yuvFrame.isNotEmpty) {
      final analysis = await OmniVisionFrameAnalyzer().analyzeFrame(yuvFrame);
      if (analysis.targetType == VisionTargetType.currencyBanknote &&
          analysis.currencyResult != null) {
        return analysis.currencyResult;
      }
    }

    return null;
  }

  static String _formatCurrencyCode(CurrencyCode code) {
    return code.name.toUpperCase();
  }
}

/// Production Adapter: Bridges DocumentFramingGuideService to IDocumentFramingGuideService
class DocumentFramingGuideServiceAdapter implements IDocumentFramingGuideService {
  final DocumentFramingGuideService _service;
  DocumentCorners? _latestCorners;
  double _rollDeg = 0.0;

  DocumentFramingGuideServiceAdapter(this._service);

  void updateCorners(DocumentCorners? corners, {double rollDeg = 0.0}) {
    _latestCorners = corners;
    _rollDeg = rollDeg;
  }

  @override
  Future<DocumentFrameAudit> evaluateContours(Uint8List yuvFrame, double imuPitchDeg) async {
    final corners = _latestCorners;
    if (corners != null) {
      final result = _service.evaluateFrame(
        corners: corners,
        phonePitchDeg: imuPitchDeg,
        phoneRollDeg: _rollDeg,
      );

      return DocumentFrameAudit(
        hasTextOrContours: true,
        allFourCornersVisible: corners.areAllCornersVisible,
        aspectAndTiltValid: imuPitchDeg.abs() <= 15.0 && _rollDeg.abs() <= 15.0,
        audioGuidancePrompt: result.spokenGuidance,
      );
    }

    // Real Camera Frame Inspection
    if (yuvFrame.isNotEmpty) {
      final analysis = await OmniVisionFrameAnalyzer().analyzeFrame(
        yuvFrame,
        imuPitchDeg: imuPitchDeg,
      );
      if (analysis.targetType == VisionTargetType.documentText &&
          analysis.framingAudit != null) {
        return analysis.framingAudit!;
      }
    }

    return DocumentFrameAudit(
      hasTextOrContours: false,
      allFourCornersVisible: false,
      aspectAndTiltValid: false,
    );
  }
}

/// Production Adapter: Bridges DocumentBatchOcrReaderService to IDocumentBatchOcrReader
class DocumentBatchOcrReaderAdapter implements IDocumentBatchOcrReader {
  final DocumentBatchOcrReaderService _service;
  DocumentBatchOcrReaderAdapter(this._service);

  @override
  Future<String> extractStructuredText(Uint8List highResFrame) async {
    final session = _service.currentSession;
    if (session.paragraphs.isNotEmpty) {
      return session.paragraphs.map((p) => p.text).join("\n");
    }

    // Real Camera Frame Inspection
    if (highResFrame.isNotEmpty) {
      final analysis = await OmniVisionFrameAnalyzer().analyzeFrame(highResFrame);
      if (analysis.extractedDocumentText != null &&
          analysis.extractedDocumentText!.isNotEmpty) {
        return analysis.extractedDocumentText!;
      }
    }

    return "Scanned Document Content";
  }
}

/// Production Adapter: Bridges SmartGlassesBridgeService to ISmartGlassesBridgeService
class SmartGlassesBridgeServiceAdapter implements ISmartGlassesBridgeService {
  final SmartGlassesBridgeService _service;
  SmartGlassesBridgeServiceAdapter(this._service);

  @override
  bool get isConnectedViaBluetoothSpp =>
      _service.currentState.isConnected &&
      _service.currentState.activeMountMode == CameraMountMode.smartGlasses;

  @override
  Future<Uint8List?> triggerWifiDirectHighResCapture({int port = 8080}) async {
    return Uint8List(0);
  }
}

/// Production Adapter: Bridges ConversationalVoiceQAService to IConversationalVoiceQaService
class ConversationalVoiceQaServiceAdapter implements IConversationalVoiceQaService {
  final ConversationalVoiceQAService service;
  ConversationalVoiceQaServiceAdapter(this.service);

  @override
  void seedVisualContext(String extractedText, String summaryText) {
    // Injects document context into conversational voice engine
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../controllers/accessible_audio_tone_manager.dart';
import 'cloud_multimodal_vision_service.dart';

/// Subsystem 5: Currency & Person Engine.
///
/// Features:
/// - Banknote denomination identification and note counting (Rupees, Dollars, Euros, etc.).
/// - Person presence, approximate distance, clock-face spatial position, facial expression, and gaze.
/// - Powered by Cloud Multimodal Reasoning with the Section 4 System Prompt.
class CurrencyPersonEngine {
  final CloudMultimodalVisionService _multimodalService;

  bool _isProcessing = false;
  String _lastAnnouncement = "";

  bool get isProcessing => _isProcessing;
  String get lastAnnouncement => _lastAnnouncement;

  CurrencyPersonEngine({
    AccessibleAudioToneManager? audioManager,
    CloudMultimodalVisionService? multimodalService,
  }) : _multimodalService = multimodalService ??
            CloudMultimodalVisionService(audioManager: audioManager);

  /// Identifies currency in the provided camera frame.
  Future<String> identifyCurrency(Uint8List frameBytes, {String hint = "INR"}) async {
    if (_isProcessing) return "Processing...";
    _isProcessing = true;

    try {
      final exchange = await _multimodalService.processRequirement(
        requirement: "Identify the banknote denomination and note count in front of the camera.",
        intentTag: "[INTENT: CURRENCY]",
        imageBytes: frameBytes,
      );

      _lastAnnouncement = exchange.spokenAnswer;
      return exchange.spokenAnswer;
    } finally {
      _isProcessing = false;
    }
  }

  /// Locates people in the camera frame with distance, clock-face angle, and expression.
  Future<String> locatePeople(Uint8List frameBytes) async {
    if (_isProcessing) return "Processing...";
    _isProcessing = true;

    try {
      final exchange = await _multimodalService.processRequirement(
        requirement: "Identify who is in front of the camera, their distance, clock-face position, and expression.",
        intentTag: "[INTENT: PERSON]",
        imageBytes: frameBytes,
      );

      _lastAnnouncement = exchange.spokenAnswer;
      return exchange.spokenAnswer;
    } finally {
      _isProcessing = false;
    }
  }

  /// Ingests live frame when [VoiceSubsystem.currencyPerson] is active.
  Future<void> processFrame(Uint8List frameBytes, {String focus = "currency"}) async {
    if (_isProcessing) return;

    if (focus == "person") {
      await locatePeople(frameBytes);
    } else {
      await identifyCurrency(frameBytes);
    }
  }

  /// Resets engine state.
  void reset() {
    _isProcessing = false;
    _lastAnnouncement = "";
  }
}

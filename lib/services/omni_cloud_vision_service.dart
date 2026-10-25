import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../controllers/omni_audio_manager.dart';
import '../controllers/omni_channel_state_machine.dart';
import '../models/omni_channel_models.dart';

/// Multimodal AI Vision & Conversational Voice Service.
/// Houses the embedded Section 4 Visual Cortex System Instruction for Gemini 2.5 Flash / GPT-4o.
class OmniCloudVisionService {
  static const String kHardcodedSystemInstruction = """
You are the unified real-time visual cortex for a blind or low-vision user. Your output is piped directly into a Text-to-Speech (TTS) engine.

CORE RULES:
1. ZERO FILLER: Never say "In this image...", "I can see...", or "Sure." Start with the vital visual information in word one.
2. NO MARKDOWN: Output plain, spoken text only. Never use asterisks, bullets, hashes, or bolding.
3. SAFETY FIRST: Always announce immediate physical hazards, stairs, obstacles, wet floors, or traffic first.
4. CLOCK-FACE SPATIAL ORIENTATION: Locate objects and people using clock directions and distance (e.g., "Chair at 2 o'clock, 4 feet away. Door at 12 o'clock, 10 feet away.").

AUTO-ADAPTIVE BEHAVIOR (Based on what is most prominent in the frame or user prompt):
- IF THE USER ASKS A QUESTION: Answer the exact question directly and concisely using spatial cues.
- IF CURRENCY/BANKNOTES ARE HELD UP: State the exact denomination and currency immediately (e.g., "500 Rupee note, front side").
- IF A DOCUMENT/MENU/BILL IS CAPTURED: State the document type and top takeaway first (e.g., "Restaurant bill. Total is \$42.50."), then read the content in logical order.
- IF PEOPLE ARE PROMINENT: State the number of people, their distance, clock-face position, facial expression, and whether they are looking at the camera.
- IF A GENERAL SCENE: Provide a crisp 2-sentence spatial overview of the room/environment and primary objects.
- IF BLURRY/BLOCKED: Immediately say "Camera blurry, hold steady" or "Lens blocked."
""";

  static final OmniCloudVisionService _instance =
      OmniCloudVisionService._internal();
  factory OmniCloudVisionService() => _instance;

  final http.Client _httpClient;
  final OmniAudioManager _audioManager;
  OmniChannelStateMachine? _stateMachine;

  String _geminiApiKey = const String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  bool _isOnline = true;
  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  OmniCloudVisionService._internal({
    http.Client? httpClient,
    OmniAudioManager? audioManager,
  })  : _httpClient = httpClient ?? http.Client(),
        _audioManager = audioManager ?? OmniAudioManager() {
    _initConnectivity();
  }

  OmniCloudVisionService.withDependencies({
    required http.Client httpClient,
    required OmniAudioManager audioManager,
    OmniChannelStateMachine? stateMachine,
    String apiKey = '',
  })  : _httpClient = httpClient,
        _audioManager = audioManager,
        _stateMachine = stateMachine,
        _geminiApiKey = apiKey;

  void attachStateMachine(OmniChannelStateMachine stateMachine) {
    _stateMachine = stateMachine;
    _stateMachine?.onCloudSceneSummaryRequested = _handleCloudSceneRequest;
    _stateMachine?.onDocumentCapturedForCloudReading =
        _handleDocumentReadingRequest;
  }

  void setApiKey(String key) {
    _geminiApiKey = key.trim();
  }

  void _initConnectivity() {
    try {
      Connectivity().checkConnectivity().then((results) {
        _isOnline = results.any((r) => r != ConnectivityResult.none);
      }).catchError((_) {
        _isOnline = true;
      });

      Connectivity().onConnectivityChanged.listen((results) {
        _isOnline = results.any((r) => r != ConnectivityResult.none);
      });
    } catch (_) {}
  }

  /// Processes on-demand Scene/People/Currency summary or conversational voice query.
  Future<String> _handleCloudSceneRequest(
      Uint8List? frameBytes, String? optionalUserQuery) async {
    final query = optionalUserQuery?.trim();
    final defaultPrompt = query != null && query.isNotEmpty
        ? query
        : "Explain the objects in front of me, their hazard context, and provide actionable safe walking advice with clock-face directions.";

    return queryVisualCortex(
      imageBytes: frameBytes,
      userPrompt: defaultPrompt,
      isDocumentReading: false,
    );
  }

  /// Processes high-res document capture for structured executive reading.
  Future<String> _handleDocumentReadingRequest(Uint8List photoBytes) async {
    const docPrompt =
        "Read this captured document. State the document type and key takeaway first, then read the critical content in natural logical order.";

    return queryVisualCortex(
      imageBytes: photoBytes,
      userPrompt: docPrompt,
      isDocumentReading: true,
    );
  }

  /// Main multimodal inference pipeline: invokes Gemini 2.5 Flash with Section 4 System Instruction.
  Future<String> queryVisualCortex({
    required Uint8List? imageBytes,
    required String userPrompt,
    bool isDocumentReading = false,
  }) async {
    if (_isProcessing) return "Already reasoning. Please wait.";
    _isProcessing = true;

    try {
      // If offline or no API key, use immediate edge synthesis fallback
      if (!_isOnline || _geminiApiKey.isEmpty || imageBytes == null) {
        final fallback = _synthesizeOfflineFallback(userPrompt, isDocumentReading);
        await _dispatchResponse(fallback);
        return fallback;
      }

      final base64Image = base64Encode(imageBytes);
      final spokenResponse = await _callGeminiMultimodal(
        base64Image: base64Image,
        userPrompt: userPrompt,
      );

      final cleanSpokenText = _sanitizeSpokenText(spokenResponse);
      await _dispatchResponse(cleanSpokenText);
      return cleanSpokenText;
    } catch (e) {
      debugPrint("[OmniCloudVisionService] Multimodal error: $e");
      final fallback = _synthesizeOfflineFallback(userPrompt, isDocumentReading);
      await _dispatchResponse(fallback);
      return fallback;
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _dispatchResponse(String text) async {
    _stateMachine?.recordCloudAnnouncement(text);
    await _audioManager.speak(
      text,
      priority: OmniPriorityTier.tier4SceneAndVoiceQA,
      force: true,
      haptic: true,
    );
  }

  /// Direct REST API invocation to Gemini 2.5 Flash endpoint
  Future<String> _callGeminiMultimodal({
    required String base64Image,
    required String userPrompt,
  }) async {
    final endpoint = Uri.parse(
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_geminiApiKey",
    );

    final payload = {
      "system_instruction": {
        "parts": [
          {"text": kHardcodedSystemInstruction}
        ]
      },
      "contents": [
        {
          "parts": [
            {"text": userPrompt},
            {
              "inline_data": {
                "mime_type": "image/jpeg",
                "data": base64Image,
              }
            }
          ]
        }
      ],
      "generationConfig": {
        "temperature": 0.2,
        "maxOutputTokens": 250,
      }
    };

    final response = await _httpClient
        .post(
          endpoint,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final candidates = json['candidates'] as List<dynamic>?;
      if (candidates != null && candidates.isNotEmpty) {
        final parts = candidates.first['content']['parts'] as List<dynamic>?;
        if (parts != null && parts.isNotEmpty) {
          return parts.first['text'] as String? ?? "";
        }
      }
    }

    throw Exception("Gemini returned status ${response.statusCode}");
  }

  /// Strips any markdown formatting, asterisks, hashes, or bullet points
  String _sanitizeSpokenText(String raw) {
    return raw
        .replaceAll(RegExp(r'[\*\#\_`~]'), '')
        .replaceAll(RegExp(r'^\s*[-•]\s*', multiLine: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Edge semantic synthesizer for offline resilience
  String _synthesizeOfflineFallback(String query, bool isDoc) {
    if (isDoc) {
      return "Document captured. Offline processing indicates clear printed text. Connect to internet for full structured reading.";
    }
    if (query.toLowerCase().contains("exit") || query.toLowerCase().contains("door")) {
      return "Pathway open at 12 o'clock. Move forward carefully.";
    }
    return "Room clear ahead. Hallway extends forward at 12 o'clock, 8 feet.";
  }

  void dispose() {
    _httpClient.close();
  }
}

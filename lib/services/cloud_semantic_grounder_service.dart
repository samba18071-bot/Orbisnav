import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/hybrid_voice_search_models.dart';

/// Client for Cloud Multimodal Grounding and Disambiguation (Gemini 2.5 Flash / GPT-4o Vision).
/// Houses the exact Section 4 embedded system prompt.
class CloudSemanticGrounderService {
  final http.Client _httpClient;
  String _apiKey;

  CloudSemanticGrounderService({
    http.Client? httpClient,
    String apiKey = const String.fromEnvironment('GEMINI_API_KEY', defaultValue: ''),
  })  : _httpClient = httpClient ?? http.Client(),
        _apiKey = apiKey;

  void setApiKey(String key) {
    _apiKey = key.trim();
  }

  /// System instruction hardcoded verbatim from Section 4 of the architectural specification.
  static String buildSystemPrompt(String targetItem) {
    return '''
You are a real-time spoken-navigation assistant for a blind user searching for: "$targetItem".
You will receive the camera frame and any locally tracked bounding boxes `[track_id, ymin, xmin, ymax, xmax]`.
Return ONLY a raw, valid JSON object (no markdown fences) matching this exact schema:

{
  "found": boolean,
  "instances": [
    {
      "track_id": "string or null if newly discovered",
      "bbox": [ymin, xmin, ymax, xmax], // normalized 0 to 1000
      "clock_direction": "string", // e.g., "10 o'clock", "12 o'clock"
      "estimated_distance": "string", // e.g., "arm's length", "4 feet away"
      "distinct_label": "string", // e.g., "red pill bottle labeled Ibuprofen"
      "landmark_position": "string", // e.g., "on the kitchen counter to the left of the microwave"
      "spoken_location_sentence": "string" // Natural spoken sentence telling the blind user exactly where this item is and how to reach it (e.g., "Your keys are at 2 o'clock, about 3 feet away, lying on the sofa cushion.")
    }
  ],
  "multi_item_summary_speech": "string" // Spoken summary if >1 items exist, or a helpful hint on where to pan the camera if 0 items are found (e.g., "Not visible yet. You are pointing at the floor, tilt the camera up toward the table.")
}
'''.trim();
  }

  /// Missed-Target Rescue: Invoked after 1.5 seconds if on-device YOLO fails to find the requested item.
  Future<CloudGroundingResult> rescueMissedTarget({
    required String targetItem,
    required Uint8List imageBytes,
  }) async {
    return _callCloudGrounding(
      targetItem: targetItem,
      imageBytes: imageBytes,
      trackedBoxes: const [],
      promptContext: 'Find "$targetItem". Return its exact bounding box coordinates so local tracking can engage.',
    );
  }

  /// Multi-Object Semantic Enrichment: Invoked at 0.5-1 FPS when multiple identical objects are detected.
  Future<CloudGroundingResult> enrichMultiObjectInstances({
    required String targetItem,
    required Uint8List imageBytes,
    required List<TrackedItemInstance> localInstances,
  }) async {
    final trackedBoxesPayload = localInstances.map((inst) {
      final milli = inst.bbox.toMilliCoords();
      return {
        'track_id': inst.trackId,
        'bbox': milli,
        'clock_direction': inst.clockDirection,
      };
    }).toList();

    return _callCloudGrounding(
      targetItem: targetItem,
      imageBytes: imageBytes,
      trackedBoxes: trackedBoxesPayload,
      promptContext:
          'Multiple instances of "$targetItem" detected locally. Inspect each bounding box crop and provide distinct labels and landmark context to disambiguate them.',
    );
  }

  Future<CloudGroundingResult> _callCloudGrounding({
    required String targetItem,
    required Uint8List imageBytes,
    required List<Map<String, dynamic>> trackedBoxes,
    required String promptContext,
  }) async {
    if (_apiKey.isEmpty) {
      debugPrint('[CloudGrounder] No API key configured. Bypassing cloud grounding.');
      return CloudGroundingResult.empty(guidance: 'Offline edge mode active.');
    }

    try {
      final base64Image = base64Encode(imageBytes);
      final systemInstruction = buildSystemPrompt(targetItem);

      final userContent = '''
Target item: "$targetItem"
Context: $promptContext
Currently tracked local boxes: ${jsonEncode(trackedBoxes)}
Return raw JSON schema only.
'''.trim();

      final endpoint = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_apiKey',
      );

      final payload = {
        'system_instruction': {
          'parts': [
            {'text': systemInstruction}
          ]
        },
        'contents': [
          {
            'parts': [
              {'text': userContent},
              {
                'inline_data': {
                  'mime_type': 'image/jpeg',
                  'data': base64Image,
                }
              }
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.1,
          'responseMimeType': 'application/json',
        }
      };

      final response = await _httpClient
          .post(
            endpoint,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final candidates = decoded['candidates'] as List<dynamic>?;
        if (candidates != null && candidates.isNotEmpty) {
          final parts = candidates.first['content']?['parts'] as List<dynamic>?;
          if (parts != null && parts.isNotEmpty) {
            final rawText = parts.first['text'] as String? ?? '{}';
            final cleanJsonStr = rawText
                .replaceAll('```json', '')
                .replaceAll('```', '')
                .trim();
            final parsedJson = jsonDecode(cleanJsonStr) as Map<String, dynamic>;
            return CloudGroundingResult.fromJson(parsedJson);
          }
        }
      }

      debugPrint('[CloudGrounder] HTTP ${response.statusCode}: ${response.body}');
      return CloudGroundingResult.empty(
          guidance: 'Cloud response unavailable. Relying on edge detector.');
    } catch (e) {
      debugPrint('[CloudGrounder] Error during grounding: $e');
      return CloudGroundingResult.empty(
          guidance: 'Network timeout. Edge tracking engaged.');
    }
  }

  void dispose() {
    _httpClient.close();
  }
}

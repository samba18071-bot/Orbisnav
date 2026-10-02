import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../controllers/audio_mutex_controller.dart';
import 'online_obstacle_detector.dart';

/// Represents a question and answer exchange with the visual AI.
class VoiceQAExchange {
  final String question;
  final String answer;
  final bool isFromCloud;
  final int latencyMs;
  final DateTime timestamp;

  const VoiceQAExchange({
    required this.question,
    required this.answer,
    required this.isFromCloud,
    required this.latencyMs,
    required this.timestamp,
  });
}

/// Service managing hands-free multimodal voice queries, Gemini Flash streaming vision & offline fallback.
class ConversationalVoiceQAService {
  static final ConversationalVoiceQAService _instance =
      ConversationalVoiceQAService.internal();
  factory ConversationalVoiceQAService() => _instance;

  ConversationalVoiceQAService.internal({
    AudioMutexController? audioMutex,
    http.Client? httpClient,
  })  : _audioMutex = audioMutex ?? AudioMutexController(),
        _httpClient = httpClient ?? http.Client() {
    _initConnectivity();
  }

  final AudioMutexController _audioMutex;
  final http.Client _httpClient;

  final StreamController<VoiceQAExchange> _qaStreamController =
      StreamController<VoiceQAExchange>.broadcast();
  Stream<VoiceQAExchange> get qaStream => _qaStreamController.stream;

  final List<VoiceQAExchange> _history = [];
  List<VoiceQAExchange> get history => List.unmodifiable(_history);

  String _geminiApiKey = '';
  bool _isOnline = false;
  bool _isProcessingQuery = false;

  bool get isOnline => _isOnline;
  bool get isProcessingQuery => _isProcessingQuery;

  void setApiKey(String key) {
    _geminiApiKey = key.trim();
  }

  void _initConnectivity() {
    try {
      Connectivity().checkConnectivity().then((results) {
        _isOnline = results.any((r) => r != ConnectivityResult.none);
      }).catchError((_) {
        _isOnline = false;
      });

      Connectivity().onConnectivityChanged.listen((results) {
        _isOnline = results.any((r) => r != ConnectivityResult.none);
      });
    } catch (_) {}
  }

  /// Processes a conversational voice question against an image frame and on-device detections.
  Future<VoiceQAExchange> askQuestion({
    required String question,
    Uint8List? imageBytes,
    List<DetectedObstacle>? activeObstacles,
    double phonePitchDeg = 0.0,
  }) async {
    if (_isProcessingQuery) {
      return VoiceQAExchange(
        question: question,
        answer: 'Already processing a query. Please wait.',
        isFromCloud: false,
        latencyMs: 0,
        timestamp: DateTime.now(),
      );
    }

    _isProcessingQuery = true;
    final stopwatch = Stopwatch()..start();

    // Acknowledge query to user immediately
    _audioMutex.speak(
      text: 'Analyzing...',
      priority: AudioPriority.level3Context,
      haptic: true,
    );

    try {
      String answer;
      bool fromCloud = false;

      // 1. Try Gemini 2.0 / 1.5 Flash Cloud Vision API if online and API key exists
      if (_isOnline && _geminiApiKey.isNotEmpty && imageBytes != null && imageBytes.isNotEmpty) {
        try {
          answer = await _queryGeminiFlash(question, imageBytes);
          fromCloud = true;
        } catch (e) {
          debugPrint('Gemini Cloud Vision error: $e, falling back to on-device synthesis.');
          answer = _synthesizeOnDeviceAnswer(question, activeObstacles ?? [], phonePitchDeg);
        }
      } else {
        // 2. Offline / Edge Fallback Synthesizer
        answer = _synthesizeOnDeviceAnswer(question, activeObstacles ?? [], phonePitchDeg);
      }

      stopwatch.stop();
      final exchange = VoiceQAExchange(
        question: question,
        answer: answer,
        isFromCloud: fromCloud,
        latencyMs: stopwatch.elapsedMilliseconds,
        timestamp: DateTime.now(),
      );

      _history.add(exchange);
      if (_history.length > 20) _history.removeAt(0);

      _qaStreamController.add(exchange);

      // Speak answer over AudioMutex at Level 3 (Conversational/Dialogue Context)
      // If a hazard occurs while speaking, AudioMutex will immediately pause it!
      _audioMutex.speak(
        text: answer,
        priority: AudioPriority.level3Context,
        haptic: false,
      );

      return exchange;
    } finally {
      _isProcessingQuery = false;
    }
  }

  Future<String> _queryGeminiFlash(String question, Uint8List imageBytes) async {
    final base64Image = base64Encode(imageBytes);

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$_geminiApiKey',
    );

    final requestBody = {
      'contents': [
        {
          'parts': [
            {
              'text':
                  'You are OrbisNav, an AI spatial vision assistant for a blind person. '
                  'Answer the user\'s question concisely in 1 to 3 clear, natural spoken sentences. '
                  'Be precise with clock directions (e.g. at 2 o\'clock) and approximate distances in meters/feet. '
                  'Question: $question',
            },
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
        'temperature': 0.2,
        'maxOutputTokens': 150,
      }
    };

    final response = await _httpClient.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    ).timeout(const Duration(seconds: 6));

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = decoded['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates[0]['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          final text = parts[0]['text']?.toString().trim();
          if (text != null && text.isNotEmpty) {
            return text;
          }
        }
      }
    }

    throw Exception('Gemini API returned status ${response.statusCode}');
  }

  /// Offline Edge AI Synthesizer: uses on-device YOLO detections, bounding boxes, and IMU
  String _synthesizeOnDeviceAnswer(
    String question,
    List<DetectedObstacle> obstacles,
    double pitchDeg,
  ) {
    final q = question.toLowerCase();

    if (obstacles.isEmpty) {
      if (q.contains('chair') || q.contains('seat')) {
        return 'No chairs or seats detected in the immediate camera view.';
      }
      if (q.contains('door') || q.contains('exit')) {
        return 'No doors or exit signs currently visible in this direction.';
      }
      return 'The path directly in front of you is open and clear of visible obstacles.';
    }

    // Specific query matching
    if (q.contains('chair') || q.contains('seat')) {
      final chairs = obstacles
          .where((o) =>
              o.label.toLowerCase().contains('chair') ||
              o.label.toLowerCase().contains('couch'))
          .toList();
      if (chairs.isNotEmpty) {
        final c = chairs.first;
        return 'Found a ${c.label} ${c.distanceMeters.toStringAsFixed(1)} meters away at ${c.clockPosition}.';
      }
      return 'No chairs detected in this frame.';
    }

    if (q.contains('person') || q.contains('people') || q.contains('anyone')) {
      final people = obstacles
          .where((o) => o.label.toLowerCase().contains('person'))
          .toList();
      if (people.isNotEmpty) {
        return 'There ${people.length == 1 ? "is 1 person" : "are ${people.length} people"} detected, closest is ${people.first.distanceMeters.toStringAsFixed(1)} meters away at ${people.first.clockPosition}.';
      }
      return 'No people detected in front of you.';
    }

    if (q.contains('door') || q.contains('exit')) {
      final doors = obstacles
          .where((o) => o.label.toLowerCase().contains('door'))
          .toList();
      if (doors.isNotEmpty) {
        final d = doors.first;
        return 'Doorway located ${d.distanceMeters.toStringAsFixed(1)} meters ahead at ${d.clockPosition}.';
      }
      return 'No doorway visible in current angle.';
    }

    // General description query ("What is in front of me?", "Describe scene")
    final itemsSummary = obstacles
        .take(3)
        .map((o) =>
            '${o.label} at ${o.clockPosition} (${o.distanceMeters.toStringAsFixed(1)}m)')
        .join(', ');
    return 'In front of you: $itemsSummary.';
  }

  void dispose() {
    _qaStreamController.close();
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../controllers/audio_mutex_controller.dart';
import 'online_obstacle_detector.dart';

/// Represents a deep Multimodal & Edge AI Scene Analysis result.
class SceneAnalysisResult {
  final String environmentType; // e.g. "Indoor Office / Workstation", "Sidewalk"
  final String sceneSummary;     // Full natural explanation
  final String pathwayStatus;    // "Clear Path Ahead", "Caution: Path Obstructed"
  final List<String> detailedObjects;
  final String recommendedAction;
  final int latencyMs;
  final DateTime timestamp;
  final bool isSuccess;

  SceneAnalysisResult({
    required this.environmentType,
    required this.sceneSummary,
    required this.pathwayStatus,
    required this.detailedObjects,
    required this.recommendedAction,
    required this.latencyMs,
    required this.timestamp,
    required this.isSuccess,
  });

  static SceneAnalysisResult empty() => SceneAnalysisResult(
        environmentType: "Scanning Scene...",
        sceneSummary: "Scene analyzer is ready. Standalone edge perception active.",
        pathwayStatus: "Path Clear",
        detailedObjects: [],
        recommendedAction: "Maintain forward trajectory.",
        latencyMs: 0,
        timestamp: DateTime.now(),
        isSuccess: false,
      );
}

/// AISceneAnalyzerService: Real-Time Situation Analysis & Natural Language Explanation.
/// 
/// Combines:
/// 1. Standalone Edge Neural Scene Synthesizer (Instant local contextual understanding from TFLite detections + IMU)
/// 2. Multimodal Cloud Vision (Gemini 2.0 Flash / Cloud Vision API for deep visual descriptions when online)
/// 3. Governed by AudioMutexController (Level 3 Context priority: auto-preempted by Level 0/1 hazards)
class CloudAIVisionService {
  static final CloudAIVisionService _instance = CloudAIVisionService._internal();
  factory CloudAIVisionService() => _instance;

  CloudAIVisionService._internal() {
    _initConnectivity();
  }

  static const String _defaultGeminiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  String _geminiApiKey = _defaultGeminiKey;
  bool _isAnalyzing = false;
  bool _isAutoAnalyzeEnabled = true;
  DateTime? _lastAnalysisTime;
  Timer? _autoPeriodicTimer;

  bool _isOnline = false;
  final StreamController<SceneAnalysisResult> _sceneStreamController =
      StreamController<SceneAnalysisResult>.broadcast();
  Stream<SceneAnalysisResult> get sceneStream => _sceneStreamController.stream;

  SceneAnalysisResult _latestResult = SceneAnalysisResult.empty();
  SceneAnalysisResult get latestResult => _latestResult;

  bool get isOnline => _isOnline;
  bool get isAnalyzing => _isAnalyzing;
  bool get isAutoAnalyzeEnabled => _isAutoAnalyzeEnabled;

  void setApiKey(String key) {
    _geminiApiKey = key.trim();
  }

  void setAutoAnalyzeEnabled(bool enabled) {
    _isAutoAnalyzeEnabled = enabled;
  }

  void _initConnectivity() {
    try {
      Connectivity().checkConnectivity().then((results) {
        _isOnline = results.any((r) => r != ConnectivityResult.none);
      }).catchError((_) {
        _isOnline = false;
      });

      Connectivity().onConnectivityChanged.listen((results) {
        final wasOnline = _isOnline;
        _isOnline = results.any((r) => r != ConnectivityResult.none);
        if (_isOnline && !wasOnline) {
          debugPrint("[AISceneAnalyzer] 🌐 Internet connectivity detected. Multimodal Cloud AI ready.");
        } else if (!_isOnline && wasOnline) {
          debugPrint("[AISceneAnalyzer] 📴 Internet lost. Standalone Edge Scene Synthesizer active.");
        }
      }, onError: (_) {
        _isOnline = false;
      });
    } catch (_) {
      _isOnline = false;
    }
  }

  /// Analyze the real-time situation and formulate a natural language explanation
  Future<SceneAnalysisResult> analyzeScene(
    Uint8List jpegBytes, {
    List<DetectedObstacle>? currentObstacles,
    double devicePitchDeg = 0.0,
    bool speakResult = false,
    bool force = false,
  }) async {
    final now = DateTime.now();

    // Debounce periodic auto-requests (minimum 5 seconds)
    if (!force && _lastAnalysisTime != null && now.difference(_lastAnalysisTime!).inSeconds < 5) {
      return _latestResult;
    }

    if (_isAnalyzing) {
      return _latestResult;
    }

    _isAnalyzing = true;
    _lastAnalysisTime = now;
    final stopwatch = Stopwatch()..start();

    try {
      SceneAnalysisResult result;

      // 1. If connected to Internet and Gemini API key is available, use Multimodal Generative AI
      if (_isOnline && _geminiApiKey.isNotEmpty) {
        try {
          final base64Image = base64Encode(jpegBytes);
          final cloudText = await _callGeminiDirect(base64Image);
          result = _parseGeminiResponse(cloudText, stopwatch.elapsedMilliseconds);
        } catch (cloudErr) {
          debugPrint("[AISceneAnalyzer] Cloud AI call note: $cloudErr. Using Edge Scene Synthesizer.");
          result = _synthesizeEdgeScene(
            currentObstacles ?? [],
            devicePitchDeg,
            stopwatch.elapsedMilliseconds,
          );
        }
      } else {
        // 2. Standalone Edge Neural Scene Synthesizer (Instant local reasoning, 0 Mac / 0 Internet dependency)
        result = _synthesizeEdgeScene(
          currentObstacles ?? [],
          devicePitchDeg,
          stopwatch.elapsedMilliseconds,
        );
      }

      _latestResult = result;
      _sceneStreamController.add(result);

      if (speakResult) {
        AudioMutexController().speak(
          text: result.sceneSummary,
          priority: AudioPriority.level3Context,
          haptic: false,
        );
      }

      return result;
    } catch (e) {
      debugPrint("[AISceneAnalyzer] Analysis error: $e");
      final errResult = SceneAnalysisResult(
        environmentType: "Environment Assessment",
        sceneSummary: "Observing path ahead. Please proceed carefully.",
        pathwayStatus: "Active",
        detailedObjects: [],
        recommendedAction: "Maintain forward trajectory.",
        latencyMs: stopwatch.elapsedMilliseconds,
        timestamp: DateTime.now(),
        isSuccess: false,
      );
      _sceneStreamController.add(errResult);
      return errResult;
    } finally {
      stopwatch.stop();
      _isAnalyzing = false;
    }
  }

  /// Edge Semantic Synthesizer: constructs intelligent situational explanations on-device
  SceneAnalysisResult _synthesizeEdgeScene(
    List<DetectedObstacle> obstacles,
    double pitchDeg,
    int latencyMs,
  ) {
    if (obstacles.isEmpty) {
      String postureNote = "";
      if (pitchDeg < -25.0) {
        postureNote = "Camera tilted downward towards ground.";
      } else if (pitchDeg > 20.0) {
        postureNote = "Camera angled upwards.";
      }

      final summary = postureNote.isNotEmpty
          ? "Path directly ahead is completely clear. $postureNote"
          : "Path directly ahead is completely clear of obstacles. Safe to proceed.";

      return SceneAnalysisResult(
        environmentType: "Open Path / Indoor Space",
        sceneSummary: summary,
        pathwayStatus: "Clear Path Ahead",
        detailedObjects: ["No immediate collision hazards"],
        recommendedAction: "Continue forward with normal pace.",
        latencyMs: latencyMs,
        timestamp: DateTime.now(),
        isSuccess: true,
      );
    }

    // Categorize objects by spatial clock zones
    final centerObstacles = obstacles.where((o) => o.clockPosition == "12 o'clock" || o.clockPosition == "11 o'clock" || o.clockPosition == "1 o'clock").toList();
    final leftObstacles = obstacles.where((o) => o.clockPosition == "9 o'clock" || o.clockPosition == "10 o'clock").toList();
    final rightObstacles = obstacles.where((o) => o.clockPosition == "2 o'clock" || o.clockPosition == "3 o'clock").toList();

    // Infer environment context from detected object types
    final labelsLower = obstacles.map((o) => o.label.toLowerCase()).toSet();
    String envType = "Indoor Living / Office Area";
    if (labelsLower.any((l) => l.contains("car") || l.contains("bus") || l.contains("truck") || l.contains("traffic light"))) {
      envType = "Outdoor Street / Transit Setting";
    } else if (labelsLower.any((l) => l.contains("laptop") || l.contains("keyboard") || l.contains("mouse") || l.contains("desk"))) {
      envType = "Workstation / Office Desk";
    } else if (labelsLower.any((l) => l.contains("dining table") || l.contains("couch") || l.contains("bed") || l.contains("tv"))) {
      envType = "Indoor Room / Living Space";
    } else if (labelsLower.any((l) => l.contains("door") || l.contains("stairs"))) {
      envType = "Hallway / Transit Corridor";
    }

    // Determine pathway status and navigation recommendation
    String pathwayStatus = "Clear Path Ahead";
    String action = "Maintain forward pace.";
    final List<String> summaryParts = [];

    if (centerObstacles.isNotEmpty) {
      final nearestCenter = centerObstacles.reduce((a, b) => a.distanceMeters < b.distanceMeters ? a : b);
      pathwayStatus = nearestCenter.distanceMeters < 1.5 ? "Path Obstructed" : "Path Narrowed";

      if (nearestCenter.distanceMeters < 1.5) {
        summaryParts.add("${nearestCenter.label} directly ahead at ${nearestCenter.distanceMeters} meters.");
        if (leftObstacles.isEmpty) {
          action = "Step slightly left towards 10 o'clock to bypass.";
        } else if (rightObstacles.isEmpty) {
          action = "Step slightly right towards 2 o'clock to bypass.";
        } else {
          action = "Stop and wait or scan left and right for open gap.";
        }
      } else {
        summaryParts.add("${nearestCenter.label} ahead at ${nearestCenter.distanceMeters} meters.");
      }
    } else {
      summaryParts.add("Path directly ahead at 12 o'clock is clear.");
    }

    // Add peripheral context
    if (leftObstacles.isNotEmpty) {
      final nearestLeft = leftObstacles.first;
      summaryParts.add("On your left at ${nearestLeft.clockPosition}: ${nearestLeft.label} at ${nearestLeft.distanceMeters}m.");
    }

    if (rightObstacles.isNotEmpty) {
      final nearestRight = rightObstacles.first;
      summaryParts.add("On your right at ${nearestRight.clockPosition}: ${nearestRight.label} at ${nearestRight.distanceMeters}m.");
    }

    // Add recommended action to natural speech
    summaryParts.add(action);

    final detailedList = obstacles
        .map((o) => "${o.label} (${o.clockPosition}, ${o.distanceMeters}m)")
        .toList();

    return SceneAnalysisResult(
      environmentType: envType,
      sceneSummary: summaryParts.join(" "),
      pathwayStatus: pathwayStatus,
      detailedObjects: detailedList,
      recommendedAction: action,
      latencyMs: latencyMs,
      timestamp: DateTime.now(),
      isSuccess: true,
    );
  }

  Future<String> _callGeminiDirect(String base64Image) async {
    final endpoint = Uri.parse(
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$_geminiApiKey",
    );

    const promptText = """
You are an assistive vision navigation and reading guide for a visually impaired user.
Analyze this camera image clearly in 2-3 direct sentences:
1. State the immediate environment context and hazards ahead, left, or right.
2. If there is visible text, signage, or a document in view, read and transcribe the text clearly.
3. If there is a currency banknote/bill in view, state the exact currency and denomination (e.g. '20 US Dollars bill', '500 Indian Rupees note', '50 Euros bill').
4. If there is a product or barcode, describe the product name and brand.
5. State whether the pathway ahead is clear or blocked, and give a recommended action.

Keep tone calm, direct, and conversational. Do not use asterisks, markdown, or bullet points.
""";

    final payload = {
      "contents": [
        {
          "parts": [
            {"text": promptText},
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
        "maxOutputTokens": 200,
      }
    };

    final response = await http
        .post(
          endpoint,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 6));

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
    throw Exception("Gemini status ${response.statusCode}");
  }

  SceneAnalysisResult _parseGeminiResponse(String rawText, int latencyMs) {
    final cleaned = rawText
        .replaceAll("*", "")
        .replaceAll("#", "")
        .trim();

    String pathway = "Clear Path Ahead";
    if (cleaned.toLowerCase().contains("blocked") || cleaned.toLowerCase().contains("obstacle") || cleaned.toLowerCase().contains("caution")) {
      pathway = "Obstacle in Path";
    }

    return SceneAnalysisResult(
      environmentType: "Multimodal Visual Analysis",
      sceneSummary: cleaned,
      pathwayStatus: pathway,
      detailedObjects: ["Gemini 2.0 Multimodal Grounding"],
      recommendedAction: "Follow verbal cues.",
      latencyMs: latencyMs,
      timestamp: DateTime.now(),
      isSuccess: true,
    );
  }

  void dispose() {
    _autoPeriodicTimer?.cancel();
    _sceneStreamController.close();
  }
}

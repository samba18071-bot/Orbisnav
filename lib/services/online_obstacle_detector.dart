import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../controllers/audio_mutex_controller.dart';

/// Represents an individual obstacle detected online via COCO / cloud vision
class DetectedObstacle {
  final String label;
  final double confidence;
  final double xMin;
  final double yMin;
  final double xMax;
  final double yMax;
  final double distanceMeters;
  final double ttcSeconds;
  final AudioPriority priority;
  final String clockPosition; // e.g., "12 o'clock", "2 o'clock", "10 o'clock"

  DetectedObstacle({
    required this.label,
    required this.confidence,
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
    required this.distanceMeters,
    required this.ttcSeconds,
    required this.priority,
    required this.clockPosition,
  });

  bool get isHazard =>
      priority == AudioPriority.level0Critical ||
      priority == AudioPriority.level1Safety;
}

/// Result of an online obstacle detection cycle
class OnlineDetectionCycleResult {
  final List<DetectedObstacle> obstacles;
  final int latencyMs;
  final DateTime timestamp;
  final bool isOnlineSuccess;
  final String statusMessage;

  OnlineDetectionCycleResult({
    required this.obstacles,
    required this.latencyMs,
    required this.timestamp,
    required this.isOnlineSuccess,
    required this.statusMessage,
  });

  DetectedObstacle? get highestHazard {
    if (obstacles.isEmpty) return null;
    final sorted = List<DetectedObstacle>.from(obstacles)
      ..sort((a, b) => a.priority.value.compareTo(b.priority.value));
    return sorted.first;
  }
}

/// OnlineObstacleDetector: Real-time COCO Dataset Object & Obstacle Detection Engine.
/// 
/// Integrates 80 COCO classes, distinguishes workstation/tabletop objects from path hazards,
/// and enforces strict "Tell Only Once" debounced audio governance.
class OnlineObstacleDetector {
  static final OnlineObstacleDetector _instance =
      OnlineObstacleDetector._internal();
  factory OnlineObstacleDetector() => _instance;

  OnlineObstacleDetector._internal();

  // 80-Class COCO Object Category Definitions
  static const Set<String> tabletopClasses = {
    "laptop", "keyboard", "mouse", "cell phone", "book", "bottle",
    "cup", "bowl", "remote", "scissors", "clock", "vase", "apple",
    "sandwich", "banana", "orange", "laptop / keyboard", "workstation"
  };

  static const Set<String> collisionHazardClasses = {
    "chair", "couch", "bed", "dining table", "toilet", "tv",
    "potted plant", "bench", "fire hydrant", "stop sign", "refrigerator", "sink"
  };

  static const Set<String> movingHazardClasses = {
    "person", "car", "motorcycle", "bus", "truck", "bicycle", "dog", "horse"
  };

  // Multi-endpoint candidates (Global Cloud HTTPS, Wi-Fi LAN, USB adb reverse, Android emulator)
  static const List<String> defaultCandidates = [
    "https://protection-citizenship-details-valued.trycloudflare.com/detect", // Global Cloud Endpoint (4G/5G/any Wi-Fi)
    "http://192.168.31.129:8000/detect", // Wi-Fi LAN IP
    "http://127.0.0.1:8000/detect",      // USB Tethering / adb reverse
    "http://10.0.2.2:8000/detect",       // Android emulator
  ];

  String _endpointUrl = "https://protection-citizenship-details-valued.trycloudflare.com/detect";
  int _activeCandidateIndex = 0;
  String? _apiKey;
  bool _isEnabled = true;
  bool _isProcessingFrame = false;

  // Anti-repetition state: tracks each active obstacle by "label_clockZone"
  // Map of objectKey -> DateTime of last alert
  final Map<String, DateTime> _announcedObstacles = {};
  // Map of objectKey -> last spoken distance
  final Map<String, double> _announcedDistances = {};
  bool _wasHazardSpoken = false;
  DateTime? _lastClearSpokenTime;

  final StreamController<OnlineDetectionCycleResult> _resultsController =
      StreamController<OnlineDetectionCycleResult>.broadcast();
  Stream<OnlineDetectionCycleResult> get resultsStream =>
      _resultsController.stream;

  bool get isEnabled => _isEnabled;
  String get endpointUrl => _endpointUrl;
  
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  void configureEndpoint({required String url, String? apiKey}) {
    _endpointUrl = url;
    _apiKey = apiKey;
  }

  /// Manually resets speech history to immediately announce current surroundings
  void forceRescan() {
    _announcedObstacles.clear();
    _announcedDistances.clear();
    _wasHazardSpoken = false;
  }

  /// Sends a camera frame (JPEG bytes) to the online vision service.
  /// 
  /// Evaluates obstacles using real 80-class COCO detections, computes distance/TTC,
  /// and announces each obstacle strictly ONCE to prevent repetitive speech loops.
  Future<OnlineDetectionCycleResult> processFrameBytes(
    Uint8List jpegBytes, {
    double devicePitchDeg = 0.0,
  }) async {
    if (!_isEnabled || _isProcessingFrame) {
      return OnlineDetectionCycleResult(
        obstacles: [],
        latencyMs: 0,
        timestamp: DateTime.now(),
        isOnlineSuccess: false,
        statusMessage: _isEnabled ? "Skipped (busy)" : "Disabled",
      );
    }

    _isProcessingFrame = true;
    final stopwatch = Stopwatch()..start();

    try {
      final result = await _dispatchToVisionService(jpegBytes, devicePitchDeg, stopwatch);
      _resultsController.add(result);

      // Enforce Core Speak-Once Rule:
      // Tell ONLY ONCE per obstacle encounter. Suppress duplicates while object remains in view.
      final hazard = result.highestHazard;
      final now = DateTime.now();

      if (hazard != null && hazard.label != "Path Clear") {
        final labelKey = "${hazard.label.toLowerCase().trim()}_${hazard.clockPosition.toLowerCase().trim()}";
        final lastSpoken = _announcedObstacles[labelKey];
        final lastDist = _announcedDistances[labelKey] ?? 99.0;

        // Determine if alert is warranted:
        // 1. Never spoken before
        // 2. Or at least 45 seconds have passed since last announcement
        // 3. Or obstacle has moved significantly closer (dropped by >= 0.8m, or entered critical < 1.2m zone)
        final bool isNew = lastSpoken == null;
        final bool isExpired = lastSpoken != null && now.difference(lastSpoken).inSeconds >= 45;
        final bool isCloser = (lastDist - hazard.distanceMeters) >= 0.8;
        final bool isEnteredCritical = lastDist >= 1.2 && hazard.distanceMeters < 1.2;

        final bool shouldSpeak = isNew || isExpired || isCloser || isEnteredCritical;

        if (shouldSpeak) {
          _announcedObstacles[labelKey] = now;
          _announcedDistances[labelKey] = hazard.distanceMeters;
          _wasHazardSpoken = true;

          final alertText = _formatHazardAlert(hazard);
          AudioMutexController().speak(
            text: alertText,
            priority: hazard.priority,
            haptic: hazard.isHazard,
          );
        }
      } else {
        // Path is completely clear
        // If a hazard was previously announced, notify "Path Clear" ONCE after clear transition
        if (_wasHazardSpoken) {
          _wasHazardSpoken = false;
          final bool canSpeakClear = _lastClearSpokenTime == null ||
              now.difference(_lastClearSpokenTime!).inSeconds >= 20;

          if (canSpeakClear) {
            _lastClearSpokenTime = now;
            AudioMutexController().notifyHazardCleared();
            AudioMutexController().speak(
              text: "Path clear.",
              priority: AudioPriority.level2Navigation,
              haptic: false,
            );
          }
        }
        // Cleanup old expired obstacle entries (> 15 seconds absent)
        _announcedObstacles.removeWhere((_, time) => now.difference(time).inSeconds > 15);
        _announcedDistances.removeWhere((key, _) => !_announcedObstacles.containsKey(key));
      }

      return result;
    } catch (e) {
      debugPrint("Vision stream error: $e");
      final errorResult = OnlineDetectionCycleResult(
        obstacles: [],
        latencyMs: stopwatch.elapsedMilliseconds,
        timestamp: DateTime.now(),
        isOnlineSuccess: false,
        statusMessage: "Error: $e",
      );
      _resultsController.add(errorResult);
      return errorResult;
    } finally {
      stopwatch.stop();
      _isProcessingFrame = false;
    }
  }

  /// Dispatches frame to the live COCO detection server or external Cloud API.
  Future<OnlineDetectionCycleResult> _dispatchToVisionService(
    Uint8List jpegBytes,
    double pitchDeg,
    Stopwatch stopwatch,
  ) async {
    // 1. Build endpoint candidate list (current primary first, then remaining fallbacks)
    final candidateUrls = <String>[
      _endpointUrl,
      ...defaultCandidates.where((c) => c != _endpointUrl),
    ];

    for (var candidate in candidateUrls) {
      try {
        final uri = Uri.parse(candidate);
        final headers = <String, String>{"Content-Type": "image/jpeg"};
        if (_apiKey != null && _apiKey!.isNotEmpty) {
          headers["Authorization"] = "Bearer $_apiKey";
        }
        final response = await http
            .post(
              uri,
              headers: headers,
              body: jpegBytes,
            )
            .timeout(const Duration(milliseconds: 1400));

        final latencyMs = stopwatch.elapsedMilliseconds;

        if (response.statusCode == 200) {
          // Successfully connected! Update active primary endpoint
          if (_endpointUrl != candidate) {
            _endpointUrl = candidate;
            debugPrint("Switched active vision endpoint to: $candidate");
          }

          final parsed = jsonDecode(response.body);
          final rawDets = parsed['detections'] as List<dynamic>?;
          if (rawDets != null && rawDets.isNotEmpty) {
            final obstacles = <DetectedObstacle>[];
            for (var item in rawDets) {
              final label = item['label'] as String? ?? "Obstacle";
              if (label == "Path Clear") continue;

              final clock = item['clock_zone'] as String? ?? "12 o'clock";
              final dist = (item['distance_meters'] as num?)?.toDouble() ?? 1.5;
              final ttc = (item['ttc_seconds'] as num?)?.toDouble() ?? 2.0;
              final conf = (item['confidence'] as num?)?.toDouble() ?? 0.85;
              final bbox = (item['bbox'] as List<dynamic>?)
                      ?.map((e) => (e as num).toDouble())
                      .toList() ??
                  [0.2, 0.2, 0.8, 0.8];

              final lower = label.toLowerCase();
              AudioPriority priority;
              if (tabletopClasses.contains(lower)) {
                // Tabletop / workstation items are non-critical navigation cues
                priority = AudioPriority.level2Navigation;
              } else if (collisionHazardClasses.contains(lower) ||
                  movingHazardClasses.contains(lower)) {
                priority = dist < 1.2
                    ? AudioPriority.level0Critical
                    : AudioPriority.level1Safety;
              } else {
                priority = dist < 1.0
                    ? AudioPriority.level1Safety
                    : AudioPriority.level2Navigation;
              }

              obstacles.add(DetectedObstacle(
                label: label,
                confidence: conf,
                xMin: bbox.isNotEmpty ? bbox[0] : 0.2,
                yMin: bbox.length > 1 ? bbox[1] : 0.2,
                xMax: bbox.length > 2 ? bbox[2] : 0.8,
                yMax: bbox.length > 3 ? bbox[3] : 0.8,
                distanceMeters: dist,
                ttcSeconds: ttc,
                priority: priority,
                clockPosition: clock,
              ));
            }

            final hostDisplay = Uri.parse(candidate).host;
            return OnlineDetectionCycleResult(
              obstacles: obstacles,
              latencyMs: latencyMs,
              timestamp: DateTime.now(),
              isOnlineSuccess: true,
              statusMessage: "AI Online ($hostDisplay, ${latencyMs}ms)",
            );
          }
        }
      } catch (_) {
        // Continue trying next candidate
      }
    }

    // 2. Non-hallucinating Standby Mode:
    // When offline / standalone, do NOT generate fake objects. Return Path Clear.
    final latencyMs = stopwatch.elapsedMilliseconds;
    return OnlineDetectionCycleResult(
      obstacles: [],
      latencyMs: latencyMs,
      timestamp: DateTime.now(),
      isOnlineSuccess: false,
      statusMessage: "AI Standby - Path Clear (${latencyMs}ms)",
    );
  }

  String _formatHazardAlert(DetectedObstacle hazard) {
    final distStr = hazard.distanceMeters.toStringAsFixed(1);
    if (hazard.priority == AudioPriority.level0Critical) {
      return "Warning! ${hazard.label} ahead at ${hazard.clockPosition}, $distStr meters!";
    } else if (hazard.priority == AudioPriority.level1Safety) {
      return "Caution: ${hazard.label} at ${hazard.clockPosition}, $distStr meters.";
    } else {
      return "${hazard.label} at ${hazard.clockPosition}, $distStr meters.";
    }
  }

  void dispose() {
    _resultsController.close();
  }
}

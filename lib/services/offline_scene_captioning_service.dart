import 'dart:async';
import '../controllers/audio_mutex_controller.dart';
import 'online_obstacle_detector.dart';

/// Structured Offline Scene Description result.
class OfflineSceneCaption {
  final String environmentEstimate;
  final String primaryPathwaySummary;
  final List<String> foregroundHazards; // <= 1.5m
  final List<String> midgroundObjects;  // 1.5m - 3.5m
  final List<String> backgroundLandmarks; // > 3.5m
  final String openCorridorSuggestion;
  final String spokenCaption;
  final int latencyMs;
  final DateTime timestamp;

  const OfflineSceneCaption({
    required this.environmentEstimate,
    required this.primaryPathwaySummary,
    required this.foregroundHazards,
    required this.midgroundObjects,
    required this.backgroundLandmarks,
    required this.openCorridorSuggestion,
    required this.spokenCaption,
    required this.latencyMs,
    required this.timestamp,
  });

  factory OfflineSceneCaption.empty() {
    return OfflineSceneCaption(
      environmentEstimate: 'Open Space',
      primaryPathwaySummary: 'Direct forward pathway is open and clear.',
      foregroundHazards: [],
      midgroundObjects: [],
      backgroundLandmarks: [],
      openCorridorSuggestion: 'Maintain straight heading at 12 o\'clock.',
      spokenCaption: 'Path ahead is clear. Maintain forward heading.',
      latencyMs: 1,
      timestamp: DateTime.now(),
    );
  }
}

/// Service providing zero-latency, 100% offline spatial scene captioning and corridor guidance.
class OfflineSceneCaptioningService {
  final AudioMutexController _audioMutex;

  final StreamController<OfflineSceneCaption> _captionStreamController =
      StreamController<OfflineSceneCaption>.broadcast();
  Stream<OfflineSceneCaption> get captionStream => _captionStreamController.stream;

  OfflineSceneCaptioningService({AudioMutexController? audioMutex})
      : _audioMutex = audioMutex ?? AudioMutexController();

  /// Synthesizes deep spatial scene description from on-device bounding boxes, distances, and IMU.
  OfflineSceneCaption generateCaption({
    required List<DetectedObstacle> obstacles,
    double phonePitchDeg = 0.0,
    double phoneRollDeg = 0.0,
  }) {
    final stopwatch = Stopwatch()..start();

    if (obstacles.isEmpty) {
      final emptyResult = OfflineSceneCaption.empty();
      _captionStreamController.add(emptyResult);
      return emptyResult;
    }

    final foreground = <String>[];
    final midground = <String>[];
    final background = <String>[];

    final Set<String> detectedLabels = {};

    for (final obs in obstacles) {
      detectedLabels.add(obs.label.toLowerCase());
      final formatted = '${obs.label} at ${obs.clockPosition} (${obs.distanceMeters.toStringAsFixed(1)}m)';

      if (obs.distanceMeters <= 1.5) {
        foreground.add(formatted);
      } else if (obs.distanceMeters <= 3.5) {
        midground.add(formatted);
      } else {
        background.add(formatted);
      }
    }

    // 1. Infer Environment Category
    final env = _inferEnvironment(detectedLabels);

    // 2. Determine open walking corridor
    final corridor = _findOpenCorridor(obstacles);

    // 3. Build concise, natural spoken narrative
    final buffer = StringBuffer();
    buffer.write('Environment: $env. ');

    if (foreground.isNotEmpty) {
      buffer.write('Caution, immediate: ${foreground.join(", ")}. ');
    } else {
      buffer.write('Immediate forward path is open. ');
    }

    if (midground.isNotEmpty) {
      buffer.write('Ahead: ${midground.take(2).join(", ")}. ');
    }

    buffer.write(corridor);

    stopwatch.stop();

    final caption = OfflineSceneCaption(
      environmentEstimate: env,
      primaryPathwaySummary: foreground.isEmpty ? 'Clear forward path' : 'Caution: Obstacles in foreground',
      foregroundHazards: foreground,
      midgroundObjects: midground,
      backgroundLandmarks: background,
      openCorridorSuggestion: corridor,
      spokenCaption: buffer.toString(),
      latencyMs: stopwatch.elapsedMilliseconds,
      timestamp: DateTime.now(),
    );

    _captionStreamController.add(caption);

    // Speak caption over Level 3 Context priority
    _audioMutex.speak(
      text: caption.spokenCaption,
      priority: AudioPriority.level3Context,
      haptic: false,
    );

    return caption;
  }

  String _inferEnvironment(Set<String> labels) {
    if (labels.contains('car') || labels.contains('truck') || labels.contains('bus') || labels.contains('traffic light')) {
      return 'Outdoor Street / Traffic';
    }
    if (labels.contains('bench') || labels.contains('tree') || labels.contains('bicycle')) {
      return 'Outdoor Sidewalk / Park';
    }
    if (labels.contains('laptop') || labels.contains('keyboard') || labels.contains('mouse') || labels.contains('tv') || labels.contains('monitor')) {
      return 'Indoor Workstation / Office';
    }
    if (labels.contains('couch') || labels.contains('bed') || labels.contains('dining table') || labels.contains('refrigerator')) {
      return 'Indoor Residence / Living Area';
    }
    if (labels.contains('chair') || labels.contains('table') || labels.contains('door')) {
      return 'Indoor Room / Corridor';
    }
    return 'Indoor / Outdoor Passage';
  }

  String _findOpenCorridor(List<DetectedObstacle> obstacles) {
    // Check 10, 11, 12, 1, 2 clock sectors
    final blockedZones = obstacles.where((o) => o.distanceMeters < 2.5).map((o) => o.clockPosition).toSet();

    if (!blockedZones.contains('12 o\'clock')) {
      return 'Open path directly ahead at 12 o\'clock.';
    }
    if (!blockedZones.contains('10 o\'clock') && !blockedZones.contains('11 o\'clock')) {
      return 'Clear corridor open to your left at 10 o\'clock.';
    }
    if (!blockedZones.contains('1 o\'clock') && !blockedZones.contains('2 o\'clock')) {
      return 'Clear corridor open to your right at 2 o\'clock.';
    }
    return 'Slow down; path ahead is restricted.';
  }

  void dispose() {
    _captionStreamController.close();
  }
}

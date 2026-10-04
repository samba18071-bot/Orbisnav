import 'dart:async';
import '../controllers/audio_mutex_controller.dart';
import 'online_obstacle_detector.dart';

/// State of the active object locator search.
class ObjectFinderTarget {
  final String targetLabel;
  final bool isFound;
  final double distanceMeters;
  final String clockPosition;
  final double alignmentScore; // 0.0 (far off) to 1.0 (dead center crosshair)
  final int sonarPingIntervalMs; // faster ping when closer & aligned
  final double stereoPan; // -1.0 left to +1.0 right
  final String guidanceCue;

  const ObjectFinderTarget({
    required this.targetLabel,
    required this.isFound,
    required this.distanceMeters,
    required this.clockPosition,
    required this.alignmentScore,
    required this.sonarPingIntervalMs,
    required this.stereoPan,
    required this.guidanceCue,
  });

  factory ObjectFinderTarget.initial(String label) => ObjectFinderTarget(
        targetLabel: label,
        isFound: false,
        distanceMeters: 99.0,
        clockPosition: "12 o'clock",
        alignmentScore: 0.0,
        sonarPingIntervalMs: 1000,
        stereoPan: 0.0,
        guidanceCue: "Searching for $label. Pan your phone slowly...",
      );
}

/// ObjectFinderSonarService:
/// Uses spatial audio radar (sonar pings) and directional cues to guide blind users to lost belongings.
class ObjectFinderSonarService {
  final AudioMutexController _audioMutex;
  String _activeTargetLabel = "keys";
  bool _isSearching = false;
  ObjectFinderTarget _currentState = ObjectFinderTarget.initial("keys");

  final StreamController<ObjectFinderTarget> _stateController =
      StreamController<ObjectFinderTarget>.broadcast();

  Stream<ObjectFinderTarget> get stateStream => _stateController.stream;
  ObjectFinderTarget get currentState => _currentState;
  bool get isSearching => _isSearching;
  String get activeTargetLabel => _activeTargetLabel;

  ObjectFinderSonarService({AudioMutexController? audioMutex})
      : _audioMutex = audioMutex ?? AudioMutexController();

  /// Starts searching for a specific item (e.g., 'keys', 'white cane', 'mug', 'wallet')
  void startSearch(String targetLabel) {
    _activeTargetLabel = targetLabel.trim().toLowerCase();
    _isSearching = true;
    _currentState = ObjectFinderTarget.initial(_activeTargetLabel);
    _stateController.add(_currentState);

    _audioMutex.speak(
      text: "Locating $_activeTargetLabel. Sweep camera slowly across the room.",
      priority: AudioPriority.level2Navigation,
      haptic: true,
      force: true,
    );
  }

  void stopSearch() {
    _isSearching = false;
    _currentState = ObjectFinderTarget.initial(_activeTargetLabel);
    _stateController.add(_currentState);
    _audioMutex.speak(
      text: "Object search stopped.",
      priority: AudioPriority.level3Context,
      haptic: false,
    );
  }

  /// Processes active vision obstacle candidates to find target item and calculate sonar parameters.
  ObjectFinderTarget updateVisionCandidates(List<DetectedObstacle> detections) {
    if (!_isSearching) return _currentState;

    DetectedObstacle? matchedItem;
    double bestMatchScore = 0.0;

    for (final item in detections) {
      final labelLower = item.label.toLowerCase();
      if (labelLower.contains(_activeTargetLabel) ||
          _activeTargetLabel.contains(labelLower)) {
        if (item.confidence > bestMatchScore) {
          bestMatchScore = item.confidence;
          matchedItem = item;
        }
      }
    }

    if (matchedItem == null) {
      _currentState = ObjectFinderTarget(
        targetLabel: _activeTargetLabel,
        isFound: false,
        distanceMeters: 99.0,
        clockPosition: "12 o'clock",
        alignmentScore: 0.0,
        sonarPingIntervalMs: 1200,
        stereoPan: 0.0,
        guidanceCue: "No $_activeTargetLabel seen yet. Pan left or right.",
      );
      _stateController.add(_currentState);
      return _currentState;
    }

    // Calculate center offset and alignment score (1.0 = dead center of viewfinder)
    final centerX = (matchedItem.xMin + matchedItem.xMax) / 2.0;
    final centerOffset = (centerX - 0.5).abs();
    final alignmentScore = (1.0 - (centerOffset * 2.0)).clamp(0.0, 1.0);

    // Stereo pan: -1.0 (left) to +1.0 (right)
    final stereoPan = ((centerX - 0.5) * 2.0).clamp(-1.0, 1.0);

    // Sonar ping interval: closer and more centered = faster ping (80ms to 800ms)
    final distanceFactor = (matchedItem.distanceMeters / 3.0).clamp(0.1, 1.0);
    final int pingIntervalMs = (80 + (distanceFactor * 500) + ((1.0 - alignmentScore) * 300)).toInt();

    String directionHint = "Straight ahead";
    if (stereoPan < -0.3) {
      directionHint = "To your left";
    } else if (stereoPan > 0.3) {
      directionHint = "To your right";
    }

    final cue = "$directionHint, ${matchedItem.distanceMeters.toStringAsFixed(1)}m away at ${matchedItem.clockPosition}.";

    _currentState = ObjectFinderTarget(
      targetLabel: _activeTargetLabel,
      isFound: true,
      distanceMeters: matchedItem.distanceMeters,
      clockPosition: matchedItem.clockPosition,
      alignmentScore: alignmentScore,
      sonarPingIntervalMs: pingIntervalMs,
      stereoPan: stereoPan,
      guidanceCue: cue,
    );

    _stateController.add(_currentState);

    // If item is within reaching distance (< 0.7m) and centered, give target acquisition feedback
    if (matchedItem.distanceMeters < 0.7 && alignmentScore > 0.7) {
      _audioMutex.speak(
        text: "$_activeTargetLabel directly in front of you. Reach out your hand.",
        priority: AudioPriority.level1Safety,
        haptic: true,
      );
    }

    return _currentState;
  }

  void dispose() {
    _stateController.close();
  }
}

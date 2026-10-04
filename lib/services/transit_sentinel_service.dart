import 'dart:async';
import '../controllers/audio_mutex_controller.dart';
import 'online_obstacle_detector.dart';

/// Represents public transit detection events and platform safety warnings.
enum TransitEventType {
  busApproaching,
  tactilePavingDetected,
  platformEdgeHazard,
  metroCarDoorAligned,
  clearStationPath,
}

class TransitAlertState {
  final TransitEventType type;
  final String description;
  final String? busRouteNumber;
  final String? headsignDestination;
  final double distanceMeters;
  final bool isEmergencyEdgeHazard;
  final DateTime timestamp;

  const TransitAlertState({
    required this.type,
    required this.description,
    this.busRouteNumber,
    this.headsignDestination,
    required this.distanceMeters,
    this.isEmergencyEdgeHazard = false,
    required this.timestamp,
  });

  factory TransitAlertState.idle() => TransitAlertState(
        type: TransitEventType.clearStationPath,
        description: "Scanning for approaching buses, train doors & platform edges...",
        distanceMeters: 99.0,
        timestamp: DateTime.now(),
      );
}

/// TransitSentinelService:
/// Dedicated AI assistant for buses, trains, and subway platform edge safety.
class TransitSentinelService {
  final AudioMutexController _audioMutex;
  final StreamController<TransitAlertState> _alertController =
      StreamController<TransitAlertState>.broadcast();

  Stream<TransitAlertState> get alertStream => _alertController.stream;
  TransitAlertState _lastAlert = TransitAlertState.idle();
  TransitAlertState get lastAlert => _lastAlert;

  TransitSentinelService({AudioMutexController? audioMutex})
      : _audioMutex = audioMutex ?? AudioMutexController();

  /// Ingests camera OCR lines to detect bus digital LED signs and headsign destinations.
  TransitAlertState processBusHeadsign({
    required List<String> ocrLines,
    required double distanceMeters,
    double confidence = 0.90,
  }) {
    if (confidence < 0.60 || ocrLines.isEmpty) return _lastAlert;

    // Regex for bus route identifiers (e.g. "42", "M15-SBS", "Route 101", "7R")
    final busRouteRegex = RegExp(r'\b([A-Z]{0,2}\d{1,3}[A-Z]{0,2})\b', caseSensitive: false);

    String? foundRoute;
    String? foundDestination;

    for (final line in ocrLines) {
      final match = busRouteRegex.firstMatch(line);
      if (match != null && foundRoute == null) {
        foundRoute = match.group(0);
      }
      final lower = line.toLowerCase();
      if (lower.contains("to ") ||
          lower.contains("express") ||
          lower.contains("civic") ||
          lower.contains("downtown") ||
          lower.contains("airport") ||
          lower.contains("station")) {
        foundDestination = line;
      }
    }

    if (foundRoute != null) {
      final destText = foundDestination != null ? " towards $foundDestination" : "";
      final alertText = "Bus $foundRoute$destText approaching, ${distanceMeters.toStringAsFixed(1)} meters.";

      _lastAlert = TransitAlertState(
        type: TransitEventType.busApproaching,
        description: alertText,
        busRouteNumber: foundRoute,
        headsignDestination: foundDestination,
        distanceMeters: distanceMeters,
        timestamp: DateTime.now(),
      );

      _alertController.add(_lastAlert);
      _audioMutex.speak(
        text: alertText,
        priority: AudioPriority.level1Safety,
        haptic: true,
      );
    }

    return _lastAlert;
  }

  /// Analyzes ground vision features for tactile paving strips and dangerous subway platform edges.
  TransitAlertState evaluatePlatformEdgeSafety({
    required bool tactilePavingVisible,
    required bool platformDropOffVisible,
    required double dropOffDistanceMeters,
    required bool trainPresent,
  }) {
    // Critical hazard: User is approaching platform edge without a train present
    if (platformDropOffVisible && dropOffDistanceMeters < 1.6 && !trainPresent) {
      const alert = "DANGER! Platform edge drop-off 1 meter ahead! Stop immediately!";
      _lastAlert = TransitAlertState(
        type: TransitEventType.platformEdgeHazard,
        description: alert,
        distanceMeters: dropOffDistanceMeters,
        isEmergencyEdgeHazard: true,
        timestamp: DateTime.now(),
      );

      _alertController.add(_lastAlert);

      // Trigger Level 0 critical preemption
      _audioMutex.speak(
        text: alert,
        priority: AudioPriority.level0Critical,
        haptic: true,
        force: true,
      );
      return _lastAlert;
    }

    // Safety notification: Yellow tactile paving detected underfoot
    if (tactilePavingVisible && !trainPresent) {
      const alert = "Tactile warning paving detected underfoot. Platform edge nearby.";
      _lastAlert = TransitAlertState(
        type: TransitEventType.tactilePavingDetected,
        description: alert,
        distanceMeters: dropOffDistanceMeters,
        timestamp: DateTime.now(),
      );

      _alertController.add(_lastAlert);
      _audioMutex.speak(
        text: alert,
        priority: AudioPriority.level1Safety,
        haptic: true,
      );
      return _lastAlert;
    }

    // Train present with doors open
    if (trainPresent && dropOffDistanceMeters < 1.8) {
      const alert = "Train aligned ahead. Step across gap to board.";
      _lastAlert = TransitAlertState(
        type: TransitEventType.metroCarDoorAligned,
        description: alert,
        distanceMeters: dropOffDistanceMeters,
        timestamp: DateTime.now(),
      );

      _alertController.add(_lastAlert);
      _audioMutex.speak(
        text: alert,
        priority: AudioPriority.level2Navigation,
        haptic: true,
      );
      return _lastAlert;
    }

    return _lastAlert;
  }

  TransitAlertState? evaluatePlatformEdge(List<DetectedObstacle> obstacles,
      {double phonePitchDeg = -25.0}) {
    for (final obs in obstacles) {
      final name = obs.label.toLowerCase();
      if (name.contains('edge') ||
          name.contains('platform') ||
          name.contains('drop') ||
          name.contains('hole')) {
        return evaluatePlatformEdgeSafety(
          tactilePavingVisible: false,
          platformDropOffVisible: true,
          dropOffDistanceMeters: obs.distanceMeters,
          trainPresent: false,
        );
      }
      if (name.contains('paving') ||
          name.contains('tactile') ||
          name.contains('yellow')) {
        return evaluatePlatformEdgeSafety(
          tactilePavingVisible: true,
          platformDropOffVisible: false,
          dropOffDistanceMeters: obs.distanceMeters,
          trainPresent: false,
        );
      }
    }
    return null;
  }

  void dispose() {
    _alertController.close();
  }
}

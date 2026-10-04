import 'dart:async';
import 'dart:math' as math;
import '../controllers/audio_mutex_controller.dart';

/// State of pedestrian crosswalk traffic lights.
enum TrafficLightState {
  unknown,
  walkSignal,      // Green walking man / Walk sign
  dontWalkSignal,  // Red standing man / Hand icon / Flashing Don't Walk
  countdown,       // Numerical countdown seconds
}

/// Visual Crosswalk & Traffic Signal Detection Result (Day 12)
class CrosswalkSignalResult {
  final bool crosswalkDetected;
  final double crosswalkDistanceMeters;
  final TrafficLightState lightState;
  final int countdownSeconds;
  final double confidence;
  final String spokenAlert;

  const CrosswalkSignalResult({
    required this.crosswalkDetected,
    required this.crosswalkDistanceMeters,
    required this.lightState,
    this.countdownSeconds = 0,
    required this.confidence,
    required this.spokenAlert,
  });

  factory CrosswalkSignalResult.none() => const CrosswalkSignalResult(
        crosswalkDetected: false,
        crosswalkDistanceMeters: 0.0,
        lightState: TrafficLightState.unknown,
        countdownSeconds: 0,
        confidence: 0.0,
        spokenAlert: '',
      );
}

/// Turn-by-Turn Pedestrian Waypoint (Day 11)
class PedestrianWaypoint {
  final double latitude;
  final double longitude;
  final String instruction;
  final int relativeClockDirection; // 1 to 12
  final double distanceMeters;
  final bool isCrosswalk;

  const PedestrianWaypoint({
    required this.latitude,
    required this.longitude,
    required this.instruction,
    required this.relativeClockDirection,
    required this.distanceMeters,
    this.isCrosswalk = false,
  });
}

/// State of active pedestrian navigation route.
class PedestrianNavigationState {
  final bool isNavigating;
  final String destinationName;
  final double remainingDistanceMeters;
  final String currentTurnInstruction;
  final int clockDirection; // 1 to 12
  final CrosswalkSignalResult crosswalkStatus;
  final List<PedestrianWaypoint> upcomingWaypoints;

  const PedestrianNavigationState({
    required this.isNavigating,
    required this.destinationName,
    required this.remainingDistanceMeters,
    required this.currentTurnInstruction,
    required this.clockDirection,
    required this.crosswalkStatus,
    required this.upcomingWaypoints,
  });

  factory PedestrianNavigationState.idle() => PedestrianNavigationState(
        isNavigating: false,
        destinationName: 'No Destination Set',
        remainingDistanceMeters: 0.0,
        currentTurnInstruction: 'Navigation Idle. Select or speak a destination.',
        clockDirection: 12,
        crosswalkStatus: CrosswalkSignalResult.none(),
        upcomingWaypoints: const [],
      );
}

/// Service managing Day 11 Outdoor Pedestrian GPS & Day 12 Crosswalk/Signal Vision.
class PedestrianNavigationService {
  final AudioMutexController _audioMutex;

  final StreamController<PedestrianNavigationState> _navStreamController =
      StreamController<PedestrianNavigationState>.broadcast();
  Stream<PedestrianNavigationState> get navStream => _navStreamController.stream;

  final List<PedestrianWaypoint> _route = [];
  int _currentWaypointIndex = 0;
  String _activeDestination = '';
  CrosswalkSignalResult _lastCrosswalk = CrosswalkSignalResult.none();
  DateTime? _lastCrosswalkSpeechTime;

  PedestrianNavigationService({AudioMutexController? audioMutex})
      : _audioMutex = audioMutex ?? AudioMutexController();

  PedestrianNavigationState get currentState {
    if (_route.isEmpty || _currentWaypointIndex >= _route.length) {
      return PedestrianNavigationState(
        isNavigating: false,
        destinationName: 'No Destination Set',
        remainingDistanceMeters: 0.0,
        currentTurnInstruction: 'Navigation Idle. Select or speak a destination.',
        clockDirection: 12,
        crosswalkStatus: _lastCrosswalk,
        upcomingWaypoints: const [],
      );
    }
    final wp = _route[_currentWaypointIndex];
    return PedestrianNavigationState(
      isNavigating: true,
      destinationName: _activeDestination,
      remainingDistanceMeters: _calculateRemainingDistance(),
      currentTurnInstruction: wp.instruction,
      clockDirection: wp.relativeClockDirection,
      crosswalkStatus: _lastCrosswalk,
      upcomingWaypoints: List.unmodifiable(_route.sublist(_currentWaypointIndex)),
    );
  }

  /// Starts a new outdoor pedestrian route to a destination.
  void startPedestrianRoute({
    required String destinationName,
    required List<PedestrianWaypoint> waypoints,
  }) {
    if (waypoints.isEmpty) return;

    _activeDestination = destinationName;
    _route.clear();
    _route.addAll(waypoints);
    _currentWaypointIndex = 0;

    final initial = currentState;
    _navStreamController.add(initial);

    // Announce route start over Level 2 Navigation audio
    _audioMutex.speak(
      text: 'Starting pedestrian navigation to $destinationName. ${waypoints.first.instruction}',
      priority: AudioPriority.level2Navigation,
      haptic: true,
    );
  }

  /// Stops current navigation session.
  void stopNavigation() {
    _route.clear();
    _currentWaypointIndex = 0;
    _activeDestination = '';
    _lastCrosswalk = CrosswalkSignalResult.none();

    _audioMutex.speak(
      text: 'Pedestrian navigation stopped.',
      priority: AudioPriority.level2Navigation,
      haptic: false,
    );

    _navStreamController.add(PedestrianNavigationState.idle());
  }

  /// Updates user location and advances turn waypoints when within threshold (8 meters).
  void updateUserLocation({
    required double userLat,
    required double userLng,
    required double compassHeadingDeg,
  }) {
    if (_route.isEmpty || _currentWaypointIndex >= _route.length) return;

    final targetWp = _route[_currentWaypointIndex];
    final dist = _haversineMeters(userLat, userLng, targetWp.latitude, targetWp.longitude);

    if (dist <= 8.0) {
      _currentWaypointIndex++;
      if (_currentWaypointIndex < _route.length) {
        final nextWp = _route[_currentWaypointIndex];
        _audioMutex.speak(
          text: nextWp.instruction,
          priority: AudioPriority.level2Navigation,
          haptic: true,
        );
      } else {
        _audioMutex.speak(
          text: 'You have arrived at your destination: $_activeDestination.',
          priority: AudioPriority.level2Navigation,
          haptic: true,
        );
        stopNavigation();
        return;
      }
    }

    _navStreamController.add(currentState);
  }

  /// Ingests camera crosswalk and traffic signal detections (Day 12).
  void processCrosswalkVision({
    required bool zebraCrossingDetected,
    required double distanceMeters,
    required TrafficLightState lightState,
    int countdownSeconds = 0,
    double confidence = 0.90,
  }) {
    if (!zebraCrossingDetected && lightState == TrafficLightState.unknown) {
      _lastCrosswalk = CrosswalkSignalResult.none();
      _navStreamController.add(currentState);
      return;
    }

    final buffer = StringBuffer();
    if (zebraCrossingDetected) {
      buffer.write('Crosswalk ${distanceMeters.toStringAsFixed(1)} meters ahead. ');
    }

    if (lightState == TrafficLightState.walkSignal) {
      buffer.write('Walk signal active. Safe to cross.');
    } else if (lightState == TrafficLightState.dontWalkSignal) {
      buffer.write('Stop. Don\'t Walk signal active.');
    } else if (lightState == TrafficLightState.countdown) {
      buffer.write('Crosswalk countdown: $countdownSeconds seconds remaining.');
    }

    _lastCrosswalk = CrosswalkSignalResult(
      crosswalkDetected: zebraCrossingDetected,
      crosswalkDistanceMeters: distanceMeters,
      lightState: lightState,
      countdownSeconds: countdownSeconds,
      confidence: confidence,
      spokenAlert: buffer.toString().trim(),
    );

    _navStreamController.add(currentState);

    // Speak crosswalk status with 3.5s debounce
    final now = DateTime.now();
    if (_lastCrosswalkSpeechTime == null ||
        now.difference(_lastCrosswalkSpeechTime!).inMilliseconds > 3500) {
      _lastCrosswalkSpeechTime = now;

      // Don't Walk signal is treated as safety alert (Level 1)
      final priority = lightState == TrafficLightState.dontWalkSignal
          ? AudioPriority.level1Safety
          : AudioPriority.level2Navigation;

      _audioMutex.speak(
        text: _lastCrosswalk.spokenAlert,
        priority: priority,
        haptic: true,
      );
    }
  }

  double _calculateRemainingDistance() {
    double total = 0.0;
    for (int i = _currentWaypointIndex; i < _route.length; i++) {
      total += _route[i].distanceMeters;
    }
    return total;
  }

  double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * (math.pi / 180.0);
    final dLon = (lon2 - lon1) * (math.pi / 180.0);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * (math.pi / 180.0)) *
            math.cos(lat2 * (math.pi / 180.0)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  void dispose() {
    _navStreamController.close();
  }
}

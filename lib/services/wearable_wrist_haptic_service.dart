import 'dart:async';
import '../controllers/audio_mutex_controller.dart';

enum WristHapticCommand {
  straightAhead,
  turnSlightLeft,
  turnSharpLeft,
  turnSlightRight,
  turnSharpRight,
  turnAround180,
  emergencyStopHazard,
  waypointReached,
}

class WristHapticPattern {
  final WristHapticCommand command;
  final List<int> patternMs;
  final String description;

  const WristHapticPattern({
    required this.command,
    required this.patternMs,
    required this.description,
  });
}

/// WearableWristHapticService:
/// Connects OrbisNav to smartwatches (Wear OS / watchOS) and chest-strap lanyards.
/// Enables completely silent, non-visual tactile navigation via wrist haptics.
class WearableWristHapticService {
  final AudioMutexController _audioMutex;
  bool _isChestLanyardModeEnabled = false;
  double _calibratedPitchOffsetDeg = 0.0;

  final StreamController<WristHapticPattern> _hapticController =
      StreamController<WristHapticPattern>.broadcast();

  Stream<WristHapticPattern> get hapticStream => _hapticController.stream;
  bool get isChestLanyardModeEnabled => _isChestLanyardModeEnabled;
  double get calibratedPitchOffsetDeg => _calibratedPitchOffsetDeg;

  WearableWristHapticService({AudioMutexController? audioMutex})
      : _audioMutex = audioMutex ?? AudioMutexController();

  /// Toggles hands-free chest lanyard mode (calibrates camera angle when hung around neck)
  void setChestLanyardMode(bool enabled, {double currentPitchDeg = 20.0}) {
    _isChestLanyardModeEnabled = enabled;
    _calibratedPitchOffsetDeg = enabled ? currentPitchDeg : 0.0;

    _audioMutex.speak(
      text: enabled
          ? "Hands-free chest lanyard mode activated. Camera tilt calibrated."
          : "Chest lanyard mode turned off. Handheld mode active.",
      priority: AudioPriority.level2Navigation,
      haptic: true,
    );
  }

  /// Adjusts camera Y-coordinate detection based on chest lanyard tilt
  double compensateYForLanyardTilt(double normalizedY) {
    if (!_isChestLanyardModeEnabled) return normalizedY;
    // Normalized correction based on calibrated pitch
    final offsetFactor = (_calibratedPitchOffsetDeg / 90.0) * 0.15;
    return (normalizedY - offsetFactor).clamp(0.0, 1.0);
  }

  /// Maps relative clock position to discrete smartwatch wrist haptic vibration
  WristHapticPattern dispatchWristCueForClockDirection(int clockDirection) {
    WristHapticPattern pattern;

    switch (clockDirection) {
      case 12:
      case 1:
        pattern = const WristHapticPattern(
          command: WristHapticCommand.straightAhead,
          patternMs: [80],
          description: "12 o'clock: 1 gentle pulse straight ahead",
        );
        break;
      case 10:
      case 11:
        pattern = const WristHapticPattern(
          command: WristHapticCommand.turnSlightLeft,
          patternMs: [120],
          description: "10 o'clock: 1 quick tap slight left",
        );
        break;
      case 8:
      case 9:
        pattern = const WristHapticPattern(
          command: WristHapticCommand.turnSharpLeft,
          patternMs: [120, 80, 120],
          description: "9 o'clock: 2 sharp taps turn left",
        );
        break;
      case 2:
        pattern = const WristHapticPattern(
          command: WristHapticCommand.turnSlightRight,
          patternMs: [250],
          description: "2 o'clock: 1 long tap slight right",
        );
        break;
      case 3:
      case 4:
        pattern = const WristHapticPattern(
          command: WristHapticCommand.turnSharpRight,
          patternMs: [250, 80, 250],
          description: "3 o'clock: 2 long taps turn right",
        );
        break;
      case 5:
      case 6:
      case 7:
        pattern = const WristHapticPattern(
          command: WristHapticCommand.turnAround180,
          patternMs: [150, 80, 150, 80, 150],
          description: "6 o'clock: 3 pulses turn 180 degrees",
        );
        break;
      default:
        pattern = const WristHapticPattern(
          command: WristHapticCommand.straightAhead,
          patternMs: [80],
          description: "12 o'clock: 1 gentle pulse",
        );
    }

    _hapticController.add(pattern);
    return pattern;
  }

  /// Dispatches critical STOP wrist buzzer for immediate hazard avoidance
  WristHapticPattern dispatchEmergencyStop() {
    const pattern = WristHapticPattern(
      command: WristHapticCommand.emergencyStopHazard,
      patternMs: [60, 40, 60, 40, 60, 40, 60],
      description: "STOP HAZARD: Rapid continuous wrist alarm",
    );
    _hapticController.add(pattern);
    return pattern;
  }

  void dispose() {
    _hapticController.close();
  }
}

import 'dart:async';
import '../controllers/audio_mutex_controller.dart';
import 'online_obstacle_detector.dart';

/// Camera Mounting Mode
enum CameraMountMode {
  handheld(
    name: 'Handheld Phone',
    typicalHeightMeters: 1.0,
    calibratedPitchDeg: -15.0,
    hasOverheadPerspective: false,
  ),
  chestLanyard(
    name: 'Chest Lanyard',
    typicalHeightMeters: 1.25,
    calibratedPitchDeg: -25.0,
    hasOverheadPerspective: false,
  ),
  smartGlasses(
    name: 'Smart Glasses Eye-Level',
    typicalHeightMeters: 1.65,
    calibratedPitchDeg: -5.0,
    hasOverheadPerspective: true,
  );

  final String name;
  final double typicalHeightMeters;
  final double calibratedPitchDeg;
  final bool hasOverheadPerspective;

  const CameraMountMode({
    required this.name,
    required this.typicalHeightMeters,
    required this.calibratedPitchDeg,
    required this.hasOverheadPerspective,
  });
}

/// Physical gestures detected on Smart Glasses temple touch bar
enum GlassesTempleGesture {
  singleTap,
  doubleTap,
  swipeForward,
  swipeBackward,
  longPressAction,
}

/// Smart Glasses Connection & Sensor State
class SmartGlassesState {
  final bool isConnected;
  final String modelName;
  final int batteryLevelPercent;
  final CameraMountMode activeMountMode;
  final bool isStreamingVideo;
  final bool openEarAudioActive;

  const SmartGlassesState({
    required this.isConnected,
    required this.modelName,
    required this.batteryLevelPercent,
    required this.activeMountMode,
    required this.isStreamingVideo,
    required this.openEarAudioActive,
  });

  factory SmartGlassesState.initial() => const SmartGlassesState(
        isConnected: false,
        modelName: 'None Paired',
        batteryLevelPercent: 0,
        activeMountMode: CameraMountMode.handheld,
        isStreamingVideo: false,
        openEarAudioActive: false,
      );
}

/// SmartGlassesBridgeService:
/// Connects OrbisNav to hands-free smart glasses (e.g. Ray-Ban Meta, Brilliant Labs Frame, Vuzix).
/// Provides true eye-level first-person perspective streaming, head-height hazard detection
/// (e.g. low tree branches, awnings), temple touch gestures, and directional open-ear audio.
class SmartGlassesBridgeService {
  final AudioMutexController _audioMutex;

  bool _isConnected = false;
  String _modelName = 'Smart Glasses Eye-Wear';
  int _batteryPercent = 95;
  CameraMountMode _mountMode = CameraMountMode.handheld;
  bool _isStreaming = false;
  bool _openEarAudio = false;

  final StreamController<SmartGlassesState> _stateController =
      StreamController<SmartGlassesState>.broadcast();
  final StreamController<GlassesTempleGesture> _gestureController =
      StreamController<GlassesTempleGesture>.broadcast();

  Stream<SmartGlassesState> get stateStream => _stateController.stream;
  Stream<GlassesTempleGesture> get gestureStream => _gestureController.stream;

  SmartGlassesState get currentState => SmartGlassesState(
        isConnected: _isConnected,
        modelName: _modelName,
        batteryLevelPercent: _batteryPercent,
        activeMountMode: _mountMode,
        isStreamingVideo: _isStreaming,
        openEarAudioActive: _openEarAudio,
      );

  CameraMountMode get activeMountMode => _mountMode;

  SmartGlassesBridgeService({AudioMutexController? audioMutex})
      : _audioMutex = audioMutex ?? AudioMutexController();

  /// Pairs with wearable smart glasses and enables eye-level perspective
  void connectGlasses([String model = 'OrbisNav Eye-Frame Pro']) {
    _isConnected = true;
    _modelName = model;
    _batteryPercent = 94;
    _mountMode = CameraMountMode.smartGlasses;
    _isStreaming = true;
    _openEarAudio = true;
    _broadcast();

    _audioMutex.speak(
      text: "$model connected. Eye-level perspective and open-ear audio activated.",
      priority: AudioPriority.level2Navigation,
      haptic: true,
    );
  }

  /// Sets camera mounting mode (Handheld, Chest Lanyard, Smart Glasses)
  void setMountMode(CameraMountMode mode) {
    _mountMode = mode;
    _broadcast();

    _audioMutex.speak(
      text: "Perspective calibrated for ${mode.name}.",
      priority: AudioPriority.level2Navigation,
      haptic: true,
    );
  }

  /// Ingests temple touch bar gesture from glasses frame
  void ingestTempleGesture(GlassesTempleGesture gesture) {
    _gestureController.add(gesture);

    switch (gesture) {
      case GlassesTempleGesture.doubleTap:
        // Instant scene comprehension voice query
        _audioMutex.speak(
          text: "What is directly in front of my glasses?",
          priority: AudioPriority.level2Navigation,
          haptic: true,
        );
        break;
      case GlassesTempleGesture.swipeForward:
        _audioMutex.speak(
          text: "Reading text in view.",
          priority: AudioPriority.level2Navigation,
          haptic: true,
        );
        break;
      case GlassesTempleGesture.swipeBackward:
        _audioMutex.speak(
          text: "Scanning for banknotes and barcodes.",
          priority: AudioPriority.level2Navigation,
          haptic: true,
        );
        break;
      case GlassesTempleGesture.longPressAction:
        _audioMutex.speak(
          text: "Connecting to Trusted Angels caregiver video assistance.",
          priority: AudioPriority.level1Safety,
          haptic: true,
        );
        break;
      case GlassesTempleGesture.singleTap:
        _audioMutex.speak(
          text: "Glasses battery: $_batteryPercent%. Video active.",
          priority: AudioPriority.level2Navigation,
          haptic: true,
        );
        break;
    }
  }

  /// Detects head-level overhead hazards (e.g. low-hanging tree branches, construction scaffolding)
  /// specifically visible from the 1.65m eye-level perspective.
  List<DetectedObstacle> filterHeadHeightHazards(List<DetectedObstacle> obstacles) {
    if (_mountMode != CameraMountMode.smartGlasses) return obstacles;

    final updated = <DetectedObstacle>[];
    for (final obs in obstacles) {
      // In eye-level perspective, obstacles in top half (yMin < 0.40) that are close (< 2.0m)
      // are dangerous head-height collisions
      final isHeadLevelCollision = obs.yMin < 0.40 && obs.distanceMeters < 2.0;
      if (isHeadLevelCollision) {
        updated.add(
          DetectedObstacle(
            label: 'HEAD_HAZARD_${obs.label.toUpperCase()}',
            confidence: obs.confidence,
            distanceMeters: obs.distanceMeters,
            xMin: obs.xMin,
            yMin: obs.yMin,
            xMax: obs.xMax,
            yMax: obs.yMax,
            ttcSeconds: obs.ttcSeconds,
            priority: AudioPriority.level0Critical,
            clockPosition: obs.clockPosition,
          ),
        );
      } else {
        updated.add(obs);
      }
    }
    return updated;
  }

  /// Disconnects smart glasses
  void disconnect() {
    _isConnected = false;
    _mountMode = CameraMountMode.handheld;
    _isStreaming = false;
    _openEarAudio = false;
    _broadcast();

    _audioMutex.speak(
      text: "Smart Glasses disconnected. Switched back to handheld phone mode.",
      priority: AudioPriority.level2Navigation,
      haptic: false,
    );
  }

  void _broadcast() {
    _stateController.add(currentState);
  }

  void dispose() {
    _stateController.close();
    _gestureController.close();
  }
}

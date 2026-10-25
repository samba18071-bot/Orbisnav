import 'dart:async';
import 'package:flutter/services.dart';
import '../controllers/audio_mutex_controller.dart';
import 'online_obstacle_detector.dart';

/// Vertical Hazard Elevation Zone
enum HazardElevationZone {
  headLevel,  // Low branches, signboards, scaffolding (>1.5m)
  torsoLevel, // Posts, furniture, walls (0.6m - 1.5m)
  dropOff,    // Downward stairs, curbs, subway platform edges (<0.6m)
}

/// 3D Spatial Earcon Cue metadata
class SpatialEarconCue {
  final HazardElevationZone zone;
  final double panStereo; // -1.0 (hard left) to +1.0 (hard right)
  final double pitchMultiplier; // 0.6 (low drop-off rumble) to 1.8 (high head alert)
  final int pulseCount;
  final String label;
  final double distanceMeters;
  final DateTime timestamp;

  const SpatialEarconCue({
    required this.zone,
    required this.panStereo,
    required this.pitchMultiplier,
    required this.pulseCount,
    required this.label,
    required this.distanceMeters,
    required this.timestamp,
  });
}

/// Service managing Day 16 3D Binaural Spatial Earcons & 3-Zone Vertical Hazard Classification.
class SpatialBinauralEarconService {
  final StreamController<SpatialEarconCue> _cueStreamController =
      StreamController<SpatialEarconCue>.broadcast();
  Stream<SpatialEarconCue> get cueStream => _cueStreamController.stream;

  SpatialEarconCue? _lastCue;
  SpatialEarconCue? get lastCue => _lastCue;

  SpatialBinauralEarconService({AudioMutexController? audioMutex});

  /// Evaluates an obstacle and dispatches a 3D Binaural Earcon and directional haptics.
  SpatialEarconCue dispatchSpatialEarcon({
    required DetectedObstacle obstacle,
    required double estimatedElevationMeters,
  }) {
    // If exclusive scene explanation is active, suppress earcons so user exclusively hears the AI scene analyser
    if (AudioMutexController().isSceneExplanationExclusive) {
      final cue = SpatialEarconCue(
        zone: HazardElevationZone.torsoLevel,
        panStereo: 0.0,
        pitchMultiplier: 1.0,
        pulseCount: 0,
        label: obstacle.label,
        distanceMeters: obstacle.distanceMeters,
        timestamp: DateTime.now(),
      );
      _lastCue = cue;
      return cue;
    }

    // 1. Determine Vertical Hazard Zone
    final HazardElevationZone zone;
    final double pitch;
    final int pulses;

    if (estimatedElevationMeters >= 1.5 ||
        obstacle.label.toLowerCase().contains('branch') ||
        obstacle.label.toLowerCase().contains('sign')) {
      zone = HazardElevationZone.headLevel;
      pitch = 1.8; // High-pitch earcon alert
      pulses = 3;
    } else if (estimatedElevationMeters <= 0.4 ||
        obstacle.label.toLowerCase().contains('stair') ||
        obstacle.label.toLowerCase().contains('curb')) {
      zone = HazardElevationZone.dropOff;
      pitch = 0.6; // Low-frequency rumble drop-off
      pulses = 1;
    } else {
      zone = HazardElevationZone.torsoLevel;
      pitch = 1.0;
      pulses = 2;
    }

    // 2. Compute Stereo Panning from Bounding Box Centroid (0.0 to 1.0 -> -1.0 to +1.0)
    final boxCenter = (obstacle.xMin + obstacle.xMax) / 2.0;
    final pan = ((boxCenter - 0.5) * 2.0).clamp(-1.0, 1.0);

    final cue = SpatialEarconCue(
      zone: zone,
      panStereo: pan,
      pitchMultiplier: pitch,
      pulseCount: pulses,
      label: obstacle.label,
      distanceMeters: obstacle.distanceMeters,
      timestamp: DateTime.now(),
    );

    _lastCue = cue;
    _cueStreamController.add(cue);

    // 3. Play Directional Tactile Haptic Pattern
    _triggerDirectionalHaptics(pan, zone);

    return cue;
  }

  Future<void> _triggerDirectionalHaptics(double pan, HazardElevationZone zone) async {
    try {
      if (zone == HazardElevationZone.headLevel) {
        await HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 80));
        await HapticFeedback.heavyImpact();
      } else if (zone == HazardElevationZone.dropOff) {
        await HapticFeedback.vibrate();
      } else {
        if (pan < -0.3) {
          await HapticFeedback.lightImpact();
        } else if (pan > 0.3) {
          await HapticFeedback.mediumImpact();
        } else {
          await HapticFeedback.selectionClick();
        }
      }
    } catch (_) {}
  }

  void dispose() {
    _cueStreamController.close();
  }
}

import '../controllers/audio_mutex_controller.dart';
import 'online_obstacle_detector.dart';

enum TactileCellType {
  clearCorridor,
  obstacleObject,
  wallBoundary,
  doorwayOrGoal,
  hazardOrDropOff,
}

class TactileTouchResult {
  final double normalizedX; // 0.0 left to 1.0 right
  final double normalizedY; // 0.0 top to 1.0 bottom (user is at bottom center: x=0.5, y=1.0)
  final TactileCellType cellType;
  final String label;
  final double distanceMeters;
  final bool shouldVibrate;
  final List<int> hapticPatternMs;

  const TactileTouchResult({
    required this.normalizedX,
    required this.normalizedY,
    required this.cellType,
    required this.label,
    required this.distanceMeters,
    required this.shouldVibrate,
    required this.hapticPatternMs,
  });
}

/// TactileHapticMapService:
/// Converts room vision and indoor graph into a touch-explorable tactile map screen.
/// Blind users drag their finger to "feel" what is in the room without walking forward.
class TactileHapticMapService {
  final AudioMutexController _audioMutex;
  List<DetectedObstacle> _activeObstacles = [];
  String? _lastAnnouncedLabel;
  DateTime? _lastAnnouncementTime;

  TactileHapticMapService({AudioMutexController? audioMutex})
      : _audioMutex = audioMutex ?? AudioMutexController();

  void updateObstacleGrid(List<DetectedObstacle> obstacles) {
    _activeObstacles = obstacles;
  }

  /// Evaluates finger coordinate on screen (0.0 to 1.0).
  /// User position is at Bottom Center (X: 0.5, Y: 1.0).
  /// Top of screen (Y: 0.0) is 5 meters ahead into the room.
  TactileTouchResult inspectScreenPoint(double touchX, double touchY) {
    // Check if touch point falls inside any detected obstacle bounding box
    DetectedObstacle? hitObstacle;

    for (final obstacle in _activeObstacles) {
      if (touchX >= obstacle.xMin &&
          touchX <= obstacle.xMax &&
          touchY >= obstacle.yMin &&
          touchY <= obstacle.yMax) {
        hitObstacle = obstacle;
        break;
      }
    }

    // Distance proportional to Y (0.0 = 5.0m ahead, 1.0 = 0.2m ahead)
    final estimatedDistance = ((1.0 - touchY) * 5.0).clamp(0.2, 5.0);

    if (hitObstacle != null) {
      final isDrop = hitObstacle.label.toLowerCase().contains("stair") ||
          hitObstacle.label.toLowerCase().contains("drop") ||
          hitObstacle.label.toLowerCase().contains("curb");

      final isDoor = hitObstacle.label.toLowerCase().contains("door") ||
          hitObstacle.label.toLowerCase().contains("exit");

      if (isDrop) {
        _announceOccasionally(hitObstacle.label);
        return TactileTouchResult(
          normalizedX: touchX,
          normalizedY: touchY,
          cellType: TactileCellType.hazardOrDropOff,
          label: hitObstacle.label,
          distanceMeters: estimatedDistance,
          shouldVibrate: true,
          hapticPatternMs: const [40, 40, 40, 40], // rapid alarm buzz
        );
      }

      if (isDoor) {
        _announceOccasionally(hitObstacle.label);
        return TactileTouchResult(
          normalizedX: touchX,
          normalizedY: touchY,
          cellType: TactileCellType.doorwayOrGoal,
          label: hitObstacle.label,
          distanceMeters: estimatedDistance,
          shouldVibrate: true,
          hapticPatternMs: const [100, 100], // distinct double tap
        );
      }

      _announceOccasionally(hitObstacle.label);
      return TactileTouchResult(
        normalizedX: touchX,
        normalizedY: touchY,
        cellType: TactileCellType.obstacleObject,
        label: hitObstacle.label,
        distanceMeters: estimatedDistance,
        shouldVibrate: true,
        hapticPatternMs: const [60], // solid tactile bump
      );
    }

    // Boundaries of the room (sides)
    if (touchX < 0.08 || touchX > 0.92) {
      return TactileTouchResult(
        normalizedX: touchX,
        normalizedY: touchY,
        cellType: TactileCellType.wallBoundary,
        label: "Wall Boundary",
        distanceMeters: estimatedDistance,
        shouldVibrate: true,
        hapticPatternMs: const [30],
      );
    }

    // Clear walkable path
    return TactileTouchResult(
      normalizedX: touchX,
      normalizedY: touchY,
      cellType: TactileCellType.clearCorridor,
      label: "Clear Walkable Path",
      distanceMeters: estimatedDistance,
      shouldVibrate: false,
      hapticPatternMs: const [],
    );
  }

  void _announceOccasionally(String label) {
    final now = DateTime.now();
    if (_lastAnnouncedLabel != label ||
        _lastAnnouncementTime == null ||
        now.difference(_lastAnnouncementTime!).inSeconds >= 2) {
      _lastAnnouncedLabel = label;
      _lastAnnouncementTime = now;
      _audioMutex.speak(
        text: label,
        priority: AudioPriority.level3Context,
        haptic: false,
      );
    }
  }

  void dispose() {}
}

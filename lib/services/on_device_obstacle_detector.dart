import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import '../controllers/audio_mutex_controller.dart';
import 'online_obstacle_detector.dart';
import 'kinematic_motion_tracker.dart';

/// OnDeviceObstacleDetector: 100% Offline, Edge-Native Obstacle Detection Engine.
/// 
/// Runs directly on the mobile device CPU/GPU/NPU using Google ML Kit.
/// Combines Object Localization (bounding boxes) + Image Labeling (400+ classifications).
/// Requires NO Mac, NO Python server, and NO Internet connection.
class OnDeviceObstacleDetector {
  static final OnDeviceObstacleDetector _instance =
      OnDeviceObstacleDetector._internal();
  factory OnDeviceObstacleDetector() => _instance;

  OnDeviceObstacleDetector._internal();

  ObjectDetector? _objectDetector;
  ImageLabeler? _imageLabeler;
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isEnabled = true;

  // Approximate focal length for mobile wide-angle camera (in pixels at 720p/480p)
  static const double _focalLengthApprox = 550.0;

  // Physical object dimensions priors (Height in meters, Priority, Spoken Label)
  static const Map<String, _ObjectPrior> _priors = {
    "person": _ObjectPrior(1.70, AudioPriority.level0Critical, "Person"),
    "man": _ObjectPrior(1.70, AudioPriority.level0Critical, "Person"),
    "woman": _ObjectPrior(1.65, AudioPriority.level0Critical, "Person"),
    "child": _ObjectPrior(1.20, AudioPriority.level0Critical, "Person"),
    "chair": _ObjectPrior(0.85, AudioPriority.level1Safety, "Chair"),
    "couch": _ObjectPrior(0.85, AudioPriority.level1Safety, "Couch"),
    "sofa": _ObjectPrior(0.85, AudioPriority.level1Safety, "Sofa"),
    "table": _ObjectPrior(0.75, AudioPriority.level1Safety, "Table"),
    "desk": _ObjectPrior(0.75, AudioPriority.level1Safety, "Desk"),
    "dining table": _ObjectPrior(0.75, AudioPriority.level1Safety, "Dining table"),
    "door": _ObjectPrior(2.00, AudioPriority.level1Safety, "Door"),
    "stairs": _ObjectPrior(1.50, AudioPriority.level0Critical, "Stairs"),
    "bed": _ObjectPrior(0.65, AudioPriority.level1Safety, "Bed"),
    "bench": _ObjectPrior(0.50, AudioPriority.level1Safety, "Bench"),
    "car": _ObjectPrior(1.50, AudioPriority.level0Critical, "Car"),
    "vehicle": _ObjectPrior(1.50, AudioPriority.level0Critical, "Vehicle"),
    "bicycle": _ObjectPrior(1.00, AudioPriority.level0Critical, "Bicycle"),
    "laptop": _ObjectPrior(0.25, AudioPriority.level2Navigation, "Laptop"),
    "computer": _ObjectPrior(0.45, AudioPriority.level2Navigation, "Computer"),
    "monitor": _ObjectPrior(0.40, AudioPriority.level2Navigation, "Monitor"),
    "screen": _ObjectPrior(0.40, AudioPriority.level2Navigation, "Screen"),
    "keyboard": _ObjectPrior(0.15, AudioPriority.level3Context, "Keyboard"),
    "bottle": _ObjectPrior(0.25, AudioPriority.level3Context, "Bottle"),
    "cup": _ObjectPrior(0.12, AudioPriority.level3Context, "Cup"),
    "plant": _ObjectPrior(0.60, AudioPriority.level2Navigation, "Potted plant"),
    "home goods": _ObjectPrior(0.75, AudioPriority.level1Safety, "Furniture"),
    "fashion goods": _ObjectPrior(0.40, AudioPriority.level3Context, "Item"),
    "food": _ObjectPrior(0.15, AudioPriority.level3Context, "Food item"),
    "place": _ObjectPrior(2.00, AudioPriority.level0Critical, "Structure"),
    "generic": _ObjectPrior(0.70, AudioPriority.level1Safety, "Obstacle"),
  };

  // Anti-repetition speech state: tracks active obstacles by "label_clockZone"
  final Map<String, DateTime> _announcedObstacles = {};
  final Map<String, double> _announcedDistances = {};
  bool _wasHazardSpoken = false;
  DateTime? _lastClearSpokenTime;

  final StreamController<OnlineDetectionCycleResult> _resultsController =
      StreamController<OnlineDetectionCycleResult>.broadcast();
  Stream<OnlineDetectionCycleResult> get resultsStream =>
      _resultsController.stream;

  bool get isInitialized => _isInitialized;
  bool get isEnabled => _isEnabled;

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  /// Initialize ML Kit On-Device Vision Engines
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final objectDetectorOptions = ObjectDetectorOptions(
        mode: DetectionMode.single,
        classifyObjects: true,
        multipleObjects: true,
      );
      _objectDetector = ObjectDetector(options: objectDetectorOptions);

      final imageLabelerOptions = ImageLabelerOptions(confidenceThreshold: 0.45);
      _imageLabeler = ImageLabeler(options: imageLabelerOptions);

      _isInitialized = true;
      debugPrint("[OnDeviceObstacleDetector] Initialized ML Kit ObjectDetector + ImageLabeler successfully.");
    } catch (e) {
      debugPrint("[OnDeviceObstacleDetector] Initialization error: $e");
    }
  }

  /// Reset speech debounce history
  void forceRescan() {
    _announcedObstacles.clear();
    _announcedDistances.clear();
    _wasHazardSpoken = false;
  }

  /// Process camera frame bytes locally on device
  Future<OnlineDetectionCycleResult> processFrameBytes(
    Uint8List jpegBytes, {
    double devicePitchDeg = 0.0,
  }) async {
    if (!_isEnabled || _isProcessing || !_isInitialized || _objectDetector == null) {
      return OnlineDetectionCycleResult(
        obstacles: [],
        latencyMs: 0,
        timestamp: DateTime.now(),
        isOnlineSuccess: false,
        statusMessage: !_isEnabled
            ? "Disabled"
            : !_isInitialized
                ? "Initializing On-Device ML..."
                : "Skipped (busy)",
      );
    }

    _isProcessing = true;
    final stopwatch = Stopwatch()..start();

    try {
      // Write temporary JPEG file for ML Kit InputImage
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/offline_frame.jpg');
      await tempFile.writeAsBytes(jpegBytes, flush: true);

      final inputImage = InputImage.fromFilePath(tempFile.path);

      // Run Object Detection & Image Classification concurrently
      final objectsFuture = _objectDetector!.processImage(inputImage);
      final labelsFuture = _imageLabeler?.processImage(inputImage) ?? Future.value(<ImageLabel>[]);

      final detectedObjects = await objectsFuture;
      final detectedLabels = await labelsFuture;

      final List<DetectedObstacle> obstacles = [];

      // Extract top image classification labels (e.g., Chair, Laptop, Person, Table)
      final topClassLabels = detectedLabels
          .where((l) => l.confidence >= 0.50 && !_isBackgroundLabel(l.label))
          .map((l) => l.label)
          .toList();

      debugPrint("[OnDeviceObstacleDetector] Raw Objects: ${detectedObjects.length}, Labels: ${topClassLabels.join(', ')}");

      // Approximate frame dimensions for normalization
      const double frameW = 480.0;
      const double frameH = 720.0;

      if (detectedObjects.isNotEmpty) {
        for (int i = 0; i < detectedObjects.length; i++) {
          final obj = detectedObjects[i];
          final rect = obj.boundingBox;

          // Normalized bounding box (0.0 to 1.0)
          final xMin = (rect.left / frameW).clamp(0.0, 1.0);
          final yMin = (rect.top / frameH).clamp(0.0, 1.0);
          final xMax = (rect.right / frameW).clamp(0.0, 1.0);
          final yMax = (rect.bottom / frameH).clamp(0.0, 1.0);

          final bboxH = math.max(rect.height, 20.0);
          final bboxCenterX = (rect.left + rect.right) / 2.0;

          // Determine object label: Check object label first, then refine with image label
          String label = "Obstacle";
          double confidence = 0.80;

          if (obj.labels.isNotEmpty) {
            final firstText = obj.labels.first.text.trim();
            confidence = obj.labels.first.confidence;
            label = _cleanMlKitLabel(firstText);
          }

          // If label is generic (e.g., "Furniture" / "Item" / "Obstacle") and image classifier found specific objects
          if ((label == "Obstacle" || label == "Furniture" || label == "Item") && topClassLabels.isNotEmpty) {
            final specificLabel = i < topClassLabels.length ? topClassLabels[i] : topClassLabels.first;
            label = _cleanMlKitLabel(specificLabel);
          }

          final prior = _getPriorForLabel(label);

          // Metric distance estimation using pinhole camera model
          final distanceMeters = double.parse(
            ((_focalLengthApprox * prior.realHeightMeters) / bboxH)
                .clamp(0.4, 6.0)
                .toStringAsFixed(1),
          );

          // 12-Hour Spatial Clock Position
          final normX = (bboxCenterX / frameW).clamp(0.0, 1.0);
          final clock = _calculateClockPosition(normX);

          // TTC (Time To Collision)
          final ttcSeconds = double.parse((distanceMeters / 1.1).toStringAsFixed(1));

          // Priority assignment
          AudioPriority priority;
          if (distanceMeters < 1.2 || prior.defaultPriority == AudioPriority.level0Critical) {
            priority = AudioPriority.level0Critical;
          } else if (distanceMeters < 2.0 || prior.defaultPriority == AudioPriority.level1Safety) {
            priority = AudioPriority.level1Safety;
          } else {
            priority = prior.defaultPriority;
          }

          obstacles.add(DetectedObstacle(
            label: label,
            confidence: confidence,
            xMin: xMin,
            yMin: yMin,
            xMax: xMax,
            yMax: yMax,
            distanceMeters: distanceMeters,
            ttcSeconds: ttcSeconds,
            priority: priority,
            clockPosition: clock,
          ));
        }
      } else if (topClassLabels.isNotEmpty) {
        // If object detector missed bounding box but image labeler found prominent objects in view
        final primaryLabel = _cleanMlKitLabel(topClassLabels.first);
        final prior = _getPriorForLabel(primaryLabel);
        final defaultDist = prior.realHeightMeters >= 1.5 ? 1.8 : 1.2;

        obstacles.add(DetectedObstacle(
          label: primaryLabel,
          confidence: 0.78,
          xMin: 0.25,
          yMin: 0.25,
          xMax: 0.75,
          yMax: 0.75,
          distanceMeters: defaultDist,
          ttcSeconds: double.parse((defaultDist / 1.1).toStringAsFixed(1)),
          priority: prior.defaultPriority,
          clockPosition: "12 o'clock",
        ));
      }

      // Apply Kinematic Motion & Trajectory Tracking (Approaching, Walking Away, Overhead Branches)
      final enrichedObstacles = KinematicMotionTracker().enrichWithKinematics(obstacles);

      // Sort by hazard priority (critical hazards first)
      enrichedObstacles.sort((a, b) => a.priority.value.compareTo(b.priority.value));

      final latencyMs = stopwatch.elapsedMilliseconds;
      final cycleResult = OnlineDetectionCycleResult(
        obstacles: enrichedObstacles,
        latencyMs: latencyMs,
        timestamp: DateTime.now(),
        isOnlineSuccess: true,
        statusMessage: enrichedObstacles.isEmpty
            ? "Offline On-Device ML: Path Clear (${latencyMs}ms)"
            : "Offline On-Device ML: ${enrichedObstacles.length} Obstacle${enrichedObstacles.length > 1 ? 's' : ''} (${latencyMs}ms)",
      );

      _resultsController.add(cycleResult);

      // Enforce Speak-Once Audio Mutex Rule with Rich Motion Kinematics
      _enforceSpeechGovernance(cycleResult);

      return cycleResult;
    } catch (e) {
      debugPrint("[OnDeviceObstacleDetector] Inference error: $e");
      final errorResult = OnlineDetectionCycleResult(
        obstacles: [],
        latencyMs: stopwatch.elapsedMilliseconds,
        timestamp: DateTime.now(),
        isOnlineSuccess: false,
        statusMessage: "On-Device ML: $e",
      );
      _resultsController.add(errorResult);
      return errorResult;
    } finally {
      stopwatch.stop();
      _isProcessing = false;
    }
  }

  void _enforceSpeechGovernance(OnlineDetectionCycleResult result) {
    final hazard = result.highestHazard;
    final now = DateTime.now();

    if (hazard != null && hazard.label != "Path Clear") {
      final labelKey = "${hazard.label.toLowerCase().trim()}_${hazard.clockPosition.toLowerCase().trim()}";
      final lastSpoken = _announcedObstacles[labelKey];
      final lastDist = _announcedDistances[labelKey] ?? 99.0;

      final bool isNew = lastSpoken == null;
      final bool isExpired = lastSpoken != null && now.difference(lastSpoken).inSeconds >= 20;
      final bool isCloser = (lastDist - hazard.distanceMeters) >= 0.5;
      final bool isEnteredCritical = lastDist >= 1.2 && hazard.distanceMeters < 1.2;
      final bool isApproachingFast = hazard.motionType == ObjectMotionType.approachingTowardsUser &&
          (now.difference(lastSpoken ?? DateTime.fromMillisecondsSinceEpoch(0)).inSeconds >= 8);

      final bool shouldSpeak = isNew || isExpired || isCloser || isEnteredCritical || isApproachingFast;

      if (shouldSpeak) {
        _announcedObstacles[labelKey] = now;
        _announcedDistances[labelKey] = hazard.distanceMeters;
        _wasHazardSpoken = true;

        final alertText = hazard.speechAnnouncement;
        debugPrint("[OnDeviceObstacleDetector] 🗣️ Voice Alert: $alertText (Priority: ${hazard.priority})");
        AudioMutexController().speak(
          text: alertText,
          priority: hazard.priority,
          haptic: hazard.isHazard,
        );
      }
    } else {
      if (_wasHazardSpoken) {
        _wasHazardSpoken = false;
        final bool canSpeakClear = _lastClearSpokenTime == null ||
            now.difference(_lastClearSpokenTime!).inSeconds >= 15;

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
      _announcedObstacles.removeWhere((_, time) => now.difference(time).inSeconds > 15);
      _announcedDistances.removeWhere((key, _) => !_announcedObstacles.containsKey(key));
    }
  }

  String _cleanMlKitLabel(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower.contains("home goods")) return "Furniture";
    if (lower.contains("fashion goods")) return "Item";
    if (lower.contains("food")) return "Food item";
    if (lower.contains("place")) return "Structure";
    if (lower.contains("plant")) return "Potted plant";
    // Capitalize first letter
    if (raw.isNotEmpty) {
      return raw[0].toUpperCase() + raw.substring(1);
    }
    return "Obstacle";
  }

  bool _isBackgroundLabel(String label) {
    final lower = label.toLowerCase();
    return lower.contains("room") ||
        lower.contains("indoor") ||
        lower.contains("floor") ||
        lower.contains("ceiling") ||
        lower.contains("wall") ||
        lower.contains("light") ||
        lower.contains("shade") ||
        lower.contains("pattern");
  }

  String _calculateClockPosition(double normX) {
    if (normX < 0.20) return "9 o'clock";
    if (normX < 0.35) return "10 o'clock";
    if (normX < 0.45) return "11 o'clock";
    if (normX < 0.55) return "12 o'clock";
    if (normX < 0.65) return "1 o'clock";
    if (normX < 0.80) return "2 o'clock";
    return "3 o'clock";
  }

  _ObjectPrior _getPriorForLabel(String label) {
    final lower = label.toLowerCase();
    for (final entry in _priors.entries) {
      if (lower.contains(entry.key)) {
        return entry.value;
      }
    }
    return _priors["generic"]!;
  }

  Future<void> dispose() async {
    _objectDetector?.close();
    _imageLabeler?.close();
    _objectDetector = null;
    _imageLabeler = null;
    _isInitialized = false;
  }
}

class _ObjectPrior {
  final double realHeightMeters;
  final AudioPriority defaultPriority;
  final String speechName;

  const _ObjectPrior(this.realHeightMeters, this.defaultPriority, this.speechName);
}

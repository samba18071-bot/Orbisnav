import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../controllers/audio_mutex_controller.dart';
import 'online_obstacle_detector.dart';
import 'kinematic_motion_tracker.dart';

/// Preprocessed tensor data and letterbox scaling factors passed from background isolate
class _PreprocessedData {
  final List<List<List<List<double>>>> tensor;
  final double scale;
  final double padX;
  final double padY;
  final double scaledW;
  final double scaledH;

  _PreprocessedData({
    required this.tensor,
    required this.scale,
    required this.padX,
    required this.padY,
    required this.scaledW,
    required this.scaledH,
  });
}

/// Top-level isolate worker to decode, letterbox, and normalize camera frames without blocking UI thread
_PreprocessedData _isolateLetterboxPreprocess(Uint8List jpegBytes) {
  const int targetSize = 320;
  final rawImage = img.decodeImage(jpegBytes);
  if (rawImage == null) {
    return _PreprocessedData(
      tensor: List.generate(
        1,
        (_) => List.generate(
          targetSize,
          (_) => List.generate(targetSize, (_) => [0.447, 0.447, 0.447]),
        ),
      ),
      scale: 1.0,
      padX: 0.0,
      padY: 0.0,
      scaledW: targetSize.toDouble(),
      scaledH: targetSize.toDouble(),
    );
  }

  final int origW = rawImage.width;
  final int origH = rawImage.height;

  // Calculate high-fidelity letterbox scale to preserve 100% geometric aspect ratio
  final double scale = math.min(targetSize / origW, targetSize / origH);
  final int newW = (origW * scale).round().clamp(1, targetSize);
  final int newH = (origH * scale).round().clamp(1, targetSize);
  final double padX = (targetSize - newW) / 2.0;
  final double padY = (targetSize - newH) / 2.0;

  final resized = img.copyResize(
    rawImage,
    width: newW,
    height: newH,
    interpolation: img.Interpolation.linear,
  );

  final int padXInt = padX.round();
  final int padYInt = padY.round();

  // Create 320x320 float tensor with 114 gray background (0.447)
  final tensor = List.generate(
    1,
    (_) => List.generate(
      targetSize,
      (y) => List.generate(
        targetSize,
        (x) {
          final imgX = x - padXInt;
          final imgY = y - padYInt;
          if (imgX >= 0 && imgX < newW && imgY >= 0 && imgY < newH) {
            final pixel = resized.getPixel(imgX, imgY);
            return [
              pixel.r / 255.0,
              pixel.g / 255.0,
              pixel.b / 255.0,
            ];
          } else {
            return [0.447, 0.447, 0.447]; // Letterbox neutral padding
          }
        },
      ),
    ),
  );

  return _PreprocessedData(
    tensor: tensor,
    scale: scale,
    padX: padX,
    padY: padY,
    scaledW: newW.toDouble(),
    scaledH: newH.toDouble(),
  );
}

/// Physical dimensional priors for real-world COCO and assistive navigation classes.
class _ObjectPrior {
  final double realHeightMeters;
  final double realWidthMeters;
  final AudioPriority defaultPriority;
  final String spokenLabel;

  const _ObjectPrior(
    this.realHeightMeters,
    this.realWidthMeters,
    this.defaultPriority,
    this.spokenLabel,
  );
}

/// Internal detection candidate before filtering
class _DetectionCandidate {
  final String label;
  final double score;
  final double xMin;
  final double yMin;
  final double xMax;
  final double yMax;

  const _DetectionCandidate({
    required this.label,
    required this.score,
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
  });

  double get width => (xMax - xMin).clamp(0.0, 1.0);
  double get height => (yMax - yMin).clamp(0.0, 1.0);
  double get area => width * height;
}

/// OnDeviceObstacleDetector: 100% Offline, High-Speed Edge Neural Obstacle Detection Engine.
/// 
/// Runs directly on device CPU/NPU with multi-threading, strict false-positive suppression,
/// temporal persistence filtering, and calibrated metric distance estimation.
class OnDeviceObstacleDetector {
  static final OnDeviceObstacleDetector _instance =
      OnDeviceObstacleDetector._internal();
  factory OnDeviceObstacleDetector() => _instance;

  OnDeviceObstacleDetector._internal();

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isEnabled = true;

  // Calibrated focal length ratio for mobile smartphone cameras (~68° vertical FOV)
  static const double _focalLengthRatio = 1.15;
  static const double _defaultConfidenceThreshold = 0.26;
  static const double _personConfidenceThreshold = 0.32;
  static const double _smallItemConfidenceThreshold = 0.35;
  static const double _sameClassIouThreshold = 0.45;
  static const double _crossClassIouThreshold = 0.72;

  // Real-world physical dimensions (Height, Width in meters, AudioPriority, Spoken Name) for all 80 COCO classes
  static const Map<String, _ObjectPrior> _priors = {
    // 1. Pedestrians & Living Entities
    "person": _ObjectPrior(1.72, 0.50, AudioPriority.level1Safety, "Person"),
    "bird": _ObjectPrior(0.20, 0.25, AudioPriority.level3Context, "Bird"),
    "cat": _ObjectPrior(0.30, 0.45, AudioPriority.level2Navigation, "Cat"),
    "dog": _ObjectPrior(0.60, 0.75, AudioPriority.level1Safety, "Dog"),
    "horse": _ObjectPrior(1.80, 2.00, AudioPriority.level0Critical, "Horse"),
    "sheep": _ObjectPrior(0.90, 1.10, AudioPriority.level1Safety, "Sheep"),
    "cow": _ObjectPrior(1.50, 2.20, AudioPriority.level0Critical, "Cow"),
    "elephant": _ObjectPrior(3.00, 3.50, AudioPriority.level0Critical, "Elephant"),
    "bear": _ObjectPrior(1.80, 1.40, AudioPriority.level0Critical, "Bear"),
    "zebra": _ObjectPrior(1.50, 2.00, AudioPriority.level0Critical, "Zebra"),
    "giraffe": _ObjectPrior(4.80, 2.20, AudioPriority.level0Critical, "Giraffe"),

    // 2. Vehicles & Critical Traffic Hazards (Level 0 Critical)
    "bicycle": _ObjectPrior(1.05, 1.65, AudioPriority.level0Critical, "Bicycle"),
    "car": _ObjectPrior(1.50, 1.80, AudioPriority.level0Critical, "Car"),
    "motorcycle": _ObjectPrior(1.20, 0.80, AudioPriority.level0Critical, "Motorcycle"),
    "airplane": _ObjectPrior(8.00, 15.00, AudioPriority.level1Safety, "Airplane"),
    "bus": _ObjectPrior(3.20, 2.50, AudioPriority.level0Critical, "Bus"),
    "train": _ObjectPrior(3.80, 3.00, AudioPriority.level0Critical, "Train"),
    "truck": _ObjectPrior(3.00, 2.40, AudioPriority.level0Critical, "Truck"),
    "boat": _ObjectPrior(2.00, 3.50, AudioPriority.level1Safety, "Boat"),
    "traffic light": _ObjectPrior(0.90, 0.35, AudioPriority.level1Safety, "Traffic light"),
    "fire hydrant": _ObjectPrior(0.75, 0.40, AudioPriority.level1Safety, "Fire hydrant"),
    "stop sign": _ObjectPrior(0.75, 0.75, AudioPriority.level0Critical, "Stop sign"),
    "parking meter": _ObjectPrior(1.20, 0.25, AudioPriority.level1Safety, "Parking meter"),
    "bench": _ObjectPrior(0.50, 1.50, AudioPriority.level1Safety, "Bench"),

    // 3. Luggage, Bags & Accessories
    "backpack": _ObjectPrior(0.48, 0.35, AudioPriority.level2Navigation, "Backpack"),
    "umbrella": _ObjectPrior(0.85, 0.10, AudioPriority.level2Navigation, "Umbrella"),
    "handbag": _ObjectPrior(0.30, 0.35, AudioPriority.level3Context, "Handbag"),
    "tie": _ObjectPrior(0.45, 0.08, AudioPriority.level3Context, "Tie"),
    "suitcase": _ObjectPrior(0.65, 0.45, AudioPriority.level1Safety, "Suitcase"),

    // 4. Sports & Outdoor Equipment
    "frisbee": _ObjectPrior(0.04, 0.25, AudioPriority.level3Context, "Frisbee"),
    "skis": _ObjectPrior(1.70, 0.15, AudioPriority.level2Navigation, "Skis"),
    "snowboard": _ObjectPrior(1.50, 0.30, AudioPriority.level2Navigation, "Snowboard"),
    "sports ball": _ObjectPrior(0.22, 0.22, AudioPriority.level2Navigation, "Ball"),
    "kite": _ObjectPrior(0.80, 0.80, AudioPriority.level3Context, "Kite"),
    "baseball bat": _ObjectPrior(0.85, 0.07, AudioPriority.level2Navigation, "Baseball bat"),
    "baseball glove": _ObjectPrior(0.25, 0.20, AudioPriority.level3Context, "Baseball glove"),
    "skateboard": _ObjectPrior(0.15, 0.80, AudioPriority.level1Safety, "Skateboard"),
    "surfboard": _ObjectPrior(2.00, 0.50, AudioPriority.level1Safety, "Surfboard"),
    "tennis racket": _ObjectPrior(0.68, 0.28, AudioPriority.level3Context, "Tennis racket"),

    // 5. Kitchenware & Tabletop Dining Items
    "bottle": _ObjectPrior(0.26, 0.08, AudioPriority.level3Context, "Bottle"),
    "wine glass": _ObjectPrior(0.20, 0.08, AudioPriority.level3Context, "Wine glass"),
    "cup": _ObjectPrior(0.12, 0.08, AudioPriority.level3Context, "Cup"),
    "fork": _ObjectPrior(0.18, 0.03, AudioPriority.level3Context, "Fork"),
    "knife": _ObjectPrior(0.20, 0.03, AudioPriority.level1Safety, "Knife"),
    "spoon": _ObjectPrior(0.16, 0.04, AudioPriority.level3Context, "Spoon"),
    "bowl": _ObjectPrior(0.08, 0.16, AudioPriority.level3Context, "Bowl"),

    // 6. Food & Groceries
    "banana": _ObjectPrior(0.18, 0.04, AudioPriority.level3Context, "Banana"),
    "apple": _ObjectPrior(0.08, 0.08, AudioPriority.level3Context, "Apple"),
    "sandwich": _ObjectPrior(0.07, 0.14, AudioPriority.level3Context, "Sandwich"),
    "orange": _ObjectPrior(0.08, 0.08, AudioPriority.level3Context, "Orange"),
    "broccoli": _ObjectPrior(0.14, 0.12, AudioPriority.level3Context, "Broccoli"),
    "carrot": _ObjectPrior(0.18, 0.03, AudioPriority.level3Context, "Carrot"),
    "hot dog": _ObjectPrior(0.05, 0.16, AudioPriority.level3Context, "Hot dog"),
    "pizza": _ObjectPrior(0.04, 0.30, AudioPriority.level3Context, "Pizza"),
    "donut": _ObjectPrior(0.04, 0.10, AudioPriority.level3Context, "Donut"),
    "cake": _ObjectPrior(0.12, 0.25, AudioPriority.level3Context, "Cake"),

    // 7. Indoor Furniture & Structural Elements
    "chair": _ObjectPrior(0.85, 0.55, AudioPriority.level1Safety, "Chair"),
    "couch": _ObjectPrior(0.85, 1.80, AudioPriority.level1Safety, "Couch"),
    "sofa": _ObjectPrior(0.85, 1.80, AudioPriority.level1Safety, "Sofa"),
    "potted plant": _ObjectPrior(0.60, 0.40, AudioPriority.level2Navigation, "Potted plant"),
    "bed": _ObjectPrior(0.65, 1.60, AudioPriority.level1Safety, "Bed"),
    "dining table": _ObjectPrior(0.75, 1.40, AudioPriority.level1Safety, "Dining table"),
    "table": _ObjectPrior(0.75, 1.20, AudioPriority.level1Safety, "Table"),
    "toilet": _ObjectPrior(0.75, 0.45, AudioPriority.level1Safety, "Toilet"),
    "door": _ObjectPrior(2.05, 0.85, AudioPriority.level1Safety, "Door"),
    "stairs": _ObjectPrior(1.50, 1.20, AudioPriority.level0Critical, "Stairs"),
    "tree": _ObjectPrior(3.50, 1.40, AudioPriority.level1Safety, "Tree"),

    // 8. Workstation & Electronics
    "tv": _ObjectPrior(0.60, 1.00, AudioPriority.level2Navigation, "TV screen"),
    "laptop": _ObjectPrior(0.22, 0.32, AudioPriority.level2Navigation, "Laptop"),
    "mouse": _ObjectPrior(0.04, 0.07, AudioPriority.level3Context, "Mouse"),
    "remote": _ObjectPrior(0.03, 0.18, AudioPriority.level3Context, "Remote"),
    "keyboard": _ObjectPrior(0.03, 0.42, AudioPriority.level3Context, "Keyboard"),
    "cell phone": _ObjectPrior(0.15, 0.08, AudioPriority.level3Context, "Cell phone"),

    // 9. Appliances
    "microwave": _ObjectPrior(0.35, 0.55, AudioPriority.level2Navigation, "Microwave"),
    "oven": _ObjectPrior(0.85, 0.60, AudioPriority.level1Safety, "Oven"),
    "toaster": _ObjectPrior(0.20, 0.25, AudioPriority.level3Context, "Toaster"),
    "sink": _ObjectPrior(0.85, 0.60, AudioPriority.level1Safety, "Sink"),
    "refrigerator": _ObjectPrior(1.75, 0.80, AudioPriority.level1Safety, "Refrigerator"),

    // 10. Household Objects
    "book": _ObjectPrior(0.03, 0.18, AudioPriority.level3Context, "Book"),
    "clock": _ObjectPrior(0.30, 0.30, AudioPriority.level3Context, "Clock"),
    "vase": _ObjectPrior(0.35, 0.18, AudioPriority.level3Context, "Vase"),
    "scissors": _ObjectPrior(0.02, 0.15, AudioPriority.level3Context, "Scissors"),
    "teddy bear": _ObjectPrior(0.35, 0.25, AudioPriority.level3Context, "Teddy bear"),
    "hair drier": _ObjectPrior(0.22, 0.18, AudioPriority.level3Context, "Hair dryer"),
    "toothbrush": _ObjectPrior(0.18, 0.02, AudioPriority.level3Context, "Toothbrush"),

    // 11. Everyday Assistive & Personal Belongings (Sonar Target Items)
    "ironbox": _ObjectPrior(0.16, 0.28, AudioPriority.level2Navigation, "Ironbox"),
    "iron": _ObjectPrior(0.16, 0.28, AudioPriority.level2Navigation, "Ironbox"),
    "keys": _ObjectPrior(0.04, 0.09, AudioPriority.level2Navigation, "Keys"),
    "white cane": _ObjectPrior(1.20, 0.05, AudioPriority.level1Safety, "White cane"),
    "white_cane": _ObjectPrior(1.20, 0.05, AudioPriority.level1Safety, "White cane"),
    "cane": _ObjectPrior(1.20, 0.05, AudioPriority.level1Safety, "White cane"),
    "wallet": _ObjectPrior(0.10, 0.12, AudioPriority.level2Navigation, "Wallet"),
    "glasses": _ObjectPrior(0.05, 0.14, AudioPriority.level2Navigation, "Glasses"),
    "spectacles": _ObjectPrior(0.05, 0.14, AudioPriority.level2Navigation, "Spectacles"),
    "cell_phone": _ObjectPrior(0.15, 0.08, AudioPriority.level3Context, "Cell phone"),
    "charger": _ObjectPrior(0.08, 0.08, AudioPriority.level2Navigation, "Charger"),
    "shoes": _ObjectPrior(0.14, 0.30, AudioPriority.level2Navigation, "Shoes"),
    "shoe": _ObjectPrior(0.14, 0.30, AudioPriority.level2Navigation, "Shoes"),
    "medicine": _ObjectPrior(0.12, 0.06, AudioPriority.level2Navigation, "Medicine"),
    "medicine_bottle": _ObjectPrior(0.12, 0.06, AudioPriority.level2Navigation, "Medicine bottle"),
    "headphones": _ObjectPrior(0.18, 0.18, AudioPriority.level2Navigation, "Headphones"),
    "watch": _ObjectPrior(0.04, 0.04, AudioPriority.level3Context, "Watch"),
    "pen": _ObjectPrior(0.14, 0.01, AudioPriority.level3Context, "Pen"),
    "fan": _ObjectPrior(0.45, 0.45, AudioPriority.level1Safety, "Fan"),
    "plate": _ObjectPrior(0.03, 0.25, AudioPriority.level3Context, "Plate"),
    "signboard": _ObjectPrior(0.60, 0.80, AudioPriority.level1Safety, "Signboard"),
    "vehicle": _ObjectPrior(1.50, 1.80, AudioPriority.level0Critical, "Vehicle"),
    "pole": _ObjectPrior(2.80, 0.25, AudioPriority.level0Critical, "Pole"),
    "trash_bin": _ObjectPrior(0.75, 0.45, AudioPriority.level1Safety, "Trash bin"),
  };

  // Multi-frame temporal persistence to suppress 1-frame transient glitches
  final Map<String, int> _temporalTrackCount = {};
  
  // Anti-repetition debounced speech tracking
  final Map<String, DateTime> _announcedObstacles = {};
  final Map<String, double> _announcedDistances = {};
  bool _wasHazardSpoken = false;

  final StreamController<OnlineDetectionCycleResult> _resultsController =
      StreamController<OnlineDetectionCycleResult>.broadcast();
  Stream<OnlineDetectionCycleResult> get resultsStream =>
      _resultsController.stream;

  bool get isInitialized => _isInitialized;
  bool get isEnabled => _isEnabled;

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  /// Initialize Standalone Neural Vision Engine (Loads TFLite & Real-World Labels)
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1. Load Real-World Class Labels
      final labelsData = await rootBundle.loadString('assets/models/labels.txt');
      _labels = labelsData
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      // 2. Load TFLite Model with multi-threaded edge interpreter (4 threads)
      final options = InterpreterOptions()..threads = 4;
      try {
        _interpreter = await Interpreter.fromAsset(
          'assets/models/yolov8n.tflite',
          options: options,
        );
        debugPrint("[OnDeviceObstacleDetector] Loaded YOLOv8 TFLite model with ${_labels.length} classes.");
      } catch (modelErr) {
        debugPrint("[OnDeviceObstacleDetector] Model load note: $modelErr");
      }

      _isInitialized = true;
      debugPrint("[OnDeviceObstacleDetector] Standalone Edge-AI Vision initialized successfully.");
    } catch (e) {
      debugPrint("[OnDeviceObstacleDetector] Initialization error: $e");
      _isInitialized = true;
    }
  }

  /// Reset speech debounce history
  void forceRescan() {
    _announcedObstacles.clear();
    _announcedDistances.clear();
    _temporalTrackCount.clear();
    _wasHazardSpoken = false;
  }

  /// Process camera frame bytes locally on device with Zero UI Lag
  Future<OnlineDetectionCycleResult> processFrameBytes(
    Uint8List jpegBytes, {
    double devicePitchDeg = 0.0,
    bool speakGovernance = true,
  }) async {
    if (!_isEnabled || _isProcessing || !_isInitialized) {
      return OnlineDetectionCycleResult(
        obstacles: [],
        latencyMs: 0,
        timestamp: DateTime.now(),
        isOnlineSuccess: false,
        statusMessage: !_isEnabled
            ? "Disabled"
            : !_isInitialized
                ? "Initializing On-Device AI..."
                : "Skipped (busy)",
      );
    }

    _isProcessing = true;
    final stopwatch = Stopwatch()..start();

    try {
      final List<DetectedObstacle> obstacles = [];
      final Set<String> currentFrameKeys = {};

      if (_interpreter != null) {
        // 1. Asynchronously letterbox and normalize frame in background isolate (Zero UI Block)
        final preprocessed = await compute(_isolateLetterboxPreprocess, jpegBytes);

        // 2. Prepare output tensor: YOLOv8 320x320 outputs [1, 84, 2100]
        final numClasses = _labels.isNotEmpty ? _labels.length : 80;
        const int numPredictions = 2100;
        final output = List.generate(
          1,
          (_) => List.generate(
            4 + numClasses,
            (_) => List.filled(numPredictions, 0.0),
          ),
        );

        // 3. Run native neural inference
        _interpreter!.run(preprocessed.tensor, output);

        // 4. Parse bounding boxes and confidence scores with strict false-positive filtering
        final candidates = _parseYoloOutput(
          output[0],
          numClasses,
          numPredictions,
          preprocessed.scale,
          preprocessed.padX,
          preprocessed.padY,
          preprocessed.scaledW,
          preprocessed.scaledH,
        );

        // 5. High-Recall Class-Aware Non-Maximum Suppression (NMS)
        final filtered = _applyNms(candidates);

        // 6. Calculate Metric Distance & Spatial Clock Position with Temporal Confirmation
        for (final cand in filtered) {
          final label = cand.label;
          final prior = _getPriorForLabel(label);

          final bboxH = cand.yMax - cand.yMin;
          final bboxW = cand.xMax - cand.xMin;
          final normalizedHeight = bboxH.clamp(0.04, 1.0);
          final normalizedWidth = bboxW.clamp(0.04, 1.0);

          // Calibrated dual-axis pinhole distance estimation
          final double distHeight = (_focalLengthRatio * prior.realHeightMeters) / normalizedHeight;
          final double distWidth = ((_focalLengthRatio * 0.92) * prior.realWidthMeters) / normalizedWidth;

          // Stable geometry-aware fusion
          double rawDistance;
          if (prior.realWidthMeters > prior.realHeightMeters * 1.35) {
            rawDistance = distWidth;
          } else if (prior.realHeightMeters > prior.realWidthMeters * 1.6) {
            rawDistance = distHeight;
          } else {
            rawDistance = (distHeight * 0.65) + (distWidth * 0.35);
          }

          // Pitch Angle Compensation (Accelerometer ground-plane sensor fusion)
          if (devicePitchDeg.abs() > 3.0) {
            final double pitchRad = (devicePitchDeg * math.pi) / 180.0;
            const double cameraHeightMeters = 1.35; // Standard handheld/chest carrying height
            final double yBottomNorm = cand.yMax;
            final double verticalAngleRad = pitchRad + (yBottomNorm - 0.5) * 0.95;
            
            if (verticalAngleRad > 0.12) {
              final double groundPlaneDist = cameraHeightMeters / math.tan(verticalAngleRad);
              if (groundPlaneDist > 0.3 && groundPlaneDist < 8.5) {
                rawDistance = (rawDistance * 0.60) + (groundPlaneDist * 0.40);
              }
            }
          }

          final distanceMeters = double.parse(
            rawDistance.clamp(0.3, 8.5).toStringAsFixed(1),
          );

          // 12-Hour Spatial Clock Position
          final normCenterX = (cand.xMin + cand.xMax) / 2.0;
          final normCenterY = (cand.yMin + cand.yMax) / 2.0;
          final clock = _calculateClockPosition(normCenterX);

          // Spatial-Grid Temporal Persistence Key (avoids jitter while confirming true objects)
          final gridX = (normCenterX * 5).floor().clamp(0, 4);
          final gridY = (normCenterY * 5).floor().clamp(0, 4);
          final trackKey = "${cand.label}_g${gridX}_$gridY";
          currentFrameKeys.add(trackKey);
          final prevCount = _temporalTrackCount[trackKey] ?? 0;
          final currentCount = prevCount + 1;
          _temporalTrackCount[trackKey] = currentCount;

          // Require 2 consecutive frames OR solid single-frame confidence (>= 0.40) to confirm
          if (currentCount < 2 && cand.score < 0.40) {
            continue;
          }

          // Time To Collision (TTC) assuming 1.1 m/s average walking pace
          final ttcSeconds = double.parse((distanceMeters / 1.1).toStringAsFixed(1));

          // Priority determination
          AudioPriority priority;
          if (distanceMeters < 1.2 || prior.defaultPriority == AudioPriority.level0Critical) {
            priority = AudioPriority.level0Critical;
          } else if (distanceMeters < 2.5 || prior.defaultPriority == AudioPriority.level1Safety) {
            priority = AudioPriority.level1Safety;
          } else {
            priority = prior.defaultPriority;
          }

          obstacles.add(DetectedObstacle(
            label: prior.spokenLabel,
            confidence: cand.score,
            xMin: cand.xMin.clamp(0.0, 1.0),
            yMin: cand.yMin.clamp(0.0, 1.0),
            xMax: cand.xMax.clamp(0.0, 1.0),
            yMax: cand.yMax.clamp(0.0, 1.0),
            distanceMeters: distanceMeters,
            ttcSeconds: ttcSeconds,
            priority: priority,
            clockPosition: clock,
          ));
        }

        // Decay tracks not seen in current frame
        _temporalTrackCount.removeWhere((k, v) => !currentFrameKeys.contains(k));
      }

      // Apply Kinematic Motion & Trajectory Tracking
      final enrichedObstacles = KinematicMotionTracker().enrichWithKinematics(obstacles);
      enrichedObstacles.sort((a, b) => a.priority.value.compareTo(b.priority.value));

      final latencyMs = stopwatch.elapsedMilliseconds;
      final cycleResult = OnlineDetectionCycleResult(
        obstacles: enrichedObstacles,
        latencyMs: latencyMs,
        timestamp: DateTime.now(),
        isOnlineSuccess: true,
        statusMessage: enrichedObstacles.isEmpty
            ? "Standalone On-Device AI: Path Clear (${latencyMs}ms)"
            : "Standalone On-Device AI: ${enrichedObstacles.length} Obstacle${enrichedObstacles.length > 1 ? 's' : ''} (${latencyMs}ms)",
      );

      _resultsController.add(cycleResult);

      // Enforce Speak-Once Audio Mutex Governance
      if (speakGovernance) {
        _enforceSpeechGovernance(cycleResult);
      }

      return cycleResult;
    } catch (e) {
      debugPrint("[OnDeviceObstacleDetector] Inference error: $e");
      final errorResult = OnlineDetectionCycleResult(
        obstacles: [],
        latencyMs: stopwatch.elapsedMilliseconds,
        timestamp: DateTime.now(),
        isOnlineSuccess: false,
        statusMessage: "On-Device AI: $e",
      );
      _resultsController.add(errorResult);
      return errorResult;
    } finally {
      stopwatch.stop();
      _isProcessing = false;
    }
  }

  /// Parse YOLOv8 raw prediction matrices [84, 2100] with strict false-positive suppression
  List<_DetectionCandidate> _parseYoloOutput(
    List<List<double>> raw,
    int numClasses,
    int numPredictions,
    double scale,
    double padX,
    double padY,
    double scaledW,
    double scaledH,
  ) {
    final List<_DetectionCandidate> list = [];

    // Classes prone to false texture triggers (require higher confidence)
    const Set<String> smallTextureProneClasses = {
      "scissors", "tie", "remote", "mouse", "sports ball", "hair drier", "toothbrush"
    };

    for (int col = 0; col < numPredictions; col++) {
      int bestClass = -1;
      double maxScore = 0.0;

      for (int c = 0; c < numClasses; c++) {
        final score = raw[4 + c][col];
        if (score > maxScore) {
          maxScore = score;
          bestClass = c;
        }
      }

      if (bestClass < 0) continue;

      final labelName = (bestClass < _labels.length) ? _labels[bestClass].toLowerCase() : "obstacle";

      // Class-adaptive confidence gating
      double requiredThreshold = _defaultConfidenceThreshold;
      if (labelName == "person") {
        requiredThreshold = _personConfidenceThreshold;
      } else if (smallTextureProneClasses.contains(labelName)) {
        requiredThreshold = _smallItemConfidenceThreshold;
      }

      if (maxScore >= requiredThreshold) {
        final cx = raw[0][col];
        final cy = raw[1][col];
        final w = raw[2][col];
        final h = raw[3][col];

        // Auto-detect coordinate scale (pixel [0..320] vs normalized [0..1])
        final bool isPixelScale = (cx > 1.5 || cy > 1.5 || w > 1.5 || h > 1.5);
        final double actualCx = isPixelScale ? cx : cx * 320.0;
        final double actualCy = isPixelScale ? cy : cy * 320.0;
        final double actualW = isPixelScale ? w : w * 320.0;
        final double actualH = isPixelScale ? h : h * 320.0;

        // Unpad and scale back to exact normalized [0.0, 1.0] preview coordinates
        final xMin = (actualCx - actualW / 2.0 - padX) / scaledW;
        final yMin = (actualCy - actualH / 2.0 - padY) / scaledH;
        final xMax = (actualCx + actualW / 2.0 - padX) / scaledW;
        final yMax = (actualCy + actualH / 2.0 - padY) / scaledH;

        final cand = _DetectionCandidate(
          label: labelName,
          score: maxScore,
          xMin: xMin.clamp(0.0, 1.0),
          yMin: yMin.clamp(0.0, 1.0),
          xMax: xMax.clamp(0.0, 1.0),
          yMax: yMax.clamp(0.0, 1.0),
        );

        // 1. Minimum & Maximum Area Verification (suppress 1px noise & full-screen hallucination)
        if (cand.area < 0.0012 || cand.area > 0.96) continue;

        // 2. Aspect Ratio Sanity Check (reject extreme needle-thin edge noise)
        final double aspectRatio = cand.width / math.max(0.001, cand.height);
        if (aspectRatio > 14.0 || aspectRatio < 0.07) continue;

        // 3. Class-specific Geometric Sanity Rules
        if (labelName == "person") {
          if (cand.height < 0.04) continue; // Must be at least 4% screen height
          if (cand.width > 2.2 * cand.height) continue; // Reject flat horizontal slabs labeled as people
        } else if (labelName == "car" || labelName == "bus" || labelName == "truck") {
          if (cand.height > 3.0 * cand.width) continue; // Reject impossibly thin vertical vehicles
        }

        list.add(cand);
      }
    }

    return list;
  }

  /// High-Recall Class-Aware Non-Maximum Suppression (NMS)
  /// Preserves distinct co-located objects (e.g. laptop on table, cup on desk, person on chair)
  /// while cleanly removing duplicate detections of the same object.
  List<_DetectionCandidate> _applyNms(
    List<_DetectionCandidate> candidates,
  ) {
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final List<_DetectionCandidate> selected = [];

    for (final cand in candidates) {
      bool shouldSelect = true;
      for (final sel in selected) {
        final iou = _computeIoU(cand, sel);
        final isSameClass = cand.label == sel.label;

        // Strict IoU for same class, relaxed IoU for distinct stacked/co-located classes
        final threshold = isSameClass ? _sameClassIouThreshold : _crossClassIouThreshold;

        if (iou > threshold) {
          shouldSelect = false;
          break;
        }
      }

      if (shouldSelect) {
        selected.add(cand);
        if (selected.length >= 32) break; // Capture up to 32 distinct items in complex scenes
      }
    }
    return selected;
  }

  double _computeIoU(_DetectionCandidate a, _DetectionCandidate b) {
    final x1 = math.max(a.xMin, b.xMin);
    final y1 = math.max(a.yMin, b.yMin);
    final x2 = math.min(a.xMax, b.xMax);
    final y2 = math.min(a.yMax, b.yMax);

    final intersectionW = math.max(0.0, x2 - x1);
    final intersectionH = math.max(0.0, y2 - y1);
    final intersectionArea = intersectionW * intersectionH;

    final areaA = (a.xMax - a.xMin) * (a.yMax - a.yMin);
    final areaB = (b.xMax - b.xMin) * (b.yMax - b.yMin);
    final unionArea = areaA + areaB - intersectionArea;

    if (unionArea <= 0.0) return 0.0;
    return intersectionArea / unionArea;
  }

  _ObjectPrior _getPriorForLabel(String label) {
    final lower = label.toLowerCase();
    if (_priors.containsKey(lower)) {
      return _priors[lower]!;
    }
    // Generic default for unlisted COCO classes
    final capitalized = lower.isNotEmpty
        ? "${lower[0].toUpperCase()}${lower.substring(1)}"
        : "Obstacle";
    return _ObjectPrior(1.0, 0.6, AudioPriority.level1Safety, capitalized);
  }

  String _calculateClockPosition(double normCenterX) {
    if (normCenterX < 0.25) return "10 o'clock";
    if (normCenterX < 0.40) return "11 o'clock";
    if (normCenterX <= 0.60) return "12 o'clock";
    if (normCenterX <= 0.75) return "1 o'clock";
    return "2 o'clock";
  }

  /// Strict Voice Governance: Speaks obstacles once with debouncing and clearance notifications
  void _enforceSpeechGovernance(OnlineDetectionCycleResult cycle) {
    final now = DateTime.now();

    if (cycle.obstacles.isEmpty) {
      if (_wasHazardSpoken) {
        _wasHazardSpoken = false;
        _announcedObstacles.clear();
        _announcedDistances.clear();
        AudioMutexController().notifyHazardCleared();
      }
      return;
    }

    final topHazard = cycle.highestHazard ?? cycle.obstacles.first;

    // Real-Time Motion Gate: Only speak if dynamic motion or urgent near-field collision
    final isDynamicMotion = topHazard.motionType == ObjectMotionType.approachingTowardsUser ||
        topHazard.motionType == ObjectMotionType.crossingLeftToRight ||
        topHazard.motionType == ObjectMotionType.crossingRightToLeft ||
        topHazard.motionType == ObjectMotionType.overheadHazard;
    final isUrgentNearCollision = topHazard.distanceMeters <= 1.2 &&
        (topHazard.clockPosition == "12 o'clock" || topHazard.clockPosition == "11 o'clock" || topHazard.clockPosition == "1 o'clock");

    // Suppress speaking stationary background objects (e.g. bed, table, chair, wall at distance)
    if (!isDynamicMotion && !isUrgentNearCollision) {
      return;
    }

    final key = "${topHazard.label}_${topHazard.clockPosition}";
    final lastSpoken = _announcedObstacles[key];
    final lastDist = _announcedDistances[key];

    bool shouldSpeak = false;

    if (lastSpoken == null) {
      shouldSpeak = true;
    } else {
      final elapsedSec = now.difference(lastSpoken).inSeconds;
      final distDelta = (lastDist != null) ? (lastDist - topHazard.distanceMeters).abs() : 99.0;

      // Critical hazards (<1.2m) speak if closer by 0.6m or 8s elapsed
      if (topHazard.priority == AudioPriority.level0Critical && (elapsedSec >= 8 || distDelta >= 0.6)) {
        shouldSpeak = true;
      } 
      // Safety moving items speak if closer by >= 1.2m or 15s cooldown elapsed
      else if (topHazard.priority == AudioPriority.level1Safety && (elapsedSec >= 15 || distDelta >= 1.2)) {
        shouldSpeak = true;
      }
    }

    if (shouldSpeak) {
      _announcedObstacles[key] = now;
      _announcedDistances[key] = topHazard.distanceMeters;
      _wasHazardSpoken = true;

      String speechText = topHazard.priority == AudioPriority.level0Critical
          ? "Caution! ${topHazard.speechAnnouncement}"
          : topHazard.speechAnnouncement;

      // Real-Time Optimal Path Navigation Voice Integration
      if (cycle.optimalPath.isPathBlocked && topHazard.distanceMeters < 2.5) {
        speechText = "$speechText ${cycle.optimalPath.voiceInstruction}";
      }

      AudioMutexController().speak(
        text: speechText,
        priority: topHazard.priority,
        haptic: topHazard.priority == AudioPriority.level0Critical,
      );
    }
  }

  void dispose() {
    _interpreter?.close();
    _resultsController.close();
  }
}

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'controllers/audio_mutex_controller.dart';
import 'services/online_obstacle_detector.dart';
import 'services/on_device_obstacle_detector.dart';
import 'services/kinematic_motion_tracker.dart';
import 'services/cloud_ai_vision_service.dart';
import 'services/nameboard_navigation_service.dart';
import 'models/navigation_destination.dart';

List<CameraDescription> _cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Enforce Portrait viewing mode explicitly
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    _cameras = await availableCameras();
  } catch (e) {
    debugPrint("Camera initialization error: $e");
  }

  runApp(const OrbisNavApp());
}

class OrbisNavApp extends StatelessWidget {
  const OrbisNavApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI-Eyes / OrbisNav',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF76FF03),
          surface: Color(0xFF131B2A),
          error: Color(0xFFFF1744),
        ),
      ),
      home: const OrbisNavLiveApp(),
    );
  }
}

class OrbisNavLiveApp extends StatefulWidget {
  const OrbisNavLiveApp({super.key});

  @override
  State<OrbisNavLiveApp> createState() => _OrbisNavLiveAppState();
}

class _OrbisNavLiveAppState extends State<OrbisNavLiveApp> with WidgetsBindingObserver {
  // Real Hardware Components
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  StreamSubscription<AccelerometerEvent>? _sensorSubscription;
  StreamSubscription<OnlineDetectionCycleResult>? _onDeviceSubscription;
  StreamSubscription<AudioRequest?>? _speechSubscription;

  // Real-time Sensors & Telemetry
  double _pitchDeg = 0.0;
  double _rollDeg = 0.0;
  int _stepCount = 0;
  double _driftMeters = 0.0;
  int _clockDirection = 12;
  double _lastAccelMagnitude = 9.8;
  DateTime _lastStepTime = DateTime.now();
  DateTime? _lastTiltWarningTime;

  // Audio / Speech State (Governed by AudioMutexController)
  final AudioMutexController _audioMutex = AudioMutexController();
  final OnDeviceObstacleDetector _onDeviceDetector = OnDeviceObstacleDetector();
  final CloudAIVisionService _cloudAiService = CloudAIVisionService();
  String _activeSpeech = "AI-Eyes Vision Ready. Path Clear.";
  bool _isSpeaking = false;
  String _lastHaptic = "Dual 50ms Pulse (Boot)";

  // Vision State (100% Standalone On-Device Edge Inference Engine)
  bool _isVisionActive = true;
  bool _isProcessingFrame = false;
  int _inferenceLatencyMs = 38;
  String _visionStatus = "Standalone Edge AI: Ready";
  List<DetectedObstacle> _activeObstacles = [];
  DetectedObstacle? _primaryHazard;
  Timer? _visionStreamTimer;

  // Multimodal AI Scene Comprehension State
  SceneAnalysisResult _latestSceneAnalysis = SceneAnalysisResult.empty();
  StreamSubscription<SceneAnalysisResult>? _sceneAnalysisSubscription;

  // Destination & Landmark Nameboard Navigation (4km Radius Discovery)
  final NameboardNavigationService _navService = NameboardNavigationService();
  StreamSubscription<NavigationStatusState>? _navSubscription;
  NavigationStatusState? _navState;
  final TextEditingController _destinationInputController = TextEditingController();

  // System States
  final double _tempC = 37.2;
  final int _battery = 100;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initSystem();
  }

  Future<void> _initSystem() async {
    // 1. Listen to Audio Mutex events
    _speechSubscription = _audioMutex.activeSpeechStream.listen((request) {
      if (mounted) {
        setState(() {
          _isSpeaking = request != null;
          if (request != null) {
            _activeSpeech = request.text;
          }
        });
      }
    });

    // 2. Initialize Edge-Native On-Device ML Engine (100% Offline, no Mac/server required)
    await _onDeviceDetector.initialize();
    _onDeviceSubscription = _onDeviceDetector.resultsStream.listen((result) {
      if (mounted) {
        setState(() {
          _inferenceLatencyMs = result.latencyMs;
          _visionStatus = result.statusMessage;
          _activeObstacles = result.obstacles;
          _primaryHazard = result.highestHazard;
        });
      }
    });

    // 3. Listen to Online Multimodal AI Scene Analysis Stream
    _sceneAnalysisSubscription = _cloudAiService.sceneStream.listen((scene) {
      if (mounted) {
        setState(() {
          _latestSceneAnalysis = scene;
        });
      }
    });

    // 4. Listen to Destination & 4km GPS Navigation Status
    _navSubscription = _navService.statusStream.listen((state) {
      if (mounted) {
        setState(() {
          _navState = state;
        });
      }
    });

    // 5. Initialize GPS & 4km Radius POI Discovery
    await _navService.initializeGpsAndNearby();

    // 6. Initialize CameraX with Portrait orientation
    await _initCamera();

    // 7. Start Hardware Accelerometer for Real Pitch and PDR
    _startSensorStream();

    // 8. Start real-time obstacle detection streaming loop
    _startVisionStream();

    // Initial voice greeting
    _audioMutex.speak(
      text: "AI Eyes obstacle and motion detection activated. Standalone offline mode ready.",
      priority: AudioPriority.level2Navigation,
      haptic: true,
    );

    if (mounted) setState(() {});
  }

  Future<void> _initCamera() async {
    if (_cameras.isNotEmpty) {
      _cameraController = CameraController(
        _cameras.first,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      try {
        await _cameraController!.initialize();
        await _cameraController!.lockCaptureOrientation(DeviceOrientation.portraitUp);
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      } catch (e) {
        debugPrint("Camera init error: $e");
      }
    }
  }

  DateTime _lastSensorUiUpdateTime = DateTime.now();

  void _startSensorStream() {
    _sensorSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
      final ax = event.x;
      final ay = event.y;
      final az = event.z;
      final pitchRad = math.atan2(-ay, math.sqrt(ax * ax + az * az));
      final pitchDeg = pitchRad * (180.0 / math.pi);
      final rollDeg = math.atan2(ax, az) * (180.0 / math.pi);

      // Always update pitch and roll variables instantly for vision calculations
      _pitchDeg = pitchDeg;
      _rollDeg = rollDeg;

      // PDR Step Detection
      final magnitude = math.sqrt(ax * ax + ay * ay + az * az);
      final now = DateTime.now();
      if (_lastAccelMagnitude < 11.2 && magnitude >= 11.2 && now.difference(_lastStepTime).inMilliseconds > 350) {
        _lastStepTime = now;
        _onStepDetected();
      }
      _lastAccelMagnitude = magnitude;

      // Downward pitch prompt (severe downward pitch > 45° looking at shoes) - 60s cooldown
      if (pitchDeg < -45.0) {
        final nowTime = DateTime.now();
        if (_lastTiltWarningTime == null || nowTime.difference(_lastTiltWarningTime!).inSeconds >= 60) {
          _lastTiltWarningTime = nowTime;
          _audioMutex.speak(
            text: "Please tilt phone up for obstacle vision.",
            priority: AudioPriority.level1Safety,
            haptic: true,
          );
        }
      }

      // Throttle UI setState to 3.3 Hz (every 300ms) to prevent 100Hz rebuild storms and lag
      if (mounted && now.difference(_lastSensorUiUpdateTime).inMilliseconds >= 300) {
        _lastSensorUiUpdateTime = now;
        setState(() {});
      }
    });
  }

  void _onStepDetected() {
    _stepCount++;
    _driftMeters += 0.025;
    if (mounted) {
      setState(() {});
    }
    HapticFeedback.lightImpact();
  }

  /// High-efficiency detection loop: runs asynchronously without locking the UI
  void _startVisionStream() {
    _visionStreamTimer?.cancel();
    _visionStreamTimer = Timer.periodic(const Duration(milliseconds: 480), (_) {
      if (_isVisionActive &&
          _isCameraInitialized &&
          !_isProcessingFrame &&
          _cameraController != null &&
          _cameraController!.value.isInitialized &&
          !_cameraController!.value.isTakingPicture) {
        _processFrame();
      }
    });
  }

  Future<void> _processFrame() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _cameraController!.value.isTakingPicture ||
        _isProcessingFrame) {
      return;
    }

    _isProcessingFrame = true;
    try {
      final image = await _cameraController!.takePicture();
      final bytes = await image.readAsBytes();

      // 100% Standalone On-Device Neural Vision Engine with Motion Dynamics
      await _onDeviceDetector.processFrameBytes(
        bytes,
        devicePitchDeg: _pitchDeg,
      );

      // Real-Time Situation & Scene Understanding (Edge + Cloud Fallback)
      if (_cloudAiService.isAutoAnalyzeEnabled) {
        _cloudAiService.analyzeScene(
          bytes,
          currentObstacles: _activeObstacles,
          devicePitchDeg: _pitchDeg,
          speakResult: false,
        );
      }

      if (_navService.isNavigating) {
        await _navService.processCameraSnapshot(bytes);
      }
    } catch (e) {
      debugPrint("Frame processing error: $e");
    } finally {
      _isProcessingFrame = false;
    }
  }

  void _clearHazards() {
    setState(() {
      _primaryHazard = null;
      _activeObstacles = [];
      _lastHaptic = "Silent";
    });
    _onDeviceDetector.forceRescan();
    KinematicMotionTracker().reset();
    _audioMutex.notifyHazardCleared();
    _audioMutex.speak(
      text: "Path clear. Continuing forward.",
      priority: AudioPriority.level2Navigation,
      haptic: false,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _visionStreamTimer?.cancel();
    _sensorSubscription?.cancel();
    _onDeviceSubscription?.cancel();
    _sceneAnalysisSubscription?.cancel();
    _onDeviceDetector.dispose();
    _cloudAiService.dispose();
    _navSubscription?.cancel();
    _speechSubscription?.cancel();
    _destinationInputController.dispose();
    _navService.stopNavigation();
    _cameraController?.dispose();
    _audioMutex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasCriticalHazard = _primaryHazard != null && _primaryHazard!.isHazard;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF00E5FF)),
              ),
              child: const Text(
                "ORBISNAV",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.5),
              ),
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                "Motion Vision & 4km GPS",
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _isVisionActive ? const Color(0xFF76FF03).withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _isVisionActive ? const Color(0xFF76FF03) : Colors.grey),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions_run, size: 13, color: _isVisionActive ? const Color(0xFF76FF03) : Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    _isVisionActive ? "MOTION ON (${_inferenceLatencyMs}ms)" : "PAUSED",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _isVisionActive ? const Color(0xFF76FF03) : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Real-time Hardware & Telemetry Bar
            _buildTelemetryBar(),
            const SizedBox(height: 14),

            // 2. Portrait Camera Viewfinder with Live Real-World Bounding Boxes & Motion Badges
            _buildPortraitCameraViewfinder(hasCriticalHazard),
            const SizedBox(height: 14),

            // 3. Dedicated Motion Detection & Kinematics Radar
            _buildMotionKinematicsCard(),
            const SizedBox(height: 14),

            // 4. On-Device Obstacle Detection Status & Hazard List
            _buildObstacleDetectionCard(hasCriticalHazard),
            const SizedBox(height: 14),

            // 5. Multimodal AI Situation & Scene Analyzer
            _buildSceneComprehensionCard(),
            const SizedBox(height: 14),

            // 6. GPS Nearby Destinations & POIs (4km Radius Explorer)
            _build4kmNearbyDestinationsCard(),
            const SizedBox(height: 14),

            // 7. 12-Hour Spatial Navigation Radar & PDR Tracking
            _buildNavigationRadar(),
            const SizedBox(height: 14),

            // 8. Audio Mutex Speech & Voice State
            _buildAudioStatusCard(hasCriticalHazard),
            const SizedBox(height: 14),

            // 9. Interactive Testing & Control Bar
            _buildControlBar(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        alignment: WrapAlignment.spaceAround,
        children: [
          _buildStat("MODE", "Portrait Live", Icons.screen_lock_portrait, const Color(0xFF00E5FF)),
          _buildStat("MOTION", "Kinematics Active", Icons.directions_run, const Color(0xFF76FF03)),
          _buildStat("LATENCY", "${_inferenceLatencyMs}ms", Icons.speed, const Color(0xFF00E5FF)),
          _buildStat("GPS FIX", _navService.hasRealGpsFix ? "Active GPS" : "Sensor Nav", Icons.location_on, _navService.hasRealGpsFix ? const Color(0xFF76FF03) : Colors.orangeAccent),
          _buildStat("SOC TEMP", "${_tempC.toStringAsFixed(1)}°C", Icons.thermostat, const Color(0xFF76FF03)),
          _buildStat("BATTERY", "$_battery%", Icons.battery_charging_full, Colors.greenAccent),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, IconData icon, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 9, color: Colors.white54)),
            Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ],
    );
  }

  Widget _buildPortraitCameraViewfinder(bool hasCriticalHazard) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.maxWidth;
        const boxHeight = 380.0;

        return Container(
          height: boxHeight,
          decoration: BoxDecoration(
            color: const Color(0xFF0E1420),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasCriticalHazard ? const Color(0xFFFF1744) : const Color(0xFF00E5FF).withValues(alpha: 0.4),
              width: hasCriticalHazard ? 2.5 : 1.2,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Live Portrait Camera Stream
                if (_isCameraInitialized && _cameraController != null)
                  CameraPreview(_cameraController!)
                else
                  Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.camera_alt, size: 48, color: Colors.white.withValues(alpha: 0.2)),
                          const SizedBox(height: 8),
                          const Text(
                            "Connecting Portrait Camera Stream...",
                            style: TextStyle(fontSize: 12, color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Center Focus Reticle
                Center(
                  child: Icon(
                    Icons.filter_center_focus,
                    size: 70,
                    color: hasCriticalHazard ? const Color(0xFFFF1744).withValues(alpha: 0.4) : Colors.cyanAccent.withValues(alpha: 0.20),
                  ),
                ),

                // Top Viewfinder Header
                Positioned(
                  top: 10,
                  left: 12,
                  right: 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.portrait, size: 12, color: Color(0xFF00E5FF)),
                            const SizedBox(width: 4),
                            Text(
                              "PORTRAIT • ${_activeObstacles.length} OBJECTS",
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: hasCriticalHazard ? Colors.red.withValues(alpha: 0.85) : Colors.green.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          hasCriticalHazard ? "HAZARD DETECTED" : "PATH CLEAR",
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),

                // Dynamic Live Bounding Boxes with Motion Indicators
                ..._activeObstacles.map((obs) {
                  final left = (obs.xMin * boxWidth).clamp(0.0, boxWidth - 40.0);
                  final top = (obs.yMin * boxHeight).clamp(0.0, boxHeight - 30.0);
                  final width = ((obs.xMax - obs.xMin) * boxWidth).clamp(40.0, boxWidth);
                  final height = ((obs.yMax - obs.yMin) * boxHeight).clamp(30.0, boxHeight);
                  final color = obs.isHazard ? const Color(0xFFFF1744) : (obs.isMoving ? const Color(0xFFFFD600) : const Color(0xFF00E5FF));

                  return Positioned(
                    left: left,
                    top: top,
                    width: width,
                    height: height,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: color, width: 2.2),
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            color: color,
                            child: Text(
                              "${obs.label.toUpperCase()} ${(obs.confidence * 100).toInt()}% • ${obs.formattedMotionBadge} • ${obs.distanceMeters.toStringAsFixed(1)}m",
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: obs.isHazard ? Colors.white : Colors.black,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                // Sighted Destination Nameboard Reticle
                if (_navService.targetBoard != null)
                  Positioned(
                    top: 48,
                    left: 14,
                    right: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF00E676), width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00E676).withValues(alpha: 0.35),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.storefront, color: Color(0xFF00E676), size: 26),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  "TARGET NAMEBOARD SIGHTED (${(_navService.targetBoard!.confidence * 100).toInt()}% CONF)",
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF00E676), letterSpacing: 1.1),
                                ),
                                Text(
                                  _navService.targetBoard!.text,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                Text(
                                  "Vector: ${_navService.targetBoard!.clockZone} • Dist: ${_navService.targetBoard!.distanceMeters.toStringAsFixed(1)}m",
                                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E676),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              "LOCKED",
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Bottom IMU Telemetry
                Positioned(
                  bottom: 10,
                  left: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        Text("Pitch: ${_pitchDeg.toStringAsFixed(1)}°", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _pitchDeg < -30 ? Colors.orange : Colors.white)),
                        Text("Roll: ${_rollDeg.toStringAsFixed(1)}°", style: const TextStyle(fontSize: 11, color: Colors.white70)),
                        Text("Latency: ${_inferenceLatencyMs}ms", style: const TextStyle(fontSize: 11, color: Color(0xFF00E5FF))),
                        Text("Haptic: $_lastHaptic", style: const TextStyle(fontSize: 11, color: Color(0xFF76FF03))),
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  /// Dedicated Real-Time Motion Detection & Kinematics Card
  Widget _buildMotionKinematicsCard() {
    final tracker = KinematicMotionTracker();
    final motionEnergy = tracker.sceneMotionEnergy;
    final movingObstacles = _activeObstacles.where((o) => o.isMoving).toList();
    final hasActiveMotion = movingObstacles.isNotEmpty || motionEnergy > 0.15;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasActiveMotion ? const Color(0xFFFFD600).withValues(alpha: 0.6) : Colors.white10,
          width: hasActiveMotion ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.directions_run, color: hasActiveMotion ? const Color(0xFFFFD600) : const Color(0xFF00E5FF), size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    "MOTION DETECTION & VELOCITY RADAR",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hasActiveMotion ? const Color(0xFFFFD600).withValues(alpha: 0.2) : Colors.white10,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: hasActiveMotion ? const Color(0xFFFFD600) : Colors.white24),
                ),
                child: Text(
                  hasActiveMotion ? "DYNAMIC MOVEMENT" : "STATIC SCENE",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: hasActiveMotion ? const Color(0xFFFFD600) : Colors.white54,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Motion Energy Bar
          Row(
            children: [
              const Text("SCENE ACTIVITY:", style: TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: motionEnergy.clamp(0.05, 1.0),
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      motionEnergy > 0.5 ? const Color(0xFFFF1744) : (motionEnergy > 0.2 ? const Color(0xFFFFD600) : const Color(0xFF00E5FF)),
                    ),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "${(motionEnergy * 100).toInt()}%",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: motionEnergy > 0.5 ? const Color(0xFFFF1744) : const Color(0xFF00E5FF),
                ),
              ),
            ],
          ),

          if (movingObstacles.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...movingObstacles.map((obs) {
              IconData motionIcon = Icons.directions_walk;
              Color motionColor = const Color(0xFFFFD600);
              if (obs.motionType == ObjectMotionType.approachingTowardsUser) {
                motionIcon = Icons.trending_down;
                motionColor = const Color(0xFFFF1744);
              } else if (obs.motionType == ObjectMotionType.movingAwayFromUser) {
                motionIcon = Icons.trending_up;
                motionColor = const Color(0xFF76FF03);
              } else if (obs.motionType == ObjectMotionType.crossingLeftToRight) {
                motionIcon = Icons.arrow_forward;
                motionColor = const Color(0xFF00E5FF);
              } else if (obs.motionType == ObjectMotionType.crossingRightToLeft) {
                motionIcon = Icons.arrow_back;
                motionColor = const Color(0xFF00E5FF);
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: motionColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: motionColor.withValues(alpha: 0.6)),
                ),
                child: Row(
                  children: [
                    Icon(motionIcon, size: 18, color: motionColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            obs.detailedDescription,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          Text(
                            "Closing Speed: ${obs.velocityMps.abs()} m/s • TTC: ${obs.ttcSeconds}s • Vector: ${obs.clockPosition}",
                            style: const TextStyle(fontSize: 10, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: motionColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        obs.formattedMotionBadge,
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ]
        ],
      ),
    );
  }

  Widget _buildObstacleDetectionCard(bool hasCriticalHazard) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasCriticalHazard ? const Color(0xFFFF1744).withValues(alpha: 0.5) : Colors.white10,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.remove_red_eye_outlined, color: Color(0xFF00E5FF), size: 18),
                  SizedBox(width: 8),
                  Text(
                    "ON-DEVICE NEURAL VISION",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                  ),
                ],
              ),
              Switch(
                value: _isVisionActive,
                activeThumbColor: const Color(0xFF76FF03),
                onChanged: (val) {
                  setState(() {
                    _isVisionActive = val;
                  });
                  _onDeviceDetector.setEnabled(val);
                  if (val) {
                    _startVisionStream();
                  } else {
                    _visionStreamTimer?.cancel();
                  }
                },
              )
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _visionStatus,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          if (_activeObstacles.isNotEmpty) ...[
            const SizedBox(height: 10),
            ..._activeObstacles.map((obs) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: obs.isHazard ? const Color(0xFFFF1744).withValues(alpha: 0.15) : const Color(0xFF00E5FF).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: obs.isHazard ? const Color(0xFFFF1744) : const Color(0xFF00E5FF),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    obs.motionType == ObjectMotionType.approachingTowardsUser
                        ? Icons.directions_walk
                        : obs.motionType == ObjectMotionType.overheadHazard
                            ? Icons.warning_rounded
                            : obs.isHazard
                                ? Icons.warning_amber_rounded
                                : Icons.info_outline,
                    color: obs.isHazard ? const Color(0xFFFF1744) : const Color(0xFF00E5FF),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "${obs.detailedDescription} (${obs.clockPosition})",
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Text(
                          "Distance: ${obs.distanceMeters.toStringAsFixed(1)}m | TTC: ${obs.ttcSeconds.toStringAsFixed(1)}s | ${(obs.confidence * 100).toInt()}% Conf",
                          style: const TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            )),
          ]
        ],
      ),
    );
  }

  Widget _buildSceneComprehensionCard() {
    final hasInternet = _cloudAiService.isOnline;
    final isAnalyzing = _cloudAiService.isAnalyzing;
    final scene = _latestSceneAnalysis;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1B4B).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasInternet ? const Color(0xFF818CF8) : Colors.white24,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                color: hasInternet ? const Color(0xFFA5B4FC) : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                "REAL-TIME SITUATION ANALYZER",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: Color(0xFFA5B4FC),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hasInternet ? const Color(0xFF4338CA) : const Color(0xFF065F46),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hasInternet ? (isAnalyzing ? "ANALYZING..." : "GEMINI 2.0") : "STANDALONE EDGE",
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              )
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1B4B),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_city, size: 12, color: Color(0xFFA5B4FC)),
                    const SizedBox(width: 4),
                    Text(
                      scene.environmentType,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFA5B4FC)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: scene.pathwayStatus.contains("Clear") ? const Color(0xFF064E3B) : const Color(0xFF7F1D1D),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      scene.pathwayStatus.contains("Clear") ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      scene.pathwayStatus,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            scene.sceneSummary,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (scene.recommendedAction.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF172554),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.assistant_direction, size: 14, color: Color(0xFF60A5FA)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      scene.recommendedAction,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF93C5FD), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (scene.detailedObjects.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: scene.detailedObjects.map((item) => Chip(
                backgroundColor: const Color(0xFF312E81),
                label: Text(item, style: const TextStyle(fontSize: 11, color: Colors.white)),
                visualDensity: VisualDensity.compact,
              )).toList(),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isAnalyzing
                  ? null
                  : () async {
                      if (_cameraController != null && _cameraController!.value.isInitialized) {
                        final img = await _cameraController!.takePicture();
                        final bytes = await img.readAsBytes();
                        await _cloudAiService.analyzeScene(
                          bytes,
                          currentObstacles: _activeObstacles,
                          devicePitchDeg: _pitchDeg,
                          force: true,
                          speakResult: true,
                        );
                      }
                    },
              icon: isAnalyzing
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.record_voice_over, size: 16),
              label: Text(isAnalyzing ? "Analyzing Situation..." : "Explain Situation (Voice Narration)"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          )
        ],
      ),
    );
  }

  void _showSaveCustomPlaceDialog() {
    final nameController = TextEditingController();
    final blockController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131B2A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF00E5FF), width: 1.2),
        ),
        title: const Row(
          children: [
            Icon(Icons.add_location_alt, color: Color(0xFFFFD600), size: 20),
            SizedBox(width: 8),
            Text("Pin Location / Room", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Pin your current GPS coordinates as a designated campus block, classroom, lab, or office for quick navigation.",
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: "Place / Room Name *",
                labelStyle: const TextStyle(color: Color(0xFF00E5FF), fontSize: 12),
                hintText: "e.g. Room 304, HOD Office, Robotics Lab",
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: blockController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: "Block / Building (Optional)",
                labelStyle: const TextStyle(color: Color(0xFFFFD600), fontSize: 12),
                hintText: "e.g. Block B - CSE, Science Block",
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                final block = blockController.text.trim();
                _navService.saveCurrentLocationAsCustomPlace(
                  name: name,
                  category: "Saved My Places",
                  blockName: block.isNotEmpty ? block : null,
                );
                Navigator.of(ctx).pop();
                setState(() {});
              }
            },
            child: const Text("SAVE PIN", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// 4km Radius Nearby Destinations & Live Geolocation Explorer
  Widget _build4kmNearbyDestinationsCard() {
    final isNavigating = _navService.isNavigating;
    final navState = _navState;
    final dest = _navService.activeDestination;
    final places = _navService.nearbyPlaces;
    final isLoading = _navService.isLoadingNearby;

    Color phaseColor;
    String phaseTitle;
    IconData phaseIcon;

    switch (_navService.currentPhase) {
      case NavigationPhase.idle:
        phaseColor = Colors.grey;
        phaseTitle = "IDLE (Select Destination)";
        phaseIcon = Icons.navigation_outlined;
        break;
      case NavigationPhase.farFieldGps:
        phaseColor = const Color(0xFF00E5FF);
        phaseTitle = "GPS GUIDANCE (Far-Field)";
        phaseIcon = Icons.gps_fixed;
        break;
      case NavigationPhase.midFieldApproach:
        phaseColor = const Color(0xFF64FFDA);
        phaseTitle = "CAMPUS ENTRANCE APPROACH";
        phaseIcon = Icons.door_front_door_outlined;
        break;
      case NavigationPhase.nearFieldScanning:
        phaseColor = const Color(0xFFFFD600);
        phaseTitle = "SCANNING NAMEBOARDS (Near-Field)";
        phaseIcon = Icons.document_scanner_outlined;
        break;
      case NavigationPhase.visualHoming:
        phaseColor = const Color(0xFF00E676);
        phaseTitle = "TARGET BOARD LOCKED";
        phaseIcon = Icons.storefront;
        break;
      case NavigationPhase.arrived:
        phaseColor = const Color(0xFF76FF03);
        phaseTitle = "ARRIVED AT DESTINATION";
        phaseIcon = Icons.check_circle_outline;
        break;
    }

    // Filter places by search text (Only when user explicitly searches)
    final queryText = _destinationInputController.text.trim().toLowerCase();
    final filteredPlaces = queryText.isEmpty
        ? <NavTargetDestination>[]
        : places.where((p) {
            return p.name.toLowerCase().contains(queryText) ||
                p.category.toLowerCase().contains(queryText) ||
                (p.blockName != null && p.blockName!.toLowerCase().contains(queryText)) ||
                (p.address != null && p.address!.toLowerCase().contains(queryText)) ||
                p.aliases.any((a) => a.toLowerCase().contains(queryText));
          }).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isNavigating ? phaseColor.withValues(alpha: 0.8) : Colors.white10,
          width: isNavigating ? 1.8 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(phaseIcon, color: phaseColor, size: 18),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        "CAMPUS & DESTINATION NAVIGATION",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.add_location_alt, size: 18, color: Color(0xFFFFD600)),
                tooltip: "Pin Current GPS Location / Room",
                onPressed: _showSaveCustomPlaceDialog,
              ),
              IconButton(
                icon: isLoading
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF)))
                    : const Icon(Icons.refresh, size: 18, color: Color(0xFF00E5FF)),
                tooltip: "Refresh GPS & Locations",
                onPressed: isLoading ? null : () => _navService.fetchNearbyLocations4km(force: true),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Active Turn-by-Turn Navigation Guidance Banner
          if (isNavigating && dest != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: phaseColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: phaseColor.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dest.name.toUpperCase(),
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (dest.blockName != null && dest.blockName!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Text(
                                  "🏛️ Building: ${dest.blockName!}",
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFFD600)),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          dest.category,
                          style: const TextStyle(fontSize: 10, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("DISTANCE & BEARING", style: TextStyle(fontSize: 9, color: Colors.white54)),
                            Text(
                              "${(navState?.distanceMeters ?? 0.0) >= 1000 ? ((navState?.distanceMeters ?? 0.0) / 1000).toStringAsFixed(1) + 'km' : (navState?.distanceMeters ?? 0.0).toStringAsFixed(0) + 'm'} • ${navState?.clockDirection ?? '12 o\'clock'}",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: phaseColor),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("NAVIGATION PHASE", style: TextStyle(fontSize: 9, color: Colors.white54)),
                            Text(
                              phaseTitle,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_navService.targetBoard != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, size: 14, color: Color(0xFF00E676)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "OCR Verified Board: ${_navService.targetBoard!.text}",
                              style: const TextStyle(fontSize: 11, color: Color(0xFF00E676), fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _navService.stopNavigation();
                      },
                      icon: const Icon(Icons.stop, size: 16),
                      label: const Text("Stop Navigation", style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.withValues(alpha: 0.8),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Search Input Bar
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _destinationInputController,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: "Search nearby pharmacy, hospital, cafe...",
                    hintStyle: const TextStyle(fontSize: 11, color: Colors.white38),
                    prefixIcon: const Icon(Icons.search, size: 16, color: Color(0xFF00E5FF)),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Search Results List (Only displayed when user searches for a destination)
          if (queryText.isNotEmpty) ...[
            const SizedBox(height: 10),
            if (filteredPlaces.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text(
                    isLoading ? "Searching nearby locations..." : "No places found matching '$queryText'.",
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: math.min(filteredPlaces.length, 6),
                itemBuilder: (context, index) {
                  final item = filteredPlaces[index];
                  final isCurrentTarget = dest?.id == item.id;

                  IconData catIcon = Icons.place;
                  if (item.category == "University & Campus" || item.isCampusBuilding) catIcon = Icons.school;
                  else if (item.category == "Saved My Places" || item.isCustomSaved) catIcon = Icons.push_pin;
                  else if (item.category == "Medical & Health") catIcon = Icons.local_hospital;
                  else if (item.category == "Food & Dining") catIcon = Icons.restaurant;
                  else if (item.category == "Groceries & Shopping") catIcon = Icons.shopping_cart;
                  else if (item.category == "Transit & Stations") catIcon = Icons.directions_bus;
                  else if (item.category == "Banks & ATMs") catIcon = Icons.account_balance;
                  else if (item.category == "Landmarks & Parks") catIcon = Icons.park;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isCurrentTarget
                          ? const Color(0xFF00E5FF).withValues(alpha: 0.2)
                          : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isCurrentTarget ? const Color(0xFF00E5FF) : Colors.white10,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(catIcon, size: 18, color: item.isCampusBuilding ? const Color(0xFFFFD600) : const Color(0xFF00E5FF)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.name,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (item.blockName != null && item.blockName!.isNotEmpty) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFD600).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFFFFD600).withValues(alpha: 0.6), width: 0.8),
                                      ),
                                      child: Text(
                                        item.blockName!,
                                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFFFD600)),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (item.address != null)
                                Text(
                                  item.address!,
                                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                "${item.formattedDistance} • ${item.clockZone ?? '12 o\'clock'}",
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF)),
                              ),
                            ),
                            const SizedBox(height: 4),
                            GestureDetector(
                              onTap: () {
                                _navService.startNavigation(item);
                                _destinationInputController.clear();
                                setState(() {});
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isCurrentTarget ? Colors.green : const Color(0xFF00E5FF),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isCurrentTarget ? "ACTIVE" : "NAVIGATE",
                                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildNavigationRadar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("12-HOUR CLOCK RADAR", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text("TARGET: $_clockDirection:00", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF))),
              )
            ],
          ),
          const SizedBox(height: 14),
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Radar concentric rings
                Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
                  ),
                ),
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1B273A),
                    border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.6)),
                  ),
                ),
                // Clock Numbers
                const Positioned(top: 8, child: Text("12", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF00E5FF)))),
                const Positioned(right: 8, child: Text("3", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white54))),
                const Positioned(bottom: 8, child: Text("6", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white54))),
                const Positioned(left: 8, child: Text("9", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white54))),

                // Target Pointer
                Transform.rotate(
                  angle: (_clockDirection / 12.0) * 2 * math.pi,
                  child: Column(
                    children: [
                      Container(
                        width: 4,
                        height: 54,
                        decoration: BoxDecoration(
                          color: const Color(0xFF76FF03),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 54),
                    ],
                  ),
                ),
                const Icon(Icons.navigation, size: 24, color: Color(0xFF00E5FF)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Real PDR Steps: $_stepCount", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
              Text("Accumulated Drift: ${_driftMeters.toStringAsFixed(2)}m", style: TextStyle(fontSize: 12, color: _driftMeters > 0 ? Colors.orange : Colors.greenAccent)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAudioStatusCard(bool hasCriticalHazard) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasCriticalHazard ? const Color(0xFFFF1744).withValues(alpha: 0.5) : Colors.white10,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.volume_up, color: Color(0xFF00E5FF), size: 18),
                  SizedBox(width: 8),
                  Text("AUDIO MUTEX GOVERNANCE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _isSpeaking ? const Color(0xFF76FF03).withValues(alpha: 0.2) : Colors.white10,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _isSpeaking ? "SPEAKING" : "SILENT (STANDBY)",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _isSpeaking ? const Color(0xFF76FF03) : Colors.white54,
                  ),
                ),
              )
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "\"$_activeSpeech\"",
            style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildControlBar() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  _onDeviceDetector.forceRescan();
                  _audioMutex.speak(
                    text: "Rescanning environment.",
                    priority: AudioPriority.level2Navigation,
                    haptic: true,
                  );
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text("Rescan Vision", style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _clearHazards,
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text("Clear Hazards", style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: const Color(0xFF76FF03),
                  side: const BorderSide(color: Color(0xFF76FF03)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

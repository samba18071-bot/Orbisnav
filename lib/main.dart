import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'controllers/audio_mutex_controller.dart';
import 'services/online_obstacle_detector.dart';
import 'models/navigation_destination.dart';
import 'services/nameboard_navigation_service.dart';

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
  StreamSubscription<OnlineDetectionCycleResult>? _detectionSubscription;
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
  final OnlineObstacleDetector _onlineDetector = OnlineObstacleDetector();
  String _activeSpeech = "AI-Eyes Online Vision Ready. Path Clear.";
  bool _isSpeaking = false;
  String _lastHaptic = "Dual 50ms Pulse (Boot)";

  // Online Cloud Vision State
  bool _isOnlineVisionActive = true;
  bool _isCapturingOnlineFrame = false;
  int _cloudLatencyMs = 68;
  String _cloudStatus = "CONNECTED (Online Cloud AI)";
  List<DetectedObstacle> _activeObstacles = [];
  DetectedObstacle? _primaryHazard;
  Timer? _onlineStreamTimer;

  // Destination & Landmark Nameboard Navigation
  final NameboardNavigationService _navService = NameboardNavigationService();
  StreamSubscription<NavigationStatusState>? _navSubscription;
  NavigationStatusState? _navState;
  final TextEditingController _destinationInputController = TextEditingController();

  // System States
  final double _tempC = 37.4;
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

    // 2. Listen to Online Cloud Detection Results
    _detectionSubscription = _onlineDetector.resultsStream.listen((result) {
      if (mounted) {
        setState(() {
          _cloudLatencyMs = result.latencyMs;
          _cloudStatus = result.statusMessage;
          _activeObstacles = result.obstacles;
          _primaryHazard = result.highestHazard;
        });
      }
    });

    // 3. Listen to Destination & Board Navigation Status
    _navSubscription = _navService.statusStream.listen((state) {
      if (mounted) {
        setState(() {
          _navState = state;
        });
      }
    });

    // 4. Initialize CameraX with Portrait orientation
    await _initCamera();

    // 4. Start Hardware Accelerometer for Real Pitch and PDR
    _startSensorStream();

    // 5. Start real-time Internet obstacle detection streaming loop
    _startOnlineVisionStream();

    // Initial voice greeting
    _audioMutex.speak(
      text: "AI Eyes online obstacle detection activated. Portrait mode ready.",
      priority: AudioPriority.level2Navigation,
      haptic: true,
    );

    if (mounted) setState(() {});
  }

  Future<void> _initCamera() async {
    if (_cameras.isNotEmpty) {
      _cameraController = CameraController(
        _cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      try {
        await _cameraController!.initialize();
        // Lock capture orientation to portrait
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

  void _startSensorStream() {
    _sensorSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
      final ax = event.x;
      final ay = event.y;
      final az = event.z;
      final pitchRad = math.atan2(-ay, math.sqrt(ax * ax + az * az));
      final pitchDeg = pitchRad * (180.0 / math.pi);
      final rollDeg = math.atan2(ax, az) * (180.0 / math.pi);

      // PDR Step Detection
      final magnitude = math.sqrt(ax * ax + ay * ay + az * az);
      final now = DateTime.now();
      if (_lastAccelMagnitude < 11.2 && magnitude >= 11.2 && now.difference(_lastStepTime).inMilliseconds > 350) {
        _lastStepTime = now;
        _onStepDetected();
      }
      _lastAccelMagnitude = magnitude;

      // Downward pitch prompt (severe downward pitch > 45° looking at shoes) - Tell Only Once with 60s cooldown
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

      if (mounted) {
        setState(() {
          _pitchDeg = pitchDeg;
          _rollDeg = rollDeg;
        });
      }
    });
  }

  void _onStepDetected() {
    setState(() {
      _stepCount++;
      _driftMeters += 0.025;
    });
    HapticFeedback.lightImpact();
  }

  /// Real-time Internet streaming loop: periodically captures frames and executes
  /// cloud obstacle detection without requiring offline C++ model execution.
  void _startOnlineVisionStream() {
    _onlineStreamTimer?.cancel();
    _onlineStreamTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      if (_isOnlineVisionActive && _isCameraInitialized && !_isCapturingOnlineFrame) {
        _captureAndAnalyzeCloudFrame();
      }
    });
  }

  Future<void> _captureAndAnalyzeCloudFrame() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (_isCapturingOnlineFrame) return;

    _isCapturingOnlineFrame = true;
    try {
      final image = await _cameraController!.takePicture();
      final bytes = await image.readAsBytes();

      await _onlineDetector.processFrameBytes(
        bytes,
        devicePitchDeg: _pitchDeg,
      );

      if (_navService.isNavigating) {
        await _navService.processCameraSnapshot(bytes);
      }
    } catch (e) {
      debugPrint("Frame capture error: $e");
    } finally {
      _isCapturingOnlineFrame = false;
    }
  }

  void _triggerSimulatedHazard(AudioPriority priority, String label, double dist, String clock) {
    setState(() {
      _primaryHazard = DetectedObstacle(
        label: label,
        confidence: 0.96,
        xMin: 0.30,
        yMin: 0.20,
        xMax: 0.70,
        yMax: 0.80,
        distanceMeters: dist,
        ttcSeconds: (dist / 1.2),
        priority: priority,
        clockPosition: clock,
      );
      _activeObstacles = [_primaryHazard!];
      _lastHaptic = priority == AudioPriority.level0Critical ? "Continuous Heavy Pulse" : "Dual Tap Haptic";
    });

    final prompt = priority == AudioPriority.level0Critical
        ? "Warning! $label at $clock, ${dist.toStringAsFixed(1)} meters ahead!"
        : "Caution: $label at $clock, ${dist.toStringAsFixed(1)} meters.";

    _audioMutex.speak(
      text: prompt,
      priority: priority,
      haptic: true,
    );
  }

  void _clearHazards() {
    setState(() {
      _primaryHazard = null;
      _activeObstacles = [];
      _lastHaptic = "Silent";
    });
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
    _onlineStreamTimer?.cancel();
    _sensorSubscription?.cancel();
    _detectionSubscription?.cancel();
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
                "Online Vision",
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
                color: _isOnlineVisionActive ? const Color(0xFF76FF03).withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _isOnlineVisionActive ? const Color(0xFF76FF03) : Colors.grey),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_done, size: 12, color: _isOnlineVisionActive ? const Color(0xFF76FF03) : Colors.grey),
                  const SizedBox(width: 5),
                  Text(
                    _isOnlineVisionActive ? "ONLINE (${_cloudLatencyMs}ms)" : "PAUSED",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _isOnlineVisionActive ? const Color(0xFF76FF03) : Colors.grey,
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
            // 1. Top Real-time Internet & System Telemetry
            _buildTelemetryBar(),
            const SizedBox(height: 14),

            // 2. Portrait Camera Viewfinder with Live Online Obstacle Bounding Boxes
            _buildPortraitCameraViewfinder(hasCriticalHazard),
            const SizedBox(height: 14),

            // 3. Online Cloud Vision Status & Detected Obstacle Banner
            _buildOnlineObstacleCard(hasCriticalHazard),
            const SizedBox(height: 14),

            // 4. Destination & Landmark Nameboard Navigation
            _buildLandmarkNavigationCard(),
            const SizedBox(height: 14),

            // 5. 12-Hour Clock Navigation Radar
            _buildNavigationRadar(),
            const SizedBox(height: 14),

            // 5. Audio Mutex & Speech State
            _buildAudioStatusCard(hasCriticalHazard),
            const SizedBox(height: 14),

            // 6. Interactive Testing & Real-Time Controls
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
          _buildStat("INFERENCE", "Internet / Cloud", Icons.cloud_outlined, const Color(0xFF76FF03)),
          _buildStat("LATENCY", "${_cloudLatencyMs}ms", Icons.speed, const Color(0xFF00E5FF)),
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
    return Container(
      height: 380,
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

            // Reticle / Visual Focus in Center
            Center(
              child: Icon(
                Icons.filter_center_focus,
                size: 80,
                color: hasCriticalHazard ? const Color(0xFFFF1744).withValues(alpha: 0.4) : Colors.cyanAccent.withValues(alpha: 0.25),
              ),
            ),

            // Top Status Overlay
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
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.portrait, size: 12, color: Color(0xFF00E5FF)),
                        const SizedBox(width: 4),
                        const Text("PORTRAIT VIEW", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: hasCriticalHazard ? Colors.red.withValues(alpha: 0.85) : Colors.green.withValues(alpha: 0.7),
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

            // Render Target Nameboard Reticle if sighted
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

            // Render Live Cloud-Detected Obstacle Bounding Boxes
            if (_primaryHazard != null)
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 170,
                  height: 190,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _primaryHazard!.isHazard ? const Color(0xFFFF1744) : const Color(0xFF00E5FF),
                      width: 3,
                    ),
                    color: (_primaryHazard!.isHazard ? const Color(0xFFFF1744) : const Color(0xFF00E5FF)).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          color: _primaryHazard!.isHazard ? const Color(0xFFFF1744) : const Color(0xFF00E5FF),
                          child: Text(
                            "${_primaryHazard!.label.toUpperCase()} ${(_primaryHazard!.confidence * 100).toInt()}%",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _primaryHazard!.isHazard ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          "Dist: ${_primaryHazard!.distanceMeters.toStringAsFixed(1)}m",
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Text(
                          "TTC: ${_primaryHazard!.ttcSeconds.toStringAsFixed(1)}s",
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber),
                        ),
                        Text(
                          "Vector: ${_primaryHazard!.clockPosition}",
                          style: const TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      ],
                    ),
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
                    Text("Cloud Latency: ${_cloudLatencyMs}ms", style: const TextStyle(fontSize: 11, color: Color(0xFF00E5FF))),
                    Text("Haptic: $_lastHaptic", style: const TextStyle(fontSize: 11, color: Color(0xFF76FF03))),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildOnlineObstacleCard(bool hasCriticalHazard) {
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
                  Icon(Icons.wifi, color: Color(0xFF00E5FF), size: 18),
                  SizedBox(width: 8),
                  Text(
                    "REAL-TIME INTERNET DETECTION",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                  ),
                ],
              ),
              Switch(
                value: _isOnlineVisionActive,
                activeThumbColor: const Color(0xFF76FF03),
                onChanged: (val) {
                  setState(() {
                    _isOnlineVisionActive = val;
                    _onlineDetector.setEnabled(val);
                  });
                  if (val) {
                    _startOnlineVisionStream();
                  } else {
                    _onlineStreamTimer?.cancel();
                  }
                },
              )
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _cloudStatus,
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
                    obs.isHazard ? Icons.warning_amber_rounded : Icons.info_outline,
                    color: obs.isHazard ? const Color(0xFFFF1744) : const Color(0xFF00E5FF),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "${obs.label} (${obs.clockPosition})",
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

  Widget _buildLandmarkNavigationCard() {
    final isNavigating = _navService.isNavigating;
    final navState = _navState;
    final dest = _navService.activeDestination;

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
                        "DESTINATION & BOARDS",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: phaseColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: phaseColor),
                ),
                child: Text(
                  isNavigating ? "ACTIVE" : "STANDBY",
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: phaseColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Active Navigation Guidance Banner
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
                      Text(
                        dest.name.toUpperCase(),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
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
                            const Text("DISTANCE & VECTOR", style: TextStyle(fontSize: 9, color: Colors.white54)),
                            Text(
                              "${(navState?.distanceMeters ?? 0.0).toStringAsFixed(1)}m • ${navState?.clockDirection ?? '12 o\'clock'}",
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
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            _navService.simulateStepCloser(10.0);
                          },
                          icon: const Icon(Icons.directions_walk, size: 16),
                          label: const Text("Walk 10m Closer", style: TextStyle(fontSize: 11)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF00E5FF),
                            side: const BorderSide(color: Color(0xFF00E5FF)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            _navService.stopNavigation();
                          },
                          icon: const Icon(Icons.stop, size: 16),
                          label: const Text("Stop Nav", style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.withValues(alpha: 0.8),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Destination Search / Quick Selector
          const Text(
            "SELECT DESTINATION OR SHOP:",
            style: TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: NavTargetDestination.defaultDestinations.map((d) {
                final isSelected = dest?.id == d.id;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: isSelected,
                    selectedColor: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                    backgroundColor: const Color(0xFF1E293B),
                    label: Text(d.name, style: TextStyle(fontSize: 11, color: isSelected ? const Color(0xFF00E5FF) : Colors.white)),
                    onSelected: (_) {
                      _navService.startNavigation(d);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),

          // Custom Search Input Field
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _destinationInputController,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Enter custom shop/room name...",
                    hintStyle: const TextStyle(fontSize: 11, color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  final text = _destinationInputController.text.trim();
                  if (text.isNotEmpty) {
                    final customDest = NavTargetDestination(
                      id: "custom_${DateTime.now().millisecondsSinceEpoch}",
                      name: text,
                      category: "Custom Target",
                      latitude: 17.4436,
                      longitude: 78.3774,
                      aliases: [text.toLowerCase()],
                    );
                    _navService.startNavigation(customDest);
                    _destinationInputController.clear();
                  }
                },
                icon: const Icon(Icons.search, size: 16),
                label: const Text("Go", style: TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ],
          ),
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
              Row(
                children: [
                  Icon(
                    _isSpeaking ? Icons.volume_up : Icons.volume_mute,
                    color: _isSpeaking ? const Color(0xFF76FF03) : Colors.white54,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text("ZERO-OVERLAP AUDIO MUTEX", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _isSpeaking ? const Color(0xFF76FF03).withValues(alpha: 0.2) : Colors.white10,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _isSpeaking ? "SPEAKING" : "IDLE",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _isSpeaking ? const Color(0xFF76FF03) : Colors.white70,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1420),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: Text(
              _activeSpeech,
              style: TextStyle(
                fontSize: 12,
                color: hasCriticalHazard ? const Color(0xFFFF1744) : Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showApiConfigDialog() {
    final urlController = TextEditingController(text: "http://127.0.0.1:8000/detect");
    final keyController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131B2A),
        title: const Text("Configure Vision API / Cloud Endpoint", style: TextStyle(fontSize: 15, color: Color(0xFF00E5FF))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Endpoint URL (YOLOv8 server or Cloud Vision API):", style: TextStyle(fontSize: 11, color: Colors.white70)),
            const SizedBox(height: 6),
            TextField(
              controller: urlController,
              style: const TextStyle(fontSize: 12, color: Colors.white),
              decoration: const InputDecoration(
                filled: true,
                fillColor: Color(0xFF1E293B),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            const Text("API Key / Bearer Token (Optional):", style: TextStyle(fontSize: 11, color: Colors.white70)),
            const SizedBox(height: 6),
            TextField(
              controller: keyController,
              style: const TextStyle(fontSize: 12, color: Colors.white),
              decoration: const InputDecoration(
                filled: true,
                fillColor: Color(0xFF1E293B),
                border: OutlineInputBorder(),
                isDense: true,
                hintText: "Bearer token if required...",
                hintStyle: TextStyle(fontSize: 11, color: Colors.white24),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              final url = urlController.text.trim();
              if (url.isNotEmpty) {
                _onlineDetector.configureEndpoint(
                  url: url,
                  apiKey: keyController.text.trim().isNotEmpty ? keyController.text.trim() : null,
                );
                _onlineDetector.forceRescan();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Vision endpoint configured to: $url")),
                );
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF), foregroundColor: Colors.black),
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Widget _buildControlBar() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("QUICK ACTIONS & TESTING", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  _onlineDetector.forceRescan();
                  _captureAndAnalyzeCloudFrame();
                },
                icon: const Icon(Icons.refresh, color: Colors.black, size: 16),
                label: const Text("Rescan Surroundings (Tell Once)"),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF), foregroundColor: Colors.black),
              ),
              OutlinedButton.icon(
                onPressed: _showApiConfigDialog,
                icon: const Icon(Icons.settings_ethernet, size: 16, color: Color(0xFF00E5FF)),
                label: const Text("Config Vision API URL", style: TextStyle(color: Color(0xFF00E5FF))),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF00E5FF))),
              ),
              ElevatedButton.icon(
                onPressed: _clearHazards,
                icon: const Icon(Icons.check_circle, color: Colors.black, size: 16),
                label: const Text("Clear Path"),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF76FF03), foregroundColor: Colors.black),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  _audioMutex.speak(
                    text: "Turn 90 degrees right towards corridor at 3 o'clock.",
                    priority: AudioPriority.level2Navigation,
                    haptic: true,
                  );
                },
                icon: const Icon(Icons.record_voice_over, size: 16),
                label: const Text("Speak Guidance"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

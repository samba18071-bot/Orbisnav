import 'dart:async';
import 'dart:io';
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
import 'services/conversational_voice_qa_service.dart';
import 'services/offline_scene_captioning_service.dart';
import 'services/spatial_binaural_earcon_service.dart';
import 'services/object_finder_sonar_service.dart';
import 'services/assistive_item_detector.dart';
import 'services/tactile_haptic_map_service.dart';
import 'services/emergency_sos_sentinel_service.dart';
import 'services/wearable_wrist_haptic_service.dart';
import 'services/global_standards_service.dart';
import 'services/smart_cane_ble_service.dart';
import 'services/smart_glasses_bridge_service.dart';
import 'controllers/eyes_free_gesture_controller.dart';
import 'services/sensory_haptic_service.dart';
import 'ui/views/voice_camera_screen.dart';

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

class _OrbisNavLiveAppState extends State<OrbisNavLiveApp>
    with WidgetsBindingObserver {
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
  OptimalPathRecommendation? _optimalPath;
  Timer? _visionStreamTimer;

  // Multimodal AI Scene Comprehension State
  SceneAnalysisResult _latestSceneAnalysis = SceneAnalysisResult.empty();
  StreamSubscription<SceneAnalysisResult>? _sceneAnalysisSubscription;
  bool _isExplainingSituation = false;

  // Destination & Landmark Nameboard Navigation (4km Radius Discovery)
  final NameboardNavigationService _navService = NameboardNavigationService();


  // Day 6 & Day 7: Conversational Multimodal Voice Q&A Assistant
  final ConversationalVoiceQAService _voiceQaService =
      ConversationalVoiceQAService();
  StreamSubscription<VoiceQAExchange>? _voiceQaSubscription;
  VoiceQAExchange? _lastVoiceExchange;
  final TextEditingController _voiceQuestionInputController =
      TextEditingController();

  // Day 10: Offline Scene Captioning Fallback Engine
  final OfflineSceneCaptioningService _captioningService =
      OfflineSceneCaptioningService();
  StreamSubscription<OfflineSceneCaption>? _captionSubscription;
  OfflineSceneCaption? _lastOfflineCaption;

  // Spatial Binaural 3D Elevation Earcon Service (Head-Level, Torso, Drop-Off)
  final SpatialBinauralEarconService _earconService =
      SpatialBinauralEarconService();
  StreamSubscription<SpatialEarconCue>? _earconSubscription;
  SpatialEarconCue? _lastEarconCue;



  final ObjectFinderSonarService _objectFinderService =
      ObjectFinderSonarService();
  StreamSubscription<ObjectFinderTarget>? _objectFinderSubscription;
  ObjectFinderTarget _lastObjectFinderState =
      ObjectFinderTarget.initial("keys");

  final TactileHapticMapService _tactileMapService =
      TactileHapticMapService();
  TactileTouchResult? _lastTactileTouchResult;

  final EmergencySosSentinelService _emergencySosService =
      EmergencySosSentinelService();
  StreamSubscription<EmergencySosState>? _emergencySosSubscription;
  EmergencySosState _lastEmergencySosState =
      EmergencySosState.monitoring();

  final WearableWristHapticService _wristHapticService =
      WearableWristHapticService();
  StreamSubscription<WristHapticPattern>? _wristHapticSubscription;
  WristHapticPattern? _lastWristHapticPattern;

  // Global Standards, Accessibility & Internationalization Engine
  final GlobalStandardsService _globalStandards = GlobalStandardsService();

  // 10/10 Hardware Ecosystem: Smart White Cane BLE & Wearable Smart Glasses
  final SmartWhiteCaneBleService _smartCaneService = SmartWhiteCaneBleService();
  StreamSubscription<SmartCaneState>? _smartCaneSubscription;
  SmartCaneState _lastCaneState = SmartCaneState.initial();

  final SmartGlassesBridgeService _smartGlassesService =
      SmartGlassesBridgeService();
  StreamSubscription<SmartGlassesState>? _smartGlassesSubscription;
  SmartGlassesState _lastGlassesState = SmartGlassesState.initial();

  final SensoryHapticService _sensoryHaptics = SensoryHapticService();
  late final EyesFreeGestureController _eyesFreeGestureController;

  int _activeNavTab = 0; // 0: Hazard HUD, 1: Lost Item Sonar

  // Lost Item Sonar Radar state (Channel 2 of 2 - Voice & Object Detection)
  Timer? _itemSonarStreamTimer;
  Timer? _sonarPingTimer;
  bool _isProcessingSonarFrame = false;
  final TextEditingController _voiceSonarItemController =
      TextEditingController();

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
    // 0. Initialize Eyes-Free Multi-Touch Gesture & Sensory Haptic Controller
    _eyesFreeGestureController = EyesFreeGestureController(
      audioMutex: _audioMutex,
      hapticService: _sensoryHaptics,
      initialMode: _activeNavTab,
      maxModes: 2,
      enableShakeDetection: true,
    );
    _eyesFreeGestureController.onModeChanged = (newMode) {
      if (mounted) {
        _switchChannel(newMode);
      }
    };
    _eyesFreeGestureController.onEmergencySosTriggered = () {
      if (mounted) {
        _emergencySosService.triggerManualSos();
      }
    };
    _eyesFreeGestureController.onSpatialAuditRequested = () {
      if (mounted) {
        _sensoryHaptics.triggerPattern(TactilePatternType.actionConfirmed);
      }
    };

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
        // Head-height overhead hazard filtering via Smart Glasses
        var processedObstacles =
            _smartGlassesService.filterHeadHeightHazards(result.obstacles);
        // Ground-level ultrasonic sensor fusion via Smart White Cane BLE
        processedObstacles = _smartCaneService.fuseObstaclesWithCane(
            cameraObstacles: processedObstacles);

        setState(() {
          _inferenceLatencyMs = result.latencyMs;
          _visionStatus = result.statusMessage;
          _activeObstacles = processedObstacles;
          _primaryHazard = result.highestHazard;
          _optimalPath = result.optimalPath;
        });
        // World-Class Add-On Services Real-Time Feed
        _tactileMapService.updateObstacleGrid(processedObstacles);
        _objectFinderService.updateVisionCandidates(processedObstacles);

        // Real-Time 3D Binaural Earcon Hazard Spatializer
        if (result.highestHazard != null) {
          _earconService.dispatchSpatialEarcon(
            obstacle: result.highestHazard!,
            estimatedElevationMeters:
                result.highestHazard!.isHazard ? 1.6 : 1.0,
          );
        }
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

    // 4d. Listen to Conversational Voice Q&A Stream
    _voiceQaSubscription = _voiceQaService.qaStream.listen((exchange) {
      if (mounted) {
        setState(() {
          _lastVoiceExchange = exchange;
        });
      }
    });

    // 4e. Listen to Offline Scene Captioning Stream
    _captionSubscription = _captioningService.captionStream.listen((cap) {
      if (mounted) {
        setState(() {
          _lastOfflineCaption = cap;
        });
      }
    });

    // Binaural 3D Earcon stream
    _earconSubscription = _earconService.cueStream.listen((cue) {
      if (mounted) {
        setState(() {
          _lastEarconCue = cue;
        });
      }
    });

    _objectFinderSubscription =
        _objectFinderService.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _lastObjectFinderState = state;
        });
      }
    });

    _emergencySosSubscription =
        _emergencySosService.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _lastEmergencySosState = state;
        });
      }
    });

    _wristHapticSubscription =
        _wristHapticService.hapticStream.listen((pattern) {
      if (mounted) {
        setState(() {
          _lastWristHapticPattern = pattern;
        });
      }
    });

    _smartCaneSubscription = _smartCaneService.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _lastCaneState = state;
        });
      }
    });

    _smartGlassesSubscription =
        _smartGlassesService.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _lastGlassesState = state;
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
    _audioMutex.setActiveChannel(_activeNavTab);
    _stopAllChannelsExcept(_activeNavTab);
    if (_activeNavTab == 0) {
      _startVisionStream();
    }

    // Initial voice greeting
    _audioMutex.speak(
      text:
          "AI Eyes obstacle and motion detection activated. Standalone offline mode ready.",
      priority: AudioPriority.level2Navigation,
      channelIndex: 0,
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
        await _cameraController!
            .lockCaptureOrientation(DeviceOrientation.portraitUp);
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
    _sensorSubscription =
        accelerometerEventStream().listen((AccelerometerEvent event) {
      final ax = event.x;
      final ay = event.y;
      final az = event.z;
      final pitchRad = math.atan2(-ay, math.sqrt(ax * ax + az * az));
      final pitchDeg = pitchRad * (180.0 / math.pi);
      final rollDeg = math.atan2(ax, az) * (180.0 / math.pi);

      // Always update pitch and roll variables instantly for vision calculations
      _pitchDeg = pitchDeg;
      _rollDeg = rollDeg;

      // Ingest accelerometer into Fall & Accident Sentinel
      _emergencySosService.ingestAccelerometer(x: ax, y: ay, z: az);

      // PDR Step Detection
      final magnitude = math.sqrt(ax * ax + ay * ay + az * az);
      final now = DateTime.now();
      if (_lastAccelMagnitude < 11.2 &&
          magnitude >= 11.2 &&
          now.difference(_lastStepTime).inMilliseconds > 350) {
        _lastStepTime = now;
        _onStepDetected();
      }
      _lastAccelMagnitude = magnitude;

      // Downward pitch haptic alert (severe downward pitch > 45°) - 60s cooldown
      if (pitchDeg < -45.0) {
        final nowTime = DateTime.now();
        if (_lastTiltWarningTime == null ||
            nowTime.difference(_lastTiltWarningTime!).inSeconds >= 60) {
          _lastTiltWarningTime = nowTime;
          HapticFeedback.mediumImpact();
        }
      }
    });
  }

  void _onStepDetected() {
    _stepCount++;
    if (mounted) {
      setState(() {});
    }
    HapticFeedback.lightImpact();
  }

  /// High-efficiency detection loop: runs asynchronously without locking the UI or thrashing camera ISP
  void _startVisionStream() {
    _visionStreamTimer?.cancel();
    _visionStreamTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (_activeNavTab == 0 &&
          _isVisionActive &&
          _isCameraInitialized &&
          !_isProcessingFrame &&
          !_isExplainingSituation &&
          _cameraController != null &&
          _cameraController!.value.isInitialized &&
          !_cameraController!.value.isTakingPicture) {
        _processFrame();
      }
    });
  }

  Future<void> _processFrame() async {
    if (_activeNavTab != 0 ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _cameraController!.value.isTakingPicture ||
        _isProcessingFrame ||
        _isExplainingSituation) {
      return;
    }

    _isProcessingFrame = true;
    try {
      final image = await _cameraController!.takePicture();
      final bytes = await image.readAsBytes();

      // Immediately abort if user switched away from Channel 0
      if (_activeNavTab != 0) return;

      // Immediately delete temporary captured photo to prevent storage/cache accumulation
      try {
        final f = File(image.path);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}

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

  /// Stops detection, clears speech queues, and provides an exclusive voice explanation of the situation.
  Future<void> _explainSituation() async {
    if (_isExplainingSituation) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized)
      return;

    setState(() {
      _isExplainingSituation = true;
    });

    // 1. Immediately pause ongoing obstacle detection and stop active audio alerts
    _onDeviceDetector.setEnabled(false);
    await _audioMutex.stopAll();

    try {
      // 2. Capture fresh scene snapshot
      final img = await _cameraController!.takePicture();
      final bytes = await img.readAsBytes();

      // 3. Analyze real-time situation
      final result = await _cloudAiService.analyzeScene(
        bytes,
        currentObstacles: _activeObstacles,
        devicePitchDeg: _pitchDeg,
        force: true,
        speakResult: false,
      );

      final explanationText = result.sceneSummary.isNotEmpty
          ? result.sceneSummary
          : "Path directly ahead is clear of obstacles.";

      // 4. Speak situation explanation with priority
      await _audioMutex.speak(
        text: explanationText,
        priority: AudioPriority.level1Safety,
        force: true,
        haptic: false,
      );
    } catch (e) {
      debugPrint("[SceneComprehension] Explain situation exception: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isExplainingSituation = false;
        });
      }
      // 5. Resume on-device obstacle detection
      _onDeviceDetector.setEnabled(true);
      _onDeviceDetector.forceRescan();
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
    _voiceQaSubscription?.cancel();
    _captionSubscription?.cancel();
    _earconSubscription?.cancel();
    _objectFinderSubscription?.cancel();
    _emergencySosSubscription?.cancel();
    _wristHapticSubscription?.cancel();
    _smartCaneSubscription?.cancel();
    _smartGlassesSubscription?.cancel();
    _voiceQaService.dispose();
    _captioningService.dispose();
    _earconService.dispose();
    _eyesFreeGestureController.dispose();
    _objectFinderService.dispose();
    _tactileMapService.dispose();
    _emergencySosService.dispose();
    _wristHapticService.dispose();
    _smartCaneService.dispose();
    _smartGlassesService.dispose();
    _speechSubscription?.cancel();
    _itemSonarStreamTimer?.cancel();
    _sonarPingTimer?.cancel();
    _voiceQuestionInputController.dispose();
    _voiceSonarItemController.dispose();
    _navService.stopNavigation();
    _cameraController?.dispose();
    _audioMutex.dispose();
    super.dispose();
  }

  void _stopAllChannelsExcept(int activeChannel) {
    // Channel 0 (Safety HUD): Stop vision stream, cancel timer, disable detector
    if (activeChannel != 0) {
      _visionStreamTimer?.cancel();
      _visionStreamTimer = null;
      _onDeviceDetector.setEnabled(false);
      _isProcessingFrame = false;
    }

    // Channel 1 (Lost Item Sonar): Cancel sonar stream timer, ping timer, and stop object search
    if (activeChannel != 1) {
      _itemSonarStreamTimer?.cancel();
      _itemSonarStreamTimer = null;
      _sonarPingTimer?.cancel();
      _sonarPingTimer = null;
      _isProcessingSonarFrame = false;
      _objectFinderService.stopSearch();
    }
  }

  void _switchChannel(int newChannel) {
    if (newChannel == _activeNavTab) return;

    // 1. Immediately inform AudioMutex of active channel switch & stop/purge previous channel tasks
    _audioMutex.setActiveChannel(newChannel);
    _audioMutex.stopAll();

    // 2. Hard stop ALL other channels completely
    _stopAllChannelsExcept(newChannel);

    // 3. Clear all camera frame locks so the newly activated channel starts immediately without deadlock
    _isProcessingFrame = false;
    _isProcessingSonarFrame = false;

    setState(() {
      _activeNavTab = newChannel;
    });

    // 2. Start/resume tasks for newly activated channel
    if (newChannel == 0) {
      _onDeviceDetector.setEnabled(true);
      _startVisionStream();
    } else if (newChannel == 1) {
      // Channel 2 of 2: Auto-start Lost Item Sonar stream with immediate active search
      _onDeviceDetector.setEnabled(true);
      if (!_objectFinderService.isSearching) {
        _objectFinderService.startSearch(_objectFinderService.activeTargetLabel);
      }
      _startItemSonarStream();
    }

    final channelNames = [
      "Safety Hazard HUD",
      "Lost Item Sonar Radar",
    ];

    HapticFeedback.heavyImpact();
    _audioMutex.speak(
      text: "Switched to ${channelNames[newChannel]} Mode.",
      priority: AudioPriority.level2Navigation,
      channelIndex: newChannel,
      force: true,
      haptic: true,
    );
  }


  void _startItemSonarStream() {
    _onDeviceDetector.setEnabled(true);
    _itemSonarStreamTimer?.cancel();
    _itemSonarStreamTimer =
        Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (_activeNavTab == 1 &&
          _isCameraInitialized &&
          !_isProcessingSonarFrame &&
          _cameraController != null &&
          _cameraController!.value.isInitialized &&
          !_cameraController!.value.isTakingPicture) {
        _processSonarCameraFrame();
      }
    });

    _startSonarAcousticLoop();
  }

  void _startSonarAcousticLoop() {
    _sonarPingTimer?.cancel();
    if (!_objectFinderService.isSearching || _activeNavTab != 1) return;

    final target = _objectFinderService.currentState;
    final interval = target.sonarPingIntervalMs.clamp(80, 1200);

    _sonarPingTimer = Timer(Duration(milliseconds: interval), () {
      if (!mounted || _activeNavTab != 1 || !_objectFinderService.isSearching) return;

      if (target.isFound) {
        HapticFeedback.selectionClick();
        SystemSound.play(SystemSoundType.click);
      } else {
        HapticFeedback.lightImpact();
      }

      // Chain next ping
      _startSonarAcousticLoop();
    });
  }

  Future<void> _processSonarCameraFrame() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _cameraController!.value.isTakingPicture ||
        _isProcessingSonarFrame ||
        _activeNavTab != 1) {
      return;
    }

    _isProcessingSonarFrame = true;
    try {
      final img = await _cameraController!.takePicture();
      final bytes = await img.readAsBytes();
      if (_activeNavTab != 1) return;
      try {
        final f = File(img.path);
        if (await f.exists()) await f.delete();
      } catch (_) {}

      // Ensure detector is enabled for real-time edge inference
      _onDeviceDetector.setEnabled(true);

      // Run on-device detector without hazard speech governance (Sonar drives its own audio cues)
      final result = await _onDeviceDetector.processFrameBytes(
        bytes,
        devicePitchDeg: _pitchDeg,
        speakGovernance: false,
      );
      if (_activeNavTab != 1) return;

      final candidateObstacles = List<DetectedObstacle>.from(result.obstacles);

      // Check cloud scene if active target is not standard or not in COCO
      if (_objectFinderService.isSearching) {
        final targetLabel =
            _objectFinderService.activeTargetLabel.toLowerCase();
        final hasMatch = candidateObstacles.any(
            (o) => _objectFinderService.isMatching(o.label, targetLabel));

        if (!hasMatch) {
          // 1. High-Precision On-Device Detection for everyday items (glasses, keys, charger, etc.)
          final assistiveItem = await AssistiveItemDetector().detectTargetItem(
            bytes,
            targetLabel,
            devicePitchDeg: _pitchDeg,
          );
          if (_activeNavTab != 1) return;

          if (assistiveItem != null) {
            candidateObstacles.add(assistiveItem);
          } else if (_cloudAiService.isAutoAnalyzeEnabled) {
            final cloudRes = await _cloudAiService.analyzeScene(
              bytes,
              currentObstacles: candidateObstacles,
              devicePitchDeg: _pitchDeg,
              speakResult: false,
            );

            // Check if cloud found the target
            for (final obj in cloudRes.detailedObjects) {
              if (_objectFinderService.isMatching(obj, targetLabel)) {
                candidateObstacles.add(
                  DetectedObstacle(
                    label: targetLabel,
                    confidence: 0.92,
                    xMin: 0.35,
                    yMin: 0.30,
                    xMax: 0.65,
                    yMax: 0.70,
                    distanceMeters: 1.2,
                    ttcSeconds: 4.0,
                    priority: AudioPriority.level2Navigation,
                    clockPosition: "12 o'clock",
                  ),
                );
                break;
              }
            }
          }
        }
      }

      // Update vision candidates in ObjectFinderSonarService (triggers instant found speech)
      final updatedState =
          _objectFinderService.updateVisionCandidates(candidateObstacles);

      if (mounted) {
        setState(() {
          _lastObjectFinderState = updatedState;
          if (candidateObstacles.isNotEmpty) {
            _activeObstacles = candidateObstacles;
          }
        });
      }

      _startSonarAcousticLoop();
    } catch (e) {
      debugPrint("Sonar frame processing error: $e");
    } finally {
      _isProcessingSonarFrame = false;
    }
  }

  void _startSonarSearchFor(String label) {
    _onDeviceDetector.setEnabled(true);
    _objectFinderService.startSearch(label);
    _startSonarAcousticLoop();
    _startItemSonarStream();
    setState(() {});
  }

  Future<void> _startVoiceItemSearch() async {
    HapticFeedback.heavyImpact();
    await _audioMutex.speak(
      text: "Listening. Speak the item you want to find.",
      priority: AudioPriority.level2Navigation,
      channelIndex: 1,
      force: true,
      haptic: true,
    );

    // Give TTS 1.2s to announce before opening microphone to avoid capturing app's own voice
    await Future.delayed(const Duration(milliseconds: 1200));

    final recognized = await _audioMutex.startVoiceInput();
    if (recognized.isNotEmpty) {
      var clean = recognized.toLowerCase().trim();
      final prefixes = [
        "find my ",
        "find ",
        "where is my ",
        "where's my ",
        "where is ",
        "where are my ",
        "locate my ",
        "locate ",
        "search for ",
        "look for ",
        "i lost my ",
        "i lost ",
        "bring me ",
        "show me "
      ];
      for (final p in prefixes) {
        if (clean.startsWith(p)) {
          clean = clean.substring(p.length).trim();
          break;
        }
      }
      if (clean.isNotEmpty) {
        _startSonarSearchFor(clean);
        return;
      }
    }

    _audioMutex.speak(
      text:
          "No speech recognized. Still searching for ${_objectFinderService.activeTargetLabel}.",
      priority: AudioPriority.level3Context,
      channelIndex: 1,
    );
  }


  @override
  Widget build(BuildContext context) {
    final hasCriticalHazard =
        _primaryHazard != null && _primaryHazard!.isHazard;

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
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 1.5),
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
                color: _isVisionActive
                    ? const Color(0xFF76FF03).withValues(alpha: 0.15)
                    : Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _isVisionActive
                        ? const Color(0xFF76FF03)
                        : Colors.grey),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions_run,
                      size: 13,
                      color: _isVisionActive
                          ? const Color(0xFF76FF03)
                          : Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    _isVisionActive
                        ? "MOTION ON (${_inferenceLatencyMs}ms)"
                        : "PAUSED",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _isVisionActive
                          ? const Color(0xFF76FF03)
                          : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: Color(0xFF00E5FF)),
            tooltip: "Open Voice Visual Cortex (Double-tap Torch / Voice Router)",
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VoiceCameraScreen(cameras: _cameras),
                ),
              );
            },
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () {
          _eyesFreeGestureController.handleTwoFingerDoubleTap();
          _triggerQuickVoiceQA("What is in front of me?");
        },
        onLongPress: () {
          _eyesFreeGestureController.handleLongPress(
            compassHeading: _pitchDeg,
            stepCount: _stepCount,
            closestObstacleMeters: _primaryHazard?.distanceMeters ?? 5.0,
          );
        },
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0.0;
          if (velocity < -120) {
            _eyesFreeGestureController.handleSwipeUp();
          } else if (velocity > 120) {
            _eyesFreeGestureController.handleSwipeDown();
          }
        },
        onHorizontalDragEnd: (details) {
          // Channel Swipe: Horizontal swipe switches channels and halts previous tasks immediately
          final velocity = details.primaryVelocity ?? 0.0;
          if (velocity < -120) {
            _eyesFreeGestureController.handleSwipeNext();
          } else if (velocity > 120) {
            _eyesFreeGestureController.handleSwipePrevious();
          }
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Broadcast-Style Channel Indicator Header (4 Channels)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: () => _switchChannel((_activeNavTab - 1 + 2) % 2),
                      child: const Row(
                        children: [
                          Icon(Icons.arrow_back_ios, size: 12, color: Colors.white70),
                          Text("SWIPE", style: TextStyle(fontSize: 10, color: Colors.white70)),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _activeNavTab == 0
                                ? const Color(0xFF00E5FF).withValues(alpha: 0.2)
                                : const Color(0xFFFF0055).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _activeNavTab == 0
                                ? "CHANNEL 1 OF 2: SAFETY HUD"
                                : "CHANNEL 2 OF 2: LOST ITEM SONAR",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                              color: _activeNavTab == 0
                                  ? const Color(0xFF00E5FF)
                                  : const Color(0xFFFF0055),
                            ),
                          ),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: () => _switchChannel((_activeNavTab + 1) % 2),
                      child: const Row(
                        children: [
                          Text("SWIPE", style: TextStyle(fontSize: 10, color: Colors.white70)),
                          Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white70),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 1. Clean Mode Switcher Tab Bar (Safety HUD / Navigation / Living & Care)
              _buildModeSwitcherTabBar(),
              const SizedBox(height: 12),

              if (_activeNavTab == 0) ...[
                // Primary Focus: Live Camera Viewfinder right on top!
                _buildPortraitCameraViewfinder(hasCriticalHazard),
                const SizedBox(height: 12),

                // Core Safety & Action Overview
                _buildObstacleDetectionCard(hasCriticalHazard),
                const SizedBox(height: 12),

                _buildOptimalPathGuidanceCard(hasCriticalHazard),
                const SizedBox(height: 12),

                // 3D Spatial Binaural Earcons
                _buildBinauralEarconStatusCard(),
                const SizedBox(height: 12),

                // Quick Voice Q&A / Situation Explanation
                _buildVoiceQACard(),
                const SizedBox(height: 12),

                // Quick Controls (Toggle Vision, Test Alert)
                _buildControlBar(),
                const SizedBox(height: 14),

                // Clean Collapsible Drawers for Secondary / Hardware Settings
                _buildAccordionSection(
                  title: "SMART HARDWARE (CANE & GLASSES)",
                  icon: Icons.devices_other,
                  color: const Color(0xFF00E5FF),
                  child: _buildSmartHardwareEcosystemCard(),
                ),

                _buildAccordionSection(
                  title: "EMERGENCY SOS & FALL SENTINEL",
                  icon: Icons.health_and_safety,
                  color: const Color(0xFFFF1744),
                  child: _buildEmergencySosCard(),
                ),

                _buildAccordionSection(
                  title: "DEVICE TELEMETRY & KINEMATICS",
                  icon: Icons.speed,
                  color: const Color(0xFF76FF03),
                  child: Column(
                    children: [
                      _buildTelemetryBar(),
                      const SizedBox(height: 10),
                      _buildMotionKinematicsCard(),
                    ],
                  ),
                ),

                _buildAccordionSection(
                  title: "ROOM MAP & SPATIAL PERCEPTION",
                  icon: Icons.grid_view_rounded,
                  color: const Color(0xFFFFD600),
                  child: Column(
                    children: [
                      _buildTactileRoomMapCard(),
                      const SizedBox(height: 10),
                      _buildSceneComprehensionCard(),
                    ],
                  ),
                ),

                _buildAccordionSection(
                  title: "GLOBAL ACCESSIBILITY & WCAG",
                  icon: Icons.public,
                  color: const Color(0xFF00E5FF),
                  child: _buildGlobalStandardsBar(),
                ),

                _buildAccordionSection(
                  title: "AUDIO CHANNEL MUTEX",
                  icon: Icons.volume_up,
                  color: Colors.white70,
                  child: _buildAudioStatusCard(hasCriticalHazard),
                ),
              ] else ...[
                // Channel 2 of 2: Dedicated Lost Item Sonar Radar Channel (Voice Query & Acoustic Echo-Location)
                _buildLostItemSonarChannel(),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccordionSection({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
    bool initiallyExpanded = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Material(
        color: Colors.transparent,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            leading: Icon(icon, color: color, size: 20),
            title: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: color,
              ),
            ),
            iconColor: color,
            collapsedIconColor: Colors.white38,
            childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            children: [child],
          ),
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
          _buildStat("MODE", "Portrait Live", Icons.screen_lock_portrait,
              const Color(0xFF00E5FF)),
          _buildStat("MOTION", "Kinematics Active", Icons.directions_run,
              const Color(0xFF76FF03)),
          _buildStat("LATENCY", "${_inferenceLatencyMs}ms", Icons.speed,
              const Color(0xFF00E5FF)),
          _buildStat(
              "GPS FIX",
              _navService.hasRealGpsFix ? "Active GPS" : "Sensor Nav",
              Icons.location_on,
              _navService.hasRealGpsFix
                  ? const Color(0xFF76FF03)
                  : Colors.orangeAccent),
          _buildStat("SOC TEMP", "${_tempC.toStringAsFixed(1)}°C",
              Icons.thermostat, const Color(0xFF76FF03)),
          _buildStat("BATTERY", "$_battery%", Icons.battery_charging_full,
              Colors.greenAccent),
          _buildStat(
              "WEARABLE",
              _lastWristHapticPattern != null
                  ? "${_lastWristHapticPattern!.patternMs.length} pulse"
                  : "Watch Synced",
              Icons.watch,
              const Color(0xFF00E5FF)),
          _buildStat(
              "CANE BLE",
              _lastCaneState.connectionStatus == CaneConnectionStatus.connected
                  ? "${_lastCaneState.batteryLevelPercent}%"
                  : "Standby",
              Icons.nordic_walking,
              _lastCaneState.connectionStatus == CaneConnectionStatus.connected
                  ? const Color(0xFF76FF03)
                  : Colors.white38),
          _buildStat(
              "GLASSES",
              _lastGlassesState.isConnected
                  ? _lastGlassesState.activeMountMode.name.toUpperCase()
                  : "Standby",
              Icons.visibility,
              _lastGlassesState.isConnected
                  ? const Color(0xFF00E5FF)
                  : Colors.white38),
        ],
      ),
    );
  }

  Widget _buildGlobalStandardsBar() {
    final lang = _globalStandards.currentLanguage;
    final unit = _globalStandards.measurementSystem;
    final emProfile = _globalStandards.emergencyProfile;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.public, color: Color(0xFF00E5FF), size: 16),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        "GLOBAL STANDARDS & ACCESSIBILITY",
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                          color: Color(0xFF00E5FF),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF76FF03).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF76FF03)),
                ),
                child: const Text(
                  "WCAG 2.2 AAA",
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF76FF03),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // 1. Language Switcher Chips (10 Global Languages)
                ...AppLanguage.values.take(6).map((l) {
                  final isSelected = lang == l;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Semantics(
                      button: true,
                      label: "Switch language to ${l.displayName}",
                      child: ChoiceChip(
                        selected: isSelected,
                        label: Text(
                          "${l.code.toUpperCase()} (${l.nativeName})",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.black : Colors.white70,
                          ),
                        ),
                        selectedColor: const Color(0xFF00E5FF),
                        backgroundColor: const Color(0xFF0A0E17),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _globalStandards.setLanguage(l);
                            });
                            _audioMutex.speak(
                              text: "Language set to ${l.displayName}.",
                              priority: AudioPriority.level2Navigation,
                              haptic: true,
                            );
                          }
                        },
                      ),
                    ),
                  );
                }),
                // 2. Metric / Imperial Unit Toggle
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Semantics(
                    button: true,
                    label: "Toggle units: currently ${unit.name}",
                    child: ActionChip(
                      backgroundColor: const Color(0xFF0A0E17),
                      side: const BorderSide(color: Color(0xFF76FF03)),
                      label: Text(
                        unit == MeasurementSystem.metric
                            ? "METRIC (m, km)"
                            : "IMPERIAL (ft, mi)",
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF76FF03),
                        ),
                      ),
                      onPressed: () {
                        final next = unit == MeasurementSystem.metric
                            ? MeasurementSystem.imperial
                            : MeasurementSystem.metric;
                        setState(() {
                          _globalStandards.setMeasurementSystem(next);
                        });
                        _audioMutex.speak(
                          text: "Measurement units set to ${next.name}.",
                          priority: AudioPriority.level2Navigation,
                          haptic: true,
                        );
                      },
                    ),
                  ),
                ),
                // 3. International Emergency Country Router
                Semantics(
                  button: true,
                  label:
                      "Emergency Dispatch: ${emProfile.countryName}, Number ${emProfile.emergencyNumber}",
                  child: ActionChip(
                    backgroundColor: const Color(0xFF0A0E17),
                    side: const BorderSide(color: Color(0xFFFF1744)),
                    label: Text(
                      "SOS: ${emProfile.countryCode} (${emProfile.emergencyNumber})",
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFF1744),
                      ),
                    ),
                    onPressed: () {
                      final codes = ['US', 'EU', 'GB', 'IN', 'JP', 'AU'];
                      final currentIndex =
                          codes.indexOf(emProfile.countryCode);
                      final nextIndex = (currentIndex + 1) % codes.length;
                      final nextCode = codes[nextIndex];
                      setState(() {
                        _globalStandards.setEmergencyCountry(nextCode);
                      });
                      final updated = _globalStandards.emergencyProfile;
                      _audioMutex.speak(
                        text:
                            "Emergency dispatch set to ${updated.countryName}, calling ${updated.emergencyNumber}.",
                        priority: AudioPriority.level2Navigation,
                        haptic: true,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartHardwareEcosystemCard() {
    final caneConnected =
        _lastCaneState.connectionStatus == CaneConnectionStatus.connected;
    final glassesConnected = _lastGlassesState.isConnected;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
          width: 1.5,
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
                  Icon(Icons.devices_other,
                      color: Color(0xFF00E5FF), size: 20),
                  SizedBox(width: 8),
                  Text(
                    "SMART HARDWARE ECOSYSTEM",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Color(0xFF00E5FF),
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF76FF03).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF76FF03)),
                ),
                child: const Text(
                  "10/10 TIER",
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF76FF03),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Sub-section A: Smart White Cane (BLE + Dual Haptics + Ultrasonic)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0E17),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: caneConnected
                    ? const Color(0xFF76FF03).withValues(alpha: 0.5)
                    : Colors.white12,
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
                        children: [
                          Icon(
                            Icons.nordic_walking,
                            color: caneConnected
                                ? const Color(0xFF76FF03)
                                : Colors.white38,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          const Flexible(
                            child: Text(
                              "SMART WHITE CANE (BLE)",
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: caneConnected
                          ? "Disconnect Smart White Cane"
                          : "Pair Smart White Cane via Bluetooth",
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          backgroundColor: caneConnected
                              ? Colors.redAccent.withValues(alpha: 0.15)
                              : const Color(0xFF76FF03)
                                  .withValues(alpha: 0.15),
                        ),
                        icon: Icon(
                          caneConnected
                              ? Icons.bluetooth_connected
                              : Icons.bluetooth_searching,
                          size: 14,
                          color: caneConnected
                              ? Colors.redAccent
                              : const Color(0xFF76FF03),
                        ),
                        label: Text(
                          caneConnected ? "DISCONNECT" : "CONNECT BLE",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: caneConnected
                                ? Colors.redAccent
                                : const Color(0xFF76FF03),
                          ),
                        ),
                        onPressed: () {
                          if (caneConnected) {
                            _smartCaneService.disconnect();
                          } else {
                            _smartCaneService.connectToSmartCane();
                          }
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  caneConnected
                      ? "Battery: ${_lastCaneState.batteryLevelPercent}% | Ground Dist: ${_lastCaneState.ultrasonicDistanceMeters.toStringAsFixed(2)}m"
                      : "WeWALK / UltraCane BLE sensor integration standby.",
                  style: TextStyle(
                    fontSize: 11,
                    color: caneConnected
                        ? const Color(0xFF76FF03)
                        : Colors.white60,
                  ),
                ),
                if (_lastCaneState.hasGroundObstacle ||
                    _lastCaneState.hasPotholeOrDropOff) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF1744).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFF1744)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning,
                            color: Color(0xFFFF1744), size: 14),
                        const SizedBox(width: 6),
                        Text(
                          _lastCaneState.hasPotholeOrDropOff
                              ? "CANE GROUND DROP-OFF DETECTED"
                              : "CANE ULTRASONIC OBSTACLE AHEAD",
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFF1744),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Sub-section B: Smart Vision Glasses (Eye-Level View & Overhead Hazards)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0E17),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: glassesConnected
                    ? const Color(0xFF00E5FF).withValues(alpha: 0.5)
                    : Colors.white12,
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
                        children: [
                          Icon(
                            Icons.visibility,
                            color: glassesConnected
                                ? const Color(0xFF00E5FF)
                                : Colors.white38,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          const Flexible(
                            child: Text(
                              "SMART GLASSES (RAY-BAN / META)",
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: glassesConnected
                          ? "Disconnect Smart Glasses"
                          : "Pair Smart Glasses",
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          backgroundColor: glassesConnected
                              ? Colors.redAccent.withValues(alpha: 0.15)
                              : const Color(0xFF00E5FF).withValues(alpha: 0.15),
                        ),
                        icon: Icon(
                          glassesConnected ? Icons.link_off : Icons.link,
                          size: 14,
                          color: glassesConnected
                              ? Colors.redAccent
                              : const Color(0xFF00E5FF),
                        ),
                        label: Text(
                          glassesConnected ? "DISCONNECT" : "CONNECT",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: glassesConnected
                                ? Colors.redAccent
                                : const Color(0xFF00E5FF),
                          ),
                        ),
                        onPressed: () {
                          if (glassesConnected) {
                            _smartGlassesService.disconnect();
                          } else {
                            _smartGlassesService.connectGlasses();
                          }
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      "Perspective: ${_lastGlassesState.activeMountMode.name.toUpperCase()}",
                      style: TextStyle(
                        fontSize: 11,
                        color: glassesConnected
                            ? const Color(0xFF00E5FF)
                            : Colors.white60,
                      ),
                    ),
                    const Spacer(),
                    Semantics(
                      button: true,
                      label: "Cycle camera perspective mode",
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          side: const BorderSide(color: Color(0xFF00E5FF)),
                        ),
                        child: const Text(
                          "SWITCH MODE",
                          style: TextStyle(
                              fontSize: 9, color: Color(0xFF00E5FF)),
                        ),
                        onPressed: () {
                          final current = _lastGlassesState.activeMountMode;
                          final next = current == CameraMountMode.smartGlasses
                              ? CameraMountMode.chestLanyard
                              : current == CameraMountMode.chestLanyard
                                  ? CameraMountMode.handheld
                                  : CameraMountMode.smartGlasses;
                          _smartGlassesService.setMountMode(next);
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  "Eye-Level Overhead Hazard Guard: Active (Low branches & awnings < 2m)",
                  style: TextStyle(fontSize: 10, color: Colors.white38),
                ),
              ],
            ),
          ),
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
            Text(label,
                style: const TextStyle(fontSize: 9, color: Colors.white54)),
            Text(value,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: color)),
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
              color: hasCriticalHazard
                  ? const Color(0xFFFF1744)
                  : const Color(0xFF00E5FF).withValues(alpha: 0.4),
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
                          Icon(Icons.camera_alt,
                              size: 48,
                              color: Colors.white.withValues(alpha: 0.2)),
                          const SizedBox(height: 8),
                          const Text(
                            "Connecting Portrait Camera Stream...",
                            style:
                                TextStyle(fontSize: 12, color: Colors.white54),
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
                    color: hasCriticalHazard
                        ? const Color(0xFFFF1744).withValues(alpha: 0.4)
                        : Colors.cyanAccent.withValues(alpha: 0.20),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.portrait,
                                size: 12, color: Color(0xFF00E5FF)),
                            const SizedBox(width: 4),
                            Text(
                              "PORTRAIT • ${_activeObstacles.length} OBJECTS",
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: hasCriticalHazard
                              ? Colors.red.withValues(alpha: 0.85)
                              : Colors.green.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          hasCriticalHazard ? "HAZARD DETECTED" : "PATH CLEAR",
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),

                // Dynamic Live Bounding Boxes with Motion Indicators
                ..._activeObstacles.map((obs) {
                  final left =
                      (obs.xMin * boxWidth).clamp(0.0, boxWidth - 40.0);
                  final top =
                      (obs.yMin * boxHeight).clamp(0.0, boxHeight - 30.0);
                  final width =
                      ((obs.xMax - obs.xMin) * boxWidth).clamp(40.0, boxWidth);
                  final height = ((obs.yMax - obs.yMin) * boxHeight)
                      .clamp(30.0, boxHeight);
                  final color = obs.isHazard
                      ? const Color(0xFFFF1744)
                      : (obs.isMoving
                          ? const Color(0xFFFFD600)
                          : const Color(0xFF00E5FF));

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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            color: color,
                            child: Text(
                              "${obs.label.toUpperCase()} ${(obs.confidence * 100).toInt()}% • ${obs.formattedMotionBadge} • ${obs.distanceMeters.toStringAsFixed(1)}m",
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color:
                                    obs.isHazard ? Colors.white : Colors.black,
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFF00E676), width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF00E676).withValues(alpha: 0.35),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.storefront,
                              color: Color(0xFF00E676), size: 26),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  "TARGET NAMEBOARD SIGHTED (${(_navService.targetBoard!.confidence * 100).toInt()}% CONF)",
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF00E676),
                                      letterSpacing: 1.1),
                                ),
                                Text(
                                  _navService.targetBoard!.text,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white),
                                ),
                                Text(
                                  "Vector: ${_navService.targetBoard!.clockZone} • Dist: ${_navService.targetBoard!.distanceMeters.toStringAsFixed(1)}m",
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E676),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              "LOCKED",
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                        Text("Pitch: ${_pitchDeg.toStringAsFixed(1)}°",
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _pitchDeg < -30
                                    ? Colors.orange
                                    : Colors.white)),
                        Text("Roll: ${_rollDeg.toStringAsFixed(1)}°",
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white70)),
                        Text("Latency: ${_inferenceLatencyMs}ms",
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF00E5FF))),
                        Text("Haptic: $_lastHaptic",
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF76FF03))),
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

  void _speakAllDetectedObjects() {
    if (_activeObstacles.isEmpty) {
      _audioMutex.speak(
        text: "The path is clear. No obstacles detected in your immediate field of view.",
        priority: AudioPriority.level2Navigation,
        force: true,
        haptic: true,
      );
      return;
    }

    final count = _activeObstacles.length;
    final opt = _optimalPath ??
        OptimalPathRecommendation.computeOptimalPath(_activeObstacles);
    final buffer = StringBuffer();
    buffer.write("Scene explanation: $count ${count == 1 ? "object" : "objects"} detected. ");
    for (int i = 0; i < count; i++) {
      final obs = _activeObstacles[i];
      buffer.write("Object ${i + 1}: ${obs.comprehensiveExplanation} ");
    }
    buffer.write(opt.safeWalkingRouteSummary);

    _audioMutex.speak(
      text: buffer.toString(),
      priority: AudioPriority.level1Safety,
      force: true,
      haptic: true,
    );
  }

  void _speakSingleObject(DetectedObstacle obs) {
    _audioMutex.speak(
      text: obs.comprehensiveExplanation,
      priority: AudioPriority.level1Safety,
      force: true,
      haptic: true,
    );
  }

  void _speakOptimalSafeWalkingRoute() {
    final opt = _optimalPath ??
        OptimalPathRecommendation.computeOptimalPath(_activeObstacles);
    final steps = opt.stepByStepGuidance.join(' ');
    final message = "${opt.safeWalkingRouteSummary} Step by step walking route: $steps";
    _audioMutex.speak(
      text: message,
      priority: AudioPriority.level1Safety,
      force: true,
      haptic: true,
    );
  }

  /// Dedicated Real-Time Optimal Path Navigation Corridor Guidance Card
  Widget _buildOptimalPathGuidanceCard(bool hasCriticalHazard) {
    final opt = _optimalPath ??
        OptimalPathRecommendation.computeOptimalPath(_activeObstacles);

    IconData directionIcon;
    Color directionColor;
    String badgeText;

    switch (opt.direction) {
      case OptimalCorridorDirection.straightAhead:
        directionIcon = Icons.navigation;
        directionColor = const Color(0xFF00E676);
        badgeText = "PATH CLEAR (12 O'CLOCK)";
        break;
      case OptimalCorridorDirection.veerLeft:
        directionIcon = Icons.turn_left;
        directionColor = const Color(0xFF00E5FF);
        badgeText = "VEER LEFT (10 O'CLOCK)";
        break;
      case OptimalCorridorDirection.veerRight:
        directionIcon = Icons.turn_right;
        directionColor = const Color(0xFF00E5FF);
        badgeText = "VEER RIGHT (2 O'CLOCK)";
        break;
      case OptimalCorridorDirection.blockedHold:
        directionIcon = Icons.pan_tool_rounded;
        directionColor = const Color(0xFFFF1744);
        badgeText = "PATH BLOCKED (HOLD)";
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: directionColor.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: directionColor.withValues(alpha: 0.15),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.alt_route, color: directionColor, size: 18),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        "OPTIMAL ROUTE FOR SAFE WALKING",
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: directionColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                  border:
                      Border.all(color: directionColor.withValues(alpha: 0.6)),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: directionColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: directionColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: directionColor, width: 2.0),
                ),
                child: Icon(directionIcon, color: directionColor, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      opt.voiceInstruction,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Clearance: ${opt.clearanceMeters.toStringAsFixed(1)}m • Vector: ${opt.clockDirection}",
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: "Speak Safe Walking Route",
                icon: const Icon(Icons.volume_up,
                    color: Color(0xFF00E5FF), size: 22),
                onPressed: _speakOptimalSafeWalkingRoute,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Step-by-Step Safe Walking Corridor Guide
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0E17),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: directionColor.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.directions_walk,
                            size: 14, color: directionColor),
                        const SizedBox(width: 6),
                        const Text(
                          "SAFE WALKING ROUTE STEPS:",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      "${opt.clockDirection} Corridor",
                      style: TextStyle(
                        fontSize: 9,
                        color: directionColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ...opt.stepByStepGuidance.map((step) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.arrow_right,
                              size: 14, color: directionColor),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              step,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white70,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ],
      ),
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
          color: hasActiveMotion
              ? const Color(0xFFFFD600).withValues(alpha: 0.6)
              : Colors.white10,
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
                  Icon(Icons.directions_run,
                      color: hasActiveMotion
                          ? const Color(0xFFFFD600)
                          : const Color(0xFF00E5FF),
                      size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    "MOTION DETECTION & VELOCITY RADAR",
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hasActiveMotion
                      ? const Color(0xFFFFD600).withValues(alpha: 0.2)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: hasActiveMotion
                          ? const Color(0xFFFFD600)
                          : Colors.white24),
                ),
                child: Text(
                  hasActiveMotion ? "DYNAMIC MOVEMENT" : "STATIC SCENE",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: hasActiveMotion
                        ? const Color(0xFFFFD600)
                        : Colors.white54,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Motion Energy Bar
          Row(
            children: [
              const Text("SCENE ACTIVITY:",
                  style: TextStyle(
                      fontSize: 10,
                      color: Colors.white54,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: motionEnergy.clamp(0.05, 1.0),
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      motionEnergy > 0.5
                          ? const Color(0xFFFF1744)
                          : (motionEnergy > 0.2
                              ? const Color(0xFFFFD600)
                              : const Color(0xFF00E5FF)),
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
                  color: motionEnergy > 0.5
                      ? const Color(0xFFFF1744)
                      : const Color(0xFF00E5FF),
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
              } else if (obs.motionType ==
                  ObjectMotionType.movingAwayFromUser) {
                motionIcon = Icons.trending_up;
                motionColor = const Color(0xFF76FF03);
              } else if (obs.motionType ==
                  ObjectMotionType.crossingLeftToRight) {
                motionIcon = Icons.arrow_forward;
                motionColor = const Color(0xFF00E5FF);
              } else if (obs.motionType ==
                  ObjectMotionType.crossingRightToLeft) {
                motionIcon = Icons.arrow_back;
                motionColor = const Color(0xFF00E5FF);
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                          Text(
                            "Closing Speed: ${obs.velocityMps.abs()} m/s • TTC: ${obs.ttcSeconds}s • Vector: ${obs.clockPosition}",
                            style: const TextStyle(
                                fontSize: 10, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: motionColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        obs.formattedMotionBadge,
                        style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.black),
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
          color: hasCriticalHazard
              ? const Color(0xFFFF1744).withValues(alpha: 0.5)
              : Colors.white10,
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
                  Icon(Icons.remove_red_eye_outlined,
                      color: Color(0xFF00E5FF), size: 18),
                  SizedBox(width: 8),
                  Text(
                    "ON-DEVICE NEURAL VISION",
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _visionStatus,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
              if (_activeObstacles.isNotEmpty)
                InkWell(
                  onTap: _speakAllDetectedObjects,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.6)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.record_voice_over,
                            size: 13, color: Color(0xFF00E5FF)),
                        SizedBox(width: 5),
                        Text(
                          "EXPLAIN ALL",
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00E5FF)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (_activeObstacles.isNotEmpty) ...[
            const SizedBox(height: 10),
            ..._activeObstacles.map((obs) {
              final bypassText = obs.bypassRecommendation;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: obs.isHazard
                      ? const Color(0xFFFF1744).withValues(alpha: 0.12)
                      : const Color(0xFF00E5FF).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: obs.isHazard
                        ? const Color(0xFFFF1744).withValues(alpha: 0.8)
                        : const Color(0xFF00E5FF).withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          obs.motionType ==
                                  ObjectMotionType.approachingTowardsUser
                              ? Icons.directions_walk
                              : obs.motionType == ObjectMotionType.overheadHazard
                                  ? Icons.warning_rounded
                                  : obs.isHazard
                                      ? Icons.warning_amber_rounded
                                      : Icons.info_outline,
                          color: obs.isHazard
                              ? const Color(0xFFFF1744)
                              : const Color(0xFF00E5FF),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "${obs.detailedDescription} (${obs.clockPosition})",
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.volume_up,
                              size: 18, color: Color(0xFF00E5FF)),
                          tooltip: "Explain Object",
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _speakSingleObject(obs),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Distance: ${obs.distanceMeters.toStringAsFixed(1)}m | TTC: ${obs.ttcSeconds.toStringAsFixed(1)}s | ${(obs.confidence * 100).toInt()}% Conf • ${obs.formattedMotionBadge}",
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0E17).withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.psychology,
                                  size: 13, color: Color(0xFFFFD600)),
                              const SizedBox(width: 4),
                              const Text(
                                "OBJECT EXPLANATION & SAFE WALKING ADVICE:",
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFFFD600),
                                    letterSpacing: 0.8),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF76FF03).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: const Color(0xFF76FF03).withValues(alpha: 0.5)),
                                ),
                                child: Text(
                                  bypassText,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF76FF03),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            obs.comprehensiveExplanation,
                            style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                height: 1.3),
                          ),
                        ],
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
                  color: hasInternet
                      ? const Color(0xFF4338CA)
                      : const Color(0xFF065F46),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hasInternet
                      ? (isAnalyzing ? "ANALYZING..." : "GEMINI 2.0")
                      : "STANDALONE EDGE",
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
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
                  border: Border.all(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_city,
                        size: 12, color: Color(0xFFA5B4FC)),
                    const SizedBox(width: 4),
                    Text(
                      scene.environmentType,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFA5B4FC)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: scene.pathwayStatus.contains("Clear")
                      ? const Color(0xFF064E3B)
                      : const Color(0xFF7F1D1D),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      scene.pathwayStatus.contains("Clear")
                          ? Icons.check_circle_outline
                          : Icons.warning_amber_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      scene.pathwayStatus,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
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
                border: Border.all(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.assistant_direction,
                      size: 14, color: Color(0xFF60A5FA)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      scene.recommendedAction,
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF93C5FD),
                          fontWeight: FontWeight.w600),
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
              children: scene.detailedObjects
                  .map((item) => Chip(
                        backgroundColor: const Color(0xFF312E81),
                        label: Text(item,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white)),
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_isExplainingSituation || isAnalyzing)
                  ? null
                  : () => _explainSituation(),
              icon: (_isExplainingSituation || isAnalyzing)
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.record_voice_over, size: 16),
              label: Text((_isExplainingSituation || isAnalyzing)
                  ? "Explaining Situation..."
                  : "Explain Situation (Voice Narration)"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          )
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
          color: hasCriticalHazard
              ? const Color(0xFFFF1744).withValues(alpha: 0.5)
              : Colors.white10,
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
                  Text("AUDIO MUTEX GOVERNANCE",
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _isSpeaking
                      ? const Color(0xFF76FF03).withValues(alpha: 0.2)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _isSpeaking ? "SPEAKING" : "SILENT (STANDBY)",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color:
                        _isSpeaking ? const Color(0xFF76FF03) : Colors.white54,
                  ),
                ),
              )
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "\"$_activeSpeech\"",
            style: const TextStyle(
                fontSize: 13, fontStyle: FontStyle.italic, color: Colors.white),
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
                label:
                    const Text("Rescan Vision", style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _clearHazards,
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label:
                    const Text("Clear Hazards", style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: const Color(0xFF76FF03),
                  side: const BorderSide(color: Color(0xFF76FF03)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModeSwitcherTabBar() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          // Tab 0: Safety HUD
          Expanded(
            child: Semantics(
              button: true,
              selected: _activeNavTab == 0,
              label: "Safety Hazard HUD Mode",
              hint: "Double tap to switch to Safety Hazard HUD mode for real-time obstacle avoidance",
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('mode_tab_safety'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _switchChannel(0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _activeNavTab == 0
                          ? const Color(0xFF00E5FF).withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _activeNavTab == 0
                            ? const Color(0xFF00E5FF)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 14,
                          color: _activeNavTab == 0
                              ? const Color(0xFF00E5FF)
                              : Colors.white60,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            "Safety HUD",
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _activeNavTab == 0
                                  ? const Color(0xFF00E5FF)
                                  : Colors.white60,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Tab 1: Lost Item Sonar Radar
          Expanded(
            child: Semantics(
              button: true,
              selected: _activeNavTab == 1,
              label: "Lost Item Sonar Radar Mode",
              hint: "Double tap to switch to Lost Item Sonar Radar for voice-guided echo-location",
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('mode_tab_sonar'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _switchChannel(1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _activeNavTab == 1
                          ? const Color(0xFFFF0055).withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _activeNavTab == 1
                            ? const Color(0xFFFF0055)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.radar,
                          size: 14,
                          color: _activeNavTab == 1
                              ? const Color(0xFFFF0055)
                              : Colors.white60,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            "Item Sonar",
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _activeNavTab == 1
                                  ? const Color(0xFFFF0055)
                                  : Colors.white60,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBinauralEarconStatusCard() {
    final lastCue = _lastEarconCue ?? _earconService.lastCue;
    final lastElevation = lastCue?.zone ?? HazardElevationZone.torsoLevel;
    final lastAzimuth = lastCue?.panStereo ?? 0.0;

    Color zoneColor = const Color(0xFF00E5FF);
    String zoneTitle = "Torso Hazard (880 Hz Steady Tone)";
    if (lastElevation == HazardElevationZone.headLevel) {
      zoneColor = const Color(0xFFFF1744);
      zoneTitle = "Head-Level Overhang (2500 Hz Triple Pulse)";
    } else if (lastElevation == HazardElevationZone.dropOff) {
      zoneColor = const Color(0xFFFF9100);
      zoneTitle = "Drop-Off / Curb / Stair (220 Hz Low Sweep)";
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: zoneColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.headphones, size: 18, color: zoneColor),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        "3D SPATIAL BINAURAL EARCONS",
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: zoneColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  "Bone Conduction Ready",
                  style: TextStyle(
                      fontSize: 10,
                      color: zoneColor,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Zone: $zoneTitle • Azimuth: ${(lastAzimuth * 100).toInt()}% (${lastAzimuth < 0 ? 'Left' : (lastAzimuth > 0 ? 'Right' : 'Center')})",
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  _earconService.dispatchSpatialEarcon(
                    obstacle: DetectedObstacle(
                      label: "Low Tree Branch",
                      confidence: 0.92,
                      xMin: 0.1,
                      yMin: 0.05,
                      xMax: 0.4,
                      yMax: 0.35,
                      distanceMeters: 1.4,
                      ttcSeconds: 1.5,
                      priority: AudioPriority.level1Safety,
                      clockPosition: "11 o'clock",
                    ),
                    estimatedElevationMeters: 1.8,
                  );
                },
                icon: const Icon(Icons.arrow_upward, size: 13),
                label: const Text("Test Head-Level (Left)",
                    style: TextStyle(fontSize: 10)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: const Color(0xFFFF1744),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  _earconService.dispatchSpatialEarcon(
                    obstacle: DetectedObstacle(
                      label: "Downward Curb Step",
                      confidence: 0.95,
                      xMin: 0.6,
                      yMin: 0.7,
                      xMax: 0.9,
                      yMax: 0.95,
                      distanceMeters: 1.1,
                      ttcSeconds: 1.2,
                      priority: AudioPriority.level1Safety,
                      clockPosition: "2 o'clock",
                    ),
                    estimatedElevationMeters: 0.2,
                  );
                },
                icon: const Icon(Icons.arrow_downward, size: 13),
                label: const Text("Test Drop-Off (Right)",
                    style: TextStyle(fontSize: 10)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: const Color(0xFFFF9100),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  _earconService.dispatchSpatialEarcon(
                    obstacle: DetectedObstacle(
                      label: "Bollard Post",
                      confidence: 0.91,
                      xMin: 0.4,
                      yMin: 0.3,
                      xMax: 0.6,
                      yMax: 0.7,
                      distanceMeters: 2.2,
                      ttcSeconds: 2.0,
                      priority: AudioPriority.level1Safety,
                      clockPosition: "12 o'clock",
                    ),
                    estimatedElevationMeters: 1.0,
                  );
                },
                icon: const Icon(Icons.center_focus_strong, size: 13),
                label: const Text("Test Torso (Center)",
                    style: TextStyle(fontSize: 10)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: const Color(0xFF00E5FF),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleTactileTouch(Offset localPos, double boxWidth, double boxHeight) {
    if (boxWidth <= 0 || boxHeight <= 0) return;
    final normX = (localPos.dx / boxWidth).clamp(0.0, 1.0);
    final normY = (localPos.dy / boxHeight).clamp(0.0, 1.0);
    final result = _tactileMapService.inspectScreenPoint(normX, normY);
    setState(() {
      _lastTactileTouchResult = result;
    });
    if (result.shouldVibrate) {
      HapticFeedback.selectionClick();
    }
  }

  Widget _buildTactileRoomMapCard() {
    final result = _lastTactileTouchResult;
    final cellName = result?.label ?? "Drag finger on grid to feel obstacles";
    final cellDist = result != null ? "${result.distanceMeters.toStringAsFixed(1)}m ahead" : "Touch & Drag to explore";

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.touch_app, color: Color(0xFF00E5FF), size: 18),
              SizedBox(width: 8),
              Text(
                "TACTILE SCREEN MAP EXPLORER",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: Color(0xFF00E5FF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            "Feel your surroundings without walking. Drag finger across the surface below.",
            style: TextStyle(fontSize: 11, color: Colors.white70),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              const height = 140.0;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanDown: (d) => _handleTactileTouch(d.localPosition, width, height),
                onPanUpdate: (d) => _handleTactileTouch(d.localPosition, width, height),
                child: Container(
                  height: height,
                  width: width,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0E17),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Stack(
                    children: [
                      CustomPaint(
                        size: Size(width, height),
                        painter: _TactileGridPainter(
                          touchResult: result,
                          obstacles: _activeObstacles,
                        ),
                      ),
                      Center(
                        child: Text(
                          result == null ? "TOUCH & DRAG TO FEEL ROOM" : cellName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: result?.shouldVibrate == true
                                ? const Color(0xFFFF1744)
                                : const Color(0xFF76FF03),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  "Point: $cellName",
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                cellDist,
                style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF00E5FF),
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencySosCard() {
    final sos = _lastEmergencySosState;
    final isCountdown =
        sos.status == FallDetectionStatus.fallDetectedCountdown;
    final isLanyard = _wristHapticService.isChestLanyardModeEnabled;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCountdown
              ? const Color(0xFFFF1744)
              : const Color(0xFFFF9100).withValues(alpha: 0.4),
          width: isCountdown ? 2.0 : 1.0,
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
                  children: [
                    Icon(
                      Icons.health_and_safety,
                      color: isCountdown
                          ? const Color(0xFFFF1744)
                          : const Color(0xFFFF9100),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        "EMERGENCY FALL & SOS SENTINEL",
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                          color: isCountdown
                              ? const Color(0xFFFF1744)
                              : const Color(0xFFFF9100),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isCountdown
                      ? const Color(0xFFFF1744).withValues(alpha: 0.2)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isCountdown
                      ? "FALL DETECTED (${sos.countdownRemainingSeconds}s)"
                      : "MONITORING",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color:
                        isCountdown ? const Color(0xFFFF1744) : Colors.white60,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            sos.statusMessage,
            style: TextStyle(
              fontSize: 11,
              color: isCountdown ? const Color(0xFFFF1744) : Colors.white70,
              fontWeight: isCountdown ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (isCountdown)
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      _emergencySosService.cancelEmergency();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF76FF03),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text("I AM OKAY (CANCEL SOS)", style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                )
              else ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _emergencySosService.triggerManualSos();
                    },
                    icon: const Icon(Icons.emergency, size: 14),
                    label: const Text("Test SOS Alert (30s)", style: TextStyle(fontSize: 10)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E293B),
                      foregroundColor: const Color(0xFFFF1744),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _wristHapticService.setChestLanyardMode(!isLanyard, currentPitchDeg: _pitchDeg);
                      });
                    },
                    icon: Icon(isLanyard ? Icons.check_circle : Icons.accessibility_new, size: 14),
                    label: Text(
                      isLanyard ? "Chest Lanyard ON" : "Hands-Free Lanyard",
                      style: const TextStyle(fontSize: 10),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E293B),
                      foregroundColor: isLanyard ? const Color(0xFF76FF03) : Colors.white70,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildVoiceQACard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.record_voice_over_outlined,
                      size: 18, color: Color(0xFF00E5FF)),
                  SizedBox(width: 8),
                  Text(
                    "CONVERSATIONAL VOICE AI",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Color(0xFF00E5FF),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _voiceQaService.isOnline ? "Gemini 2.0 Flash" : "Edge Offline",
                  style: const TextStyle(fontSize: 10, color: Color(0xFF00E5FF)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_lastVoiceExchange != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E17),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Q: \"${_lastVoiceExchange!.question}\"",
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00E5FF),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _lastVoiceExchange!.answer,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${_lastVoiceExchange!.isFromCloud ? "Cloud Vision" : "Edge Synthesizer"} (${_lastVoiceExchange!.latencyMs}ms)",
                    style: const TextStyle(fontSize: 9, color: Colors.white54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (_lastOfflineCaption != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E17),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF76FF03).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "OFFLINE SPATIAL CAPTION (${_lastOfflineCaption!.environmentEstimate})",
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF76FF03),
                        ),
                      ),
                      Text(
                        "${_lastOfflineCaption!.latencyMs}ms",
                        style: const TextStyle(fontSize: 9, color: Colors.white54),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _lastOfflineCaption!.spokenCaption,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          const Text(
            "Quick Visual Queries (Tap or Voice):",
            style: TextStyle(fontSize: 11, color: Colors.white60),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildVoiceQueryChip("Explain all detected objects"),
              _buildVoiceQueryChip("Optimal route for safe walking"),
              _buildVoiceQueryChip("What is in front of me?"),
              _buildVoiceQueryChip("Find empty chair"),
              _buildVoiceQueryChip("Where is the doorway?"),
              _buildVoiceQueryChip("Is anyone nearby?"),
              ActionChip(
                backgroundColor: const Color(0xFF1E293B),
                side: const BorderSide(color: Color(0xFF76FF03)),
                avatar: const Icon(Icons.spatial_audio_off, size: 14, color: Color(0xFF76FF03)),
                label: const Text(
                  "Offline Scene Caption",
                  style: TextStyle(fontSize: 11, color: Color(0xFF76FF03)),
                ),
                onPressed: () {
                  _captioningService.generateCaption(
                    obstacles: _activeObstacles,
                    phonePitchDeg: _pitchDeg,
                    phoneRollDeg: _rollDeg,
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceQueryChip(String query) {
    return ActionChip(
      backgroundColor: const Color(0xFF1E293B),
      side: const BorderSide(color: Colors.white12),
      label: Text(
        query,
        style: const TextStyle(fontSize: 11, color: Color(0xFF00E5FF)),
      ),
      onPressed: () => _triggerQuickVoiceQA(query),
    );
  }

  void _triggerQuickVoiceQA(String question) {
    _voiceQaService.askQuestion(
      question: question,
      activeObstacles: _activeObstacles,
      phonePitchDeg: _pitchDeg,
    );
  }

  Widget _buildLostItemSonarChannel() {
    final finder = _lastObjectFinderState;
    final isSearching = _objectFinderService.isSearching;

    return Container(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF131B2A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: finder.isFound
                    ? const Color(0xFF76FF03)
                    : const Color(0xFFFF0055).withValues(alpha: 0.5),
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
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF0055).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.radar,
                              color: Color(0xFFFF0055), size: 22),
                        ),
                        const SizedBox(width: 10),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "LOST ITEM SONAR RADAR",
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                                color: Color(0xFFFF0055),
                              ),
                            ),
                            Text(
                              "Voice & Acoustic Echo-Location",
                              style: TextStyle(fontSize: 10, color: Colors.white60),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSearching
                            ? (finder.isFound
                                ? const Color(0xFF76FF03).withValues(alpha: 0.2)
                                : const Color(0xFFFF0055).withValues(alpha: 0.2))
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSearching
                              ? (finder.isFound
                                  ? const Color(0xFF76FF03)
                                  : const Color(0xFFFF0055))
                              : Colors.white24,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSearching ? Icons.sensors : Icons.sensors_off,
                            size: 12,
                            color: isSearching
                                ? (finder.isFound
                                    ? const Color(0xFF76FF03)
                                    : const Color(0xFFFF0055))
                                : Colors.white60,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isSearching
                                ? (finder.isFound ? "LOCKED ON" : "SEARCHING")
                                : "RADAR IDLE",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isSearching
                                  ? (finder.isFound
                                      ? const Color(0xFF76FF03)
                                      : const Color(0xFFFF0055))
                                  : Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 100% Voice-Driven Accessible Command for Blind People
                Semantics(
                  button: true,
                  label: "Voice Item Finder: Double-tap to speak the item you want to locate",
                  hint: "Speak item name, like keys, phone, charger, or cane. No typing required.",
                  child: InkWell(
                    onTap: _startVoiceItemSearch,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF0055), Color(0xFFC2003F)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF0055).withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.mic, size: 28, color: Colors.white),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "🎙️ TAP TO SPEAK ITEM",
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.8,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  "Searching for: ${_objectFinderService.activeTargetLabel.toUpperCase()}",
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  "100% Voice-Guided for Blind Users • Tap anywhere to change item",
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Live Camera Sonar Viewfinder with Acoustic Radar Overlay
          _buildSonarCameraViewfinder(finder),
          const SizedBox(height: 14),

          // Sonar Guidance & Acoustic Echo Telemetry Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF131B2A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: finder.isFound
                    ? const Color(0xFF76FF03).withValues(alpha: 0.6)
                    : const Color(0xFF00E5FF).withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      finder.isFound ? Icons.check_circle : Icons.hearing,
                      color: finder.isFound
                          ? const Color(0xFF76FF03)
                          : const Color(0xFF00E5FF),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        finder.guidanceCue,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: finder.isFound
                              ? const Color(0xFF76FF03)
                              : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                if (finder.isFound) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSonarTelemetryPill(
                        icon: Icons.speed,
                        label: "PING RATE",
                        value: "${finder.sonarPingIntervalMs}ms",
                        color: const Color(0xFF76FF03),
                      ),
                      _buildSonarTelemetryPill(
                        icon: Icons.spatial_audio_off,
                        label: "STEREO PAN",
                        value: finder.stereoPan < -0.2
                            ? "LEFT ${(finder.stereoPan.abs() * 100).toInt()}%"
                            : finder.stereoPan > 0.2
                                ? "RIGHT ${(finder.stereoPan * 100).toInt()}%"
                                : "CENTER",
                        color: const Color(0xFF00E5FF),
                      ),
                      _buildSonarTelemetryPill(
                        icon: Icons.straighten,
                        label: "DISTANCE",
                        value: "${finder.distanceMeters.toStringAsFixed(1)}m",
                        color: const Color(0xFFFFD600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: finder.alignmentScore,
                      minHeight: 6,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        finder.distanceMeters < 0.7
                            ? const Color(0xFF76FF03)
                            : const Color(0xFF00E5FF),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (isSearching) {
                            _objectFinderService.stopSearch();
                            _sonarPingTimer?.cancel();
                          } else {
                            _startSonarSearchFor(
                                _objectFinderService.activeTargetLabel);
                          }
                          setState(() {});
                        },
                        icon: Icon(
                          isSearching ? Icons.stop : Icons.play_arrow,
                          size: 16,
                        ),
                        label: Text(
                          isSearching
                              ? "STOP SONAR RADAR"
                              : "START SONAR RADAR",
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isSearching
                              ? const Color(0xFFFF1744)
                              : const Color(0xFF76FF03),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        _startSonarSearchFor("keys");
                        _objectFinderService.updateVisionCandidates([
                          DetectedObstacle(
                            label: "keys",
                            confidence: 0.96,
                            xMin: 0.45,
                            yMin: 0.35,
                            xMax: 0.65,
                            yMax: 0.55,
                            distanceMeters: 0.9,
                            ttcSeconds: 3.0,
                            priority: AudioPriority.level2Navigation,
                            clockPosition: "12 o'clock",
                          ),
                        ]);
                        setState(() {});
                      },
                      icon: const Icon(Icons.vpn_key, size: 14),
                      label: const Text("Simulate Keys",
                          style: TextStyle(fontSize: 10)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E293B),
                        foregroundColor: const Color(0xFF00E5FF),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSonarCameraViewfinder(ObjectFinderTarget finder) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const boxHeight = 280.0;

        return Container(
          height: boxHeight,
          decoration: BoxDecoration(
            color: const Color(0xFF0E1420),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: finder.isFound
                  ? const Color(0xFF76FF03)
                  : const Color(0xFFFF0055).withValues(alpha: 0.6),
              width: 1.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Live Camera Stream
                if (_isCameraInitialized && _cameraController != null)
                  CameraPreview(_cameraController!)
                else
                  Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.radar,
                              size: 44,
                              color: Colors.white.withValues(alpha: 0.2)),
                          const SizedBox(height: 8),
                          const Text(
                            "Starting Live Sonar Camera Stream...",
                            style:
                                TextStyle(fontSize: 12, color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Sonar Radar Custom Painter (Concentric rings + Target blip)
                CustomPaint(
                  painter: _SonarRadarPainter(target: finder),
                ),

                // Top Header Overlay
                Positioned(
                  top: 10,
                  left: 12,
                  right: 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: finder.isFound
                                ? const Color(0xFF76FF03)
                                : const Color(0xFFFF0055),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: finder.isFound
                                    ? const Color(0xFF76FF03)
                                    : const Color(0xFFFF0055),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              finder.isFound
                                  ? "TARGET: ${_objectFinderService.activeTargetLabel.toUpperCase()} (${finder.distanceMeters.toStringAsFixed(1)}m)"
                                  : "SEARCHING: ${_objectFinderService.activeTargetLabel.toUpperCase()}",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: finder.isFound
                                    ? const Color(0xFF76FF03)
                                    : const Color(0xFFFF0055),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          "ACOUSTIC PING: ${finder.sonarPingIntervalMs}ms",
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSonarTelemetryPill({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E17),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 3),
              Text(label,
                  style: TextStyle(
                      fontSize: 9, color: color, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _TactileGridPainter extends CustomPainter {
  final TactileTouchResult? touchResult;
  final List<DetectedObstacle> obstacles;

  _TactileGridPainter({this.touchResult, required this.obstacles});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw 3x3 touch grid dividing lines
    final cellW = size.width / 3.0;
    final cellH = size.height / 3.0;
    for (int i = 1; i < 3; i++) {
      canvas.drawLine(
          Offset(cellW * i, 0), Offset(cellW * i, size.height), gridPaint);
      canvas.drawLine(
          Offset(0, cellH * i), Offset(size.width, cellH * i), gridPaint);
    }

    // Draw detected obstacle bounding boxes
    final obsFillPaint = Paint()
      ..color = const Color(0xFFFF1744).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    final obsStrokePaint = Paint()
      ..color = const Color(0xFFFF1744)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final obs in obstacles) {
      final rect = Rect.fromLTRB(
        obs.xMin * size.width,
        obs.yMin * size.height,
        obs.xMax * size.width,
        obs.yMax * size.height,
      );
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)), obsFillPaint);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          obsStrokePaint);
    }

    // Draw user touch target circle
    if (touchResult != null) {
      final touchPos = Offset(
        touchResult!.normalizedX * size.width,
        touchResult!.normalizedY * size.height,
      );
      final touchPaint = Paint()
        ..color = touchResult!.shouldVibrate
            ? const Color(0xFFFF1744)
            : const Color(0xFF76FF03)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(touchPos, 14, touchPaint);

      final touchBorder = Paint()
        ..color = Colors.white
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(touchPos, 16, touchBorder);
    }
  }

  @override
  bool shouldRepaint(covariant _TactileGridPainter oldDelegate) {
    return oldDelegate.touchResult != touchResult ||
        oldDelegate.obstacles != obstacles;
  }
}

class _SonarRadarPainter extends CustomPainter {
  final ObjectFinderTarget target;

  _SonarRadarPainter({required this.target});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) * 0.44;

    final ringPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw 3 concentric sonar radar rings
    for (int i = 1; i <= 3; i++) {
      final r = maxRadius * (i / 3.0);
      canvas.drawCircle(center, r, ringPaint);
    }

    // Crosshair axes
    canvas.drawLine(
        Offset(center.dx, center.dy - maxRadius),
        Offset(center.dx, center.dy + maxRadius),
        ringPaint);
    canvas.drawLine(
        Offset(center.dx - maxRadius, center.dy),
        Offset(center.dx + maxRadius, center.dy),
        ringPaint);

    // If target found, draw targeted reticle and connection line
    if (target.isFound) {
      final targetX = center.dx + (target.stereoPan * maxRadius * 0.75);
      final distRatio = (target.distanceMeters / 3.0).clamp(0.15, 0.95);
      final targetY = center.dy - (maxRadius * (1.0 - distRatio));

      final targetPos = Offset(targetX, targetY);

      // Blip paint
      final blipColor = target.distanceMeters < 0.7
          ? const Color(0xFF76FF03)
          : const Color(0xFFFF0055);

      final blipPaint = Paint()
        ..color = blipColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(targetPos, 8.0, blipPaint);

      final glowPaint = Paint()
        ..color = blipColor.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0;
      canvas.drawCircle(targetPos, 14.0, glowPaint);

      // Line from center to target blip
      final linePaint = Paint()
        ..color = blipColor.withValues(alpha: 0.6)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(center, targetPos, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SonarRadarPainter oldDelegate) {
    return oldDelegate.target != target;
  }
}


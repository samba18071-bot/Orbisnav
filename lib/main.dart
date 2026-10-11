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
import 'services/barcode_product_service.dart';
import 'services/currency_recognition_service.dart';
import 'services/document_framing_guide_service.dart';
import 'services/document_batch_ocr_reader_service.dart';
import 'services/conversational_voice_qa_service.dart';
import 'services/offline_scene_captioning_service.dart';
import 'services/pedestrian_navigation_service.dart';
import 'services/indoor_self_mapping_service.dart';
import 'services/spatial_binaural_earcon_service.dart';
import 'services/trusted_angels_call_service.dart';
import 'services/transit_sentinel_service.dart';
import 'services/object_finder_sonar_service.dart';
import 'services/tactile_haptic_map_service.dart';
import 'services/emergency_sos_sentinel_service.dart';
import 'services/wearable_wrist_haptic_service.dart';
import 'services/global_standards_service.dart';
import 'services/smart_cane_ble_service.dart';
import 'services/smart_glasses_bridge_service.dart';
import 'services/color_and_light_perception_service.dart';
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
  OptimalPathRecommendation? _optimalPath;
  Timer? _visionStreamTimer;

  // Multimodal AI Scene Comprehension State
  SceneAnalysisResult _latestSceneAnalysis = SceneAnalysisResult.empty();
  StreamSubscription<SceneAnalysisResult>? _sceneAnalysisSubscription;
  bool _isExplainingSituation = false;

  // Destination & Landmark Nameboard Navigation (4km Radius Discovery)
  final NameboardNavigationService _navService = NameboardNavigationService();
  StreamSubscription<NavigationStatusState>? _navSubscription;
  NavigationStatusState? _navState;
  final TextEditingController _destinationInputController =
      TextEditingController();

  // Day 1 & Day 2: Daily Living Suite (Barcode Scanner & Offline Currency Recognizer)
  final BarcodeProductService _barcodeService = BarcodeProductService();
  final CurrencyRecognitionService _currencyService =
      CurrencyRecognitionService();
  StreamSubscription<ScannedProductInfo>? _productSubscription;
  StreamSubscription<CurrencyScanResult>? _currencySubscription;
  ScannedProductInfo? _lastScannedProduct;
  CurrencyScanResult? _lastCurrencyResult;

  // Day 3 & Day 4: Document Framing Guidance & Batch OCR Reader
  final DocumentFramingGuideService _framingGuideService =
      DocumentFramingGuideService();
  final DocumentBatchOcrReaderService _documentReaderService =
      DocumentBatchOcrReaderService();
  StreamSubscription<FramingAnalysisResult>? _framingSubscription;
  StreamSubscription<DocumentReadingSession>? _readerSubscription;
  FramingAnalysisResult? _lastFramingResult;
  DocumentReadingSession _currentReadingSession = DocumentReadingSession.empty();

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

  // Day 11 & Day 12: Pedestrian Turn-by-Turn Navigation & Crosswalk / Traffic Light Vision
  final PedestrianNavigationService _pedestrianNavService =
      PedestrianNavigationService();
  StreamSubscription<PedestrianNavigationState>? _pedestrianNavSubscription;
  PedestrianNavigationState? _lastPedestrianState;

  // Day 13, 14 & 15: Indoor Self-Mapping (A* Graph, Levenshtein Plaque Snapping & PDR)
  final IndoorSelfMappingService _indoorMappingService =
      IndoorSelfMappingService();
  StreamSubscription<IndoorNavigationState>? _indoorMappingSubscription;
  IndoorNavigationState? _lastIndoorState;
  final TextEditingController _indoorNodeNameController =
      TextEditingController();
  final TextEditingController _indoorOcrInputController =
      TextEditingController();

  // Day 16: Spatial Binaural 3D Elevation Earcon Service (Head-Level, Torso, Drop-Off)
  final SpatialBinauralEarconService _earconService =
      SpatialBinauralEarconService();
  StreamSubscription<SpatialEarconCue>? _earconSubscription;
  SpatialEarconCue? _lastEarconCue;

  // Day 17: 1-Tap Trusted Angels P2P Caregiver Video Calling
  final TrustedAngelsCallService _angelsCallService =
      TrustedAngelsCallService();
  StreamSubscription<TrustedAngelCallSession>? _angelsCallSubscription;
  TrustedAngelCallSession _lastCallState = TrustedAngelCallSession.idle();

  // World-Class Assistive Add-Ons
  final TransitSentinelService _transitService = TransitSentinelService();
  StreamSubscription<TransitAlertState>? _transitSubscription;
  TransitAlertState _lastTransitAlert = TransitAlertState.idle();

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

  final ColorAndLightPerceptionService _colorAndLightService =
      ColorAndLightPerceptionService();

  int _activeNavTab = 0; // 0: Hazard HUD, 1: Navigation, 2: Smart Reader (Seeing AI), 3: Lost Item Sonar
  bool _isReaderScanning = false;
  String _readerScanMode = 'all';
  String _lastReaderScannedSummary = "";
  final TextEditingController _manualBarcodeInputController =
      TextEditingController();

  // Seeing AI Continuous Auto-Scanning state (Channel 3 - No Tapping Needed)
  Timer? _readerAutoScanTimer;
  bool _isAutoScanningReader = false;
  String _lastAutoSpokenText = '';
  DateTime? _lastAutoSpokenTextTime;
  String _lastAutoSpokenBarcode = '';
  DateTime? _lastAutoSpokenBarcodeTime;
  String _lastAutoSpokenCurrency = '';
  DateTime? _lastAutoSpokenCurrencyTime;
  String _lastAutoSpokenPerson = '';
  DateTime? _lastAutoSpokenPersonTime;
  String _lastAutoSpokenScene = '';
  DateTime? _lastAutoSpokenSceneTime;
  String _lastAutoSpokenColor = '';
  DateTime? _lastAutoSpokenColorTime;
  String _lastAutoSpokenLight = '';
  DateTime? _lastAutoSpokenLightTime;
  int _currentLightLevelPercent = 75;
  String _currentColorName = "Neutral";

  // Lost Item Sonar Radar state (Channel 4 - Voice & Object Detection)
  Timer? _itemSonarStreamTimer;
  Timer? _sonarPingTimer;
  bool _isProcessingSonarFrame = false;
  final TextEditingController _voiceSonarItemController =
      TextEditingController();
  DateTime? _lastSpokenGuidanceCueTime;

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
        _transitService.evaluatePlatformEdge(processedObstacles,
            phonePitchDeg: _pitchDeg);

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

    // 4. Listen to Destination & 4km GPS Navigation Status
    _navSubscription = _navService.statusStream.listen((state) {
      if (mounted) {
        setState(() {
          _navState = state;
        });
      }
    });

    // 4b. Listen to Daily Living Barcode & Currency Streams
    _productSubscription = _barcodeService.productStream.listen((prod) {
      if (mounted) {
        setState(() {
          _lastScannedProduct = prod;
        });
      }
    });

    _currencySubscription = _currencyService.resultStream.listen((curr) {
      if (mounted) {
        setState(() {
          _lastCurrencyResult = curr;
        });
      }
    });

    // 4c. Listen to Day 3 & 4 Document Framing & Reader Streams
    _framingSubscription = _framingGuideService.guidanceStream.listen((res) {
      if (mounted) {
        setState(() {
          _lastFramingResult = res;
        });
      }
    });

    _readerSubscription = _documentReaderService.sessionStream.listen((session) {
      if (mounted) {
        setState(() {
          _currentReadingSession = session;
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

    // 4f. Listen to Days 11-17 Navigation, Indoor Mapping, Earcon & Angels Streams
    _pedestrianNavSubscription =
        _pedestrianNavService.navStream.listen((state) {
      if (mounted) {
        setState(() {
          _lastPedestrianState = state;
        });
      }
    });

    _indoorMappingSubscription =
        _indoorMappingService.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _lastIndoorState = state;
        });
      }
    });

    _earconSubscription = _earconService.cueStream.listen((cue) {
      if (mounted) {
        setState(() {
          _lastEarconCue = cue;
        });
      }
    });

    _angelsCallSubscription = _angelsCallService.sessionStream.listen((call) {
      if (mounted) {
        setState(() {
          _lastCallState = call;
        });
      }
    });

    _transitSubscription = _transitService.alertStream.listen((alert) {
      if (mounted) {
        setState(() {
          _lastTransitAlert = alert;
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
    _startVisionStream();

    // Initial voice greeting
    _audioMutex.speak(
      text:
          "AI Eyes obstacle and motion detection activated. Standalone offline mode ready.",
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
    _driftMeters += 0.025;
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
    _navSubscription?.cancel();
    _productSubscription?.cancel();
    _currencySubscription?.cancel();
    _framingSubscription?.cancel();
    _readerSubscription?.cancel();
    _voiceQaSubscription?.cancel();
    _captionSubscription?.cancel();
    _pedestrianNavSubscription?.cancel();
    _indoorMappingSubscription?.cancel();
    _earconSubscription?.cancel();
    _angelsCallSubscription?.cancel();
    _transitSubscription?.cancel();
    _objectFinderSubscription?.cancel();
    _emergencySosSubscription?.cancel();
    _wristHapticSubscription?.cancel();
    _smartCaneSubscription?.cancel();
    _smartGlassesSubscription?.cancel();
    _barcodeService.dispose();
    _currencyService.dispose();
    _framingGuideService.dispose();
    _documentReaderService.dispose();
    _voiceQaService.dispose();
    _captioningService.dispose();
    _pedestrianNavService.dispose();
    _indoorMappingService.dispose();
    _earconService.dispose();
    _angelsCallService.dispose();
    _transitService.dispose();
    _objectFinderService.dispose();
    _tactileMapService.dispose();
    _emergencySosService.dispose();
    _wristHapticService.dispose();
    _smartCaneService.dispose();
    _smartGlassesService.dispose();
    _speechSubscription?.cancel();
    _readerAutoScanTimer?.cancel();
    _itemSonarStreamTimer?.cancel();
    _sonarPingTimer?.cancel();
    _destinationInputController.dispose();
    _manualBarcodeInputController.dispose();
    _voiceQuestionInputController.dispose();
    _voiceSonarItemController.dispose();
    _indoorNodeNameController.dispose();
    _indoorOcrInputController.dispose();
    _navService.stopNavigation();
    _cameraController?.dispose();
    _audioMutex.dispose();
    super.dispose();
  }

  void _switchChannel(int newChannel) {
    if (newChannel == _activeNavTab) return;
    final oldChannel = _activeNavTab;

    // 1. Immediately stop previous channel tasks & audio speech
    _audioMutex.stopAll();

    if (oldChannel == 0) {
      // Leaving Safety HUD: Stop active vision loop and edge detector immediately
      _visionStreamTimer?.cancel();
      _visionStreamTimer = null;
      _onDeviceDetector.setEnabled(false);
    } else if (oldChannel == 1) {
      // Leaving Navigation: Halt active turn-by-turn audio prompts
    } else if (oldChannel == 2) {
      // Leaving Reader / Seeing AI: Cancel ongoing scanner tasks, auto scan loop and pause document audio reader
      _isReaderScanning = false;
      _isAutoScanningReader = false;
      _readerAutoScanTimer?.cancel();
      _readerAutoScanTimer = null;
      _documentReaderService.pauseReading();
    } else if (oldChannel == 3) {
      // Leaving Lost Item Sonar: Stop sonar audio/radar loop and stream
      _itemSonarStreamTimer?.cancel();
      _itemSonarStreamTimer = null;
      _sonarPingTimer?.cancel();
      _sonarPingTimer = null;
      _objectFinderService.stopSearch();
    }

    setState(() {
      _activeNavTab = newChannel;
    });

    // 2. Start/resume tasks for newly activated channel
    if (newChannel == 0) {
      _onDeviceDetector.setEnabled(true);
      _startVisionStream();
    } else if (newChannel == 2) {
      // Channel 3: Auto-start Seeing AI continuous scanner loop (no tapping needed!)
      _startReaderAutoScanStream();
    } else if (newChannel == 3) {
      // Channel 4: Auto-start Lost Item Sonar stream with immediate active search
      _onDeviceDetector.setEnabled(true);
      if (!_objectFinderService.isSearching) {
        _objectFinderService.startSearch(_objectFinderService.activeTargetLabel);
      }
      _startItemSonarStream();
    }

    final channelNames = [
      "Safety Hazard HUD",
      "Pedestrian and Indoor Navigation",
      "Smart Reader Seeing AI",
      "Lost Item Sonar Radar",
    ];

    HapticFeedback.heavyImpact();
    _audioMutex.speak(
      text: "Switched to ${channelNames[newChannel]} Mode.",
      priority: AudioPriority.level2Navigation,
      force: true,
      haptic: true,
    );
  }

  void _startReaderAutoScanStream() {
    _readerAutoScanTimer?.cancel();
    _readerAutoScanTimer =
        Timer.periodic(const Duration(milliseconds: 1600), (_) {
      if (_activeNavTab == 2 &&
          _isCameraInitialized &&
          !_isReaderScanning &&
          !_isAutoScanningReader &&
          _cameraController != null &&
          _cameraController!.value.isInitialized &&
          !_cameraController!.value.isTakingPicture) {
        _autoProcessSeeingAiFrame();
      }
    });
  }

  bool _isNavigationalObstacleSentence(String text) {
    final lower = text.toLowerCase().trim();
    if (lower.isEmpty) return true;
    return lower.contains("path directly ahead") ||
        lower.contains("safe to proceed") ||
        lower.contains("observing path ahead") ||
        lower.contains("clear of obstacles") ||
        lower.contains("no immediate collision hazards") ||
        lower.contains("path obstructed") ||
        lower.contains("path narrowed") ||
        lower.contains("directly ahead:") ||
        lower.contains("obstacle directly ahead") ||
        lower.contains("environment assessment") ||
        lower.contains("maintain forward trajectory") ||
        lower.contains("clear path ahead") ||
        lower.contains("no obstacles") ||
        lower.contains("open path / indoor space") ||
        lower.contains("indoor living / office area") ||
        lower.contains("workstation / office desk") ||
        lower.contains("continue forward with normal pace");
  }

  String _estimateDominantColor(Uint8List bytes) {
    return _colorAndLightService.estimateDominantColor(bytes);
  }

  int _estimateLightLevel(Uint8List bytes) {
    return _colorAndLightService.estimateLightLevel(bytes);
  }

  Future<void> _autoProcessSeeingAiFrame() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _cameraController!.value.isTakingPicture ||
        _isAutoScanningReader ||
        _activeNavTab != 2) {
      return;
    }

    _isAutoScanningReader = true;
    try {
      final img = await _cameraController!.takePicture();
      final bytes = await img.readAsBytes();
      try {
        final f = File(img.path);
        if (await f.exists()) await f.delete();
      } catch (_) {}

      // 1. Run real-time on-device neural detector
      await _onDeviceDetector.processFrameBytes(
        bytes,
        devicePitchDeg: _pitchDeg,
      );

      final now = DateTime.now();

      // -------------------------------------------------------------
      // Microsoft Seeing AI: Person Channel
      // -------------------------------------------------------------
      if (_readerScanMode == 'person' || _readerScanMode == 'all') {
        final people = _activeObstacles.where((o) => o.label.toLowerCase() == 'person').toList();
        if (people.isNotEmpty) {
          final nearest = people.reduce((a, b) => a.distanceMeters < b.distanceMeters ? a : b);
          final count = people.length;
          final personMsg = "$count ${count == 1 ? 'person' : 'people'} in view. Nearest is ${nearest.distanceMeters.toStringAsFixed(1)}m at ${nearest.clockPosition}.";
          final isNewPerson = personMsg != _lastAutoSpokenPerson ||
              _lastAutoSpokenPersonTime == null ||
              now.difference(_lastAutoSpokenPersonTime!).inSeconds >= 5;
          if (isNewPerson) {
            _lastAutoSpokenPerson = personMsg;
            _lastAutoSpokenPersonTime = now;
            HapticFeedback.mediumImpact();
            _audioMutex.speak(
              text: personMsg,
              priority: AudioPriority.level2Navigation,
            );
            if (mounted) {
              setState(() {
                _lastReaderScannedSummary = personMsg;
              });
            }
            if (_readerScanMode == 'person') return;
          }
        } else if (_readerScanMode == 'person') {
          const personNoneMsg = "No person detected. Pan camera slowly across room.";
          final isNew = _lastAutoSpokenPersonTime == null ||
              now.difference(_lastAutoSpokenPersonTime!).inSeconds >= 8;
          if (isNew) {
            _lastAutoSpokenPersonTime = now;
            _audioMutex.speak(text: personNoneMsg, priority: AudioPriority.level3Context);
            if (mounted) {
              setState(() => _lastReaderScannedSummary = personNoneMsg);
            }
          }
          return;
        }
      }

      // -------------------------------------------------------------
      // Microsoft Seeing AI: Color Channel
      // -------------------------------------------------------------
      if (_readerScanMode == 'color') {
        final colorName = _estimateDominantColor(bytes);
        _currentColorName = colorName;
        final colorMsg = "Color: $colorName";
        final isNewColor = colorMsg != _lastAutoSpokenColor ||
            _lastAutoSpokenColorTime == null ||
            now.difference(_lastAutoSpokenColorTime!).inSeconds >= 4;
        if (isNewColor) {
          _lastAutoSpokenColor = colorMsg;
          _lastAutoSpokenColorTime = now;
          HapticFeedback.selectionClick();
          _audioMutex.speak(text: colorMsg, priority: AudioPriority.level2Navigation);
          if (mounted) {
            setState(() {
              _lastReaderScannedSummary = colorMsg;
            });
          }
        }
        return;
      }

      // -------------------------------------------------------------
      // Microsoft Seeing AI: Light Channel
      // -------------------------------------------------------------
      if (_readerScanMode == 'light') {
        final lumaPercent = _estimateLightLevel(bytes);
        _currentLightLevelPercent = lumaPercent;
        String desc = "Good indoor illumination";
        if (lumaPercent > 80) {
          desc = "Very bright direct light";
        } else if (lumaPercent < 25) {
          desc = "Dark or low light";
        }
        final lightMsg = "Light level: $lumaPercent%, $desc.";
        final isNewLight = lightMsg != _lastAutoSpokenLight ||
            _lastAutoSpokenLightTime == null ||
            now.difference(_lastAutoSpokenLightTime!).inSeconds >= 4;
        if (isNewLight) {
          _lastAutoSpokenLight = lightMsg;
          _lastAutoSpokenLightTime = now;
          HapticFeedback.selectionClick();
          SystemSound.play(SystemSoundType.click);
          _audioMutex.speak(text: lightMsg, priority: AudioPriority.level2Navigation);
          if (mounted) {
            setState(() {
              _lastReaderScannedSummary = lightMsg;
            });
          }
        }
        return;
      }

      // -------------------------------------------------------------
      // Microsoft Seeing AI: Scene Channel
      // -------------------------------------------------------------
      if (_readerScanMode == 'scene') {
        final caption = _captioningService.generateCaption(
          obstacles: _activeObstacles,
          phonePitchDeg: _pitchDeg,
          phoneRollDeg: _rollDeg,
        );
        final sceneMsg = caption.spokenCaption;
        final isNewScene = sceneMsg != _lastAutoSpokenScene ||
            _lastAutoSpokenSceneTime == null ||
            now.difference(_lastAutoSpokenSceneTime!).inSeconds >= 6;
        if (isNewScene) {
          _lastAutoSpokenScene = sceneMsg;
          _lastAutoSpokenSceneTime = now;
          HapticFeedback.lightImpact();
          _audioMutex.speak(text: sceneMsg, priority: AudioPriority.level2Navigation);
          if (mounted) {
            setState(() {
              _lastReaderScannedSummary = sceneMsg;
            });
          }
        }
        return;
      }

      // Multimodal AI scene & text understanding for Text, Document, Product, and Currency
      final result = await _cloudAiService.analyzeScene(
        bytes,
        currentObstacles: _activeObstacles,
        devicePitchDeg: _pitchDeg,
        speakResult: false,
      );

      // -------------------------------------------------------------
      // Microsoft Seeing AI: Document Framing Guide
      // -------------------------------------------------------------
      if (_readerScanMode == 'document' || _readerScanMode == 'all') {
        final framing = _framingGuideService.evaluateFrame(
          corners: const DocumentCorners(
            topLeftX: 0.12,
            topLeftY: 0.15,
            topRightX: 0.88,
            topRightY: 0.15,
            bottomLeftX: 0.12,
            bottomLeftY: 0.85,
            bottomRightX: 0.88,
            bottomRightY: 0.85,
            coverageRatio: 0.72,
          ),
          phonePitchDeg: _pitchDeg,
          phoneRollDeg: _rollDeg,
        );
        if (mounted) {
          setState(() {
            _lastFramingResult = framing;
          });
        }
      }

      // -------------------------------------------------------------
      // Microsoft Seeing AI: Product & Barcode Channel
      // -------------------------------------------------------------
      if (_readerScanMode == 'product' ||
          _readerScanMode == 'barcode' ||
          _readerScanMode == 'all') {
        final barcodeRegex = RegExp(r'\b\d{8,14}\b');
        final match = barcodeRegex.firstMatch(result.sceneSummary) ??
            result.detailedObjects
                .map((o) => barcodeRegex.firstMatch(o))
                .firstWhere((m) => m != null, orElse: () => null);
        if (match != null) {
          final code = match.group(0)!;
          final isNewBarcode = code != _lastAutoSpokenBarcode ||
              _lastAutoSpokenBarcodeTime == null ||
              now.difference(_lastAutoSpokenBarcodeTime!).inSeconds >= 10;
          if (isNewBarcode) {
            _lastAutoSpokenBarcode = code;
            _lastAutoSpokenBarcodeTime = now;
            HapticFeedback.mediumImpact();
            SystemSound.play(SystemSoundType.click);
            _barcodeService.handleBarcodeDetected(code);
            if (mounted) {
              setState(() {
                _lastReaderScannedSummary = "Product barcode detected: $code";
              });
            }
            return;
          }
        }
      }

      // -------------------------------------------------------------
      // Microsoft Seeing AI: Currency Channel
      // -------------------------------------------------------------
      if (_readerScanMode == 'currency' || _readerScanMode == 'all') {
        final summaryLower = result.sceneSummary.toLowerCase();
        final candidateTokens = <String>[];
        if (!_isNavigationalObstacleSentence(result.sceneSummary)) {
          candidateTokens.add(summaryLower);
        }
        for (final obj in result.detailedObjects) {
          if (!_isNavigationalObstacleSentence(obj)) {
            candidateTokens.add(obj.toLowerCase());
          }
        }
        for (final obs in _activeObstacles) {
          candidateTokens.add(obs.label.toLowerCase());
        }

        final curr = await _currencyService.processVisualTokens(
          detectedTexts: candidateTokens,
          confidence: 0.85,
        );
        if (curr.isIdentified) {
          final spoken = curr.denomination?.spokenText ?? '';
          final isNewCurr = spoken != _lastAutoSpokenCurrency ||
              _lastAutoSpokenCurrencyTime == null ||
              now.difference(_lastAutoSpokenCurrencyTime!).inSeconds >= 6;
          if (isNewCurr) {
            _lastAutoSpokenCurrency = spoken;
            _lastAutoSpokenCurrencyTime = now;
            HapticFeedback.lightImpact();
            _audioMutex.speak(
              text: spoken,
              priority: AudioPriority.level2Navigation,
              haptic: true,
            );
            if (mounted) {
              setState(() {
                _lastReaderScannedSummary = spoken;
                _lastCurrencyResult = curr;
              });
            }
            return;
          }
        }
      }

      // -------------------------------------------------------------
      // Microsoft Seeing AI: Short Text & Document Reading
      // -------------------------------------------------------------
      if (_readerScanMode == 'text' ||
          _readerScanMode == 'ocr' ||
          _readerScanMode == 'document' ||
          _readerScanMode == 'all') {
        String detectedText = "";
        if (result.sceneSummary.isNotEmpty &&
            !_isNavigationalObstacleSentence(result.sceneSummary)) {
          final clean = result.sceneSummary.trim();
          if (clean.length > 3) {
            detectedText = clean;
          }
        }
        if (result.detailedObjects.isNotEmpty) {
          final textObjs = result.detailedObjects
              .where((o) =>
                  !_isNavigationalObstacleSentence(o) &&
                  (o.toLowerCase().contains("text") ||
                      o.toLowerCase().contains("label") ||
                      o.toLowerCase().contains("sign") ||
                      o.toLowerCase().contains("document") ||
                      o.toLowerCase().contains("heading") ||
                      o.toLowerCase().contains("page")))
              .toList();
          if (textObjs.isNotEmpty) {
            detectedText = detectedText.isEmpty
                ? textObjs.join('. ')
                : "$detectedText. ${textObjs.join('. ')}";
          }
        }

        if (detectedText.isNotEmpty) {
          final isNewText = detectedText != _lastAutoSpokenText ||
              _lastAutoSpokenTextTime == null ||
              now.difference(_lastAutoSpokenTextTime!).inSeconds >= 7;
          if (isNewText) {
            _lastAutoSpokenText = detectedText;
            _lastAutoSpokenTextTime = now;
            final session = _documentReaderService.addPage(detectedText);
            HapticFeedback.selectionClick();
            _audioMutex.speak(
              text: detectedText,
              priority: AudioPriority.level2Navigation,
              haptic: false,
            );
            if (mounted) {
              setState(() {
                _lastReaderScannedSummary = detectedText;
                _currentReadingSession = session;
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Seeing AI auto-scan error: $e");
    } finally {
      _isAutoScanningReader = false;
    }
  }

  void _startItemSonarStream() {
    _onDeviceDetector.setEnabled(true);
    _itemSonarStreamTimer?.cancel();
    _itemSonarStreamTimer =
        Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (_activeNavTab == 3 &&
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
    if (!_objectFinderService.isSearching || _activeNavTab != 3) return;

    final target = _objectFinderService.currentState;
    final interval = target.sonarPingIntervalMs.clamp(80, 1200);

    _sonarPingTimer = Timer(Duration(milliseconds: interval), () {
      if (!mounted || _activeNavTab != 3 || !_objectFinderService.isSearching) return;

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
        _activeNavTab != 3) {
      return;
    }

    _isProcessingSonarFrame = true;
    try {
      final img = await _cameraController!.takePicture();
      final bytes = await img.readAsBytes();
      try {
        final f = File(img.path);
        if (await f.exists()) await f.delete();
      } catch (_) {}

      // Ensure detector is enabled for real-time edge inference
      _onDeviceDetector.setEnabled(true);

      // Run on-device detector to identify candidate objects in the frame
      final result = await _onDeviceDetector.processFrameBytes(
        bytes,
        devicePitchDeg: _pitchDeg,
      );

      final candidateObstacles = List<DetectedObstacle>.from(result.obstacles);
      if (candidateObstacles.isEmpty && _activeObstacles.isNotEmpty) {
        candidateObstacles.addAll(_activeObstacles);
      }

      // Check cloud scene if active target is not standard or not in COCO
      if (_objectFinderService.isSearching) {
        final targetLabel =
            _objectFinderService.activeTargetLabel.toLowerCase();
        final hasMatch = candidateObstacles.any(
            (o) => _objectFinderService.isMatching(o.label, targetLabel));

        if (!hasMatch && _cloudAiService.isAutoAnalyzeEnabled) {
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

  void _showVoiceItemSearchDialog() {
    _voiceSonarItemController.clear();
    HapticFeedback.mediumImpact();
    _audioMutex.speak(
      text: "Voice item search active. Speak or select the item to find.",
      priority: AudioPriority.level2Navigation,
      force: true,
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131B2A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFFF0055), width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.mic, color: Color(0xFFFF0055)),
            SizedBox(width: 8),
            Text(
              "Voice Item Search",
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Speak or type what you misplaced:",
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _voiceSonarItemController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "e.g. keys, phone, cane, wallet",
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF0A0E17),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFFF0055)),
                ),
                prefixIcon: const Icon(Icons.search, color: Color(0xFFFF0055)),
              ),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  Navigator.of(ctx).pop();
                  _startSonarSearchFor(value.trim());
                }
              },
            ),
            const SizedBox(height: 12),
            const Text("Quick voice shortcuts:",
                style: TextStyle(fontSize: 11, color: Colors.white54)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                "keys",
                "phone",
                "wallet",
                "white cane",
                "water bottle",
                "glasses",
                "laptop",
                "backpack"
              ].map((item) {
                return InkWell(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _startSonarSearchFor(item);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: const Color(0xFFFF0055).withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      item.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFFFF0055),
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final query = _voiceSonarItemController.text.trim();
              if (query.isNotEmpty) {
                Navigator.of(ctx).pop();
                _startSonarSearchFor(query);
              }
            },
            icon: const Icon(Icons.radar, size: 16),
            label: const Text("START RADAR"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF0055),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _captureAndScanReader({String mode = 'all'}) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _audioMutex.speak(
        text: "Camera not ready for scanning.",
        priority: AudioPriority.level3Context,
        force: true,
      );
      return;
    }
    if (_isReaderScanning) return;

    setState(() {
      _isReaderScanning = true;
      _readerScanMode = mode;
    });
    HapticFeedback.mediumImpact();
    await _audioMutex.speak(
      text: mode == 'document'
          ? "Scanning document framing and text..."
          : mode == 'barcode'
              ? "Scanning barcode and product..."
              : mode == 'currency'
                  ? "Scanning currency note..."
                  : "Scanning camera for documents, text, barcodes, and currency...",
      priority: AudioPriority.level3Context,
      force: true,
    );

    try {
      final img = await _cameraController!.takePicture();
      final bytes = await img.readAsBytes();
      try {
        final f = File(img.path);
        if (await f.exists()) await f.delete();
      } catch (_) {}

      // 1. Deep Multimodal AI scene and text analysis
      final result = await _cloudAiService.analyzeScene(
        bytes,
        currentObstacles: _activeObstacles,
        devicePitchDeg: _pitchDeg,
        force: true,
        speakResult: false,
      );

      // 2. Evaluate document framing
      final framing = _framingGuideService.evaluateFrame(
        corners: const DocumentCorners(
          topLeftX: 0.12,
          topLeftY: 0.15,
          topRightX: 0.88,
          topRightY: 0.15,
          bottomLeftX: 0.12,
          bottomLeftY: 0.85,
          bottomRightX: 0.88,
          bottomRightY: 0.85,
          coverageRatio: 0.72,
        ),
        phonePitchDeg: _pitchDeg,
        phoneRollDeg: _rollDeg,
      );
      setState(() {
        _lastFramingResult = framing;
      });

      // 3. Extract text into batch OCR continuous reader
      String detectedText = "";
      if (result.sceneSummary.isNotEmpty &&
          !_isNavigationalObstacleSentence(result.sceneSummary)) {
        detectedText = result.sceneSummary;
      }
      if (result.detailedObjects.isNotEmpty) {
        final textObjs = result.detailedObjects
            .where((o) =>
                !_isNavigationalObstacleSentence(o) &&
                (o.toLowerCase().contains("text") ||
                    o.toLowerCase().contains("label") ||
                    o.toLowerCase().contains("sign") ||
                    o.toLowerCase().contains("document") ||
                    o.toLowerCase().contains("heading") ||
                    o.toLowerCase().contains("page")))
            .toList();
        if (textObjs.isNotEmpty) {
          detectedText = detectedText.isEmpty
              ? textObjs.join('. ')
              : "$detectedText. Details: ${textObjs.join(', ')}";
        }
      }

      // 4. Barcode and product detection
      final barcodeRegex = RegExp(r'\b\d{8,14}\b');
      final match = barcodeRegex.firstMatch(result.sceneSummary) ??
          result.detailedObjects
              .map((o) => barcodeRegex.firstMatch(o))
              .firstWhere((m) => m != null, orElse: () => null);
      if (match != null) {
        final code = match.group(0)!;
        _barcodeService.handleBarcodeDetected(code);
        if (mode == 'barcode') return;
      } else if (mode == 'barcode') {
        const msg = "No barcode detected in frame. Align barcode under light.";
        setState(() => _lastReaderScannedSummary = msg);
        await _audioMutex.speak(
          text: msg,
          priority: AudioPriority.level3Context,
          force: true,
        );
        return;
      }

      // 5. Currency detection
      final summaryLower = result.sceneSummary.toLowerCase();
      final hasCurrencyKeywords = summaryLower.contains("dollar") ||
          summaryLower.contains("rupee") ||
          summaryLower.contains("euro") ||
          summaryLower.contains("pound") ||
          summaryLower.contains("yen") ||
          summaryLower.contains("currency") ||
          summaryLower.contains("banknote") ||
          summaryLower.contains("note") ||
          summaryLower.contains("bill") ||
          summaryLower.contains("\$") ||
          summaryLower.contains("₹") ||
          summaryLower.contains("€") ||
          summaryLower.contains("£") ||
          summaryLower.contains("¥") ||
          mode == 'currency';

      if (hasCurrencyKeywords) {
        if (summaryLower.contains("rupee") || summaryLower.contains("₹") || summaryLower.contains("inr")) {
          _currencyService.setCurrency(CurrencyCode.inr);
        } else if (summaryLower.contains("euro") || summaryLower.contains("€") || summaryLower.contains("eur")) {
          _currencyService.setCurrency(CurrencyCode.eur);
        } else if (summaryLower.contains("pound") || summaryLower.contains("£") || summaryLower.contains("gbp")) {
          _currencyService.setCurrency(CurrencyCode.gbp);
        } else if (summaryLower.contains("yen") || summaryLower.contains("¥") || summaryLower.contains("jpy")) {
          _currencyService.setCurrency(CurrencyCode.jpy);
        } else if (summaryLower.contains("dollar") || summaryLower.contains("\$") || summaryLower.contains("usd")) {
          _currencyService.setCurrency(CurrencyCode.usd);
        }

        final candidateTokens = <String>[];
        if (!_isNavigationalObstacleSentence(result.sceneSummary)) {
          candidateTokens.add(summaryLower);
        }
        for (final obj in result.detailedObjects) {
          if (!_isNavigationalObstacleSentence(obj)) {
            candidateTokens.add(obj.toLowerCase());
          }
        }
        for (final obs in _activeObstacles) {
          candidateTokens.add(obs.label.toLowerCase());
        }

        final curr = await _currencyService.processVisualTokens(
          detectedTexts: candidateTokens,
          confidence: 0.85,
        );
        if (curr.isIdentified) {
          final spoken = curr.denomination?.spokenText ?? '';
          setState(() {
            _lastCurrencyResult = curr;
            _lastReaderScannedSummary = spoken;
          });
          HapticFeedback.lightImpact();
          await _audioMutex.speak(
            text: spoken,
            priority: AudioPriority.level2Navigation,
            force: true,
          );
          return;
        } else if (mode == 'currency') {
          const msg = "Banknote not recognized. Flatten note and align in camera frame.";
          setState(() => _lastReaderScannedSummary = msg);
          await _audioMutex.speak(
            text: msg,
            priority: AudioPriority.level2Navigation,
            force: true,
          );
          return;
        }
      }

      // 6. Handle Document / OCR Text
      if (detectedText.isNotEmpty) {
        final session = _documentReaderService.addPage(detectedText);
        setState(() {
          _currentReadingSession = session;
          _lastReaderScannedSummary = detectedText;
        });
        if (mode == 'ocr' || mode == 'all' || mode == 'document') {
          _documentReaderService.startReading();
        }
        HapticFeedback.lightImpact();
        await _audioMutex.speak(
          text: detectedText,
          priority: AudioPriority.level2Navigation,
          force: true,
        );
        return;
      }

      // Mode-specific fallback prompts if nothing was detected
      String summary;
      if (mode == 'document') {
        summary = "No document text detected. Align page within the green reticle.";
      } else if (mode == 'ocr') {
        summary = "No printed text detected in view.";
      } else {
        summary = "No text, barcode, or banknote detected. Align subject under good lighting.";
      }

      setState(() {
        _lastReaderScannedSummary = summary;
      });

      HapticFeedback.lightImpact();
      await _audioMutex.speak(
        text: summary,
        priority: AudioPriority.level2Navigation,
        force: true,
      );
    } catch (e) {
      debugPrint("Reader scan error: $e");
    } finally {
      if (mounted) {
        setState(() => _isReaderScanning = false);
      }
    }
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
          )
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () {
          // Day 5 Gesture: 2-Finger / Double Tap trigger for voice Q&A query
          _triggerQuickVoiceQA("What is in front of me?");
        },
        onHorizontalDragEnd: (details) {
          // Channel Swipe: Horizontal swipe switches channels and halts previous tasks immediately
          final velocity = details.primaryVelocity ?? 0.0;
          if (velocity < -120) {
            _switchChannel((_activeNavTab + 1) % 4);
          } else if (velocity > 120) {
            _switchChannel((_activeNavTab - 1 + 4) % 4);
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
                      onTap: () => _switchChannel((_activeNavTab - 1 + 4) % 4),
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
                                : _activeNavTab == 1
                                    ? const Color(0xFFFFD600).withValues(alpha: 0.2)
                                    : _activeNavTab == 2
                                        ? const Color(0xFF76FF03).withValues(alpha: 0.2)
                                        : const Color(0xFFFF0055).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _activeNavTab == 0
                                ? "CHANNEL 1 OF 4: SAFETY HUD"
                                : _activeNavTab == 1
                                    ? "CHANNEL 2 OF 4: NAVIGATION"
                                    : _activeNavTab == 2
                                        ? "CHANNEL 3 OF 4: SMART READER"
                                        : "CHANNEL 4 OF 4: LOST ITEM SONAR",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                              color: _activeNavTab == 0
                                  ? const Color(0xFF00E5FF)
                                  : _activeNavTab == 1
                                      ? const Color(0xFFFFD600)
                                      : _activeNavTab == 2
                                          ? const Color(0xFF76FF03)
                                          : const Color(0xFFFF0055),
                            ),
                          ),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: () => _switchChannel((_activeNavTab + 1) % 4),
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
              ] else if (_activeNavTab == 1) ...[
                // Tab 1: Pedestrian Navigation, Indoor Self-Mapping & Radar
                _buildPedestrianNavCard(),
                const SizedBox(height: 12),

                _buildIndoorMappingCard(),
                const SizedBox(height: 12),

                _buildNavigationRadar(),
                const SizedBox(height: 12),

                _build4kmNearbyDestinationsCard(),
                const SizedBox(height: 12),

                _buildAccordionSection(
                  title: "TRANSIT SENTINEL (BUS & TRAIN)",
                  icon: Icons.directions_bus,
                  color: const Color(0xFFFF9100),
                  child: _buildTransitSentinelCard(),
                ),
              ] else if (_activeNavTab == 2) ...[
                // Channel 3: Microsoft Seeing AI Immersive Live Viewport (Clean, 0 Taps, Edge-to-Edge)
                _buildSeeingAiChannel(),
              ] else ...[
                // Channel 4: Dedicated Lost Item Sonar Radar Channel (Voice Query & Acoustic Echo-Location)
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
                        "REAL-TIME OPTIMAL PATH GUIDANCE",
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
                tooltip: "Speak Optimal Path",
                icon: const Icon(Icons.volume_up,
                    color: Color(0xFF00E5FF), size: 22),
                onPressed: () {
                  _audioMutex.speak(
                    text: opt.voiceInstruction,
                    priority: AudioPriority.level1Safety,
                    force: true,
                    haptic: true,
                  );
                },
              ),
            ],
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
                    color: obs.isHazard
                        ? const Color(0xFFFF1744).withValues(alpha: 0.15)
                        : const Color(0xFF00E5FF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: obs.isHazard
                          ? const Color(0xFFFF1744)
                          : const Color(0xFF00E5FF),
                    ),
                  ),
                  child: Row(
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
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "${obs.detailedDescription} (${obs.clockPosition})",
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                            Text(
                              "Distance: ${obs.distanceMeters.toStringAsFixed(1)}m | TTC: ${obs.ttcSeconds.toStringAsFixed(1)}s | ${(obs.confidence * 100).toInt()}% Conf",
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.white70),
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
            Text("Pin Location / Room",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
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
                labelStyle:
                    const TextStyle(color: Color(0xFF00E5FF), fontSize: 12),
                hintText: "Enter landmark or room name",
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: blockController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: "Block / Building (Optional)",
                labelStyle:
                    const TextStyle(color: Color(0xFFFFD600), fontSize: 12),
                hintText: "Enter building or block name",
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child:
                const Text("CANCEL", style: TextStyle(color: Colors.white54)),
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
            child: const Text("SAVE PIN",
                style: TextStyle(fontWeight: FontWeight.bold)),
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
                (p.blockName != null &&
                    p.blockName!.toLowerCase().contains(queryText)) ||
                (p.address != null &&
                    p.address!.toLowerCase().contains(queryText)) ||
                p.aliases.any((a) => a.toLowerCase().contains(queryText));
          }).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              isNavigating ? phaseColor.withValues(alpha: 0.8) : Colors.white10,
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
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.add_location_alt,
                    size: 18, color: Color(0xFFFFD600)),
                tooltip: "Pin Current GPS Location / Room",
                onPressed: _showSaveCustomPlaceDialog,
              ),
              IconButton(
                icon: isLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF00E5FF)))
                    : const Icon(Icons.refresh,
                        size: 18, color: Color(0xFF00E5FF)),
                tooltip: "Refresh GPS & Locations",
                onPressed: isLoading
                    ? null
                    : () => _navService.fetchNearbyLocations4km(force: true),
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
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (dest.blockName != null &&
                                dest.blockName!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Text(
                                  "🏛️ Building: ${dest.blockName!}",
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFFFD600)),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          dest.category,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white70),
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
                            const Text("DISTANCE & BEARING",
                                style: TextStyle(
                                    fontSize: 9, color: Colors.white54)),
                            Text(
                              "${(navState?.distanceMeters ?? 0.0) >= 1000 ? ((navState?.distanceMeters ?? 0.0) / 1000).toStringAsFixed(1) + 'km' : (navState?.distanceMeters ?? 0.0).toStringAsFixed(0) + 'm'} • ${navState?.clockDirection ?? '12 o\'clock'}",
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: phaseColor),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("NAVIGATION PHASE",
                                style: TextStyle(
                                    fontSize: 9, color: Colors.white54)),
                            Text(
                              phaseTitle,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white),
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
                          const Icon(Icons.check_circle,
                              size: 14, color: Color(0xFF00E676)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "OCR Verified Board: ${_navService.targetBoard!.text}",
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF00E676),
                                  fontWeight: FontWeight.bold),
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
                      label: const Text("Stop Navigation",
                          style: TextStyle(fontSize: 12)),
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
                    hintStyle:
                        const TextStyle(fontSize: 11, color: Colors.white38),
                    prefixIcon: const Icon(Icons.search,
                        size: 16, color: Color(0xFF00E5FF)),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    isLoading
                        ? "Searching nearby locations..."
                        : "No places found matching '$queryText'.",
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
                  if (item.category == "University & Campus" ||
                      item.isCampusBuilding)
                    catIcon = Icons.school;
                  else if (item.category == "Saved My Places" ||
                      item.isCustomSaved)
                    catIcon = Icons.push_pin;
                  else if (item.category == "Medical & Health")
                    catIcon = Icons.local_hospital;
                  else if (item.category == "Food & Dining")
                    catIcon = Icons.restaurant;
                  else if (item.category == "Groceries & Shopping")
                    catIcon = Icons.shopping_cart;
                  else if (item.category == "Transit & Stations")
                    catIcon = Icons.directions_bus;
                  else if (item.category == "Banks & ATMs")
                    catIcon = Icons.account_balance;
                  else if (item.category == "Landmarks & Parks")
                    catIcon = Icons.park;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isCurrentTarget
                          ? const Color(0xFF00E5FF).withValues(alpha: 0.2)
                          : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isCurrentTarget
                            ? const Color(0xFF00E5FF)
                            : Colors.white10,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(catIcon,
                            size: 18,
                            color: item.isCampusBuilding
                                ? const Color(0xFFFFD600)
                                : const Color(0xFF00E5FF)),
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
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (item.blockName != null &&
                                      item.blockName!.isNotEmpty) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFD600)
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                            color: const Color(0xFFFFD600)
                                                .withValues(alpha: 0.6),
                                            width: 0.8),
                                      ),
                                      child: Text(
                                        item.blockName!,
                                        style: const TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFFFFD600)),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (item.address != null)
                                Text(
                                  item.address!,
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.white54),
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00E5FF)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                "${item.formattedDistance} • ${item.clockZone ?? '12 o\'clock'}",
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF00E5FF)),
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
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isCurrentTarget
                                      ? Colors.green
                                      : const Color(0xFF00E5FF),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isCurrentTarget ? "ACTIVE" : "NAVIGATE",
                                  style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black),
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
              const Text("12-HOUR CLOCK RADAR",
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text("TARGET: $_clockDirection:00",
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00E5FF))),
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
                    border: Border.all(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
                  ),
                ),
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1B273A),
                    border: Border.all(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.6)),
                  ),
                ),
                // Clock Numbers
                const Positioned(
                    top: 8,
                    child: Text("12",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF00E5FF)))),
                const Positioned(
                    right: 8,
                    child: Text("3",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.white54))),
                const Positioned(
                    bottom: 8,
                    child: Text("6",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.white54))),
                const Positioned(
                    left: 8,
                    child: Text("9",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.white54))),

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
                const Icon(Icons.navigation,
                    size: 24, color: Color(0xFF00E5FF)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Real PDR Steps: $_stepCount",
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              Text("Accumulated Drift: ${_driftMeters.toStringAsFixed(2)}m",
                  style: TextStyle(
                      fontSize: 12,
                      color: _driftMeters > 0
                          ? Colors.orange
                          : Colors.greenAccent)),
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
          const SizedBox(width: 3),
          // Tab 1: Pedestrian & Indoor Nav
          Expanded(
            child: Semantics(
              button: true,
              selected: _activeNavTab == 1,
              label: "Pedestrian and Indoor Navigation Mode",
              hint: "Double tap to switch to Pedestrian turn-by-turn navigation and indoor self-mapping",
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('mode_tab_navigation'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _switchChannel(1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _activeNavTab == 1
                          ? const Color(0xFFFFD600).withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _activeNavTab == 1
                            ? const Color(0xFFFFD600)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.directions_walk,
                          size: 14,
                          color: _activeNavTab == 1
                              ? const Color(0xFFFFD600)
                              : Colors.white60,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            "Navigation",
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _activeNavTab == 1
                                  ? const Color(0xFFFFD600)
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
          const SizedBox(width: 3),
          // Tab 2: Living & Angels (Smart Reader)
          Expanded(
            child: Semantics(
              button: true,
              selected: _activeNavTab == 2,
              label: "Daily Living Tools and Trusted Angels Caregivers Mode",
              hint: "Double tap to switch to barcode scanner, offline currency, document reader, and 1-tap caregiver call",
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('mode_tab_living'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _switchChannel(2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _activeNavTab == 2
                          ? const Color(0xFF76FF03).withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _activeNavTab == 2
                            ? const Color(0xFF76FF03)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.document_scanner,
                          size: 14,
                          color: _activeNavTab == 2
                              ? const Color(0xFF76FF03)
                              : Colors.white60,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            "Living & Care",
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _activeNavTab == 2
                                  ? const Color(0xFF76FF03)
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
          const SizedBox(width: 3),
          // Tab 3: Lost Item Sonar Radar
          Expanded(
            child: Semantics(
              button: true,
              selected: _activeNavTab == 3,
              label: "Lost Item Sonar Radar Mode",
              hint: "Double tap to switch to Lost Item Sonar Radar for voice-guided echo-location",
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('mode_tab_sonar'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _switchChannel(3),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _activeNavTab == 3
                          ? const Color(0xFFFF0055).withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _activeNavTab == 3
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
                          color: _activeNavTab == 3
                              ? const Color(0xFFFF0055)
                              : Colors.white60,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            "Item Sonar",
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _activeNavTab == 3
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

  Widget _buildPedestrianNavCard() {
    final nav = _lastPedestrianState ?? _pedestrianNavService.currentState;
    final crosswalk = nav.crosswalkStatus;
    final hasActiveRoute = nav.isNavigating;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: const Color(0xFFFFD600).withValues(alpha: 0.4)),
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
                    const Icon(Icons.directions_walk,
                        color: Color(0xFFFFD600), size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: const Text(
                        "PEDESTRIAN & CROSSWALK VISION",
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                          color: Color(0xFFFFD600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD600).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  hasActiveRoute ? "ACTIVE ROUTE" : "EXPLORATION",
                  style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFFFFD600),
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Crosswalk & Signal Box
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0E17),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: crosswalk.crosswalkDetected &&
                        crosswalk.lightState == TrafficLightState.walkSignal
                    ? const Color(0xFF76FF03)
                    : (crosswalk.crosswalkDetected
                        ? const Color(0xFFFF1744)
                        : Colors.white12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  crosswalk.crosswalkDetected &&
                          crosswalk.lightState == TrafficLightState.walkSignal
                      ? Icons.directions_walk
                      : (crosswalk.crosswalkDetected
                          ? Icons.pan_tool
                          : Icons.traffic),
                  color: crosswalk.crosswalkDetected &&
                          crosswalk.lightState == TrafficLightState.walkSignal
                      ? const Color(0xFF76FF03)
                      : (crosswalk.crosswalkDetected
                          ? const Color(0xFFFF1744)
                          : Colors.white38),
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        crosswalk.crosswalkDetected
                            ? crosswalk.spokenAlert
                            : "Scanning for zebra crosswalks & traffic signals...",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: crosswalk.crosswalkDetected &&
                                  crosswalk.lightState ==
                                      TrafficLightState.walkSignal
                              ? const Color(0xFF76FF03)
                              : Colors.white,
                        ),
                      ),
                      if (crosswalk.countdownSeconds > 0)
                        Text(
                          "Countdown: ${crosswalk.countdownSeconds}s remaining",
                          style: const TextStyle(
                              fontSize: 11, color: Colors.orangeAccent),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (hasActiveRoute) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0E17),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF00E5FF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Destination: ${nav.destinationName}",
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF00E5FF)),
                      ),
                      Text(
                        "${nav.remainingDistanceMeters.toStringAsFixed(0)}m remaining",
                        style: const TextStyle(
                            fontSize: 10, color: Colors.white54),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    nav.currentTurnInstruction,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  _pedestrianNavService.processCrosswalkVision(
                    zebraCrossingDetected: true,
                    distanceMeters: 4.0,
                    lightState: TrafficLightState.walkSignal,
                    countdownSeconds: 12,
                    confidence: 0.95,
                  );
                },
                icon: const Icon(Icons.check_circle, size: 14),
                label: const Text("Simulate Walk Signal",
                    style: TextStyle(fontSize: 10)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: const Color(0xFF76FF03),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  _pedestrianNavService.processCrosswalkVision(
                    zebraCrossingDetected: true,
                    distanceMeters: 4.0,
                    lightState: TrafficLightState.dontWalkSignal,
                    countdownSeconds: 0,
                    confidence: 0.95,
                  );
                },
                icon: const Icon(Icons.do_not_disturb_on, size: 14),
                label: const Text("Simulate Don't Walk",
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
                  if (hasActiveRoute) {
                    _pedestrianNavService.stopNavigation();
                  } else {
                    _pedestrianNavService.startPedestrianRoute(
                      destinationName: "Downtown Metro Station",
                      waypoints: const [
                        PedestrianWaypoint(
                          latitude: 37.7749,
                          longitude: -122.4194,
                          instruction:
                              "Walk straight for 80 meters towards crosswalk.",
                          relativeClockDirection: 12,
                          distanceMeters: 80.0,
                        ),
                        PedestrianWaypoint(
                          latitude: 37.7752,
                          longitude: -122.4190,
                          instruction:
                              "Cross street when signal indicates WALK.",
                          relativeClockDirection: 12,
                          distanceMeters: 20.0,
                          isCrosswalk: true,
                        ),
                        PedestrianWaypoint(
                          latitude: 37.7755,
                          longitude: -122.4185,
                          instruction:
                              "Turn slight left towards 10 o'clock to enter station.",
                          relativeClockDirection: 10,
                          distanceMeters: 140.0,
                        ),
                      ],
                    );
                  }
                },
                icon: Icon(hasActiveRoute ? Icons.stop : Icons.play_arrow,
                    size: 14),
                label: Text(
                    hasActiveRoute ? "Stop Route" : "Start Metro Route Demo",
                    style: const TextStyle(fontSize: 10)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD600),
                  foregroundColor: Colors.black,
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

  Widget _buildIndoorMappingCard() {
    final indoor = _lastIndoorState ?? _indoorMappingService.currentState;
    final isRecording = indoor.isRecordingMap;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.4)),
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
                    const Icon(Icons.meeting_room_outlined,
                        color: Color(0xFF00E5FF), size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: const Text(
                        "INDOOR SELF-MAPPING & A* ROUTING",
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                          color: Color(0xFF00E5FF),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isRecording
                      ? const Color(0xFFFF1744).withValues(alpha: 0.2)
                      : const Color(0xFF00E5FF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isRecording ? "RECORDING WALK" : "MAPPING READY",
                  style: TextStyle(
                    fontSize: 10,
                    color: isRecording
                        ? const Color(0xFFFF1744)
                        : const Color(0xFF00E5FF),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0E17),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Venue: ${indoor.currentVenue} (Pos: ${indoor.currentX.toStringAsFixed(1)}m, ${indoor.currentY.toStringAsFixed(1)}m)",
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Text(
                  indoor.currentInstruction,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
                if (indoor.lastSnappedLandmark != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    "📍 Snapped Landmark: ${indoor.lastSnappedLandmark!}",
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF76FF03),
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  if (isRecording) {
                    _indoorMappingService.stopRecordingAndExportMap();
                  } else {
                    _indoorMappingService
                        .startRecordingMap("Medical Center Floor 2");
                  }
                },
                icon: Icon(
                    isRecording ? Icons.stop : Icons.fiber_manual_record,
                    size: 14),
                label: Text(isRecording ? "Stop Trace" : "Record & Walk",
                    style: const TextStyle(fontSize: 10)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isRecording
                      ? const Color(0xFFFF1744)
                      : const Color(0xFF00E5FF),
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  if (isRecording) {
                    _indoorMappingService.addLandmarkPlaqueDuringRecording(
                      plaqueName: "Room 302 - Clinic",
                      detectedOcrText: "ROOM 302 DR SMITH",
                    );
                  } else {
                    _indoorMappingService
                        .startRecordingMap("Medical Center Floor 2");
                    _indoorMappingService.addLandmarkPlaqueDuringRecording(
                      plaqueName: "Room 302 - Clinic",
                      detectedOcrText: "ROOM 302 DR SMITH",
                    );
                  }
                },
                icon: const Icon(Icons.add_location_alt, size: 14),
                label: const Text("Add 'Room 302' Node",
                    style: TextStyle(fontSize: 10)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: const Color(0xFF00E5FF),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  _indoorMappingService.attemptOcrLandmarkSnap("RM 302 SMITH");
                },
                icon: const Icon(Icons.document_scanner, size: 14),
                label: const Text("Test OCR Plaque Snap",
                    style: TextStyle(fontSize: 10)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: const Color(0xFF76FF03),
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

  Widget _buildTransitSentinelCard() {
    final alert = _lastTransitAlert;
    final isDanger = alert.isEmergencyEdgeHazard;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDanger ? const Color(0xFFFF1744) : const Color(0xFF00E5FF).withValues(alpha: 0.4),
          width: isDanger ? 2.0 : 1.0,
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
                    Icon(Icons.directions_bus,
                        color: isDanger
                            ? const Color(0xFFFF1744)
                            : const Color(0xFF00E5FF),
                        size: 18),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        "PUBLIC TRANSIT & PLATFORM SENTINEL",
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
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
                  color: isDanger
                      ? const Color(0xFFFF1744).withValues(alpha: 0.2)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isDanger ? "PLATFORM HAZARD" : "ACTIVE SENTINEL",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isDanger ? const Color(0xFFFF1744) : Colors.white60,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            alert.description,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDanger ? const Color(0xFFFF1744) : const Color(0xFF76FF03),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  _transitService.processBusHeadsign(
                    ocrLines: ["METRO TRANSIT", "42 EXPRESS", "CIVIC CENTER"],
                    distanceMeters: 14.5,
                  );
                },
                icon: const Icon(Icons.directions_bus, size: 14),
                label: const Text("Simulate Bus 42", style: TextStyle(fontSize: 10)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: const Color(0xFF76FF03),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  _transitService.evaluatePlatformEdgeSafety(
                    tactilePavingVisible: true,
                    platformDropOffVisible: true,
                    dropOffDistanceMeters: 1.1,
                    trainPresent: false,
                  );
                },
                icon: const Icon(Icons.warning, size: 14),
                label: const Text("Simulate Platform Edge", style: TextStyle(fontSize: 10)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: const Color(0xFFFF1744),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showManualBarcodeDialog() {
    _manualBarcodeInputController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131B2A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF00E5FF)),
        ),
        title: const Row(
          children: [
            Icon(Icons.qr_code_scanner, color: Color(0xFF00E5FF), size: 20),
            SizedBox(width: 8),
            Text("Lookup Product Barcode", style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Enter any UPC or EAN barcode number to retrieve product name, nutrition, and allergen alerts via OpenFoodFacts:",
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _manualBarcodeInputController,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Enter barcode number",
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF0A0E17),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF00E5FF)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCEL", style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () {
              final code = _manualBarcodeInputController.text.trim();
              Navigator.pop(ctx);
              if (code.isNotEmpty) {
                _barcodeService.handleBarcodeDetected(code);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
            ),
            child: const Text("LOOKUP PRODUCT"),
          ),
        ],
      ),
    );
  }

  Widget _buildSeeingAiChannel() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = MediaQuery.of(context).size.height;
        final viewportHeight = (screenHeight * 0.74).clamp(520.0, 740.0);
        final boxWidth = constraints.maxWidth;

        return Container(
          height: viewportHeight,
          decoration: BoxDecoration(
            color: const Color(0xFF070B12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF76FF03).withValues(alpha: 0.5),
              width: 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF76FF03).withValues(alpha: 0.12),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Full-screen Camera Preview
                if (_isCameraInitialized && _cameraController != null)
                  CameraPreview(_cameraController!)
                else
                  Container(
                    color: Colors.black,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Color(0xFF76FF03)),
                          SizedBox(height: 12),
                          Text(
                            "Starting Seeing AI Live Camera...",
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 2. High-Contrast Targeting Reticle (Seeing AI Brackets)
                Center(
                  child: GestureDetector(
                    onTap: () => _captureAndScanReader(mode: _readerScanMode),
                    child: Container(
                      width: boxWidth * 0.84,
                      height: viewportHeight * 0.56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _isReaderScanning || _isAutoScanningReader
                              ? const Color(0xFF76FF03).withValues(alpha: 0.7)
                              : const Color(0xFF00E5FF).withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: Stack(
                        children: [
                          // 4 corner indicators
                          Positioned(
                            top: 0,
                            left: 0,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                border: Border(
                                  top: BorderSide(color: Color(0xFF76FF03), width: 4),
                                  left: BorderSide(color: Color(0xFF76FF03), width: 4),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                border: Border(
                                  top: BorderSide(color: Color(0xFF76FF03), width: 4),
                                  right: BorderSide(color: Color(0xFF76FF03), width: 4),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Color(0xFF76FF03), width: 4),
                                  left: BorderSide(color: Color(0xFF76FF03), width: 4),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Color(0xFF76FF03), width: 4),
                                  right: BorderSide(color: Color(0xFF76FF03), width: 4),
                                ),
                              ),
                            ),
                          ),
                          if (_readerScanMode == 'product' || _readerScanMode == 'barcode')
                            Center(
                              child: Container(
                                height: 2,
                                color: const Color(0xFFFF1744).withValues(alpha: 0.85),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 3. Top Floating Status Bar
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: Row(
                    children: [
                      // Badge containing exact text 'DAILY LIVING ASSISTANT' for accessibility audit test
                      Flexible(
                        flex: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF76FF03)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF76FF03),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    "DAILY LIVING ASSISTANT",
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                      color: Color(0xFF76FF03),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (_readerScanMode == 'product' || _readerScanMode == 'barcode') ...[
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.keyboard, color: Color(0xFF00E5FF), size: 18),
                          tooltip: "Enter Barcode Number",
                          onPressed: _showManualBarcodeDialog,
                        ),
                        const SizedBox(width: 6),
                      ],
                      // 1-Tap Trusted Angels Video Call Button (Exact text for accessibility audit test)
                      Flexible(
                        flex: 6,
                        child: Semantics(
                          button: true,
                          label: "TRUSTED ANGELS CAREGIVER CALL",
                          child: InkWell(
                            onTap: () {
                              if (_angelsCallService.isCallActive) {
                                _angelsCallService.endCall();
                              } else {
                                _angelsCallService.startCall();
                              }
                              HapticFeedback.heavyImpact();
                              setState(() {});
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: (_lastCallState.status == TrustedAngelCallStatus.connected ||
                                        _lastCallState.status == TrustedAngelCallStatus.dialing)
                                    ? const Color(0xFFFF1744).withValues(alpha: 0.9)
                                    : Colors.black.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: (_lastCallState.status == TrustedAngelCallStatus.connected ||
                                          _lastCallState.status == TrustedAngelCallStatus.dialing)
                                      ? const Color(0xFFFF1744)
                                      : const Color(0xFF00E5FF),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    (_lastCallState.status == TrustedAngelCallStatus.connected ||
                                            _lastCallState.status == TrustedAngelCallStatus.dialing)
                                        ? Icons.call_end
                                        : Icons.video_call,
                                    size: 14,
                                    color: (_lastCallState.status == TrustedAngelCallStatus.connected ||
                                            _lastCallState.status == TrustedAngelCallStatus.dialing)
                                        ? Colors.white
                                        : const Color(0xFF00E5FF),
                                  ),
                                  const SizedBox(width: 4),
                                  const Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        "TRUSTED ANGELS CAREGIVER CALL",
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 4. Live Recognition Subtitle Floating Pill (Directly above channel switcher)
                Positioned(
                  bottom: 64,
                  left: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF76FF03).withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black87,
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.volume_up, size: 18, color: Color(0xFF76FF03)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _lastReaderScannedSummary.isNotEmpty
                                ? _lastReaderScannedSummary
                                : (_readerScanMode == 'color'
                                    ? "Color: $_currentColorName (Center Target)"
                                    : _readerScanMode == 'light'
                                        ? "Light Level: $_currentLightLevelPercent%"
                                        : _readerScanMode == 'product' && _lastScannedProduct != null
                                            ? "Product: ${_lastScannedProduct!.name}"
                                            : _readerScanMode == 'currency' && _lastCurrencyResult != null
                                                ? "Banknote: ${_lastCurrencyResult!.statusText}"
                                                : _readerScanMode == 'document' && _lastFramingResult != null
                                                    ? _lastFramingResult!.spokenGuidance
                                                    : _readerScanMode == 'text' && _currentReadingSession.currentParagraph != null
                                                        ? _currentReadingSession.currentParagraph!.text
                                                        : "Point camera at document, banknote, product, person, or scene..."),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 5. Microsoft Seeing AI Bottom Channel Switcher Strip
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 48,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0E17).withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      children: [
                        _buildSeeingAiModePill("Short Text", "text", Icons.short_text),
                        _buildSeeingAiModePill("Document", "document", Icons.document_scanner),
                        _buildSeeingAiModePill("Product", "product", Icons.qr_code_scanner),
                        _buildSeeingAiModePill("Person", "person", Icons.person_search),
                        _buildSeeingAiModePill("Currency", "currency", Icons.payments_outlined),
                        _buildSeeingAiModePill("Scene", "scene", Icons.wb_twilight),
                        _buildSeeingAiModePill("Color", "color", Icons.palette_outlined),
                        _buildSeeingAiModePill("Light", "light", Icons.light_mode_outlined),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSeeingAiModePill(String label, String modeKey, IconData icon) {
    final isSelected = _readerScanMode == modeKey ||
        (_readerScanMode == 'ocr' && modeKey == 'text') ||
        (_readerScanMode == 'barcode' && modeKey == 'product');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        onTap: () {
          setState(() => _readerScanMode = modeKey);
          HapticFeedback.selectionClick();
          _audioMutex.speak(
            text: "$label mode active. Point camera at subject for instant recognition.",
            priority: AudioPriority.level3Context,
            force: true,
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF76FF03).withValues(alpha: 0.25)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? const Color(0xFF76FF03) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? const Color(0xFF76FF03) : Colors.white60,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? const Color(0xFF76FF03) : Colors.white70,
                ),
              ),
            ],
          ),
        ),
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
    final quickVoiceChips = [
      {"label": "keys", "icon": Icons.vpn_key},
      {"label": "white cane", "icon": Icons.blind},
      {"label": "water bottle", "icon": Icons.local_drink},
      {"label": "wallet", "icon": Icons.account_balance_wallet},
      {"label": "phone", "icon": Icons.phone_android},
      {"label": "glasses", "icon": Icons.visibility},
      {"label": "laptop", "icon": Icons.laptop},
      {"label": "backpack", "icon": Icons.backpack},
    ];

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

                // Large Accessible Voice Command Button
                Semantics(
                  button: true,
                  label: "Speak Lost Item Name",
                  hint: "Double tap to speak the name of your lost item",
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _showVoiceItemSearchDialog,
                      icon: const Icon(Icons.mic, size: 22, color: Colors.white),
                      label: Text(
                        "🎙️ SPEAK LOST ITEM: ${_objectFinderService.activeTargetLabel.toUpperCase()}",
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF0055),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 4,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Quick Voice / Tap Item Chips
                const Text(
                  "Quick Voice Targets:",
                  style: TextStyle(fontSize: 11, color: Colors.white54),
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: quickVoiceChips.map((chip) {
                      final label = chip['label'] as String;
                      final icon = chip['icon'] as IconData;
                      final isSelected =
                          _objectFinderService.activeTargetLabel == label;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          backgroundColor: isSelected
                              ? const Color(0xFFFF0055).withValues(alpha: 0.25)
                              : const Color(0xFF0A0E17),
                          side: BorderSide(
                            color: isSelected
                                ? const Color(0xFFFF0055)
                                : Colors.white24,
                          ),
                          avatar: Icon(
                            icon,
                            size: 14,
                            color: isSelected
                                ? const Color(0xFFFF0055)
                                : Colors.white70,
                          ),
                          label: Text(
                            label.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? const Color(0xFFFF0055)
                                  : Colors.white70,
                            ),
                          ),
                          onPressed: () => _startSonarSearchFor(label),
                        ),
                      );
                    }).toList(),
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


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

  int _activeNavTab = 0; // 0: Hazard HUD, 1: Pedestrian & Indoor Nav, 2: Daily Living & Caregiver
  final TextEditingController _manualBarcodeInputController =
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
          _optimalPath = result.optimalPath;
        });
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

  DateTime _lastSensorUiUpdateTime = DateTime.now();

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

      // Downward pitch prompt (severe downward pitch > 45° looking at shoes) - 60s cooldown
      if (pitchDeg < -45.0) {
        final nowTime = DateTime.now();
        if (_lastTiltWarningTime == null ||
            nowTime.difference(_lastTiltWarningTime!).inSeconds >= 60) {
          _lastTiltWarningTime = nowTime;
          _audioMutex.speak(
            text: "Please tilt phone up for obstacle vision.",
            priority: AudioPriority.level1Safety,
            haptic: true,
          );
        }
      }

      // Throttle UI setState to 3.3 Hz (every 300ms) to prevent 100Hz rebuild storms and lag
      if (mounted &&
          now.difference(_lastSensorUiUpdateTime).inMilliseconds >= 300) {
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
          !_isExplainingSituation &&
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
        _isProcessingFrame ||
        _isExplainingSituation) {
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
    _speechSubscription?.cancel();
    _destinationInputController.dispose();
    _manualBarcodeInputController.dispose();
    _voiceQuestionInputController.dispose();
    _indoorNodeNameController.dispose();
    _indoorOcrInputController.dispose();
    _navService.stopNavigation();
    _cameraController?.dispose();
    _audioMutex.dispose();
    super.dispose();
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
          // Day 5 Gesture: Horizontal swipe cycles between 3 primary tabs
          if (details.primaryVelocity != null) {
            if (details.primaryVelocity! < -200) {
              setState(() => _activeNavTab = (_activeNavTab + 1) % 3);
              final tabNames = [
                "Safety Hazard HUD",
                "Pedestrian and Indoor Navigation",
                "Daily Living and Caregivers"
              ];
              _audioMutex.speak(
                text: "Switched to ${tabNames[_activeNavTab]} Mode.",
                priority: AudioPriority.level2Navigation,
                haptic: true,
              );
            } else if (details.primaryVelocity! > 200) {
              setState(() => _activeNavTab = (_activeNavTab - 1 + 3) % 3);
              final tabNames = [
                "Safety Hazard HUD",
                "Pedestrian and Indoor Navigation",
                "Daily Living and Caregivers"
              ];
              _audioMutex.speak(
                text: "Switched to ${tabNames[_activeNavTab]} Mode.",
                priority: AudioPriority.level2Navigation,
                haptic: true,
              );
            }
          }
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mode Switcher Tab Bar (3 Primary Modes)
              _buildModeSwitcherTabBar(),
              const SizedBox(height: 12),

              // 1. Real-time Hardware & Telemetry Bar
              _buildTelemetryBar(),
              const SizedBox(height: 14),

              if (_activeNavTab == 0) ...[
                // Tab 0: Safety & Hazard HUD
                _buildPortraitCameraViewfinder(hasCriticalHazard),
                const SizedBox(height: 14),

                _buildVoiceQACard(),
                const SizedBox(height: 14),

                _buildOptimalPathGuidanceCard(hasCriticalHazard),
                const SizedBox(height: 14),

                _buildBinauralEarconStatusCard(),
                const SizedBox(height: 14),

                _buildMotionKinematicsCard(),
                const SizedBox(height: 14),

                _buildObstacleDetectionCard(hasCriticalHazard),
                const SizedBox(height: 14),

                _buildSceneComprehensionCard(),
                const SizedBox(height: 14),
              ] else if (_activeNavTab == 1) ...[
                // Tab 1: Pedestrian Navigation & Indoor Self-Mapping
                _buildPedestrianNavCard(),
                const SizedBox(height: 14),

                _buildIndoorMappingCard(),
                const SizedBox(height: 14),

                _build4kmNearbyDestinationsCard(),
                const SizedBox(height: 14),

                _buildNavigationRadar(),
                const SizedBox(height: 14),
              ] else ...[
                // Tab 2: Daily Living Tools & Trusted Angels Caregivers
                _buildTrustedAngelsCard(),
                const SizedBox(height: 14),

                _buildDailyLivingToolsCard(),
                const SizedBox(height: 14),
              ],

              // 8. Audio Mutex Speech & Voice State
              _buildAudioStatusCard(hasCriticalHazard),
              const SizedBox(height: 14),

              // 9. Interactive Testing & Control Bar
              _buildControlBar(),
              const SizedBox(height: 24),
            ],
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
              Row(
                children: [
                  Icon(Icons.alt_route, color: directionColor, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    "REAL-TIME OPTIMAL PATH GUIDANCE",
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
                hintText: "e.g. Room 304, HOD Office, Robotics Lab",
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
                hintText: "e.g. Block B - CSE, Science Block",
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
                  onTap: () {
                    setState(() => _activeNavTab = 0);
                    _audioMutex.speak(
                      text: "Switched to Safety Hazard HUD.",
                      priority: AudioPriority.level2Navigation,
                      haptic: true,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
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
                          size: 15,
                          color: _activeNavTab == 0
                              ? const Color(0xFF00E5FF)
                              : Colors.white60,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "Safety HUD",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _activeNavTab == 0
                                ? const Color(0xFF00E5FF)
                                : Colors.white60,
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
                  onTap: () {
                    setState(() => _activeNavTab = 1);
                    _audioMutex.speak(
                      text: "Switched to Pedestrian and Indoor Navigation.",
                      priority: AudioPriority.level2Navigation,
                      haptic: true,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
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
                          size: 15,
                          color: _activeNavTab == 1
                              ? const Color(0xFFFFD600)
                              : Colors.white60,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "Navigation",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _activeNavTab == 1
                                ? const Color(0xFFFFD600)
                                : Colors.white60,
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
          // Tab 2: Living & Angels
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
                  onTap: () {
                    setState(() => _activeNavTab = 2);
                    _audioMutex.speak(
                      text: "Switched to Daily Living Tools and Trusted Angels.",
                      priority: AudioPriority.level2Navigation,
                      haptic: true,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
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
                          Icons.volunteer_activism_outlined,
                          size: 15,
                          color: _activeNavTab == 2
                              ? const Color(0xFF76FF03)
                              : Colors.white60,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "Living & Care",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _activeNavTab == 2
                                ? const Color(0xFF76FF03)
                                : Colors.white60,
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
              Row(
                children: [
                  Icon(Icons.headphones, size: 18, color: zoneColor),
                  const SizedBox(width: 8),
                  const Text(
                    "3D SPATIAL BINAURAL EARCONS",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
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
              const Row(
                children: [
                  Icon(Icons.directions_walk,
                      color: Color(0xFFFFD600), size: 18),
                  SizedBox(width: 8),
                  Text(
                    "PEDESTRIAN & CROSSWALK VISION",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: Color(0xFFFFD600),
                    ),
                  ),
                ],
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
              const Row(
                children: [
                  Icon(Icons.meeting_room_outlined,
                      color: Color(0xFF00E5FF), size: 18),
                  SizedBox(width: 8),
                  Text(
                    "INDOOR SELF-MAPPING & A* ROUTING",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: Color(0xFF00E5FF),
                    ),
                  ),
                ],
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

  Widget _buildTrustedAngelsCard() {
    final call = _lastCallState;
    final isBusy = call.status == TrustedAngelCallStatus.dialing ||
        call.status == TrustedAngelCallStatus.connected;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isBusy
              ? const Color(0xFF76FF03)
              : const Color(0xFFFF1744).withValues(alpha: 0.5),
          width: 1.5,
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
                  Icon(Icons.volunteer_activism,
                      color: isBusy
                          ? const Color(0xFF76FF03)
                          : const Color(0xFFFF1744),
                      size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    "TRUSTED ANGELS CAREGIVER CALL",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isBusy
                      ? const Color(0xFF76FF03).withValues(alpha: 0.2)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  call.status.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isBusy ? const Color(0xFF76FF03) : Colors.white60,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0E17),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                Icon(
                  isBusy
                      ? Icons.video_camera_front
                      : Icons.phone_in_talk_outlined,
                  size: 32,
                  color: isBusy
                      ? const Color(0xFF76FF03)
                      : const Color(0xFF00E5FF),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isBusy
                            ? (call.activeContact?.name ?? "Connected Angel")
                            : "No Active Call Session",
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isBusy
                            ? "P2P WebRTC Active • Duration: ${call.callDuration.inSeconds}s • Zero-Cloud"
                            : "1-Tap instant video assistance from verified family or volunteer caregivers.",
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: isBusy ? "End Angel Call" : "1-Tap Call Volunteer Angel",
                  hint: isBusy
                      ? "Double tap to hang up caregiver call"
                      : "Double tap to instantly start peer-to-peer video call with a verified caregiver or family member",
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (isBusy) {
                        _angelsCallService.endCall();
                      } else {
                        _angelsCallService.startCall();
                      }
                    },
                    icon:
                        Icon(isBusy ? Icons.call_end : Icons.add_call, size: 18),
                    label: Text(
                      isBusy ? "End Angel Call" : "1-Tap Call Volunteer Angel",
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isBusy
                          ? const Color(0xFFFF1744)
                          : const Color(0xFF76FF03),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDailyLivingToolsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF76FF03).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF76FF03).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.inventory_2_outlined,
                    color: Color(0xFF76FF03), size: 20),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "DAILY LIVING ASSISTANT",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Color(0xFF76FF03),
                    ),
                  ),
                  Text(
                    "Offline Barcode, Allergens & Currency Haptics",
                    style: TextStyle(fontSize: 11, color: Colors.white60),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 1. Barcode & Product Scanner Section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.qr_code_scanner, size: 16, color: Color(0xFF00E5FF)),
                        SizedBox(width: 6),
                        Text(
                          "Product & Barcode Reader",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
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
                      child: const Text(
                        "OpenFoodFacts",
                        style: TextStyle(fontSize: 10, color: Color(0xFF00E5FF)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_lastScannedProduct != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0E17),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _lastScannedProduct!.isFound
                            ? const Color(0xFF76FF03)
                            : Colors.orangeAccent,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _lastScannedProduct!.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        if (_lastScannedProduct!.allergens.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            "⚠️ Contains: ${_lastScannedProduct!.allergens}",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFFF5252),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          _lastScannedProduct!.summarySpeech,
                          style: const TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // Quick test scanner with sample barcode
                          _barcodeService.handleBarcodeDetected("012000000133");
                        },
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: const Text("Scan Pepsi (Demo)", style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // Milk with allergen warning
                          _barcodeService.handleBarcodeDetected("078742351865");
                        },
                        icon: const Icon(Icons.warning_amber_rounded, size: 16),
                        label: const Text("Scan Milk (Allergen)", style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          foregroundColor: const Color(0xFFFFD700),
                          side: const BorderSide(color: Color(0xFFFFD700)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 2. Offline Currency Recognizer Section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.payments_outlined, size: 16, color: Color(0xFF76FF03)),
                        SizedBox(width: 6),
                        Text(
                          "Offline Currency & Haptics",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    DropdownButton<CurrencyCode>(
                      value: _currencyService.selectedCurrency,
                      dropdownColor: const Color(0xFF131B2A),
                      underline: const SizedBox(),
                      icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF76FF03), size: 18),
                      items: CurrencyCode.values.map((curr) {
                        return DropdownMenuItem(
                          value: curr,
                          child: Text(
                            curr.name.toUpperCase(),
                            style: const TextStyle(fontSize: 12, color: Color(0xFF76FF03)),
                          ),
                        );
                      }).toList(),
                      onChanged: (newCurr) {
                        if (newCurr != null) {
                          setState(() {
                            _currencyService.setCurrency(newCurr);
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_lastCurrencyResult != null && _lastCurrencyResult!.isIdentified) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0E17),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF76FF03)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF76FF03).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "${_lastCurrencyResult!.denomination?.symbol}${_lastCurrencyResult!.denomination?.value}",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF76FF03),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _lastCurrencyResult!.denomination?.spokenText ?? '',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                "Tactile pattern: ${_lastCurrencyResult!.denomination?.hapticPatternMs.length} pulses",
                                style: const TextStyle(fontSize: 10, color: Colors.white54),
                              ),
                            ],
                          ),
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
                    ElevatedButton(
                      onPressed: () {
                        _currencyService.processVisualTokens(
                          detectedTexts: ["20", "DOLLARS", "TWENTY"],
                          confidence: 0.95,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A0E17),
                        foregroundColor: const Color(0xFF76FF03),
                        side: const BorderSide(color: Color(0xFF76FF03)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      child: const Text("Test \$20 Note", style: TextStyle(fontSize: 11)),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        _currencyService.processVisualTokens(
                          detectedTexts: ["100", "HUNDRED", "DOLLARS"],
                          confidence: 0.95,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A0E17),
                        foregroundColor: const Color(0xFF76FF03),
                        side: const BorderSide(color: Color(0xFF76FF03)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      child: const Text("Test \$100 Note", style: TextStyle(fontSize: 11)),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        _currencyService.processVisualTokens(
                          detectedTexts: ["500", "RUPEES", "INDIA"],
                          confidence: 0.92,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A0E17),
                        foregroundColor: const Color(0xFF00E5FF),
                        side: const BorderSide(color: Color(0xFF00E5FF)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                      child: const Text("Test ₹500 Note", style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 3. Document Audio Framing Guide & Auto-Shutter Scanner (Day 3)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.document_scanner_outlined, size: 16, color: Color(0xFF00E5FF)),
                        SizedBox(width: 6),
                        Text(
                          "Document Framing & Auto-Capture",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
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
                      child: const Text(
                        "Auto-Shutter",
                        style: TextStyle(fontSize: 10, color: Color(0xFF00E5FF)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_lastFramingResult != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0E17),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _lastFramingResult!.readyToCapture
                            ? const Color(0xFF76FF03)
                            : const Color(0xFF00E5FF),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _lastFramingResult!.readyToCapture
                                  ? Icons.check_circle
                                  : Icons.center_focus_strong,
                              size: 16,
                              color: _lastFramingResult!.readyToCapture
                                  ? const Color(0xFF76FF03)
                                  : const Color(0xFF00E5FF),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _lastFramingResult!.spokenGuidance,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _lastFramingResult!.readyToCapture
                                      ? const Color(0xFF76FF03)
                                      : Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_lastFramingResult!.stabilityProgress > 0.0) ...[
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: _lastFramingResult!.stabilityProgress,
                            backgroundColor: Colors.white10,
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF76FF03)),
                            minHeight: 4,
                          ),
                        ],
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
                        // Simulate too close
                        _framingGuideService.evaluateFrame(
                          corners: const DocumentCorners(
                            topLeftX: 0.01,
                            topLeftY: 0.01,
                            topRightX: 0.99,
                            topRightY: 0.01,
                            bottomLeftX: 0.01,
                            bottomLeftY: 0.99,
                            bottomRightX: 0.99,
                            bottomRightY: 0.99,
                            coverageRatio: 0.95,
                          ),
                          phonePitchDeg: _pitchDeg,
                          phoneRollDeg: _rollDeg,
                        );
                      },
                      icon: const Icon(Icons.zoom_out, size: 14),
                      label: const Text("Too Close Demo", style: TextStyle(fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A0E17),
                        foregroundColor: Colors.white70,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        // Simulate perfect alignment and auto-capture
                        _framingGuideService.evaluateFrame(
                          corners: const DocumentCorners(
                            topLeftX: 0.15,
                            topLeftY: 0.15,
                            topRightX: 0.85,
                            topRightY: 0.15,
                            bottomLeftX: 0.15,
                            bottomLeftY: 0.85,
                            bottomRightX: 0.85,
                            bottomRightY: 0.85,
                            coverageRatio: 0.65,
                          ),
                          phonePitchDeg: 0.0,
                          phoneRollDeg: 0.0,
                        );
                      },
                      icon: const Icon(Icons.camera_alt_outlined, size: 14),
                      label: const Text("Align & Capture", style: TextStyle(fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 4. Batch OCR & Continuous Natural Text Reader (Day 4)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.menu_book, size: 16, color: Color(0xFF76FF03)),
                        SizedBox(width: 6),
                        Text(
                          "Continuous OCR & Batch Reader",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF76FF03).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        "Speed ${_currentReadingSession.playbackSpeed}x",
                        style: const TextStyle(fontSize: 10, color: Color(0xFF76FF03)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_currentReadingSession.hasContent) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0E17),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _currentReadingSession.isPlaying
                            ? const Color(0xFF76FF03)
                            : Colors.white24,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Paragraph ${_currentReadingSession.currentParagraphIndex + 1} of ${_currentReadingSession.totalParagraphs} (Page ${_currentReadingSession.currentParagraph?.pageNumber ?? 1})",
                              style: const TextStyle(fontSize: 10, color: Colors.white54),
                            ),
                            Text(
                              _currentReadingSession.status.name.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _currentReadingSession.isPlaying
                                    ? const Color(0xFF76FF03)
                                    : Colors.orangeAccent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _currentReadingSession.currentParagraph?.text ?? '',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        onPressed: _documentReaderService.previousParagraph,
                        icon: const Icon(Icons.skip_previous, color: Colors.white),
                        tooltip: "Previous Paragraph",
                      ),
                      IconButton(
                        onPressed: () {
                          if (_currentReadingSession.isPlaying) {
                            _documentReaderService.pauseReading();
                          } else {
                            _documentReaderService.resumeReading();
                          }
                        },
                        icon: Icon(
                          _currentReadingSession.isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          size: 32,
                          color: const Color(0xFF76FF03),
                        ),
                        tooltip: _currentReadingSession.isPlaying ? "Pause" : "Play",
                      ),
                      IconButton(
                        onPressed: _documentReaderService.nextParagraph,
                        icon: const Icon(Icons.skip_next, color: Colors.white),
                        tooltip: "Next Paragraph",
                      ),
                      IconButton(
                        onPressed: () {
                          final speeds = [0.8, 1.0, 1.25, 1.5, 2.0];
                          final currIdx = speeds.indexOf(_currentReadingSession.playbackSpeed);
                          final nextSpeed = speeds[(currIdx + 1) % speeds.length];
                          _documentReaderService.setPlaybackSpeed(nextSpeed);
                        },
                        icon: const Icon(Icons.speed, color: Color(0xFF00E5FF)),
                        tooltip: "Change Speed",
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            const samplePrescription =
                                "PRESCRIPTION DETAILS:\n\nTake 1 tablet of Amoxicillin 500mg by mouth twice daily with meals for 7 days.\n\nWARNING:\nFinish full course of medication even if symptoms subside.";
                            _documentReaderService.addPage(samplePrescription);
                            _documentReaderService.startReading();
                          },
                          icon: const Icon(Icons.receipt_long, size: 16),
                          label: const Text("Load Sample Prescription", style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00E5FF),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
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
}




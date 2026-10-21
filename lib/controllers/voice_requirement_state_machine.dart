import 'package:flutter/foundation.dart';

import '../models/voice_requirement_models.dart';
import '../router/voice_intent_router.dart';
import 'accessible_audio_tone_manager.dart';
import '../services/subsystems/barcode_pitch_engine.dart';
import '../services/subsystems/cloud_multimodal_vision_service.dart';
import '../services/subsystems/currency_person_engine.dart';
import '../services/subsystems/document_edge_guidance_engine.dart';
import '../services/subsystems/light_detector_engine.dart';
import '../services/subsystems/short_text_engine.dart';

typedef HardwareTorchHandler = Future<void> Function(bool enabled);
typedef SubsystemFrameHandler = Future<void> Function(Uint8List frameBytes, double luminance);

/// Central Controller & State Machine for the All-in-One Voice Requirement Router.
///
/// Ensures strict exclusivity: ONLY the user's spoken requirement subsystem receives
/// camera frames and audio channel priority, completely eliminating channel-swiping
/// and multi-engine processing conflicts.
class VoiceRequirementStateMachine extends ChangeNotifier {
  static final VoiceRequirementStateMachine _instance =
      VoiceRequirementStateMachine._internal();
  factory VoiceRequirementStateMachine() => _instance;

  final VoiceIntentRouter _router;
  final AccessibleAudioToneManager _audioManager;

  // Tier 1 & 2 Subsystem Engines
  late final ShortTextEngine shortTextEngine;
  late final LightDetectorEngine lightDetectorEngine;
  late final BarcodePitchEngine barcodePitchEngine;
  late final DocumentEdgeGuidanceEngine documentEdgeEngine;
  late final CurrencyPersonEngine currencyPersonEngine;
  late final CloudMultimodalVisionService cloudMultimodalService;

  VoiceRouterState _state = VoiceRouterState.initial();
  VoiceRouterState get state => _state;

  // Hardware Torch Callback Hook (e.g. CameraController.setFlashMode)
  HardwareTorchHandler? onHardwareTorchToggle;

  // Active Subsystem Frame Callback Hook
  SubsystemFrameHandler? onActiveSubsystemFrame;

  // Scene & QA Processing Flag
  bool _isAwaitingSceneAnalysis = false;
  String _pendingSceneQuery = "";

  // Low Light Sentinel State
  DateTime _lastLowLightWarningTime = DateTime.fromMillisecondsSinceEpoch(0);
  int _consecutiveDarkFrames = 0;

  VoiceRequirementStateMachine._internal({
    VoiceIntentRouter? router,
    AccessibleAudioToneManager? audioManager,
    ShortTextEngine? shortText,
    LightDetectorEngine? lightDetector,
    BarcodePitchEngine? barcodePitch,
    DocumentEdgeGuidanceEngine? documentEdge,
    CurrencyPersonEngine? currencyPerson,
    CloudMultimodalVisionService? cloudMultimodal,
  })  : _router = router ?? VoiceIntentRouter(),
        _audioManager = audioManager ?? AccessibleAudioToneManager() {
    cloudMultimodalService = cloudMultimodal ?? CloudMultimodalVisionService(audioManager: _audioManager);
    shortTextEngine = shortText ?? ShortTextEngine(audioManager: _audioManager);
    lightDetectorEngine = lightDetector ?? LightDetectorEngine(audioManager: _audioManager);
    barcodePitchEngine = barcodePitch ?? BarcodePitchEngine(audioManager: _audioManager);
    documentEdgeEngine = documentEdge ?? DocumentEdgeGuidanceEngine(audioManager: _audioManager);
    currencyPersonEngine = currencyPerson ??
        CurrencyPersonEngine(
          audioManager: _audioManager,
          multimodalService: cloudMultimodalService,
        );
  }

  VoiceRequirementStateMachine.withDependencies({
    required VoiceIntentRouter router,
    required AccessibleAudioToneManager audioManager,
    ShortTextEngine? shortText,
    LightDetectorEngine? lightDetector,
    BarcodePitchEngine? barcodePitch,
    DocumentEdgeGuidanceEngine? documentEdge,
    CurrencyPersonEngine? currencyPerson,
    CloudMultimodalVisionService? cloudMultimodal,
  })  : _router = router,
        _audioManager = audioManager {
    cloudMultimodalService = cloudMultimodal ?? CloudMultimodalVisionService(audioManager: _audioManager);
    shortTextEngine = shortText ?? ShortTextEngine(audioManager: _audioManager);
    lightDetectorEngine = lightDetector ?? LightDetectorEngine(audioManager: _audioManager);
    barcodePitchEngine = barcodePitch ?? BarcodePitchEngine(audioManager: _audioManager);
    documentEdgeEngine = documentEdge ?? DocumentEdgeGuidanceEngine(audioManager: _audioManager);
    currencyPersonEngine = currencyPerson ??
        CurrencyPersonEngine(
          audioManager: _audioManager,
          multimodalService: cloudMultimodalService,
        );
  }

  // ---------------------------------------------------------------------------
  // 1. Spoken Requirement Ingestion & Intent Dispatch (<50ms)
  // ---------------------------------------------------------------------------

  /// Processes a user's spoken requirement, classifies the intent, and transitions
  /// camera/audio resources exclusively to that subsystem.
  Future<VoiceIntentResult> handleVoiceRequirement(String spokenRequirement) async {
    _state = _state.copyWith(
      isListening: false,
      isProcessingIntent: true,
      lastRecognizedVoice: spokenRequirement,
      statusDescription: "Routing requirement...",
    );
    notifyListeners();

    // Route intent locally in <50ms
    final intent = _router.route(spokenRequirement);

    // Mute any previous subsystem audio/tone generators
    _deactivatePreviousSubsystem(_state.activeSubsystem);

    // Activate the new subsystem
    _state = _state.copyWith(
      activeSubsystem: intent.subsystem,
      isProcessingIntent: false,
      statusDescription: "${intent.subsystem.displayName} Active",
      telemetry: {
        'lastIntent': intent.intentType,
        'confidence': intent.confidence,
        'latencyMs': intent.latencyMs,
        'parameters': intent.parameters,
      },
    );
    notifyListeners();

    // Provide immediate spoken confirmation to user
    await _audioManager.speak(
      intent.subsystem.spokenConfirmation,
      interrupt: true,
      cacheForReplay: true,
    );

    // If Light Detector was selected, immediately initialize continuous tone
    if (intent.subsystem == VoiceSubsystem.lightDetector) {
      _audioManager.setLightDetectorFrequency(_state.luminance);
    }

    // If Scene QA was selected, flag pending query for the next camera frame
    if (intent.subsystem == VoiceSubsystem.sceneQa) {
      _isAwaitingSceneAnalysis = true;
      _pendingSceneQuery = spokenRequirement;
    }

    return intent;
  }

  /// Deactivates any persistent tones, sonar, or beeps from the previous subsystem.
  void _deactivatePreviousSubsystem(VoiceSubsystem previous) {
    switch (previous) {
      case VoiceSubsystem.lightDetector:
        _audioManager.stopLightDetectorTone();
        lightDetectorEngine.stop();
        break;
      case VoiceSubsystem.barcode:
        _audioManager.stopBarcodeBeep();
        barcodePitchEngine.stop();
        break;
      case VoiceSubsystem.shortText:
        shortTextEngine.reset();
        break;
      case VoiceSubsystem.document:
        documentEdgeEngine.reset();
        break;
      case VoiceSubsystem.currencyPerson:
        currencyPersonEngine.reset();
        break;
      case VoiceSubsystem.sceneQa:
        _audioManager.stopCloudWaitingSonar();
        _isAwaitingSceneAnalysis = false;
        break;
      default:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // 2. Hardware Flashlight Toggle (WCAG AAA Double-Tap Anywhere)
  // ---------------------------------------------------------------------------

  /// Immediately toggles camera hardware torch ON or OFF.
  /// Triggers distinct double-haptic click and announces state aloud.
  Future<bool> toggleFlashlight() async {
    final newTorchState = !_state.torchActive;

    // 1. Double-haptic tactile click
    await _audioManager.triggerFlashlightHaptic();

    // 2. Hardware camera torch execution
    if (onHardwareTorchToggle != null) {
      try {
        await onHardwareTorchToggle!(newTorchState);
      } catch (e) {
        debugPrint("Hardware torch switch error: $e");
      }
    }

    // 3. State update
    _state = _state.copyWith(torchActive: newTorchState);
    notifyListeners();

    // 4. Spoken confirmation
    final speechText = newTorchState ? "Flashlight on." : "Flashlight off.";
    await _audioManager.speak(speechText, interrupt: true, cacheForReplay: false);

    return newTorchState;
  }

  // ---------------------------------------------------------------------------
  // 3. Live Frame Processor & Low-Light Sentinel
  // ---------------------------------------------------------------------------

  /// Ingests live camera frames (1-5 FPS) and metadata from the camera feed.
  /// Only forwards the frame to the active subsystem.
  Future<void> processCameraFrame(Uint8List frameBytes, double luminance) async {
    final isLowLight = luminance < 0.08;

    _state = _state.copyWith(
      luminance: luminance,
      isLowLight: isLowLight,
    );

    // Dynamic pitch update if Light Detector is the active engine
    if (_state.activeSubsystem == VoiceSubsystem.lightDetector) {
      _audioManager.setLightDetectorFrequency(luminance);
    }

    // Automatic Low-Light Warning (if camera view is near zero and torch is off)
    if (isLowLight && !_state.torchActive) {
      _consecutiveDarkFrames++;
      final now = DateTime.now();
      if (_consecutiveDarkFrames > 3 &&
          now.difference(_lastLowLightWarningTime).inSeconds > 15) {
        _lastLowLightWarningTime = now;
        _consecutiveDarkFrames = 0;
        await _audioManager.speak(
          "Too dark, double-tap the screen to turn on the flashlight.",
          interrupt: false,
          cacheForReplay: false,
        );
      }
    } else {
      _consecutiveDarkFrames = 0;
    }

    // Forward frame strictly to the active subsystem
    switch (_state.activeSubsystem) {
      case VoiceSubsystem.shortText:
        await shortTextEngine.processFrame(frameBytes);
        break;
      case VoiceSubsystem.lightDetector:
        lightDetectorEngine.processFrame(frameBytes, luminance);
        break;
      case VoiceSubsystem.barcode:
        await barcodePitchEngine.processFrame(frameBytes);
        break;
      case VoiceSubsystem.document:
        await documentEdgeEngine.processFrame(frameBytes);
        break;
      case VoiceSubsystem.currencyPerson:
        final focus = _state.telemetry['parameters']?['targetFocus'] as String? ?? 'currency';
        await currencyPersonEngine.processFrame(frameBytes, focus: focus);
        break;
      case VoiceSubsystem.sceneQa:
        if (_isAwaitingSceneAnalysis) {
          _isAwaitingSceneAnalysis = false;
          final intentTag = _pendingSceneQuery.toLowerCase().contains('find') ||
                  _pendingSceneQuery.toLowerCase().contains('where')
              ? '[INTENT: USER_QUESTION]'
              : '[INTENT: SCENE]';
          await cloudMultimodalService.processRequirement(
            requirement: _pendingSceneQuery,
            intentTag: intentTag,
            imageBytes: frameBytes,
          );
        }
        break;
      default:
        break;
    }

    if (_state.activeSubsystem != VoiceSubsystem.none &&
        onActiveSubsystemFrame != null) {
      await onActiveSubsystemFrame!(frameBytes, luminance);
    }
  }

  // ---------------------------------------------------------------------------
  // 4. State Machine Reset & Speech Actions
  // ---------------------------------------------------------------------------

  /// Cancels any active subsystem and puts the camera screen in standby mode.
  void resetToStandby() {
    _deactivatePreviousSubsystem(_state.activeSubsystem);
    _state = _state.copyWith(
      activeSubsystem: VoiceSubsystem.none,
      statusDescription: "Standing by. Tap and hold to speak a requirement.",
    );
    notifyListeners();
  }

  /// Sets cloud waiting indicator (sonar ticks and haptic pulses).
  void setWaitingForCloud(bool isWaiting) {
    _state = _state.copyWith(isWaitingForCloud: isWaiting);
    if (isWaiting) {
      _audioManager.startCloudWaitingSonar();
    } else {
      _audioManager.stopCloudWaitingSonar();
    }
    notifyListeners();
  }

  /// Updates status description for visual HUD and screen readers.
  void updateStatus(String status) {
    _state = _state.copyWith(statusDescription: status);
    notifyListeners();
  }
}

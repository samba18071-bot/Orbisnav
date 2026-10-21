import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../controllers/accessible_audio_tone_manager.dart';
import '../../controllers/voice_requirement_state_machine.dart';
import '../../router/voice_intent_router.dart';
import 'accessible_gesture_shell.dart';

/// Unified Voice Requirement Camera Screen.
///
/// Replaces all multi-channel and omni-channel swiping buttons with ONE single
/// camera viewport governed exclusively by spoken voice requirements and
/// eyes-free full-screen gestures (Double-tap flashlight, single-tap/hold voice router,
/// two-finger repeat).
class VoiceCameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const VoiceCameraScreen({
    super.key,
    required this.cameras,
  });

  @override
  State<VoiceCameraScreen> createState() => _VoiceCameraScreenState();
}

class _VoiceCameraScreenState extends State<VoiceCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  late final AccessibleAudioToneManager _audioManager;
  late final VoiceIntentRouter _router;
  late final VoiceRequirementStateMachine _stateMachine;

  bool _isCameraReady = false;
  DateTime _lastFrameTimestamp = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isProcessingFrame = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _audioManager = AccessibleAudioToneManager();
    _router = VoiceIntentRouter();
    _stateMachine = VoiceRequirementStateMachine.withDependencies(
      router: _router,
      audioManager: _audioManager,
    );

    // Wire up hardware camera torch toggle
    _stateMachine.onHardwareTorchToggle = _setCameraTorch;
    _stateMachine.documentEdgeEngine.onAutoCaptureStill = captureHighResPhoto;

    _initCamera();
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) return;

    final firstBackCamera = widget.cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => widget.cameras.first,
    );

    _cameraController = CameraController(
      firstBackCamera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      if (!mounted) return;

      setState(() {
        _isCameraReady = true;
      });

      // Stream frames at throttled 1-5 FPS rate
      await _cameraController!.startImageStream((CameraImage image) {
        _handleCameraStreamImage(image);
      });
    } catch (e) {
      debugPrint("VoiceCameraScreen camera init error: $e");
    }
  }

  void _handleCameraStreamImage(CameraImage image) {
    final now = DateTime.now();
    // Throttle to 3 FPS (333ms per frame) to prevent battery drain & CPU heat
    if (now.difference(_lastFrameTimestamp).inMilliseconds < 333 ||
        _isProcessingFrame) {
      return;
    }
    _lastFrameTimestamp = now;
    _isProcessingFrame = true;

    try {
      if (image.planes.isNotEmpty) {
        final planeBytes = image.planes.first.bytes;
        final luminance = _computeFrameLuminance(planeBytes);
        _stateMachine.processCameraFrame(planeBytes, luminance);
      }
    } catch (e) {
      debugPrint("Frame processing error: $e");
    } finally {
      _isProcessingFrame = false;
    }
  }

  /// Calculates normalized luminance (0.0 - 1.0) by sampling the Y (luminance) plane.
  double _computeFrameLuminance(Uint8List yPlaneBytes) {
    if (yPlaneBytes.isEmpty) return 0.5;
    int sum = 0;
    final step = (yPlaneBytes.length / 500).floor().clamp(1, 1000);
    int samples = 0;

    for (int i = 0; i < yPlaneBytes.length; i += step) {
      sum += yPlaneBytes[i];
      samples++;
    }

    if (samples == 0) return 0.5;
    return (sum / (samples * 255.0)).clamp(0.0, 1.0);
  }

  /// Controls camera hardware flashlight.
  Future<void> _setCameraTorch(bool enabled) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    try {
      await _cameraController!.setFlashMode(
        enabled ? FlashMode.torch : FlashMode.off,
      );
    } catch (e) {
      debugPrint("Failed to set camera torch: $e");
    }
  }

  /// Captures a high-resolution photo file on-demand.
  Future<Uint8List?> captureHighResPhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return null;
    }
    try {
      final file = await _cameraController!.takePicture();
      return await file.readAsBytes();
    } catch (e) {
      debugPrint("Photo capture error: $e");
      return null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    final CameraController? controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    if (lifecycleState == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (lifecycleState == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _stateMachine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget? cameraWidget;
    if (_isCameraReady && _cameraController != null) {
      cameraWidget = SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _cameraController!.value.previewSize?.height ?? 1,
            height: _cameraController!.value.previewSize?.width ?? 1,
            child: CameraPreview(_cameraController!),
          ),
        ),
      );
    }

    return AccessibleGestureShell(
      stateMachine: _stateMachine,
      audioManager: _audioManager,
      cameraPreview: cameraWidget,
      showVisualHud: true,
    );
  }
}

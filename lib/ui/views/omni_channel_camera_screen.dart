import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../controllers/omni_audio_manager.dart';
import '../../controllers/omni_channel_state_machine.dart';
import '../../controllers/omni_feedback_controller.dart';
import '../../services/omni_camera_frame_processor.dart';
import '../../services/omni_cloud_vision_service.dart';
import 'omni_channel_gesture_shell.dart';

/// Complete Single Omni-Channel Camera Screen.
/// The unified, evolved Seeing AI visual assistant module.
/// Replaces separate modes with ONE intelligent camera screen that automatically
/// detects context in real time and routes feedback.
class OmniChannelCameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const OmniChannelCameraScreen({
    super.key,
    required this.cameras,
  });

  @override
  State<OmniChannelCameraScreen> createState() =>
      _OmniChannelCameraScreenState();
}

class _OmniChannelCameraScreenState extends State<OmniChannelCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  late final OmniAudioManager _audioManager;
  late final OmniFeedbackController _feedbackController;
  late final OmniChannelStateMachine _stateMachine;
  late final OmniCameraFrameProcessor _frameProcessor;
  late final OmniCloudVisionService _cloudVisionService;

  bool _isCameraReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _audioManager = OmniAudioManager();
    _feedbackController = OmniFeedbackController();
    _stateMachine = OmniChannelStateMachine(
      audioManager: _audioManager,
      feedbackController: _feedbackController,
    );
    _frameProcessor = OmniCameraFrameProcessor();
    _cloudVisionService = OmniCloudVisionService();

    // Attach cloud vision service to state machine triggers
    _cloudVisionService.attachStateMachine(_stateMachine);

    // Wire up hardware torch toggle hook
    _stateMachine.onTorchToggleRequested = _setCameraTorch;
    _stateMachine.onCaptureHighResPhoto = _captureCurrentStillPhoto;

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
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      if (!mounted) return;

      setState(() {
        _isCameraReady = true;
      });

      // Start live camera stream (2-5 FPS throttled by processor)
      await _cameraController!.startImageStream((CameraImage image) {
        _handleCameraStreamImage(image);
      });
    } catch (e) {
      debugPrint("Camera initialization error: $e");
    }
  }

  void _handleCameraStreamImage(CameraImage image) {
    try {
      // Extract frame planes and delegate to local ML frame processor
      if (image.planes.isNotEmpty) {
        final planeBytes = image.planes.first.bytes;
        _frameProcessor
            .processCameraFrame(planeBytes, width: image.width, height: image.height)
            .then((bundle) {
          if (bundle != null && mounted) {
            _stateMachine.processFrame(bundle);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _setCameraTorch(bool torchOn) async {
    try {
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        await _cameraController!
            .setFlashMode(torchOn ? FlashMode.torch : FlashMode.off);
      }
    } catch (e) {
      debugPrint("Flash mode toggle note: $e");
    }
  }

  Future<Uint8List?> _captureCurrentStillPhoto() async {
    try {
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        final xFile = await _cameraController!.takePicture();
        return await xFile.readAsBytes();
      }
    } catch (e) {
      debugPrint("Error taking still photo: $e");
    }
    return null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _stateMachine.dispose();
    _frameProcessor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cameraPreviewWidget = (_isCameraReady && _cameraController != null)
        ? AspectRatio(
            aspectRatio: _cameraController!.value.aspectRatio,
            child: CameraPreview(_cameraController!),
          )
        : null;

    return OmniChannelGestureShell(
      stateMachine: _stateMachine,
      audioManager: _audioManager,
      cameraPreview: cameraPreviewWidget,
      onCaptureCurrentFrame: _captureCurrentStillPhoto,
      showVisualHud: true,
    );
  }
}

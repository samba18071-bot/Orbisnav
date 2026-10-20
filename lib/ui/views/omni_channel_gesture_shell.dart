import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../controllers/omni_audio_manager.dart';
import '../../controllers/omni_channel_state_machine.dart';
import '../../models/omni_channel_models.dart';

/// OmniChannelGestureShell:
/// Section 3 WCAG 2.1 AAA Compliant Zero-Visual Touch Target Interface.
/// The entire screen acts as a continuous gesture surface for blind and low-vision users:
/// - Single Tap: Describe current view (Scene/Person/Currency summary) OR silence TTS if speaking
/// - Double Tap: Repeat the last spoken announcement
/// - Long Press (Press & Hold): Listen to user's voice question; send audio + frame to Cloud AI
class OmniChannelGestureShell extends StatefulWidget {
  final OmniChannelStateMachine stateMachine;
  final OmniAudioManager audioManager;
  final Widget? cameraPreview;
  final Future<Uint8List?> Function()? onCaptureCurrentFrame;
  final bool showVisualHud;

  // WCAG AAA High-Contrast Palette (> 7:1 Contrast Ratio)
  static const Color kBackground = Color(0xFF0A0E17);
  static const Color kNeonCyan = Color(0xFF00E5FF);
  static const Color kSafetyYellow = Color(0xFFFFD600);
  static const Color kVibrantGreen = Color(0xFF76FF03);
  static const Color kHazardRed = Color(0xFFFF1744);
  static const Color kHighContrastWhite = Color(0xFFFFFFFF);

  const OmniChannelGestureShell({
    super.key,
    required this.stateMachine,
    required this.audioManager,
    this.cameraPreview,
    this.onCaptureCurrentFrame,
    this.showVisualHud = true,
  });

  @override
  State<OmniChannelGestureShell> createState() =>
      _OmniChannelGestureShellState();
}

class _OmniChannelGestureShellState extends State<OmniChannelGestureShell> {
  bool _isPressing = false;
  String _gestureFeedbackLabel = "Ready (Zero-Visual Touch Active)";

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.stateMachine, widget.audioManager]),
      builder: (context, _) {
        final state = widget.stateMachine.state;
        final isSpeaking = widget.audioManager.isSpeaking;
        final isListening = widget.audioManager.isListening;
        final isWaiting = state.isWaitingForCloud;

        final Color accentColor = _resolveAccentColor(state.mode, isListening);
        final String modeLabel = _resolveModeLabel(state.mode, isListening);

        return Scaffold(
          backgroundColor: OmniChannelGestureShell.kBackground,
          body: Semantics(
            container: true,
            liveRegion: true,
            label:
                "Omni-Channel Visual Cortex. Current status: $modeLabel. ${state.statusMessage}. "
                "${isSpeaking ? 'Speaking.' : 'Silent.'}",
            hint:
                "Single tap anywhere to describe view or silence speech. "
                "Double tap to repeat announcement. "
                "Press and hold to ask a voice question.",
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleSingleTap,
              onDoubleTap: _handleDoubleTap,
              onLongPress: () {},
              onLongPressStart: _handleLongPressStart,
              onLongPressEnd: _handleLongPressEnd,
              child: Stack(
                fit: StackFit.expand,
                children: [
                // 1. Live Camera Preview Layer (if provided)
                if (widget.cameraPreview != null) widget.cameraPreview!,

                // 2. High-Contrast Accessible Screen Perimeter Border (WCAG AAA)
                IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.9),
                        width: 6.0,
                      ),
                    ),
                  ),
                ),

                // 3. Visual HUD Overlay for Low-Vision Users
                if (widget.showVisualHud)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        color: OmniChannelGestureShell.kBackground
                            .withValues(alpha: 0.85),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: accentColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    modeLabel.toUpperCase(),
                                    style: TextStyle(
                                      color: accentColor,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                                if (state.isTorchActive)
                                  const Icon(
                                    Icons.flashlight_on,
                                    color: OmniChannelGestureShell.kSafetyYellow,
                                    size: 26,
                                  ),
                                if (Navigator.canPop(context))
                                  IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      color: OmniChannelGestureShell.kHighContrastWhite,
                                      size: 28,
                                    ),
                                    tooltip: "Exit Visual Assistant",
                                    onPressed: () => Navigator.of(context).pop(),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              state.statusMessage,
                              style: const TextStyle(
                                color: OmniChannelGestureShell.kHighContrastWhite,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 4. Loading indicator overlay when waiting for Cloud AI
                if (isWaiting)
                  Positioned(
                    top: 140,
                    left: 24,
                    right: 24,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: OmniChannelGestureShell.kBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: OmniChannelGestureShell.kNeonCyan,
                          width: 3,
                        ),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                OmniChannelGestureShell.kNeonCyan,
                              ),
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              "Reasoning with Cloud AI...",
                              style: TextStyle(
                                color: OmniChannelGestureShell.kNeonCyan,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 5. Active Voice Listening Banner
                if (isListening)
                  Positioned(
                    bottom: 120,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: OmniChannelGestureShell.kSafetyYellow,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.mic,
                            color: OmniChannelGestureShell.kBackground,
                            size: 32,
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              "Listening... Release to ask Cloud AI",
                              style: TextStyle(
                                color: OmniChannelGestureShell.kBackground,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 6. Bottom Accessibility Quick Hints
                Positioned(
                  bottom: 24,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: OmniChannelGestureShell.kBackground
                          .withValues(alpha: 0.90),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: OmniChannelGestureShell.kHighContrastWhite
                            .withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      _gestureFeedbackLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: OmniChannelGestureShell.kHighContrastWhite,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

  void _announceSemantics(String message) {
    try {
      if (mounted) {
        SemanticsService.sendAnnouncement(
          View.of(context),
          message,
          TextDirection.ltr,
        );
      }
    } catch (_) {}
  }

  // ===========================================================================
  // GESTURE HANDLERS (WCAG AAA ZERO-VISUAL UI)
  // ===========================================================================

  /// SINGLE TAP:
  /// - If TTS is currently speaking: Cleanly pause/silence active speech
  /// - If TTS is silent: Capture current view & ask Cloud AI for instant spatial summary
  Future<void> _handleSingleTap() async {
    if (widget.audioManager.isSpeaking) {
      await widget.audioManager.stopSpeech();
      setState(() {
        _gestureFeedbackLabel = "Speech paused.";
      });
      _announceSemantics("Speech paused.");
      return;
    }

    setState(() {
      _gestureFeedbackLabel = "Single Tap: Analyzing view...";
    });
    _announceSemantics("Analyzing view...");

    Uint8List? frameBytes;
    if (widget.onCaptureCurrentFrame != null) {
      frameBytes = await widget.onCaptureCurrentFrame!();
    }

    await widget.stateMachine.triggerOnDemandSpatialSummary(frameBytes);
  }

  /// DOUBLE TAP:
  /// Replays the last spoken announcement verbatim.
  Future<void> _handleDoubleTap() async {
    setState(() {
      _gestureFeedbackLabel = "Double Tap: Repeating announcement";
    });
    _announceSemantics("Repeating last announcement.");
    await widget.audioManager.repeatLastAnnouncement();
  }

  /// LONG PRESS START:
  /// Starts voice recording & listening for question about what the camera sees.
  Future<void> _handleLongPressStart(LongPressStartDetails details) async {
    setState(() {
      _isPressing = true;
      _gestureFeedbackLabel = "Listening... Speak your question now.";
    });
    _announceSemantics("Listening. Speak your question now.");

    await widget.audioManager.startListening(
      onResult: (words) {
        // Updated transcribed words from engine
      },
      onError: (err) {
        setState(() {
          _gestureFeedbackLabel = "Voice query error: $err";
        });
      },
    );
  }

  /// LONG PRESS END:
  /// Finishes voice recording; submits transcribed question + frame to Cloud AI.
  Future<void> _handleLongPressEnd(LongPressEndDetails details) async {
    if (!_isPressing && !widget.audioManager.isListening) return;
    _isPressing = false;
    setState(() {
      _isPressing = false;
      _gestureFeedbackLabel = "Processing question with Cloud AI...";
    });

    await widget.audioManager.stopListening();

    final query = widget.audioManager.lastRecognizedSpeech ??
        "What is in front of me right now?";

    Uint8List? frameBytes;
    if (widget.onCaptureCurrentFrame != null) {
      frameBytes = await widget.onCaptureCurrentFrame!();
    }

    await widget.stateMachine.submitVoiceQuery(
      question: query,
      frameBytes: frameBytes,
    );
  }

  // ---------------------------------------------------------------------------
  // UI Helpers
  // ---------------------------------------------------------------------------
  Color _resolveAccentColor(OmniChannelMode mode, bool isListening) {
    if (isListening) return OmniChannelGestureShell.kSafetyYellow;
    switch (mode) {
      case OmniChannelMode.barcodeDecoded:
      case OmniChannelMode.documentCapturing:
      case OmniChannelMode.shortTextReading:
        return OmniChannelGestureShell.kVibrantGreen;
      case OmniChannelMode.barcodeProximityActive:
      case OmniChannelMode.documentFramingActive:
      case OmniChannelMode.shortTextDetected:
      case OmniChannelMode.cloudProcessing:
        return OmniChannelGestureShell.kNeonCyan;
      case OmniChannelMode.lowLightTriggered:
        return OmniChannelGestureShell.kSafetyYellow;
      case OmniChannelMode.idle:
      case OmniChannelMode.monitoring:
      case OmniChannelMode.announcing:
      case OmniChannelMode.voiceListening:
        return OmniChannelGestureShell.kHighContrastWhite;
    }
  }

  String _resolveModeLabel(OmniChannelMode mode, bool isListening) {
    if (isListening) return "Voice Query Active";
    switch (mode) {
      case OmniChannelMode.idle:
        return "Idle";
      case OmniChannelMode.monitoring:
        return "Omni-Scanner Active";
      case OmniChannelMode.lowLightTriggered:
        return "Low Light / Flashlight Active";
      case OmniChannelMode.barcodeProximityActive:
        return "Centering Barcode";
      case OmniChannelMode.barcodeDecoded:
        return "Barcode Decoded";
      case OmniChannelMode.documentFramingActive:
        return "Aligning Document Corners";
      case OmniChannelMode.documentCapturing:
        return "Document Captured";
      case OmniChannelMode.shortTextDetected:
        return "Steadying Short Text";
      case OmniChannelMode.shortTextReading:
        return "Reading Text";
      case OmniChannelMode.cloudProcessing:
        return "Analyzing With Cloud AI";
      case OmniChannelMode.voiceListening:
        return "Listening to Voice";
      case OmniChannelMode.announcing:
        return "Announcing";
    }
  }
}

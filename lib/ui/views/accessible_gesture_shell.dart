import 'dart:async';
import 'package:flutter/material.dart';

import '../../controllers/accessible_audio_tone_manager.dart';
import '../../controllers/voice_requirement_state_machine.dart';
import '../../models/voice_requirement_models.dart';

/// Full-Screen Eyes-Free Gesture Shell complying with Section 3 WCAG AAA standards.
///
/// Touch Surface Architecture:
/// - DOUBLE-TAP ANYWHERE: Toggles hardware camera flashlight ON/OFF with double-haptic confirmation.
/// - SINGLE-TAP OR PRESS-AND-HOLD: Interrupts TTS, plays listening earcon, captures spoken requirement.
/// - TWO-FINGER TAP: Repeats last spoken announcement or toggles speech pause.
/// - SCREEN-READER FIRST: Full liveRegion, accessibilityLabel, and hint semantics for TalkBack & VoiceOver.
class AccessibleGestureShell extends StatefulWidget {
  final VoiceRequirementStateMachine stateMachine;
  final AccessibleAudioToneManager audioManager;
  final Widget? cameraPreview;
  final bool showVisualHud;

  // WCAG AAA High-Contrast Color Tokens (> 7:1 Contrast Ratio)
  static const Color kBackground = Color(0xFF0A0E17);
  static const Color kNeonCyan = Color(0xFF00E5FF);
  static const Color kSafetyYellow = Color(0xFFFFD600);
  static const Color kVibrantGreen = Color(0xFF76FF03);
  static const Color kHazardRed = Color(0xFFFF1744);
  static const Color kWhite = Color(0xFFFFFFFF);

  const AccessibleGestureShell({
    super.key,
    required this.stateMachine,
    required this.audioManager,
    this.cameraPreview,
    this.showVisualHud = true,
  });

  @override
  State<AccessibleGestureShell> createState() => _AccessibleGestureShellState();
}

class _AccessibleGestureShellState extends State<AccessibleGestureShell> {
  // Multi-Touch Pointer Tracking for Two-Finger Tap
  final Map<int, Offset> _activePointers = {};
  DateTime _lastPointerDownTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isTwoFingerGesture = false;

  bool _isPressAndHoldActive = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.stateMachine, widget.audioManager]),
      builder: (context, _) {
        final state = widget.stateMachine.state;
        final isListening = widget.audioManager.isListening;
        final isSpeaking = widget.audioManager.isSpeaking;
        final isWaiting = state.isWaitingForCloud;
        final activeSubsystem = state.activeSubsystem;

        final Color borderColor = _resolveBorderColor(activeSubsystem, isListening);
        final String accessibilityStatus = _buildAccessibilityDescription(state, isListening, isSpeaking);

        return Scaffold(
          backgroundColor: AccessibleGestureShell.kBackground,
          body: Semantics(
            container: true,
            liveRegion: true,
            label: accessibilityStatus,
            hint: "Double-tap to toggle flashlight. Tap or hold to speak a requirement. Two-finger tap to repeat announcement.",
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _handlePointerDown,
              onPointerUp: _handlePointerUp,
              onPointerCancel: (event) => _activePointers.remove(event.pointer),
              child: GestureDetector(
                key: const ValueKey('accessible_gesture_surface'),
                behavior: HitTestBehavior.opaque,
                onTap: _handleSingleTap,
                onDoubleTap: _handleDoubleTap,
                onLongPressStart: (_) => _handlePressAndHoldStart(),
                onLongPressEnd: (_) => _handlePressAndHoldEnd(),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 1. Live Camera Preview Layer
                    if (widget.cameraPreview != null) widget.cameraPreview!,

                    // 2. High-Contrast Accessible Screen Perimeter Border (WCAG AAA)
                    IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: borderColor.withValues(alpha: 0.95),
                            width: isListening ? 8.0 : 5.0,
                          ),
                        ),
                      ),
                    ),

                    // 3. Visual HUD Overlay for Low-Vision Users
                    if (widget.showVisualHud)
                      _buildVisualHud(
                        state: state,
                        isListening: isListening,
                        isSpeaking: isSpeaking,
                        isWaiting: isWaiting,
                        borderColor: borderColor,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Gesture Handlers
  // ---------------------------------------------------------------------------

  /// Multi-touch pointer tracking to detect clean Two-Finger Taps.
  void _handlePointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.position;
    if (_activePointers.length == 2) {
      _isTwoFingerGesture = true;
      _lastPointerDownTime = DateTime.now();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    if (_isTwoFingerGesture && _activePointers.isEmpty) {
      final elapsed = DateTime.now().difference(_lastPointerDownTime).inMilliseconds;
      if (elapsed < 350) {
        // Registered Two-Finger Tap
        _handleTwoFingerTap();
      }
      _isTwoFingerGesture = false;
    }
  }

  /// DOUBLE-TAP ANYWHERE: Hardware Flashlight Toggle.
  Future<void> _handleDoubleTap() async {
    await widget.stateMachine.toggleFlashlight();
  }

  /// SINGLE-TAP ANYWHERE: Interrupts TTS, activates Voice Requirement listener.
  Future<void> _handleSingleTap() async {
    // If speaking, first priority is immediate silence
    if (widget.audioManager.isSpeaking) {
      await widget.audioManager.stopSpeech();
      return;
    }

    await _startVoiceRequirementCapture();
  }

  /// PRESS-AND-HOLD ANYWHERE: Start Voice Requirement listener while held.
  Future<void> _handlePressAndHoldStart() async {
    _isPressAndHoldActive = true;
    await _startVoiceRequirementCapture();
  }

  /// RELEASE PRESS-AND-HOLD: Stop listening and process requirement.
  Future<void> _handlePressAndHoldEnd() async {
    if (_isPressAndHoldActive) {
      _isPressAndHoldActive = false;
      await widget.audioManager.stopListening();
    }
  }

  /// TWO-FINGER TAP ANYWHERE: Repeat last spoken announcement.
  Future<void> _handleTwoFingerTap() async {
    await widget.audioManager.repeatLastAnnouncement();
  }

  /// Activates the STT voice listener hook.
  Future<void> _startVoiceRequirementCapture() async {
    await widget.audioManager.startListening(
      onResult: (words) async {
        if (words.isNotEmpty) {
          widget.audioManager.handleSpeechRecognized(words);
          await widget.stateMachine.handleVoiceRequirement(words);
        }
      },
      onError: (error) async {
        await widget.audioManager.speak("Could not hear requirement. Please try again.");
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Accessibility & Visual HUD Helpers
  // ---------------------------------------------------------------------------

  Color _resolveBorderColor(VoiceSubsystem subsystem, bool isListening) {
    if (isListening) return AccessibleGestureShell.kSafetyYellow;
    switch (subsystem) {
      case VoiceSubsystem.shortText:
        return AccessibleGestureShell.kNeonCyan;
      case VoiceSubsystem.document:
        return const Color(0xFFE040FB); // Vivid Purple
      case VoiceSubsystem.sceneQa:
        return const Color(0xFF00E676); // Spring Green
      case VoiceSubsystem.barcode:
        return const Color(0xFFFF9100); // Amber Orange
      case VoiceSubsystem.currencyPerson:
        return const Color(0xFF2979FF); // Electric Blue
      case VoiceSubsystem.lightDetector:
        return AccessibleGestureShell.kSafetyYellow;
      case VoiceSubsystem.none:
        return AccessibleGestureShell.kWhite.withValues(alpha: 0.6);
    }
  }

  String _buildAccessibilityDescription(
    VoiceRouterState state,
    bool isListening,
    bool isSpeaking,
  ) {
    final buffer = StringBuffer();
    buffer.write("Unified Vision Camera. ");
    if (state.torchActive) buffer.write("Flashlight is on. ");
    if (isListening) {
      buffer.write("Listening for your voice requirement. Speak now. ");
    } else if (state.activeSubsystem != VoiceSubsystem.none) {
      buffer.write("${state.activeSubsystem.displayName} is active. ");
    } else {
      buffer.write("Standing by. ");
    }
    buffer.write(state.statusDescription);
    if (isSpeaking) buffer.write(". Speaking output.");
    return buffer.toString();
  }

  Widget _buildVisualHud({
    required VoiceRouterState state,
    required bool isListening,
    required bool isSpeaking,
    required bool isWaiting,
    required Color borderColor,
  }) {
    return Positioned(
      top: 50,
      left: 20,
      right: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AccessibleGestureShell.kBackground.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 2),
            ),
            child: Row(
              children: [
                Icon(
                  isListening
                      ? Icons.mic
                      : state.torchActive
                          ? Icons.flashlight_on
                          : Icons.visibility,
                  color: borderColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isListening
                            ? "LISTENING FOR REQUIREMENT..."
                            : state.activeSubsystem.displayName.toUpperCase(),
                        style: TextStyle(
                          color: borderColor,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        state.statusDescription,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AccessibleGestureShell.kWhite,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                if (state.torchActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AccessibleGestureShell.kSafetyYellow.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AccessibleGestureShell.kSafetyYellow),
                    ),
                    child: const Text(
                      "TORCH",
                      style: TextStyle(
                        color: AccessibleGestureShell.kSafetyYellow,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Speech Prompt Subtitle (if speaking)
          if (isSpeaking && widget.audioManager.currentUtterance != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                widget.audioManager.currentUtterance!,
                style: const TextStyle(
                  color: AccessibleGestureShell.kWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import '../../controllers/eyes_free_gesture_controller.dart';

/// Full-screen Eyes-Free Gesture Surface.
/// Provides zero-visual dependency interaction for Blind and Visually Impaired (BVI) users.
/// Fully compatible with iOS VoiceOver and Android TalkBack.
/// Operates 100% on-device with zero cloud or API requirements.
class EyesFreeGestureSurface extends StatefulWidget {
  final EyesFreeGestureController controller;
  final Widget? child;
  final double compassHeading;
  final int stepCount;
  final double closestObstacleDistance;
  final bool showVisualOverlay;

  const EyesFreeGestureSurface({
    super.key,
    required this.controller,
    this.child,
    this.compassHeading = 0.0,
    this.stepCount = 0,
    this.closestObstacleDistance = 5.0,
    this.showVisualOverlay = true,
  });

  @override
  State<EyesFreeGestureSurface> createState() => _EyesFreeGestureSurfaceState();
}

class _EyesFreeGestureSurfaceState extends State<EyesFreeGestureSurface> {
  int _pointerCount = 0;
  String _lastGestureFeedback = "Ready (Eyes-Free Mode)";
  Offset? _touchPosition;

  // WCAG 2.1 AAA High Contrast Palette
  static const Color kBackground = Color(0xFF0A0E17);
  static const Color kNeonCyan = Color(0xFF00E5FF);
  static const Color kSafetyYellow = Color(0xFFFFD600);

  void _onPointerDown(PointerDownEvent event) {
    setState(() {
      _pointerCount++;
      _touchPosition = event.position;
    });

    if (_pointerCount == 2) {
      // 2-Finger interaction detected
      widget.controller.handleTwoFingerDoubleTap();
      setState(() {
        _lastGestureFeedback = "2-Finger Action: Pause / Resume";
      });
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    setState(() {
      _pointerCount = (_pointerCount - 1).clamp(0, 10);
      if (_pointerCount == 0) {
        _touchPosition = null;
      }
    });
  }

  void _onPointerCancel(PointerCancelEvent event) {
    setState(() {
      _pointerCount = 0;
      _touchPosition = null;
    });
  }

  Offset _dragDelta = Offset.zero;

  void _handlePanStart(DragStartDetails details) {
    _dragDelta = Offset.zero;
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    _dragDelta += details.delta;
  }

  void _handlePanEnd(DragEndDetails details) {
    final dx = _dragDelta.dx != 0 ? _dragDelta.dx : details.velocity.pixelsPerSecond.dx;
    final dy = _dragDelta.dy != 0 ? _dragDelta.dy : details.velocity.pixelsPerSecond.dy;

    if (dx.abs() > dy.abs()) {
      // Horizontal swipe
      if (dx < -40 || details.velocity.pixelsPerSecond.dx < -200) {
        // Swipe Left: Next Mode
        widget.controller.handleSwipeNext();
        setState(() => _lastGestureFeedback = "Swiped Left: Next Mode");
      } else if (dx > 40 || details.velocity.pixelsPerSecond.dx > 200) {
        // Swipe Right: Previous Mode
        widget.controller.handleSwipePrevious();
        setState(() => _lastGestureFeedback = "Swiped Right: Previous Mode");
      }
    } else {
      // Vertical swipe
      if (dy < -40 || details.velocity.pixelsPerSecond.dy < -200) {
        // Swipe Up: Repeat last announcement
        widget.controller.handleSwipeUp();
        setState(() => _lastGestureFeedback = "Swiped Up: Repeating Speech");
      } else if (dy > 40 || details.velocity.pixelsPerSecond.dy > 200) {
        // Swipe Down: Cycle speech rate
        widget.controller.handleSwipeDown();
        setState(() => _lastGestureFeedback = "Swiped Down: Rate Changed");
      }
    }

    _dragDelta = Offset.zero;
  }

  @override
  Widget build(BuildContext context) {
    final semanticsLabel =
        "OrbisNav Eyes-Free Surface. Active. "
        "Swipe left for next mode, right for previous mode, "
        "up to repeat announcement, down to toggle speech rate. "
        "Long press anywhere for spatial compass audit. "
        "Shake device for emergency hazard alert.";

    return Semantics(
      container: true,
      focused: true,
      label: semanticsLabel,
      onScrollLeft: () => widget.controller.handleSwipeNext(),
      onScrollRight: () => widget.controller.handleSwipePrevious(),
      onScrollUp: () => widget.controller.handleSwipeUp(),
      onScrollDown: () => widget.controller.handleSwipeDown(),
      onLongPress: () => widget.controller.handleLongPress(
        compassHeading: widget.compassHeading,
        stepCount: widget.stepCount,
        closestObstacleMeters: widget.closestObstacleDistance,
      ),
      customSemanticsActions: {
        const CustomSemanticsAction(label: "Repeat Last Audio Cue"): () {
          widget.controller.handleSwipeUp();
        },
        const CustomSemanticsAction(label: "Spatial Compass Audit"): () {
          widget.controller.handleLongPress(
            compassHeading: widget.compassHeading,
            stepCount: widget.stepCount,
            closestObstacleMeters: widget.closestObstacleDistance,
          );
        },
        const CustomSemanticsAction(label: "Emergency Re-scan SOS"): () {
          widget.controller.handleShakeEmergency();
        },
      },
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        behavior: HitTestBehavior.opaque,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _handlePanStart,
          onPanUpdate: _handlePanUpdate,
          onPanEnd: _handlePanEnd,
          onLongPress: () {
            widget.controller.handleLongPress(
              compassHeading: widget.compassHeading,
              stepCount: widget.stepCount,
              closestObstacleMeters: widget.closestObstacleDistance,
            );
            setState(() => _lastGestureFeedback = "Long Press: Spatial Audit");
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.child != null) widget.child!,

              // High-Contrast Visual Overlay for Low-Vision users
              if (widget.showVisualOverlay)
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: kBackground.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kNeonCyan, width: 2.0),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _lastGestureFeedback.toUpperCase(),
                            style: const TextStyle(
                              color: kSafetyYellow,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: kNeonCyan.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: kNeonCyan),
                          ),
                          child: Text(
                            "${widget.controller.currentSpeechRate.toStringAsFixed(1)}x TTS",
                            style: const TextStyle(
                              color: kNeonCyan,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Touch Feedback ripple indicator
              if (_touchPosition != null && widget.showVisualOverlay)
                Positioned(
                  left: _touchPosition!.dx - 36,
                  top: _touchPosition!.dy - 36,
                  child: IgnorePointer(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: kNeonCyan, width: 3),
                        color: kNeonCyan.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

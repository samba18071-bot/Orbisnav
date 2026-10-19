import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/controllers/audio_mutex_controller.dart';
import 'package:orbisnav/controllers/eyes_free_gesture_controller.dart';
import 'package:orbisnav/services/sensory_haptic_service.dart';
import 'package:orbisnav/ui/views/eyes_free_gesture_surface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Module 1: Sensory Haptic Engine & Haptic Vocabulary Tests', () {
    late SensoryHapticService hapticService;

    setUp(() {
      hapticService = SensoryHapticService();
    });

    test('SensoryHapticService dispatches distinct tactile patterns', () async {
      await hapticService.triggerPattern(TactilePatternType.stopImmediately);
      expect(hapticService.lastPattern, equals(TactilePatternType.stopImmediately));

      await Future.delayed(const Duration(milliseconds: 150));
      await hapticService.triggerPattern(TactilePatternType.veerLeft);
      expect(hapticService.lastPattern, equals(TactilePatternType.veerLeft));

      await Future.delayed(const Duration(milliseconds: 150));
      await hapticService.triggerPattern(TactilePatternType.veerRight);
      expect(hapticService.lastPattern, equals(TactilePatternType.veerRight));

      await Future.delayed(const Duration(milliseconds: 150));
      await hapticService.triggerPattern(TactilePatternType.centeredOnPath);
      expect(hapticService.lastPattern, equals(TactilePatternType.centeredOnPath));

      await Future.delayed(const Duration(milliseconds: 150));
      await hapticService.triggerPattern(TactilePatternType.approachingCurb);
      expect(hapticService.lastPattern, equals(TactilePatternType.approachingCurb));
    });

    test('SensoryHapticService maps proximity distance to safety escalation', () async {
      await hapticService.triggerProximityWarning(0.8);
      expect(hapticService.lastPattern, equals(TactilePatternType.stopImmediately));

      await Future.delayed(const Duration(milliseconds: 150));
      await hapticService.triggerProximityWarning(1.9);
      expect(hapticService.lastPattern, equals(TactilePatternType.approachingCurb));

      await Future.delayed(const Duration(milliseconds: 150));
      await hapticService.triggerProximityWarning(3.5);
      expect(hapticService.lastPattern, equals(TactilePatternType.centeredOnPath));
    });
  });

  group('Module 1: Eyes-Free Gesture Controller Tests', () {
    late AudioMutexController audioMutex;
    late SensoryHapticService hapticService;
    late EyesFreeGestureController gestureController;

    setUp(() {
      audioMutex = AudioMutexController();
      hapticService = SensoryHapticService();
      gestureController = EyesFreeGestureController(
        audioMutex: audioMutex,
        hapticService: hapticService,
        initialMode: 0,
        maxModes: 4,
        enableShakeDetection: false,
      );
    });

    tearDown(() {
      gestureController.dispose();
    });

    test('Swipe left switches to next channel and dispatches haptic', () async {
      int? switchedMode;
      gestureController.onModeChanged = (mode) => switchedMode = mode;

      await gestureController.handleSwipeNext();
      expect(switchedMode, equals(1));
      expect(audioMutex.activeChannelIndex, equals(1));
      expect(hapticService.lastPattern, equals(TactilePatternType.modeSwitched));

      await gestureController.handleSwipeNext();
      expect(switchedMode, equals(2));
      expect(audioMutex.activeChannelIndex, equals(2));
    });

    test('Swipe right wraps around to previous channel', () async {
      int? switchedMode;
      gestureController.onModeChanged = (mode) => switchedMode = mode;

      await gestureController.handleSwipePrevious();
      expect(switchedMode, equals(3));
      expect(audioMutex.activeChannelIndex, equals(3));
    });

    test('Swipe up repeats last recorded message', () async {
      gestureController.recordSpokenAnnouncement("Warning: Descending staircase at 12 o'clock");
      expect(gestureController.lastSpokenSummary, contains("staircase"));

      await gestureController.handleSwipeUp();
      expect(hapticService.lastPattern, equals(TactilePatternType.actionConfirmed));
    });

    test('Swipe down cycles speech rate (1.0x -> 1.5x -> 2.0x -> 1.0x)', () async {
      expect(gestureController.currentSpeechRate, equals(1.0));

      await gestureController.handleSwipeDown();
      expect(gestureController.currentSpeechRate, equals(1.5));

      await gestureController.handleSwipeDown();
      expect(gestureController.currentSpeechRate, equals(2.0));

      await gestureController.handleSwipeDown();
      expect(gestureController.currentSpeechRate, equals(1.0));
    });

    test('Long press triggers spatial audit with compass heading and obstacle distance', () async {
      bool auditTriggered = false;
      gestureController.onSpatialAuditRequested = () => auditTriggered = true;

      await gestureController.handleLongPress(
        compassHeading: 90.0,
        stepCount: 142,
        closestObstacleMeters: 1.8,
      );

      expect(auditTriggered, isTrue);
      expect(gestureController.lastSpokenSummary, contains("Facing East"));
      expect(gestureController.lastSpokenSummary, contains("142 steps taken"));
      expect(gestureController.lastSpokenSummary, contains("1.8 meters"));
    });

    test('Emergency shake alerts sentinel and triggers critical haptic buzz', () async {
      bool sosTriggered = false;
      gestureController.onEmergencySosTriggered = () => sosTriggered = true;

      await gestureController.handleShakeEmergency();

      expect(sosTriggered, isTrue);
      expect(hapticService.lastPattern, equals(TactilePatternType.stopImmediately));
    });
  });

  group('Module 1: Eyes-Free Gesture Surface Widget & A11y Semantics Tests', () {
    late EyesFreeGestureController gestureController;

    setUp(() {
      gestureController = EyesFreeGestureController(
        initialMode: 0,
        maxModes: 4,
        enableShakeDetection: false,
      );
    });

    tearDown(() {
      gestureController.dispose();
    });

    testWidgets('EyesFreeGestureSurface renders high contrast HUD and accessibility semantics',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EyesFreeGestureSurface(
              controller: gestureController,
              compassHeading: 0.0,
              stepCount: 50,
              closestObstacleDistance: 2.5,
              child: const Center(child: Text("Camera Feed Mock")),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // Verify visual HUD elements
      expect(find.text("Camera Feed Mock"), findsOneWidget);
      expect(find.textContaining("TTS"), findsOneWidget);
      expect(find.textContaining("EYES-FREE"), findsOneWidget);

      // Verify accessibility semantics
      expect(
        find.bySemanticsLabel(RegExp(r'OrbisNav Eyes-Free Surface')),
        findsOneWidget,
      );
    });

    testWidgets('Interacting with gestures updates controller state',
        (WidgetTester tester) async {
      int mode = 0;
      gestureController.onModeChanged = (m) => mode = m;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EyesFreeGestureSurface(
              controller: gestureController,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // Simulate swipe left (drag right to left with velocity)
      await tester.fling(
        find.byType(EyesFreeGestureSurface),
        const Offset(-400, 0),
        1000,
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(mode, equals(1));
    });
  });
}

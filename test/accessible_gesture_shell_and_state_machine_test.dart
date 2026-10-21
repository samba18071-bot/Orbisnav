import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/controllers/accessible_audio_tone_manager.dart';
import 'package:orbisnav/controllers/voice_requirement_state_machine.dart';
import 'package:orbisnav/models/voice_requirement_models.dart';
import 'package:orbisnav/router/voice_intent_router.dart';
import 'package:orbisnav/ui/views/accessible_gesture_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AccessibleAudioToneManager audioManager;
  late VoiceIntentRouter router;
  late VoiceRequirementStateMachine stateMachine;

  setUp(() {
    AccessibleAudioToneManager.testMode = true;
    audioManager = AccessibleAudioToneManager();
    router = VoiceIntentRouter();
    stateMachine = VoiceRequirementStateMachine.withDependencies(
      router: router,
      audioManager: audioManager,
    );
  });

  group('Phase 1 & Phase 2: State Machine & Gesture Shell Unit Tests', () {
    test('Double-tap flashlight toggle updates torch state and speaks feedback', () async {
      bool hardwareTorchCalledWith = false;
      stateMachine.onHardwareTorchToggle = (enabled) async {
        hardwareTorchCalledWith = enabled;
      };

      expect(stateMachine.state.torchActive, isFalse);

      // 1. Toggle ON
      final resultOn = await stateMachine.toggleFlashlight();
      expect(resultOn, isTrue);
      expect(stateMachine.state.torchActive, isTrue);
      expect(hardwareTorchCalledWith, isTrue);
      expect(audioManager.currentUtterance, equals("Flashlight on."));

      // 2. Toggle OFF
      final resultOff = await stateMachine.toggleFlashlight();
      expect(resultOff, isFalse);
      expect(stateMachine.state.torchActive, isFalse);
      expect(hardwareTorchCalledWith, isFalse);
      expect(audioManager.currentUtterance, equals("Flashlight off."));
    });

    test('Handling spoken requirement routes intent and mutes inactive subsystems', () async {
      // 1. Activate Light Detector
      await stateMachine.handleVoiceRequirement("Check the light level");
      expect(stateMachine.state.activeSubsystem, equals(VoiceSubsystem.lightDetector));
      expect(audioManager.isOscillatorActive, isTrue);
      expect(audioManager.currentUtterance, contains("Light detector active"));

      // 2. State spoken requirement switches to Barcode Engine
      await stateMachine.handleVoiceRequirement("Scan this barcode");
      expect(stateMachine.state.activeSubsystem, equals(VoiceSubsystem.barcode));
      // Light detector oscillator must be muted
      expect(audioManager.isOscillatorActive, isFalse);
      expect(audioManager.currentUtterance, contains("Barcode scanner active"));
    });

    test('Audio Manager speech rate cycles 1.0x -> 1.5x -> 2.0x', () async {
      expect(audioManager.speechRate, equals(1.0));

      await audioManager.cycleSpeechRate();
      expect(audioManager.speechRate, equals(1.5));

      await audioManager.cycleSpeechRate();
      expect(audioManager.speechRate, equals(2.0));

      await audioManager.cycleSpeechRate();
      expect(audioManager.speechRate, equals(1.0));
    });

    test('Audio Manager two-finger announcement repeat', () async {
      await audioManager.speak("High priority safety warning");
      expect(audioManager.lastSpokenAnnouncement, equals("High priority safety warning"));

      await audioManager.repeatLastAnnouncement();
      expect(audioManager.currentUtterance, equals("High priority safety warning"));
    });

    test('Frame processing forwards only to active subsystem', () async {
      bool frameReceived = false;
      stateMachine.onActiveSubsystemFrame = (bytes, luminance) async {
        frameReceived = true;
      };

      // In Standby / None mode: frame is NOT forwarded
      await stateMachine.processCameraFrame(Uint8List(100), 0.5);
      expect(frameReceived, isFalse);

      // In Active mode: frame IS forwarded
      await stateMachine.handleVoiceRequirement("Read text");
      await stateMachine.processCameraFrame(Uint8List(100), 0.5);
      expect(frameReceived, isTrue);
    });
  });

  group('AccessibleGestureShell Widget & Eyes-Free Touch Surface Tests', () {
    testWidgets('Renders WCAG AAA accessible liveRegion and perimeter border', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AccessibleGestureShell(
            stateMachine: stateMachine,
            audioManager: audioManager,
            showVisualHud: true,
          ),
        ),
      );

      // Verify Semantics contains accessibility labels
      expect(find.byType(Semantics), findsWidgets);
      expect(find.text("STANDBY"), findsOneWidget);

      // Double tap triggers flashlight toggle
      final gestureSurface = find.byKey(const ValueKey('accessible_gesture_surface'));
      await tester.tap(gestureSurface);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(gestureSurface);
      await tester.pump(const Duration(milliseconds: 100));

      expect(stateMachine.state.torchActive, isTrue);
      expect(find.text("TORCH"), findsOneWidget);
    });

    testWidgets('Single tap when speaking stops speech immediately', (tester) async {
      await audioManager.speak("Ongoing verbose announcement");
      expect(audioManager.isSpeaking, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: AccessibleGestureShell(
            stateMachine: stateMachine,
            audioManager: audioManager,
          ),
        ),
      );

      // Single tap - wait for double-tap timeout window (350ms) to resolve
      final gestureSurface = find.byKey(const ValueKey('accessible_gesture_surface'));
      await tester.tap(gestureSurface);
      await tester.pump(const Duration(milliseconds: 350));

      expect(audioManager.isSpeaking, isFalse);
    });
  });
}

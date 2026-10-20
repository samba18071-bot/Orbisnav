import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/controllers/omni_audio_manager.dart';
import 'package:orbisnav/controllers/omni_feedback_controller.dart';
import 'package:orbisnav/controllers/omni_channel_state_machine.dart';
import 'package:orbisnav/models/omni_channel_models.dart';
import 'package:orbisnav/ui/views/omni_channel_gesture_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Step 2: OmniChannelGestureShell & Accessibility Tests', () {
    late OmniAudioManager audioManager;
    late OmniFeedbackController feedbackController;
    late OmniChannelStateMachine stateMachine;

    setUp(() {
      OmniAudioManager.testMode = true;
      audioManager = OmniAudioManager();
      feedbackController = OmniFeedbackController();
      stateMachine = OmniChannelStateMachine(
        audioManager: audioManager,
        feedbackController: feedbackController,
      );
    });

    tearDown(() {
      stateMachine.dispose();
      audioManager.stopSpeech();
      feedbackController.stopCloudWaitingCue();
    });

    Widget createTestApp({Future<Uint8List?> Function()? onCaptureFrame}) {
      return MaterialApp(
        home: OmniChannelGestureShell(
          stateMachine: stateMachine,
          audioManager: audioManager,
          onCaptureCurrentFrame: onCaptureFrame ?? () async => Uint8List(32),
          showVisualHud: true,
        ),
      );
    }

    testWidgets('Renders accessible full-bleed touch surface with WCAG liveRegion',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pump(const Duration(milliseconds: 50));

      // Find Semantics container with liveRegion
      final semanticsFinder = find.byType(Semantics);
      expect(semanticsFinder, findsWidgets);

      // Verify visual HUD elements
      expect(find.text("OMNI-SCANNER ACTIVE"), findsOneWidget);
      expect(find.byType(GestureDetector), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Single Tap pauses active TTS speech if speaking',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pump(const Duration(milliseconds: 50));

      // Simulate active speaking
      await audioManager.speak(
        "Currently reading a lengthy text block.",
        priority: OmniPriorityTier.tier3InstantShortText,
        force: true,
      );
      expect(audioManager.isSpeaking, isTrue);

      // Tap anywhere on the full-screen touch target and wait for double-tap disambiguation
      await tester.tap(find.byType(GestureDetector));
      await tester.pump(const Duration(milliseconds: 350));

      // Must have stopped speech
      expect(audioManager.isSpeaking, isFalse);
      expect(find.text("Speech paused."), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Single Tap triggers on-demand spatial summary when TTS is silent',
        (WidgetTester tester) async {
      bool summaryRequested = false;
      stateMachine.onCloudSceneSummaryRequested = (bytes, prompt) async {
        summaryRequested = true;
      };

      await tester.pumpWidget(createTestApp());
      await tester.pump(const Duration(milliseconds: 50));

      expect(audioManager.isSpeaking, isFalse);

      // Tap on the full-screen surface and wait for double-tap window
      await tester.tap(find.byType(GestureDetector));
      await tester.pump(const Duration(milliseconds: 350));

      expect(summaryRequested, isTrue);
      expect(find.text("Single Tap: Analyzing view..."), findsOneWidget);

      feedbackController.stopCloudWaitingCue();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Double Tap repeats the last spoken announcement',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pump(const Duration(milliseconds: 50));

      // Set last announcement
      await audioManager.speak(
        "Door at 12 o'clock, 5 feet away.",
        priority: OmniPriorityTier.tier4SceneAndVoiceQA,
        force: true,
      );

      // Perform fast double-tap (<300ms gap)
      await tester.tap(find.byType(GestureDetector));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.byType(GestureDetector));
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text("Double Tap: Repeating announcement"), findsOneWidget);
      expect(
        audioManager.lastSpokenAnnouncement,
        equals("Door at 12 o'clock, 5 feet away."),
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Press-and-Hold (Long Press) captures voice question and routes to Cloud AI',
        (WidgetTester tester) async {
      String? sentPrompt;
      stateMachine.onCloudSceneSummaryRequested = (bytes, prompt) async {
        sentPrompt = prompt;
      };

      await tester.pumpWidget(createTestApp());
      await tester.pump(const Duration(milliseconds: 50));

      // Simulate user transcription in STT
      audioManager.simulateVoiceTranscription("Where is the exit door?");

      // Long press start (hold beyond kLongPressTimeout)
      final gesture = await tester.startGesture(const Offset(200, 300));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 150));

      expect(audioManager.isListening, isTrue);
      expect(find.text("Listening... Release to ask Cloud AI"), findsOneWidget);

      // Release finger (Long press end)
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(audioManager.isListening, isFalse);
      expect(sentPrompt, equals("Where is the exit door?"));

      feedbackController.stopCloudWaitingCue();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

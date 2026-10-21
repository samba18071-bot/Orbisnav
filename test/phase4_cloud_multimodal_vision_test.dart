import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:orbisnav/controllers/accessible_audio_tone_manager.dart';
import 'package:orbisnav/controllers/voice_requirement_state_machine.dart';
import 'package:orbisnav/models/voice_requirement_models.dart';
import 'package:orbisnav/router/voice_intent_router.dart';
import 'package:orbisnav/services/subsystems/cloud_multimodal_vision_service.dart';

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

  group('Phase 4: Section 4 Embedded Vision AI System Prompt Verification', () {
    test('contains all 5 mandatory system prompt instructions and intent behaviors', () {
      expect(kEmbeddedVisionSystemPrompt, contains("ZERO FILLER"));
      expect(kEmbeddedVisionSystemPrompt, contains("NO MARKDOWN"));
      expect(kEmbeddedVisionSystemPrompt, contains("SAFETY FIRST"));
      expect(kEmbeddedVisionSystemPrompt, contains("SPATIAL CLOCK-FACE ORIENTATION"));
      expect(kEmbeddedVisionSystemPrompt, contains("[INTENT: USER_QUESTION]"));
      expect(kEmbeddedVisionSystemPrompt, contains("[INTENT: SCENE]"));
      expect(kEmbeddedVisionSystemPrompt, contains("[INTENT: DOCUMENT]"));
      expect(kEmbeddedVisionSystemPrompt, contains("[INTENT: CURRENCY]"));
      expect(kEmbeddedVisionSystemPrompt, contains("[INTENT: PERSON]"));
      expect(kEmbeddedVisionSystemPrompt, contains("[INTENT: BLURRY/OBSCURED]"));
    });
  });

  group('Phase 4: Cloud Multimodal Vision Service & Conversational Follow-Ups', () {
    test('sends system prompt, strips markdown, and saves conversational history', () async {
      String? capturedRequestBody;

      final mockClient = MockClient((request) async {
        capturedRequestBody = request.body;
        final response = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text':
                        "**Stairs straight ahead at 12 o'clock**, five steps leading down. *Hold handrail at 3 o'clock*."
                  }
                ]
              }
            }
          ]
        };
        return http.Response(jsonEncode(response), 200);
      });

      final service = CloudMultimodalVisionService(
        audioManager: audioManager,
        httpClient: mockClient,
      );
      service.setApiKey("test_gemini_key");

      final exchange = await service.processRequirement(
        requirement: "Describe the room ahead",
        intentTag: "[INTENT: SCENE]",
        imageBytes: Uint8List.fromList([1, 2, 3, 4]),
      );

      // Verify request payload injected the system prompt
      expect(capturedRequestBody, isNotNull);
      expect(capturedRequestBody, contains("system_instruction"));
      expect(capturedRequestBody, contains("ZERO FILLER"));

      // Verify ZERO MARKDOWN in final TTS spoken answer (asterisks stripped)
      expect(exchange.spokenAnswer, isNot(contains("*")));
      expect(exchange.spokenAnswer,
          equals("Stairs straight ahead at 12 o'clock, five steps leading down. Hold handrail at 3 o'clock."));
      expect(audioManager.currentUtterance, equals(exchange.spokenAnswer));

      // Verify multi-turn conversational follow-up retains frame context
      expect(service.hasActiveSceneContext, isTrue);
      expect(service.conversationHistory.length, equals(2));

      // Follow-up query without re-capturing a frame
      await service.processRequirement(
        requirement: "Are the stairs wet?",
        intentTag: "[INTENT: USER_QUESTION]",
        isFollowUp: true,
      );
      expect(service.conversationHistory.length, equals(4));
    });

    test('offline fallback synthesizes spatial layout when disconnected', () async {
      final service = CloudMultimodalVisionService(
        audioManager: audioManager,
      );
      // No API key provided -> triggers local spatial reasoning

      final exchange = await service.processRequirement(
        requirement: "What is in front of me?",
        intentTag: "[INTENT: SCENE]",
        imageBytes: Uint8List.fromList([1, 2, 3]),
      );

      expect(exchange.isFromCloud, isFalse);
      expect(exchange.spokenAnswer, contains("12 o'clock"));
      expect(audioManager.currentUtterance, contains("12 o'clock"));
    });
  });

  group('Phase 4: Subsystem 5 - Currency & Person Engine', () {
    test('identifies banknote currency denominations and note counts', () async {
      final engine = stateMachine.currencyPersonEngine;

      final result = await engine.identifyCurrency(Uint8List.fromList([1, 2, 3]));
      expect(result, contains("rupee"));
      expect(audioManager.currentUtterance, contains("rupee"));
    });

    test('locates nearby people with clock position and distance', () async {
      final engine = stateMachine.currencyPersonEngine;

      final result = await engine.locatePeople(Uint8List.fromList([1, 2, 3]));
      expect(result, contains("person"));
      expect(result, contains("12 o'clock"));
      expect(audioManager.currentUtterance, contains("person"));
    });
  });

  group('Phase 4: State Machine Integration with Scene QA and Currency Person', () {
    test('routes user question requirement to Cloud Multimodal engine with live frame', () async {
      // 1. Spoken requirement: "Find my keys"
      await stateMachine.handleVoiceRequirement("Find my keys");
      expect(stateMachine.state.activeSubsystem, equals(VoiceSubsystem.sceneQa));

      // Feed live camera frame -> immediately triggers Multimodal QA
      await stateMachine.processCameraFrame(Uint8List.fromList([10, 20, 30]), 0.6);
      expect(audioManager.currentUtterance, contains("2 o'clock"));

      // 2. Spoken requirement: "Count money"
      await stateMachine.handleVoiceRequirement("Count money");
      expect(stateMachine.state.activeSubsystem, equals(VoiceSubsystem.currencyPerson));

      await stateMachine.processCameraFrame(Uint8List.fromList([10, 20, 30]), 0.6);
      expect(audioManager.currentUtterance, contains("rupee"));
    });
  });
}

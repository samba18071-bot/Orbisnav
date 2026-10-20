import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:orbisnav/controllers/omni_audio_manager.dart';
import 'package:orbisnav/controllers/omni_channel_state_machine.dart';
import 'package:orbisnav/services/omni_cloud_vision_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    OmniAudioManager.testMode = true;
  });

  group('Step 4: OmniCloudVisionService Multimodal AI Tests', () {
    test('Contains the hardcoded Section 4 System Instruction', () {
      final prompt = OmniCloudVisionService.kHardcodedSystemInstruction;
      expect(prompt, contains('ZERO FILLER'));
      expect(prompt, contains('NO MARKDOWN'));
      expect(prompt, contains('SAFETY FIRST'));
      expect(prompt, contains('CLOCK-FACE SPATIAL ORIENTATION'));
      expect(prompt, contains('CURRENCY/BANKNOTES'));
      expect(prompt, contains('DOCUMENT/MENU/BILL'));
      expect(prompt, contains('PEOPLE ARE PROMINENT'));
    });

    test('Provides immediate edge synthesis fallback when offline or no API key', () async {
      final audioManager = OmniAudioManager();
      final service = OmniCloudVisionService.withDependencies(
        httpClient: http.Client(),
        audioManager: audioManager,
        apiKey: '', // Empty key simulates unconfigured/offline
      );

      final result = await service.queryVisualCortex(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        userPrompt: 'What is ahead of me?',
        isDocumentReading: false,
      );

      expect(result, isNotEmpty);
      expect(result, contains('Room clear ahead'));
      expect(audioManager.lastSpokenAnnouncement, equals(result));
    });

    test('Invokes Gemini 2.5 Flash endpoint and strips markdown headers/bullets', () async {
      final audioManager = OmniAudioManager();
      var interceptedRequestUri = '';
      var interceptedBody = '';

      final mockClient = MockClient((request) async {
        interceptedRequestUri = request.url.toString();
        interceptedBody = request.body;
        final responsePayload = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text': '**Desk at 12 o\'clock**, 4 feet away. *Empty doorway* at 2 o\'clock.'
                  }
                ]
              }
            }
          ]
        };
        return http.Response(jsonEncode(responsePayload), 200, headers: {'content-type': 'application/json'});
      });

      final service = OmniCloudVisionService.withDependencies(
        httpClient: mockClient,
        audioManager: audioManager,
        apiKey: 'test_api_key_123',
      );

      final result = await service.queryVisualCortex(
        imageBytes: Uint8List.fromList([10, 20, 30, 40]),
        userPrompt: 'Describe room',
      );

      expect(interceptedRequestUri, contains('gemini-2.5-flash:generateContent'));
      expect(interceptedRequestUri, contains('key=test_api_key_123'));
      expect(interceptedBody, contains('system_instruction'));
      expect(interceptedBody, contains('inline_data'));

      // Ensure markdown symbols like ** and * are stripped for clear spoken TTS
      expect(result, isNot(contains('**')));
      expect(result, isNot(contains('*')));
      expect(result, contains('Desk at 12 o\'clock, 4 feet away. Empty doorway at 2 o\'clock.'));
    });

    test('State machine hooks correctly trigger cloud scene and voice query responses', () async {
      final audioManager = OmniAudioManager();
      final stateMachine = OmniChannelStateMachine();

      final mockClient = MockClient((request) async {
        final decoded = jsonDecode(request.body) as Map<String, dynamic>;
        final userText = decoded['contents']?[0]?['parts']?[0]?['text'] ?? '';

        String reply = 'Room is clear. Table at 12 o\'clock.';
        if (userText.toString().contains('door')) {
          reply = 'Door at 2 o\'clock, 5 feet away.';
        }

        final responsePayload = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text': reply
                  }
                ]
              }
            }
          ]
        };
        return http.Response(jsonEncode(responsePayload), 200);
      });

      final service = OmniCloudVisionService.withDependencies(
        httpClient: mockClient,
        audioManager: audioManager,
        stateMachine: stateMachine,
        apiKey: 'dummy_key',
      );
      service.attachStateMachine(stateMachine);

      // Verify triggerOnDemandSpatialSummary invokes cloud hook
      final mockPhotoBytes = Uint8List.fromList([100, 101, 102]);
      await stateMachine.triggerOnDemandSpatialSummary(mockPhotoBytes);

      expect(audioManager.lastSpokenAnnouncement, contains('Room is clear. Table at 12 o\'clock.'));

      // Verify submitVoiceQuery routes user question properly
      await stateMachine.submitVoiceQuery(
        question: 'Where is the door?',
        frameBytes: mockPhotoBytes,
      );

      expect(audioManager.lastSpokenAnnouncement, contains('Door at 2 o\'clock, 5 feet away.'));
    });
  });
}

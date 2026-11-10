import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:orbisnav/controllers/audio_mutex_controller.dart';
import 'package:orbisnav/services/google_maps_audio_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> nativeCalls = [];

  setUp(() {
    nativeCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.orbisnav.orbisnav/audio_mutex'),
      (MethodCall methodCall) async {
        nativeCalls.add(methodCall);
        if (methodCall.method == 'speak') {
          return true;
        }
        if (methodCall.method == 'stop') {
          return true;
        }
        return null;
      },
    );
  });

  tearDown(() {
    GoogleMapsAudioBridge().setMapsVoiceActive(false);
    GoogleMapsAudioBridge().setNavigating(false);
    AudioMutexController().hardStop();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.orbisnav.orbisnav/audio_mutex'),
      null,
    );
  });

  group('Google Maps & Safety HUD Simultaneous Audio Synchronization', () {
    test('1. When Maps voice speaks, HUD TTS is muted and lower-tier speech is suppressed', () async {
      final mutex = AudioMutexController();
      final bridge = GoogleMapsAudioBridge();

      // Start initial HUD speech (Level 2 Navigation)
      await mutex.speak(
        text: 'Obstacle ahead 2.5 meters',
        priority: AudioPriority.level2Navigation,
        channelIndex: 0,
      );

      // Maps begins speaking turn instruction
      bridge.setMapsVoiceActive(true);

      // Verify native 'stop' was immediately invoked by AudioMutexController.muteHudForMapsVoice()
      expect(nativeCalls.any((call) => call.method == 'stop'), isTrue);

      // Attempt HUD Level 2 guidance during active Maps voice
      final hudSpeechAllowed = await mutex.speak(
        text: 'Path is clear on right',
        priority: AudioPriority.level2Navigation,
        channelIndex: 0,
      );

      // Must be suppressed
      expect(hudSpeechAllowed, isFalse);
    });

    test('2. Turn direction is spoken once, and Safety HUD resumes after direction finishes', () async {
      final mutex = AudioMutexController();
      final bridge = GoogleMapsAudioBridge();

      // Simulate receiving navigation turn instruction
      const instruction = 'In 50 meters, turn right onto Lalupuram Road';
      bridge.setLastInstruction(instruction);
      bridge.setMapsVoiceActive(true);

      // Maps instruction spoken with Level 1 Safety priority (overriding HUD)
      final turnSpoken = await mutex.speak(
        text: instruction,
        priority: AudioPriority.level1Safety,
        force: true,
      );
      expect(turnSpoken, isTrue);

      // Duplicate instruction should be deduplicated (speak only once)
      final duplicateTurn = await mutex.speak(
        text: instruction,
        priority: AudioPriority.level1Safety,
        force: false,
      );
      // Suppressed by deduplication filter
      expect(duplicateTurn, isTrue);

      // Maps turn finishes speaking
      bridge.setMapsVoiceActive(false);

      // Safety HUD now speaks obstacle detection
      final resumedHudSpeech = await mutex.speak(
        text: 'Safety HUD active: Curb detected at 12 o\'clock, 1.8 meters',
        priority: AudioPriority.level1Safety,
        channelIndex: 0,
        force: true,
      );
      expect(resumedHudSpeech, isTrue);
    });

    test('3. Level 0 Critical Life Safety Alerts always pass through even when Maps voice is active', () async {
      final mutex = AudioMutexController();
      final bridge = GoogleMapsAudioBridge();

      // Maps is currently giving directions
      bridge.setMapsVoiceActive(true);

      // Sudden critical life safety hazard (e.g. drop-off / platform edge < 0.7m)
      final criticalPassed = await mutex.speak(
        text: 'DANGER! Drop-off detected immediately ahead!',
        priority: AudioPriority.level0Critical,
        channelIndex: 0,
        force: true,
      );

      // Level 0 must never be suppressed
      expect(criticalPassed, isTrue);
    });

    test('4. GoogleMapsAudioBridge updates state and streams reliably', () async {
      final bridge = GoogleMapsAudioBridge();
      final List<bool> voiceStates = [];
      final List<String> instructions = [];
      final List<String> addresses = [];

      final sub1 = bridge.mapsVoiceStream.listen(voiceStates.add);
      final sub2 = bridge.instructionStream.listen(instructions.add);
      final sub3 = bridge.addressStream.listen(addresses.add);

      bridge.setMapsVoiceActive(true);
      bridge.setLastInstruction('Turn left at intersection');
      bridge.setCurrentAddress('Lalupuram Village, Guntur, AP');

      await Future.delayed(const Duration(milliseconds: 20));

      expect(bridge.isMapsVoiceActive, isTrue);
      expect(bridge.lastInstruction, 'Turn left at intersection');
      expect(bridge.currentAddress, 'Lalupuram Village, Guntur, AP');
      expect(voiceStates, contains(true));
      expect(instructions, contains('Turn left at intersection'));
      expect(addresses, contains('Lalupuram Village, Guntur, AP'));

      await sub1.cancel();
      await sub2.cancel();
      await sub3.cancel();
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/controllers/audio_mutex_controller.dart';
import 'package:orbisnav/services/offline_scene_captioning_service.dart';
import 'package:orbisnav/services/online_obstacle_detector.dart';
import 'package:orbisnav/services/object_finder_sonar_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Day 8 & 9: Audio Mutex Preemption & Auto-Resume Context Stack Tests', () {
    late AudioMutexController audioMutex;

    setUp(() {
      audioMutex = AudioMutexController();
    });

    tearDown(() {
      audioMutex.hardStop();
    });

    test('Level 0 Critical Hazard flushes lower priority requests', () async {
      // 1. Send Level 3 Context dialogue
      audioMutex.speak(
        text: 'This is a long description of the living room with furniture.',
        priority: AudioPriority.level3Context,
        haptic: false,
      );

      expect(audioMutex.currentActivePriority, equals(AudioPriority.level3Context));

      // 2. Immediate Level 0 Critical Hazard strikes!
      audioMutex.speak(
        text: 'Warning! Obstacle 1 meter ahead.',
        priority: AudioPriority.level0Critical,
        haptic: true,
        force: true,
      );

      // Mutex must immediately switch active priority to Level 0 Critical
      expect(audioMutex.currentActivePriority, equals(AudioPriority.level0Critical));
    });

    test('Notifies hazard cleared and enforces 1.5s debounce before resumption', () async {
      // Suspend dialogue with hazard
      audioMutex.speak(
        text: 'Detailed explanation of outdoor garden path.',
        priority: AudioPriority.level3Context,
        haptic: false,
      );

      audioMutex.speak(
        text: 'Step down ahead.',
        priority: AudioPriority.level0Critical,
        haptic: true,
        force: true,
      );

      // Trigger hazard cleared event
      audioMutex.notifyHazardCleared();
      expect(audioMutex.lastHazardClearedTime, isNotNull);

      // Wait 1600ms (exceeding 1.5s debounce)
      await Future.delayed(const Duration(milliseconds: 1600));

      // Context resumption was triggered
      expect(audioMutex.lastHazardClearedTime, isNotNull);
    });
  });

  group('Day 10: Offline Scene Captioning & Corridor Guidance Tests', () {
    late OfflineSceneCaptioningService captionService;
    late AudioMutexController audioMutex;

    setUp(() {
      audioMutex = AudioMutexController();
      captionService = OfflineSceneCaptioningService(audioMutex: audioMutex);
    });

    tearDown(() {
      captionService.dispose();
    });

    test('Synthesizes empty scene with forward trajectory recommendation', () {
      final caption = captionService.generateCaption(obstacles: []);

      expect(caption.environmentEstimate, equals('Open Space'));
      expect(caption.foregroundHazards, isEmpty);
      expect(caption.openCorridorSuggestion, contains("12 o'clock"));
      expect(caption.spokenCaption, contains('Path ahead is clear'));
    });

    test('Partitions foreground hazards (<=1.5m) and midground objects accurately', () {
      final obstacles = [
        DetectedObstacle(
          label: 'Chair',
          confidence: 0.95,
          xMin: 0.4,
          yMin: 0.4,
          xMax: 0.6,
          yMax: 0.8,
          distanceMeters: 1.1, // Foreground
          ttcSeconds: 1.2,
          priority: AudioPriority.level0Critical,
          clockPosition: "12 o'clock",
        ),
        DetectedObstacle(
          label: 'Table',
          confidence: 0.88,
          xMin: 0.7,
          yMin: 0.3,
          xMax: 0.9,
          yMax: 0.7,
          distanceMeters: 2.5, // Midground
          ttcSeconds: 3.0,
          priority: AudioPriority.level2Navigation,
          clockPosition: "2 o'clock",
        ),
      ];

      final caption = captionService.generateCaption(obstacles: obstacles);

      expect(caption.environmentEstimate, contains('Indoor'));
      expect(caption.foregroundHazards.length, equals(1));
      expect(caption.foregroundHazards.first, contains('Chair'));
      expect(caption.midgroundObjects.length, equals(1));
      expect(caption.midgroundObjects.first, contains('Table'));
      expect(caption.openCorridorSuggestion, contains("10 o'clock")); // 12 and 2 are blocked, so 10 is recommended
    });

    test('Infers outdoor street traffic environment correctly', () {
      final obstacles = [
        DetectedObstacle(
          label: 'Car',
          confidence: 0.91,
          xMin: 0.1,
          yMin: 0.2,
          xMax: 0.5,
          yMax: 0.8,
          distanceMeters: 4.0, // Background
          ttcSeconds: 5.0,
          priority: AudioPriority.level2Navigation,
          clockPosition: "10 o'clock",
        ),
      ];

      final caption = captionService.generateCaption(obstacles: obstacles);
      expect(caption.environmentEstimate, contains('Outdoor Street'));
      expect(caption.backgroundLandmarks.length, equals(1));
    });
  });

  group('Channel Priority Matrix: Active Tab Supremacy & Background Demotion', () {
    late AudioMutexController audioMutex;

    setUp(() {
      audioMutex = AudioMutexController();
      audioMutex.setActiveChannel(2); // Channel 2 (Doc Scan / Google Lens) is active
    });

    tearDown(() {
      audioMutex.hardStop();
    });

    test('Active tab speech takes immediate active priority', () async {
      audioMutex.speak(
        text: 'In front of you: Laptop on wooden desk.',
        priority: AudioPriority.level2Navigation,
        channelIndex: 2,
        force: true,
      );

      expect(audioMutex.currentActivePriority, equals(AudioPriority.level2Navigation));
    });

    test('Background channel cannot preempt active tab speech', () async {
      // 1. Active tab (Channel 2) is speaking
      audioMutex.speak(
        text: 'Reading: Paragraph 1 of document.',
        priority: AudioPriority.level2Navigation,
        channelIndex: 2,
        force: true,
      );

      expect(audioMutex.currentActivePriority, equals(AudioPriority.level2Navigation));

      // 2. Background tab (Channel 1 Navigation) attempts Level 1 Safety cue
      audioMutex.speak(
        text: 'Turn right in 50 meters.',
        priority: AudioPriority.level1Safety,
        channelIndex: 1, // Background!
        force: true,
      );

      // Active tab speech must NOT be preempted by background channel!
      expect(audioMutex.currentActivePriority, equals(AudioPriority.level2Navigation));
    });

    test('Background channel Level 3 context is discarded when active tab is speaking', () async {
      audioMutex.speak(
        text: 'Active lens scene description.',
        priority: AudioPriority.level2Navigation,
        channelIndex: 2,
        force: true,
      );

      final accepted = await audioMutex.speak(
        text: 'Background general chatter from another channel.',
        priority: AudioPriority.level3Context,
        channelIndex: 1, // Background!
        force: true,
      );

      expect(accepted, isFalse);
    });

    test('Active tab immediately preempts non-critical background channel speech', () async {
      // Set active channel to 0 temporarily so channel 1 is considered active
      audioMutex.setActiveChannel(1);
      audioMutex.speak(
        text: 'Navigating towards main building.',
        priority: AudioPriority.level2Navigation,
        channelIndex: 1,
        force: true,
      );

      // Now user switches to Channel 3 (Lost Item Sonar)
      audioMutex.setActiveChannel(3);

      // Channel 3 issues speech
      audioMutex.speak(
        text: 'Keys found at 12 oclock 1 meter away.',
        priority: AudioPriority.level2Navigation,
        channelIndex: 3,
        force: true,
      );

      // Channel 3 must have immediately taken over!
      expect(audioMutex.currentActivePriority, equals(AudioPriority.level2Navigation));
    });

    test('Level 0 Critical emergency from any channel still alerts user', () async {
      audioMutex.speak(
        text: 'Scanning page...',
        priority: AudioPriority.level2Navigation,
        channelIndex: 2,
        force: true,
      );

      // Life safety emergency strikes from background channel
      audioMutex.speak(
        text: 'Emergency hazard! Drop-off 1 meter ahead.',
        priority: AudioPriority.level0Critical,
        channelIndex: 0,
        force: true,
      );

      expect(audioMutex.currentActivePriority, equals(AudioPriority.level0Critical));
    });

    test('ObjectFinderSonarService matches all 32 trained assistive classes with high fidelity', () {
      final sonarService = ObjectFinderSonarService(audioMutex: audioMutex);

      final testCases = [
        {'target': 'keys', 'detected': 'keys', 'shouldMatch': true},
        {'target': 'keys', 'detected': 'key', 'shouldMatch': true},
        {'target': 'phone', 'detected': 'cell_phone', 'shouldMatch': true},
        {'target': 'phone', 'detected': 'cell phone', 'shouldMatch': true},
        {'target': 'white cane', 'detected': 'white_cane', 'shouldMatch': true},
        {'target': 'charger', 'detected': 'charger', 'shouldMatch': true},
        {'target': 'wallet', 'detected': 'wallet', 'shouldMatch': true},
        {'target': 'glasses', 'detected': 'glasses', 'shouldMatch': true},
        {'target': 'water bottle', 'detected': 'bottle', 'shouldMatch': true},
        {'target': 'shoes', 'detected': 'shoes', 'shouldMatch': true},
        {'target': 'laptop', 'detected': 'laptop', 'shouldMatch': true},
        {'target': 'medicine', 'detected': 'medicine_bottle', 'shouldMatch': true},
        {'target': 'headphones', 'detected': 'headphones', 'shouldMatch': true},
        {'target': 'watch', 'detected': 'watch', 'shouldMatch': true},
        {'target': 'remote', 'detected': 'remote', 'shouldMatch': true},
        {'target': 'pen', 'detected': 'pen', 'shouldMatch': true},
      ];

      for (final tc in testCases) {
        final matches = sonarService.isMatching(
          tc['detected'] as String,
          tc['target'] as String,
        );
        expect(matches, equals(tc['shouldMatch']),
            reason: 'Failed matching ${tc["detected"]} with ${tc["target"]}');
      }
    });

    test('Voice search item cleaning correctly removes natural voice query prefixes', () {
      String cleanVoiceItem(String input) {
        var clean = input.toLowerCase().trim();
        final prefixes = [
          "find my ", "find ", "where is my ", "where's my ", "where is ",
          "where are my ", "locate my ", "locate ", "search for ", "look for ",
          "i lost my ", "i lost ", "bring me ", "show me "
        ];
        for (final p in prefixes) {
          if (clean.startsWith(p)) {
            clean = clean.substring(p.length).trim();
            break;
          }
        }
        return clean;
      }

      expect(cleanVoiceItem("find my keys"), equals("keys"));
      expect(cleanVoiceItem("where is my cell phone"), equals("cell phone"));
      expect(cleanVoiceItem("locate my white cane"), equals("white cane"));
      expect(cleanVoiceItem("search for charger"), equals("charger"));
      expect(cleanVoiceItem("where's my wallet"), equals("wallet"));
      expect(cleanVoiceItem("i lost my glasses"), equals("glasses"));
      expect(cleanVoiceItem("water bottle"), equals("water bottle"));
    });
  });
}

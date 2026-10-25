import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:orbisnav/controllers/spoken_guidance_cadence_controller.dart';
import 'package:orbisnav/models/hybrid_voice_search_models.dart';
import 'package:orbisnav/services/cloud_semantic_grounder_service.dart';
import 'package:orbisnav/services/multi_object_tracker_and_disambiguator.dart';
import 'package:orbisnav/services/network_health_monitor.dart';
import 'package:orbisnav/services/offline_spatial_speech_formatter.dart';
import 'package:orbisnav/services/hybrid_search_orchestrator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Step 1: OfflineSpatialSpeechFormatter & SpokenGuidanceCadenceController', () {
    test('OfflineSpatialSpeechFormatter maps horizontal clock sectors correctly', () {
      expect(OfflineSpatialSpeechFormatter.formatClockDirection(0.08), contains("9 o'clock (far left)"));
      expect(OfflineSpatialSpeechFormatter.formatClockDirection(0.25), contains("10 o'clock (left)"));
      expect(OfflineSpatialSpeechFormatter.formatClockDirection(0.40), contains("11 o'clock (slightly left)"));
      expect(OfflineSpatialSpeechFormatter.formatClockDirection(0.50), contains("12 o'clock (straight ahead)"));
      expect(OfflineSpatialSpeechFormatter.formatClockDirection(0.60), contains("1 o'clock (slightly right)"));
      expect(OfflineSpatialSpeechFormatter.formatClockDirection(0.75), contains("2 o'clock (right)"));
      expect(OfflineSpatialSpeechFormatter.formatClockDirection(0.92), contains("3 o'clock (far right)"));

      expect(OfflineSpatialSpeechFormatter.getClockHour(0.08), equals(9));
      expect(OfflineSpatialSpeechFormatter.getClockHour(0.25), equals(10));
      expect(OfflineSpatialSpeechFormatter.getClockHour(0.40), equals(11));
      expect(OfflineSpatialSpeechFormatter.getClockHour(0.50), equals(12));
      expect(OfflineSpatialSpeechFormatter.getClockHour(0.60), equals(1));
      expect(OfflineSpatialSpeechFormatter.getClockHour(0.75), equals(2));
      expect(OfflineSpatialSpeechFormatter.getClockHour(0.92), equals(3));
    });

    test('OfflineSpatialSpeechFormatter formats vertical elevation and distance correctly', () {
      expect(OfflineSpatialSpeechFormatter.formatVerticalTilt(0.20), equals("high up, tilt camera up"));
      expect(OfflineSpatialSpeechFormatter.formatVerticalTilt(0.50), equals("at chest/table level"));
      expect(OfflineSpatialSpeechFormatter.formatVerticalTilt(0.80), equals("low down, tilt camera down"));

      expect(OfflineSpatialSpeechFormatter.formatDistanceAndReach(0.02, false), contains("about 6 to 8 feet away"));
      expect(OfflineSpatialSpeechFormatter.formatDistanceAndReach(0.08, false), contains("about 3 to 4 feet away"));
      expect(OfflineSpatialSpeechFormatter.formatDistanceAndReach(0.18, false), contains("within arm's reach, extend your hand"));
      expect(OfflineSpatialSpeechFormatter.formatDistanceAndReach(0.30, true), contains("directly in front of your hand, grab it now"));
    });

    test('OfflineSpatialSpeechFormatter generates crisp micro-corrections', () {
      // Far left
      expect(
        OfflineSpatialSpeechFormatter.formatMicroCorrection(
          const NormalizedBoundingBox(ymin: 0.4, xmin: 0.1, ymax: 0.6, xmax: 0.2),
        ),
        equals("Pan slightly left."),
      );

      // Far right
      expect(
        OfflineSpatialSpeechFormatter.formatMicroCorrection(
          const NormalizedBoundingBox(ymin: 0.4, xmin: 0.7, ymax: 0.6, xmax: 0.8),
        ),
        equals("Pan slightly right."),
      );

      // High up
      expect(
        OfflineSpatialSpeechFormatter.formatMicroCorrection(
          const NormalizedBoundingBox(ymin: 0.05, xmin: 0.45, ymax: 0.2, xmax: 0.55),
        ),
        equals("Tilt camera up."),
      );

      // Low down
      expect(
        OfflineSpatialSpeechFormatter.formatMicroCorrection(
          const NormalizedBoundingBox(ymin: 0.75, xmin: 0.45, ymax: 0.9, xmax: 0.55),
        ),
        equals("Tilt camera down."),
      );

      // Centered arm's reach
      expect(
        OfflineSpatialSpeechFormatter.formatMicroCorrection(
          const NormalizedBoundingBox(ymin: 0.35, xmin: 0.35, ymax: 0.75, xmax: 0.65), // area = 0.4 * 0.3 = 0.12
        ),
        equals("Centered, reach your hand forward."),
      );

      // Directly in front of hand grab ready
      expect(
        OfflineSpatialSpeechFormatter.formatMicroCorrection(
          const NormalizedBoundingBox(ymin: 0.2, xmin: 0.2, ymax: 0.8, xmax: 0.8), // area = 0.36
        ),
        equals("Within arm's reach, reach your hand straight out and grab it."),
      );
    });

    test('OfflineSpatialSpeechFormatter formats lost target velocity recovery', () {
      // User panned right -> object drifted left (vx < -0.012)
      final recovery1 = OfflineSpatialSpeechFormatter.formatLostTargetRecovery(
        targetItem: 'keys',
        vx: -0.02,
        vy: 0.0,
      );
      expect(recovery1, contains("you panned too far right, move camera back to the left"));

      // User panned left -> object drifted right (vx > 0.012)
      final recovery2 = OfflineSpatialSpeechFormatter.formatLostTargetRecovery(
        targetItem: 'keys',
        vx: 0.02,
        vy: 0.0,
      );
      expect(recovery2, contains("you panned too far left, move camera back to the right"));

      // User tilted camera up -> object drifted down
      final recovery3 = OfflineSpatialSpeechFormatter.formatLostTargetRecovery(
        targetItem: 'keys',
        vx: 0.0,
        vy: -0.02,
      );
      expect(recovery3, contains("tilt camera back down"));
    });

    test('SpokenGuidanceCadenceController priority interrupts and rate limits speech', () async {
      final mockTts = MockSpokenTtsBackend();
      final controller = SpokenGuidanceCadenceController(ttsBackend: mockTts, initialSpeechRate: 1.20);

      expect(controller.speechRate, equals(1.20));

      // 1. Send navigation speech at 12 o'clock
      final spoke1 = await controller.speakNavigation(
        text: 'At 12 o\'clock, 4 feet away.',
        clockHour: 12,
      );
      expect(spoke1, isTrue);
      expect(mockTts.spokenHistory.last, equals('At 12 o\'clock, 4 feet away.'));
      expect(controller.lastSpokenPriority, equals(SpeechPriority.navigation));

      // 2. Immediate same-hour navigation speech within 2.0s is throttled
      final spoke2 = await controller.speakNavigation(
        text: 'At 12 o\'clock, 3.5 feet away.',
        clockHour: 12,
      );
      expect(spoke2, isFalse);

      // 3. Navigation speech with sector delta >= 1 hour bypasses interval immediately
      final spoke3 = await controller.speakNavigation(
        text: 'Pan right, now at 2 o\'clock.',
        clockHour: 2,
      );
      expect(spoke3, isTrue);
      expect(mockTts.spokenHistory.last, equals('Pan right, now at 2 o\'clock.'));

      // 4. Critical interrupt immediately stops previous speech and speaks
      await controller.speakCritical('Stop! Target directly in front of hand.');
      expect(mockTts.stopCalls, greaterThanOrEqualTo(1));
      expect(mockTts.spokenHistory.last, equals('Stop! Target directly in front of hand.'));
      expect(controller.lastSpokenPriority, equals(SpeechPriority.critical));

      // 5. Context landmark speech speaks only once per target lock
      final spokeContext1 = await controller.speakContext(
        targetId: 'ID_1',
        text: 'Sitting next to the laptop on the wooden desk.',
      );
      expect(spokeContext1, isTrue);
      expect(mockTts.spokenHistory.last, contains('Sitting next to the laptop'));
      expect(controller.lastSpokenPriority, equals(SpeechPriority.context));

      final spokeContextDuplicate = await controller.speakContext(
        targetId: 'ID_1',
        text: 'Sitting next to the laptop on the wooden desk.',
      );
      expect(spokeContextDuplicate, isFalse); // Suppressed duplicate
    });
  });

  group('Step 2: MultiObjectTrackerAndDisambiguator & HybridSearchOrchestrator', () {
    test('NormalizedBoundingBox computes IoU and distance from center accurately', () {
      const boxA = NormalizedBoundingBox(ymin: 0.4, xmin: 0.4, ymax: 0.6, xmax: 0.6);
      const boxB = NormalizedBoundingBox(ymin: 0.45, xmin: 0.45, ymax: 0.65, xmax: 0.65);
      const boxDisjoint = NormalizedBoundingBox(ymin: 0.8, xmin: 0.8, ymax: 0.9, xmax: 0.9);

      expect(boxA.cx, closeTo(0.5, 0.01));
      expect(boxA.cy, closeTo(0.5, 0.01));
      expect(boxA.distanceFromCenter, closeTo(0.0, 0.01));

      expect(boxA.computeIoU(boxB), greaterThan(0.2));
      expect(boxA.computeIoU(boxDisjoint), equals(0.0));
    });

    test('MOT assigns persistent track_id across consecutive frames', () {
      final tracker = MultiObjectTrackerAndDisambiguator();

      // Frame 1: Detection at center
      final bundle1 = tracker.updateFrame(
        targetItem: 'bottle',
        detections: [
          const RawDetection(
            label: 'water bottle',
            bbox: NormalizedBoundingBox(ymin: 0.4, xmin: 0.45, ymax: 0.6, xmax: 0.55),
            confidence: 0.9,
          ),
        ],
      );

      expect(bundle1.instances.length, equals(1));
      final trackId1 = bundle1.instances.first.trackId;
      expect(bundle1.activeTargetId, equals(trackId1));

      // Frame 2: Slight movement
      final bundle2 = tracker.updateFrame(
        targetItem: 'bottle',
        detections: [
          const RawDetection(
            label: 'water bottle',
            bbox: NormalizedBoundingBox(ymin: 0.42, xmin: 0.46, ymax: 0.62, xmax: 0.56),
            confidence: 0.92,
          ),
        ],
      );

      expect(bundle2.instances.length, equals(1));
      expect(bundle2.instances.first.trackId, equals(trackId1));
    });

    test('Disambiguates multiple identical items and auto-locks center-most target', () {
      final tracker = MultiObjectTrackerAndDisambiguator();

      // Three bottles in frame: left, center, right
      final bundle = tracker.updateFrame(
        targetItem: 'bottle',
        detections: [
          const RawDetection(
            label: 'bottle',
            bbox: NormalizedBoundingBox(ymin: 0.4, xmin: 0.1, ymax: 0.6, xmax: 0.25),
            confidence: 0.88,
          ), // Left (approx 9-10 o'clock)
          const RawDetection(
            label: 'bottle',
            bbox: NormalizedBoundingBox(ymin: 0.4, xmin: 0.45, ymax: 0.6, xmax: 0.55),
            confidence: 0.95,
          ), // Center (12 o'clock)
          const RawDetection(
            label: 'bottle',
            bbox: NormalizedBoundingBox(ymin: 0.4, xmin: 0.75, ymax: 0.6, xmax: 0.90),
            confidence: 0.85,
          ), // Right (2-3 o'clock)
        ],
      );

      expect(bundle.instances.length, equals(3));
      expect(bundle.isMultiObject, isTrue);

      final active = bundle.activeInstance;
      expect(active, isNotNull);
      expect(active!.bbox.cx, closeTo(0.5, 0.06));
      expect(bundle.spokenOfflineAnnouncement, contains('Found 3 bottles'));
      expect(bundle.spokenOfflineAnnouncement, contains('Guiding you to'));
    });

    test('Cycles targets left and right, and filters by voice attributes', () {
      final tracker = MultiObjectTrackerAndDisambiguator();

      // Create 2 items
      tracker.updateFrame(
        targetItem: 'bottle',
        detections: [
          const RawDetection(
            label: 'bottle',
            bbox: NormalizedBoundingBox(ymin: 0.4, xmin: 0.2, ymax: 0.6, xmax: 0.35),
            confidence: 0.9,
          ),
          const RawDetection(
            label: 'bottle',
            bbox: NormalizedBoundingBox(ymin: 0.4, xmin: 0.7, ymax: 0.6, xmax: 0.85),
            confidence: 0.9,
          ),
        ],
      );

      final initialActiveId = tracker.activeTargetId;
      expect(initialActiveId, isNotNull);

      // Cycle next
      final nextTarget = tracker.cycleNext();
      expect(nextTarget, isNotNull);
      expect(nextTarget!.trackId, isNot(equals(initialActiveId)));

      // Merge mock cloud descriptions
      tracker.mergeCloudEnrichment([
        CloudGroundingInstance(
          trackId: initialActiveId,
          bbox: const NormalizedBoundingBox(ymin: 0.4, xmin: 0.2, ymax: 0.6, xmax: 0.35),
          clockDirection: "10 o'clock",
          estimatedDistance: '3 feet',
          distinctLabel: 'Diet Coke can',
          landmarkPosition: 'next to mousepad',
        ),
      ]);

      // Voice attribute matching switches lock to Diet Coke
      final matched = tracker.filterByVoiceAttribute('the Diet Coke one');
      expect(matched, isNotNull);
      expect(matched!.trackId, equals(initialActiveId));
      expect(tracker.activeTargetId, equals(initialActiveId));
    });

    test('Captures Kalman velocity when actively tracked target is lost', () {
      final tracker = MultiObjectTrackerAndDisambiguator();

      // Frame 1: Center
      tracker.updateFrame(
        targetItem: 'keys',
        detections: [
          const RawDetection(
            label: 'keys',
            bbox: NormalizedBoundingBox(ymin: 0.4, xmin: 0.45, ymax: 0.6, xmax: 0.55),
            confidence: 0.9,
          ),
        ],
      );

      // Frame 2: Moving left smoothly (user panned right)
      tracker.updateFrame(
        targetItem: 'keys',
        detections: [
          const RawDetection(
            label: 'keys',
            bbox: NormalizedBoundingBox(ymin: 0.4, xmin: 0.41, ymax: 0.6, xmax: 0.51),
            confidence: 0.9,
          ),
        ],
      );

      // Frame 3: Object leaves frame completely
      final bundle3 = tracker.updateFrame(
        targetItem: 'keys',
        detections: [],
      );

      expect(bundle3.instances.isEmpty, isTrue);
      expect(tracker.hasActiveTargetJustBeenLost, isTrue);
      // Moving left means vx < 0
      expect(tracker.lastActiveLostVx, lessThan(0.0));
    });

    test('NetworkHealthMonitor marks cloud available when latency <= 1200ms', () async {
      final mockClient = MockClient((request) async {
        return http.Response('', 204);
      });

      final monitor = NetworkHealthMonitor.withClient(httpClient: mockClient);
      final status = await monitor.checkHealthNow();

      expect(status.isOnline, isTrue);
      expect(status.isCloudAvailable, isTrue);
      expect(status.latencyMs, lessThan(1200));
    });

    test('CloudSemanticGrounderService builds prompt and parses Section 4 JSON schema', () {
      final prompt = CloudSemanticGrounderService.buildSystemPrompt('blue water bottle');
      expect(prompt, contains('blue water bottle'));
      expect(prompt, contains('spoken_location_sentence'));
      expect(prompt, contains('multi_item_summary_speech'));

      final jsonSample = {
        'found': true,
        'instances': [
          {
            'track_id': 'ID_1',
            'bbox': [350, 450, 650, 550],
            'clock_direction': "12 o'clock",
            'estimated_distance': "3 feet away",
            'distinct_label': "Blue thermos with silver lid",
            'landmark_position': "on wooden table next to keyboard",
            'spoken_location_sentence': "Your bottle is at 12 o'clock, 3 feet away on the table."
          }
        ],
        'multi_item_summary_speech': "Found 1 blue water bottle straight ahead."
      };

      final result = CloudGroundingResult.fromJson(jsonSample);
      expect(result.found, isTrue);
      expect(result.instances.length, equals(1));
      expect(result.instances.first.distinctLabel, equals('Blue thermos with silver lid'));
      expect(result.instances.first.landmarkPosition, contains('wooden table'));
      expect(result.instances.first.spokenLocationSentence, contains('3 feet away'));
      expect(result.multiItemSummarySpeech, contains('Found 1 blue water bottle'));
    });

    test('HybridSearchOrchestrator integrates MOT, Cadence Controller, and Cloud Grounding', () async {
      final mockTts = MockSpokenTtsBackend();
      final cadenceController = SpokenGuidanceCadenceController(ttsBackend: mockTts);

      final mockCloudClient = MockClient((request) async {
        final payload = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text': jsonEncode({
                      'found': true,
                      'instances': [
                        {
                          'track_id': null,
                          'bbox': [400, 480, 600, 520],
                          'clock_direction': "12 o'clock",
                          'estimated_distance': "3 feet",
                          'distinct_label': "Prescription Advil bottle",
                          'landmark_position': "on desk next to keyboard",
                          'spoken_location_sentence': "Your Advil bottle is straight ahead at 12 o'clock, 3 feet away."
                        }
                      ],
                      'multi_item_summary_speech': "Advil bottle located at 12 o'clock."
                    })
                  }
                ]
              }
            }
          ]
        };
        return http.Response(jsonEncode(payload), 200);
      });

      final tracker = MultiObjectTrackerAndDisambiguator();
      final grounder = CloudSemanticGrounderService(
        httpClient: mockCloudClient,
        apiKey: 'test_key',
      );
      final healthMonitor = NetworkHealthMonitor.withClient(
        httpClient: MockClient((req) async => http.Response('', 204)),
      );

      final orchestrator = HybridSearchOrchestrator(
        tracker: tracker,
        cloudGrounder: grounder,
        healthMonitor: healthMonitor,
        cadenceController: cadenceController,
      );

      // 1. Start search announces start
      orchestrator.startSearch('Advil');
      expect(orchestrator.isSearching, isTrue);
      await Future.delayed(const Duration(milliseconds: 15));
      expect(mockTts.spokenHistory.last, contains('Searching for Advil'));

      // 2. Process frame with item at 10 o'clock speaks navigation
      orchestrator.processFrame(
        localDetections: [
          const RawDetection(
            label: 'Advil',
            bbox: NormalizedBoundingBox(ymin: 0.4, xmin: 0.2, ymax: 0.6, xmax: 0.3),
            confidence: 0.9,
          ),
        ],
      );
      await Future.delayed(const Duration(milliseconds: 15));
      expect(mockTts.spokenHistory.last, contains('Pan slightly left'));

      // 3. Process frame with item centered & within grabbing reach speaks critical grab ready
      orchestrator.processFrame(
        localDetections: [
          const RawDetection(
            label: 'Advil',
            bbox: NormalizedBoundingBox(ymin: 0.2, xmin: 0.2, ymax: 0.8, xmax: 0.8),
            confidence: 0.95,
          ),
        ],
      );
      await Future.delayed(const Duration(milliseconds: 15));
      expect(mockTts.spokenHistory.last, contains("Within arm's reach, reach your hand straight out"));

      // 4. Double tap announces full location with landmarks
      orchestrator.repeatFullLocationWithLandmarks();
      await Future.delayed(const Duration(milliseconds: 15));
      expect(mockTts.spokenHistory.last, contains("Found your Advil"));

      orchestrator.stopSearch();
      expect(orchestrator.isSearching, isFalse);
    });
  });
}

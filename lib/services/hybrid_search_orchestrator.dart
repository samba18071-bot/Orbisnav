import 'dart:async';
import 'package:flutter/foundation.dart';
import '../controllers/spoken_guidance_cadence_controller.dart';
import '../models/hybrid_voice_search_models.dart';
import 'cloud_semantic_grounder_service.dart';
import 'multi_object_tracker_and_disambiguator.dart';
import 'network_health_monitor.dart';
import 'offline_spatial_speech_formatter.dart';

/// Primary Dual-Loop Orchestrator coordinating the 30 FPS On-Device Edge MOT
/// with the Asynchronous 0.5-1 FPS Cloud Semantic Grounder and Smart Spoken Cadence Controller.
class HybridSearchOrchestrator extends ChangeNotifier {
  final MultiObjectTrackerAndDisambiguator _tracker;
  final CloudSemanticGrounderService _cloudGrounder;
  final NetworkHealthMonitor _healthMonitor;
  final SpokenGuidanceCadenceController _cadenceController;

  String _activeTargetItem = '';
  String get activeTargetItem => _activeTargetItem;
  bool get isSearching => _activeTargetItem.isNotEmpty;

  DisambiguationBundle? _lastDisambiguation;
  DisambiguationBundle? get lastDisambiguation => _lastDisambiguation;

  final StreamController<DisambiguationBundle> _disambiguationController =
      StreamController<DisambiguationBundle>.broadcast();
  Stream<DisambiguationBundle> get disambiguationStream =>
      _disambiguationController.stream;

  // Timers and rate-limiters for the Dual-Loop Pipeline
  DateTime? _searchStartTime;
  bool _isRescueInProgress = false;
  bool _isRescueCompleted = false;

  DateTime? _lastCloudEnrichmentTime;
  bool _isCloudEnrichmentInProgress = false;

  HybridSearchOrchestrator({
    MultiObjectTrackerAndDisambiguator? tracker,
    CloudSemanticGrounderService? cloudGrounder,
    NetworkHealthMonitor? healthMonitor,
    SpokenGuidanceCadenceController? cadenceController,
  })  : _tracker = tracker ?? MultiObjectTrackerAndDisambiguator(),
        _cloudGrounder = cloudGrounder ?? CloudSemanticGrounderService(),
        _healthMonitor = healthMonitor ?? NetworkHealthMonitor(),
        _cadenceController = cadenceController ?? SpokenGuidanceCadenceController();

  SpokenGuidanceCadenceController get cadenceController => _cadenceController;
  MultiObjectTrackerAndDisambiguator get tracker => _tracker;
  NetworkHealthMonitor get healthMonitor => _healthMonitor;

  /// Starts searching for a target object (e.g., 'water bottle', 'keys', 'Advil').
  void startSearch(String targetItem) {
    final clean = targetItem.trim();
    if (clean.isEmpty) return;

    _activeTargetItem = clean;
    _searchStartTime = DateTime.now();
    _isRescueInProgress = false;
    _isRescueCompleted = false;
    _tracker.reset();
    _cadenceController.reset();

    _cadenceController.speakNavigation(
      text: 'Searching for $_activeTargetItem. Pan camera slowly.',
      clockHour: 12,
      force: true,
    );

    notifyListeners();
  }

  /// Halts active item search.
  void stopSearch() {
    _activeTargetItem = '';
    _searchStartTime = null;
    _isRescueInProgress = false;
    _isRescueCompleted = false;
    _lastDisambiguation = null;
    _tracker.reset();
    _cadenceController.stop();
    notifyListeners();
  }

  /// FAST LOOP: Process live camera frame detections at 15-30 FPS.
  DisambiguationBundle processFrame({
    required List<RawDetection> localDetections,
    Uint8List? rawFrameBytes,
  }) {
    if (!isSearching) {
      return const DisambiguationBundle(
        targetItem: '',
        instances: [],
        spokenOfflineAnnouncement: 'Search idle.',
        isMultiObject: false,
      );
    }

    // 1. Run 30 FPS ByteTrack / Kalman Multi-Object Tracker
    final bundle = _tracker.updateFrame(
      targetItem: _activeTargetItem,
      detections: localDetections,
      rawFrameBytes: rawFrameBytes,
    );

    _lastDisambiguation = bundle;
    _disambiguationController.add(bundle);

    // 2. Continuous Spoken Voice Navigation Logic
    if (bundle.instances.isEmpty && _tracker.hasActiveTargetJustBeenLost) {
      // Actively tracked target just left camera frame -> speak recovery guidance immediately
      _cadenceController.notifyTargetLost(
        targetItem: _activeTargetItem,
        vx: _tracker.lastActiveLostVx,
        vy: _tracker.lastActiveLostVy,
      );
      _tracker.consumeActiveTargetLostEvent();
    } else if (bundle.activeInstance != null) {
      final active = bundle.activeInstance!;
      _cadenceController.notifyActiveTargetChanged(active.trackId);

      final isCentered = (active.bbox.cx >= 0.45 && active.bbox.cx <= 0.55);
      final isGrabbingReach = (active.bbox.area >= 0.25 && isCentered);

      if (isGrabbingReach) {
        // Priority CRITICAL: User is ready to grab object
        _cadenceController.speakCritical(
          "Within arm's reach, reach your hand straight out and grab it.",
        );
      } else {
        // Priority NAVIGATION: Micro-corrections or clock directions
        final microPrompt = OfflineSpatialSpeechFormatter.formatMicroCorrection(active.bbox);
        final clockHour = OfflineSpatialSpeechFormatter.getClockHour(active.bbox.cx);

        _cadenceController.speakNavigation(
          text: microPrompt,
          clockHour: clockHour,
        );
      }

      // Priority CONTEXT: Cloud landmark context (spoken once per target lock)
      if (active.isCloudEnriched &&
          active.cloudLandmarkPosition != null &&
          active.cloudLandmarkPosition!.isNotEmpty) {
        _cadenceController.speakContext(
          targetId: active.trackId,
          text: 'Located ${active.cloudLandmarkPosition}.',
        );
      }
    }

    // 3. SLOW LOOP TRIGGER A: Missed-Target Rescue
    // If not found after 1.5 seconds and cloud is available, invoke Cloud API
    if (bundle.instances.isEmpty &&
        !_isRescueInProgress &&
        !_isRescueCompleted &&
        _searchStartTime != null &&
        rawFrameBytes != null &&
        _healthMonitor.isCloudAvailable) {
      final elapsedMs =
          DateTime.now().difference(_searchStartTime!).inMilliseconds;
      if (elapsedMs >= 1500) {
        _triggerMissedTargetRescue(rawFrameBytes);
      }
    }

    // 4. SLOW LOOP TRIGGER B: Multi-Object Semantic Enrichment
    // If multiple instances detected (count > 1), dispatch async batch enrichment at 0.5-1 FPS
    if (bundle.isMultiObject &&
        !_isCloudEnrichmentInProgress &&
        rawFrameBytes != null &&
        _healthMonitor.isCloudAvailable) {
      final now = DateTime.now();
      if (_lastCloudEnrichmentTime == null ||
          now.difference(_lastCloudEnrichmentTime!).inMilliseconds >= 1200) {
        _triggerMultiObjectEnrichment(rawFrameBytes, bundle.instances);
      }
    }

    notifyListeners();
    return bundle;
  }

  /// Executes Missed-Target Rescue: calls Cloud Grounder and seeds bounding box into MOT.
  Future<void> _triggerMissedTargetRescue(Uint8List frameBytes) async {
    _isRescueInProgress = true;
    final item = _activeTargetItem;

    try {
      final result = await _cloudGrounder.rescueMissedTarget(
        targetItem: item,
        imageBytes: frameBytes,
      );

      if (result.found && result.instances.isNotEmpty && _activeTargetItem == item) {
        final targetInstance = result.instances.first;
        // Seed box directly into local Kalman/ByteTrack tracker
        _tracker.seedBoundingBox(
          bbox: targetInstance.bbox,
          targetLabel: item,
          distinctLabel: targetInstance.distinctLabel,
          landmarkContext: targetInstance.landmarkPosition,
          spokenLocationSentence: targetInstance.spokenLocationSentence,
        );
        _isRescueCompleted = true;

        if (targetInstance.spokenLocationSentence.isNotEmpty) {
          _cadenceController.speakCritical(targetInstance.spokenLocationSentence);
        }
      }
    } catch (e) {
      debugPrint('[Orchestrator] Rescue error: $e');
    } finally {
      _isRescueInProgress = false;
    }
  }

  /// Executes Multi-Object Enrichment: updates ID_1, ID_2, ID_3 with fine-grained descriptions.
  Future<void> _triggerMultiObjectEnrichment(
      Uint8List frameBytes, List<TrackedItemInstance> instances) async {
    _isCloudEnrichmentInProgress = true;
    _lastCloudEnrichmentTime = DateTime.now();
    final item = _activeTargetItem;

    try {
      final result = await _cloudGrounder.enrichMultiObjectInstances(
        targetItem: item,
        imageBytes: frameBytes,
        localInstances: instances,
      );

      if (result.found && _activeTargetItem == item) {
        _tracker.mergeCloudEnrichment(result.instances);
      }
    } catch (e) {
      debugPrint('[Orchestrator] Multi-object enrichment error: $e');
    } finally {
      _isCloudEnrichmentInProgress = false;
    }
  }

  /// Target Cycling: Swipe Right or 'Next'
  TrackedItemInstance? cycleNextTarget() {
    final next = _tracker.cycleNext();
    if (next != null) {
      _cadenceController.notifyActiveTargetChanged(next.trackId);
      final confirmation = OfflineSpatialSpeechFormatter.formatTargetSwitched(next);
      _cadenceController.speakCritical(confirmation);
    }
    notifyListeners();
    return next;
  }

  /// Target Cycling: Swipe Left or 'Previous'
  TrackedItemInstance? cyclePreviousTarget() {
    final prev = _tracker.cyclePrevious();
    if (prev != null) {
      _cadenceController.notifyActiveTargetChanged(prev.trackId);
      final confirmation = OfflineSpatialSpeechFormatter.formatTargetSwitched(prev);
      _cadenceController.speakCritical(confirmation);
    }
    notifyListeners();
    return prev;
  }

  /// Voice Attribute Filtering (e.g. 'The Diet Coke one', 'The green one on the left')
  TrackedItemInstance? filterByVoice(String voiceQuery) {
    final matched = _tracker.filterByVoiceAttribute(voiceQuery);
    if (matched != null) {
      _cadenceController.notifyActiveTargetChanged(matched.trackId);
      final confirmation = OfflineSpatialSpeechFormatter.formatTargetSwitched(matched);
      _cadenceController.speakCritical(confirmation);
    }
    notifyListeners();
    return matched;
  }

  /// Speaks full detailed location and landmarks (Double-tap action).
  void repeatFullLocationWithLandmarks() {
    final active = _lastDisambiguation?.activeInstance;
    if (active == null) {
      _cadenceController.speakCritical("No item currently locked on. Pan camera slowly.");
      return;
    }

    final fullSentence = OfflineSpatialSpeechFormatter.formatInitialLocation(
      targetItem: _activeTargetItem,
      bbox: active.bbox,
      color: active.offlineColor,
      landmark: active.cloudLandmarkPosition,
    );
    _cadenceController.speakCritical(fullSentence);
  }

  @override
  void dispose() {
    _disambiguationController.close();
    _cadenceController.dispose();
    super.dispose();
  }
}

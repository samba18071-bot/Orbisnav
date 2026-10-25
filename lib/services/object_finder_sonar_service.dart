import 'dart:async';
import '../controllers/audio_mutex_controller.dart';
import 'online_obstacle_detector.dart';

/// State of the active object locator search.
class ObjectFinderTarget {
  final String targetLabel;
  final bool isFound;
  final double distanceMeters;
  final String clockPosition;
  final double alignmentScore; // 0.0 (far off) to 1.0 (dead center crosshair)
  final int sonarPingIntervalMs; // faster ping when closer & aligned
  final double stereoPan; // -1.0 left to +1.0 right
  final String guidanceCue;

  final int totalFoundCount;
  final List<DetectedObstacle> secondaryMatches;

  const ObjectFinderTarget({
    required this.targetLabel,
    required this.isFound,
    required this.distanceMeters,
    required this.clockPosition,
    required this.alignmentScore,
    required this.sonarPingIntervalMs,
    required this.stereoPan,
    required this.guidanceCue,
    this.totalFoundCount = 0,
    this.secondaryMatches = const [],
  });

  factory ObjectFinderTarget.initial(String label) => ObjectFinderTarget(
        targetLabel: label,
        isFound: false,
        distanceMeters: 99.0,
        clockPosition: "12 o'clock",
        alignmentScore: 0.0,
        sonarPingIntervalMs: 1000,
        stereoPan: 0.0,
        guidanceCue: "Searching for $label. Pan your phone slowly...",
        totalFoundCount: 0,
        secondaryMatches: const [],
      );
}

/// ObjectFinderSonarService:
/// Uses spatial audio radar (sonar pings) and directional cues to guide blind users to lost belongings.
class ObjectFinderSonarService {
  final AudioMutexController _audioMutex;
  String _activeTargetLabel = "";
  bool _isSearching = false;
  bool _wasFoundPreviously = false;
  int _consecutiveMissingFrames = 0;
  ObjectFinderTarget _currentState = ObjectFinderTarget.initial("");

  final StreamController<ObjectFinderTarget> _stateController =
      StreamController<ObjectFinderTarget>.broadcast();

  Stream<ObjectFinderTarget> get stateStream => _stateController.stream;
  ObjectFinderTarget get currentState => _currentState;
  bool get isSearching => _isSearching;
  String get activeTargetLabel => _activeTargetLabel;

  ObjectFinderSonarService({AudioMutexController? audioMutex})
      : _audioMutex = audioMutex ?? AudioMutexController();

  String _formatLabel(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  DateTime? _lastSpokenGuidanceTime;
  String? _lastSpokenGuidanceText;
  int _consecutiveTrackingTicks = 0;

  /// Starts searching for a specific item (e.g., 'keys', 'white cane', 'mug', 'wallet')
  void startSearch(String targetLabel) {
    final clean = targetLabel.trim().toLowerCase();
    if (clean.isEmpty) {
      _activeTargetLabel = "";
      _isSearching = false;
      return;
    }
    _activeTargetLabel = clean;
    _isSearching = true;
    _wasFoundPreviously = false;
    _consecutiveMissingFrames = 0;
    _lastSpokenGuidanceTime = null;
    _lastSpokenGuidanceText = null;
    _consecutiveTrackingTicks = 0;
    _currentState = ObjectFinderTarget.initial(_activeTargetLabel);
    _stateController.add(_currentState);

    final activeChan = _audioMutex.activeChannelIndex;
    _audioMutex.speak(
      text: "Lost item sensor active. Locating ${_activeTargetLabel}. Slowly sweep camera across the room.",
      priority: AudioPriority.level2Navigation,
      channelIndex: activeChan,
      haptic: true,
      force: true,
    );
  }

  void stopSearch() {
    _isSearching = false;
    _wasFoundPreviously = false;
    _consecutiveMissingFrames = 0;
    _lastSpokenGuidanceTime = null;
    _lastSpokenGuidanceText = null;
    _consecutiveTrackingTicks = 0;
    _currentState = ObjectFinderTarget.initial(_activeTargetLabel);
    _stateController.add(_currentState);
    final activeChan = _audioMutex.activeChannelIndex;
    _audioMutex.speak(
      text: "Lost item search stopped.",
      priority: AudioPriority.level3Context,
      channelIndex: activeChan,
      haptic: false,
    );
  }

  /// Processes active vision obstacle candidates to find target item and calculate sonar parameters.
  ObjectFinderTarget updateVisionCandidates(List<DetectedObstacle> detections) {
    if (!_isSearching || _activeTargetLabel.isEmpty) return _currentState;

    // Filter all matching candidate detections
    final List<DetectedObstacle> matchingCandidates = [];
    for (final item in detections) {
      if (isMatching(item.label, _activeTargetLabel)) {
        matchingCandidates.add(item);
      }
    }

    if (matchingCandidates.isEmpty) {
      _consecutiveMissingFrames++;
      if (_consecutiveMissingFrames >= 8) {
        _wasFoundPreviously = false;
        _consecutiveTrackingTicks = 0;
      }
      _currentState = ObjectFinderTarget(
        targetLabel: _activeTargetLabel,
        isFound: false,
        distanceMeters: 99.0,
        clockPosition: "12 o'clock",
        alignmentScore: 0.0,
        sonarPingIntervalMs: 1200,
        stereoPan: 0.0,
        guidanceCue: "No ${_activeTargetLabel} seen yet. Pan left or right.",
      );
      _stateController.add(_currentState);
      return _currentState;
    }

    _consecutiveMissingFrames = 0;

    // Sort matching items: primary target is closest to center of field of view
    matchingCandidates.sort((a, b) {
      final aCenterX = (a.xMin + a.xMax) / 2.0;
      final bCenterX = (b.xMin + b.xMax) / 2.0;
      final aDistCenter = (aCenterX - 0.5).abs();
      final bDistCenter = (bCenterX - 0.5).abs();
      return aDistCenter.compareTo(bDistCenter);
    });

    final matchedItem = matchingCandidates.first;

    // Calculate center offset and alignment score (1.0 = dead center of viewfinder)
    final centerX = (matchedItem.xMin + matchedItem.xMax) / 2.0;
    final centerOffset = (centerX - 0.5).abs();
    final alignmentScore = (1.0 - (centerOffset * 2.0)).clamp(0.0, 1.0);

    // Stereo pan: -1.0 (left) to +1.0 (right)
    final stereoPan = ((centerX - 0.5) * 2.0).clamp(-1.0, 1.0);

    // Sonar ping interval: closer and more centered = faster ping (80ms to 800ms)
    final distanceFactor = (matchedItem.distanceMeters / 3.0).clamp(0.1, 1.0);
    final int pingIntervalMs = (80 + (distanceFactor * 500) + ((1.0 - alignmentScore) * 300)).toInt();

    String directionHint = "Straight ahead";
    if (stereoPan < -0.3) {
      directionHint = "To your left";
    } else if (stereoPan > 0.3) {
      directionHint = "To your right";
    }

    final labelName = _formatLabel(_activeTargetLabel.isNotEmpty ? _activeTargetLabel : matchedItem.label);
    final distStr = matchedItem.distanceMeters.toStringAsFixed(1);
    final clock = matchedItem.clockPosition;

    final String cue;
    if (matchingCandidates.length > 1) {
      cue = "Found ${matchingCandidates.length} ${labelName}s. Nearest is $directionHint at $clock ($distStr m).";
    } else {
      cue = "$labelName found! Located $directionHint at $clock, $distStr meters away.";
    }

    _currentState = ObjectFinderTarget(
      targetLabel: _activeTargetLabel,
      isFound: true,
      distanceMeters: matchedItem.distanceMeters,
      clockPosition: clock,
      alignmentScore: alignmentScore,
      sonarPingIntervalMs: pingIntervalMs,
      stereoPan: stereoPan,
      guidanceCue: cue,
      totalFoundCount: matchingCandidates.length,
      secondaryMatches: matchingCandidates.skip(1).toList(),
    );

    _stateController.add(_currentState);

    final now = DateTime.now();
    final activeChan = _audioMutex.activeChannelIndex;

    // 1. Initial Disambiguation or Discovery Announcement
    if (!_wasFoundPreviously) {
      _wasFoundPreviously = true;
      _lastSpokenGuidanceTime = now;
      _consecutiveTrackingTicks = 0;

      String initialSpeech;
      if (matchingCandidates.length > 1) {
        // Multi-item of same type disambiguation
        final count = matchingCandidates.length;
        // Sort left-to-right for spatial clarity
        final spatialCandidates = List<DetectedObstacle>.from(matchingCandidates)
          ..sort((a, b) => ((a.xMin + a.xMax) / 2.0).compareTo((b.xMin + b.xMax) / 2.0));

        final buffer = StringBuffer();
        buffer.write("Found $count ${labelName}s. ");
        for (int i = 0; i < spatialCandidates.length; i++) {
          final c = spatialCandidates[i];
          final cDist = c.distanceMeters.toStringAsFixed(1);
          buffer.write("One at ${c.clockPosition}, $cDist meters. ");
        }
        buffer.write("Guiding you to the primary $labelName at $clock, $distStr meters away.");
        initialSpeech = buffer.toString();
      } else {
        initialSpeech = "$labelName found! Located $directionHint at $clock, $distStr meters away.";
      }

      _lastSpokenGuidanceText = initialSpeech;
      _audioMutex.speak(
        text: initialSpeech,
        priority: AudioPriority.level1Safety,
        channelIndex: activeChan,
        haptic: true,
        force: true,
      );
    } else {
      // 2. Continuous Voice Guidance suitable for blind users
      // Provides spoken instructions as user moves or pans (e.g., "Pan slightly right", "Walk forward", "Within arm's reach, grab it now")
      _consecutiveTrackingTicks++;
      final elapsedSinceSpoken = _lastSpokenGuidanceTime == null
          ? 9999
          : now.difference(_lastSpokenGuidanceTime!).inMilliseconds;

      // Minimum cadence between continuous spoken nudges: 2200ms
      if (elapsedSinceSpoken >= 2200 && _consecutiveTrackingTicks >= 5) {
        String guidanceSpoken;
        AudioPriority priority = AudioPriority.level2Navigation;

        if (matchedItem.distanceMeters <= 0.45 && alignmentScore >= 0.6) {
          // Grabbing reach
          guidanceSpoken = "Directly in front of your hand. Reach straight out and grab the $labelName now!";
          priority = AudioPriority.level0Critical;
        } else if (matchedItem.distanceMeters <= 0.9) {
          // Arm's reach
          if (stereoPan < -0.25) {
            guidanceSpoken = "Within arm's reach to your left. Reach out at ${clock}.";
          } else if (stereoPan > 0.25) {
            guidanceSpoken = "Within arm's reach to your right. Reach out at ${clock}.";
          } else {
            guidanceSpoken = "Within arm's reach, extend your hand forward.";
          }
        } else if (alignmentScore < 0.4) {
          // Misaligned: guide panning
          if (stereoPan < 0) {
            guidanceSpoken = "Pan camera slightly left towards $clock.";
          } else {
            guidanceSpoken = "Pan camera slightly right towards $clock.";
          }
        } else {
          // Centered: guide walking
          final metersRound = matchedItem.distanceMeters.toStringAsFixed(1);
          guidanceSpoken = "Centered straight ahead at 12 o'clock, $metersRound meters away. Walk forward.";
        }

        // Avoid repeating the exact identical prompt unless proximity reached
        if (guidanceSpoken != _lastSpokenGuidanceText || matchedItem.distanceMeters <= 0.6) {
          _lastSpokenGuidanceText = guidanceSpoken;
          _lastSpokenGuidanceTime = now;
          _audioMutex.speak(
            text: guidanceSpoken,
            priority: priority,
            channelIndex: activeChan,
            haptic: matchedItem.distanceMeters <= 0.6,
          );
        }
      }
    }

    return _currentState;
  }

  bool isMatching(String itemLabel, String target) {
    final i = itemLabel.toLowerCase().trim();
    final t = target.toLowerCase().trim();
    // Direct match, substring match, or reverse substring match
    if (i == t || i.contains(t) || t.contains(i)) return true;

    // Word token overlap match (e.g. "water" in "water bottle", "iron" in "ironbox")
    final iWords = i.split(RegExp(r'[\s_\-]+')).where((w) => w.length > 2);
    final tWords = t.split(RegExp(r'[\s_\-]+')).where((w) => w.length > 2);
    for (final iw in iWords) {
      if (tWords.any((tw) => tw == iw || tw.contains(iw) || iw.contains(tw))) {
        return true;
      }
    }

    // High-accuracy synonyms for target items
    const proxies = <String, List<String>>{
      'ironbox': ['ironbox', 'iron', 'clothes iron', 'steam iron', 'press'],
      'iron': ['ironbox', 'iron', 'clothes iron', 'steam iron', 'press'],
      'charger': ['charger', 'adapter', 'charging cable', 'cable', 'wire', 'plug', 'cord', 'power adapter'],
      'shoes': ['shoes', 'shoe', 'slippers', 'sandals', 'sneakers', 'footwear', 'boots'],
      'shoe': ['shoes', 'shoe', 'slippers', 'sandals', 'sneakers', 'footwear', 'boots'],
      'medicine': ['medicine', 'medicine_bottle', 'pill bottle', 'pills', 'tablets', 'capsules', 'bottle', 'syrup'],
      'headphones': ['headphones', 'earphones', 'earbuds', 'headset'],
      'watch': ['watch', 'smartwatch', 'wristwatch', 'clock'],
      'pen': ['pen', 'pencil', 'marker', 'highlighter', 'stationery'],
      'plate': ['plate', 'dish', 'tray', 'saucer', 'bowl'],
      'spoon': ['spoon', 'fork', 'knife', 'cutlery', 'utensil'],
      'fan': ['fan', 'ceiling fan', 'table fan', 'electric fan'],
      'keys': ['keys', 'key', 'keychain', 'keyset', 'keyring', 'remote'],
      'key': ['keys', 'key', 'keychain', 'keyset', 'keyring', 'remote'],
      'wallet': ['wallet', 'handbag', 'purse', 'billfold', 'card holder'],
      'purse': ['wallet', 'handbag', 'purse', 'backpack'],
      'white cane': ['white cane', 'white_cane', 'cane', 'walking stick', 'stick'],
      'white_cane': ['white cane', 'white_cane', 'cane', 'walking stick', 'stick'],
      'cane': ['white cane', 'white_cane', 'cane', 'walking stick', 'stick'],
      'glasses': ['glasses', 'spectacles', 'sunglasses', 'reading glasses', 'eyewear'],
      'spectacles': ['glasses', 'spectacles', 'sunglasses', 'reading glasses', 'eyewear'],
      'water bottle': ['water bottle', 'bottle', 'flask', 'thermos', 'tumbler'],
      'bottle': ['water bottle', 'bottle', 'flask', 'thermos', 'tumbler'],
      'cup': ['cup', 'mug', 'tea cup', 'coffee mug'],
      'mug': ['cup', 'mug', 'coffee mug'],
      'phone': ['cell phone', 'cell_phone', 'phone', 'telephone', 'mobile', 'smartphone'],
      'cell phone': ['cell phone', 'cell_phone', 'phone', 'telephone', 'mobile', 'smartphone'],
      'cell_phone': ['cell phone', 'cell_phone', 'phone', 'telephone', 'mobile', 'smartphone'],
      'medicine_bottle': ['medicine', 'medicine_bottle', 'pill bottle', 'pills', 'tablets', 'capsules', 'bottle', 'syrup'],
      'laptop': ['laptop', 'computer', 'screen', 'notebook'],
      'backpack': ['backpack', 'handbag', 'bag', 'tote'],
      'bag': ['backpack', 'handbag', 'bag', 'tote'],
      'chair': ['chair', 'couch', 'bench', 'stool', 'seat', 'armchair'],
      'table': ['table', 'desk', 'dining table', 'counter', 'workstation'],
      'door': ['door', 'doorway', 'entrance', 'gate'],
      'stairs': ['stairs', 'staircase', 'steps'],
      'book': ['book', 'notebook', 'diary', 'magazine'],
      'remote': ['remote', 'remote control', 'controller', 'clicker'],
      'mouse': ['mouse', 'computer mouse'],
      'keyboard': ['keyboard', 'computer keyboard'],
    };

    for (final entry in proxies.entries) {
      if (t.contains(entry.key) || entry.key.contains(t)) {
        if (entry.value.any((syn) => i.contains(syn) || syn.contains(i))) {
          return true;
        }
      }
    }
    return false;
  }

  void dispose() {
    _stateController.close();
  }
}

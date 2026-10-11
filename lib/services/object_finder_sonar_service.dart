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

  const ObjectFinderTarget({
    required this.targetLabel,
    required this.isFound,
    required this.distanceMeters,
    required this.clockPosition,
    required this.alignmentScore,
    required this.sonarPingIntervalMs,
    required this.stereoPan,
    required this.guidanceCue,
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
      );
}

/// ObjectFinderSonarService:
/// Uses spatial audio radar (sonar pings) and directional cues to guide blind users to lost belongings.
class ObjectFinderSonarService {
  final AudioMutexController _audioMutex;
  String _activeTargetLabel = "keys";
  bool _isSearching = false;
  bool _wasFoundPreviously = false;
  DateTime? _lastSpokenGuidanceTime;
  ObjectFinderTarget _currentState = ObjectFinderTarget.initial("keys");

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

  /// Starts searching for a specific item (e.g., 'keys', 'white cane', 'mug', 'wallet')
  void startSearch(String targetLabel) {
    _activeTargetLabel = targetLabel.trim().toLowerCase();
    _isSearching = true;
    _wasFoundPreviously = false;
    _lastSpokenGuidanceTime = null;
    _currentState = ObjectFinderTarget.initial(_activeTargetLabel);
    _stateController.add(_currentState);

    _audioMutex.speak(
      text: "Lost item sonar radar active. Locating ${_activeTargetLabel}. Sweep camera slowly across the room.",
      priority: AudioPriority.level2Navigation,
      haptic: true,
      force: true,
    );
  }

  void stopSearch() {
    _isSearching = false;
    _wasFoundPreviously = false;
    _lastSpokenGuidanceTime = null;
    _currentState = ObjectFinderTarget.initial(_activeTargetLabel);
    _stateController.add(_currentState);
    _audioMutex.speak(
      text: "Object search stopped.",
      priority: AudioPriority.level3Context,
      haptic: false,
    );
  }

  /// Processes active vision obstacle candidates to find target item and calculate sonar parameters.
  ObjectFinderTarget updateVisionCandidates(List<DetectedObstacle> detections) {
    if (!_isSearching) return _currentState;

    DetectedObstacle? matchedItem;
    double bestMatchScore = 0.0;

    for (final item in detections) {
      if (isMatching(item.label, _activeTargetLabel)) {
        if (item.confidence > bestMatchScore) {
          bestMatchScore = item.confidence;
          matchedItem = item;
        }
      }
    }

    if (matchedItem == null) {
      if (_wasFoundPreviously) {
        _wasFoundPreviously = false;
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

    final labelName = _formatLabel(matchedItem.label.isNotEmpty ? matchedItem.label : _activeTargetLabel);
    final distStr = matchedItem.distanceMeters.toStringAsFixed(1);
    final clock = matchedItem.clockPosition;

    final cue = "$labelName found! Located $directionHint at $clock, $distStr meters away.";

    _currentState = ObjectFinderTarget(
      targetLabel: _activeTargetLabel,
      isFound: true,
      distanceMeters: matchedItem.distanceMeters,
      clockPosition: clock,
      alignmentScore: alignmentScore,
      sonarPingIntervalMs: pingIntervalMs,
      stereoPan: stereoPan,
      guidanceCue: cue,
    );

    _stateController.add(_currentState);

    final now = DateTime.now();

    // 1. First time object is matched/locked on: announce immediately!
    if (!_wasFoundPreviously) {
      _wasFoundPreviously = true;
      _lastSpokenGuidanceTime = now;
      _audioMutex.speak(
        text: "$labelName found! Located $directionHint at $clock, $distStr meters away.",
        priority: AudioPriority.level1Safety,
        haptic: true,
        force: true,
      );
    } else {
      // 2. Periodic continuous tracking update
      final timeSinceLast = _lastSpokenGuidanceTime == null
          ? 9999
          : now.difference(_lastSpokenGuidanceTime!).inMilliseconds;

      if (timeSinceLast >= 2800) {
        _lastSpokenGuidanceTime = now;
        if (matchedItem.distanceMeters < 0.65 && alignmentScore > 0.7) {
          _audioMutex.speak(
            text: "$labelName directly in front of you at reach distance. Reach out your hand.",
            priority: AudioPriority.level1Safety,
            haptic: true,
          );
        } else {
          _audioMutex.speak(
            text: "$labelName at $clock, $distStr meters. $directionHint.",
            priority: AudioPriority.level2Navigation,
            haptic: false,
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

    // Comprehensive synonyms and proxy object matches for real-time edge detection
    const proxies = <String, List<String>>{
      'ironbox': ['ironbox', 'iron', 'clothes iron', 'steam iron', 'press', 'appliance', 'toaster', 'hair drier', 'remote', 'mouse'],
      'iron': ['ironbox', 'iron', 'clothes iron', 'steam iron', 'press', 'appliance', 'toaster', 'hair drier', 'remote', 'mouse'],
      'charger': ['charger', 'adapter', 'charging cable', 'cable', 'wire', 'plug', 'cord', 'power adapter', 'remote', 'mouse'],
      'shoes': ['shoes', 'shoe', 'slippers', 'sandals', 'sneakers', 'footwear', 'boots'],
      'shoe': ['shoes', 'shoe', 'slippers', 'sandals', 'sneakers', 'footwear', 'boots'],
      'medicine': ['medicine', 'pill bottle', 'pills', 'tablets', 'capsules', 'bottle', 'syrup'],
      'headphones': ['headphones', 'earphones', 'earbuds', 'headset'],
      'watch': ['watch', 'smartwatch', 'wristwatch', 'clock'],
      'pen': ['pen', 'pencil', 'marker', 'highlighter', 'stationery'],
      'plate': ['plate', 'dish', 'tray', 'saucer', 'bowl'],
      'spoon': ['spoon', 'fork', 'knife', 'cutlery', 'utensil'],
      'fan': ['fan', 'ceiling fan', 'table fan', 'electric fan'],
      'keys': ['keys', 'key', 'keychain', 'scissors', 'remote', 'mouse', 'cell phone'],
      'key': ['keys', 'key', 'keychain', 'scissors', 'remote', 'mouse', 'cell phone'],
      'wallet': ['wallet', 'handbag', 'book', 'cell phone', 'purse', 'billfold', 'card holder'],
      'purse': ['wallet', 'handbag', 'purse', 'backpack'],
      'white cane': ['white cane', 'cane', 'umbrella', 'stick', 'walking stick', 'baseball bat'],
      'cane': ['white cane', 'cane', 'umbrella', 'stick', 'walking stick', 'baseball bat'],
      'glasses': ['glasses', 'spectacles', 'sunglasses', 'reading glasses', 'eyewear', 'remote', 'cell phone'],
      'spectacles': ['glasses', 'spectacles', 'sunglasses', 'reading glasses', 'eyewear', 'remote', 'cell phone'],
      'water bottle': ['water bottle', 'bottle', 'cup', 'glass', 'flask', 'thermos', 'tumbler'],
      'bottle': ['water bottle', 'bottle', 'cup', 'glass', 'flask', 'thermos', 'tumbler'],
      'cup': ['cup', 'bottle', 'mug', 'glass', 'tea cup'],
      'mug': ['cup', 'bottle', 'mug', 'coffee mug'],
      'phone': ['cell phone', 'phone', 'telephone', 'mobile', 'smartphone'],
      'cell phone': ['cell phone', 'phone', 'telephone', 'mobile', 'smartphone'],
      'laptop': ['laptop', 'tv', 'keyboard', 'computer', 'screen', 'notebook'],
      'backpack': ['backpack', 'handbag', 'suitcase', 'bag', 'tote'],
      'bag': ['backpack', 'handbag', 'suitcase', 'bag', 'tote'],
      'chair': ['chair', 'couch', 'bench', 'stool', 'seat', 'armchair'],
      'table': ['table', 'desk', 'dining table', 'counter', 'workstation'],
      'door': ['door', 'doorway', 'entrance', 'gate'],
      'stairs': ['stairs', 'staircase', 'steps'],
      'book': ['book', 'notebook', 'diary', 'magazine', 'paper'],
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

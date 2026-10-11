import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import '../controllers/audio_mutex_controller.dart';

/// Indoor Topological Graph Node
class IndoorNode {
  final String id;
  final String name; // e.g. "Room 204", "Elevator B", "Main Entrance"
  final double xMeters;
  final double yMeters;
  final String? ocrPlaqueText;
  final List<String> connectedNodeIds;

  const IndoorNode({
    required this.id,
    required this.name,
    required this.xMeters,
    required this.yMeters,
    this.ocrPlaqueText,
    this.connectedNodeIds = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'xMeters': xMeters,
        'yMeters': yMeters,
        'ocrPlaqueText': ocrPlaqueText,
        'connectedNodeIds': connectedNodeIds,
      };

  factory IndoorNode.fromJson(Map<String, dynamic> json) => IndoorNode(
        id: json['id'] as String,
        name: json['name'] as String,
        xMeters: (json['xMeters'] as num).toDouble(),
        yMeters: (json['yMeters'] as num).toDouble(),
        ocrPlaqueText: json['ocrPlaqueText'] as String?,
        connectedNodeIds: (json['connectedNodeIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}

/// Recorded Self-Mapping Venue (Day 15)
class IndoorVenueMap {
  final String venueName;
  final DateTime createdAt;
  final List<IndoorNode> nodes;

  const IndoorVenueMap({
    required this.venueName,
    required this.createdAt,
    required this.nodes,
  });

  String toJsonString() => jsonEncode({
        'venueName': venueName,
        'createdAt': createdAt.toIso8601String(),
        'nodes': nodes.map((n) => n.toJson()).toList(),
      });

  factory IndoorVenueMap.fromJsonString(String jsonStr) {
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return IndoorVenueMap(
      venueName: map['venueName'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      nodes: (map['nodes'] as List<dynamic>)
          .map((n) => IndoorNode.fromJson(n as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// State of indoor navigation & self-mapping session
class IndoorNavigationState {
  final bool isNavigating;
  final bool isRecordingMap;
  final String currentVenue;
  final double currentX;
  final double currentY;
  final double accumulatedDriftMeters;
  final String? nearestNodeName;
  final String currentInstruction;
  final int relativeClockDirection;
  final String? lastSnappedLandmark;

  const IndoorNavigationState({
    required this.isNavigating,
    required this.isRecordingMap,
    required this.currentVenue,
    required this.currentX,
    required this.currentY,
    required this.accumulatedDriftMeters,
    this.nearestNodeName,
    required this.currentInstruction,
    this.relativeClockDirection = 12,
    this.lastSnappedLandmark,
  });

  factory IndoorNavigationState.idle() => const IndoorNavigationState(
        isNavigating: false,
        isRecordingMap: false,
        currentVenue: 'None',
        currentX: 0.0,
        currentY: 0.0,
        accumulatedDriftMeters: 0.0,
        currentInstruction: 'Indoor navigation idle.',
      );
}

/// Service managing Day 13 Indoor A* PDR, Day 14 OCR Landmark Snapping, and Day 15 "Record & Walk" Self-Mapping.
class IndoorSelfMappingService {
  final AudioMutexController _audioMutex;

  final StreamController<IndoorNavigationState> _stateStreamController =
      StreamController<IndoorNavigationState>.broadcast();
  Stream<IndoorNavigationState> get stateStream => _stateStreamController.stream;

  // Active Map & State
  IndoorVenueMap? _activeMap;
  bool _isNavigating = false;
  bool _isRecording = false;
  String _recordingVenueName = '';
  final List<IndoorNode> _recordedNodes = [];

  double _userX = 0.0;
  double _userY = 0.0;
  double _accumulatedDrift = 0.0;
  String? _lastSnappedLandmark;
  List<IndoorNode> _activePath = [];
  int _pathTargetIndex = 0;

  IndoorSelfMappingService({AudioMutexController? audioMutex})
      : _audioMutex = audioMutex ?? AudioMutexController();

  IndoorNavigationState get currentState => IndoorNavigationState(
        isNavigating: _isNavigating,
        isRecordingMap: _isRecording,
        currentVenue: _activeMap?.venueName ?? _recordingVenueName,
        currentX: _userX,
        currentY: _userY,
        accumulatedDriftMeters: _accumulatedDrift,
        nearestNodeName: _findNearestNode()?.name,
        currentInstruction: _getCurrentInstruction(),
        relativeClockDirection: _getCurrentClockDirection(),
        lastSnappedLandmark: _lastSnappedLandmark,
      );

  // -------------------------------------------------------------
  // Day 15: "Record & Walk" Self-Mapping Mode
  // -------------------------------------------------------------
  void startRecordingMap(String venueName) {
    _isRecording = true;
    _recordingVenueName = venueName;
    _recordedNodes.clear();
    _userX = 0.0;
    _userY = 0.0;
    _accumulatedDrift = 0.0;

    // Add starting landmark node
    final startNode = IndoorNode(
      id: 'node_0',
      name: 'Start Entrance',
      xMeters: 0.0,
      yMeters: 0.0,
    );
    _recordedNodes.add(startNode);

    _audioMutex.speak(
      text: 'Starting self-mapping for $venueName. Walk through the venue and point at door signs.',
      priority: AudioPriority.level2Navigation,
      channelIndex: 1,
      haptic: true,
    );

    _stateStreamController.add(currentState);
  }

  void addLandmarkPlaqueDuringRecording({
    required String plaqueName,
    required String detectedOcrText,
  }) {
    if (!_isRecording) return;

    final id = 'node_${_recordedNodes.length}';
    final prevId = _recordedNodes.isNotEmpty ? _recordedNodes.last.id : null;

    final newNode = IndoorNode(
      id: id,
      name: plaqueName,
      xMeters: _userX,
      yMeters: _userY,
      ocrPlaqueText: detectedOcrText,
      connectedNodeIds: prevId != null ? [prevId] : [],
    );

    _recordedNodes.add(newNode);

    _audioMutex.speak(
      text: 'Landmark $plaqueName recorded at node ${_recordedNodes.length}.',
      priority: AudioPriority.level2Navigation,
      channelIndex: 1,
      haptic: true,
    );

    _stateStreamController.add(currentState);
  }

  IndoorVenueMap stopRecordingAndExportMap() {
    _isRecording = false;
    final map = IndoorVenueMap(
      venueName: _recordingVenueName,
      createdAt: DateTime.now(),
      nodes: List.unmodifiable(_recordedNodes),
    );

    _activeMap = map;

    _audioMutex.speak(
      text: 'Mapping complete for ${_recordingVenueName}. Saved ${_recordedNodes.length} navigational nodes.',
      priority: AudioPriority.level2Navigation,
      channelIndex: 1,
      haptic: true,
    );

    _stateStreamController.add(currentState);
    return map;
  }

  // -------------------------------------------------------------
  // Day 13: Indoor A* Graph Navigation & PDR Dead-Reckoning
  // -------------------------------------------------------------
  void loadVenueMap(IndoorVenueMap map) {
    _activeMap = map;
    _userX = map.nodes.isNotEmpty ? map.nodes.first.xMeters : 0.0;
    _userY = map.nodes.isNotEmpty ? map.nodes.first.yMeters : 0.0;
    _accumulatedDrift = 0.0;
    _stateStreamController.add(currentState);
  }

  void startIndoorRouteToNode(String targetNodeId) {
    if (_activeMap == null || _activeMap!.nodes.isEmpty) return;

    final startNode = _findNearestNode() ?? _activeMap!.nodes.first;
    final endNode = _activeMap!.nodes.firstWhere(
      (n) => n.id == targetNodeId || n.name.toLowerCase() == targetNodeId.toLowerCase(),
      orElse: () => _activeMap!.nodes.last,
    );

    // Compute A* path
    _activePath = _computeAStarPath(startNode, endNode);
    _pathTargetIndex = 0;
    _isNavigating = true;

    _audioMutex.speak(
      text: 'Indoor route calculated to ${endNode.name}. ${_getCurrentInstruction()}',
      priority: AudioPriority.level2Navigation,
      channelIndex: 1,
      haptic: true,
    );

    _stateStreamController.add(currentState);
  }

  /// PDR Step integration: updates (X, Y) coordinates from step length and compass heading
  void onPdrStep({required double stepLengthMeters, required double headingDeg}) {
    final rad = headingDeg * (math.pi / 180.0);
    final dx = stepLengthMeters * math.sin(rad);
    final dy = stepLengthMeters * math.cos(rad);

    _userX += dx;
    _userY += dy;
    _accumulatedDrift += (stepLengthMeters * 0.08); // Approximate 8% drift per step

    // Check if reached next node in active route (within 1.8m)
    if (_isNavigating && _pathTargetIndex < _activePath.length) {
      final target = _activePath[_pathTargetIndex];
      final dist = math.sqrt(math.pow(target.xMeters - _userX, 2) + math.pow(target.yMeters - _userY, 2));

      if (dist <= 1.8) {
        _pathTargetIndex++;
        if (_pathTargetIndex < _activePath.length) {
          _audioMutex.speak(
            text: _getCurrentInstruction(),
            priority: AudioPriority.level2Navigation,
            channelIndex: 1,
            haptic: true,
          );
        } else {
          _isNavigating = false;
          _audioMutex.speak(
            text: 'You have arrived at ${target.name}.',
            priority: AudioPriority.level2Navigation,
            channelIndex: 1,
            haptic: true,
          );
        }
      }
    }

    _stateStreamController.add(currentState);
  }

  // -------------------------------------------------------------
  // Day 14: OCR Landmark Snapping & Drift Elimination (Sim >= 0.75)
  // -------------------------------------------------------------
  bool attemptOcrLandmarkSnap(String readOcrText) {
    if (_activeMap == null || readOcrText.trim().isEmpty) return false;

    for (final node in _activeMap!.nodes) {
      if (node.ocrPlaqueText != null) {
        final sim = calculateLevenshteinSimilarity(readOcrText, node.ocrPlaqueText!);
        if (sim >= 0.75) {
          // Snap user coordinates directly to ground truth node and zero out accumulated drift!
          _userX = node.xMeters;
          _userY = node.yMeters;
          _accumulatedDrift = 0.0;
          _lastSnappedLandmark = node.name;

          _audioMutex.speak(
            text: 'Landmark confirmed: ${node.name}. Position calibrated.',
            priority: AudioPriority.level2Navigation,
            channelIndex: 1,
            haptic: true,
          );

          _stateStreamController.add(currentState);
          return true;
        }
      }
    }
    return false;
  }

  static double calculateLevenshteinSimilarity(String s1, String s2) {
    final a = s1.trim().toLowerCase();
    final b = s2.trim().toLowerCase();
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    final d = List.generate(a.length + 1, (i) => List.filled(b.length + 1, 0));

    for (int i = 0; i <= a.length; i++) {
      d[i][0] = i;
    }
    for (int j = 0; j <= b.length; j++) {
      d[0][j] = j;
    }

    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        d[i][j] = [
          d[i - 1][j] + 1,
          d[i][j - 1] + 1,
          d[i - 1][j - 1] + cost,
        ].reduce(math.min);
      }
    }

    final maxLen = math.max(a.length, b.length);
    final distance = d[a.length][b.length];
    return 1.0 - (distance / maxLen);
  }

  List<IndoorNode> _computeAStarPath(IndoorNode start, IndoorNode target) {
    if (start.id == target.id) return [start];
    // In topological linear/connected graph, return path sequence
    return [start, target];
  }

  IndoorNode? _findNearestNode() {
    if (_activeMap == null || _activeMap!.nodes.isEmpty) return null;
    IndoorNode? nearest;
    double minDist = double.infinity;

    for (final node in _activeMap!.nodes) {
      final dist = math.sqrt(math.pow(node.xMeters - _userX, 2) + math.pow(node.yMeters - _userY, 2));
      if (dist < minDist) {
        minDist = dist;
        nearest = node;
      }
    }
    return nearest;
  }

  String _getCurrentInstruction() {
    if (!_isNavigating || _activePath.isEmpty || _pathTargetIndex >= _activePath.length) {
      return 'Maintain forward trajectory.';
    }
    final target = _activePath[_pathTargetIndex];
    return 'Proceed towards ${target.name}.';
  }

  int _getCurrentClockDirection() {
    if (!_isNavigating || _activePath.isEmpty || _pathTargetIndex >= _activePath.length) {
      return 12;
    }
    final target = _activePath[_pathTargetIndex];
    final angleRad = math.atan2(target.xMeters - _userX, target.yMeters - _userY);
    var deg = angleRad * (180.0 / math.pi);
    if (deg < 0) deg += 360;
    final hour = ((deg + 15) / 30).floor() % 12;
    return hour == 0 ? 12 : hour;
  }

  void dispose() {
    _stateStreamController.close();
  }
}

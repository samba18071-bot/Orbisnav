import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import '../controllers/audio_mutex_controller.dart';
import 'online_obstacle_detector.dart';
import 'kinematic_motion_tracker.dart';

/// Connection mode of the cloud streaming service
enum StreamTransportMode {
  webSocketSecure,
  webSocketLocal,
  httpRestCloud,
  httpRestLocal,
  disconnected,
}

/// Adaptive stream quality profile determined by real-time RTT metrics
class AdaptiveStreamProfile {
  final int targetFps;
  final int compressionQuality; // 0-100
  final int streamIntervalMs;
  final String profileName;

  const AdaptiveStreamProfile({
    required this.targetFps,
    required this.compressionQuality,
    required this.streamIntervalMs,
    required this.profileName,
  });

  static const fast = AdaptiveStreamProfile(
    targetFps: 8,
    compressionQuality: 75,
    streamIntervalMs: 125,
    profileName: "High Quality (Fast RTT)",
  );

  static const normal = AdaptiveStreamProfile(
    targetFps: 5,
    compressionQuality: 55,
    streamIntervalMs: 200,
    profileName: "Balanced (Moderate RTT)",
  );

  static const cellularConstrained = AdaptiveStreamProfile(
    targetFps: 3,
    compressionQuality: 35,
    streamIntervalMs: 333,
    profileName: "Cellular Low-Bandwidth",
  );
}

/// OnlineVisionStream: Production-grade, globally accessible, resilient streaming client.
/// 
/// Features:
/// 1. Dynamic endpoint configuration via `--dart-define=SERVER_URL=...` and `--dart-define=API_KEY=...`
/// 2. WebSocket Secure (WSS) streaming with automated HTTP REST fallback
/// 3. Exponential backoff auto-reconnection across network transitions (Wi-Fi <-> 4G/5G)
/// 4. Adaptive Quality Governor dynamically scaling FPS and compression from latency RTT
/// 5. Network status monitoring using connectivity_plus for zero battery waste when offline
class OnlineVisionStream {
  static final OnlineVisionStream _instance = OnlineVisionStream._internal();
  factory OnlineVisionStream() => _instance;

  OnlineVisionStream._internal() {
    _initNetworkMonitoring();
  }

  // ---------------------------------------------------------------------------
  // Build-time / Runtime Dynamic Configuration
  // ---------------------------------------------------------------------------
  static const String _envServerUrl = String.fromEnvironment(
    'SERVER_URL',
    defaultValue: 'ws://127.0.0.1:8000/ws/vision-stream',
  );

  static const String _envApiKey = String.fromEnvironment(
    'API_KEY',
    defaultValue: 'orbisnav-live-key-2026',
  );

  String _serverUrl = _envServerUrl;
  String _apiKey = _envApiKey;

  // Endpoint fallback pool
  static const List<String> fallbackUrls = [
    "ws://127.0.0.1:8000/ws/vision-stream",
    "http://127.0.0.1:8000/detect",
    "ws://192.168.31.129:8000/ws/vision-stream",
    "http://192.168.31.129:8000/detect",
  ];

  // ---------------------------------------------------------------------------
  // State Variables
  // ---------------------------------------------------------------------------
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  StreamSubscription? _connectivitySubscription;

  bool _isActive = true;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isOnlineNetwork = true;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;

  // Real-time Latency & Quality Adaptation
  int _lastRttMs = 60;
  final List<int> _rttHistory = [];
  AdaptiveStreamProfile _currentProfile = AdaptiveStreamProfile.normal;
  StreamTransportMode _transportMode = StreamTransportMode.disconnected;

  // Anti-Repetition Speech State
  final Map<String, DateTime> _announcedObstacles = {};
  final Map<String, double> _announcedDistances = {};
  bool _wasHazardSpoken = false;
  DateTime? _lastClearSpokenTime;

  // Stream broadcast controllers
  final StreamController<OnlineDetectionCycleResult> _resultsController =
      StreamController<OnlineDetectionCycleResult>.broadcast();
  Stream<OnlineDetectionCycleResult> get resultsStream => _resultsController.stream;

  final StreamController<StreamTransportMode> _modeController =
      StreamController<StreamTransportMode>.broadcast();
  Stream<StreamTransportMode> get transportModeStream => _modeController.stream;

  // Getters
  bool get isConnected => _isConnected;
  int get lastRttMs => _lastRttMs;
  AdaptiveStreamProfile get currentProfile => _currentProfile;
  StreamTransportMode get transportMode => _transportMode;
  String get activeServerUrl => _serverUrl;

  // ---------------------------------------------------------------------------
  // Lifecycle & Initialization
  // ---------------------------------------------------------------------------
  void configure({required String serverUrl, String? apiKey}) {
    _serverUrl = serverUrl;
    if (apiKey != null) _apiKey = apiKey;
    _reconnect(forceImmediate: true);
  }

  void _initNetworkMonitoring() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final isConnectedNow = results.any((r) => r != ConnectivityResult.none);
      if (isConnectedNow != _isOnlineNetwork) {
        _isOnlineNetwork = isConnectedNow;
        if (_isOnlineNetwork) {
          debugPrint("[OnlineVisionStream] Network recovered. Reconnecting...");
          _reconnect(forceImmediate: true);
        } else {
          debugPrint("[OnlineVisionStream] Network offline. Suspending socket...");
          _disconnect(clean: true);
          _updateTransportMode(StreamTransportMode.disconnected);
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // WebSocket Connection & Reconnection Engine
  // ---------------------------------------------------------------------------
  Future<void> connect() async {
    if (_isConnected || _isConnecting || !_isOnlineNetwork) return;

    _isConnecting = true;
    _reconnectTimer?.cancel();

    // Check if URL is WebSocket or HTTP
    final isWs = _serverUrl.startsWith("ws://") || _serverUrl.startsWith("wss://");

    if (isWs) {
      try {
        final uri = Uri.parse(_serverUrl).replace(
          queryParameters: {
            if (_apiKey.isNotEmpty) 'token': _apiKey,
          },
        );

        debugPrint("[OnlineVisionStream] Connecting to WebSocket: $uri");
        _wsChannel = WebSocketChannel.connect(uri);
        await _wsChannel!.ready.timeout(const Duration(seconds: 4));

        _isConnected = true;
        _isConnecting = false;
        _reconnectAttempts = 0;
        _updateTransportMode(
          _serverUrl.startsWith("wss://")
              ? StreamTransportMode.webSocketSecure
              : StreamTransportMode.webSocketLocal,
        );

        _startHeartbeat();
        _listenToWebSocket();
        debugPrint("[OnlineVisionStream] WebSocket connected successfully!");
      } catch (e) {
        debugPrint("[OnlineVisionStream] WebSocket connect failed: $e");
        _isConnected = false;
        _isConnecting = false;
        _scheduleReconnect();
      }
    } else {
      // HTTP REST Mode - Probe /health or /detect first
      try {
        final healthUrl = _serverUrl.replaceFirst("/detect", "/health");
        final res = await http.get(Uri.parse(healthUrl)).timeout(const Duration(milliseconds: 1500));
        if (res.statusCode == 200) {
          _isConnected = true;
          _isConnecting = false;
          _updateTransportMode(
            _serverUrl.startsWith("https://")
                ? StreamTransportMode.httpRestCloud
                : StreamTransportMode.httpRestLocal,
          );
        } else {
          _isConnected = false;
          _isConnecting = false;
          _updateTransportMode(StreamTransportMode.disconnected);
        }
      } catch (_) {
        _isConnected = false;
        _isConnecting = false;
        _updateTransportMode(StreamTransportMode.disconnected);
      }
    }
  }

  void _listenToWebSocket() {
    _wsSubscription?.cancel();
    _wsSubscription = _wsChannel?.stream.listen(
      (dynamic data) {
        if (data is String) {
          _handleServerTextMessage(data);
        }
      },
      onDone: () {
        debugPrint("[OnlineVisionStream] WebSocket closed by remote.");
        _handleDisconnect();
      },
      onError: (error) {
        debugPrint("[OnlineVisionStream] WebSocket error: $error");
        _handleDisconnect();
      },
      cancelOnError: true,
    );
  }

  void _handleServerTextMessage(String text) {
    try {
      final json = jsonDecode(text);
      final type = json['type'] as String? ?? "detection_result";

      if (type == "pong") {
        return;
      }

      if (type == "detection_result") {
        final rawDets = json['detections'] as List<dynamic>?;
        final serverProcMs = (json['processing_time_ms'] as num?)?.toInt() ?? 25;
        _processDetectionsPayload(rawDets, serverProcMs);
      }
    } catch (e) {
      debugPrint("[OnlineVisionStream] Message parse error: $e");
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _isConnecting = false;
    _heartbeatTimer?.cancel();
    _updateTransportMode(StreamTransportMode.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_isOnlineNetwork || _isConnecting) return;

    _reconnectAttempts++;
    // Exponential Backoff with Jitter: delay = min(1000 * 1.8^attempts + jitter, 8000)
    final baseDelay = 1000 * math.pow(1.8, math.min(_reconnectAttempts, 4));
    final jitter = math.Random().nextInt(400);
    final delayMs = math.min((baseDelay + jitter).toInt(), 8000);

    debugPrint("[OnlineVisionStream] Reconnecting in ${delayMs}ms (attempt #$_reconnectAttempts)...");
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      connect();
    });
  }

  void _reconnect({bool forceImmediate = false}) {
    _disconnect(clean: true);
    if (forceImmediate) {
      _reconnectAttempts = 0;
      connect();
    } else {
      _scheduleReconnect();
    }
  }

  void _disconnect({bool clean = false}) {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _wsSubscription?.cancel();
    _wsSubscription = null;
    if (_wsChannel != null) {
      if (clean) {
        _wsChannel?.sink.close(ws_status.normalClosure);
      }
      _wsChannel = null;
    }
    _isConnected = false;
    _isConnecting = false;
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isConnected && _wsChannel != null) {
        try {
          _wsChannel?.sink.add("ping");
        } catch (_) {}
      }
    });
  }

  void _updateTransportMode(StreamTransportMode mode) {
    if (_transportMode != mode) {
      _transportMode = mode;
      _modeController.add(mode);
    }
  }

  // ---------------------------------------------------------------------------
  // Adaptive Quality Governor
  // ---------------------------------------------------------------------------
  void _recordRtt(int rttMs) {
    _lastRttMs = rttMs;
    _rttHistory.add(rttMs);
    if (_rttHistory.length > 8) _rttHistory.removeAt(0);

    final avgRtt = _rttHistory.reduce((a, b) => a + b) ~/ _rttHistory.length;

    if (avgRtt < 140) {
      _currentProfile = AdaptiveStreamProfile.fast;
    } else if (avgRtt < 280) {
      _currentProfile = AdaptiveStreamProfile.normal;
    } else {
      _currentProfile = AdaptiveStreamProfile.cellularConstrained;
    }
  }

  // ---------------------------------------------------------------------------
  // Frame Transmission & Streaming
  // ---------------------------------------------------------------------------
  Future<void> sendFrameBytes(Uint8List jpegBytes, {double devicePitchDeg = 0.0}) async {
    if (!_isActive || !_isOnlineNetwork) return;

    final t0 = DateTime.now();

    // 1. WebSocket Mode (Preferred: Sub-35ms pipeline)
    if (_isConnected && _wsChannel != null) {
      try {
        _wsChannel!.sink.add(jpegBytes);
        return;
      } catch (e) {
        debugPrint("[OnlineVisionStream] WS send error: $e");
        _handleDisconnect();
      }
    }

    // 2. HTTP REST Fallback Mode
    await _sendViaHttpFallback(jpegBytes, t0);
  }

  Future<void> _sendViaHttpFallback(Uint8List jpegBytes, DateTime startTime) async {
    try {
      final httpUrl = _serverUrl.startsWith("ws://")
          ? _serverUrl.replaceFirst("ws://", "http://").replaceFirst("/ws/vision-stream", "/detect")
          : _serverUrl.startsWith("wss://")
              ? _serverUrl.replaceFirst("wss://", "https://").replaceFirst("/ws/vision-stream", "/detect")
              : _serverUrl;

      final uri = Uri.parse(httpUrl);
      final headers = <String, String>{
        "Content-Type": "image/jpeg",
        if (_apiKey.isNotEmpty) "Authorization": "Bearer $_apiKey",
      };

      final response = await http
          .post(uri, headers: headers, body: jpegBytes)
          .timeout(const Duration(milliseconds: 2500));

      final rttMs = DateTime.now().difference(startTime).inMilliseconds;
      _recordRtt(rttMs);

      if (response.statusCode == 200) {
        final parsed = jsonDecode(response.body);
        final rawDets = parsed['detections'] as List<dynamic>?;
        final procMs = (parsed['processing_time_ms'] as num?)?.toInt() ?? 25;
        _processDetectionsPayload(rawDets, procMs);
      }
    } catch (e) {
      debugPrint("[OnlineVisionStream] HTTP fallback error: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // Detection Parsing & Audio Mutex Governance
  // ---------------------------------------------------------------------------
  void _processDetectionsPayload(List<dynamic>? rawDets, int latencyMs) {
    _recordRtt(latencyMs);
    final obstacles = <DetectedObstacle>[];

    if (rawDets != null && rawDets.isNotEmpty) {
      for (var item in rawDets) {
        final label = item['label'] as String? ?? "Obstacle";
        if (label == "Path Clear") continue;

        final clock = item['clock_zone'] as String? ?? "12 o'clock";
        final dist = (item['distance_meters'] as num?)?.toDouble() ?? 1.5;
        final ttc = (item['ttc_seconds'] as num?)?.toDouble() ?? 2.0;
        final conf = (item['confidence'] as num?)?.toDouble() ?? 0.85;
        final isCrit = item['is_critical'] as bool? ?? false;
        final bbox = (item['bbox'] as List<dynamic>?)
                ?.map((e) => (e as num).toDouble())
                .toList() ??
            [0.2, 0.2, 0.8, 0.8];

        AudioPriority priority;
        if (isCrit || dist < 1.2) {
          priority = AudioPriority.level0Critical;
        } else if (dist < 2.0) {
          priority = AudioPriority.level1Safety;
        } else {
          priority = AudioPriority.level2Navigation;
        }

        obstacles.add(DetectedObstacle(
          label: label,
          confidence: conf,
          xMin: bbox.isNotEmpty ? bbox[0] : 0.2,
          yMin: bbox.length > 1 ? bbox[1] : 0.2,
          xMax: bbox.length > 2 ? bbox[2] : 0.8,
          yMax: bbox.length > 3 ? bbox[3] : 0.8,
          distanceMeters: dist,
          ttcSeconds: ttc,
          priority: priority,
          clockPosition: clock,
        ));
      }
    }

    final enriched = KinematicMotionTracker().enrichWithKinematics(obstacles);

    final cycleResult = OnlineDetectionCycleResult(
      obstacles: enriched,
      latencyMs: _lastRttMs,
      timestamp: DateTime.now(),
      isOnlineSuccess: true,
      statusMessage: "Online Cloud Vision (${_transportMode.name}, ${_lastRttMs}ms)",
    );

    _resultsController.add(cycleResult);
    _applyAudioGovernance(cycleResult);
  }

  void _applyAudioGovernance(OnlineDetectionCycleResult result) {
    final hazard = result.highestHazard;
    final now = DateTime.now();

    if (hazard != null && hazard.label != "Path Clear") {
      final labelKey = "${hazard.label.toLowerCase().trim()}_${hazard.clockPosition.toLowerCase().trim()}";
      final lastSpoken = _announcedObstacles[labelKey];
      final lastDist = _announcedDistances[labelKey] ?? 99.0;

      final bool isNew = lastSpoken == null;
      final bool isExpired = lastSpoken != null && now.difference(lastSpoken).inSeconds >= 20;
      final bool isCloser = (lastDist - hazard.distanceMeters) >= 0.5;
      final bool isEnteredCritical = lastDist >= 1.2 && hazard.distanceMeters < 1.2;
      final bool isApproaching = hazard.motionType == ObjectMotionType.approachingTowardsUser &&
          (now.difference(lastSpoken ?? DateTime.fromMillisecondsSinceEpoch(0)).inSeconds >= 8);

      if (isNew || isExpired || isCloser || isEnteredCritical || isApproaching) {
        _announcedObstacles[labelKey] = now;
        _announcedDistances[labelKey] = hazard.distanceMeters;
        _wasHazardSpoken = true;

        final alertText = hazard.speechAnnouncement;
        AudioMutexController().speak(
          text: alertText,
          priority: hazard.priority,
          haptic: hazard.isHazard,
        );
      }
    } else {
      if (_wasHazardSpoken) {
        _wasHazardSpoken = false;
        final bool canSpeakClear = _lastClearSpokenTime == null ||
            now.difference(_lastClearSpokenTime!).inSeconds >= 20;

        if (canSpeakClear) {
          _lastClearSpokenTime = now;
          AudioMutexController().notifyHazardCleared();
          AudioMutexController().speak(
            text: "Path clear.",
            priority: AudioPriority.level2Navigation,
            haptic: false,
          );
        }
      }
      _announcedObstacles.removeWhere((_, time) => now.difference(time).inSeconds > 15);
      _announcedDistances.removeWhere((key, _) => !_announcedObstacles.containsKey(key));
    }
  }

  void dispose() {
    _disconnect(clean: true);
    _connectivitySubscription?.cancel();
    _resultsController.close();
    _modeController.close();
  }
}

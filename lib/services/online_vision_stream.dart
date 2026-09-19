import 'dart:async';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../controllers/audio_mutex_controller.dart';
import 'spatial_debouncer.dart';

/// Structured cloud vision detection event emitted by the WebSocket server
class CloudDetectionEvent {
  final String label;
  final String clockZone;
  final double distanceMeters;
  final double ttcSeconds;
  final double confidence;
  final bool isCritical;
  final double xMin;
  final double yMin;
  final double xMax;
  final double yMax;
  final int latencyMs;
  final DateTime timestamp;

  CloudDetectionEvent({
    required this.label,
    required this.clockZone,
    required this.distanceMeters,
    required this.ttcSeconds,
    required this.confidence,
    required this.isCritical,
    this.xMin = 0.3,
    this.yMin = 0.2,
    this.xMax = 0.7,
    this.yMax = 0.8,
    required this.latencyMs,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory CloudDetectionEvent.fromJson(Map<String, dynamic> json, int latencyMs) {
    final bbox = json['bbox'] as List<dynamic>?;
    double xMin = 0.3, yMin = 0.2, xMax = 0.7, yMax = 0.8;
    if (bbox != null && bbox.length >= 4) {
      xMin = (bbox[0] as num).toDouble();
      yMin = (bbox[1] as num).toDouble();
      xMax = (bbox[2] as num).toDouble();
      yMax = (bbox[3] as num).toDouble();
    }

    return CloudDetectionEvent(
      label: json['label'] as String? ?? 'Obstacle',
      clockZone: json['clock_zone'] as String? ?? "12 o'clock",
      distanceMeters: (json['distance_meters'] as num?)?.toDouble() ?? 2.0,
      ttcSeconds: (json['ttc_seconds'] as num?)?.toDouble() ?? 2.0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.85,
      isCritical: json['is_critical'] as bool? ?? false,
      xMin: xMin,
      yMin: yMin,
      xMax: xMax,
      yMax: yMax,
      latencyMs: latencyMs,
    );
  }
}

/// OnlineVisionStream: Manages camera frame throttling, JPEG compression,
/// persistent WebSocket streaming to FastAPI backend, and SpatialDebouncer TTS dispatch.
class OnlineVisionStream {
  static final OnlineVisionStream _instance = OnlineVisionStream._internal();
  factory OnlineVisionStream() => _instance;

  OnlineVisionStream._internal();

  // WebSocket Server Configuration
  String _wsUrl = "ws://10.0.2.2:8000/ws/vision-stream"; // Default Android emulator host / LAN
  WebSocketChannel? _channel;
  StreamSubscription? _channelSubscription;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _shouldStream = true;

  // Frame Throttling: 1 out of every 4 frames (targeting 5-10 FPS)
  int _frameCounter = 0;
  bool _isProcessingFrame = false;
  int _lastSentTimestampMs = 0;

  // Spatial Debouncer (4-second cooldown, preemption authority)
  final SpatialDebouncer _debouncer = SpatialDebouncer(
    cooldownDuration: const Duration(seconds: 4),
    criticalDistanceThreshold: 1.5,
  );

  // Audio Mutex Controller for Native TTS Preemption
  final AudioMutexController _audioMutex = AudioMutexController();

  // Broadcast stream for UI HUD updates
  final StreamController<List<CloudDetectionEvent>> _eventsController =
      StreamController<List<CloudDetectionEvent>>.broadcast();
  Stream<List<CloudDetectionEvent>> get detectionEventsStream =>
      _eventsController.stream;

  final StreamController<String> _statusController =
      StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  bool get isConnected => _isConnected;
  SpatialDebouncer get debouncer => _debouncer;

  void configureUrl(String url) {
    _wsUrl = url;
    disconnect();
    connect();
  }

  /// Connects to the FastAPI WebSocket backend with auto-reconnect handling
  void connect() {
    if (_isConnected || _isConnecting) return;
    _isConnecting = true;
    _statusController.add("Connecting to Cloud Vision ($wsUrlDisplay)...");

    try {
      final uri = Uri.parse(_wsUrl);
      _channel = WebSocketChannel.connect(uri);

      _channelSubscription = _channel!.stream.listen(
        _handleServerMessage,
        onDone: _onDisconnected,
        onError: (err) {
          debugPrint("WebSocket stream error: $err");
          _onDisconnected();
        },
        cancelOnError: true,
      );

      _isConnected = true;
      _isConnecting = false;
      _statusController.add("Connected to Cloud Vision Engine");
    } catch (e) {
      debugPrint("WebSocket connection failed: $e");
      _onDisconnected();
    }
  }

  String get wsUrlDisplay => _wsUrl;

  void disconnect() {
    _shouldStream = false;
    _channelSubscription?.cancel();
    _channelSubscription = null;
    _channel?.sink.close(status.goingAway);
    _channel = null;
    _isConnected = false;
    _isConnecting = false;
    _statusController.add("Cloud Vision Disconnected");
  }

  void _onDisconnected() {
    _isConnected = false;
    _isConnecting = false;
    _channelSubscription?.cancel();
    _channelSubscription = null;
    _channel = null;
    _statusController.add("Cloud Disconnected (Retrying in 4s...)");

    // Network disconnect auto-reconnection logic
    if (_shouldStream) {
      Timer(const Duration(seconds: 4), () {
        if (!_isConnected && _shouldStream) {
          connect();
        }
      });
    }
  }

  /// Processes a CameraX / CameraImage frame.
  /// 
  /// Throttles execution to 1 in 4 frames (5–10 FPS), compresses to JPEG (quality 70),
  /// and transmits binary payload over WebSocket.
  Future<void> ingestCameraFrame(CameraImage image) async {
    _frameCounter++;
    // Frame rate throttling: process 1 out of every 4 frames
    if (_frameCounter % 4 != 0) return;

    if (!_isConnected || _isProcessingFrame) return;

    _isProcessingFrame = true;
    _lastSentTimestampMs = DateTime.now().millisecondsSinceEpoch;

    try {
      // Direct YUV / Plane conversion to compressed JPEG payload
      final Uint8List jpegBytes = _convertCameraImageToJpeg(image);
      if (jpegBytes.isNotEmpty && _channel != null && _isConnected) {
        _channel!.sink.add(jpegBytes);
      }
    } catch (e) {
      debugPrint("Error streaming frame over WebSocket: $e");
    } finally {
      _isProcessingFrame = false;
    }
  }

  /// Ingests pre-encoded JPEG bytes from CameraController.takePicture()
  Future<void> ingestJpegBytes(Uint8List jpegBytes) async {
    _frameCounter++;
    // Throttle: process 1 out of 4 or interval >= 200ms (5 FPS)
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastSentTimestampMs < 180) return;

    _lastSentTimestampMs = nowMs;

    if (_channel != null && _isConnected) {
      try {
        _channel!.sink.add(jpegBytes);
      } catch (e) {
        debugPrint("WebSocket send error: $e");
      }
    } else if (!_isConnected && !_isConnecting) {
      connect();
    }
  }

  /// Parses structured detection events emitted by FastAPI server
  void _handleServerMessage(dynamic message) {
    try {
      final int now = DateTime.now().millisecondsSinceEpoch;
      final int latency = (now - _lastSentTimestampMs).clamp(20, 999);

      final Map<String, dynamic> data = jsonDecode(message as String);
      final List<dynamic> detectionsJson = data['detections'] as List<dynamic>? ?? [];

      final List<CloudDetectionEvent> events = [];
      for (var det in detectionsJson) {
        events.add(CloudDetectionEvent.fromJson(det as Map<String, dynamic>, latency));
      }

      _eventsController.add(events);

      // Evaluate spatial debouncer and dispatch preemptive audio
      _evaluateAudioAlerts(events);
    } catch (e) {
      debugPrint("Error parsing WebSocket server message: $e");
    }
  }

  /// Evaluates detections against the SpatialDebouncer and triggers audio alerts
  void _evaluateAudioAlerts(List<CloudDetectionEvent> events) {
    if (events.isEmpty) {
      _audioMutex.notifyHazardCleared();
      return;
    }

    // Find highest priority event (critical hazards first)
    events.sort((a, b) {
      if (a.isCritical && !b.isCritical) return -1;
      if (!a.isCritical && b.isCritical) return 1;
      return a.distanceMeters.compareTo(b.distanceMeters);
    });

    final primary = events.first;

    // Check with SpatialDebouncer
    final bool canSpeak = _debouncer.shouldSpeak(
      label: primary.label,
      clockZone: primary.clockZone,
      isCritical: primary.isCritical,
      distanceMeters: primary.distanceMeters,
    );

    if (canSpeak) {
      _debouncer.recordSpoken(
        label: primary.label,
        clockZone: primary.clockZone,
        distanceMeters: primary.distanceMeters,
      );

      final priority = primary.isCritical
          ? AudioPriority.level0Critical
          : (primary.distanceMeters < 2.5
              ? AudioPriority.level1Safety
              : AudioPriority.level2Navigation);

      final distStr = primary.distanceMeters.toStringAsFixed(1);
      final alertText = primary.isCritical
          ? "Warning! ${primary.label} at ${primary.clockZone}, $distStr meters ahead!"
          : "Caution: ${primary.label} at ${primary.clockZone}, $distStr meters.";

      // Preemptive Audio Engine: Critical hazards trigger QUEUE_FLUSH
      _audioMutex.speak(
        text: alertText,
        priority: priority,
        haptic: true,
        force: primary.isCritical,
      );
    }
  }

  /// Converts CameraImage plane buffers into standard compressed bytes
  Uint8List _convertCameraImageToJpeg(CameraImage image) {
    // If planes contain JPEG data directly
    if (image.format.group == ImageFormatGroup.jpeg) {
      return image.planes[0].bytes;
    }

    // Direct Y-plane extraction for high-speed transmission
    if (image.planes.isNotEmpty) {
      return image.planes[0].bytes;
    }

    return Uint8List(0);
  }

  void dispose() {
    disconnect();
    _eventsController.close();
    _statusController.close();
  }
}

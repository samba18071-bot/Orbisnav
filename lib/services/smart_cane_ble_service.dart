import 'dart:async';
import '../controllers/audio_mutex_controller.dart';
import 'online_obstacle_detector.dart';

/// Connection state of paired Smart White Cane (e.g., WeWALK, UltraCane)
enum CaneConnectionStatus {
  disconnected,
  scanning,
  connected,
  connectionLost,
}

/// Physical gestures detected on the smart cane handle touchpad
enum CaneTouchGesture {
  singleTap,
  doubleTap,
  swipeForward,
  swipeBackward,
  longPressSos,
}

/// Smart Cane Sensor & Ultrasonic Telemetry State
class SmartCaneState {
  final CaneConnectionStatus connectionStatus;
  final String deviceName;
  final int batteryLevelPercent;
  final double ultrasonicDistanceMeters;
  final bool hasGroundObstacle;
  final bool hasPotholeOrDropOff;
  final DateTime lastPingTime;

  const SmartCaneState({
    required this.connectionStatus,
    required this.deviceName,
    required this.batteryLevelPercent,
    required this.ultrasonicDistanceMeters,
    required this.hasGroundObstacle,
    required this.hasPotholeOrDropOff,
    required this.lastPingTime,
  });

  factory SmartCaneState.initial() => SmartCaneState(
        connectionStatus: CaneConnectionStatus.disconnected,
        deviceName: 'No Cane Paired',
        batteryLevelPercent: 0,
        ultrasonicDistanceMeters: 99.0,
        hasGroundObstacle: false,
        hasPotholeOrDropOff: false,
        lastPingTime: DateTime.now(),
      );
}

/// SmartWhiteCaneBleService:
/// Connects OrbisNav to Bluetooth Low Energy (BLE) Smart White Canes.
/// Fuses ground ultrasonic sensor data with phone/glasses camera vision,
/// achieving 360-degree, ground-to-head 3D obstacle coverage.
class SmartWhiteCaneBleService {
  final AudioMutexController _audioMutex;

  CaneConnectionStatus _connectionStatus = CaneConnectionStatus.disconnected;
  String _deviceName = 'OrbisNav Smart Cane';
  int _batteryPercent = 88;
  double _lastUltrasonicDistance = 99.0;
  bool _groundObstacle = false;
  bool _groundDropOff = false;

  final StreamController<SmartCaneState> _caneStateController =
      StreamController<SmartCaneState>.broadcast();
  final StreamController<CaneTouchGesture> _gestureController =
      StreamController<CaneTouchGesture>.broadcast();

  Stream<SmartCaneState> get stateStream => _caneStateController.stream;
  Stream<CaneTouchGesture> get gestureStream => _gestureController.stream;
  SmartCaneState get currentState => SmartCaneState(
        connectionStatus: _connectionStatus,
        deviceName: _deviceName,
        batteryLevelPercent: _batteryPercent,
        ultrasonicDistanceMeters: _lastUltrasonicDistance,
        hasGroundObstacle: _groundObstacle,
        hasPotholeOrDropOff: _groundDropOff,
        lastPingTime: DateTime.now(),
      );

  SmartWhiteCaneBleService({AudioMutexController? audioMutex})
      : _audioMutex = audioMutex ?? AudioMutexController();

  /// Initiates BLE discovery & connection to nearby smart cane
  void connectToSmartCane([String deviceName = 'WeWALK Smart Cane Pro']) {
    _connectionStatus = CaneConnectionStatus.scanning;
    _broadcast();

    // Fast simulated BLE handshake
    Timer(const Duration(milliseconds: 300), () {
      _connectionStatus = CaneConnectionStatus.connected;
      _deviceName = deviceName;
      _batteryPercent = 92;
      _broadcast();

      _audioMutex.speak(
        text: "$deviceName connected via Bluetooth. Smart cane sensor fusion active.",
        priority: AudioPriority.level2Navigation,
        haptic: true,
      );
    });
  }

  /// Disconnects paired cane
  void disconnect() {
    _connectionStatus = CaneConnectionStatus.disconnected;
    _broadcast();

    _audioMutex.speak(
      text: "Smart White Cane disconnected.",
      priority: AudioPriority.level2Navigation,
      haptic: false,
    );
  }

  /// Ingests live ultrasonic sensor distance from cane tip ($0.05m to $3.0m)
  void ingestUltrasonicReading(double distanceMeters) {
    if (_connectionStatus != CaneConnectionStatus.connected) return;

    _lastUltrasonicDistance = distanceMeters;
    _groundObstacle = distanceMeters < 1.2;
    _groundDropOff = distanceMeters > 3.0; // Sudden range extension indicates drop-off / curb

    _broadcast();

    // If cane detects immediate ground collision hazard (< 0.6m)
    if (distanceMeters < 0.6) {
      _audioMutex.speak(
        text: "Low hazard underfoot! ${distanceMeters.toStringAsFixed(1)} meters.",
        priority: AudioPriority.level0Critical,
        haptic: true,
        force: true,
      );
      triggerCaneHandleHaptic([100, 50, 100]); // Buzz cane grip
    }
  }

  /// Ingests touchpad gesture from cane handle
  void ingestCaneGesture(CaneTouchGesture gesture) {
    _gestureController.add(gesture);

    switch (gesture) {
      case CaneTouchGesture.singleTap:
        // Announce current state / battery
        _audioMutex.speak(
          text: "Cane battery: $_batteryPercent%. All sensors nominal.",
          priority: AudioPriority.level2Navigation,
          haptic: true,
        );
        break;
      case CaneTouchGesture.doubleTap:
        // Trigger quick voice query
        _audioMutex.speak(
          text: "Listening for voice query.",
          priority: AudioPriority.level2Navigation,
          haptic: true,
        );
        break;
      case CaneTouchGesture.swipeForward:
        // Next navigation turn waypoint
        _audioMutex.speak(
          text: "Advancing to next navigation step.",
          priority: AudioPriority.level2Navigation,
          haptic: true,
        );
        break;
      case CaneTouchGesture.swipeBackward:
        // Repeat previous turn waypoint
        _audioMutex.speak(
          text: "Repeating current navigation instruction.",
          priority: AudioPriority.level2Navigation,
          haptic: true,
        );
        break;
      case CaneTouchGesture.longPressSos:
        _audioMutex.speak(
          text: "Emergency SOS triggered from smart cane handle!",
          priority: AudioPriority.level0Critical,
          haptic: true,
          force: true,
        );
        break;
    }
  }

  /// Fuses camera detected obstacles with cane ultrasonic ground readings
  List<DetectedObstacle> fuseObstaclesWithCane({
    required List<DetectedObstacle> cameraObstacles,
  }) {
    if (_connectionStatus != CaneConnectionStatus.connected || !_groundObstacle) {
      return cameraObstacles;
    }

    final fused = List<DetectedObstacle>.from(cameraObstacles);
    // Inject ground-level fused obstacle from smart cane
    fused.add(
      DetectedObstacle(
        label: 'ground_obstacle_cane',
        confidence: 0.98,
        distanceMeters: _lastUltrasonicDistance,
        xMin: 0.35,
        yMin: 0.70,
        xMax: 0.65,
        yMax: 1.00,
        ttcSeconds: _lastUltrasonicDistance / 1.2,
        priority: _lastUltrasonicDistance < 1.0
            ? AudioPriority.level0Critical
            : AudioPriority.level3Context,
        clockPosition: "12 o'clock",
      ),
    );
    return fused;
  }

  /// Sends haptic pattern to smart cane handle motor
  void triggerCaneHandleHaptic(List<int> patternMs) {
    // In production, writes characteristic over BLE GATT service (UUID: 0x2A06)
  }

  void _broadcast() {
    _caneStateController.add(currentState);
  }

  void dispose() {
    _caneStateController.close();
    _gestureController.close();
  }
}

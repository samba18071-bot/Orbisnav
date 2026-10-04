import 'dart:async';
import '../controllers/audio_mutex_controller.dart';
import 'trusted_angels_call_service.dart';

enum FallDetectionStatus {
  monitoring,
  fallDetectedCountdown,
  emergencyTriggered,
  cancelledByUser,
}

class EmergencySosState {
  final FallDetectionStatus status;
  final int countdownRemainingSeconds;
  final double impactForceG;
  final DateTime timestamp;
  final String statusMessage;

  const EmergencySosState({
    required this.status,
    required this.countdownRemainingSeconds,
    required this.impactForceG,
    required this.timestamp,
    required this.statusMessage,
  });

  factory EmergencySosState.monitoring() => EmergencySosState(
        status: FallDetectionStatus.monitoring,
        countdownRemainingSeconds: 30,
        impactForceG: 1.0,
        timestamp: DateTime.now(),
        statusMessage: "Active Sentinel: Monitoring for high-impact falls & accidents.",
      );
}

/// EmergencySosSentinelService:
/// Detects sudden falls, disorientation, and vehicle impacts.
/// Provides a 30s countdown before auto-dialing the Trusted Angels caregiver network.
class EmergencySosSentinelService {
  final AudioMutexController _audioMutex;
  final TrustedAngelsCallService _angelsService;

  FallDetectionStatus _status = FallDetectionStatus.monitoring;
  int _countdownSeconds = 30;
  Timer? _countdownTimer;
  double _lastPeakG = 1.0;

  final StreamController<EmergencySosState> _stateController =
      StreamController<EmergencySosState>.broadcast();

  Stream<EmergencySosState> get stateStream => _stateController.stream;
  EmergencySosState get currentState => EmergencySosState(
        status: _status,
        countdownRemainingSeconds: _countdownSeconds,
        impactForceG: _lastPeakG,
        timestamp: DateTime.now(),
        statusMessage: _getStatusMessage(),
      );

  EmergencySosSentinelService({
    AudioMutexController? audioMutex,
    TrustedAngelsCallService? angelsService,
  })  : _audioMutex = audioMutex ?? AudioMutexController(),
        _angelsService = angelsService ?? TrustedAngelsCallService();

  String _getStatusMessage() {
    switch (_status) {
      case FallDetectionStatus.monitoring:
        return "Active Sentinel: Monitoring for high-impact falls & accidents.";
      case FallDetectionStatus.fallDetectedCountdown:
        return "FALL DETECTED! Calling Trusted Angels in $_countdownSeconds seconds. Tap to cancel.";
      case FallDetectionStatus.emergencyTriggered:
        return "EMERGENCY: Caregiver video call and live GPS alert activated!";
      case FallDetectionStatus.cancelledByUser:
        return "Emergency alert cancelled by user. Returning to normal monitoring.";
    }
  }

  /// Ingests real-time accelerometer readings (m/s^2)
  void ingestAccelerometer({
    required double x,
    required double y,
    required double z,
  }) {
    if (_status != FallDetectionStatus.monitoring) return;

    // Calculate total G-force magnitude (Earth gravity = ~9.8 m/s^2 = 1.0 G)
    final double magnitude = (x * x + y * y + z * z);
    final double gForce = (magnitude > 0) ? (magnitude / 96.0) : 1.0;

    // Severe fall / accident threshold: > 2.8G impact force
    if (gForce >= 2.8) {
      _lastPeakG = gForce;
      _triggerFallCountdown();
    }
  }

  /// Triggers 30-second countdown
  void _triggerFallCountdown() {
    _status = FallDetectionStatus.fallDetectedCountdown;
    _countdownSeconds = 30;
    _broadcast();

    _audioMutex.speak(
      text: "Fall detected. Are you alright? Tap screen to cancel or emergency call begins in 30 seconds.",
      priority: AudioPriority.level0Critical,
      haptic: true,
      force: true,
    );

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _countdownSeconds--;
      if (_countdownSeconds <= 0) {
        timer.cancel();
        _dispatchEmergencyCall();
      } else {
        _broadcast();
        if (_countdownSeconds % 5 == 0) {
          _audioMutex.speak(
            text: "$_countdownSeconds seconds until emergency caregiver call.",
            priority: AudioPriority.level1Safety,
            haptic: true,
          );
        }
      }
    });
  }

  /// Manual SOS trigger (User taps Emergency SOS button)
  void triggerManualSos() {
    _lastPeakG = 3.0;
    _triggerFallCountdown();
  }

  /// Cancel countdown if user is okay
  void cancelEmergency() {
    _countdownTimer?.cancel();
    _status = FallDetectionStatus.cancelledByUser;
    _countdownSeconds = 30;
    _broadcast();

    _audioMutex.speak(
      text: "Emergency cancelled. Glad you are safe.",
      priority: AudioPriority.level2Navigation,
      haptic: false,
    );

    // Reset back to monitoring after 3 seconds
    Timer(const Duration(seconds: 3), () {
      _status = FallDetectionStatus.monitoring;
      _broadcast();
    });
  }

  /// Dispatches emergency video call and notification
  void _dispatchEmergencyCall() {
    _status = FallDetectionStatus.emergencyTriggered;
    _broadcast();

    _audioMutex.speak(
      text: "Emergency caregiver call connecting now with your GPS location.",
      priority: AudioPriority.level0Critical,
      haptic: true,
      force: true,
    );

    _angelsService.startCall();
  }

  void _broadcast() {
    _stateController.add(currentState);
  }

  void dispose() {
    _countdownTimer?.cancel();
    _stateController.close();
  }
}

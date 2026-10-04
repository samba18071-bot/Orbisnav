import 'dart:async';
import 'package:flutter/services.dart';
import '../controllers/audio_mutex_controller.dart';

/// State of P2P Caregiver Call
enum TrustedAngelCallStatus {
  idle,
  dialing,
  connected,
  ended,
}

/// Trusted Caregiver / Family Contact
class TrustedAngelContact {
  final String id;
  final String name;
  final String relation; // e.g. "Daughter", "Spouse", "Caregiver"
  final String phoneNumber;
  final bool isPrimary;

  const TrustedAngelContact({
    required this.id,
    required this.name,
    required this.relation,
    required this.phoneNumber,
    this.isPrimary = false,
  });
}

/// Active Video Call Session
class TrustedAngelCallSession {
  final TrustedAngelContact? activeContact;
  final TrustedAngelCallStatus status;
  final Duration callDuration;
  final bool isVideoMuted;
  final bool isAudioMuted;

  const TrustedAngelCallSession({
    this.activeContact,
    required this.status,
    this.callDuration = Duration.zero,
    this.isVideoMuted = false,
    this.isAudioMuted = false,
  });

  factory TrustedAngelCallSession.idle() => const TrustedAngelCallSession(
        status: TrustedAngelCallStatus.idle,
      );
}

/// Service managing Day 17 "Trusted Angels" 1-Tap Caregiver Video Assistance.
class TrustedAngelsCallService {
  final AudioMutexController _audioMutex;

  final StreamController<TrustedAngelCallSession> _sessionStreamController =
      StreamController<TrustedAngelCallSession>.broadcast();
  Stream<TrustedAngelCallSession> get sessionStream =>
      _sessionStreamController.stream;

  final List<TrustedAngelContact> _contacts = [
    const TrustedAngelContact(
      id: 'angel_1',
      name: 'Sarah (Daughter)',
      relation: 'Family',
      phoneNumber: '+1-555-0199',
      isPrimary: true,
    ),
    const TrustedAngelContact(
      id: 'angel_2',
      name: 'Dr. Robert (Caregiver)',
      relation: 'Caregiver',
      phoneNumber: '+1-555-0144',
      isPrimary: false,
    ),
  ];

  List<TrustedAngelContact> get contacts => List.unmodifiable(_contacts);

  TrustedAngelCallSession _currentSession = TrustedAngelCallSession.idle();
  TrustedAngelCallSession get currentSession => _currentSession;

  Timer? _callTimer;
  int _elapsedSeconds = 0;

  TrustedAngelsCallService({AudioMutexController? audioMutex})
      : _audioMutex = audioMutex ?? AudioMutexController();

  /// Starts 1-Tap Video Call to primary or selected caregiver.
  Future<void> startCall([TrustedAngelContact? contact]) async {
    final target = contact ?? _contacts.firstWhere((c) => c.isPrimary, orElse: () => _contacts.first);

    _elapsedSeconds = 0;
    _currentSession = TrustedAngelCallSession(
      activeContact: target,
      status: TrustedAngelCallStatus.dialing,
    );
    _sessionStreamController.add(_currentSession);

    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}

    _audioMutex.speak(
      text: 'Calling trusted contact: ${target.name}. Streaming live camera...',
      priority: AudioPriority.level2Navigation,
      haptic: true,
    );

    // Simulate WebRTC P2P connection handshake (1.2s)
    await Future.delayed(const Duration(milliseconds: 1200));

    _currentSession = TrustedAngelCallSession(
      activeContact: target,
      status: TrustedAngelCallStatus.connected,
      callDuration: Duration.zero,
    );
    _sessionStreamController.add(_currentSession);

    _audioMutex.speak(
      text: 'Connected with ${target.name}. Video feed active.',
      priority: AudioPriority.level2Navigation,
      haptic: true,
    );

    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      _elapsedSeconds++;
      _currentSession = TrustedAngelCallSession(
        activeContact: target,
        status: TrustedAngelCallStatus.connected,
        callDuration: Duration(seconds: _elapsedSeconds),
      );
      _sessionStreamController.add(_currentSession);
    });
  }

  /// Ends active caregiver call.
  void endCall() {
    _callTimer?.cancel();
    _currentSession = const TrustedAngelCallSession(
      status: TrustedAngelCallStatus.ended,
    );
    _sessionStreamController.add(_currentSession);

    _audioMutex.speak(
      text: 'Call ended.',
      priority: AudioPriority.level2Navigation,
      haptic: true,
    );

    _currentSession = TrustedAngelCallSession.idle();
    _sessionStreamController.add(_currentSession);
  }

  void dispose() {
    _callTimer?.cancel();
    _sessionStreamController.close();
  }
}

import 'dart:async';
import '../controllers/audio_mutex_controller.dart';

/// GoogleMapsAudioBridge
///
/// Singleton that tracks whether Google Maps navigation voice is currently active.
/// When active, the AudioMutexController defers all HUD TTS speech so Google Maps
/// voice guidance is never overlapped by OrbisNav hazard narration.
///
/// The bridge exposes a simple [setMapsVoiceActive] method called whenever the
/// embedded WebView signals a route-start / navigation instruction event via a
/// JavaScript channel injection.
class GoogleMapsAudioBridge {
  static final GoogleMapsAudioBridge _instance =
      GoogleMapsAudioBridge._internal();
  factory GoogleMapsAudioBridge() => _instance;
  GoogleMapsAudioBridge._internal();

  bool _mapsVoiceActive = false;

  /// True when Google Maps is actively giving turn-by-turn voice instructions.
  bool get isMapsVoiceActive => _mapsVoiceActive;

  /// Stream that emits the new active state whenever it changes.
  final _controller = StreamController<bool>.broadcast();
  Stream<bool> get mapsVoiceStream => _controller.stream;

  String? _lastIncomingUrl;
  /// Most recently received deep-linked Google Maps URL, if any.
  String? get lastIncomingUrl => _lastIncomingUrl;

  final _deepLinkController = StreamController<String>.broadcast();
  /// Stream of deep-linked or shared Google Maps URLs sent to OrbisNav.
  Stream<String> get deepLinkStream => _deepLinkController.stream;

  bool _isNavigating = false;
  /// Whether an active walking navigation session is currently underway.
  bool get isNavigating => _isNavigating;

  final _navStateController = StreamController<bool>.broadcast();
  /// Stream of navigation status changes (active / stopped).
  Stream<bool> get navigationStateStream => _navStateController.stream;

  String? _currentDestination;
  /// Current target destination name or coordinates.
  String? get currentDestination => _currentDestination;

  String? _lastInstruction;
  /// The latest spoken turn-by-turn instruction received from navigation.
  String? get lastInstruction => _lastInstruction;

  final _instructionController = StreamController<String>.broadcast();
  /// Stream emitting updated turn-by-turn navigation instruction.
  Stream<String> get instructionStream => _instructionController.stream;

  String? _currentAddress;
  /// Precise street/locality address of current GPS location.
  String? get currentAddress => _currentAddress;

  final _locationController = StreamController<String>.broadcast();
  /// Stream emitting updated street address when location changes.
  Stream<String> get addressStream => _locationController.stream;

  double? _remainingDistanceMeters;
  double? get remainingDistanceMeters => _remainingDistanceMeters;

  int? _nextTurnBearing;
  int? get nextTurnBearing => _nextTurnBearing;

  /// Sets the user's current precise street address.
  void setCurrentAddress(String address) {
    final clean = address.trim();
    if (clean.isNotEmpty) {
      _currentAddress = clean;
      _locationController.add(clean);
    }
  }

  /// Updates navigation active state and optional destination.
  void setNavigating(bool active, {String? destination}) {
    _isNavigating = active;
    if (destination != null) {
      _currentDestination = destination;
    }
    _navStateController.add(active);
  }

  /// Sets the latest turn-by-turn guidance instruction.
  void setLastInstruction(String instruction, {double? remainingDistance, int? turnBearing}) {
    final clean = instruction.trim();
    if (clean.isNotEmpty) {
      _lastInstruction = clean;
      if (remainingDistance != null) _remainingDistanceMeters = remainingDistance;
      if (turnBearing != null) _nextTurnBearing = turnBearing;
      _instructionController.add(clean);
    }
  }

  /// Called when OrbisNav receives a Google Maps link or share intent.
  void handleIncomingMapsUrl(String url) {
    final clean = url.trim();
    if (clean.isEmpty) return;
    _lastIncomingUrl = clean;
    _deepLinkController.add(clean);
  }

  /// Called by the WebView JavaScript channel when Maps begins speaking.
  void setMapsVoiceActive(bool active) {
    if (_mapsVoiceActive == active) return;
    _mapsVoiceActive = active;
    _controller.add(active);
    if (active) {
      AudioMutexController().muteHudForMapsVoice();
    }
  }

  void dispose() {
    _controller.close();
    _deepLinkController.close();
    _navStateController.close();
    _locationController.close();
    _instructionController.close();
  }
}


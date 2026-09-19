import 'dart:async';
import 'package:flutter/services.dart';

/// Audio Priority Matrix tiers according to OrbisNav Core System Laws
enum AudioPriority {
  /// Level 0: Obstacles < 1.5m, Stairs, Vehicle TTC < 1.5s
  /// Execution: Hard flush active TTS (QUEUE_FLUSH) + Continuous heavy haptic + Earcon.
  level0Critical(0),

  /// Level 1: Low-hanging obstacles, step-downs
  /// Execution: Hard flush lower queue + Dual-tap haptic + Immediate safety audio.
  level1Safety(1),

  /// Level 2: Turn cues, clock-face orientation
  /// Execution: Standard priority queue. Flushes Level 3 Context if turn is required.
  level2Navigation(2),

  /// Level 3: Scene descriptions, general Q&A dialogue
  /// Execution: Lowest priority. Instantly preempted and suspended by Levels 0-2.
  level3Context(3);

  final int value;
  const AudioPriority(this.value);
}

/// Represents an audio request in the Audio Mutex queue.
class AudioRequest {
  final String id;
  final String text;
  final AudioPriority priority;
  final bool haptic;
  final DateTime timestamp;
  final Completer<bool> completer;

  AudioRequest({
    required this.id,
    required this.text,
    required this.priority,
    this.haptic = true,
    DateTime? timestamp,
  })  : timestamp = timestamp ?? DateTime.now(),
        completer = Completer<bool>();
}

/// Represents a suspended dialogue conversation context for auto-resumption.
class SuspendedDialogueContext {
  final String query;
  final String remainingResponse;
  final DateTime suspendedAt;

  SuspendedDialogueContext({
    required this.query,
    required this.remainingResponse,
    required this.suspendedAt,
  });

  bool get isExpired =>
      DateTime.now().difference(suspendedAt).inSeconds > 45;
}

/// AudioMutexController: Flutter Dart state machine for zero-overlap audio governance.
/// 
/// Interacts directly with native Android TextToSpeech via MethodChannel:
/// `com.orbisnav.orbisnav/audio_mutex`
class AudioMutexController {
  static const MethodChannel _channel =
      MethodChannel('com.orbisnav.orbisnav/audio_mutex');

  static final AudioMutexController _instance = AudioMutexController._internal();
  factory AudioMutexController() => _instance;

  AudioMutexController._internal() {
    _channel.setMethodCallHandler(_handleNativeMethodCall);
  }

  // Active utterance state
  AudioRequest? _currentActiveRequest;
  AudioPriority? get currentActivePriority => _currentActiveRequest?.priority;
  bool get isSpeaking => _currentActiveRequest != null;

  // Queued requests for non-preemptive tiers
  final List<AudioRequest> _queue = [];

  // Suspended Level 3 conversation context stack (preserved for max 45s)
  SuspendedDialogueContext? _suspendedContext;
  Timer? _hazardClearanceTimer;
  DateTime? _lastHazardClearedTime;
  DateTime? get lastHazardClearedTime => _lastHazardClearedTime;

  // Stream controller to notify UI of speech state changes
  final StreamController<AudioRequest?> _activeSpeechController =
      StreamController<AudioRequest?>.broadcast();
  Stream<AudioRequest?> get activeSpeechStream => _activeSpeechController.stream;

  final StreamController<String> _statusController =
      StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  Future<dynamic> _handleNativeMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onSpeechCompleted':
        final String? utteranceId = call.arguments['utteranceId'] as String?;
        _onSpeechFinished(utteranceId);
        break;
      default:
        break;
    }
  }

  void _onSpeechFinished(String? utteranceId) {
    if (_currentActiveRequest != null &&
        (_currentActiveRequest!.id == utteranceId || utteranceId == null)) {
      if (!_currentActiveRequest!.completer.isCompleted) {
        _currentActiveRequest!.completer.complete(true);
      }
      _currentActiveRequest = null;
      _activeSpeechController.add(null);
    }
    _processNextInQueue();
  }

  // Speak-Once phrase deduplication
  String? _lastSpokenNormalizedKey;
  DateTime? _lastSpokenTimestamp;

  String _normalizeForDeduplication(String s) {
    // Strip distance numbers (e.g., "1.2 meters") to prevent slight distance updates from re-triggering
    return s.replaceAll(RegExp(r'\d+(\.\d+)?\s*(meters|m|s|seconds)?', caseSensitive: false), '').trim().toLowerCase();
  }

  /// Request speech output adhering to the Audio Priority Matrix.
  /// 
  /// Enforces "Tell Only Once" - drops identical/near-identical phrases within 15 seconds unless force=true.
  Future<bool> speak({
    required String text,
    required AudioPriority priority,
    bool haptic = true,
    bool force = false,
  }) async {
    final now = DateTime.now();
    final normalized = _normalizeForDeduplication(text);
    if (!force &&
        _lastSpokenNormalizedKey == normalized &&
        _lastSpokenTimestamp != null &&
        now.difference(_lastSpokenTimestamp!).inSeconds < 15) {
      // Tell only once: duplicate suppressed
      return true;
    }
    _lastSpokenNormalizedKey = normalized;
    _lastSpokenTimestamp = now;

    final request = AudioRequest(
      id: 'req_${now.millisecondsSinceEpoch}_${priority.value}',
      text: text,
      priority: priority,
      haptic: haptic,
    );

    // Rule: Level 0 or Level 1 Hazard detected
    if (priority == AudioPriority.level0Critical ||
        priority == AudioPriority.level1Safety) {
      return _handleCriticalSafetyPreemption(request);
    }

    // Rule: Level 2 Navigation cue
    if (priority == AudioPriority.level2Navigation) {
      return _handleNavigationCue(request);
    }

    // Rule: Level 3 Context / AI
    return _handleContextSpeech(request);
  }

  /// Handles Level 0 & Level 1 hard preemption
  Future<bool> _handleCriticalSafetyPreemption(AudioRequest request) async {
    _statusController.add("PREEMPTION: Level ${request.priority.value} Hazard!");

    // If active speech is Level 3, suspend and save to context stack
    if (_currentActiveRequest != null &&
        _currentActiveRequest!.priority == AudioPriority.level3Context) {
      _suspendedContext = SuspendedDialogueContext(
        query: "Context Query",
        remainingResponse: _currentActiveRequest!.text,
        suspendedAt: DateTime.now(),
      );
      _statusController.add("Level 3 Context suspended (45s TTL)");
    }

    // Drop any lower priority requests from the internal queue
    _queue.removeWhere((item) => item.priority.value > request.priority.value);

    // Hard flush native TTS queue
    _currentActiveRequest = request;
    _activeSpeechController.add(request);

    try {
      final bool success = await _channel.invokeMethod<bool>('speak', {
        'text': request.text,
        'priority': request.priority.value,
        'haptic': request.haptic,
        'utteranceId': request.id,
      }) ?? false;

      return success;
    } catch (e) {
      _onSpeechFinished(request.id);
      return false;
    }
  }

  /// Handles Level 2 Navigation cues
  Future<bool> _handleNavigationCue(AudioRequest request) async {
    // If currently speaking Level 0 or 1, do NOT preempt; queue navigation cue
    if (_currentActiveRequest != null &&
        _currentActiveRequest!.priority.value < AudioPriority.level2Navigation.value) {
      _queue.add(request);
      return request.completer.future;
    }

    // If Level 3 is active, preempt Level 3
    if (_currentActiveRequest != null &&
        _currentActiveRequest!.priority == AudioPriority.level3Context) {
      _channel.invokeMethod('stop');
      _suspendedContext = SuspendedDialogueContext(
        query: "Context Query",
        remainingResponse: _currentActiveRequest!.text,
        suspendedAt: DateTime.now(),
      );
    }

    // Drop Level 3 from queue
    _queue.removeWhere((item) => item.priority == AudioPriority.level3Context);

    _currentActiveRequest = request;
    _activeSpeechController.add(request);

    try {
      final bool success = await _channel.invokeMethod<bool>('speak', {
        'text': request.text,
        'priority': request.priority.value,
        'haptic': request.haptic,
        'utteranceId': request.id,
      }) ?? false;
      return success;
    } catch (e) {
      _onSpeechFinished(request.id);
      return false;
    }
  }

  /// Handles Level 3 Context / AI
  Future<bool> _handleContextSpeech(AudioRequest request) async {
    // If any higher priority is active or queued, drop or queue
    if (_currentActiveRequest != null &&
        _currentActiveRequest!.priority.value < AudioPriority.level3Context.value) {
      // Discard Level 3 to protect safety latency
      return false;
    }

    if (_currentActiveRequest != null) {
      _queue.add(request);
      return request.completer.future;
    }

    _currentActiveRequest = request;
    _activeSpeechController.add(request);

    try {
      final bool success = await _channel.invokeMethod<bool>('speak', {
        'text': request.text,
        'priority': request.priority.value,
        'haptic': request.haptic,
        'utteranceId': request.id,
      }) ?? false;
      return success;
    } catch (e) {
      _onSpeechFinished(request.id);
      return false;
    }
  }

  /// Notifies the mutex that a hazard has cleared.
  /// Starts a 1.5s countdown before attempting to resume suspended Level 3 conversation.
  void notifyHazardCleared() {
    _lastSpokenNormalizedKey = null;
    _lastHazardClearedTime = DateTime.now();
    _hazardClearanceTimer?.cancel();
    _hazardClearanceTimer = Timer(const Duration(milliseconds: 1500), () {
      _attemptContextResumption();
    });
  }

  /// Attempts to resume suspended dialogue if within 45s TTL and channel is clear
  void _attemptContextResumption() {
    if (_suspendedContext == null) return;

    if (_suspendedContext!.isExpired) {
      _statusController.add("Suspended dialogue context expired (>45s). Discarded.");
      _suspendedContext = null;
      return;
    }

    if (_currentActiveRequest != null) {
      // Channel busy, retry in 1s
      _hazardClearanceTimer = Timer(const Duration(seconds: 1), _attemptContextResumption);
      return;
    }

    final contextToResume = _suspendedContext!;
    _suspendedContext = null;

    final resumeText = "Continuing: ${contextToResume.remainingResponse}";
    _statusController.add("Resuming suspended context...");
    speak(
      text: resumeText,
      priority: AudioPriority.level3Context,
      haptic: false,
    );
  }

  void _processNextInQueue() {
    if (_queue.isEmpty || _currentActiveRequest != null) return;

    // Sort queue by priority ascending (0 is highest)
    _queue.sort((a, b) => a.priority.value.compareTo(b.priority.value));
    final next = _queue.removeAt(0);

    // Skip expired requests (> 10s old)
    if (DateTime.now().difference(next.timestamp).inSeconds > 10) {
      if (!next.completer.isCompleted) next.completer.complete(false);
      _processNextInQueue();
      return;
    }

    _currentActiveRequest = next;
    _activeSpeechController.add(next);

    _channel.invokeMethod<bool>('speak', {
      'text': next.text,
      'priority': next.priority.value,
      'haptic': next.haptic,
      'utteranceId': next.id,
    }).then((success) {
      if (!(success ?? false)) {
        _onSpeechFinished(next.id);
      }
    }).catchError((_) {
      _onSpeechFinished(next.id);
    });
  }

  /// Instant hard kill of all speech and clears all queues
  Future<void> hardStop() async {
    _queue.clear();
    _suspendedContext = null;
    _hazardClearanceTimer?.cancel();
    _currentActiveRequest = null;
    _activeSpeechController.add(null);
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }

  /// Triggers a discrete haptic feedback cue directly
  Future<void> triggerHaptic(String type) async {
    try {
      await _channel.invokeMethod('triggerHaptic', {'type': type});
    } catch (_) {}
  }

  void dispose() {
    hardStop();
    _activeSpeechController.close();
    _statusController.close();
  }
}

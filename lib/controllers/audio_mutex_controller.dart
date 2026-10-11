import 'dart:async';
import 'package:flutter/foundation.dart';
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
  final int? channelIndex;
  final bool haptic;
  final DateTime timestamp;
  final Completer<bool> completer;

  AudioRequest({
    required this.id,
    required this.text,
    required this.priority,
    this.channelIndex,
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

  // Active Channel / Tab tracking (0: Safety HUD, 1: Nav, 2: Doc Scan / Lens, 3: Lost Item Sonar)
  int _activeChannelIndex = 0;
  int get activeChannelIndex => _activeChannelIndex;

  /// Sets the currently active UI channel/tab.
  /// Dynamically elevates the current channel's priority over background channels,
  /// flushes background queues, and preempts any lingering background speech.
  void setActiveChannel(int index) {
    if (_activeChannelIndex == index) return;
    _activeChannelIndex = index;
    _statusController.add("Active Channel set to $index. Background channels demoted.");

    // If an inactive channel is currently speaking a non-critical utterance, stop it immediately
    if (_currentActiveRequest != null &&
        _currentActiveRequest!.channelIndex != null &&
        _currentActiveRequest!.channelIndex != index &&
        _currentActiveRequest!.priority != AudioPriority.level0Critical) {
      _channel.invokeMethod('stop').catchError((_) => null);
      if (!_currentActiveRequest!.completer.isCompleted) {
        _currentActiveRequest!.completer.complete(false);
      }
      _currentActiveRequest = null;
      _activeSpeechController.add(null);
    }

    // Purge any non-critical queued speech from other channels
    clearQueueForOtherChannels(index);
    _processNextInQueue();
  }

  /// Removes all queued non-critical requests belonging to any channel except [keepChannelIndex].
  void clearQueueForOtherChannels(int keepChannelIndex) {
    _queue.removeWhere((item) =>
        item.channelIndex != null &&
        item.channelIndex != keepChannelIndex &&
        item.priority != AudioPriority.level0Critical);
  }

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

  /// Request speech output adhering to the Audio Priority Matrix and Channel Precedence.
  /// 
  /// The active tab/channel has primary priority over background/other channels.
  /// Non-critical speech from other channels is demoted and cannot interrupt the current tab.
  Future<bool> speak({
    required String text,
    required AudioPriority priority,
    int? channelIndex,
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
      channelIndex: channelIndex,
      haptic: haptic,
    );

    final bool isFromActiveChannel =
        (channelIndex == null || channelIndex == _activeChannelIndex);

    // RULE 1: If speech request comes from a BACKGROUND / OTHER CHANNEL
    if (!isFromActiveChannel) {
      // When a channel is selected, other channels must stop completely!
      // Only Level 0 Critical emergency hazards (life safety) can alert the user
      if (priority == AudioPriority.level0Critical) {
        return _handleCriticalSafetyPreemption(request);
      }

      // All other channels are stopped and silent: do not queue or speak
      return false;
    }

    // RULE 2: Speech request comes from the CURRENT ACTIVE CHANNEL
    // If a background channel is currently speaking a non-critical utterance,
    // the active tab IMMEDIATELY PREEMPTS the background utterance!
    if (_currentActiveRequest != null &&
        _currentActiveRequest!.channelIndex != null &&
        _currentActiveRequest!.channelIndex != _activeChannelIndex &&
        _currentActiveRequest!.priority != AudioPriority.level0Critical) {
      _channel.invokeMethod('stop').catchError((_) => null);
      if (!_currentActiveRequest!.completer.isCompleted) {
        _currentActiveRequest!.completer.complete(false);
      }
      _currentActiveRequest = null;
    }

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

  Future<bool> _executeSpeech(AudioRequest request) async {
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

    return _executeSpeech(request);
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

    return _executeSpeech(request);
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

    return _executeSpeech(request);
  }

  /// Hard stops native TTS and clears speech queue completely
  Future<void> stopAll() async {
    _hazardClearanceTimer?.cancel();
    _suspendedContext = null;
    _queue.clear();
    if (_currentActiveRequest != null && !_currentActiveRequest!.completer.isCompleted) {
      _currentActiveRequest!.completer.complete(false);
    }
    _currentActiveRequest = null;
    _activeSpeechController.add(null);
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
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
      channelIndex: _activeChannelIndex,
      haptic: false,
    );
  }

  /// Comparator ensuring the active channel always has precedence over background channels
  int _compareRequests(AudioRequest a, AudioRequest b) {
    // 1. Level 0 Critical always has absolute top priority
    if (a.priority == AudioPriority.level0Critical &&
        b.priority != AudioPriority.level0Critical) return -1;
    if (b.priority == AudioPriority.level0Critical &&
        a.priority != AudioPriority.level0Critical) return 1;

    final bool aIsActive =
        a.channelIndex == null || a.channelIndex == _activeChannelIndex;
    final bool bIsActive =
        b.channelIndex == null || b.channelIndex == _activeChannelIndex;

    // 2. Current active tab always has precedence over background tabs!
    if (aIsActive && !bIsActive) return -1;
    if (!aIsActive && bIsActive) return 1;

    // 3. For requests within the same channel tier, sort by priority value (0 is highest)
    final int pComp = a.priority.value.compareTo(b.priority.value);
    if (pComp != 0) return pComp;

    // 4. Same priority: FIFO by timestamp
    return a.timestamp.compareTo(b.timestamp);
  }

  void _processNextInQueue() {
    if (_queue.isEmpty || _currentActiveRequest != null) return;

    // Sort queue with active channel precedence
    _queue.sort(_compareRequests);
    final next = _queue.removeAt(0);

    // Skip expired requests (> 10s old)
    if (DateTime.now().difference(next.timestamp).inSeconds > 10) {
      if (!next.completer.isCompleted) next.completer.complete(false);
      _processNextInQueue();
      return;
    }

    _executeSpeech(next).then((success) {
      if (!success) {
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

  /// Triggers native speech recognition for blind accessibility.
  /// Returns the recognized spoken string (or empty string if cancelled).
  Future<String> startVoiceInput() async {
    try {
      final String? result = await _channel.invokeMethod<String>('startVoiceInput');
      return result?.trim() ?? "";
    } catch (e) {
      debugPrint("[AudioMutexController] startVoiceInput error: $e");
      return "";
    }
  }

  void dispose() {
    hardStop();
  }
}

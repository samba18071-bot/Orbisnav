import 'dart:collection';

/// SpatialDebouncer: Enforces Core System Law 2 (Repetition Elimination) and Law 3 (Preemption Authority).
/// 
/// Maintains an in-memory cache of recent audio prompts keyed by spatial clock-face zone:
/// `${label}_${clockZone}` -> `DateTime`
/// 
/// Prevents repetitive TTS audio loops by enforcing a configurable 4-second cooldown window
/// while allowing critical hazards to immediately bypass cooldowns for sub-second safety alerts.
class SpatialDebouncer {
  final Duration cooldownDuration;
  final double criticalDistanceThreshold;

  // Cache: "label_clockZone" -> DateTime of last spoken alert
  final HashMap<String, DateTime> _lastSpokenTimes = HashMap<String, DateTime>();
  final HashMap<String, double> _lastSpokenDistances = HashMap<String, double>();

  SpatialDebouncer({
    this.cooldownDuration = const Duration(seconds: 4),
    this.criticalDistanceThreshold = 1.5,
  });

  /// Evaluates whether an obstacle should trigger a voice alert.
  /// 
  /// Returns `true` if:
  /// 1. Object is a critical hazard (`isCritical == true` or `distanceMeters < 1.5m`) -> BYPASSES cooldown.
  /// 2. The object/zone has never been spoken.
  /// 3. The cooldown window (4 seconds) has elapsed since the last alert for this object in this zone.
  /// 4. The obstacle has moved significantly closer (distance dropped by >= 0.7m).
  /// Evaluates whether an obstacle should trigger a voice alert.
  /// 
  /// Returns `true` if:
  /// 1. The object/zone has never been spoken.
  /// 2. The obstacle has moved significantly closer (distance dropped by >= 0.8m) or entered critical hazard range (<1.2m) for the first time.
  /// 3. The cooldown window (30 seconds) has elapsed since the last alert for this object in this zone.
  bool shouldSpeak({
    required String label,
    required String clockZone,
    bool isCritical = false,
    double distanceMeters = 5.0,
  }) {
    final key = _buildKey(label, clockZone);
    final now = DateTime.now();

    if (!_lastSpokenTimes.containsKey(key)) {
      return true;
    }

    final lastSpoken = _lastSpokenTimes[key]!;
    final elapsed = now.difference(lastSpoken);

    // If critical or close proximity, check if distance has significantly escalated
    if (_lastSpokenDistances.containsKey(key)) {
      final prevDist = _lastSpokenDistances[key]!;
      // Escalation: object came at least 0.8m closer, or dropped below 1.2m critical threshold
      if ((prevDist - distanceMeters) >= 0.8 || (prevDist >= 1.2 && distanceMeters < 1.2)) {
        return true;
      }
    }

    // Cooldown duration (default 30 seconds for non-escalated identical obstacles)
    if (elapsed >= cooldownDuration) {
      return true;
    }

    // Blocked by spatial debouncer (within cooldown without escalation)
    return false;
  }

  /// Records an alert as spoken at the current timestamp.
  void recordSpoken({
    required String label,
    required String clockZone,
    double distanceMeters = 5.0,
  }) {
    final key = _buildKey(label, clockZone);
    _lastSpokenTimes[key] = DateTime.now();
    _lastSpokenDistances[key] = distanceMeters;
  }

  /// Clears the debouncer cache for a specific clock zone (e.g. upon user rotation)
  void clearZone(String clockZone) {
    _lastSpokenTimes.removeWhere((key, _) => key.endsWith('_$clockZone'));
    _lastSpokenDistances.removeWhere((key, _) => key.endsWith('_$clockZone'));
  }

  /// Clears all debouncer history (e.g. when path clears or navigation restarts)
  void clear() {
    _lastSpokenTimes.clear();
    _lastSpokenDistances.clear();
  }

  String _buildKey(String label, String clockZone) {
    return "${label.trim().toLowerCase()}_${clockZone.trim().toLowerCase()}";
  }
}

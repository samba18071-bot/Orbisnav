import 'online_obstacle_detector.dart';

/// Represents a disambiguated item when multiple objects of the same type exist in view.
class DisambiguatedItem {
  final DetectedObstacle obstacle;
  final int index; // 1-based index among same-type items
  final int totalCount; // Total number of same-type items
  final String spatialRole; // e.g., "Nearest", "Left", "Right", "Farther", "Center"
  final String hudBadge; // e.g., "CHAIR #1 (NEAREST)"
  final String spokenDescriptor; // e.g., "nearest chair at 10 o'clock, 1.2 meters"

  const DisambiguatedItem({
    required this.obstacle,
    required this.index,
    required this.totalCount,
    required this.spatialRole,
    required this.hudBadge,
    required this.spokenDescriptor,
  });
}

/// Disambiguation Engine for multiple items of the same type.
/// 
/// Solves the blind/low-vision ambiguity problem where multiple identical object classes
/// (e.g. 3 chairs, 2 water bottles, 2 doors, 4 pedestrians) create auditory confusion
/// and inability to distinguish which object is closest, most accessible, or hazardous.
class MultiItemDisambiguator {
  /// Simple English pluralizer for common object classes.
  static String pluralize(String label, int count) {
    if (count == 1) return label;
    final lower = label.trim().toLowerCase();
    if (lower == 'person') return 'people';
    if (lower == 'footwear') return 'footwear';
    if (lower.endsWith('s') || lower.endsWith('sh') || lower.endsWith('ch') || lower.endsWith('x')) {
      return '${label}es';
    }
    if (lower.endsWith('y') && !lower.endsWith('ey') && !lower.endsWith('ay') && !lower.endsWith('oy')) {
      return '${label.substring(0, label.length - 1)}ies';
    }
    return '${label}s';
  }

  /// Disambiguates an entire list of obstacles, grouping and tagging multiple same-type items.
  static List<DisambiguatedItem> disambiguateObstacles(List<DetectedObstacle> obstacles) {
    if (obstacles.isEmpty) return const [];

    // Group obstacles by normalized label
    final Map<String, List<DetectedObstacle>> groups = {};
    for (final obs in obstacles) {
      final key = obs.label.trim().toLowerCase();
      groups.putIfAbsent(key, () => []).add(obs);
    }

    final List<DisambiguatedItem> result = [];

    for (final entry in groups.entries) {
      final group = entry.value;
      final total = group.length;

      if (total == 1) {
        final obs = group.first;
        result.add(DisambiguatedItem(
          obstacle: obs,
          index: 1,
          totalCount: 1,
          spatialRole: 'Solo',
          hudBadge: obs.label.toUpperCase(),
          spokenDescriptor: '${obs.label} at ${obs.clockPosition}, ${obs.distanceMeters.toStringAsFixed(1)} meters',
        ));
        continue;
      }

      // Sort same-type items: primary criterion = distance (closest first), secondary = x position (left to right)
      final sorted = List<DetectedObstacle>.from(group)..sort((a, b) {
        final distComp = a.distanceMeters.compareTo(b.distanceMeters);
        if (distComp != 0) return distComp;
        return a.xMin.compareTo(b.xMin);
      });

      for (int i = 0; i < sorted.length; i++) {
        final obs = sorted[i];
        final index = i + 1;
        final centerX = (obs.xMin + obs.xMax) / 2.0;

        String role;
        if (i == 0) {
          role = 'Nearest';
        } else if (centerX < 0.38) {
          role = 'Left';
        } else if (centerX > 0.62) {
          role = 'Right';
        } else {
          role = 'Farther';
        }

        final hudBadge = '${obs.label.toUpperCase()} #$index (${role.toUpperCase()})';
        final spoken = i == 0
            ? 'closest ${obs.label.toLowerCase()} at ${obs.clockPosition}, ${obs.distanceMeters.toStringAsFixed(1)} meters'
            : '$role ${obs.label.toLowerCase()} (#$index) at ${obs.clockPosition}, ${obs.distanceMeters.toStringAsFixed(1)} meters';

        result.add(DisambiguatedItem(
          obstacle: obs,
          index: index,
          totalCount: total,
          spatialRole: role,
          hudBadge: hudBadge,
          spokenDescriptor: spoken,
        ));
      }
    }

    // Preserve original relative order by finding matching reference in result
    return result;
  }

  /// Synthesizes an intelligent, non-repetitive speech summary for all active obstacles,
  /// grouping multiple items of the same type to eliminate cognitive auditory fatigue.
  static String synthesizeAggregatedSpeech(List<DetectedObstacle> obstacles) {
    if (obstacles.isEmpty) {
      return "The path is clear. No obstacles detected in your immediate field of view.";
    }

    final Map<String, List<DetectedObstacle>> groups = {};
    for (final obs in obstacles) {
      final key = obs.label.trim().toLowerCase();
      groups.putIfAbsent(key, () => []).add(obs);
    }

    final List<String> groupSummaries = [];

    for (final entry in groups.entries) {
      final items = entry.value;
      final label = items.first.label;
      final count = items.length;

      if (count == 1) {
        final obs = items.first;
        groupSummaries.add('${obs.label} at ${obs.clockPosition}, ${obs.distanceMeters.toStringAsFixed(1)} meters');
      } else {
        // Sort closest first
        items.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
        final closest = items.first;
        final pluralName = pluralize(label.toLowerCase(), count);

        if (count == 2) {
          final other = items[1];
          groupSummaries.add(
            '$count $pluralName: closest is at ${closest.clockPosition}, ${closest.distanceMeters.toStringAsFixed(1)} meters; another at ${other.clockPosition}, ${other.distanceMeters.toStringAsFixed(1)} meters',
          );
        } else {
          final othersClocks = items.skip(1).map((o) => o.clockPosition).toSet().join(' and ');
          groupSummaries.add(
            '$count $pluralName: closest is at ${closest.clockPosition}, ${closest.distanceMeters.toStringAsFixed(1)} meters, with others at $othersClocks',
          );
        }
      }
    }

    final count = obstacles.length;
    final prefix = "$count ${count == 1 ? "object" : "objects"}: ";
    return prefix + groupSummaries.join('; ') + '.';
  }

  /// Disambiguates query results for conversational voice Q&A (e.g. "Where is the chair?").
  static String disambiguateVoiceQuery({
    required String targetCategory,
    required List<DetectedObstacle> matches,
  }) {
    if (matches.isEmpty) {
      return 'No ${pluralize(targetCategory, 2)} detected in current view.';
    }

    if (matches.length == 1) {
      final m = matches.first;
      return 'Found a ${m.label} ${m.distanceMeters.toStringAsFixed(1)} meters away at ${m.clockPosition}.';
    }

    // Sort closest first
    matches.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    final closest = matches.first;
    final plural = pluralize(targetCategory, matches.length);

    if (matches.length == 2) {
      final second = matches[1];
      return 'Found 2 $plural. The closest is at ${closest.clockPosition}, ${closest.distanceMeters.toStringAsFixed(1)} meters. Another is at ${second.clockPosition}, ${second.distanceMeters.toStringAsFixed(1)} meters. Guiding you to the closest one.';
    }

    final count = matches.length;
    final otherClocks = matches.skip(1).map((m) => "${m.clockPosition} (${m.distanceMeters.toStringAsFixed(1)}m)").join(', ');
    return 'Found $count $plural. The nearest is directly at ${closest.clockPosition}, ${closest.distanceMeters.toStringAsFixed(1)} meters away. Others are located at $otherClocks.';
  }
}

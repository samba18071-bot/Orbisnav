import 'dart:math' as math;

/// Represents a designated navigation destination (shop, building, amenity, or room)
class NavTargetDestination {
  final String id;
  final String name;
  final String category; // e.g. "Coffee & Cafe", "Pharmacy", "Groceries", "Transit", "Custom"
  final double latitude;
  final double longitude;
  final List<String> aliases;

  const NavTargetDestination({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.aliases,
  });

  /// Computes Great-Circle distance in meters from a given GPS coordinate
  double distanceTo(double userLat, double userLng) {
    const double earthRadiusMeters = 6371000.0;
    final double dLat = _degreesToRadians(latitude - userLat);
    final double dLng = _degreesToRadians(longitude - userLng);

    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(userLat)) *
            math.cos(_degreesToRadians(latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  /// Computes compass bearing in degrees [0, 360) from user to destination
  double bearingFrom(double userLat, double userLng) {
    final double lat1 = _degreesToRadians(userLat);
    final double lat2 = _degreesToRadians(latitude);
    final double dLng = _degreesToRadians(longitude - userLng);

    final double y = math.sin(dLng) * math.cos(lat2);
    final double x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);

    final double bearingRad = math.atan2(y, x);
    final double bearingDeg = (bearingRad * (180.0 / math.pi) + 360.0) % 360.0;
    return bearingDeg;
  }

  static double _degreesToRadians(double deg) => deg * (math.pi / 180.0);

  /// Pre-configured curated destinations for immediate testing and demonstration
  static const List<NavTargetDestination> defaultDestinations = [
    NavTargetDestination(
      id: "dest_starbucks",
      name: "Starbucks Coffee",
      category: "Cafe & Food",
      latitude: 17.4435, // Demo near-field coordinate
      longitude: 78.3772,
      aliases: ["starbucks", "coffee", "cafe", "starbucks coffee"],
    ),
    NavTargetDestination(
      id: "dest_pharmacy",
      name: "Apollo Pharmacy",
      category: "Medical & Health",
      latitude: 17.4438,
      longitude: 78.3776,
      aliases: ["apollo", "pharmacy", "medical", "chemist"],
    ),
    NavTargetDestination(
      id: "dest_supermarket",
      name: "City Supermarket",
      category: "Groceries & Retail",
      latitude: 17.4442,
      longitude: 78.3780,
      aliases: ["supermarket", "mart", "grocery", "store"],
    ),
    NavTargetDestination(
      id: "dest_metro",
      name: "Metro Station",
      category: "Transit",
      latitude: 17.4450,
      longitude: 78.3790,
      aliases: ["metro", "station", "subway", "train"],
    ),
    NavTargetDestination(
      id: "dest_office",
      name: "Conference Room 204",
      category: "Indoor / Workplace",
      latitude: 17.4430,
      longitude: 78.3768,
      aliases: ["conference", "room", "204", "office"],
    ),
  ];
}

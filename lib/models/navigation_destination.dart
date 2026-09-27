import 'dart:math' as math;

/// Represents a designated navigation destination (shop, building, amenity, hospital, transit, or room)
class NavTargetDestination {
  final String id;
  final String name;
  final String category; // e.g. "Medical & Health", "Food & Dining", "Groceries & Shopping", "Transit & Stations", "Banks & ATMs", "Landmarks & Parks"
  final double latitude;
  final double longitude;
  final List<String> aliases;
  final String? address;
  final double? distanceMeters;
  final double? bearingDeg;
  final String? clockZone;

  const NavTargetDestination({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    this.aliases = const [],
    this.address,
    this.distanceMeters,
    this.bearingDeg,
    this.clockZone,
  });

  /// Creates a copy with updated live distance and bearing from the user's current GPS position
  NavTargetDestination withLiveTelemetry(double userLat, double userLng) {
    final dist = distanceTo(userLat, userLng);
    final bearing = bearingFrom(userLat, userLng);
    final clock = calculateClockVector(bearing);
    return NavTargetDestination(
      id: id,
      name: name,
      category: category,
      latitude: latitude,
      longitude: longitude,
      aliases: aliases,
      address: address,
      distanceMeters: dist,
      bearingDeg: bearing,
      clockZone: clock,
    );
  }

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

  /// Calculates 12-hour clock face vector for blind assistive audio cues
  static String calculateClockVector(double bearingDeg) {
    final normalized = (bearingDeg % 360.0);
    int clock = ((normalized + 15.0) / 30.0).floor() % 12;
    if (clock == 0) clock = 12;
    return "$clock o'clock";
  }

  /// Formats distance into human-friendly speech / UI string (e.g., "350 m", "1.8 km")
  String get formattedDistance {
    if (distanceMeters == null) return "--";
    if (distanceMeters! >= 1000) {
      return "${(distanceMeters! / 1000.0).toStringAsFixed(1)} km";
    }
    return "${distanceMeters!.round()} m";
  }

  static double _degreesToRadians(double deg) => deg * (math.pi / 180.0);

  /// Factory to parse OpenStreetMap Overpass API element
  static NavTargetDestination? fromOsmElement(Map<String, dynamic> element, double userLat, double userLng) {
    final id = element['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
    final tags = element['tags'] as Map<String, dynamic>? ?? {};
    
    // Get POI name
    String name = tags['name'] ?? tags['name:en'] ?? tags['brand'] ?? tags['operator'] ?? '';
    if (name.trim().isEmpty) {
      final amenity = tags['amenity'] ?? tags['shop'] ?? tags['tourism'] ?? tags['highway'] ?? 'Location';
      name = _capitalize(amenity.toString().replaceAll('_', ' '));
    }

    final double? lat = (element['lat'] as num?)?.toDouble() ?? 
                       (element['center']?['lat'] as num?)?.toDouble();
    final double? lon = (element['lon'] as num?)?.toDouble() ?? 
                       (element['center']?['lon'] as num?)?.toDouble();

    if (lat == null || lon == null) return null;

    // Categorize
    String category = "Landmarks & Parks";
    final amenity = tags['amenity']?.toString();
    final shop = tags['shop']?.toString();
    final highway = tags['highway']?.toString();
    final railway = tags['railway']?.toString();
    final tourism = tags['tourism']?.toString();

    if (amenity == 'hospital' || amenity == 'pharmacy' || amenity == 'clinic' || amenity == 'doctors' || shop == 'chemist') {
      category = "Medical & Health";
    } else if (amenity == 'restaurant' || amenity == 'cafe' || amenity == 'fast_food' || shop == 'bakery' || amenity == 'bar') {
      category = "Food & Dining";
    } else if (shop != null || amenity == 'marketplace') {
      category = "Groceries & Shopping";
    } else if (highway == 'bus_stop' || amenity == 'bus_station' || railway != null || amenity == 'ferry_terminal') {
      category = "Transit & Stations";
    } else if (amenity == 'bank' || amenity == 'atm') {
      category = "Banks & ATMs";
    } else if (tourism != null || amenity == 'place_of_worship' || tags['leisure'] == 'park') {
      category = "Landmarks & Parks";
    }

    // Street / Address
    final street = tags['addr:street'] ?? tags['addr:full'] ?? tags['addr:suburb'];
    final city = tags['addr:city'];
    String? address;
    if (street != null && city != null) {
      address = "$street, $city";
    } else if (street != null) {
      address = street.toString();
    }

    final dest = NavTargetDestination(
      id: "osm_$id",
      name: name,
      category: category,
      latitude: lat,
      longitude: lon,
      aliases: [name.toLowerCase(), category.toLowerCase()],
      address: address,
    );

    return dest.withLiveTelemetry(userLat, userLng);
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s.split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');
  }

  /// Pre-configured curated destinations for immediate standalone testing & offline fallback
  static const List<NavTargetDestination> defaultDestinations = [
    NavTargetDestination(
      id: "dest_hospital",
      name: "City Care Hospital & Trauma Center",
      category: "Medical & Health",
      latitude: 17.4460,
      longitude: 78.3790,
      aliases: ["hospital", "emergency", "medical", "clinic", "trauma"],
      address: "Main Road, Sector 3",
    ),
    NavTargetDestination(
      id: "dest_pharmacy",
      name: "Apollo 24/7 Pharmacy",
      category: "Medical & Health",
      latitude: 17.4438,
      longitude: 78.3776,
      aliases: ["apollo", "pharmacy", "medical", "chemist", "medicine"],
      address: "Shop 12, Ground Floor",
    ),
    NavTargetDestination(
      id: "dest_supermarket",
      name: "Reliance Fresh Supermarket",
      category: "Groceries & Shopping",
      latitude: 17.4442,
      longitude: 78.3780,
      aliases: ["supermarket", "reliance", "mart", "grocery", "store"],
      address: "Crossroads Avenue",
    ),
    NavTargetDestination(
      id: "dest_starbucks",
      name: "Starbucks Coffee",
      category: "Food & Dining",
      latitude: 17.4435,
      longitude: 78.3772,
      aliases: ["starbucks", "coffee", "cafe", "starbucks coffee", "drinks"],
      address: "Tower 1 Plaza",
    ),
    NavTargetDestination(
      id: "dest_metro",
      name: "Hitec City Metro Station",
      category: "Transit & Stations",
      latitude: 17.4485,
      longitude: 78.3810,
      aliases: ["metro", "station", "subway", "train", "transit"],
      address: "Blue Line Concourse",
    ),
    NavTargetDestination(
      id: "dest_bank",
      name: "State Bank & ATM Center",
      category: "Banks & ATMs",
      latitude: 17.4428,
      longitude: 78.3765,
      aliases: ["bank", "atm", "sbi", "cash", "money"],
      address: "Block A Banking Complex",
    ),
    NavTargetDestination(
      id: "dest_park",
      name: "Central Community Park",
      category: "Landmarks & Parks",
      latitude: 17.4410,
      longitude: 78.3750,
      aliases: ["park", "garden", "walkway", "central park"],
      address: "Park Street Entrance",
    ),
  ];
}

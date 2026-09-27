import 'dart:math' as math;

/// Represents a designated navigation destination (university block, shop, building, amenity, hospital, transit, or room)
class NavTargetDestination {
  final String id;
  final String name;
  final String category; // e.g. "University & Campus", "Medical & Health", "Food & Dining", "Groceries & Shopping", "Transit & Stations", "Banks & ATMs", "Landmarks & Parks", "Saved My Places"
  final double latitude;
  final double longitude;
  final List<String> aliases;
  final String? address;
  final String? blockName; // e.g. "Block B", "CSE Wing", "Floor 2"
  final double? distanceMeters;
  final double? bearingDeg;
  final String? clockZone;
  final bool isCustomSaved;

  const NavTargetDestination({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    this.aliases = const [],
    this.address,
    this.blockName,
    this.distanceMeters,
    this.bearingDeg,
    this.clockZone,
    this.isCustomSaved = false,
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
      blockName: blockName,
      distanceMeters: dist,
      bearingDeg: bearing,
      clockZone: clock,
      isCustomSaved: isCustomSaved,
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

  /// Formats distance into human-friendly speech / UI string (e.g., "35 m", "350 m", "1.8 km")
  String get formattedDistance {
    if (distanceMeters == null) return "--";
    if (distanceMeters! >= 1000) {
      return "${(distanceMeters! / 1000.0).toStringAsFixed(1)} km";
    }
    return "${distanceMeters!.round()} m";
  }

  /// Returns whether this destination belongs to a university or campus building block
  bool get isCampusBuilding => category == "University & Campus" || blockName != null;

  static double _degreesToRadians(double deg) => deg * (math.pi / 180.0);

  /// Factory to parse OpenStreetMap Overpass API element with University & Block awareness
  static NavTargetDestination? fromOsmElement(Map<String, dynamic> element, double userLat, double userLng) {
    final id = element['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
    final tags = element['tags'] as Map<String, dynamic>? ?? {};
    
    // Get POI name
    String name = tags['name'] ?? tags['name:en'] ?? tags['brand'] ?? tags['operator'] ?? '';
    if (name.trim().isEmpty) {
      final amenity = tags['amenity'] ?? tags['building'] ?? tags['shop'] ?? tags['tourism'] ?? tags['highway'] ?? 'Location';
      name = _capitalize(amenity.toString().replaceAll('_', ' '));
    }

    final double? lat = (element['lat'] as num?)?.toDouble() ?? 
                       (element['center']?['lat'] as num?)?.toDouble();
    final double? lon = (element['lon'] as num?)?.toDouble() ?? 
                       (element['center']?['lon'] as num?)?.toDouble();

    if (lat == null || lon == null) return null;

    // Categorize with University & Campus support
    String category = "Landmarks & Parks";
    final amenity = tags['amenity']?.toString();
    final building = tags['building']?.toString();
    final shop = tags['shop']?.toString();
    final highway = tags['highway']?.toString();
    final railway = tags['railway']?.toString();
    final tourism = tags['tourism']?.toString();

    if (amenity == 'university' || amenity == 'college' || amenity == 'school' || amenity == 'library' ||
        building == 'university' || building == 'college' || building == 'academic' || building == 'faculty' ||
        building == 'dormitory' || tags['faculty'] != null || tags['department'] != null) {
      category = "University & Campus";
    } else if (amenity == 'hospital' || amenity == 'pharmacy' || amenity == 'clinic' || amenity == 'doctors' || shop == 'chemist') {
      category = "Medical & Health";
    } else if (amenity == 'restaurant' || amenity == 'cafe' || amenity == 'fast_food' || shop == 'bakery' || amenity == 'canteen') {
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

    // Street / Address / Block
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

  /// Pre-configured curated destinations with University & Block-Level Navigation Support
  static const List<NavTargetDestination> defaultDestinations = [
    // University & Campus Blocks
    NavTargetDestination(
      id: "dest_univ_cse",
      name: "Block B - Computer Science & AI",
      category: "University & Campus",
      blockName: "Block B",
      latitude: 17.4436,
      longitude: 78.3773,
      aliases: ["cse", "computer science", "block b", "cs block", "ai block", "lab 204"],
      address: "Academic Wing 2, Tech Campus",
    ),
    NavTargetDestination(
      id: "dest_univ_library",
      name: "Central University Library",
      category: "University & Campus",
      blockName: "Library Wing",
      latitude: 17.4440,
      longitude: 78.3778,
      aliases: ["library", "central library", "books", "reading room", "study hall"],
      address: "North Quadrangle, Ground & 1st Floor",
    ),
    NavTargetDestination(
      id: "dest_univ_admin",
      name: "Block A - Main Admin & Dean Office",
      category: "University & Campus",
      blockName: "Block A",
      latitude: 17.4432,
      longitude: 78.3768,
      aliases: ["admin", "block a", "dean", "office", "principal", "reception"],
      address: "Main Entrance Plaza",
    ),
    NavTargetDestination(
      id: "dest_univ_canteen",
      name: "Student Cafeteria & Food Court",
      category: "University & Campus",
      blockName: "Dining Block",
      latitude: 17.4445,
      longitude: 78.3782,
      aliases: ["canteen", "cafeteria", "food court", "mess", "lunch"],
      address: "Campus Hub, Ground Floor",
    ),
    NavTargetDestination(
      id: "dest_univ_auditorium",
      name: "University Grand Auditorium",
      category: "University & Campus",
      blockName: "Auditorium",
      latitude: 17.4428,
      longitude: 78.3762,
      aliases: ["auditorium", "hall", "seminar hall", "event", "stage"],
      address: "West Campus Gate",
    ),
    NavTargetDestination(
      id: "dest_univ_mech",
      name: "Block C - Mechanical & Robotics Lab",
      category: "University & Campus",
      blockName: "Block C",
      latitude: 17.4448,
      longitude: 78.3775,
      aliases: ["block c", "mech", "mechanical", "robotics", "workshop"],
      address: "Engineering Complex South",
    ),

    // Public Facilities & City Landmarks
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
  ];
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../controllers/audio_mutex_controller.dart';

/// Represents parsed product information from barcode scan.
class ScannedProductInfo {
  final String barcode;
  final String name;
  final String brand;
  final String category;
  final String ingredients;
  final String allergens;
  final String nutritionGrade;
  final bool isFound;
  final String summarySpeech;

  const ScannedProductInfo({
    required this.barcode,
    required this.name,
    this.brand = '',
    this.category = '',
    this.ingredients = '',
    this.allergens = '',
    this.nutritionGrade = '',
    required this.isFound,
    required this.summarySpeech,
  });

  factory ScannedProductInfo.notFound(String barcode) {
    return ScannedProductInfo(
      barcode: barcode,
      name: 'Unknown Product',
      isFound: false,
      summarySpeech: 'Barcode $barcode detected, but product details were not found.',
    );
  }

  factory ScannedProductInfo.fromOpenFoodFacts(String barcode, Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>?;
    if (product == null) {
      return ScannedProductInfo.notFound(barcode);
    }

    final name = product['product_name'] ?? product['generic_name'] ?? 'Product';
    final brand = product['brands'] ?? '';
    final category = product['categories']?.toString().split(',').first.trim() ?? '';
    final ingredients = product['ingredients_text'] ?? '';
    final allergens = product['allergens_tags'] != null && (product['allergens_tags'] as List).isNotEmpty
        ? (product['allergens_tags'] as List).map((e) => e.toString().replaceAll('en:', '')).join(', ')
        : '';
    final grade = product['nutrition_grades']?.toString().toUpperCase() ?? '';

    final buffer = StringBuffer();
    if (brand.isNotEmpty) {
      buffer.write('$brand ');
    }
    buffer.write('$name.');

    if (allergens.isNotEmpty) {
      buffer.write(' Warning: Contains $allergens.');
    } else if (category.isNotEmpty) {
      buffer.write(' Category: $category.');
    }

    return ScannedProductInfo(
      barcode: barcode,
      name: name.toString(),
      brand: brand.toString(),
      category: category,
      ingredients: ingredients.toString(),
      allergens: allergens,
      nutritionGrade: grade,
      isFound: true,
      summarySpeech: buffer.toString(),
    );
  }
}

/// Service managing offline/online barcode identification and audio output.
class BarcodeProductService {
  final AudioMutexController _audioMutex;
  final http.Client _httpClient;

  final StreamController<ScannedProductInfo> _productStreamController =
      StreamController<ScannedProductInfo>.broadcast();

  Stream<ScannedProductInfo> get productStream => _productStreamController.stream;

  // Debouncing to avoid repeated voice spam for the same barcode within 4 seconds
  String? _lastScannedBarcode;
  DateTime? _lastScanTime;
  bool _isFetching = false;

  // Common offline fallback database for essential items
  static final Map<String, Map<String, String>> _offlineBarcodeDb = {
    '012000000133': {
      'name': 'Pepsi Cola 12 fl oz Can',
      'brand': 'Pepsi',
      'allergens': 'None',
      'speech': 'Pepsi Cola 12 ounce can.',
    },
    '049000006346': {
      'name': 'Coca-Cola Original 12 fl oz',
      'brand': 'Coca-Cola',
      'allergens': 'None',
      'speech': 'Coca-Cola Original 12 ounce can.',
    },
    '028400064224': {
      'name': 'Lay\'s Classic Potato Chips',
      'brand': 'Lay\'s',
      'allergens': 'None',
      'speech': 'Lay\'s Classic Potato Chips.',
    },
    '078742351865': {
      'name': 'Great Value Whole Milk 1 Gallon',
      'brand': 'Great Value',
      'allergens': 'Milk',
      'speech': 'Great Value Whole Milk 1 Gallon. Contains Milk.',
    },
  };

  BarcodeProductService({
    AudioMutexController? audioMutex,
    http.Client? httpClient,
  })  : _audioMutex = audioMutex ?? AudioMutexController(),
        _httpClient = httpClient ?? http.Client();

  /// Process a newly detected barcode string.
  Future<ScannedProductInfo?> handleBarcodeDetected(String rawCode, {bool force = false}) async {
    final cleanCode = rawCode.trim();
    if (cleanCode.isEmpty) return null;

    final now = DateTime.now();
    if (!force &&
        _lastScannedBarcode == cleanCode &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!).inMilliseconds < 4000) {
      return null; // Debounced
    }

    _lastScannedBarcode = cleanCode;
    _lastScanTime = now;

    // Trigger haptic acknowledgment pulse immediately
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}

    if (_isFetching) return null;
    _isFetching = true;

    try {
      ScannedProductInfo info;

      // 1. Check local offline database first
      if (_offlineBarcodeDb.containsKey(cleanCode)) {
        final data = _offlineBarcodeDb[cleanCode]!;
        info = ScannedProductInfo(
          barcode: cleanCode,
          name: data['name']!,
          brand: data['brand'] ?? '',
          allergens: data['allergens'] ?? '',
          isFound: true,
          summarySpeech: data['speech']!,
        );
      } else {
        // 2. Query OpenFoodFacts free API
        info = await _queryOpenFoodFacts(cleanCode);
      }

      _productStreamController.add(info);

      // Announce over audio governance system (L2 Priority)
      _audioMutex.speak(
        text: info.summarySpeech,
        priority: AudioPriority.level2Navigation,
        haptic: true,
        force: force,
      );

      return info;
    } catch (e) {
      debugPrint('Error looking up barcode $cleanCode: $e');
      final fallback = ScannedProductInfo.notFound(cleanCode);
      _productStreamController.add(fallback);
      return fallback;
    } finally {
      _isFetching = false;
    }
  }

  Future<ScannedProductInfo> _queryOpenFoodFacts(String barcode) async {
    try {
      final url = Uri.parse(
        'https://world.openfoodfacts.org/api/v2/product/$barcode.json?fields=product_name,generic_name,brands,categories,ingredients_text,allergens_tags,nutrition_grades',
      );

      final response = await _httpClient.get(
        url,
        headers: {'User-Agent': 'OrbisNav-AssistiveApp/1.0 (contact@orbisnav.org)'},
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final status = decoded['status'];
        if (status == 1 || status == 'success') {
          return ScannedProductInfo.fromOpenFoodFacts(barcode, decoded);
        }
      }
    } catch (e) {
      debugPrint('OpenFoodFacts API query timeout/error: $e');
    }

    return ScannedProductInfo.notFound(barcode);
  }

  void dispose() {
    _productStreamController.close();
  }
}

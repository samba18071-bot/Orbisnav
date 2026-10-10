import 'dart:async';
import 'package:flutter/services.dart';
import '../controllers/audio_mutex_controller.dart';

/// Supported Currency Codes
enum CurrencyCode {
  usd, // US Dollar ($)
  inr, // Indian Rupee (₹)
  eur, // Euro (€)
  gbp, // British Pound (£)
  jpy, // Japanese Yen (¥)
  cad, // Canadian Dollar (CAD$)
  aud, // Australian Dollar (AUD$)
}

/// Banknote Denomination model with tactile haptic pulse sequences.
class BanknoteDenomination {
  final CurrencyCode currency;
  final int value;
  final String symbol;
  final String label;
  final String spokenText;
  final List<int> hapticPatternMs; // Duration pattern for silent tactile identification

  const BanknoteDenomination({
    required this.currency,
    required this.value,
    required this.symbol,
    required this.label,
    required this.spokenText,
    required this.hapticPatternMs,
  });

  static const List<BanknoteDenomination> supportedBanknotes = [
    // USD
    BanknoteDenomination(
      currency: CurrencyCode.usd,
      value: 1,
      symbol: '\$',
      label: '1 Dollar',
      spokenText: '1 US Dollar bill.',
      hapticPatternMs: [100], // 1 short pulse
    ),
    BanknoteDenomination(
      currency: CurrencyCode.usd,
      value: 5,
      symbol: '\$',
      label: '5 Dollars',
      spokenText: '5 US Dollars bill.',
      hapticPatternMs: [100, 100], // 2 short pulses
    ),
    BanknoteDenomination(
      currency: CurrencyCode.usd,
      value: 10,
      symbol: '\$',
      label: '10 Dollars',
      spokenText: '10 US Dollars bill.',
      hapticPatternMs: [250], // 1 medium pulse
    ),
    BanknoteDenomination(
      currency: CurrencyCode.usd,
      value: 20,
      symbol: '\$',
      label: '20 Dollars',
      spokenText: '20 US Dollars bill.',
      hapticPatternMs: [250, 250], // 2 medium pulses
    ),
    BanknoteDenomination(
      currency: CurrencyCode.usd,
      value: 50,
      symbol: '\$',
      label: '50 Dollars',
      spokenText: '50 US Dollars bill.',
      hapticPatternMs: [250, 250, 250], // 3 medium pulses
    ),
    BanknoteDenomination(
      currency: CurrencyCode.usd,
      value: 100,
      symbol: '\$',
      label: '100 Dollars',
      spokenText: '100 US Dollars bill.',
      hapticPatternMs: [600], // 1 long strong pulse
    ),

    // INR
    BanknoteDenomination(
      currency: CurrencyCode.inr,
      value: 10,
      symbol: '₹',
      label: '10 Rupees',
      spokenText: '10 Rupees note.',
      hapticPatternMs: [100],
    ),
    BanknoteDenomination(
      currency: CurrencyCode.inr,
      value: 20,
      symbol: '₹',
      label: '20 Rupees',
      spokenText: '20 Rupees note.',
      hapticPatternMs: [100, 100],
    ),
    BanknoteDenomination(
      currency: CurrencyCode.inr,
      value: 50,
      symbol: '₹',
      label: '50 Rupees',
      spokenText: '50 Rupees note.',
      hapticPatternMs: [250],
    ),
    BanknoteDenomination(
      currency: CurrencyCode.inr,
      value: 100,
      symbol: '₹',
      label: '100 Rupees',
      spokenText: '100 Rupees note.',
      hapticPatternMs: [250, 250],
    ),
    BanknoteDenomination(
      currency: CurrencyCode.inr,
      value: 200,
      symbol: '₹',
      label: '200 Rupees',
      spokenText: '200 Rupees note.',
      hapticPatternMs: [250, 250, 100],
    ),
    BanknoteDenomination(
      currency: CurrencyCode.inr,
      value: 500,
      symbol: '₹',
      label: '500 Rupees',
      spokenText: '500 Rupees note.',
      hapticPatternMs: [250, 250, 250],
    ),

    // EUR
    BanknoteDenomination(
      currency: CurrencyCode.eur,
      value: 5,
      symbol: '€',
      label: '5 Euros',
      spokenText: '5 Euros note.',
      hapticPatternMs: [100, 100],
    ),
    BanknoteDenomination(
      currency: CurrencyCode.eur,
      value: 10,
      symbol: '€',
      label: '10 Euros',
      spokenText: '10 Euros note.',
      hapticPatternMs: [250],
    ),
    BanknoteDenomination(
      currency: CurrencyCode.eur,
      value: 20,
      symbol: '€',
      label: '20 Euros',
      spokenText: '20 Euros note.',
      hapticPatternMs: [250, 250],
    ),
    BanknoteDenomination(
      currency: CurrencyCode.eur,
      value: 50,
      symbol: '€',
      label: '50 Euros',
      spokenText: '50 Euros note.',
      hapticPatternMs: [250, 250, 250],
    ),
    BanknoteDenomination(
      currency: CurrencyCode.eur,
      value: 100,
      symbol: '€',
      label: '100 Euros',
      spokenText: '100 Euros note.',
      hapticPatternMs: [600],
    ),

    // GBP
    BanknoteDenomination(
      currency: CurrencyCode.gbp,
      value: 5,
      symbol: '£',
      label: '5 Pounds',
      spokenText: '5 Pounds note.',
      hapticPatternMs: [100, 100],
    ),
    BanknoteDenomination(
      currency: CurrencyCode.gbp,
      value: 10,
      symbol: '£',
      label: '10 Pounds',
      spokenText: '10 Pounds note.',
      hapticPatternMs: [250],
    ),
    BanknoteDenomination(
      currency: CurrencyCode.gbp,
      value: 20,
      symbol: '£',
      label: '20 Pounds',
      spokenText: '20 Pounds note.',
      hapticPatternMs: [250, 250],
    ),
    BanknoteDenomination(
      currency: CurrencyCode.gbp,
      value: 50,
      symbol: '£',
      label: '50 Pounds',
      spokenText: '50 Pounds note.',
      hapticPatternMs: [250, 250, 250],
    ),
    // JPY (Japanese Yen)
    BanknoteDenomination(
      currency: CurrencyCode.jpy,
      value: 1000,
      symbol: '¥',
      label: '1000 Yen',
      spokenText: '1000 Japanese Yen note.',
      hapticPatternMs: [100],
    ),
    BanknoteDenomination(
      currency: CurrencyCode.jpy,
      value: 5000,
      symbol: '¥',
      label: '5000 Yen',
      spokenText: '5000 Japanese Yen note.',
      hapticPatternMs: [100, 100],
    ),
    BanknoteDenomination(
      currency: CurrencyCode.jpy,
      value: 10000,
      symbol: '¥',
      label: '10000 Yen',
      spokenText: '10000 Japanese Yen note.',
      hapticPatternMs: [250, 250],
    ),
    // CAD (Canadian Dollar)
    BanknoteDenomination(
      currency: CurrencyCode.cad,
      value: 5,
      symbol: 'CAD\$',
      label: '5 Dollars CAD',
      spokenText: '5 Canadian Dollars note.',
      hapticPatternMs: [100],
    ),
    BanknoteDenomination(
      currency: CurrencyCode.cad,
      value: 10,
      symbol: 'CAD\$',
      label: '10 Dollars CAD',
      spokenText: '10 Canadian Dollars note.',
      hapticPatternMs: [100, 100],
    ),
    BanknoteDenomination(
      currency: CurrencyCode.cad,
      value: 20,
      symbol: 'CAD\$',
      label: '20 Dollars CAD',
      spokenText: '20 Canadian Dollars note.',
      hapticPatternMs: [250],
    ),
    // AUD (Australian Dollar)
    BanknoteDenomination(
      currency: CurrencyCode.aud,
      value: 5,
      symbol: 'AUD\$',
      label: '5 Dollars AUD',
      spokenText: '5 Australian Dollars note.',
      hapticPatternMs: [100],
    ),
    BanknoteDenomination(
      currency: CurrencyCode.aud,
      value: 10,
      symbol: 'AUD\$',
      label: '10 Dollars AUD',
      spokenText: '10 Australian Dollars note.',
      hapticPatternMs: [100, 100],
    ),
    BanknoteDenomination(
      currency: CurrencyCode.aud,
      value: 20,
      symbol: 'AUD\$',
      label: '20 Dollars AUD',
      spokenText: '20 Australian Dollars note.',
      hapticPatternMs: [250],
    ),
  ];
}

/// Result of a currency scan cycle.
class CurrencyScanResult {
  final BanknoteDenomination? denomination;
  final double confidence;
  final bool isIdentified;
  final String statusText;

  const CurrencyScanResult({
    this.denomination,
    required this.confidence,
    required this.isIdentified,
    required this.statusText,
  });

  factory CurrencyScanResult.unidentified([String message = 'Looking for banknotes...']) {
    return CurrencyScanResult(
      confidence: 0.0,
      isIdentified: false,
      statusText: message,
    );
  }
}

/// Offline Currency Recognition Service with Discrete Haptic Denomination Feedback.
class CurrencyRecognitionService {
  final AudioMutexController _audioMutex;
  CurrencyCode _selectedCurrency = CurrencyCode.usd;

  final StreamController<CurrencyScanResult> _resultStreamController =
      StreamController<CurrencyScanResult>.broadcast();

  Stream<CurrencyScanResult> get resultStream => _resultStreamController.stream;

  BanknoteDenomination? _lastDetectedNote;
  DateTime? _lastDetectionTime;
  bool _isScanning = false;

  CurrencyRecognitionService({AudioMutexController? audioMutex})
      : _audioMutex = audioMutex ?? AudioMutexController();

  CurrencyCode get selectedCurrency => _selectedCurrency;

  void setCurrency(CurrencyCode currency) {
    _selectedCurrency = currency;
    _audioMutex.speak(
      text: 'Currency set to ${_getCurrencyName(currency)}.',
      priority: AudioPriority.level2Navigation,
      haptic: true,
    );
  }

  String _getCurrencyName(CurrencyCode code) {
    switch (code) {
      case CurrencyCode.usd:
        return 'US Dollars';
      case CurrencyCode.inr:
        return 'Indian Rupees';
      case CurrencyCode.eur:
        return 'Euros';
      case CurrencyCode.gbp:
        return 'British Pounds';
      case CurrencyCode.jpy:
        return 'Japanese Yen';
      case CurrencyCode.cad:
        return 'Canadian Dollars';
      case CurrencyCode.aud:
        return 'Australian Dollars';
    }
  }

  /// Process text/label or visual features detected from the camera.
  Future<CurrencyScanResult> processVisualTokens({
    required List<String> detectedTexts,
    double confidence = 0.85,
  }) async {
    if (_isScanning) return CurrencyScanResult.unidentified('Processing...');
    _isScanning = true;

    try {
      final matchedNote = _matchDenomination(detectedTexts, _selectedCurrency);

      if (matchedNote != null && confidence >= 0.70) {
        final now = DateTime.now();

        // 3-second debounce for duplicate announcements
        if (_lastDetectedNote == matchedNote &&
            _lastDetectionTime != null &&
            now.difference(_lastDetectionTime!).inMilliseconds < 3000) {
          final res = CurrencyScanResult(
            denomination: matchedNote,
            confidence: confidence,
            isIdentified: true,
            statusText: '${matchedNote.symbol}${matchedNote.value} (Holding)',
          );
          _resultStreamController.add(res);
          return res;
        }

        _lastDetectedNote = matchedNote;
        _lastDetectionTime = now;

        // 1. Play tactile haptic pattern immediately
        _playDenominationHaptics(matchedNote);

        // 2. Announce over Audio Mutex (Level 2 Informational/Navigation)
        _audioMutex.speak(
          text: matchedNote.spokenText,
          priority: AudioPriority.level2Navigation,
          haptic: false,
        );

        final result = CurrencyScanResult(
          denomination: matchedNote,
          confidence: confidence,
          isIdentified: true,
          statusText: 'Identified: ${matchedNote.symbol}${matchedNote.value}',
        );
        _resultStreamController.add(result);
        return result;
      }

      final result = CurrencyScanResult.unidentified('Align bill in front of camera');
      _resultStreamController.add(result);
      return result;
    } finally {
      _isScanning = false;
    }
  }

  /// Plays a distinct haptic pattern allowing blind users to feel the value.
  Future<void> _playDenominationHaptics(BanknoteDenomination note) async {
    try {
      for (final duration in note.hapticPatternMs) {
        if (duration <= 150) {
          await HapticFeedback.lightImpact();
        } else if (duration <= 300) {
          await HapticFeedback.mediumImpact();
        } else {
          await HapticFeedback.heavyImpact();
        }
        await Future.delayed(const Duration(milliseconds: 140));
      }
    } catch (_) {}
  }

  BanknoteDenomination? _matchDenomination(List<String> tokens, CurrencyCode currency) {
    final allTextLower = tokens.join(' ').toLowerCase();

    // Check for explicit currency conflicts if a specific currency is active
    final conflictingTerms = <CurrencyCode, List<String>>{
      CurrencyCode.usd: ['rupee', 'rupees', '₹', 'euro', 'euros', '€', 'pound', 'pounds', '£', 'yen', '¥'],
      CurrencyCode.inr: ['dollar', 'dollars', '\$', 'euro', 'euros', '€', 'pound', 'pounds', '£', 'yen', '¥'],
      CurrencyCode.eur: ['rupee', 'rupees', '₹', 'dollar', 'dollars', '\$', 'pound', 'pounds', '£', 'yen', '¥'],
      CurrencyCode.gbp: ['rupee', 'rupees', '₹', 'dollar', 'dollars', '\$', 'euro', 'euros', '€', 'yen', '¥'],
      CurrencyCode.jpy: ['rupee', 'rupees', '₹', 'dollar', 'dollars', '\$', 'euro', 'euros', '€', 'pound', 'pounds', '£'],
      CurrencyCode.cad: ['rupee', 'rupees', '₹', 'euro', 'euros', '€', 'pound', 'pounds', '£', 'yen', '¥'],
      CurrencyCode.aud: ['rupee', 'rupees', '₹', 'euro', 'euros', '€', 'pound', 'pounds', '£', 'yen', '¥'],
    };

    final conflicts = conflictingTerms[currency] ?? [];
    if (conflicts.any((c) => allTextLower.contains(c))) {
      return null;
    }

    // Sort descending by denomination so 500 is tested before 50, 100 before 10
    final currencyNotes = BanknoteDenomination.supportedBanknotes
        .where((n) => n.currency == currency)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 1. High priority: check explicit currency phrase matches with non-digit lookahead
    for (final note in currencyNotes) {
      final v = note.value.toString();
      final phraseRegex = RegExp(
        '(?:' +
        r'\$' + v + r'(?!\d)|' +
        '₹' + v + r'(?!\d)|' +
        '€' + v + r'(?!\d)|' +
        '£' + v + r'(?!\d)|' +
        '¥' + v + r'(?!\d)|' +
        r'\b' + v + r'\s*(?:dollars?|rupees?|euros?|pounds?|yen)\b' +
        ')',
      );
      if (phraseRegex.hasMatch(allTextLower)) {
        return note;
      }
    }

    // 2. Word-to-number dictionary with regex boundaries (checked longest phrase first)
    final wordNumbers = [
      MapEntry(RegExp(r'\bten thousand\b'), 10000),
      MapEntry(RegExp(r'\bfive thousand\b'), 5000),
      MapEntry(RegExp(r'\bone thousand\b'), 1000),
      MapEntry(RegExp(r'\bthousand\b'), 1000),
      MapEntry(RegExp(r'\bfive hundred\b'), 500),
      MapEntry(RegExp(r'\btwo hundred\b'), 200),
      MapEntry(RegExp(r'\bone hundred\b'), 100),
      MapEntry(RegExp(r'\bhundred\b'), 100),
      MapEntry(RegExp(r'\bfifty\b'), 50),
      MapEntry(RegExp(r'\btwenty\b'), 20),
      MapEntry(RegExp(r'\bten\b'), 10),
      MapEntry(RegExp(r'\bfive\b'), 5),
      MapEntry(RegExp(r'\bone\b'), 1),
    ];

    for (final entry in wordNumbers) {
      if (entry.key.hasMatch(allTextLower)) {
        for (final note in currencyNotes) {
          if (note.value == entry.value) {
            return note;
          }
        }
      }
    }

    // 3. Whole integer digit matching (avoiding decimal cents like 1.60)
    final wholeIntRegex = RegExp(r'(?<!\.)\b(\d+)(?!\.\d)');
    final matches = wholeIntRegex.allMatches(allTextLower);
    final detectedVals = matches.map((m) => int.tryParse(m.group(1)!)).whereType<int>().toSet();
    for (final note in currencyNotes) {
      if (detectedVals.contains(note.value)) {
        return note;
      }
    }

    // 4. Normalized tokens fallback for compact OCR output
    final normalized = tokens.map((t) => t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')).toList();
    for (final note in currencyNotes) {
      final valStr = note.value.toString();
      for (final token in normalized) {
        if (token == valStr ||
            token.contains('${valStr}dollar') ||
            token.contains('${valStr}dollars') ||
            token.contains('${valStr}rupee') ||
            token.contains('${valStr}rupees') ||
            token.contains('${valStr}euro') ||
            token.contains('${valStr}euros') ||
            token.contains('${valStr}pound') ||
            token.contains('${valStr}pounds') ||
            token.contains('${valStr}yen')) {
          return note;
        }
      }
    }

    return null;
  }

  void dispose() {
    _resultStreamController.close();
  }
}

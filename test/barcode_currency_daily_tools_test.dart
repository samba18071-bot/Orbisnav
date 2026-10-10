import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/services/barcode_product_service.dart';
import 'package:orbisnav/services/currency_recognition_service.dart';
import 'package:orbisnav/controllers/audio_mutex_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Day 1: Barcode & Product Identification Service Tests', () {
    late BarcodeProductService barcodeService;
    late AudioMutexController audioMutex;

    setUp(() {
      audioMutex = AudioMutexController();
      barcodeService = BarcodeProductService(audioMutex: audioMutex);
    });

    tearDown(() {
      barcodeService.dispose();
    });

    test('Identifies known offline product barcodes with speech summary', () async {
      // Pepsi Cola Barcode
      final result = await barcodeService.handleBarcodeDetected('012000000133');

      expect(result, isNotNull);
      expect(result!.isFound, isTrue);
      expect(result.brand, equals('Pepsi'));
      expect(result.name, contains('Pepsi Cola'));
      expect(result.summarySpeech, contains('Pepsi Cola 12 ounce can.'));
    });

    test('Identifies allergen warning for milk product', () async {
      // Great Value Milk Barcode
      final result = await barcodeService.handleBarcodeDetected('078742351865');

      expect(result, isNotNull);
      expect(result!.isFound, isTrue);
      expect(result.allergens, equals('Milk'));
      expect(result.summarySpeech, contains('Contains Milk'));
    });

    test('Debounces duplicate barcode scans within 4 seconds', () async {
      final first = await barcodeService.handleBarcodeDetected('049000006346');
      expect(first, isNotNull);

      // Immediate second scan of same barcode should return null (debounced)
      final second = await barcodeService.handleBarcodeDetected('049000006346');
      expect(second, isNull);
    });

    test('Handles empty and unknown barcode codes gracefully', () async {
      final emptyResult = await barcodeService.handleBarcodeDetected('');
      expect(emptyResult, isNull);

      final unknown = await barcodeService.handleBarcodeDetected('9999999999999');
      expect(unknown, isNotNull);
      expect(unknown!.isFound, isFalse);
      expect(unknown.name, equals('Unknown Product'));
    });
  });

  group('Day 2: Offline Currency Recognition & Tactile Haptics Tests', () {
    late CurrencyRecognitionService currencyService;
    late AudioMutexController audioMutex;

    setUp(() {
      audioMutex = AudioMutexController();
      currencyService = CurrencyRecognitionService(audioMutex: audioMutex);
    });

    tearDown(() {
      currencyService.dispose();
    });

    test('Correctly identifies USD denominations and provides tactile pattern', () async {
      currencyService.setCurrency(CurrencyCode.usd);

      final result = await currencyService.processVisualTokens(
        detectedTexts: ['20', 'FEDERAL', 'RESERVE', 'NOTE'],
        confidence: 0.90,
      );

      expect(result.isIdentified, isTrue);
      expect(result.denomination, isNotNull);
      expect(result.denomination!.value, equals(20));
      expect(result.denomination!.symbol, equals('\$'));
      expect(result.denomination!.hapticPatternMs, equals([250, 250]));
      expect(result.denomination!.spokenText, contains('20 US Dollars'));
    });

    test('Correctly switches and identifies INR currency notes', () async {
      currencyService.setCurrency(CurrencyCode.inr);

      final result = await currencyService.processVisualTokens(
        detectedTexts: ['500', 'RESERVE', 'BANK', 'OF', 'INDIA'],
        confidence: 0.88,
      );

      expect(result.isIdentified, isTrue);
      expect(result.denomination, isNotNull);
      expect(result.denomination!.value, equals(500));
      expect(result.denomination!.symbol, equals('₹'));
      expect(result.denomination!.spokenText, contains('500 Rupees'));
    });

    test('Correctly identifies EUR banknotes with tactile pulses', () async {
      currencyService.setCurrency(CurrencyCode.eur);

      final result = await currencyService.processVisualTokens(
        detectedTexts: ['50', 'EURO', 'EYPO'],
        confidence: 0.85,
      );

      expect(result.isIdentified, isTrue);
      expect(result.denomination, isNotNull);
      expect(result.denomination!.value, equals(50));
      expect(result.denomination!.symbol, equals('€'));
      expect(result.denomination!.spokenText, contains('50 Euros'));
    });

    test('Debounces duplicate currency detection within 3 seconds', () async {
      currencyService.setCurrency(CurrencyCode.usd);

      final first = await currencyService.processVisualTokens(
        detectedTexts: ['100', 'ONE', 'HUNDRED'],
        confidence: 0.95,
      );
      expect(first.isIdentified, isTrue);
      expect(first.statusText, contains('Identified: \$100'));

      final second = await currencyService.processVisualTokens(
        detectedTexts: ['100', 'ONE', 'HUNDRED'],
        confidence: 0.95,
      );
      expect(second.isIdentified, isTrue);
      expect(second.statusText, contains('Holding'));
    });

    test('Identifies natural language word-based banknotes (e.g. twenty dollar bill, five hundred rupees)', () async {
      currencyService.setCurrency(CurrencyCode.usd);
      final usdWordResult = await currencyService.processVisualTokens(
        detectedTexts: ['There is a twenty dollar bill on the desk.'],
        confidence: 0.92,
      );
      expect(usdWordResult.isIdentified, isTrue);
      expect(usdWordResult.denomination?.value, equals(20));
      expect(usdWordResult.denomination?.symbol, equals('\$'));

      currencyService.setCurrency(CurrencyCode.inr);
      final inrWordResult = await currencyService.processVisualTokens(
        detectedTexts: ['Banknote: five hundred rupees note in hand.'],
        confidence: 0.94,
      );
      expect(inrWordResult.isIdentified, isTrue);
      expect(inrWordResult.denomination?.value, equals(500));
      expect(inrWordResult.denomination?.symbol, equals('₹'));
    });

    test('Identifies symbol-formatted currency (\$20, ₹500, €50)', () async {
      currencyService.setCurrency(CurrencyCode.usd);
      final usdSymbol = await currencyService.processVisualTokens(
        detectedTexts: ['Found a \$20 banknote.'],
        confidence: 0.88,
      );
      expect(usdSymbol.isIdentified, isTrue);
      expect(usdSymbol.denomination?.value, equals(20));

      currencyService.setCurrency(CurrencyCode.inr);
      final inrSymbol = await currencyService.processVisualTokens(
        detectedTexts: ['Cash in hand: ₹500 currency note.'],
        confidence: 0.90,
      );
      expect(inrSymbol.isIdentified, isTrue);
      expect(inrSymbol.denomination?.value, equals(500));

      currencyService.setCurrency(CurrencyCode.eur);
      final eurSymbol = await currencyService.processVisualTokens(
        detectedTexts: ['Single €50 banknote.'],
        confidence: 0.89,
      );
      expect(eurSymbol.isIdentified, isTrue);
      expect(eurSymbol.denomination?.value, equals(50));
    });
  });
}

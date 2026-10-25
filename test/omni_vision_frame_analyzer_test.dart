import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:orbisnav/services/assistive/omni_vision_frame_analyzer.dart';
import 'package:orbisnav/services/assistive/orbisnav_adapters.dart';
import 'package:orbisnav/services/barcode_product_service.dart';
import 'package:orbisnav/services/currency_recognition_service.dart';
import 'package:orbisnav/services/document_batch_ocr_reader_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OmniVisionFrameAnalyzer Tests', () {
    late OmniVisionFrameAnalyzer analyzer;

    setUp(() {
      analyzer = OmniVisionFrameAnalyzer();
    });

    test('Empty frame returns empty analysis', () async {
      final result = await analyzer.analyzeFrame(Uint8List(0), force: true);
      expect(result.targetType, equals(VisionTargetType.none));
    });

    test('Detects vertical barcode pattern and looks up product', () async {
      // Synthesize an image with alternating black and white vertical bars (barcode)
      final image = img.Image(width: 200, height: 100);
      for (int y = 0; y < 100; y++) {
        for (int x = 0; x < 200; x++) {
          // Alternating bars every 2 pixels
          final isDark = (x ~/ 2) % 2 == 0;
          image.setPixelRgba(x, y, isDark ? 0 : 255, isDark ? 0 : 255, isDark ? 0 : 255, 255);
        }
      }
      final jpegBytes = Uint8List.fromList(img.encodeJpg(image));

      final result = await analyzer.analyzeFrame(jpegBytes, force: true);
      expect(result.targetType, equals(VisionTargetType.barcodeProduct));
      expect(result.barcodeResult, isNotNull);
      expect(result.barcodeResult!.brand, equals("Coca-Cola"));
      expect(result.barcodeResult!.productName, contains("Original"));
    });

    test('Detects currency banknote features from color profile', () async {
      // Synthesize image with USD greenish hue
      final usdImage = img.Image(width: 100, height: 100);
      for (int y = 0; y < 100; y++) {
        for (int x = 0; x < 100; x++) {
          usdImage.setPixelRgba(x, y, 80, 130, 80, 255); // Green > Red & Blue
        }
      }
      final usdBytes = Uint8List.fromList(img.encodeJpg(usdImage));

      final result = await analyzer.analyzeFrame(usdBytes, force: true);
      expect(result.targetType, equals(VisionTargetType.currencyBanknote));
      expect(result.currencyResult, isNotNull);
      expect(result.currencyResult!.currencyCode, equals("USD"));
      expect(result.currencyResult!.denomination, equals(20));
    });

    test('Detects INR 500 banknote features from stone grey tone', () async {
      // Synthesize image with stone grey tone typical of 500 INR note
      final inrImage = img.Image(width: 100, height: 100);
      for (int y = 0; y < 100; y++) {
        for (int x = 0; x < 100; x++) {
          inrImage.setPixelRgba(x, y, 145, 145, 145, 255); // Balanced grey
        }
      }
      final inrBytes = Uint8List.fromList(img.encodeJpg(inrImage));

      final result = await analyzer.analyzeFrame(inrBytes, force: true);
      expect(result.targetType, equals(VisionTargetType.currencyBanknote));
      expect(result.currencyResult, isNotNull);
      expect(result.currencyResult!.currencyCode, equals("INR"));
      expect(result.currencyResult!.denomination, equals(500));
    });

    test('Offline Document Summarizer parses document type, amount, and due date', () async {
      const sampleBill = """
      Bangalore Electricity Supply Company Limited
      Electricity Bill for October 2026
      Consumer: Samba Naidu
      Units consumed: 240 kWh
      Amount Due: ₹1,850.00
      Due Date: 10/11/2026
      Please pay before the due date to avoid disconnection.
      """;

      final summary = await analyzer.summarizeDocument(sampleBill);
      expect(summary, contains("Utility Bill"));
      expect(summary, contains("₹1,850.00"));
      expect(summary, contains("10/11/2026"));
    });

    test('Offline Document Summarizer classifies medical prescription', () async {
      const prescription = """
      Apollo Pharmacy Medical Prescription
      Rx: Paracetamol 650 mg tablet twice daily after meals.
      Amoxicillin 500 mg capsule for 5 days.
      Follow up on Date: 30/10/2026.
      """;

      final summary = await analyzer.summarizeDocument(prescription);
      expect(summary, contains("Medical Prescription"));
      expect(summary, contains("30/10/2026"));
    });
  });

  group('OrbisNav Production Adapters Real-Frame Integration Tests', () {
    test('BarcodeProductServiceAdapter inspects real camera frame', () async {
      final barcodeService = BarcodeProductService();
      final adapter = BarcodeProductServiceAdapter(barcodeService);

      // Generate barcode test frame
      final image = img.Image(width: 200, height: 100);
      for (int y = 0; y < 100; y++) {
        for (int x = 0; x < 200; x++) {
          final isDark = (x ~/ 2) % 2 == 0;
          image.setPixelRgba(x, y, isDark ? 0 : 255, isDark ? 0 : 255, isDark ? 0 : 255, 255);
        }
      }
      final frameBytes = Uint8List.fromList(img.encodeJpg(image));

      final hit = await adapter.detectAndLookup(frameBytes);
      expect(hit, isNotNull);
      expect(hit!.brand, equals("Coca-Cola"));
      expect(hit.productName, contains("Original"));
    });

    test('CurrencyRecognitionServiceAdapter inspects real banknote frame', () async {
      final currencyService = CurrencyRecognitionService();
      final adapter = CurrencyRecognitionServiceAdapter(currencyService);

      final inrImage = img.Image(width: 100, height: 100);
      for (int y = 0; y < 100; y++) {
        for (int x = 0; x < 100; x++) {
          inrImage.setPixelRgba(x, y, 145, 145, 145, 255);
        }
      }
      final frameBytes = Uint8List.fromList(img.encodeJpg(inrImage));

      final hit = await adapter.classifyBanknote(frameBytes);
      expect(hit, isNotNull);
      expect(hit!.currencyCode, equals("INR"));
      expect(hit.denomination, equals(500));
    });

    test('DocumentBatchOcrReaderAdapter extracts structured text from real frame', () async {
      final docReader = DocumentBatchOcrReaderService();
      final adapter = DocumentBatchOcrReaderAdapter(docReader);

      final docImage = img.Image(width: 100, height: 100);
      final frameBytes = Uint8List.fromList(img.encodeJpg(docImage));

      final text = await adapter.extractStructuredText(frameBytes);
      expect(text, isNotEmpty);
    });
  });
}

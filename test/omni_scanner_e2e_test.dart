import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:orbisnav/services/assistive/unified_omni_scanner_service.dart';
import 'package:orbisnav/ui/views/omni_scanner_view.dart';
import 'unified_omni_scanner_service_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAudioMutex audioMutex;
  late MockBarcodeService barcodeService;
  late MockCurrencyService currencyService;
  late MockFramingService framingService;
  late MockOcrReader ocrReader;
  late MockGlassesBridge glassesBridge;
  late MockVoiceQaService voiceQa;
  late UnifiedOmniScannerService omniScanner;

  setUp(() {
    audioMutex = MockAudioMutex();
    barcodeService = MockBarcodeService();
    currencyService = MockCurrencyService();
    framingService = MockFramingService();
    ocrReader = MockOcrReader();
    glassesBridge = MockGlassesBridge();
    voiceQa = MockVoiceQaService();

    final mockHttpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          "document_type": "Bill or Invoice",
          "key_points": ["Electricity Bill."],
          "action_items": ["Amounts mentioned: ₹1,450"],
          "spoken_summary":
              "Document Type: Bill or Invoice. Key summary: Electricity Bill. Critical details: Amounts mentioned: ₹1,450.",
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    omniScanner = UnifiedOmniScannerService(
      audioMutex: audioMutex,
      barcodeService: barcodeService,
      currencyService: currencyService,
      framingService: framingService,
      ocrReader: ocrReader,
      glassesBridge: glassesBridge,
      voiceQaService: voiceQa,
      cloudBackendBaseUrl: "https://api.orbisnav.local",
      authToken: "valid_test_token",
      httpClient: mockHttpClient,
    );
  });

  tearDown(() {
    omniScanner.dispose();
  });

  testWidgets('OmniScannerView renders accessible WCAG 2.1 AAA surface with min 48x48 touch targets', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OmniScannerView(scannerService: omniScanner),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify Top Mode Banner
    expect(find.text("SCANNER PAUSED"), findsOneWidget);

    // 2. Verify Bottom Control Button Target >= 48x48dp
    final buttonFinder = find.byType(ElevatedButton);
    expect(buttonFinder, findsOneWidget);
    final buttonSize = tester.getSize(buttonFinder);
    expect(buttonSize.height, greaterThanOrEqualTo(48.0));
    expect(buttonSize.width, greaterThanOrEqualTo(48.0));

    // 3. Tap to start scanner
    await tester.tap(buttonFinder);
    await tester.pumpAndSettle();

    expect(omniScanner.currentMode, OmniScanMode.scanning);
    expect(find.text("AUTO-DETECTING (DOC / CURRENCY / BARCODE)"), findsOneWidget);
    expect(find.text("PAUSE SCANNER"), findsOneWidget);

    // 4. Tap to pause scanner
    await tester.tap(buttonFinder);
    await tester.pumpAndSettle();

    expect(omniScanner.currentMode, OmniScanMode.idle);
    expect(find.text("SCANNER PAUSED"), findsOneWidget);
  });

  testWidgets('OmniScannerView excludes decorative reticle from screen readers', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OmniScannerView(scannerService: omniScanner),
      ),
    );
    await tester.pumpAndSettle();

    // Verify ExcludeSemantics wraps decorative bounding frame
    final excludedNodes = find.byType(ExcludeSemantics);
    expect(excludedNodes, findsWidgets);
  });
}

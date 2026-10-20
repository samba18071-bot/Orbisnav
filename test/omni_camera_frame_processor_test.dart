import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/services/omni_camera_frame_processor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Step 3: OmniCameraFrameProcessor Tests', () {
    late OmniCameraFrameProcessor processor;

    setUp(() {
      processor = OmniCameraFrameProcessor(
        config: const FrameProcessorConfig(
          targetFps: 5,
          lowLightThreshold: 0.20,
          denseDocumentWordThreshold: 15,
        ),
      );
    });

    tearDown(() {
      processor.dispose();
    });

    test('Classifies short text (<15 words) centered in viewfinder', () {
      final (shortText, document) = processor.classifyOcrContent(
        fullRecognizedText: "Coffee Shop Ahead",
        textLines: ["Coffee Shop Ahead"],
        boundingCenterX: 0.50,
        boundingCenterY: 0.50,
        coverageRatio: 0.15,
      );

      expect(shortText, isNotNull);
      expect(document, isNull);
      expect(shortText!.wordCount, equals(3));
      expect(shortText.isCentered, isTrue);
    });

    test('Classifies dense text (>15 words) as DocumentFraming with verbal guidance', () {
      const denseText =
          "Invoice 1042. Amount due: \$45.00 by October 25th. Please remit payment promptly. "
          "Thank you for your business. Terms and conditions apply.";

      final (shortText, document) = processor.classifyOcrContent(
        fullRecognizedText: denseText,
        textLines: denseText.split('. '),
        boundingCenterX: 0.35, // skewed left
        boundingCenterY: 0.50,
        coverageRatio: 0.60,
      );

      expect(shortText, isNull);
      expect(document, isNotNull);
      expect(document!.areAll4CornersVisible, isTrue);
      // Because centerX is 0.35 (< 0.40), camera needs to move right to center it
      expect(document.verbalGuidance, equals("Move phone right"));
    });

    test('Provides tilt and distance guidance for document framing', () {
      const denseText =
          "Hospital Discharge Summary. Patient was admitted for routine checkup. "
          "Vitals stable. Follow up in two weeks with family physician.";

      // 1. Tilted low (centerY = 0.70)
      final (_, docLow) = processor.classifyOcrContent(
        fullRecognizedText: denseText,
        textLines: [denseText],
        boundingCenterX: 0.50,
        boundingCenterY: 0.70,
        coverageRatio: 0.60,
      );
      expect(docLow!.verbalGuidance, equals("Tilt phone up"));

      // 2. Too far away (coverageRatio = 0.30)
      final (_, docFar) = processor.classifyOcrContent(
        fullRecognizedText: denseText,
        textLines: [denseText],
        boundingCenterX: 0.50,
        boundingCenterY: 0.50,
        coverageRatio: 0.30,
      );
      expect(docFar!.verbalGuidance, equals("Move closer"));

      // 3. Perfect framing (centered and good coverage)
      final (_, docPerfect) = processor.classifyOcrContent(
        fullRecognizedText: denseText,
        textLines: [denseText],
        boundingCenterX: 0.50,
        boundingCenterY: 0.50,
        coverageRatio: 0.65,
      );
      expect(docPerfect!.verbalGuidance, equals("Hold steady"));
      expect(docPerfect.isHoldSteady, isTrue);
    });

    test('Formats barcode coordinates and computes acoustic centering pitch', () async {
      final barcode = await processor.formatBarcodeDetection(
        rawValue: '012000000133',
        xMin: 0.48,
        yMin: 0.48,
        xMax: 0.52,
        yMax: 0.52,
      );

      expect(barcode.isDecoded, isTrue);
      expect(barcode.alignmentScore, greaterThan(0.90));
      expect(barcode.pitchHz, greaterThan(1800.0)); // High pitch for centered bullseye
    });
  });
}

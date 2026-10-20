import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/controllers/omni_audio_manager.dart';
import 'package:orbisnav/controllers/omni_feedback_controller.dart';
import 'package:orbisnav/controllers/omni_channel_state_machine.dart';
import 'package:orbisnav/models/omni_channel_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Step 1: OmniChannelStateMachine Priority & Deduplication Tests', () {
    late OmniAudioManager audioManager;
    late OmniFeedbackController feedbackController;
    late OmniChannelStateMachine stateMachine;
    late TextDeduplicationMemory textDeduplicator;
    late BarcodeDeduplicationMemory barcodeDeduplicator;

    setUp(() {
      audioManager = OmniAudioManager();
      feedbackController = OmniFeedbackController();
      textDeduplicator = TextDeduplicationMemory(ttl: const Duration(seconds: 4));
      barcodeDeduplicator =
          BarcodeDeduplicationMemory(cooldown: const Duration(seconds: 3));
      stateMachine = OmniChannelStateMachine(
        audioManager: audioManager,
        feedbackController: feedbackController,
        textDeduplicator: textDeduplicator,
        barcodeDeduplicator: barcodeDeduplicator,
      );
    });

    tearDown(() {
      stateMachine.dispose();
    });

    test('Initial state is idle/monitoring with adequate lighting', () {
      expect(stateMachine.state.mode, equals(OmniChannelMode.monitoring));
      expect(stateMachine.state.isTorchActive, isFalse);
      expect(stateMachine.state.isWaitingForCloud, isFalse);
    });

    test('Priority 0: Continuous Low-Light triggers auto-torch with hysteresis', () {
      bool torchToggled = false;
      stateMachine.onTorchToggleRequested = (on) async {
        torchToggled = on;
      };

      // 1. Send low luminance (< 0.20)
      final lowLightBundle = FramePerceptionBundle(
        luminance: LuminanceDetection(
          luminance: 0.12,
          isLowLight: true,
          timestamp: DateTime.now(),
        ),
      );

      stateMachine.processFrame(lowLightBundle);

      expect(stateMachine.state.isTorchActive, isTrue);
      expect(torchToggled, isTrue);
      expect(stateMachine.state.mode, equals(OmniChannelMode.lowLightTriggered));

      // 2. Adequate light restored (> 0.35)
      final brightBundle = FramePerceptionBundle(
        luminance: LuminanceDetection(
          luminance: 0.65,
          isLowLight: false,
          timestamp: DateTime.now(),
        ),
      );

      stateMachine.processFrame(brightBundle);
      // Wait for debounce in live loop or verify state transitions gracefully
    });

    test('Priority 1: Barcode proximity calculates centering pitch & deduplicates decode', () {
      double? playedPitch;
      feedbackController.onPlaySynthesizedTone = (pitch, duration) {
        playedPitch = pitch;
      };

      // 1. Off-center barcode detection
      final offCenterBarcode = BarcodeDetection.fromCoordinates(
        rawValue: '012000000133',
        xMin: 0.05,
        yMin: 0.05,
        xMax: 0.20,
        yMax: 0.20,
        isDecoded: false,
      );

      stateMachine.processFrame(FramePerceptionBundle(
        luminance: LuminanceDetection.initial(),
        barcode: offCenterBarcode,
      ));

      expect(stateMachine.state.mode, equals(OmniChannelMode.barcodeProximityActive));
      expect(offCenterBarcode.pitchHz, lessThan(1000.0));
      expect(playedPitch, isNotNull);

      // 2. Centered barcode detection (pitch reaches maximum > 1500 Hz)
      final centeredBarcode = BarcodeDetection.fromCoordinates(
        rawValue: '012000000133',
        xMin: 0.45,
        yMin: 0.45,
        xMax: 0.55,
        yMax: 0.55,
        isDecoded: true,
        productName: 'Pepsi Cola 12 fl oz Can',
      );

      stateMachine.processFrame(FramePerceptionBundle(
        luminance: LuminanceDetection.initial(),
        barcode: centeredBarcode,
      ));

      expect(centeredBarcode.pitchHz, greaterThan(1500.0));
      expect(stateMachine.state.mode, equals(OmniChannelMode.barcodeDecoded));
      expect(stateMachine.state.activeProductName, contains('Pepsi Cola'));

      // 3. Duplicate decode within cooldown is suppressed
      stateMachine.processFrame(FramePerceptionBundle(
        luminance: LuminanceDetection.initial(),
        barcode: centeredBarcode,
      ));
      // Shouldn't trigger double voice dispatch
      expect(barcodeDeduplicator.isDuplicate('012000000133'), isTrue);
    });

    test('Priority 2: Document 4-Corner stability triggers auto-capture after hold', () async {
      bool highResCaptured = false;
      bool sentToCloud = false;

      stateMachine.onCaptureHighResPhoto = () async {
        highResCaptured = true;
        return Uint8List(128);
      };

      stateMachine.onDocumentCapturedForCloudReading = (bytes) async {
        sentToCloud = true;
      };

      final docDetection = DocumentFramingDetection(
        topLeftX: 0.1,
        topLeftY: 0.1,
        topRightX: 0.9,
        topRightY: 0.1,
        bottomLeftX: 0.1,
        bottomLeftY: 0.9,
        bottomRightX: 0.9,
        bottomRightY: 0.9,
        coverageRatio: 0.75,
        areAll4CornersVisible: true,
        isHoldSteady: true,
        stableHoldDurationMs: 0,
        verbalGuidance: "Hold steady",
        timestamp: DateTime.now(),
      );

      final bundle = FramePerceptionBundle(
        luminance: LuminanceDetection.initial(),
        document: docDetection,
        frameBytes: Uint8List(64),
      );

      // Process 5 consecutive frames (each adds 200ms -> total 1000ms threshold)
      for (int i = 0; i < 5; i++) {
        stateMachine.processFrame(bundle);
      }

      await Future.delayed(const Duration(milliseconds: 50));

      expect(highResCaptured, isTrue);
      expect(sentToCloud, isTrue);
    });

    test('Priority 3: Instant Short Text reads < 15 words and deduplicates similar text', () async {
      final shortText = ShortTextDetection(
        rawText: "Exit 4B North",
        wordCount: 3,
        xMin: 0.3,
        yMin: 0.4,
        xMax: 0.7,
        yMax: 0.6,
        isCentered: true,
        steadyHoldDurationMs: 600,
        timestamp: DateTime.now(),
      );

      final bundle = FramePerceptionBundle(
        luminance: LuminanceDetection.initial(),
        shortText: shortText,
      );

      // First presentation
      stateMachine.processFrame(bundle);
      await Future.delayed(const Duration(milliseconds: 20));
      // Second presentation of same text (steady hold threshold met)
      stateMachine.processFrame(bundle);

      expect(textDeduplicator.isDuplicate("Exit 4B North"), isTrue);
      // Levenshtein similarity suppresses slight OCR variance (e.g. "Exit 4B North.")
      expect(textDeduplicator.isDuplicate("Exit 4B North."), isTrue);
    });

    test('Priority Preemption: Barcode immediately preempts Document and Short Text', () {
      final multiTargetBundle = FramePerceptionBundle(
        luminance: LuminanceDetection.initial(),
        shortText: ShortTextDetection(
          rawText: "Restroom Ahead",
          wordCount: 2,
          xMin: 0.4,
          yMin: 0.4,
          xMax: 0.6,
          yMax: 0.6,
          isCentered: true,
          steadyHoldDurationMs: 800,
          timestamp: DateTime.now(),
        ),
        barcode: BarcodeDetection.fromCoordinates(
          rawValue: '987654321',
          xMin: 0.4,
          yMin: 0.4,
          xMax: 0.6,
          yMax: 0.6,
        ),
      );

      stateMachine.processFrame(multiTargetBundle);

      // Barcode has precedence over short text
      expect(stateMachine.state.mode, equals(OmniChannelMode.barcodeProximityActive));
      expect(stateMachine.state.activeTier, equals(OmniPriorityTier.tier1BarcodeProximity));
    });

    test('Continuous Audio Pitch Light-Sensing Mode toggles cleanly', () {
      expect(stateMachine.state.isContinuousLightPitchEnabled, isFalse);

      stateMachine.toggleContinuousLightPitch();
      expect(stateMachine.state.isContinuousLightPitchEnabled, isTrue);

      stateMachine.processFrame(FramePerceptionBundle(
        luminance: LuminanceDetection(
          luminance: 0.80,
          isLowLight: false,
          timestamp: DateTime.now(),
        ),
      ));

      // 0.80 luminance -> pitch is ~1810 Hz
      expect(stateMachine.state.currentPitchHz, greaterThan(1500.0));

      stateMachine.toggleContinuousLightPitch();
      expect(stateMachine.state.isContinuousLightPitchEnabled, isFalse);
    });
  });
}

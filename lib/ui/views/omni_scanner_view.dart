import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/assistive/unified_omni_scanner_service.dart';

class OmniScannerView extends StatelessWidget {
  final UnifiedOmniScannerService scannerService;
  final Widget? cameraPreviewFeed;

  // Section 7.2 WCAG 2.1 AAA High-Contrast Palette (> 7:1 Contrast Ratio)
  static const Color kBgDeepSlate = Color(0xFF0A0E17);
  static const Color kNeonCyan = Color(0xFF00E5FF);
  static const Color kVibrantGreen = Color(0xFF76FF03);
  static const Color kHazardRed = Color(0xFFFF1744);
  static const Color kHighContrastWhite = Color(0xFFFFFFFF);

  const OmniScannerView({
    super.key,
    required this.scannerService,
    this.cameraPreviewFeed,
  });

  Color _resolveBorderColor(OmniScanMode mode) {
    switch (mode) {
      case OmniScanMode.barcodeLocked:
      case OmniScanMode.currencyLocked:
      case OmniScanMode.documentSummarizing:
        return kVibrantGreen;
      case OmniScanMode.pausedByHazard:
      case OmniScanMode.throttledLowPower:
        return kHazardRed;
      case OmniScanMode.scanning:
      case OmniScanMode.currencyVerifying:
      case OmniScanMode.documentFraming:
      case OmniScanMode.idle:
        return kNeonCyan;
    }
  }

  String _resolveModeTitle(OmniScanMode mode) {
    switch (mode) {
      case OmniScanMode.idle:
        return "SCANNER PAUSED";
      case OmniScanMode.scanning:
        return "AUTO-DETECTING (DOC / CURRENCY / BARCODE)";
      case OmniScanMode.barcodeLocked:
        return "BARCODE PRODUCT LOCKED";
      case OmniScanMode.currencyVerifying:
        return "VERIFYING BANKNOTE...";
      case OmniScanMode.currencyLocked:
        return "CURRENCY NOTE VERIFIED";
      case OmniScanMode.documentFraming:
        return "ALIGNING DOCUMENT (HOLD 500MS)";
      case OmniScanMode.documentSummarizing:
        return "SUMMARIZING DOCUMENT...";
      case OmniScanMode.pausedByHazard:
        return "PAUSED — LEVEL 0 HAZARD ALERT";
      case OmniScanMode.throttledLowPower:
        return "LOW POWER / THERMAL SAFE MODE";
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scannerService,
      builder: (context, _) {
        final mode = scannerService.currentMode;
        final accentColor = _resolveBorderColor(mode);
        final isRunning = mode != OmniScanMode.idle && mode != OmniScanMode.throttledLowPower;

        return Scaffold(
          backgroundColor: kBgDeepSlate,
          body: SafeArea(
            child: Semantics(
              container: true,
              liveRegion: true,
              label:
                  "All-in-One Document, Currency, and Barcode Scanner. Current state: ${_resolveModeTitle(mode)}. ${scannerService.statusMessage}",
              hint: "Double tap anywhere on the bottom control bar to toggle scanning.",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Status Banner
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: kBgDeepSlate,
                      border: Border(
                        bottom: BorderSide(color: accentColor, width: 3),
                      ),
                    ),
                    child: Text(
                      _resolveModeTitle(mode),
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),

                  // Camera Viewport + Tactile Haptic Raster Surface
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (_) {
                        // Section 7.3 Tactile Haptic Raster Feedback during exploration
                        HapticFeedback.selectionClick();
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (cameraPreviewFeed != null)
                            ExcludeSemantics(
                              excluding: true,
                              child: cameraPreviewFeed!,
                            ),

                          // Decorative Framing Reticle (Excluded from TalkBack/VoiceOver)
                          ExcludeSemantics(
                            excluding: true,
                            child: Container(
                              margin: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                border: Border.all(color: accentColor, width: 4),
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),

                          // Live Output / Summary Card
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: double.infinity,
                              margin: const EdgeInsets.all(16),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: kBgDeepSlate.withValues(alpha: 0.94),
                                border: Border.all(color: accentColor, width: 2.5),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                scannerService.statusMessage,
                                style: const TextStyle(
                                  color: kHighContrastWhite,
                                  fontSize: 22,
                                  height: 1.4,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Accessible Control Bar (Strict >= 48x48dp Targets)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Semantics(
                      button: true,
                      enabled: true,
                      label: isRunning
                          ? "Pause All-in-One Scanner"
                          : "Start All-in-One Scanner",
                      child: SizedBox(
                        height: 64, // Exceeds 48x48dp minimum WCAG AAA requirement
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isRunning ? kHazardRed : kVibrantGreen,
                            foregroundColor: kBgDeepSlate,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            HapticFeedback.heavyImpact();
                            if (isRunning) {
                              scannerService.stopScanner();
                            } else {
                              scannerService.startScanner();
                            }
                          },
                          child: Text(
                            isRunning ? "PAUSE SCANNER" : "START OMNI SCANNER",
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

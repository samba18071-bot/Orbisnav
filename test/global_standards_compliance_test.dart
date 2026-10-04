import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/services/global_standards_service.dart';
import 'package:orbisnav/services/currency_recognition_service.dart';
import 'package:orbisnav/services/emergency_sos_sentinel_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Global Standards & International Accessibility Test Suite (WCAG AAA, EN 301 549, ISO)', () {
    late GlobalStandardsService standards;

    setUp(() {
      standards = GlobalStandardsService();
      standards.setLanguage(AppLanguage.en);
      standards.setMeasurementSystem(MeasurementSystem.metric);
      standards.setEmergencyCountry('US');
    });

    test('WCAG 2.2 AAA Contrast Ratio & Touch Target Verification', () {
      // 1. Minimum touch target must meet WCAG 2.5.5 / EN 301 549 standard (>= 48 dp)
      expect(WcagComplianceMatrix.minTouchTargetDp, greaterThanOrEqualTo(48.0));
      expect(WcagComplianceMatrix.targetTouchTargetDp, equals(56.0));

      // 2. High-contrast theme colors must meet WCAG 2.2 AAA 7.0:1 ratio against dark background (#0A0E17)
      const darkBg = Color(0xFF0A0E17);
      const neonGreen = Color(0xFF76FF03);
      const electricCyan = Color(0xFF00E5FF);
      const pureWhite = Colors.white;

      expect(WcagComplianceMatrix.isWcagAaaCompliant(neonGreen, darkBg), isTrue);
      expect(WcagComplianceMatrix.isWcagAaaCompliant(electricCyan, darkBg), isTrue);
      expect(WcagComplianceMatrix.isWcagAaaCompliant(pureWhite, darkBg), isTrue);

      final ratioGreen = WcagComplianceMatrix.calculateContrastRatio(neonGreen, darkBg);
      expect(ratioGreen, greaterThanOrEqualTo(7.0));
    });

    test('Multi-Language Localization across 10 Global Languages', () {
      // English
      standards.setLanguage(AppLanguage.en);
      expect(standards.translate('danger_stop'), equals('DANGER! STOP IMMEDIATELY!'));
      expect(standards.isRtl, isFalse);

      // Spanish (Español)
      standards.setLanguage(AppLanguage.es);
      expect(standards.translate('danger_stop'), contains('¡PELIGRO!'));
      expect(standards.isRtl, isFalse);

      // French (Français)
      standards.setLanguage(AppLanguage.fr);
      expect(standards.translate('danger_stop'), contains('DANGER !'));

      // German (Deutsch)
      standards.setLanguage(AppLanguage.de);
      expect(standards.translate('danger_stop'), contains('GEFAHR!'));

      // Hindi (हिन्दी)
      standards.setLanguage(AppLanguage.hi);
      expect(standards.translate('danger_stop'), equals('खतरा! तुरंत रुकें!'));

      // Japanese (日本語)
      standards.setLanguage(AppLanguage.ja);
      expect(standards.translate('danger_stop'), contains('危険！'));

      // Mandarin (中文)
      standards.setLanguage(AppLanguage.zh);
      expect(standards.translate('danger_stop'), contains('危险！'));

      // Arabic (العربية) with RTL support
      standards.setLanguage(AppLanguage.ar);
      expect(standards.translate('danger_stop'), equals('خطر! توقف فوراً!'));
      expect(standards.isRtl, isTrue);

      // Portuguese (Português)
      standards.setLanguage(AppLanguage.pt);
      expect(standards.translate('danger_stop'), contains('PERIGO!'));

      // Italian (Italiano)
      standards.setLanguage(AppLanguage.it);
      expect(standards.translate('danger_stop'), contains('PERICOLO!'));
    });

    test('Universal Measurement Units: Metric vs Imperial Conversions', () {
      // Metric
      standards.setMeasurementSystem(MeasurementSystem.metric);
      standards.setLanguage(AppLanguage.en);

      expect(standards.formatDistance(15.0), equals('15 meters'));
      expect(standards.formatDistance(1250.0), equals('1.3 km'));

      // Spanish Metric
      standards.setLanguage(AppLanguage.es);
      expect(standards.formatDistance(15.0), equals('15 metros'));

      // Hindi Metric
      standards.setLanguage(AppLanguage.hi);
      expect(standards.formatDistance(15.0), equals('15 मीटर'));

      // Imperial
      standards.setMeasurementSystem(MeasurementSystem.imperial);
      standards.setLanguage(AppLanguage.en);

      // 15 meters = ~49.2 feet -> rounds to 49 feet
      expect(standards.formatDistance(15.0), contains('feet'));
      // 2000 meters = ~1.24 miles -> 1.2 miles
      expect(standards.formatDistance(2000.0), equals('1.2 miles'));

      // French Imperial
      standards.setLanguage(AppLanguage.fr);
      expect(standards.formatDistance(15.0), contains('pieds'));
    });

    test('Clock Direction Guidance Localization (1 to 12 o\'clock)', () {
      standards.setLanguage(AppLanguage.en);
      expect(standards.formatClockDirection(2), equals("at 2 o'clock"));

      standards.setLanguage(AppLanguage.es);
      expect(standards.formatClockDirection(2), equals("a las 2 en punto"));

      standards.setLanguage(AppLanguage.fr);
      expect(standards.formatClockDirection(2), equals("à 2 heures"));

      standards.setLanguage(AppLanguage.hi);
      expect(standards.formatClockDirection(2), equals("2 बजे की दिशा में"));

      standards.setLanguage(AppLanguage.ja);
      expect(standards.formatClockDirection(2), equals("2時方向"));

      standards.setLanguage(AppLanguage.ar);
      expect(standards.formatClockDirection(2), equals("عند الساعة 2"));
    });

    test('International Emergency Dispatch Profiles across Global Jurisdictions', () {
      // US / Canada -> 911
      final usProfile = InternationalEmergencyProfile.fromCountryCode('US');
      expect(usProfile.emergencyNumber, equals('911'));

      // European Union / India -> 112
      final euProfile = InternationalEmergencyProfile.fromCountryCode('EU');
      expect(euProfile.emergencyNumber, equals('112'));

      final inProfile = InternationalEmergencyProfile.fromCountryCode('IN');
      expect(inProfile.emergencyNumber, equals('112'));

      // United Kingdom -> 999
      final ukProfile = InternationalEmergencyProfile.fromCountryCode('GB');
      expect(ukProfile.emergencyNumber, equals('999'));

      // Japan -> 119
      final jpProfile = InternationalEmergencyProfile.fromCountryCode('JP');
      expect(jpProfile.emergencyNumber, equals('119'));

      // Australia -> 000
      final auProfile = InternationalEmergencyProfile.fromCountryCode('AU');
      expect(auProfile.emergencyNumber, equals('000'));

      // Unknown Fallback -> 112 (GSM Global standard)
      final fallbackProfile = InternationalEmergencyProfile.fromCountryCode('XYZ');
      expect(fallbackProfile.emergencyNumber, equals('112'));
    });

    test('EmergencySosSentinelService integrates Global Emergency Profile', () {
      standards.setEmergencyCountry('GB'); // UK -> 999
      final sosService = EmergencySosSentinelService(globalStandards: standards);

      sosService.triggerManualSos();
      expect(sosService.currentState.status, equals(FallDetectionStatus.fallDetectedCountdown));

      sosService.cancelEmergency();
      expect(sosService.currentState.status, equals(FallDetectionStatus.cancelledByUser));
      sosService.dispose();
    });

    test('Expanded Global Currency Recognition (USD, EUR, GBP, INR, JPY, CAD, AUD)', () {
      final currencyService = CurrencyRecognitionService();

      // Test JPY (Japanese Yen)
      currencyService.setCurrency(CurrencyCode.jpy);
      final jpyNotes = BanknoteDenomination.supportedBanknotes
          .where((n) => n.currency == CurrencyCode.jpy)
          .toList();
      expect(jpyNotes.length, equals(3));
      expect(jpyNotes.any((n) => n.value == 1000), isTrue);

      // Test CAD (Canadian Dollar)
      currencyService.setCurrency(CurrencyCode.cad);
      final cadNotes = BanknoteDenomination.supportedBanknotes
          .where((n) => n.currency == CurrencyCode.cad)
          .toList();
      expect(cadNotes.length, equals(3));

      // Test AUD (Australian Dollar)
      currencyService.setCurrency(CurrencyCode.aud);
      final audNotes = BanknoteDenomination.supportedBanknotes
          .where((n) => n.currency == CurrencyCode.aud)
          .toList();
      expect(audNotes.length, equals(3));

      currencyService.dispose();
    });

    test('Zero-Cloud Privacy & GDPR Compliance Validation', () {
      expect(standards.verifyDataSovereigntyCompliance(), isTrue);
    });
  });
}

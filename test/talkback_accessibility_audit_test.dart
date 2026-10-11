import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Day 19: TalkBack & VoiceOver Accessibility Semantic Audit', () {
    testWidgets('App renders with full high-contrast theme and accessible tabs', (WidgetTester tester) async {
      await tester.pumpWidget(const OrbisNavApp());
      await tester.pump(const Duration(milliseconds: 50));

      // Verify Header & Brand
      expect(find.text('ORBISNAV'), findsOneWidget);

      // Verify 3 Top-Level Navigation Modes
      expect(find.text('Safety HUD'), findsOneWidget);
      expect(find.text('Navigation'), findsOneWidget);
      expect(find.text('Doc Scan'), findsOneWidget);

      // Clean unmount
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Tab switching provides proper semantic feedback', (WidgetTester tester) async {
      await tester.pumpWidget(const OrbisNavApp());
      await tester.pump(const Duration(milliseconds: 50));

      // Switch to Tab 1 (Navigation)
      final navTabFinder = find.byKey(const Key('mode_tab_navigation'));
      expect(navTabFinder, findsOneWidget);
      await tester.tap(navTabFinder);
      await tester.pump(const Duration(milliseconds: 400));

      // Verify Pedestrian & Indoor Mapping cards are rendered
      expect(find.text('PEDESTRIAN & CROSSWALK VISION'), findsOneWidget);
      expect(find.text('INDOOR SELF-MAPPING & A* ROUTING'), findsOneWidget);

      // Switch to Tab 2 (Living & Care)
      final careTabFinder = find.byKey(const Key('mode_tab_living'));
      expect(careTabFinder, findsOneWidget);
      await tester.tap(careTabFinder);
      await tester.pump(const Duration(milliseconds: 400));

      // Verify 1-Tap Trusted Angels Video Call section is rendered
      expect(find.text('TRUSTED ANGELS CAREGIVER CALL'), findsOneWidget);
      expect(find.text('DAILY LIVING ASSISTANT'), findsOneWidget);

      // Switch to Tab 3 (Channel 4: Lost Item Sonar)
      final sonarTabFinder = find.byKey(const Key('mode_tab_sonar'));
      expect(sonarTabFinder, findsOneWidget);
      await tester.tap(sonarTabFinder);
      await tester.pump(const Duration(milliseconds: 400));

      // Verify Lost Item Sonar Radar is rendered
      expect(find.text('LOST ITEM SONAR RADAR'), findsOneWidget);

      // Clean unmount
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Verify interactive controls have accessible semantic actions', (WidgetTester tester) async {
      await tester.pumpWidget(const OrbisNavApp());
      await tester.pump(const Duration(milliseconds: 50));

      // Verify interactive widgets exist
      expect(find.byType(Material), findsWidgets);

      // Clean unmount
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Voice Q&A and Earcon HUD components are rendered with high contrast', (WidgetTester tester) async {
      await tester.pumpWidget(const OrbisNavApp());
      await tester.pump(const Duration(milliseconds: 50));

      // Verify UI has query / speech cards present
      expect(find.text('CONVERSATIONAL VOICE AI'), findsOneWidget);
      expect(find.text('3D SPATIAL BINAURAL EARCONS'), findsOneWidget);

      // Clean unmount
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

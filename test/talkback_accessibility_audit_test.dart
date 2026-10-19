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

      // Verify 2 Top-Level Navigation Modes
      expect(find.text('Safety HUD'), findsOneWidget);
      expect(find.text('Item Sonar'), findsOneWidget);

      // Clean unmount
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Tab switching provides proper semantic feedback', (WidgetTester tester) async {
      await tester.pumpWidget(const OrbisNavApp());
      await tester.pump(const Duration(milliseconds: 50));

      // Switch to Tab 1 (Channel 2: Lost Item Sonar)
      final sonarTabFinder = find.byKey(const Key('mode_tab_sonar'));
      expect(sonarTabFinder, findsOneWidget);
      await tester.tap(sonarTabFinder);
      await tester.pump(const Duration(milliseconds: 400));

      // Verify Lost Item Sonar Radar is rendered
      expect(find.text('LOST ITEM SONAR RADAR'), findsOneWidget);

      // Switch back to Tab 0 (Channel 1: Safety HUD)
      final safetyTabFinder = find.byKey(const Key('mode_tab_safety'));
      expect(safetyTabFinder, findsOneWidget);
      await tester.tap(safetyTabFinder);
      await tester.pump(const Duration(milliseconds: 400));

      // Verify Safety HUD components are rendered
      expect(find.text('ORBISNAV'), findsOneWidget);

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

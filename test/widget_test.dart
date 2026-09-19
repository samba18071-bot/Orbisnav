import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/main.dart';

void main() {
  testWidgets('OrbisNavApp renders HUD dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(const OrbisNavApp());
    expect(find.text('ORBISNAV'), findsOneWidget);
  });
}

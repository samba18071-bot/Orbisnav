import 'package:flutter_test/flutter_test.dart';
import 'package:orbisnav/main.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'helpers/mock_webview_platform.dart';

void main() {
  setUpAll(() {
    WebViewPlatform.instance = MockWebViewPlatform();
  });

  testWidgets('OrbisNavApp renders HUD dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(const OrbisNavApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ORBISNAV'), findsOneWidget);
  });
}

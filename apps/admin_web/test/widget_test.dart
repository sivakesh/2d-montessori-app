import 'package:admin_web/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AdminWebApp renders the Phase 0 placeholder shell', (
    WidgetTester tester,
  ) async {
    // See apps/public_web/test/widget_test.dart for why this pumps the
    // widget directly instead of calling main().
    await tester.pumpWidget(const AdminWebApp());

    expect(find.textContaining('admin_web scaffold'), findsOneWidget);
  });
}

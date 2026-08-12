import 'package:flutter_test/flutter_test.dart';
import 'package:public_web/main.dart';

void main() {
  testWidgets('PublicWebApp renders the Phase 0 placeholder shell', (
    WidgetTester tester,
  ) async {
    // Pumps the widget tree directly (not main()) so this test never
    // touches Firebase — bootstrapFirebase() requires platform channels
    // that aren't available under `flutter test` without additional
    // mocking, which is out of scope for a Phase 0 smoke test.
    await tester.pumpWidget(const PublicWebApp());

    expect(find.textContaining('public_web scaffold'), findsOneWidget);
  });
}

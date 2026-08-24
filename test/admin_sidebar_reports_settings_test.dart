// Regression coverage for adding Reports and Settings to the desktop Admin
// sidebar, below Login Logs, reusing the same "coming soon" placeholder
// behavior the mobile "More Modules" sheet already uses for these two items
// (neither has a real screen yet).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:montessori_app/modules/admin/ui/admin_layout.dart';
import 'package:montessori_app/modules/admin/ui/admin_sidebar.dart';

void main() {
  Future<void> pumpDesktopLayout(
    WidgetTester tester, {
    int selectedIndex = 9,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: AdminLayout(
            selectedIndex: selectedIndex,
            title: 'Login Logs',
            body: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Admin desktop sidebar — Reports & Settings', () {
    testWidgets('shows Reports and Settings below Login Logs', (
      tester,
    ) async {
      await pumpDesktopLayout(tester);

      expect(find.byType(AdminSidebar), findsOneWidget);

      final labels = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(AdminSidebar),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data)
          .toList();

      final loginLogsIndex = labels.indexOf('Login Logs');
      final reportsIndex = labels.indexOf('Reports');
      final settingsIndex = labels.indexOf('Settings');

      expect(loginLogsIndex, greaterThanOrEqualTo(0));
      expect(reportsIndex, greaterThan(loginLogsIndex));
      expect(settingsIndex, greaterThan(reportsIndex));
    });

    testWidgets(
      'tapping Reports shows a coming-soon snackbar and does not navigate',
      (tester) async {
        await pumpDesktopLayout(tester);

        await tester.ensureVisible(find.text('Reports'));
        await tester.tap(find.text('Reports'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Reports is coming soon'), findsOneWidget);
        expect(find.byType(AdminSidebar), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'tapping Settings shows a coming-soon snackbar and does not navigate',
      (tester) async {
        await pumpDesktopLayout(tester);

        await tester.ensureVisible(find.text('Settings'));
        await tester.tap(find.text('Settings'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Settings is coming soon'), findsOneWidget);
        expect(find.byType(AdminSidebar), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'active-state styling highlights the current destination, not Reports/Settings',
      (tester) async {
        await pumpDesktopLayout(tester, selectedIndex: 9);

        final loginLogsText = tester.widget<Text>(
          find.descendant(
            of: find.byType(AdminSidebar),
            matching: find.text('Login Logs'),
          ),
        );
        final reportsText = tester.widget<Text>(
          find.descendant(
            of: find.byType(AdminSidebar),
            matching: find.text('Reports'),
          ),
        );

        expect(loginLogsText.style?.fontWeight, FontWeight.w600);
        expect(loginLogsText.style?.color, Colors.white);
        expect(reportsText.style?.fontWeight, FontWeight.w500);
        expect(reportsText.style?.color, Colors.black87);
      },
    );
  });
}

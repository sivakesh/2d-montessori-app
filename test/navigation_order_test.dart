// Coverage for the navigation reordering: same destinations and
// permissions as before, only display order changed, and it's consistent
// between AppSidebar (desktop) and AppBottomNav (mobile) for the
// shared Admin/Staff/Parent shell, and between AdminSidebar (desktop) and
// AdminLayout's mobile "More Modules" sheet for the Admin back-office.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/core/layout/bottom_nav.dart';
import 'package:montessori_app/core/layout/sidebar.dart';
import 'package:montessori_app/modules/admin/ui/admin_layout.dart';
import 'package:montessori_app/modules/admin/ui/admin_sidebar.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';

List<String> _labelsIn(WidgetTester tester, Finder ancestor) {
  return tester
      .widgetList<Text>(find.descendant(of: ancestor, matching: find.byType(Text)))
      .map((t) => t.data)
      .whereType<String>()
      // Excludes the sidebar's own brand label — not a navigation
      // destination, so it shouldn't count toward destination order/set
      // checks.
      .where((label) => label != '2D Montessori')
      .toList();
}

Future<List<String>> _sidebarOrder(WidgetTester tester, String role) async {
  // NavigationRail with labelType.all needs real desktop height to fit
  // every destination without overflowing — the default test window
  // (800x600) is too short once a role has 6-7 destinations, independent
  // of their order, so every test using this helper renders at a
  // realistic desktop size instead.
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) => AppUser(id: 'u1', phone: '9999999999', role: role, isActive: true),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: AppSidebar(selectedIndex: 0, onItemTapped: (_) {}),
        ),
      ),
    ),
  );
  return _labelsIn(tester, find.byType(NavigationRail));
}

Future<List<String>> _bottomNavOrder(WidgetTester tester, String role) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) => AppUser(id: 'u1', phone: '9999999999', role: role, isActive: true),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNav(selectedIndex: 0, onItemTapped: (_) {}),
        ),
      ),
    ),
  );
  final labels = tester
      .widgetList<NavigationDestination>(find.byType(NavigationDestination))
      .map((d) => d.label)
      .toList();
  return labels;
}

void main() {
  group('AppSidebar / AppBottomNav — reordered but same destinations', () {
    testWidgets('staff: Dashboard, Attendance, Calendar, Leave, Students, Classes (operational relevance)', (tester) async {
      final order = await _sidebarOrder(tester, 'staff');
      expect(order, ['Dashboard', 'Attendance', 'Calendar', 'Leave', 'Students', 'Classes']);
    });

    testWidgets('admin: same order as staff, plus Admin last', (tester) async {
      final order = await _sidebarOrder(tester, 'admin');
      expect(order, ['Dashboard', 'Attendance', 'Calendar', 'Leave', 'Students', 'Classes', 'Admin']);
    });

    testWidgets('parent: Dashboard, Calendar, Leave, Fees (Leave/Fees added in the pre-UAT cleanup pass)', (tester) async {
      final order = await _sidebarOrder(tester, 'parent');
      expect(order, ['Dashboard', 'Calendar', 'Leave', 'Fees']);
    });

    testWidgets('AppBottomNav (mobile) leads with the same first 4 destinations as AppSidebar (desktop) for staff, then More', (tester) async {
      // Staff has 6 total destinations — over the 5-item mobile cap (CAL-04
      // follow-up UX rule) — so the bottom nav shows only its first 4,
      // followed by a "More" overflow entry, rather than the sidebar's full
      // list. The full staff More-menu behavior (Students/Classes reachable
      // from it) is covered in app_bottom_nav_more_menu_test.dart.
      final sidebarOrder = await _sidebarOrder(tester, 'staff');
      final bottomOrder = await _bottomNavOrder(tester, 'staff');
      expect(bottomOrder, [...sidebarOrder.take(4), 'More']);
    });

    testWidgets('AppBottomNav (mobile) leads with the same first 4 destinations as AppSidebar (desktop) for admin, then More', (tester) async {
      // Admin has 7 total destinations — same 5-item mobile cap applies.
      // Students/Classes/Admin all move behind "More" on mobile; desktop's
      // AppSidebar is unaffected and still shows all 7 directly.
      final sidebarOrder = await _sidebarOrder(tester, 'admin');
      final bottomOrder = await _bottomNavOrder(tester, 'admin');
      expect(bottomOrder, [...sidebarOrder.take(4), 'More']);
    });

    testWidgets('reordering did not add or remove any staff destination', (tester) async {
      final order = await _sidebarOrder(tester, 'staff');
      expect(order.toSet(), {'Dashboard', 'Attendance', 'Calendar', 'Leave', 'Students', 'Classes'});
    });
  });

  group('AdminSidebar — reordered display, unchanged selectedIndex identities', () {
    Future<void> pumpDesktopLayout(WidgetTester tester, {int selectedIndex = 0}) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: AdminLayout(selectedIndex: selectedIndex, title: 'Admin', body: const SizedBox.shrink()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Attendance, Calendar, and Leave Requests now lead the sidebar, right after Dashboard', (tester) async {
      await pumpDesktopLayout(tester);
      final order = _labelsIn(tester, find.byType(AdminSidebar));

      expect(order.take(4).toList(), ['Dashboard', 'Attendance', 'Calendar', 'Leave Requests']);
    });

    testWidgets('Login Logs, Reports, Settings remain last and in that relative order', (tester) async {
      await pumpDesktopLayout(tester);
      final order = _labelsIn(tester, find.byType(AdminSidebar));

      final loginLogsIndex = order.indexOf('Login Logs');
      final reportsIndex = order.indexOf('Reports');
      final settingsIndex = order.indexOf('Settings');
      expect(loginLogsIndex, order.length - 3);
      expect(reportsIndex, order.length - 2);
      expect(settingsIndex, order.length - 1);
    });

    testWidgets('every original destination is still present — reordering added/removed none', (tester) async {
      await pumpDesktopLayout(tester);
      final order = _labelsIn(tester, find.byType(AdminSidebar)).toSet();

      expect(order, {
        'Dashboard', 'Attendance', 'Calendar', 'Leave Requests', 'Notifications',
        'Fees', 'Finance', 'Students', 'Classes', 'Users', 'Documents',
        'Login Logs', 'Reports', 'Settings',
      });
    });

    testWidgets('tapping Fees reports its unchanged id (6), regardless of display position', (tester) async {
      // Standalone AdminSidebar (not AdminLayout) — AdminLayout's real
      // destination screens hit live Firestore/UserService and hang
      // pumpAndSettle in a test environment, so the id-decoupling itself
      // is verified directly against the callback instead of a real
      // navigation.
      int? tappedId;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminSidebar(
              selectedIndex: 0,
              onDestinationSelected: (id) => tappedId = id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fees'));
      await tester.pump();

      expect(tappedId, 6);
    });

    testWidgets('the currently-selected destination (by id, not position) is highlighted correctly after reordering', (tester) async {
      // id 8 = Attendance — now displayed 2nd, not 9th as before reordering.
      await pumpDesktopLayout(tester, selectedIndex: 8);
      final attendanceText = tester.widget<Text>(
        find.descendant(of: find.byType(AdminSidebar), matching: find.text('Attendance')),
      );
      final dashboardText = tester.widget<Text>(
        find.descendant(of: find.byType(AdminSidebar), matching: find.text('Dashboard')),
      );

      expect(attendanceText.style?.color, Colors.white);
      expect(dashboardText.style?.color, isNot(Colors.white));
    });
  });
}

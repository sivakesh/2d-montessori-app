// Coverage for the mobile "More" overflow UX rule (CAL-04 follow-up):
// AppBottomNav must never show more than 5 items on mobile. Roles with more
// than 5 destinations (Staff: 6, Admin: 7) get their first 4 plus a "More"
// entry; the rest live in a bottom sheet reachable from "More". AppSidebar
// (desktop) is untouched — every destination still renders directly there,
// verified below alongside the mobile behavior.
//
// These tests exercise the real AppBottomNav widget directly (not a
// reimplementation), passing selectedIndex/onItemTapped exactly as
// DashboardScreen/ParentDashboard already do, so a regression in the real
// index mapping — the same class of bug a previously duplicated Staff
// label/body mapping once caused — would be caught here.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/core/layout/bottom_nav.dart';
import 'package:montessori_app/core/layout/sidebar.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';

Widget _bottomNavHarness(String role, {required int selectedIndex, required void Function(int) onItemTapped}) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => AppUser(id: 'u1', phone: '9999999999', role: role, isActive: true),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        bottomNavigationBar: AppBottomNav(
          selectedIndex: selectedIndex,
          onItemTapped: onItemTapped,
        ),
      ),
    ),
  );
}

Future<void> _openMore(WidgetTester tester) async {
  await tester.tap(find.text('More'));
  await tester.pumpAndSettle();
}

/// Tapping the Admin entry inside More pushes the real AdminDashboardScreen,
/// which reaches for a real Firebase singleton outside this test's control
/// (same as the other navigation tests in this suite deal with via their
/// own identical drain helper) — expected and unrelated to the "did we
/// route correctly, without touching onItemTapped" behavior under test.
void _drainExpectedFirebaseSingletonErrors(WidgetTester tester) {
  for (var i = 0; i < 10; i++) {
    if (tester.takeException() == null) return;
  }
}

void main() {
  group('Admin — mobile bottom nav caps at 5 items with Students/Classes/Admin in More', () {
    testWidgets('exactly 5 visible bottom-nav items, with the right primary 4 plus More', (tester) async {
      var tapped = -1;
      await tester.pumpWidget(_bottomNavHarness('admin', selectedIndex: 0, onItemTapped: (i) => tapped = i));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationDestination), findsNWidgets(5));
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Attendance'), findsOneWidget);
      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Leave'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      expect(find.text('Students'), findsNothing);
      expect(find.text('Classes'), findsNothing);
      expect(find.text('Admin'), findsNothing);
      expect(tapped, -1); // nothing tapped yet — just confirming the bar itself
    });

    testWidgets('tapping More opens a sheet with Students, Classes, and Admin', (tester) async {
      await tester.pumpWidget(_bottomNavHarness('admin', selectedIndex: 0, onItemTapped: (_) {}));
      await tester.pumpAndSettle();

      await _openMore(tester);

      expect(find.text('Students'), findsOneWidget);
      expect(find.text('Classes'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
    });

    testWidgets('Students from More navigates correctly and closes the sheet', (tester) async {
      int? tapped;
      await tester.pumpWidget(_bottomNavHarness('admin', selectedIndex: 0, onItemTapped: (i) => tapped = i));
      await tester.pumpAndSettle();

      await _openMore(tester);
      await tester.tap(find.text('Students'));
      await tester.pumpAndSettle();

      // Sheet closed (its own "Classes"/"Admin" rows no longer present).
      expect(find.text('Classes'), findsNothing);
      // Students is index 4 in AppBottomNav's entries — Dashboard(0),
      // Attendance(1), Calendar(2), Leave(3), Students(4) — the same index
      // DashboardScreen's `tabs` list already expects for Students.
      expect(tapped, 4);
    });

    testWidgets('Classes from More navigates correctly and closes the sheet', (tester) async {
      int? tapped;
      await tester.pumpWidget(_bottomNavHarness('admin', selectedIndex: 0, onItemTapped: (i) => tapped = i));
      await tester.pumpAndSettle();

      await _openMore(tester);
      await tester.tap(find.text('Classes'));
      await tester.pumpAndSettle();

      expect(find.text('Students'), findsNothing);
      expect(tapped, 5);
    });

    testWidgets('Admin from More opens the Admin back-office (not onItemTapped) and closes the sheet', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_bottomNavHarness('admin', selectedIndex: 0, onItemTapped: (_) => tapped = true));
      await tester.pumpAndSettle();

      await _openMore(tester);
      await tester.tap(find.text('Admin'));
      await tester.pumpAndSettle();
      _drainExpectedFirebaseSingletonErrors(tester);

      // The sheet is gone (route pushed on top, first frame of the push at
      // least starts) and onItemTapped was never called for the Admin
      // entry — same "push AdminDashboard, don't touch selectedIndex"
      // contract as before this destination moved into More.
      expect(find.text('Students'), findsNothing);
      expect(tapped, isFalse);
    });

    testWidgets('More visually indicates selection when the active destination lives inside More (Students)', (tester) async {
      await tester.pumpWidget(_bottomNavHarness('admin', selectedIndex: 4, onItemTapped: (_) {}));
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      // Primary bar has 5 destinations (index 4 = "More"); selectedIndex 4
      // in the underlying entries (Students) must show as the More slot
      // selected — never swapped for one of the 4 primary items' own icon.
      expect(navBar.selectedIndex, 4);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Attendance'), findsOneWidget);
      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Leave'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
    });

    testWidgets('the currently-active More destination is marked selected inside the sheet itself', (tester) async {
      await tester.pumpWidget(_bottomNavHarness('admin', selectedIndex: 5, onItemTapped: (_) {})); // Classes active
      await tester.pumpAndSettle();

      await _openMore(tester);

      final classesTile = tester.widget<ListTile>(
        find.ancestor(of: find.text('Classes'), matching: find.byType(ListTile)),
      );
      final studentsTile = tester.widget<ListTile>(
        find.ancestor(of: find.text('Students'), matching: find.byType(ListTile)),
      );
      expect(classesTile.trailing, isNotNull); // selected check mark present
      expect(studentsTile.trailing, isNull);
    });
  });

  group('Staff — mobile bottom nav caps at 5 items with Students/Classes in More, no Admin', () {
    testWidgets('exactly 5 visible items: Dashboard, Attendance, Calendar, Leave, More', (tester) async {
      await tester.pumpWidget(_bottomNavHarness('staff', selectedIndex: 0, onItemTapped: (_) {}));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationDestination), findsNWidgets(5));
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Attendance'), findsOneWidget);
      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Leave'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
    });

    testWidgets('Students and Classes are reachable through More, and Admin is never offered to Staff', (tester) async {
      await tester.pumpWidget(_bottomNavHarness('staff', selectedIndex: 0, onItemTapped: (_) {}));
      await tester.pumpAndSettle();

      await _openMore(tester);

      expect(find.text('Students'), findsOneWidget);
      expect(find.text('Classes'), findsOneWidget);
      expect(find.text('Admin'), findsNothing);
    });

    testWidgets('selecting Students from More for Staff reports the correct index', (tester) async {
      int? tapped;
      await tester.pumpWidget(_bottomNavHarness('staff', selectedIndex: 0, onItemTapped: (i) => tapped = i));
      await tester.pumpAndSettle();

      await _openMore(tester);
      await tester.tap(find.text('Students'));
      await tester.pumpAndSettle();

      expect(tapped, 4);
    });
  });

  group('Parent — primary destinations unaffected, no More, no Staff/Admin leakage', () {
    testWidgets('exactly the 4 role-specific primary destinations, no More entry', (tester) async {
      await tester.pumpWidget(_bottomNavHarness('parent', selectedIndex: 0, onItemTapped: (_) {}));
      await tester.pumpAndSettle();

      final labels = tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((d) => d.label)
          .toList();
      expect(labels, ['Dashboard', 'Calendar', 'Leave', 'Fees']);
      expect(find.text('More'), findsNothing);
    });

    testWidgets('Fees remains directly accessible (no overflow needed for Parent)', (tester) async {
      int? tapped;
      await tester.pumpWidget(_bottomNavHarness('parent', selectedIndex: 0, onItemTapped: (i) => tapped = i));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fees'));
      await tester.pumpAndSettle();

      expect(tapped, 3);
    });

    testWidgets('Parent has no More menu to open, so Staff/Admin destinations are never exposed', (tester) async {
      await tester.pumpWidget(_bottomNavHarness('parent', selectedIndex: 0, onItemTapped: (_) {}));
      await tester.pumpAndSettle();

      // No "More" affordance exists at all for Parent — nothing to tap, and
      // none of Staff/Admin's destinations are present anywhere on screen.
      expect(find.text('More'), findsNothing);
      expect(find.text('Attendance'), findsNothing);
      expect(find.text('Students'), findsNothing);
      expect(find.text('Classes'), findsNothing);
      expect(find.text('Admin'), findsNothing);
    });
  });

  group('More sheet mechanics', () {
    testWidgets('More opens and can be dismissed without navigating (closes correctly)', (tester) async {
      var tapped = -1;
      await tester.pumpWidget(_bottomNavHarness('admin', selectedIndex: 0, onItemTapped: (i) => tapped = i));
      await tester.pumpAndSettle();

      await _openMore(tester);
      expect(find.text('Students'), findsOneWidget);

      // Dismiss via drag-down equivalent: tap the barrier / pop the route.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.text('Students'), findsNothing);
      expect(tapped, -1);
    });

    testWidgets('switching between primary destinations still works after using More', (tester) async {
      final tappedIndexes = <int>[];
      await tester.pumpWidget(_bottomNavHarness('admin', selectedIndex: 0, onItemTapped: tappedIndexes.add));
      await tester.pumpAndSettle();

      await _openMore(tester);
      await tester.tap(find.text('Classes'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Attendance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Calendar'));
      await tester.pumpAndSettle();

      expect(tappedIndexes, [5, 1, 2]);
    });
  });

  group('Desktop AppSidebar is unaffected by the mobile More rule', () {
    testWidgets('Admin sidebar still shows all 7 destinations directly, no More', (tester) async {
      // NavigationRail with labelType.all needs real desktop height to fit
      // 7 destinations without overflowing — the default test window
      // (800x600) is too short, independent of anything under test here.
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith(
              (ref) => AppUser(id: 'u1', phone: '9999999999', role: 'admin', isActive: true),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(body: AppSidebar(selectedIndex: 0, onItemTapped: (_) {})),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      final labels = rail.destinations.map((d) => (d.label as Text).data).toList();
      expect(labels, ['Dashboard', 'Attendance', 'Calendar', 'Leave', 'Students', 'Classes', 'Admin']);
      expect(find.text('More'), findsNothing);
    });
  });

  group('Responsive — no bottom nav overflow at narrow mobile widths', () {
    const widths = <String, Size>{
      '390x844': Size(390, 844),
      '400x775': Size(400, 775),
      '412x915': Size(412, 915),
    };

    for (final entry in widths.entries) {
      testWidgets('${entry.key}: Admin bottom nav (5 items incl. More) has no overflow', (tester) async {
        final originalSize = tester.view.physicalSize;
        final originalDpr = tester.view.devicePixelRatio;
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.physicalSize = originalSize;
          tester.view.devicePixelRatio = originalDpr;
        });

        await tester.pumpWidget(_bottomNavHarness('admin', selectedIndex: 0, onItemTapped: (_) {}));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('More'), findsOneWidget);

        await _openMore(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Admin'), findsOneWidget);
      });
    }
  });
}

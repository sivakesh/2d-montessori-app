// Regression coverage for the AppBottomNav crash fix: Material's
// NavigationBar hard-asserts destinations.length >= 2, which a
// single-destination role (previously only Parent, before the School
// Calendar feature gave Parent a second "Calendar" destination) violated.
// The single-destination fallback widget (_SingleDestinationNavBar) is kept
// in bottom_nav.dart as defensive code for any future role that ends up
// with exactly one destination, but no live role exercises it today — Parent
// now has 2 destinations (Dashboard, Calendar) and uses the real
// NavigationBar like every other role, which is what this file now verifies.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/core/layout/bottom_nav.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';

Future<void> _pumpAppBottomNav(WidgetTester tester, String role) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) => AppUser(
            id: 'u1',
            phone: '9999999999',
            role: role,
            isActive: true,
          ),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNav(
            selectedIndex: 0,
            onItemTapped: (_) {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'parent (Dashboard + Calendar) renders the real NavigationBar without the length>=2 assertion firing',
    (tester) async {
      await _pumpAppBottomNav(tester, 'parent');

      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Calendar'), findsOneWidget);
    },
  );

  testWidgets('staff (multiple destinations) still uses the real NavigationBar', (
    tester,
  ) async {
    await _pumpAppBottomNav(tester, 'staff');

    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Attendance'), findsOneWidget);
    // Staff has 6 total destinations, over the 5-item mobile cap, so
    // Classes now lives behind "More" rather than directly on the bar —
    // see app_bottom_nav_more_menu_test.dart for the full CAL-04-style
    // overflow coverage.
    expect(find.text('Classes'), findsNothing);
    expect(find.text('More'), findsOneWidget);
  });

  testWidgets('admin (multiple destinations, including Admin) still uses the real NavigationBar', (
    tester,
  ) async {
    await _pumpAppBottomNav(tester, 'admin');

    expect(tester.takeException(), isNull);
    expect(find.byType(NavigationBar), findsOneWidget);
    // Admin has 7 total destinations, over the 5-item mobile cap, so Admin
    // now lives behind "More" rather than directly on the bar — see
    // app_bottom_nav_more_menu_test.dart for the full overflow coverage.
    expect(find.text('Admin'), findsNothing);
    expect(find.text('More'), findsOneWidget);
  });

  group('parent nav bar at required mobile widths', () {
    // 400x775 is the exact size the NavigationBar assertion crash was
    // reproduced at; the others are the standard breakpoints this app is
    // expected to support.
    const widths = <String, Size>{
      '390x844': Size(390, 844),
      '400x775 (crash repro size)': Size(400, 775),
      '412x915': Size(412, 915),
      '768x1024': Size(768, 1024),
    };

    for (final entry in widths.entries) {
      testWidgets('${entry.key}: no crash, no overflow, bottom nav visible', (
        tester,
      ) async {
        final originalSize = tester.view.physicalSize;
        final originalDpr = tester.view.devicePixelRatio;
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.physicalSize = originalSize;
          tester.view.devicePixelRatio = originalDpr;
        });

        await _pumpAppBottomNav(tester, 'parent');

        expect(tester.takeException(), isNull);
        expect(find.text('Dashboard'), findsOneWidget);
      });
    }
  });
}

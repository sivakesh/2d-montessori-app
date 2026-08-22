// Regression coverage for the new navigation logic introduced to fix Parent
// Notifications bypassing the shared shell: NotificationsFeedScreen's
// showOwnScaffold branch, and ParentNotificationsScreen's shell + "tap
// Dashboard to go back" wiring. Does not touch notification data loading
// logic (already covered by notification_relevance_test.dart and
// admin_notification_service_audience_test.dart) — a Firestore fetch
// failure here is expected and handled by the existing error state, so no
// Firebase setup is needed for these widget-tree assertions.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/notifications/ui/notifications_feed_screen.dart';
import 'package:montessori_app/modules/parent/ui/parent_notifications_screen.dart';

ProviderScope _withParentUser(Widget child) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => AppUser(id: 'p1', phone: '9999999999', role: 'parent', isActive: true),
      ),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets(
    'showOwnScaffold: true (Staff\'s unchanged default) still renders its own Scaffold/AppBar',
    (tester) async {
      await tester.pumpWidget(
        _withParentUser(
          const NotificationsFeedScreen.forStaff(
            title: 'Notifications',
            staffUserId: 's1',
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    },
  );

  testWidgets(
    'showOwnScaffold: false renders only body content, letting a host Scaffold own the AppBar',
    (tester) async {
      await tester.pumpWidget(
        _withParentUser(
          Scaffold(
            appBar: AppBar(title: const Text('Host')),
            body: const NotificationsFeedScreen.forParent(
              title: 'Notifications',
              childStudentIds: {},
              childClassIds: {},
              showOwnScaffold: false,
            ),
          ),
        ),
      );
      await tester.pump();

      // Exactly one AppBar (the host's) — the embedded feed did not add a
      // second, competing one.
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Host'), findsOneWidget);
    },
  );

  testWidgets(
    'ParentNotificationsScreen at mobile width: no NavigationBar assertion, shell shows Dashboard + Notifications title',
    (tester) async {
      final originalSize = tester.view.physicalSize;
      final originalDpr = tester.view.devicePixelRatio;
      tester.view.physicalSize = const Size(400, 775); // the exact crash-repro size
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.physicalSize = originalSize;
        tester.view.devicePixelRatio = originalDpr;
      });

      await tester.pumpWidget(
        _withParentUser(
          const ParentNotificationsScreen(childStudentIds: {}, childClassIds: {}),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Notifications'), findsOneWidget); // AppBar title
      expect(find.text('Dashboard'), findsOneWidget); // single nav destination
    },
  );

  testWidgets(
    'tapping the shell\'s Dashboard destination pops back to whatever pushed this screen',
    (tester) async {
      await tester.pumpWidget(
        _withParentUser(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ParentNotificationsScreen(
                        childStudentIds: {},
                        childClassIds: {},
                      ),
                    ),
                  ),
                  child: const Text('Fake Dashboard'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Fake Dashboard'));
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);

      // Tap the single "Dashboard" destination in the bottom nav.
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();

      expect(find.text('Fake Dashboard'), findsOneWidget);
      expect(find.text('Notifications'), findsNothing);
    },
  );
}

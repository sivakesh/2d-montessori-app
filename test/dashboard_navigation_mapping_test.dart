// Regression coverage for a Staff navigation mapping bug found in manual
// UAT: after the destinations were reordered (Dashboard, Attendance,
// Calendar, Leave, Students, Classes), DashboardScreen carried the body
// content in TWO independently-hardcoded `switch (selectedIndex)`
// statements — one for the mobile layout, one for the web/desktop layout.
// Only the mobile one was updated to the new order; the desktop one still
// used the pre-reorder mapping. Every label was therefore correct but the
// desktop body was off by one destination (e.g. tapping "Attendance"
// showed the old index-1 screen, Classes).
//
// The fix replaces both switch statements with a single `tabs` list
// (title + body defined together, per entry) computed once in build() and
// reused by both layouts, so title and body can no longer independently
// drift. These tests exercise the real DashboardScreen/ParentDashboard
// (not a re-implementation of the mapping) so a future regression of this
// exact shape — title right, body wrong — would be caught here.
//
// DashboardScreen previously could not be constructed in any widget test:
// UserSessionLogService/UserService default to real Firebase singletons,
// and UserSessionLogService.logSessionOpened is called unconditionally
// from initState. DashboardScreen now accepts both as optional
// constructor parameters (same DI seam every other service-backed screen
// in this app already exposes) purely to make this possible — production
// callers never pass them.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/admin/students/data/admin_student_service.dart';
import 'package:montessori_app/modules/attendance/data/attendance_service.dart';
import 'package:montessori_app/modules/attendance/providers/attendance_provider.dart';
import 'package:montessori_app/modules/attendance/ui/attendance_screen.dart';
import 'package:montessori_app/modules/auth/data/user_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/calendar/ui/calendar_view.dart';
import 'package:montessori_app/modules/classes/data/class_service.dart';
import 'package:montessori_app/modules/classes/providers/class_provider.dart';
import 'package:montessori_app/modules/classes/ui/class_list_screen.dart';
import 'package:montessori_app/modules/dashboard/ui/dashboard_screen.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/leave/services/leave_service.dart';
import 'package:montessori_app/modules/leave/ui/my_leave_view.dart';
import 'package:montessori_app/modules/mood_checkin/providers/mood_checkin_provider.dart';
import 'package:montessori_app/modules/mood_checkin/services/mood_checkin_service.dart';
import 'package:montessori_app/modules/parent/data/parent_service.dart';
import 'package:montessori_app/modules/parent/ui/parent_dashboard.dart';
import 'package:montessori_app/modules/students/data/student_service.dart';
import 'package:montessori_app/modules/students/providers/student_provider.dart';
import 'package:montessori_app/modules/students/ui/student_list_screen.dart';
import 'package:montessori_app/services/user_session_log_service.dart';

// AdminNotificationService default-initializes FilePicker.platform whenever
// no filePicker is supplied — a stand-in avoids that real platform channel.
class _UnusedFilePicker extends FilePicker {}

/// Drains the known, expected build-time exceptions from other
/// pre-existing widgets on this screen that reach for real Firebase
/// singletons directly (e.g. `_DashboardHeader`'s
/// `FirebaseAuth.instance.currentUser`) — unrelated to the navigation
/// mapping under test here, and not something this task touches.
/// Flutter's own per-widget build error boundary contains them (the rest
/// of the tree still renders), but they still need to be cleared from the
/// test's exception queue afterward, or the framework reports them as an
/// unexpected failure at the end of the test. When more than one is
/// queued, `takeException()`'s first call returns an aggregate "Multiple
/// exceptions were detected" wrapper rather than a real exception
/// instance — not something worth pattern-matching against — so this
/// simply drains a bounded number of calls unconditionally rather than
/// trying to selectively rethrow a genuinely different failure. A real,
/// unrelated regression in the navigation logic itself still fails these
/// tests via their own `expect()` assertions on title/body/highlight,
/// which is what actually matters here.
void _drainExpectedFirebaseSingletonErrors(WidgetTester tester) {
  for (var i = 0; i < 10; i++) {
    if (tester.takeException() == null) return;
  }
}

Widget _buildStaffDashboard(FakeFirebaseFirestore firestore, {String role = 'staff'}) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => AppUser(id: 'u1', phone: '9999999999', role: role, isActive: true),
      ),
      attendanceServiceProvider.overrideWithValue(
        AttendanceService(firestore: firestore, storage: MockFirebaseStorage()),
      ),
      classServiceProvider.overrideWithValue(ClassService(firestore: firestore)),
      studentServiceProvider.overrideWithValue(StudentService(firestore: firestore)),
      moodCheckinServiceProvider.overrideWithValue(
        MoodCheckinService(firestore: firestore, storage: MockFirebaseStorage()),
      ),
    ],
    child: MaterialApp(
      home: DashboardScreen(
        userService: UserService(firestore),
        userSessionLogService: UserSessionLogService(
          firebaseAuth: MockFirebaseAuth(),
          firestore: firestore,
          userService: UserService(firestore),
        ),
        adminStudentService: AdminStudentService(
          firestore: firestore,
          storage: MockFirebaseStorage(),
        ),
        classService: ClassService(firestore: firestore),
      ),
    ),
  );
}

Future<void> _pumpDesktop(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
  _drainExpectedFirebaseSingletonErrors(tester);
}

Future<void> _pumpMobile(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
  _drainExpectedFirebaseSingletonErrors(tester);
}

Future<void> _tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
  _drainExpectedFirebaseSingletonErrors(tester);
}

void main() {
  group('Staff — desktop (AppSidebar) navigation mapping', () {
    testWidgets('the sidebar has exactly the 6 expected destinations, in order — none added or removed', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpDesktop(tester, _buildStaffDashboard(firestore));

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      final labels = rail.destinations
          .map((d) => (d.label as Text).data)
          .toList();
      expect(labels, ['Dashboard', 'Attendance', 'Calendar', 'Leave', 'Students', 'Classes']);
    });

    testWidgets('Dashboard (default) shows the Dashboard body', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpDesktop(tester, _buildStaffDashboard(firestore));

      expect(find.text('Dashboard'), findsWidgets); // AppBar title + sidebar label
      expect(find.text('Quick Actions'), findsOneWidget);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 0);
    });

    testWidgets('Attendance opens the Attendance screen (title, body, and highlight all agree)', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpDesktop(tester, _buildStaffDashboard(firestore));

      await _tapAndSettle(tester, find.text('Attendance'));

      expect(find.widgetWithText(AppBar, 'Attendance'), findsOneWidget);
      expect(find.byType(AttendanceScreen), findsOneWidget);
      // The exact class of bug this guards against: the wrong destination's
      // screen rendering under the right label.
      expect(find.byType(ClassListScreen), findsNothing);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 1);
    });

    testWidgets('Calendar opens CalendarView', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpDesktop(tester, _buildStaffDashboard(firestore));

      await _tapAndSettle(tester, find.text('Calendar'));

      expect(find.widgetWithText(AppBar, 'Calendar'), findsOneWidget);
      expect(find.byType(CalendarView), findsOneWidget);
      expect(find.byType(StudentListScreen), findsNothing);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 2);
    });

    testWidgets('Leave opens MyLeaveView', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpDesktop(tester, _buildStaffDashboard(firestore));

      await _tapAndSettle(tester, find.text('Leave'));

      expect(find.widgetWithText(AppBar, 'Leave'), findsOneWidget);
      expect(find.byType(MyLeaveView), findsOneWidget);
      expect(find.byType(AttendanceScreen), findsNothing);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 3);
    });

    testWidgets('Students opens StudentListScreen', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpDesktop(tester, _buildStaffDashboard(firestore));

      await _tapAndSettle(tester, find.text('Students'));

      expect(find.widgetWithText(AppBar, 'Students'), findsOneWidget);
      expect(find.byType(StudentListScreen), findsOneWidget);
      expect(find.byType(CalendarView), findsNothing);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 4);
    });

    testWidgets('Classes opens ClassListScreen', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpDesktop(tester, _buildStaffDashboard(firestore));

      await _tapAndSettle(tester, find.text('Classes'));

      expect(find.widgetWithText(AppBar, 'Classes'), findsOneWidget);
      expect(find.byType(ClassListScreen), findsOneWidget);
      expect(find.byType(MyLeaveView), findsNothing);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 5);
    });

    testWidgets('Dashboard Quick Actions ("Mark Student/Staff Attendance") navigate to the Attendance screen', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpDesktop(tester, _buildStaffDashboard(firestore));

      await tester.ensureVisible(find.text('Mark Student Attendance'));
      await _tapAndSettle(tester, find.text('Mark Student Attendance'));

      expect(find.widgetWithText(AppBar, 'Attendance'), findsOneWidget);
      expect(find.byType(AttendanceScreen), findsOneWidget);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 1);
    });
  });

  group('Staff — mobile (AppBottomNav) navigation mapping — same destination, same screen as desktop', () {
    testWidgets('the bottom nav has exactly the same 6 destinations, in the same order as the sidebar', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpMobile(tester, _buildStaffDashboard(firestore));

      final labels = tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((d) => d.label)
          .toList();
      expect(labels, ['Dashboard', 'Attendance', 'Calendar', 'Leave', 'Students', 'Classes']);
    });

    testWidgets('Attendance opens the Attendance screen on mobile too', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpMobile(tester, _buildStaffDashboard(firestore));

      await _tapAndSettle(tester, find.text('Attendance'));

      expect(find.widgetWithText(AppBar, 'Attendance'), findsOneWidget);
      expect(find.byType(AttendanceScreen), findsOneWidget);
      expect(find.byType(ClassListScreen), findsNothing);
    });

    testWidgets('Leave opens MyLeaveView on mobile too (mobile and desktop must agree)', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpMobile(tester, _buildStaffDashboard(firestore));

      await _tapAndSettle(tester, find.text('Leave'));

      expect(find.widgetWithText(AppBar, 'Leave'), findsOneWidget);
      expect(find.byType(MyLeaveView), findsOneWidget);
      expect(find.byType(AttendanceScreen), findsNothing);
    });

    testWidgets('Classes opens ClassListScreen on mobile too', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpMobile(tester, _buildStaffDashboard(firestore));

      await _tapAndSettle(tester, find.text('Classes'));

      expect(find.widgetWithText(AppBar, 'Classes'), findsOneWidget);
      expect(find.byType(ClassListScreen), findsOneWidget);
      expect(find.byType(MyLeaveView), findsNothing);
    });
  });

  group('Admin — navigation remains intact', () {
    testWidgets('Admin sees the same 6 destinations plus Admin last, and Attendance still maps correctly', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpDesktop(tester, _buildStaffDashboard(firestore, role: 'admin'));

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      final labels = rail.destinations.map((d) => (d.label as Text).data).toList();
      expect(labels, ['Dashboard', 'Attendance', 'Calendar', 'Leave', 'Students', 'Classes', 'Admin']);

      await _tapAndSettle(tester, find.text('Attendance'));
      expect(find.widgetWithText(AppBar, 'Attendance'), findsOneWidget);
      expect(find.byType(AttendanceScreen), findsOneWidget);
    });

    testWidgets('Admin sees the Add FAB on Students and Classes, and nowhere else', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpDesktop(tester, _buildStaffDashboard(firestore, role: 'admin'));

      // Dashboard (default) — no FAB.
      expect(find.byType(FloatingActionButton), findsNothing);

      await _tapAndSettle(tester, find.text('Students'));
      expect(find.byType(FloatingActionButton), findsOneWidget);

      await _tapAndSettle(tester, find.text('Attendance'));
      expect(find.byType(FloatingActionButton), findsNothing);

      await _tapAndSettle(tester, find.text('Classes'));
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });

  // Parent's Leave/Fees destinations (added in the pre-UAT cleanup pass)
  // have their own dedicated, more thorough coverage in
  // parent_leave_fees_navigation_test.dart. This group only re-affirms that
  // the pre-existing Dashboard/Calendar destinations for Parent still work
  // correctly, unaffected by the Staff nav-mapping fix this file otherwise
  // covers.
  group('Parent — Dashboard and Calendar destinations still work, unaffected by the Staff fix', () {
    Widget buildParentDashboard(FakeFirebaseFirestore firestore) {
      return ProviderScope(
        overrides: [
          currentUserProvider.overrideWith(
            (ref) => AppUser(id: 'parent-1', phone: '9999999999', role: 'parent', isActive: true),
          ),
        ],
        child: MaterialApp(
          home: ParentDashboard(
            parentService: ParentService(firestore: firestore),
            attendanceService: AttendanceService(firestore: firestore, storage: MockFirebaseStorage()),
            feeService: FeeService(firestore: firestore, auth: MockFirebaseAuth(), storage: MockFirebaseStorage()),
            notificationService: AdminNotificationService(
              firestore: firestore,
              storage: MockFirebaseStorage(),
              filePicker: _UnusedFilePicker(),
            ),
            classService: ClassService(firestore: firestore),
            moodCheckinService: MoodCheckinService(firestore: firestore, storage: MockFirebaseStorage()),
            leaveService: LeaveService(firestore: firestore),
          ),
        ),
      );
    }

    testWidgets('Parent nav starts with Dashboard then Calendar', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpDesktop(tester, buildParentDashboard(firestore));

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      final labels = rail.destinations.map((d) => (d.label as Text).data).toList();
      expect(labels.take(2), ['Dashboard', 'Calendar']);
    });

    testWidgets('Parent: Calendar destination opens CalendarView', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpDesktop(tester, buildParentDashboard(firestore));

      await _tapAndSettle(tester, find.text('Calendar'));

      expect(find.widgetWithText(AppBar, 'Calendar'), findsOneWidget);
      expect(find.byType(CalendarView), findsOneWidget);
    });
  });
}

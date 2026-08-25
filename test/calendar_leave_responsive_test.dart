// Responsive validation for the new School Calendar + Leave Requests
// screens at the required breakpoints (390x844, 400x775, 412x915, 768x1024,
// and a desktop width). Seeds items with deliberately long titles/reasons
// to exercise the maxLines/ellipsis handling on cards, and asserts no
// RenderFlex overflow and no uncaught exception at any size.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/calendar/services/calendar_service.dart';
import 'package:montessori_app/modules/calendar/ui/calendar_view.dart';
import 'package:montessori_app/modules/calendar/ui/dialogs/calendar_event_dialog.dart';
import 'package:montessori_app/modules/leave/services/leave_service.dart';
import 'package:montessori_app/modules/leave/ui/admin_leave_screen.dart';
import 'package:montessori_app/modules/leave/ui/dialogs/leave_request_dialog.dart';
import 'package:montessori_app/modules/leave/ui/dialogs/student_leave_request_dialog.dart';
import 'package:montessori_app/modules/leave/ui/my_leave_view.dart';

const _widths = <String, Size>{
  '390x844': Size(390, 844),
  '400x775': Size(400, 775),
  '412x915': Size(412, 915),
  '768x1024': Size(768, 1024),
  'desktop (1440x900)': Size(1440, 900),
};

Future<void> _atEachWidth(
  WidgetTester tester,
  Future<void> Function(WidgetTester tester) body,
) async {
  for (final entry in _widths.entries) {
    final originalSize = tester.view.physicalSize;
    final originalDpr = tester.view.devicePixelRatio;
    tester.view.physicalSize = entry.value;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.physicalSize = originalSize;
      tester.view.devicePixelRatio = originalDpr;
    });

    // FlutterError.onError catches RenderFlex overflow assertions, which
    // otherwise print to console rather than failing the test directly.
    // The restore MUST happen in a `finally` — if `body(tester)` throws
    // (e.g. an `expect` inside it fails) and the handler is never restored,
    // flutter_test's own binding later asserts on the stale override and
    // the whole file can hang until the 10-minute test timeout instead of
    // reporting the real failure.
    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details);

    try {
      await body(tester);
    } finally {
      FlutterError.onError = previousOnError;
    }
    expect(
      errors,
      isEmpty,
      reason: 'Overflow/render error at ${entry.key}: ${errors.map((e) => e.exceptionAsString()).join(', ')}',
    );
  }
}

ProviderScope _withRole(String role, Widget child) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => AppUser(id: 'u1', phone: '9999999999', role: role, isActive: true),
      ),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('CalendarView (Parent, long titles/locations) has no overflow at any required width', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = CalendarService(firestore: firestore);
    await service.createEvent({
      'title': 'Annual Sports Day and Prize Distribution Ceremony for All Classes',
      'date': DateTime(2026, 12, 5),
      'startTime': '09:00',
      'endTime': '13:00',
      'eventType': 'Event',
      'description':
          'A very long description that should wrap or ellipsize gracefully without pushing the card wider than the available screen width, even on the narrowest supported device.',
      'location': 'Main Ground, Behind the Administration Block and Cafeteria',
      'audience': 'Public',
      'status': 'Published',
      'createdBy': 'admin-1',
      'createdByName': 'Admin',
    });

    await _atEachWidth(tester, (tester) async {
      await tester.pumpWidget(_withRole('parent', CalendarView(service: service)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('CalendarView (Admin) with a Draft item and management actions has no overflow', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = CalendarService(firestore: firestore);
    await service.createEvent({
      'title': 'Staff Development Workshop on Montessori Pedagogy Techniques',
      'date': DateTime(2026, 9, 1),
      'startTime': '',
      'endTime': '',
      'eventType': 'Staff Meeting',
      'description': '',
      'location': '',
      'audience': 'Staff',
      'status': 'Draft',
      'createdBy': 'admin-1',
      'createdByName': 'Admin',
    });

    await _atEachWidth(tester, (tester) async {
      await tester.pumpWidget(_withRole('admin', CalendarView(service: service)));
      await tester.pumpAndSettle();
      // Month is the default view now; List still carries the inline
      // Publish/Edit/Archive row this test is checking for overflow on.
      await tester.tap(find.text('List'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Publish'), findsOneWidget);
    });
  });

  testWidgets('CalendarView empty state has no overflow at any required width', (tester) async {
    final service = CalendarService(firestore: FakeFirebaseFirestore());
    await _atEachWidth(tester, (tester) async {
      await tester.pumpWidget(_withRole('staff', CalendarView(service: service)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('No calendar items yet.'), findsOneWidget);
    });
  });

  testWidgets('MyLeaveView with a long reason has no overflow at any required width', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = LeaveService(firestore: firestore);
    await service.submitLeaveRequest(
      requesterId: 'u1',
      requesterName: 'A Staff Member With A Reasonably Long Display Name',
      leaveType: 'Earned Leave',
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 7),
      reason:
          'Travelling out of town for a family wedding and will not be reachable for the full duration of this leave request.',
    );

    await _atEachWidth(tester, (tester) async {
      await tester.pumpWidget(_withRole('staff', MyLeaveView(service: service)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('CalendarEventDialog form fields (including start/end time row) have no overflow', (tester) async {
    final service = CalendarService(firestore: FakeFirebaseFirestore());
    await _atEachWidth(tester, (tester) async {
      await tester.pumpWidget(
        _withRole(
          'admin',
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => CalendarEventDialog(
                  createdBy: 'admin-1',
                  createdByName: 'Admin',
                  service: service,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(CalendarEventDialog), findsOneWidget);
      Navigator.of(tester.element(find.byType(CalendarEventDialog))).pop();
      await tester.pumpAndSettle();
    });
  });

  testWidgets('AdminLeaveScreen with a pending request (Approve/Reject actions) has no overflow', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = LeaveService(firestore: firestore);
    await service.submitLeaveRequest(
      requesterId: 'staff-1',
      requesterName: 'A Staff Member With A Reasonably Long Display Name',
      leaveType: 'Earned Leave',
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 7),
      reason: 'Travelling out of town for a family wedding for the full duration of this leave request.',
    );

    await _atEachWidth(tester, (tester) async {
      await tester.pumpWidget(_withRole('admin', AdminLeaveScreen(service: service)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
    });
  });

  testWidgets('Calendar Month view with a long-titled event has no overflow (grid, day cells, day sheet)', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = CalendarService(firestore: firestore);
    final today = DateTime.now();
    await service.createEvent({
      'title': 'Annual Sports Day and Prize Distribution Ceremony for All Classes and Parents',
      'date': DateTime(today.year, today.month, today.day),
      'startTime': '09:00',
      'endTime': '13:00',
      'eventType': 'Event',
      'description': 'Long description text that must not overflow the day-events sheet or detail dialog.',
      'location': 'Main Ground, Behind the Administration Block',
      'audience': 'Public',
      'status': 'Published',
      'createdBy': 'admin-1',
      'createdByName': 'Admin',
    });

    await _atEachWidth(tester, (tester) async {
      await tester.pumpWidget(_withRole('parent', CalendarView(service: service)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // Interaction (day tap -> bottom sheet -> detail dialog) is checked once
    // at a single ordinary size rather than inside the width loop — tapping
    // through two stacked modal routes five times in a row within one test
    // is fragile or ambiguous, and the actual "event on the right day, tap
    // opens detail" behavior is already covered functionally by
    // calendar_views_test.dart's dedicated (non-responsive) test for it.
    await tester.pumpWidget(_withRole('parent', CalendarView(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${today.day}').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.textContaining('Annual Sports Day').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Calendar Week view with a long-titled event has no overflow', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = CalendarService(firestore: firestore);
    await service.createEvent({
      'title': 'Monthly Staff Development Workshop on Montessori Pedagogy Techniques',
      'date': DateTime.now(),
      'startTime': '10:00',
      'endTime': '',
      'eventType': 'Staff Meeting',
      'description': '',
      'location': '',
      'audience': 'Staff',
      'status': 'Published',
      'createdBy': 'admin-1',
      'createdByName': 'Admin',
    });

    await _atEachWidth(tester, (tester) async {
      await tester.pumpWidget(_withRole('staff', CalendarView(service: service)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Monthly Staff Development'), findsOneWidget);
    });
  });

  testWidgets('StudentLeaveRequestDialog (parent, child dropdown) form fields have no overflow', (tester) async {
    final service = LeaveService(firestore: FakeFirebaseFirestore());
    await _atEachWidth(tester, (tester) async {
      await tester.pumpWidget(
        _withRole(
          'parent',
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => StudentLeaveRequestDialog(
                  requesterId: 'parent-1',
                  requesterName: 'A Parent With A Reasonably Long Display Name',
                  requesterRole: 'parent',
                  linkedStudents: const [],
                  service: service,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(StudentLeaveRequestDialog), findsOneWidget);
      Navigator.of(tester.element(find.byType(StudentLeaveRequestDialog))).pop();
      await tester.pumpAndSettle();
    });
  });

  testWidgets('AdminLeaveScreen Student Leave tab (filters: search + status + date) has no overflow', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = LeaveService(firestore: firestore);
    await service.submitStudentLeaveRequest(
      requesterId: 'staff-1',
      requesterName: 'A Staff Member With A Reasonably Long Display Name',
      requesterRole: 'staff',
      studentId: 'student-1',
      studentName: 'A Student With A Reasonably Long Display Name',
      leaveType: 'Earned Leave',
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 5),
      reason: 'Travelling out of town for a family wedding for the full duration of this leave request.',
    );

    await _atEachWidth(tester, (tester) async {
      await tester.pumpWidget(_withRole('admin', AdminLeaveScreen(service: service)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Student Leave'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Filter by date'), findsOneWidget);
    });
  });

  testWidgets('LeaveRequestDialog form fields have no overflow at any required width', (tester) async {
    final service = LeaveService(firestore: FakeFirebaseFirestore());
    await _atEachWidth(tester, (tester) async {
      await tester.pumpWidget(
        _withRole(
          'staff',
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => LeaveRequestDialog(
                  requesterId: 'u1',
                  requesterName: 'Staff',
                  service: service,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(LeaveRequestDialog), findsOneWidget);
      // Close the dialog before the next width iteration.
      Navigator.of(tester.element(find.byType(LeaveRequestDialog))).pop();
      await tester.pumpAndSettle();
    });
  });
}

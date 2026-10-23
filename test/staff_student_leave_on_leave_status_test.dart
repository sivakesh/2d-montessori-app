// Regression coverage for Staff -> Leave -> Student Leave: an Approved
// student leave whose date range includes today must show "ON LEAVE";
// Pending/Rejected/Cancelled requests and Approved leave outside its range
// must not. StudentLeaveCard without `onLeaveDate` (Parent/Admin surfaces)
// must render exactly as before — never "ON LEAVE".
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/leave/models/leave_request_model.dart';
import 'package:montessori_app/modules/leave/services/leave_service.dart';
import 'package:montessori_app/modules/leave/ui/my_leave_view.dart';
import 'package:montessori_app/modules/leave/ui/widgets/student_leave_card.dart';

ProviderScope _withStaffUser(Widget child) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => AppUser(id: 'staff-1', phone: '9999999999', name: 'Teacher Priya', role: 'staff', isActive: true),
      ),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

Future<void> _seed(
  FakeFirebaseFirestore firestore, {
  required String studentName,
  required String status,
  required DateTime start,
  required DateTime end,
}) {
  return firestore.collection('staff_leave_requests').add({
    'requesterId': 'staff-1',
    'requesterName': 'Teacher Priya',
    'requesterRole': LeaveRequesterRole.staff,
    'subjectType': LeaveSubjectType.student,
    'studentId': 'id-$studentName',
    'studentName': studentName,
    'leaveType': LeaveType.sick,
    'startDate': start,
    'endDate': end,
    'reason': 'Reason',
    'status': status,
  });
}

/// Whether the card for [studentName] contains an "ON LEAVE" chip.
bool _cardShowsOnLeave(WidgetTester tester, String studentName) {
  final card = find.ancestor(of: find.text(studentName), matching: find.byType(StudentLeaveCard));
  return find.descendant(of: card, matching: find.text('ON LEAVE')).evaluate().isNotEmpty;
}

LeaveRequestModel _request({required String status, required DateTime start, required DateTime end}) {
  return LeaveRequestModel.fromMap('r1', {
    'subjectType': LeaveSubjectType.student,
    'studentId': 's1',
    'studentName': 'Card Student',
    'startDate': start,
    'endDate': end,
    'status': status,
  });
}

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  DateTime day(int offset) => today.add(Duration(days: offset));

  testWidgets('Staff Student Leave tab shows ON LEAVE only for approved leave covering today', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await _seed(firestore, studentName: 'Approved Single Today', status: LeaveStatus.approved, start: today, end: today);
    await _seed(firestore, studentName: 'Approved Multi Spanning', status: LeaveStatus.approved, start: day(-1), end: day(1));
    // Time-of-day components on stored dates must not affect coverage.
    await _seed(firestore, studentName: 'Approved Ends Today Morning', status: LeaveStatus.approved,
        start: day(-2), end: today.add(const Duration(hours: 9)));
    await _seed(firestore, studentName: 'Approved Past', status: LeaveStatus.approved, start: day(-5), end: day(-1));
    await _seed(firestore, studentName: 'Approved Future', status: LeaveStatus.approved, start: day(1), end: day(3));
    await _seed(firestore, studentName: 'Pending Today', status: LeaveStatus.pending, start: today, end: today);
    await _seed(firestore, studentName: 'Rejected Today', status: LeaveStatus.rejected, start: day(-1), end: day(1));
    await _seed(firestore, studentName: 'Cancelled Today', status: 'Cancelled', start: today, end: today);

    await tester.binding.setSurfaceSize(const Size(800, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_withStaffUser(MyLeaveView(service: LeaveService(firestore: firestore))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Student Leave'));
    await tester.pumpAndSettle();

    expect(_cardShowsOnLeave(tester, 'Approved Single Today'), isTrue);
    expect(_cardShowsOnLeave(tester, 'Approved Multi Spanning'), isTrue);
    expect(_cardShowsOnLeave(tester, 'Approved Ends Today Morning'), isTrue);
    expect(_cardShowsOnLeave(tester, 'Approved Past'), isFalse);
    expect(_cardShowsOnLeave(tester, 'Approved Future'), isFalse);
    expect(_cardShowsOnLeave(tester, 'Pending Today'), isFalse);
    expect(_cardShowsOnLeave(tester, 'Rejected Today'), isFalse);
    expect(_cardShowsOnLeave(tester, 'Cancelled Today'), isFalse);
    expect(find.text('ON LEAVE'), findsNWidgets(3));

    // Existing request-status chips are still shown alongside.
    expect(find.text('Approved'), findsNWidgets(5));
    expect(find.text('Rejected'), findsOneWidget);

    // Persistence after refresh: reloading the tab yields the same result.
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.text('ON LEAVE'), findsNWidgets(3));
  });

  testWidgets('StudentLeaveCard without onLeaveDate never shows ON LEAVE (Parent/Admin unchanged)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StudentLeaveCard(request: _request(status: LeaveStatus.approved, start: today, end: today)),
      ),
    ));
    expect(find.text('ON LEAVE'), findsNothing);
    expect(find.text('Approved'), findsOneWidget);
  });

  testWidgets('StudentLeaveCard ON LEAVE follows the given date, inclusive on both ends', (tester) async {
    final request = _request(status: LeaveStatus.approved, start: day(0), end: day(2));
    for (final (date, expected) in [
      (day(-1), false),
      (day(0), true),
      (day(1), true),
      (day(2), true),
      (day(3), false),
    ]) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StudentLeaveCard(request: request, onLeaveDate: date)),
      ));
      expect(find.text('ON LEAVE'), expected ? findsOneWidget : findsNothing, reason: 'date $date');
    }
  });
}

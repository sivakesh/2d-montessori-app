// UX coverage for LeaveRequestDialog: a failed submit (e.g. a transient
// Firestore write error) must show a recoverable error message and leave
// the dialog open with the user's input intact, rather than crashing or
// silently losing the request (task requirement #19 — "Failed save produces
// recoverable user feedback").
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/leave/services/leave_service.dart';
import 'package:montessori_app/modules/leave/ui/dialogs/leave_request_dialog.dart';

class _ThrowingLeaveService extends LeaveService {
  _ThrowingLeaveService({required super.firestore});

  @override
  Future<String> submitLeaveRequest({
    required String requesterId,
    required String requesterName,
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    throw Exception('network error');
  }
}

Future<void> _pumpDialog(WidgetTester tester, LeaveService service) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => LeaveRequestDialog(
                requesterId: 'staff-1',
                requesterName: 'Asha',
                service: service,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('submitting with an empty reason shows a validation error and does not submit', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await _pumpDialog(tester, LeaveService(firestore: firestore));

    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pumpAndSettle();

    expect(find.text('Reason is required'), findsOneWidget);
    final snap = await firestore.collection('staff_leave_requests').get();
    expect(snap.docs, isEmpty);
  });

  testWidgets('a failed submit shows a recoverable error message and keeps the dialog open', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await _pumpDialog(tester, _ThrowingLeaveService(firestore: firestore));

    await tester.enterText(find.byType(TextFormField).last, 'Fever');
    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not submit leave request'), findsOneWidget);
    // Dialog is still open, so the user can retry without re-entering data.
    expect(find.byType(LeaveRequestDialog), findsOneWidget);
  });

  testWidgets('a successful submit closes the dialog', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await _pumpDialog(tester, LeaveService(firestore: firestore));

    await tester.enterText(find.byType(TextFormField).last, 'Fever');
    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pumpAndSettle();

    expect(find.byType(LeaveRequestDialog), findsNothing);
    final snap = await firestore.collection('staff_leave_requests').get();
    expect(snap.docs, hasLength(1));
    expect(snap.docs.single.data()['requesterId'], 'staff-1');
  });
}

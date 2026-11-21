// Parent Dashboard Phase 1: the family overview, child cards, shared child
// navigation, attendance, fees / payments / bills (kept separate),
// notifications and upcoming events. Uses the parent-safe copies (the
// access record and projections, as after the administrator's
// reconciliation). These are application-level checks; server enforcement
// depends on the security rules review (docs/parent_access_security.md).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/core/services/auth_interface.dart';
import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/admin/students/models/admin_student_model.dart';
import 'package:montessori_app/modules/attendance/data/attendance_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/calendar/services/calendar_service.dart';
import 'package:montessori_app/modules/calendar/ui/calendar_view.dart';
import 'package:montessori_app/modules/classes/data/class_service.dart';
import 'package:montessori_app/modules/fees/models/student_fee_assignment_model.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/parent_fee_history_view.dart';
import 'package:montessori_app/modules/leave/services/leave_service.dart';
import 'package:montessori_app/modules/leave/ui/dialogs/student_leave_request_dialog.dart';
import 'package:montessori_app/modules/mood_checkin/services/mood_checkin_service.dart';
import 'package:montessori_app/modules/parent/data/parent_access_service.dart';
import 'package:montessori_app/modules/parent/data/parent_family_overview.dart';
import 'package:montessori_app/modules/parent/data/parent_file_service.dart';
import 'package:montessori_app/modules/parent/data/parent_link_service.dart';
import 'package:montessori_app/modules/parent/data/parent_projection_service.dart';
import 'package:montessori_app/modules/parent/data/parent_service.dart';
import 'package:montessori_app/modules/parent/ui/parent_app_bar.dart';
import 'package:montessori_app/modules/parent/ui/parent_dashboard.dart';
import 'package:montessori_app/modules/parent/ui/parent_family_overview.dart';
import 'package:montessori_app/modules/parent/ui/parent_notifications_screen.dart';

class _UnusedFilePicker extends FilePicker {}

const father = '9000000001';
const mother = '9000000002';
const guardian = '9000000003';
const secret = 'SECRET-TOKEN';

/// Attendance that fails for one child (a network error for that child only).
class _FlakyAttendance extends AttendanceService {
  _FlakyAttendance(FirebaseFirestore db, this.failFor) : super(firestore: db, storage: MockFirebaseStorage());
  String failFor;
  @override
  Future<List<Map<String, dynamic>>> getAttendanceHistoryForEntity({required String entityType, required String entityId, int days = 30}) {
    if (entityId == failFor) throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    return super.getAttendanceHistoryForEntity(entityType: entityType, entityId: entityId, days: days);
  }
}

class _FakeAuth implements AuthService {
  int logouts = 0;
  @override
  Future<AppUser?> signIn() async => null;
  @override
  Future<void> signOut() async {}
  @override
  Future<void> logout(WidgetRef ref, BuildContext context) async => logouts++;
}

String today([int daysAgo = 0]) {
  final d = DateTime.now().subtract(Duration(days: daysAgo));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// A family. Anu (s1) and Bala (s2): [father] is Father of both, [mother]
/// Mother of Anu only, [guardian] Guardian of both. Fees, payments (one
/// voided), a supplementary bill, attendance, leave, notices and calendar
/// items — then the access records and parent-safe copies are built, as the
/// administrator's reconciliation does.
Future<FakeFirebaseFirestore> family({int extraChildren = 0, bool withProfiles = true}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
  await db.collection('classes').doc('c2').set({'name': 'Mont 2', 'isActive': true});
  final kids = <String, String>{'s1': 'Anu Raman', 's2': 'Bala Raman', for (var i = 0; i < extraChildren; i++) 'x$i': 'Extra Child $i'};
  for (final MapEntry(key: id, value: name) in kids.entries) {
    await db.collection('students').doc(id).set({
      'name': name, 'admissionNo': 'ADM-$id', 'classId': id == 's2' ? 'c2' : 'c1', 'section': 'Rose', 'isActive': true,
    });
  }
  final links = ParentLinkService(firestore: db);
  await links.saveLinksForStudent(studentId: 's1', parents: const [
    ParentLinkEntry(userId: father, relation: 'Father', name: 'Ravi', phone: father),
    ParentLinkEntry(userId: mother, relation: 'Mother', name: 'Meena', phone: mother),
    ParentLinkEntry(userId: guardian, relation: 'Guardian', name: 'Kala', phone: guardian),
  ]);
  for (final id in kids.keys.where((k) => k != 's1')) {
    await links.saveLinksForStudent(studentId: id, parents: const [
      ParentLinkEntry(userId: father, relation: 'Father', name: 'Ravi', phone: father),
      ParentLinkEntry(userId: guardian, relation: 'Guardian', name: 'Kala', phone: guardian),
    ]);
  }
  Map<String, dynamic> fee(String studentId, double total, double discount, double paid, DateTime due) => {
        'studentId': studentId, 'feeStructureName': 'Term Fees', 'academicYear': '2026-2027', 'feeMonth': '',
        'totalFee': total, 'discountAmount': discount, 'payableAmount': total - discount, 'paidAmount': paid,
        'balanceAmount': total - discount - paid, 'status': 'partial', 'dueDate': due, 'assignedBy': 'admin-uid',
      };
  await db.collection('student_fee_assignments').doc('a1').set(fee('s1', 12000, 1000, 4000, DateTime(2026, 12, 10)));
  await db.collection('student_fee_assignments').doc('a2').set(fee('s2', 9000, 0, 9000, DateTime(2026, 12, 10)));
  await db.collection('fee_receipts').doc('r1').set({
    'studentId': 's1', 'assignmentId': 'a1', 'receiptNo': 'REC-2026-0001', 'amount': 4000, 'paymentDate': DateTime(2026, 11, 5),
    'paymentMode': 'UPI', 'referenceNo': 'UPI-778899', 'feeStructureName': 'Term Fees', 'feeMonth': '2026-11',
    'remarks': 'internal note', 'collectedBy': 'admin-uid', 'pdfUrl': 'https://storage.example/receipt.pdf?token=$secret', 'pdfPath': 'receipts/r1.pdf',
  });
  await db.collection('fee_receipts').doc('r-void').set({
    'studentId': 's1', 'assignmentId': 'a1', 'receiptNo': 'REC-2026-0099', 'amount': 777, 'paymentDate': DateTime(2026, 11, 6),
    'paymentMode': 'Cash', 'referenceNo': 'VOIDED-REF', 'isDeleted': true,
  });
  await db.collection('fee_issued_bills').doc('default_school_REC-2026-0001-000001').set({
    'schoolId': 'default_school', 'billNo': 'REC-2026-0001-000001', 'status': 'issued', 'receiptId': 'r1', 'studentId': 's1',
    'studentName': 'Anu Raman', 'payment': {'receiptId': 'r1', 'receiptNo': 'REC-2026-0001', 'amountPaise': 400000, 'paymentMode': 'UPI', 'referenceNo': 'UPI-778899'},
    'issueDate': DateTime(2026, 11, 2), 'billingMonth': '2026-11', 'description': 'Monthly fee', 'grossPaise': 410000,
    'adjustmentType': 'discount', 'adjustmentPaise': 10000, 'adjustmentReason': 'Rounding', 'netPaise': 400000,
    'issuedAt': DateTime(2026, 11, 2, 10), 'issuedBy': 'admin-uid', 'issueRequestId': 'req-1',
  });
  // Anu: present today, absent yesterday, an approved leave the day before
  // (unmarked). Bala: nothing marked.
  await db.collection('attendance').doc('${today()}_student_s1').set({'date': today(), 'status': 'present', 'entityType': 'student', 'entityId': 's1', 'photoUrl': 'https://x/photo.jpg?token=$secret'});
  await db.collection('attendance').doc('${today(1)}_student_s1').set({'date': today(1), 'status': 'absent', 'entityType': 'student', 'entityId': 's1'});
  final leaveDay = DateTime.now().subtract(const Duration(days: 2));
  await db.collection('staff_leave_requests').add({
    'requesterId': father, 'requesterName': 'Ravi', 'requesterRole': 'parent', 'subjectType': 'student', 'studentId': 's1', 'studentName': 'Anu Raman',
    'leaveType': 'Sick Leave', 'startDate': leaveDay, 'endDate': leaveDay, 'reason': 'Fever', 'status': 'Approved', 'createdAt': leaveDay,
  });
  await db.collection('staff_leave_requests').add({
    'requesterId': father, 'requesterName': 'Ravi', 'requesterRole': 'parent', 'subjectType': 'student', 'studentId': 's2', 'studentName': 'Bala Raman',
    'leaveType': 'Casual Leave', 'startDate': DateTime.now().add(const Duration(days: 5)), 'endDate': DateTime.now().add(const Duration(days: 5)),
    'reason': 'Trip', 'status': 'Pending', 'createdAt': DateTime.now(),
  });
  Map<String, dynamic> notice(String title, {List<String> students = const [], bool all = false}) => {
        'title': title, 'message': 'Details', 'status': 'Published', 'audience': 'Parents', 'appliesToAllClasses': all, 'appliesToAllStudents': false,
        'applicableClassIds': <String>[], 'applicableStudentIds': students, 'priority': 'Normal', 'category': 'General', 'publishDate': DateTime(2026, 11, 1),
      };
  await db.collection('school_notifications').doc('n-all').set(notice('School-wide notice', all: true));
  await db.collection('school_notifications').doc('n-anu').set(notice('Only for Anu', students: ['s1']));
  final soon = DateTime.now().add(const Duration(days: 3));
  await db.collection('school_calendar_events').doc('e1').set({'title': 'Annual Day', 'date': DateTime(soon.year, soon.month, soon.day), 'eventType': 'Event', 'audience': 'Parents', 'status': 'Published'});
  await db.collection('school_calendar_events').doc('e0').set({'title': 'Past Event', 'date': DateTime(2020, 1, 1), 'eventType': 'Event', 'audience': 'Parents', 'status': 'Published'});
  await db.collection('school_calendar_events').doc('e-draft').set({'title': 'Draft Event', 'date': DateTime(soon.year, soon.month, soon.day), 'eventType': 'Event', 'audience': 'Parents', 'status': 'Draft'});

  final access = ParentAccessService(firestore: db);
  await access.apply(await access.preview(requesterRole: 'admin'), requesterRole: 'admin', updatedBy: 'admin');
  if (withProfiles) await ParentProjectionService(firestore: db).syncAll(requesterRole: 'admin');
  return db;
}

Widget app(FakeFirebaseFirestore db, String parent, {AttendanceService? attendance, AuthService? auth}) => ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => AppUser(id: parent, phone: parent, name: 'Test Parent', role: 'parent', isActive: true)),
        if (auth != null) authServiceProvider.overrideWithValue(auth),
      ],
      child: MaterialApp(
        routes: {'/login': (_) => const Scaffold(body: Text('Login screen'))},
        home: ParentDashboard(
          parentService: ParentService(firestore: db),
          attendanceService: attendance ?? AttendanceService(firestore: db, storage: MockFirebaseStorage()),
          feeService: FeeService(firestore: db, auth: MockFirebaseAuth(), storage: MockFirebaseStorage()),
          notificationService: AdminNotificationService(firestore: db, storage: MockFirebaseStorage(), filePicker: _UnusedFilePicker()),
          classService: ClassService(firestore: db),
          moodCheckinService: MoodCheckinService(firestore: db, storage: MockFirebaseStorage()),
          leaveService: LeaveService(firestore: db, parentService: ParentService(firestore: db)),
          calendarService: CalendarService(firestore: db),
        ),
      ),
    );

Future<void> pump(WidgetTester tester, Widget widget, {Size size = const Size(1280, 2400)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Closes the open dialog with its close button (a full-screen page on a
/// phone, a dialog on wider screens).
Future<void> closeDialog(WidgetTester tester) => tap(tester, find.byIcon(Icons.close).last);

/// Every piece of text on screen, for "never shown" checks.
String screenText(WidgetTester tester) => [
      for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? t.textSpan?.toPlainText() ?? '',
      for (final t in tester.widgetList<widgets.RichText>(find.byType(widgets.RichText))) t.text.toPlainText(),
    ].join('\n');

Finder tile(String key) => find.byKey(Key('parent-summary-$key'));
String tileText(WidgetTester tester, String key) =>
    [for (final t in tester.widgetList<Text>(find.descendant(of: tile(key), matching: find.byType(Text)))) t.data ?? ''].join(' | ');

void main() {
  group('family overview', () {
    testWidgets('two children: a card each, family summary, family notices and upcoming events', (tester) async {
      await pump(tester, app(await family(), father));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Your family overview · 2 children'), findsOneWidget);
      expect(find.byKey(ParentChildOverviewCard.openKey('s1')), findsOneWidget);
      expect(find.byKey(ParentChildOverviewCard.openKey('s2')), findsOneWidget);
      expect(tileText(tester, 'children'), contains('2'));
      expect(tileText(tester, 'attendance'), contains('1 of 2'), reason: 'Anu present, Bala not marked');
      expect(find.text('School-wide notice'), findsOneWidget);
      expect(find.text('Only for Anu'), findsOneWidget);
      expect(find.text('Annual Day'), findsOneWidget);
      expect(find.text('Past Event'), findsNothing);
      expect(find.text('Draft Event'), findsNothing);
      expect(tileText(tester, 'events'), contains('1'));
      expect(find.byType(ChoiceChip), findsNothing, reason: 'the selector belongs to a child\'s own dashboard');
    });

    testWidgets('each child keeps their own attendance: today, the last 30 days and approved leave', (tester) async {
      await pump(tester, app(await family(), father));
      final anu = find.byKey(const Key('parent-child-card-s1'));
      final bala = find.byKey(const Key('parent-child-card-s2'));
      expect(find.descendant(of: anu, matching: find.text('Present')), findsOneWidget);
      expect(find.descendant(of: anu, matching: find.text('Last 30 days: 1 present · 1 absent · 1 on leave')), findsOneWidget);
      expect(find.descendant(of: bala, matching: find.text('Not marked yet')), findsOneWidget);
      expect(find.descendant(of: bala, matching: find.text('No attendance marked in the last 30 days.')), findsOneWidget);
      expect(find.descendant(of: bala, matching: find.text('1 leave request pending')), findsOneWidget);
      expect(find.descendant(of: anu, matching: find.text('1 notice for this child')), findsOneWidget);
      expect(screenText(tester), isNot(contains(secret)), reason: 'no attendance photo URL');
      expect(find.textContaining('%'), findsNothing, reason: 'no attendance percentage is invented');
    });

    testWidgets('many children: every child is shown, none dropped', (tester) async {
      await pump(tester, app(await family(extraChildren: 4), father));
      for (final id in ['s1', 's2', 'x0', 'x1', 'x2', 'x3']) {
        expect(find.byKey(ParentChildOverviewCard.openKey(id)), findsOneWidget, reason: id);
      }
      expect(tileText(tester, 'children'), contains('6'));
    });

    testWidgets('one child: a single page for that child, no family navigation', (tester) async {
      await pump(tester, app(await family(), mother));
      expect(find.textContaining("Here's what's happening with your child today."), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byKey(ParentChildSwitcher.familyOverviewKey), findsNothing);
      expect(tile('children'), findsNothing);
      expect(tileText(tester, 'attendance'), contains('Present'));
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Request Leave'), findsOneWidget);
      expect(find.text('Annual Day'), findsOneWidget);
    });

    testWidgets('no linked children: a clear empty state', (tester) async {
      await pump(tester, app(await family(), '9000000077'));
      // The approved wording for a parent whose account isn't linked yet.
      expect(find.text('Your account is not linked to a student yet'), findsOneWidget);
      expect(tile('outstanding'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a linked child whose profile is unavailable is reported, not silently dropped', (tester) async {
      final db = await family();
      await db.collection('parent_student_profiles').doc('s2').delete();
      await pump(tester, app(db, father));
      expect(find.byKey(const Key('parent-children-unavailable')), findsOneWidget);
      expect(find.textContaining("One linked child's profile isn't available yet"), findsOneWidget);
      expect(find.text('Anu Raman'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets("one child's data failing leaves the rest of the family usable, and Retry recovers", (tester) async {
      final db = await family();
      final attendance = _FlakyAttendance(db, 's2');
      await pump(tester, app(db, father, attendance: attendance));
      final bala = find.byKey(const Key('parent-child-card-s2'));
      expect(find.descendant(of: bala, matching: find.text("Attendance couldn't load.")), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('parent-child-card-s1')), matching: find.textContaining('Last 30 days')), findsOneWidget);
      expect(tileText(tester, 'attendance'), contains('Unavailable'), reason: 'never a partial family figure');
      expect(find.descendant(of: bala, matching: find.byKey(const Key('parent-fee-figures'))), findsOneWidget, reason: "Bala's fees still load");

      // The network is back: that child's Retry reloads just that child.
      attendance.failFor = '';
      await tap(tester, find.descendant(of: bala, matching: find.text('Retry')));
      expect(find.descendant(of: bala, matching: find.text('No attendance marked in the last 30 days.')), findsOneWidget);
      expect(tileText(tester, 'attendance'), contains('1 of 2'));
      expect(tester.takeException(), isNull);
    });
  });

  group('financial access', () {
    testWidgets("Father: each child's own fee figures (gross, discount, net, paid, outstanding, due) and the family total", (tester) async {
      await pump(tester, app(await family(), father));
      final anu = find.byKey(const Key('parent-child-card-s1'));
      for (final t in ['₹11,000.00', '₹4,000.00', '₹7,000.00']) {
        expect(find.descendant(of: anu, matching: find.text(t)), findsOneWidget, reason: t);
      }
      expect(find.descendant(of: anu, matching: find.text('Gross ₹12,000.00 · Discount ₹1,000.00')), findsOneWidget);
      expect(find.descendant(of: anu, matching: find.textContaining('due 10 Dec 2026')), findsOneWidget);
      expect(find.descendant(of: anu, matching: find.text('Last payment ₹4,000.00 on 5 Nov 2026 (UPI)')), findsOneWidget);
      expect(tileText(tester, 'outstanding'), contains('₹7,000.00'), reason: 'Anu ₹7,000 + Bala ₹0');
    });

    testWidgets('Mother: the same fee figures for her child', (tester) async {
      await pump(tester, app(await family(), mother));
      expect(find.byKey(const Key('parent-fee-figures')), findsOneWidget);
      expect(tileText(tester, 'outstanding'), contains('₹7,000.00'));
      expect(find.byKey(const Key('parent-fees-payment-history')), findsOneWidget);
      expect(find.byKey(const Key('parent-fees-issued-bills')), findsOneWidget);
    });

    testWidgets('Guardian: no fee figure, total, discount, payment or bill anywhere — family or child', (tester) async {
      await pump(tester, app(await family(), guardian));
      expect(tile('outstanding'), findsNothing);
      expect(find.byKey(const Key('parent-fee-figures')), findsNothing);
      expect(find.byKey(const Key('parent-family-fees')), findsNothing);
      expect(screenText(tester), isNot(contains('₹')));
      for (final id in ['s1', 's2']) {
        expect(find.byKey(ParentChildOverviewCard.paymentsKey(id)), findsNothing);
        expect(find.byKey(ParentChildOverviewCard.billsKey(id)), findsNothing);
      }
      await tap(tester, find.byKey(ParentChildOverviewCard.openKey('s1')));
      expect(find.byKey(const Key('parent-fees-restricted')), findsOneWidget);
      expect(find.byKey(const Key('parent-fees-payment-history')), findsNothing);
      expect(find.byKey(const Key('parent-fees-issued-bills')), findsNothing);
      expect(screenText(tester), isNot(contains('₹')));
    });

    test('Guardian: the loader reads nothing financial (not just hidden)', () async {
      final db = await family();
      final children = await ParentService(firestore: db).getLinkedChildren(guardian);
      final loader = ParentFamilyOverviewLoader(
        parentService: ParentService(firestore: db),
        attendanceService: AttendanceService(firestore: db, storage: MockFirebaseStorage()),
        feeService: FeeService(firestore: db, auth: MockFirebaseAuth(), storage: MockFirebaseStorage()),
        fileService: ParentFileService(parentUserId: guardian, firestore: db, storage: MockFirebaseStorage()),
      );
      for (final c in children) {
        final o = await loader.load(c);
        expect([o.financeRestricted, o.finance], [true, null]);
      }
      // And the bill check itself refuses a Guardian.
      await expectLater(ParentFileService(parentUserId: guardian, firestore: db, storage: MockFirebaseStorage()).feeBillsForStudent('s1'), throwsA(isA<ParentFileAccessDenied>()));
    });

    test('a family total only ever covers children whose fees the parent may see', () {
      ParentChildOverview o(String id, {bool restricted = false, double outstanding = 0}) => ParentChildOverview(
            child: LinkedChild(student: _student(id), relation: restricted ? 'Guardian' : 'Father', canViewFinance: !restricted),
            financeRestricted: restricted,
            finance: restricted ? null : ParentChildFinance(assignments: [_fee(id, outstanding)], payments: const []),
          );
      final a = o('a', outstanding: 500), b = o('b', restricted: true);
      final totals = ParentFamilyTotals.of([a.child, b.child], {'a': a, 'b': b});
      expect([totals.financeChildren, totals.outstanding], [1, 500]);
      // While a financial child is still loading, no total is shown.
      expect(ParentFamilyTotals.of([a.child, b.child], {'b': b}).outstanding, isNull);
      // Guardian only: no financial figure at all.
      expect(ParentFamilyTotals.of([b.child], {'b': b}).financeChildren, 0);
    });

    testWidgets('Payment History and Issued Bills are separate: payments show their references; bills are not payments', (tester) async {
      await pump(tester, app(await family(), father));
      await tap(tester, find.byKey(ParentChildOverviewCard.paymentsKey('s1')));
      final payments = find.byKey(const Key('parent-payment-history'));
      expect(payments, findsOneWidget);
      expect(find.descendant(of: payments, matching: find.text('Mode: UPI · Ref: UPI-778899')), findsOneWidget);
      expect(find.descendant(of: payments, matching: find.text('Receipt No. REC-2026-0001')), findsOneWidget);
      expect(find.descendant(of: payments, matching: find.text('For Term Fees · November 2026')), findsOneWidget);
      expect(find.descendant(of: payments, matching: find.textContaining('VOIDED-REF')), findsNothing, reason: 'voided payments excluded');
      expect(find.descendant(of: payments, matching: find.textContaining('REC-2026-0001-000001')), findsNothing, reason: 'no bill in payments');
      final text = screenText(tester);
      expect(text, isNot(anyOf(contains(secret), contains('receipt.pdf'), contains('internal note'), contains('admin-uid'))));
      await closeDialog(tester);

      await tap(tester, find.byKey(ParentChildOverviewCard.billsKey('s1')));
      final bills = find.byKey(const Key('parent-issued-bills'));
      expect(bills, findsOneWidget);
      expect(find.descendant(of: bills, matching: find.text('REC-2026-0001-000001')), findsOneWidget);
      expect(find.descendant(of: bills, matching: find.text('Billing month: November 2026 · Issued 2 Nov 2026')), findsOneWidget);
      expect(find.descendant(of: bills, matching: find.text('Gross ₹4,100.00 · Adjustment ₹100.00 · Net ₹4,000.00')), findsOneWidget);
      expect(find.descendant(of: bills, matching: find.text('Issued')), findsOneWidget);
      expect(find.descendant(of: bills, matching: find.textContaining('UPI-778899')), findsNothing, reason: 'no payment in bills');
      expect(find.descendant(of: bills, matching: find.byIcon(Icons.download)), findsNothing, reason: 'no download in this phase');
    });
  });

  group('responsive', () {
    for (final width in [320.0, 375.0, 430.0, 768.0, 1024.0, 1440.0]) {
      testWidgets('${width.toInt()} px: family overview, a child\'s dashboard and the dialogs lay out without overflow', (tester) async {
        final db = await family(extraChildren: 2);
        await db.collection('students').doc('s1').update({'name': 'Aadhavan Subramaniam Venkataraghavan Krishnamoorthy'});
        await ParentProjectionService(firestore: db).syncAll(requesterRole: 'admin');
        await pump(tester, app(db, father), size: Size(width, 900));
        expect(tester.takeException(), isNull);
        for (final id in ['s1', 's2', 'x0', 'x1']) {
          expect(find.byKey(ParentChildOverviewCard.openKey(id)), findsOneWidget);
        }
        expect(find.byKey(ParentAppBar.logoutKey).hitTestable(), findsOneWidget);
        await tap(tester, find.byKey(ParentChildOverviewCard.paymentsKey('s1')));
        expect(tester.takeException(), isNull);
        await closeDialog(tester);
        await tap(tester, find.byKey(ParentChildOverviewCard.openKey('s1')));
        expect(tester.takeException(), isNull);
        expect(find.byKey(ParentChildSwitcher.familyOverviewKey).hitTestable(), findsOneWidget);
        await tap(tester, find.byKey(const Key('parent-fees-issued-bills')));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('navigation', () {
    testWidgets('open a child, switch children, return to the family overview; the selected child is kept across tabs', (tester) async {
      await pump(tester, app(await family(), father));
      await tap(tester, find.byKey(ParentChildOverviewCard.openKey('s1')));
      expect(find.byType(ChoiceChip), findsNWidgets(2));
      expect(tester.widget<ChoiceChip>(find.byType(ChoiceChip).first).selected, isTrue);
      expect(find.text('Only for Anu'), findsOneWidget);

      await tap(tester, find.widgetWithText(ChoiceChip, 'Bala Raman'));
      expect(tester.widget<ChoiceChip>(find.byType(ChoiceChip).last).selected, isTrue);
      expect(find.text('Only for Anu'), findsNothing, reason: "Anu's notice is not shown on Bala's dashboard");

      // Another tab and back: still on Bala's dashboard.
      await tap(tester, find.descendant(of: find.byType(NavigationRail), matching: find.text('Leave')));
      await tap(tester, find.descendant(of: find.byType(NavigationRail), matching: find.text('Dashboard')));
      expect(tester.widget<ChoiceChip>(find.byType(ChoiceChip).last).selected, isTrue);

      await tap(tester, find.byKey(ParentChildSwitcher.familyOverviewKey));
      expect(find.byKey(ParentChildOverviewCard.openKey('s2')), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('Fees, Issued Bills, Payment History from a child\'s dashboard; Fees from the family', (tester) async {
      await pump(tester, app(await family(), father));
      await tap(tester, find.byKey(const Key('parent-family-fees')));
      expect(find.byType(ParentFeeHistoryView), findsOneWidget);
      await tap(tester, find.descendant(of: find.byType(NavigationRail), matching: find.text('Dashboard')));
      await tap(tester, find.byKey(ParentChildOverviewCard.openKey('s1')));
      await tap(tester, find.byKey(const Key('parent-fees-issued-bills')));
      expect(find.byKey(const Key('parent-issued-bills')), findsOneWidget);
      await closeDialog(tester);
      await tap(tester, find.byKey(const Key('parent-fees-payment-history')));
      expect(find.byKey(const Key('parent-payment-history')), findsOneWidget);
      await closeDialog(tester);
      await tap(tester, find.byKey(const Key('parent-fees-all')));
      expect(find.byType(ParentFeeHistoryView), findsOneWidget);
    });

    testWidgets('Calendar (and an event), Notifications, Mood, Leave, Profile and History open', (tester) async {
      await pump(tester, app(await family(), father));
      await tap(tester, find.text('Annual Day'));
      expect(find.text('Annual Day'), findsWidgets, reason: 'event detail');
      await closeDialog(tester);
      await tap(tester, find.byKey(ParentUpcomingEvents.viewCalendarKey));
      expect(find.byType(CalendarView), findsOneWidget);
      await tap(tester, find.descendant(of: find.byType(NavigationRail), matching: find.text('Dashboard')));

      await tap(tester, find.byKey(ParentFamilyHeader.notificationsKey));
      expect(find.byType(ParentNotificationsScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('How are you feeling today?'), findsOneWidget, reason: 'Mood Check-in');
      await tap(tester, find.byKey(const Key('parent-family-request-leave')));
      expect(find.byType(StudentLeaveRequestDialog), findsOneWidget);
      await tap(tester, find.text('Cancel'));

      await tap(tester, find.byKey(ParentChildOverviewCard.openKey('s1')));
      await tap(tester, find.text('Profile'));
      expect(find.text('Child Profile'), findsOneWidget);
      await closeDialog(tester);
      await tap(tester, find.text('History'));
      expect(find.text('Attendance History'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('logout still signs out and returns to the login screen', (tester) async {
      final auth = _FakeAuth();
      await pump(tester, app(await family(), father, auth: auth));
      await tap(tester, find.byKey(ParentAppBar.logoutKey));
      expect(auth.logouts, 1);
      expect(find.text('Login screen'), findsOneWidget);
    });
  });
}

AdminStudentModel _student(String id) => AdminStudentModel.fromMap(id, {'name': id, 'isActive': true});

StudentFeeAssignmentModel _fee(String studentId, double outstanding) => StudentFeeAssignmentModel.fromMap('fee-$studentId', {
      'studentId': studentId, 'totalFee': outstanding, 'discountAmount': 0, 'payableAmount': outstanding, 'paidAmount': 0, 'balanceAmount': outstanding,
    });


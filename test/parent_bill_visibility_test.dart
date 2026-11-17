// Parent Dashboard bug: "Issued bills aren't available for your account
// yet" for a Father whose child's three bills (September, October,
// November 2026) exist. Execution path: the dialog showed that text only
// when the child was read without a parent access record (legacy reads);
// the bill copies are never read then, so the backfill could not help.
// These tests reproduce that state and cover the diagnostics and parent
// states added for it:
// - Check lists linked parents with no access record; the per-account
//   diagnosis shows "access record NO" with 3 bills and 3 parent copies;
// - Apply then lets the Father retrieve the three bills;
// - opening Fee Bill Issuance runs the backfill and shows its result,
//   including failed writes with their error code;
// - refused reads are reported with their code (parent dialog, Check), never
//   as an empty list, and never hide the fees;
// - missing fee access, Guardian denial, no-bills vs error, idempotence,
//   and no original record changing.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// whenCalling: fake_cloud_firestore's failure injection (a dependency of
// it, not of the app), as in website_publish_guards_test.dart.
// ignore: depend_on_referenced_packages
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/attendance/data/attendance_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/calendar/services/calendar_service.dart';
import 'package:montessori_app/modules/classes/data/class_service.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_issuance_page.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_models.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_service.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/leave/services/leave_service.dart';
import 'package:montessori_app/modules/mood_checkin/services/mood_checkin_service.dart';
import 'package:montessori_app/modules/parent/data/parent_access_service.dart';
import 'package:montessori_app/modules/parent/data/parent_family_overview.dart';
import 'package:montessori_app/modules/parent/data/parent_fee_bill_refresh.dart';
import 'package:montessori_app/modules/parent/data/parent_file_service.dart';
import 'package:montessori_app/modules/parent/data/parent_link_service.dart';
import 'package:montessori_app/modules/parent/data/parent_projection_service.dart';
import 'package:montessori_app/modules/parent/data/parent_projections.dart';
import 'package:montessori_app/modules/parent/data/parent_service.dart';
import 'package:montessori_app/modules/parent/ui/parent_dashboard.dart';

class _UnusedFilePicker extends FilePicker {}

/// Fake Firestore whose [deny]-listed collections refuse every call the way
/// the security rules refuse a read (`permission-denied`).
class _RulesFirestore extends FakeFirebaseFirestore {
  final deny = <String>{};
  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    if (deny.contains(collectionPath)) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied', message: 'Missing or insufficient permissions.');
    }
    return super.collection(collectionPath);
  }
}

const father = '9000000001';
const guardian = '9000000003';
const school = FeeBillSchool(name: '2D Eduvance Montessori', addressLines: ['12, Lake View Road'], contactLines: ['044 1234 5678']);

FeeBillLine line(String month, int rupees, {int adjustment = 0}) => FeeBillLine(
      billingMonth: month,
      description: 'Monthly tuition fee',
      grossPaise: rupees * 100,
      adjustmentType: adjustment > 0 ? FeeBillAdjustmentType.discount : FeeBillAdjustmentType.none,
      adjustmentPaise: adjustment * 100,
      adjustmentReason: adjustment > 0 ? 'Rounded to the amount paid' : '',
    );

Future<Map<String, Object?>> originals(FakeFirebaseFirestore db) async => {
      for (final c in ['fee_issued_bills', 'fee_bill_allocations', 'fee_receipts', 'fee_transactions', 'student_fee_assignments', 'students', 'finance_income', 'finance_ledger'])
        for (final d in (await db.collection(c).get()).docs) '$c/${d.id}': d.data(),
    };

void main() {
  late _RulesFirestore db;
  late FeeBillService bills;
  late List<FeeIssuedBill> issued;
  late ParentProjectionService copies;
  late ParentAccessService access;

  Future<void> applyAccess() async => access.apply(await access.preview(requesterRole: 'admin'), requesterRole: 'admin', updatedBy: 'admin');

  setUp(() async {
    FeeBillService.defaultAfterChange = null;
    FeeBillService.defaultBackfill = null;
    db = _RulesFirestore();
    copies = ParentProjectionService(firestore: db);
    access = ParentAccessService(firestore: db);
    final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'admin-1'));
    final finance = FinanceService(firestore: db, auth: auth);
    await finance.ensureDefaults();
    final fees = FeeService(firestore: db, auth: auth, storage: MockFirebaseStorage(), financeService: finance, clock: () => DateTime(2026, 11, 5));
    bills = FeeBillService(firestore: db, auth: auth, clock: () => DateTime(2026, 11, 16, 10));
    final yearId = await AcademicYearService(firestore: db).createAcademicYear(
      schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2026-2027',
      startDate: DateTime(2026, 6, 1), endDate: DateTime(2027, 5, 31), createdBy: 'admin-1', setAsCurrent: true,
    );
    await db.collection('fee_structures').doc('term').set({'name': 'Term Fees', 'totalAmount': 12500, 'academicYear': '2026-2027', 'academicYearId': yearId, 'isActive': true, 'components': []});
    await db.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
    await db.collection('users').doc(father).set({'role': 'parent', 'phone': father, 'isActive': true});
    await db.collection('students').doc('s1').set({'name': 'Anu Raman', 'admissionNo': 'ADM-101', 'classId': 'c1', 'isActive': true, 'admissionDate': DateTime(2020, 1, 1)});
    // Linked, but no access record written yet (the DEV state).
    await ParentLinkService(firestore: db).saveLinksForStudent(studentId: 's1', parents: const [
      ParentLinkEntry(userId: father, relation: 'Father', name: 'Ravi', phone: father),
      ParentLinkEntry(userId: guardian, relation: 'Guardian', name: 'Kala', phone: guardian),
    ]);
    final assignmentId = (await fees.assignFee({
      'studentId': 's1', 'studentName': 'Anu Raman', 'admissionNo': 'ADM-101', 'classId': 'c1', 'className': 'Mont 1',
      'feeStructureId': 'term', 'feeStructureName': 'Term Fees', 'academicYearId': yearId, 'academicYear': '2026-2027',
      'totalFee': 12500, 'discountAmount': 0, 'payableAmount': 12500, 'paidAmount': 0, 'balanceAmount': 12500, 'status': 'unpaid', 'dueDate': DateTime(2026, 11, 30),
    }))!;
    final receipt = await fees.collectFee(assignmentId: assignmentId, amount: 12500, paymentDate: DateTime(2026, 11, 5), paymentMode: 'upi', referenceNo: 'UPI-778899', remarks: '');
    issued = await bills.issueBills(
      requesterRole: 'admin', studentId: 's1', receiptId: receipt.id, requestId: 'req-1', school: school,
      lines: [line('2026-09', 4200), line('2026-10', 4200), line('2026-11', 4200, adjustment: 100)],
    );
    await copies.syncAll(requesterRole: 'admin');
  });

  tearDown(() {
    FeeBillService.defaultAfterChange = null;
    FeeBillService.defaultBackfill = null;
  });

  Widget dashboard(String parent) => ProviderScope(
        overrides: [currentUserProvider.overrideWith((ref) => AppUser(id: parent, phone: parent, name: 'Parent', role: 'parent', isActive: true))],
        child: MaterialApp(
          home: ParentDashboard(
            parentService: ParentService(firestore: db),
            attendanceService: AttendanceService(firestore: db, storage: MockFirebaseStorage()),
            feeService: FeeService(firestore: db, auth: MockFirebaseAuth(), storage: MockFirebaseStorage()),
            notificationService: AdminNotificationService(firestore: db, storage: MockFirebaseStorage(), filePicker: _UnusedFilePicker()),
            classService: ClassService(firestore: db),
            moodCheckinService: MoodCheckinService(firestore: db, storage: MockFirebaseStorage()),
            leaveService: LeaveService(firestore: db, parentService: ParentService(firestore: db)),
            calendarService: CalendarService(firestore: db),
          ),
        ),
      );

  Future<void> pump(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(w);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> openBills(WidgetTester tester) => tap(tester, find.byKey(const Key('parent-fees-issued-bills')));

  group('root cause: the Father has no access record', () {
    testWidgets('fees show but the bills say parent access is not configured, although all three copies exist', (tester) async {
      expect((await tester.runAsync(() => db.collection('parent_fee_bills').get()))!.docs.length, 3, reason: 'the copies exist');
      await pump(tester, dashboard(father));
      expect(find.byKey(const Key('parent-fee-figures')), findsOneWidget);
      await openBills(tester);
      expect(find.byKey(const Key('parent-bills-access-not-configured')), findsOneWidget);
      expect(find.byKey(const Key('parent-bills-none')), findsNothing);
    });

    test('Check lists the Father as missing an access record; the account diagnosis pinpoints it', () async {
      final comparison = await access.compare(await access.preview(requesterRole: 'admin'), requesterRole: 'admin');
      expect(comparison.missing, containsAll([father, guardian]));
      final d = await copies.diagnoseParent(father, requesterRole: 'admin');
      expect([d.userRecord, d.accessRecord, d.links], [true, false, 1]);
      final child = d.children.single;
      expect([child.studentId, child.relation, child.inAccessRecord, child.financeAccess, child.profileCopy, child.billOriginals, child.billCopies],
          ['s1', 'Father', false, false, true, 3, 3]);
      expect(d.errors, isEmpty);
    });

    testWidgets('after Apply, the Father retrieves all three bills with the right references, months and amounts', (tester) async {
      await tester.runAsync(applyAccess);
      final d = (await tester.runAsync(() => copies.diagnoseParent(father, requesterRole: 'admin')))!;
      expect([d.accessRecord, d.children.single.financeAccess], [true, true]);
      await pump(tester, dashboard(father));
      await openBills(tester);
      final dialog = find.byKey(const Key('parent-issued-bills'));
      for (final b in issued) {
        expect(find.descendant(of: dialog, matching: find.text(b.billNo)), findsOneWidget);
      }
      expect(find.descendant(of: dialog, matching: find.textContaining('Billing month: September 2026')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.textContaining('Billing month: October 2026')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('Gross ₹4,200.00 · Adjustment ₹100.00 · Net ₹4,100.00')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('Gross ₹4,200.00 · Adjustment ₹0.00 · Net ₹4,200.00')), findsNWidgets(2));
    });
  });

  group('backfill from the Fee Bill Issuance page', () {
    Widget page(String role) => ProviderScope(
          overrides: [currentUserProvider.overrideWith((ref) => AppUser(id: 'u-$role', phone: '9000000000', name: role, role: role, isActive: true))],
          child: MaterialApp(home: FeeBillIssuancePage(service: bills, loadSchool: () async => SchoolSettingsModel.fromMap(kDefaultSchoolId, {'name': 'School'}), loadLogo: (_) async => null)),
        );

    Future<String> statusText(WidgetTester tester) async {
      await tester.pump();
      for (var i = 0; i < 100 && find.byKey(const Key('fee-bills-parent-copies')).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      return tester.widget<Text>(find.byKey(const Key('fee-bills-parent-copies'))).data!;
    }

    testWidgets('opening the page runs the registered backfill and shows its result; again writes nothing', (tester) async {
      registerParentFeeBillRefresh();
      await tester.runAsync(() => db.collection('parent_fee_bills').doc(issued.first.id).delete());
      await pump(tester, page('admin'));
      expect(await statusText(tester), 'Parent copies of bills are up to date (3 bills, 1 copied now).');
      await tester.pumpWidget(const SizedBox());
      await pump(tester, page('admin'));
      expect(await statusText(tester), 'Parent copies of bills are up to date (3 bills).');
    });

    testWidgets('not for staff: nothing runs and nothing is shown', (tester) async {
      registerParentFeeBillRefresh();
      await tester.runAsync(() => db.collection('parent_fee_bills').doc(issued.first.id).delete());
      await pump(tester, page('staff'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.byKey(const Key('fee-bills-parent-copies')), findsNothing);
      expect((await tester.runAsync(() => db.collection('parent_fee_bills').get()))!.docs.length, 2);
    });

    testWidgets('a refused copy write is shown on the page with its code and recorded for Check', (tester) async {
      registerParentFeeBillRefresh();
      await tester.runAsync(() => db.collection('parent_fee_bills').doc(issued.first.id).delete());
      whenCalling(Invocation.method(#set, null))
          .on(db.collection('parent_fee_bills').doc(issued.first.id))
          .thenThrow(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied', message: 'Missing or insufficient permissions.'));
      await pump(tester, page('admin'));
      final text = await statusText(tester);
      expect(text, startsWith('Parent copies of bills could not all be updated (1 failed): permission-denied'));
      final failures = (await tester.runAsync(() => copies.failures(requesterRole: 'admin')))!;
      expect(failures.map((f) => f.error), contains(startsWith('permission-denied')));
    });
  });

  group('reported, never silent', () {
    testWidgets("a refused read of the bill copies is shown with its code; the fees stay visible", (tester) async {
      await tester.runAsync(applyAccess);
      db.deny.add('parent_fee_bills');
      await pump(tester, dashboard(father));
      expect(find.byKey(const Key('parent-fee-figures')), findsOneWidget, reason: 'a bill failure never hides the fees');
      await openBills(tester);
      expect(find.byKey(const Key('parent-bills-failed')), findsOneWidget);
      expect(find.textContaining('permission-denied'), findsOneWidget);
      expect(find.byKey(const Key('parent-bills-none')), findsNothing);
      // Fixed (e.g. rules deployed): Retry reloads and shows the bills.
      db.deny.remove('parent_fee_bills');
      await tap(tester, find.byKey(const Key('parent-bills-retry')));
      await openBills(tester);
      expect(find.text(issued.first.billNo), findsOneWidget);
    });

    test('Check reports a kind it cannot read instead of failing or calling it current', () async {
      db.deny.add('parent_fee_bills');
      final health = {for (final h in await copies.health(requesterRole: 'admin')) h.kind: h};
      expect(health[ParentProjectionKind.feeBills]!.error, startsWith('permission-denied'));
      expect(health[ParentProjectionKind.feeBills]!.isCurrent, isFalse);
      expect(health[ParentProjectionKind.profile]!.error, isEmpty);
      final d = await copies.diagnoseParent(father, requesterRole: 'admin');
      expect(d.children.single.billCopies, isNull);
      expect(d.children.single.errors.single, startsWith('bill copies: permission-denied'));
    });

    test('a refused read in the loader becomes a "failed" bill status with the code, not an empty list', () async {
      await applyAccess();
      final linked = (await ParentService(firestore: db).getLinkedChildren(father)).single;
      db.deny.add('parent_fee_bills');
      final o = await ParentFamilyOverviewLoader(
        parentService: ParentService(firestore: db),
        attendanceService: AttendanceService(firestore: db, storage: MockFirebaseStorage()),
        feeService: FeeService(firestore: db, auth: MockFirebaseAuth(), storage: MockFirebaseStorage()),
        fileService: ParentFileService(parentUserId: father, firestore: db, storage: MockFirebaseStorage()),
      ).load(linked);
      expect([o.financeRestricted, o.financeFailed], [false, false]);
      expect(o.finance!.billsStatus, ParentBillsStatus.failed);
      expect(o.finance!.billsError, startsWith('permission-denied'));
      expect(o.finance!.bills, isNull);
    });

    testWidgets('no bills issued: says so (distinct from an error)', (tester) async {
      await tester.runAsync(() async {
        for (final b in issued) {
          await db.collection('fee_issued_bills').doc(b.id).delete();
        }
        await copies.syncAll(requesterRole: 'admin');
        await applyAccess();
      });
      await pump(tester, dashboard(father));
      await openBills(tester);
      expect(find.byKey(const Key('parent-bills-none')), findsOneWidget);
      expect(find.byKey(const Key('parent-bills-failed')), findsNothing);
    });
  });

  group('access', () {
    testWidgets('missing fee access (Father record without the child in its fee list): no fees or bills, diagnosis says so; nothing is granted', (tester) async {
      await tester.runAsync(() async {
        await applyAccess();
        await db.collection('parent_access').doc(father).update({'financeStudentIds': <String>[]});
      });
      await pump(tester, dashboard(father));
      expect(find.byKey(const Key('parent-fees-restricted')), findsOneWidget);
      expect(find.byKey(const Key('parent-fees-issued-bills')), findsNothing);
      final d = (await tester.runAsync(() => copies.diagnoseParent(father, requesterRole: 'admin')))!;
      expect([d.accessRecord, d.children.single.financeAccess], [true, false]);
      expect((await tester.runAsync(() => db.collection('parent_access').doc(father).get()))!.data()!['financeStudentIds'], isEmpty);
    });

    testWidgets('Guardian: no bills or amounts; the bill check refuses', (tester) async {
      await tester.runAsync(applyAccess);
      await pump(tester, dashboard(guardian));
      expect(find.byKey(const Key('parent-fees-issued-bills')), findsNothing);
      expect(find.byKey(const Key('parent-fees-restricted')), findsOneWidget);
      final refused = await tester.runAsync(() async {
        try {
          await ParentFileService(parentUserId: guardian, firestore: db, storage: MockFirebaseStorage()).feeBillsForStudent('s1');
          return false;
        } on ParentFileAccessDenied {
          return true;
        }
      });
      expect(refused, isTrue);
    });
  });

  test('repeated backfills are idempotent and change no original record', () async {
    final before = await originals(db);
    final first = await copies.syncAllFeeBillsReport();
    final second = await copies.syncAllFeeBillsReport();
    expect([first.originals, first.written, first.unchanged, first.failed], [3, 0, 3, 0]);
    expect([second.written, second.unchanged, second.failed, second.error], [0, 3, 0, '']);
    expect(await originals(db), before);
    final copy = (await db.collection('parent_fee_bills').doc(issued.last.id).get()).data()!;
    expect({...copy}..remove('syncedAt'), parentFeeBill(issued.last.id, (await db.collection('fee_issued_bills').doc(issued.last.id).get()).data()!));
  });
}

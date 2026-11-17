// Parent Dashboard bug fix: supplementary bills issued before the parent
// copies were kept automatically (Phase 0.2 follow-up) were invisible to
// parents. These tests issue three real bills (September, October, November)
// with no refresh hook — as they were issued historically — then check:
// - the parent copies are missing and Check (health) reports them;
// - Rebuild writes exactly the originals' parent-safe copies, idempotently;
// - opening Fee Bill Issuance as an administrator now backfills them
//   automatically (and does nothing for anyone else);
// - new bills, cancellations and replacements keep refreshing;
// - the Father sees all three in Issued Bills (references, months, amounts),
//   separate from Payment History; a Guardian sees no bills or amounts;
// - a parent without an access record yet sees the Issued Bills entry with
//   an explanation instead of nothing.
// Original bills, allocations, receipts and Finance records never change.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:montessori_app/modules/fees/models/fee_receipt_model.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/leave/services/leave_service.dart';
import 'package:montessori_app/modules/mood_checkin/services/mood_checkin_service.dart';
import 'package:montessori_app/modules/parent/data/parent_access_service.dart';
import 'package:montessori_app/modules/parent/data/parent_fee_bill_refresh.dart';
import 'package:montessori_app/modules/parent/data/parent_file_service.dart';
import 'package:montessori_app/modules/parent/data/parent_link_service.dart';
import 'package:montessori_app/modules/parent/data/parent_projection_service.dart';
import 'package:montessori_app/modules/parent/data/parent_projections.dart';
import 'package:montessori_app/modules/parent/data/parent_service.dart';
import 'package:montessori_app/modules/parent/ui/parent_dashboard.dart';

class _UnusedFilePicker extends FilePicker {}

const father = '9000000001';
const guardian = '9000000003';
const school = FeeBillSchool(name: '2D Eduvance Montessori', addressLines: ['12, Lake View Road'], contactLines: ['Phone: 044 1234 5678']);

FeeBillLine line(String month, int rupees, {int adjustment = 0}) => FeeBillLine(
      billingMonth: month,
      description: 'Monthly tuition fee',
      grossPaise: rupees * 100,
      adjustmentType: adjustment > 0 ? FeeBillAdjustmentType.discount : FeeBillAdjustmentType.none,
      adjustmentPaise: adjustment * 100,
      adjustmentReason: adjustment > 0 ? 'Rounded to the amount paid' : '',
    );

/// Every original record (bills with their audit history, allocations,
/// receipts, transactions, assignments, students, Finance).
Future<Map<String, Object?>> originals(FakeFirebaseFirestore db) async {
  final out = <String, Object?>{};
  for (final c in ['fee_issued_bills', 'fee_bill_allocations', 'fee_receipts', 'fee_transactions', 'student_fee_assignments', 'students', 'finance_income', 'finance_ledger', 'finance_accounts']) {
    for (final d in (await db.collection(c).get()).docs) {
      out['$c/${d.id}'] = d.data();
      if (c == 'fee_issued_bills') {
        for (final a in (await d.reference.collection('audit').get()).docs) {
          out['$c/${d.id}/audit/${a.id}'] = a.data();
        }
      }
    }
  }
  return out;
}

void main() {
  late FakeFirebaseFirestore db;
  late FeeBillService bills;
  late FeeReceiptModel receipt;
  late List<FeeIssuedBill> historical;
  late ParentProjectionService copies;

  Future<Map<String, Map<String, dynamic>>> billCopies() async => {for (final d in (await db.collection(ParentFeeBillFields.collection).get()).docs) d.id: d.data()};
  Future<Map<String, dynamic>> original(String id) async => (await db.collection('fee_issued_bills').doc(id).get()).data()!;
  Future<int> missingCopies() async => (await copies.health(requesterRole: 'admin')).firstWhere((h) => h.kind == ParentProjectionKind.feeBills).missing;
  Future<List<FeeIssuedBill>> fatherSees() => ParentFileService(parentUserId: father, firestore: db, storage: MockFirebaseStorage()).feeBillsForStudent('s1');

  setUp(() async {
    FeeBillService.defaultAfterChange = null;
    FeeBillService.defaultBackfill = null;
    db = FakeFirebaseFirestore();
    copies = ParentProjectionService(firestore: db);
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
    await db.collection('students').doc('s1').set({'name': 'Anu Raman', 'admissionNo': 'ADM-101', 'classId': 'c1', 'isActive': true, 'admissionDate': DateTime(2020, 1, 1)});
    await ParentLinkService(firestore: db).saveLinksForStudent(studentId: 's1', parents: const [
      ParentLinkEntry(userId: father, relation: 'Father', name: 'Ravi', phone: father),
      ParentLinkEntry(userId: guardian, relation: 'Guardian', name: 'Kala', phone: guardian),
    ]);
    final access = ParentAccessService(firestore: db);
    await access.apply(await access.preview(requesterRole: 'admin'), requesterRole: 'admin', updatedBy: 'admin');
    await copies.syncAll(requesterRole: 'admin');
    final assignmentId = (await fees.assignFee({
      'studentId': 's1', 'studentName': 'Anu Raman', 'admissionNo': 'ADM-101', 'classId': 'c1', 'className': 'Mont 1',
      'feeStructureId': 'term', 'feeStructureName': 'Term Fees', 'academicYearId': yearId, 'academicYear': '2026-2027',
      'totalFee': 12500, 'discountAmount': 0, 'payableAmount': 12500, 'paidAmount': 0, 'balanceAmount': 12500, 'status': 'unpaid', 'dueDate': DateTime(2026, 11, 30),
    }))!;
    receipt = await fees.collectFee(assignmentId: assignmentId, amount: 12500, paymentDate: DateTime(2026, 11, 5), paymentMode: 'upi', referenceNo: 'UPI-778899', remarks: '');
    // Issued as before the automatic refresh existed: no hook registered.
    historical = await bills.issueBills(
      requesterRole: 'admin', studentId: 's1', receiptId: receipt.id, requestId: 'req-historical', school: school,
      lines: [line('2026-09', 4200), line('2026-10', 4200), line('2026-11', 4200, adjustment: 100)],
    );
  });

  tearDown(() {
    FeeBillService.defaultAfterChange = null;
    FeeBillService.defaultBackfill = null;
  });

  test('root cause: historical bills have no parent copies, so the Father sees none; Check reports all three missing', () async {
    expect(historical.length, 3);
    expect(await billCopies(), isEmpty);
    expect(await fatherSees(), isEmpty);
    expect(await missingCopies(), 3);
  });

  test('Rebuild writes exactly the three parent-safe copies; the Father then sees them; a second Rebuild writes nothing', () async {
    final before = await originals(db);
    final result = await copies.syncAll(requesterRole: 'admin');
    expect(result.written[ParentProjectionKind.feeBills], 3);
    for (final b in historical) {
      expect({...(await billCopies())[b.id]!}..remove('syncedAt'), parentFeeBill(b.id, await original(b.id)));
    }
    final seen = {for (final b in await fatherSees()) b.billNo: b};
    expect(seen.keys.toSet(), {for (final b in historical) b.billNo});
    for (final b in historical) {
      final s = seen[b.billNo]!;
      expect([s.line.billingMonth, s.line.grossPaise, s.line.adjustmentPaise, s.line.netPaise, s.status], [b.line.billingMonth, b.line.grossPaise, b.line.adjustmentPaise, b.line.netPaise, b.status]);
    }
    expect(await missingCopies(), 0);
    final again = await copies.syncAll(requesterRole: 'admin');
    expect([again.totalWritten, again.totalRemoved, again.totalFailed], [0, 0, 0]);
    expect(await originals(db), before, reason: 'no original record changes');
  });

  test('the automatic backfill writes the missing copies for an administrator only, idempotently, originals unchanged', () async {
    registerParentFeeBillRefresh();
    final before = await originals(db);
    await bills.backfillDerivedCopies(requesterRole: 'staff');
    expect(await billCopies(), isEmpty, reason: 'not for staff');
    await bills.backfillDerivedCopies(requesterRole: 'admin');
    expect((await billCopies()).keys.toSet(), {for (final b in historical) b.id});
    final stamps = {for (final e in (await billCopies()).entries) e.key: e.value['syncedAt']};
    await bills.backfillDerivedCopies(requesterRole: 'admin');
    expect({for (final e in (await billCopies()).entries) e.key: e.value['syncedAt']}, stamps, reason: 'nothing rewritten');
    expect(await copies.failures(requesterRole: 'admin'), isEmpty);
    expect(await originals(db), before);
  });

  testWidgets('opening Fee Bill Issuance as an administrator backfills the parent copies', (tester) async {
    registerParentFeeBillRefresh();
    await tester.pumpWidget(ProviderScope(
      overrides: [currentUserProvider.overrideWith((ref) => AppUser(id: 'admin-1', phone: '9000000000', name: 'Admin', role: 'admin', isActive: true))],
      child: MaterialApp(home: FeeBillIssuancePage(service: bills, loadSchool: () async => SchoolSettingsModel.fromMap(kDefaultSchoolId, {'name': 'School'}), loadLogo: (_) async => null)),
    ));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 50 && (await billCopies()).length < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    expect((await tester.runAsync(billCopies))!.length, 3);
  });

  test('after the backfill, new bills, cancellations and replacements keep refreshing automatically', () async {
    registerParentFeeBillRefresh();
    await bills.backfillDerivedCopies(requesterRole: 'admin');
    // Cancel October with a corrected replacement; cancel November outright.
    final replacement = (await bills.cancelBill(requesterRole: 'admin', billId: historical[1].id, reason: 'Amount', replacement: line('2026-10', 4100)))!;
    await bills.cancelBill(requesterRole: 'admin', billId: historical[2].id, reason: 'Not needed');
    final seen = {for (final b in await fatherSees()) b.id: b};
    // Active bills only: September and the October replacement.
    expect(seen.keys.toSet(), {historical[0].id, replacement.id});
    expect(seen.values.every((b) => b.status == FeeBillStatus.issued), isTrue);
    expect(seen[replacement.id]!.replacesBillId, isEmpty, reason: 'no link to the cancelled bill');
    expect(seen[replacement.id]!.line.netPaise, 410000);
    expect((await billCopies()).keys.toSet(), {historical[0].id, replacement.id}, reason: 'no copy of a cancelled bill at all');
    expect((await original(historical[1].id))['status'], FeeBillStatus.cancelled.key, reason: 'kept for administrators');
    expect(await missingCopies(), 0);
    // A brand-new bill (December) appears without any Rebuild.
    final now = await bills.issueBills(requesterRole: 'admin', studentId: 's1', receiptId: receipt.id, requestId: 'req-new', school: school, lines: [line('2026-12', 100)]);
    expect((await fatherSees()).map((b) => b.id), contains(now.single.id));
  });

  group('parent dashboard', () {
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

    Future<void> pump(WidgetTester tester, String parent) async {
      tester.view.physicalSize = const Size(1280, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(dashboard(parent));
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    String screenText(WidgetTester tester) => [
          for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? '',
          for (final t in tester.widgetList<widgets.RichText>(find.byType(widgets.RichText))) t.text.toPlainText(),
        ].join('\n');

    testWidgets('Father: Issued Bills lists all three with references, months and amounts; Payment History stays separate', (tester) async {
      await tester.runAsync(() => copies.syncAll(requesterRole: 'admin'));
      await pump(tester, father);
      await tap(tester, find.byKey(const Key('parent-fees-issued-bills')));
      final dialog = find.byKey(const Key('parent-issued-bills'));
      for (final (b, month, amounts) in [
        (historical[0], 'September 2026', 'Gross ₹4,200.00 · Adjustment ₹0.00 · Net ₹4,200.00'),
        (historical[1], 'October 2026', 'Gross ₹4,200.00 · Adjustment ₹0.00 · Net ₹4,200.00'),
        (historical[2], 'November 2026', 'Gross ₹4,200.00 · Adjustment ₹100.00 · Net ₹4,100.00'),
      ]) {
        expect(find.descendant(of: dialog, matching: find.text(b.billNo)), findsOneWidget);
        expect(find.descendant(of: dialog, matching: find.textContaining('Billing month: $month')), findsOneWidget);
        expect(find.descendant(of: dialog, matching: find.text(amounts)), findsNWidgets(b == historical[2] ? 1 : 2) , reason: b.billNo);
      }
      expect(find.descendant(of: dialog, matching: find.textContaining('UPI-778899')), findsNothing, reason: 'no payment details in bills');
      await tap(tester, find.byIcon(Icons.close).last);

      await tap(tester, find.byKey(const Key('parent-fees-payment-history')));
      final payments = find.byKey(const Key('parent-payment-history'));
      expect(find.descendant(of: payments, matching: find.textContaining('UPI-778899')), findsOneWidget);
      for (final b in historical) {
        expect(find.descendant(of: payments, matching: find.textContaining(b.billNo)), findsNothing, reason: 'no bill in payments');
      }
      expect(screenText(tester), isNot(contains('receipt.pdf')));
    });

    testWidgets('Guardian: no Issued Bills, payments or amounts, even with the copies present', (tester) async {
      await tester.runAsync(() => copies.syncAll(requesterRole: 'admin'));
      await pump(tester, guardian);
      expect(find.byKey(const Key('parent-fees-issued-bills')), findsNothing);
      expect(find.byKey(const Key('parent-fees-payment-history')), findsNothing);
      expect(find.byKey(const Key('parent-fees-restricted')), findsOneWidget);
      expect(screenText(tester), isNot(contains('₹')));
      final refused = await tester.runAsync(() async {
        try {
          await ParentFileService(parentUserId: guardian, firestore: db, storage: MockFirebaseStorage()).feeBillsForStudent('s1');
          return false;
        } on ParentFileAccessDenied {
          return true;
        }
      });
      expect(refused, isTrue, reason: 'the bill check itself refuses a Guardian');
    });

    testWidgets('a parent without an access record yet: the Issued Bills entry is shown and explains, instead of disappearing', (tester) async {
      await tester.runAsync(() async {
        await copies.syncAll(requesterRole: 'admin');
        await db.collection('parent_access').doc(father).delete();
      });
      await pump(tester, father);
      await tap(tester, find.byKey(const Key('parent-fees-issued-bills')));
      expect(find.byKey(const Key('parent-bills-access-not-configured')), findsOneWidget);
    });
  });
}

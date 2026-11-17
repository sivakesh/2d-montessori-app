// Parent Dashboard: Issued Bills show active supplementary bills only, and
// each opens its details in the app. Bills are issued and cancelled through
// the real Fee Bill Issuance service; the parent copies are refreshed by the
// registered hook (as in the app). Cancelled bills get no parent copy, so
// their references, cancellation and replacement history never reach a
// parent; administrators still see them in Fee Bill Issuance. No download,
// payment, edit or cancel action is offered to parents.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
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
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_pdf.dart';
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
const school = FeeBillSchool(name: '2D Eduvance Montessori', addressLines: ['12, Lake View Road'], contactLines: ['044 1234 5678']);

FeeBillLine line(String month, int rupees, {int adjustment = 0}) => FeeBillLine(
      billingMonth: month,
      description: 'Monthly tuition fee',
      grossPaise: rupees * 100,
      adjustmentType: adjustment > 0 ? FeeBillAdjustmentType.discount : FeeBillAdjustmentType.none,
      adjustmentPaise: adjustment * 100,
      adjustmentReason: adjustment > 0 ? 'Rounded to the amount paid' : '',
    );

void main() {
  late FakeFirebaseFirestore db;
  late FeeBillService bills;
  late FeeReceiptModel receipt;
  late List<FeeIssuedBill> issued;

  setUp(() async {
    registerParentFeeBillRefresh();
    db = FakeFirebaseFirestore();
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
    final assignmentId = (await fees.assignFee({
      'studentId': 's1', 'studentName': 'Anu Raman', 'admissionNo': 'ADM-101', 'classId': 'c1', 'className': 'Mont 1',
      'feeStructureId': 'term', 'feeStructureName': 'Term Fees', 'academicYearId': yearId, 'academicYear': '2026-2027',
      'totalFee': 12500, 'discountAmount': 0, 'payableAmount': 12500, 'paidAmount': 0, 'balanceAmount': 12500, 'status': 'unpaid', 'dueDate': DateTime(2026, 11, 30),
    }))!;
    receipt = await fees.collectFee(assignmentId: assignmentId, amount: 12500, paymentDate: DateTime(2026, 11, 5), paymentMode: 'upi', referenceNo: 'UPI-778899', remarks: '');
    await ParentProjectionService(firestore: db).syncAll(requesterRole: 'admin');
    issued = await bills.issueBills(
      requesterRole: 'admin', studentId: 's1', receiptId: receipt.id, requestId: 'req-1', school: school,
      lines: [line('2026-09', 4200), line('2026-10', 4200), line('2026-11', 4200, adjustment: 100)],
    );
  });

  tearDown(() {
    FeeBillService.defaultAfterChange = null;
    FeeBillService.defaultBackfill = null;
  });

  /// Cancels October (replaced by a corrected one) and November (outright).
  Future<FeeIssuedBill> cancelSome() async {
    final replacement = (await bills.cancelBill(requesterRole: 'admin', billId: issued[1].id, reason: 'Wrong amount', replacement: line('2026-10', 4000)))!;
    await bills.cancelBill(requesterRole: 'admin', billId: issued[2].id, reason: 'Not needed');
    return replacement;
  }

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

  Future<void> pump(WidgetTester tester, Widget w, {Size size = const Size(1280, 2400)}) async {
    tester.view.physicalSize = size;
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

  Finder listDialog() => find.byKey(const Key('parent-issued-bills'));
  Finder detail() => find.byKey(const Key('parent-bill-detail'));
  Finder card(String billId) => find.byKey(Key('parent-bill-$billId'));
  Future<void> closeTop(WidgetTester tester) => tap(tester, find.byIcon(Icons.close).last);

  String screenText(WidgetTester tester) => [
        for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? '',
        for (final t in tester.widgetList<widgets.RichText>(find.byType(widgets.RichText))) t.text.toPlainText(),
      ].join('\n');

  Future<void> openList(WidgetTester tester) => tap(tester, find.byKey(const Key('parent-fees-issued-bills')));

  group('active bills only', () {
    testWidgets('three active bills are listed, each card shows it can be opened; the button counts them', (tester) async {
      await pump(tester, dashboard(father));
      expect(find.text('Issued bills (3)'), findsOneWidget);
      await openList(tester);
      for (final b in issued) {
        expect(find.descendant(of: card(b.id), matching: find.text(b.billNo)), findsOneWidget);
        expect(find.descendant(of: card(b.id), matching: find.byIcon(Icons.chevron_right)), findsOneWidget);
      }
    });

    testWidgets('cancelled bills are left out (no reference, date or replacement history); the replacement shows on its own', (tester) async {
      final replacement = (await tester.runAsync(cancelSome))!;
      await pump(tester, dashboard(father));
      expect(find.text('Issued bills (2)'), findsOneWidget, reason: 'counts active bills only');
      await openList(tester);
      expect(card(issued[0].id), findsOneWidget);
      expect(card(replacement.id), findsOneWidget);
      expect(card(issued[1].id), findsNothing);
      expect(card(issued[2].id), findsNothing);
      final text = screenText(tester);
      expect(text, isNot(anyOf(contains(issued[1].billNo), contains(issued[2].billNo), contains('Cancelled'), contains('Replaces'), contains('replaced by'), contains('Not needed'))));
    });

    test('filtering is in the data layer: no parent copy of a cancelled bill, and the parent read returns active bills only', () async {
      final replacement = await cancelSome();
      final copies = {for (final d in (await db.collection(ParentFeeBillFields.collection).get()).docs) d.id: d.data()};
      expect(copies.keys.toSet(), {issued[0].id, replacement.id});
      expect(copies.toString(), isNot(anyOf(contains(issued[1].billNo), contains(issued[2].billNo), contains('cancellation'))));
      final read = await ParentFileService(parentUserId: father, firestore: db, storage: MockFirebaseStorage()).feeBillsForStudent('s1');
      expect({for (final b in read) b.id}, {issued[0].id, replacement.id});
      expect(read.every((b) => b.status == FeeBillStatus.issued), isTrue);
    });

    test('a stale copy of a cancelled bill (written before this rule) is still left out of the parent read', () async {
      await db.collection(ParentFeeBillFields.collection).doc('stale').set({
        'billId': 'stale', 'studentId': 's1', 'billNo': 'OLD-000001', 'status': 'cancelled', 'cancellation': {'reason': 'x'},
      });
      final read = await ParentFileService(parentUserId: father, firestore: db, storage: MockFirebaseStorage()).feeBillsForStudent('s1');
      expect(read.map((b) => b.billNo), isNot(contains('OLD-000001')));
    });

    testWidgets('no active bills: "No supplementary bills have been issued yet."', (tester) async {
      await tester.runAsync(() async {
        for (final b in issued) {
          await bills.cancelBill(requesterRole: 'admin', billId: b.id, reason: 'Withdrawn');
        }
      });
      await pump(tester, dashboard(father));
      expect(find.text('Issued bills (0)'), findsOneWidget);
      await openList(tester);
      expect(find.text('No supplementary bills have been issued yet.'), findsOneWidget);
    });
  });

  group('bill details', () {
    testWidgets('tapping a card opens its details, matching the parent-safe copy; closing returns to the list', (tester) async {
      await pump(tester, dashboard(father));
      await openList(tester);
      await tap(tester, card(issued[2].id));
      final d = detail();
      expect(d, findsOneWidget);
      final copy = FeeIssuedBill.fromMap(issued[2].id, (await tester.runAsync(() => db.collection(ParentFeeBillFields.collection).doc(issued[2].id).get()))!.data()!);
      for (final t in [
        'Supplementary bill document for a payment already collected. This bill is not a payment receipt.',
        copy.billNo, 'Anu Raman', 'November 2026', DateFormat('d MMM yyyy').format(copy.documentDate!),
        // The bill PDF's own rows and amounts (FeeBillPdf).
        FeeBillPdf.money(copy.line.grossPaise), '- ${FeeBillPdf.money(copy.line.adjustmentPaise)}',
        FeeBillPdf.netLabel(copy), copy.payment.receiptNo, 'Issued',
      ]) {
        expect(find.descendant(of: d, matching: find.text(t)), findsOneWidget, reason: t);
      }
      expect([copy.line.grossPaise, copy.line.adjustmentPaise, copy.line.netPaise, copy.payment.receiptNo], [420000, 10000, 410000, receipt.receiptNo]);
      // Download PDF only: no payment, edit or cancel action.
      for (final label in ['Pay', 'Edit', 'Cancel bill']) {
        expect(find.descendant(of: d, matching: find.text(label)), findsNothing);
      }
      expect(find.descendant(of: d, matching: find.text('Download PDF')), findsOneWidget);

      await closeTop(tester);
      expect(detail(), findsNothing);
      expect(listDialog(), findsOneWidget, reason: 'back on the Issued Bills list');
    });

    testWidgets('each bill opens on its own (no adjustment line when there is none)', (tester) async {
      await pump(tester, dashboard(father));
      await openList(tester);
      for (final (b, month, net) in [(issued[0], 'September 2026', 'Rs. 4,200.00'), (issued[1], 'October 2026', 'Rs. 4,200.00'), (issued[2], 'November 2026', 'Rs. 4,100.00')]) {
        await tap(tester, card(b.id));
        expect(find.descendant(of: detail(), matching: find.text(b.billNo)), findsOneWidget);
        expect(find.descendant(of: detail(), matching: find.text(month)), findsOneWidget);
        expect(find.descendant(of: find.byKey(const Key('parent-bill-detail-net')), matching: find.text(net)), findsOneWidget);
        expect(find.descendant(of: detail(), matching: find.textContaining('Bill-only Adjustment')), b == issued[2] ? findsOneWidget : findsNothing);
        await closeTop(tester);
      }
    });

    for (final size in [const Size(375, 640), const Size(1280, 800)]) {
      testWidgets('${size.width.toInt()} px: the list scrolls to the last bill, which opens; no overflow', (tester) async {
        await pump(tester, dashboard(father), size: size);
        await openList(tester);
        await tap(tester, card(issued.last.id));
        expect(find.descendant(of: detail(), matching: find.text(issued.last.billNo)), findsOneWidget);
        expect(tester.takeException(), isNull);
        await closeTop(tester);
        expect(listDialog(), findsOneWidget);
      });
    }
  });

  group('permissions and separation', () {
    testWidgets('Guardian: no Issued Bills entry and no amounts; the bill read refuses', (tester) async {
      await pump(tester, dashboard(guardian));
      expect(find.byKey(const Key('parent-fees-issued-bills')), findsNothing);
      expect(screenText(tester), isNot(contains('₹')));
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

    testWidgets('Payment History stays separate and unchanged by bills', (tester) async {
      await tester.runAsync(cancelSome);
      await pump(tester, dashboard(father));
      await tap(tester, find.byKey(const Key('parent-fees-payment-history')));
      final payments = find.byKey(const Key('parent-payment-history'));
      expect(find.descendant(of: payments, matching: find.textContaining('UPI-778899')), findsOneWidget);
      expect(find.descendant(of: payments, matching: find.textContaining('₹12,500.00')), findsOneWidget);
      for (final b in issued) {
        expect(find.descendant(of: payments, matching: find.textContaining(b.billNo)), findsNothing);
      }
    });

    testWidgets('the administrator still sees active and cancelled bills in Fee Bill Issuance', (tester) async {
      final replacement = (await tester.runAsync(cancelSome))!;
      await pump(
        tester,
        ProviderScope(
          overrides: [currentUserProvider.overrideWith((ref) => AppUser(id: 'admin-1', phone: '9000000000', name: 'Admin', role: 'admin', isActive: true))],
          child: MaterialApp(home: FeeBillIssuancePage(service: bills, loadSchool: () async => SchoolSettingsModel.fromMap(kDefaultSchoolId, {'name': 'School'}), loadLogo: (_) async => null)),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      for (final no in [issued[0].billNo, issued[1].billNo, issued[2].billNo, replacement.billNo]) {
        expect(find.byKey(Key('fee-bills-row-$no')), findsOneWidget, reason: no);
      }
      final all = (await tester.runAsync(bills.getBills))!;
      expect(all.where((b) => b.status == FeeBillStatus.cancelled).length, 2);
      expect((await tester.runAsync(() => db.collection('fee_issued_bills').doc(issued[1].id).collection('audit').get()))!.docs, isNotEmpty);
    });
  });

  test('cancellation refresh never touches payments, receipts or fee balances', () async {
    Future<Map<String, Object?>> money() async => {
          for (final c in ['fee_receipts', 'fee_transactions', 'student_fee_assignments', 'finance_income', 'finance_ledger'])
            for (final d in (await db.collection(c).get()).docs) '$c/${d.id}': d.data(),
        };
    final before = await money();
    await cancelSome();
    expect(await money(), before);
  });
}

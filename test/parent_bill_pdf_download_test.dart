// Parent Dashboard: Issued Bills — details and the bill PDF download. The
// parent downloads the very document Fee Bill Issuance produces: the
// unchanged FeeBillPdf.build from the bill's snapshot (its parent-safe
// copy), under FeeBillPdf.fileName, through the same save path. Access is
// re-checked from stored records (the bill is re-read by id; its own
// student must be one the parent is Father or Mother of). Nothing is
// written by viewing or downloading. Browser download itself is verified
// manually (see the report): here the saver is a test seam.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_models.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_pdf.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_service.dart';
import 'package:montessori_app/modules/fees/models/amount_in_words.dart';
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
import 'package:montessori_app/modules/parent/data/parent_service.dart';
import 'package:montessori_app/modules/parent/ui/parent_dashboard.dart';

class _UnusedFilePicker extends FilePicker {}

const father = '9000000001';
const mother = '9000000002';
const guardian = '9000000003';
const otherFather = '9000000008';
const gstin = '33ABCDE1234F1Z5';
const school = FeeBillSchool(
  name: '2D Montessori',
  addressLines: ['12, Lake View Road', 'Anna Nagar, Chennai - 600040'],
  contactLines: ['Phone: 044 1234 5678'],
  gstin: gstin,
  logoUrl: 'https://firebasestorage.googleapis.com/v0/b/b/o/school_settings%2Fdefault_school%2Flogo.png?alt=media&token=SECRET',
);

FeeBillLine line(String month, int rupees, {int adjustment = 0}) => FeeBillLine(
      billingMonth: month,
      description: 'Monthly tuition fee',
      grossPaise: rupees * 100,
      adjustmentType: adjustment > 0 ? FeeBillAdjustmentType.discount : FeeBillAdjustmentType.none,
      adjustmentPaise: adjustment * 100,
      adjustmentReason: adjustment > 0 ? 'Rounded to the amount paid' : '',
    );

/// The words a PDF made by the `pdf` package draws, in order (as in
/// fee_bill_issuance_test.dart).
String pdfText(Uint8List bytes) {
  final raw = latin1.decode(bytes);
  final words = <String>[];
  for (final m in RegExp(r'stream\r?\n').allMatches(raw)) {
    final end = raw.indexOf('endstream', m.end);
    if (end < 0) continue;
    try {
      final content = latin1.decode(ZLibDecoder().convert(bytes.sublist(m.end, end)));
      for (final w in RegExp(r'\[\((.*?)\)\]TJ').allMatches(content)) {
        words.add(w.group(1)!.replaceAllMapped(RegExp(r'\\([()\\])'), (x) => x.group(1)!));
      }
    } catch (_) {}
  }
  return words.join(' ');
}

void main() {
  late FakeFirebaseFirestore db;
  late FeeBillService bills;
  late FeeReceiptModel receipt;
  late List<FeeIssuedBill> issued;
  late FeeIssuedBill otherChildBill;

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
    for (final (id, name) in [('s1', 'Anu Raman'), ('s2', 'Bala Kumar')]) {
      await db.collection('students').doc(id).set({'name': name, 'admissionNo': 'ADM-$id', 'classId': 'c1', 'isActive': true, 'admissionDate': DateTime(2020, 1, 1)});
    }
    final links = ParentLinkService(firestore: db);
    await links.saveLinksForStudent(studentId: 's1', parents: const [
      ParentLinkEntry(userId: father, relation: 'Father', name: 'Ravi Raman', phone: father),
      ParentLinkEntry(userId: mother, relation: 'Mother', name: 'Meena Raman', phone: mother),
      ParentLinkEntry(userId: guardian, relation: 'Guardian', name: 'Kala', phone: guardian),
    ]);
    await links.saveLinksForStudent(studentId: 's2', parents: const [ParentLinkEntry(userId: otherFather, relation: 'Father', name: 'Kumar', phone: otherFather)]);
    final access = ParentAccessService(firestore: db);
    await access.apply(await access.preview(requesterRole: 'admin'), requesterRole: 'admin', updatedBy: 'admin');

    Future<FeeReceiptModel> collect(String studentId, String name, String mode) async {
      final a = (await fees.assignFee({
        'studentId': studentId, 'studentName': name, 'admissionNo': 'ADM-$studentId', 'classId': 'c1', 'className': 'Mont 1',
        'feeStructureId': 'term', 'feeStructureName': 'Term Fees', 'academicYearId': yearId, 'academicYear': '2026-2027',
        'totalFee': 12500, 'discountAmount': 0, 'payableAmount': 12500, 'paidAmount': 0, 'balanceAmount': 12500, 'status': 'unpaid', 'dueDate': DateTime(2026, 11, 30),
      }))!;
      return fees.collectFee(assignmentId: a, amount: 12500, paymentDate: DateTime(2026, 11, 5), paymentMode: mode, referenceNo: 'UPI-$studentId', remarks: '');
    }

    receipt = await collect('s1', 'Anu Raman', 'upi');
    final other = await collect('s2', 'Bala Kumar', 'cash');
    await ParentProjectionService(firestore: db).syncAll(requesterRole: 'admin');
    issued = await bills.issueBills(
      requesterRole: 'admin', studentId: 's1', receiptId: receipt.id, requestId: 'req-1', school: school, amountIncludesGst: true,
      lines: [line('2026-09', 4200), line('2026-10', 4200), line('2026-11', 4200, adjustment: 100)],
    );
    otherChildBill = (await bills.issueBills(requesterRole: 'admin', studentId: 's2', receiptId: other.id, requestId: 'req-2', school: school, lines: [line('2026-09', 4200)])).single;
  });

  tearDown(() {
    FeeBillService.defaultAfterChange = null;
    FeeBillService.defaultBackfill = null;
  });

  ParentFileService files(String parent, List<(Uint8List, String)> saved) =>
      ParentFileService(parentUserId: parent, firestore: db, storage: MockFirebaseStorage(), save: (bytes, name) async => saved.add((bytes, name)));

  /// What Fee Bill Issuance's administrator download builds for [b] (its
  /// own bill record, the app logo).
  Future<Uint8List> adminPdf(FeeIssuedBill b) async => FeeBillPdf.build((await bills.getBill(b.id))!);

  group('the PDF', () {
    test('the parent download is the administrator\'s document for every bill (same text, same file name)', () async {
      final saved = <(Uint8List, String)>[];
      for (final b in issued) {
        await files(father, saved).downloadFeeBillById(b.id);
        expect(saved.last.$2, FeeBillPdf.fileName(b));
        expect(saved.last.$2, '${b.billNo}.pdf');
        expect(pdfText(saved.last.$1), pdfText(await adminPdf(b)), reason: b.billNo);
      }
    });

    test('the bill with an adjustment prints every field from the snapshot', () async {
      final saved = <(Uint8List, String)>[];
      final b = issued[2];
      await files(father, saved).downloadFeeBillById(b.id);
      final text = pdfText(saved.single.$1);
      final issueDate = DateFormat('dd MMM yyyy').format(b.documentDate!);
      for (final t in [
        'FEE BILL', b.billNo, issueDate, '2D Montessori', '12, Lake View Road', 'Phone: 044 1234 5678', gstin,
        'Ravi Raman', 'Anu Raman', 'ADM-s1', 'Mont 1', 'November 2026', 'Monthly tuition fee',
        'Rs. 4,200.00', '- Rs. 100.00', 'Rounded to the amount paid', receipt.receiptNo,
        'Rs. 4,100.00 (GST Included)', IndianAmount.words(410000), FeeBillPdf.footer,
      ]) {
        expect(text, contains(t), reason: t);
      }
      expect(text, isNot(anyOf(contains('admin-1'), contains('req-1'), contains('SECRET'))));
    });

    test('Mother can download; Guardian, an unlinked parent and another child\'s Father cannot; a cancelled bill cannot', () async {
      final saved = <(Uint8List, String)>[];
      await files(mother, saved).downloadFeeBillById(issued[0].id);
      expect(saved.single.$2, '${issued[0].billNo}.pdf');
      for (final p in [guardian, '9000000077', otherFather]) {
        await expectLater(files(p, saved).downloadFeeBillById(issued[0].id), throwsA(isA<ParentFileAccessDenied>()), reason: p);
      }
      // A bill of a child this Father isn't linked to, by its id.
      await expectLater(files(father, saved).downloadFeeBillById(otherChildBill.id), throwsA(isA<ParentFileAccessDenied>()));
      // A bill id is not proof of access: the stored copy's own student decides.
      await expectLater(files(father, saved).downloadFeeBill(FeeIssuedBill.fromMap(otherChildBill.id, {'studentId': 's1', 'billNo': 'X'})), throwsA(isA<ParentFileAccessDenied>()));
      await bills.cancelBill(requesterRole: 'admin', billId: issued[1].id, reason: 'Wrong');
      await expectLater(files(father, saved).downloadFeeBillById(issued[1].id), throwsA(isA<ParentFileAccessDenied>()));
      expect(saved.length, 1);
    });

    test('downloading writes nothing: bills, allocations, receipts, payments, fees and Finance unchanged', () async {
      Future<Map<String, Object?>> records() async => {
            for (final c in ['fee_issued_bills', 'fee_bill_allocations', 'fee_receipts', 'fee_transactions', 'student_fee_assignments', 'finance_income', 'finance_ledger', 'parent_fee_bills'])
              for (final d in (await db.collection(c).get()).docs) '$c/${d.id}': d.data(),
          };
      final before = await records();
      final saved = <(Uint8List, String)>[];
      for (final b in issued) {
        await files(father, saved).downloadFeeBillById(b.id);
      }
      expect(await records(), before);
    });
  });

  group('in the dashboard', () {
    Widget dashboard(String parent, ParentFileSaver saver) => ProviderScope(
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
              fileSaver: saver,
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

    /// Lets the PDF build (real async work) finish.
    Future<void> settleDownload(WidgetTester tester) async {
      for (var i = 0; i < 200 && find.byKey(const Key('parent-bill-download-message')).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }

    Future<void> openBill(WidgetTester tester, FeeIssuedBill b) async {
      await tap(tester, find.byKey(const Key('parent-fees-issued-bills')));
      await tap(tester, find.byKey(Key('parent-bill-${b.id}')));
    }

    testWidgets('details show the PDF\'s fields (parent name, admission no., class, particulars, GST) and Download PDF saves the bill', (tester) async {
      final saved = <(Uint8List, String)>[];
      final release = Completer<void>();
      await pump(tester, dashboard(father, (bytes, name) async {
        await release.future;
        saved.add((bytes, name));
      }));
      final b = issued[2];
      await openBill(tester, b);
      final d = find.byKey(const Key('parent-bill-detail'));
      for (final t in [
        'Supplementary bill document for a payment already collected. This bill is not a payment receipt.',
        b.billNo, FeeBillPdf.studentRows(b).first.$1, 'Ravi Raman', 'Anu Raman', 'ADM-s1', 'Mont 1', 'November 2026', 'Monthly tuition fee',
        'Rs. 4,200.00', '- Rs. 100.00', receipt.receiptNo, 'Rs. 4,100.00 (GST Included)', IndianAmount.words(410000), gstin, 'Issued',
      ]) {
        expect(find.descendant(of: d, matching: find.text(t)), findsWidgets, reason: t);
      }
      await tester.ensureVisible(find.byKey(const Key('parent-bill-download')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('parent-bill-download')));
      await tester.pump();
      expect(find.text('Preparing PDF…'), findsOneWidget, reason: 'loading feedback');
      expect(tester.widget<FilledButton>(find.byKey(const Key('parent-bill-download'))).onPressed, isNull, reason: 'no second tap while preparing');
      release.complete();
      await settleDownload(tester);
      expect(saved.single.$2, '${b.billNo}.pdf');
      expect(pdfText(saved.single.$1), pdfText((await tester.runAsync(() => adminPdf(b)))!));
      expect(find.text('PDF of ${b.billNo} downloaded.'), findsOneWidget);
    });

    testWidgets('each bill downloads its own PDF', (tester) async {
      final saved = <(Uint8List, String)>[];
      await pump(tester, dashboard(father, (bytes, name) async => saved.add((bytes, name))));
      for (final b in issued) {
        await openBill(tester, b);
        await tester.ensureVisible(find.byKey(const Key('parent-bill-download')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('parent-bill-download')));
        await settleDownload(tester);
        await tap(tester, find.byIcon(Icons.close).last);
        await tap(tester, find.byIcon(Icons.close).last);
      }
      expect(saved.map((s) => s.$2), [for (final b in issued) '${b.billNo}.pdf']);
    });

    testWidgets('a failed download shows an actionable error, and trying again works', (tester) async {
      var fail = true;
      final saved = <(Uint8List, String)>[];
      await pump(tester, dashboard(father, (bytes, name) async {
        if (fail) throw StateError('Download blocked');
        saved.add((bytes, name));
      }));
      await openBill(tester, issued[0]);
      await tester.ensureVisible(find.byKey(const Key('parent-bill-download')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('parent-bill-download')));
      await settleDownload(tester);
      final message = tester.widget<Text>(find.byKey(const Key('parent-bill-download-message'))).data!;
      expect(message, allOf(contains("Couldn't create the PDF"), contains('try again'), contains('Download blocked')));
      expect(tester.widget<FilledButton>(find.byKey(const Key('parent-bill-download'))).onPressed, isNotNull, reason: 'can retry');
      fail = false;
      await tester.ensureVisible(find.byKey(const Key('parent-bill-download')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('parent-bill-download')));
      await tester.pump();
      for (var i = 0; i < 200 && saved.isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(saved.single.$2, '${issued[0].billNo}.pdf');
    });

    testWidgets('mobile width: details and Download PDF lay out without overflow', (tester) async {
      await pump(tester, dashboard(mother, (_, _) async {}), size: const Size(360, 780));
      await openBill(tester, issued[2]);
      expect(find.byKey(const Key('parent-bill-download')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Guardian: no bills, details or download; no receipt PDF link anywhere', (tester) async {
      await pump(tester, dashboard(guardian, (_, _) async => fail('nothing may be saved')));
      expect(find.byKey(const Key('parent-fees-issued-bills')), findsNothing);
      expect(find.byKey(const Key('parent-bill-download')), findsNothing);
      final text = [
        for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? '',
        for (final t in tester.widgetList<widgets.RichText>(find.byType(widgets.RichText))) t.text.toPlainText(),
      ].join('\n');
      expect(text, isNot(anyOf(contains('₹'), contains('Rs.'), contains('.pdf'), contains('http'))));
    });

    testWidgets('Payment History stays separate: payment references, no bills or downloads', (tester) async {
      await pump(tester, dashboard(father, (_, _) async {}));
      await tap(tester, find.byKey(const Key('parent-fees-payment-history')));
      final p = find.byKey(const Key('parent-payment-history'));
      expect(find.descendant(of: p, matching: find.textContaining('UPI-s1')), findsOneWidget);
      expect(find.descendant(of: p, matching: find.textContaining(issued[0].billNo)), findsNothing);
      expect(find.descendant(of: p, matching: find.byKey(const Key('parent-bill-download'))), findsNothing);
    });
  });
}

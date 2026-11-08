// Fees -> Reports: the Student Monthly Fee Statement and the All Students –
// Fee Collection and Outstanding Report (screen and PDF from the same
// FeeReport.build result). Payments are listed under the fee month they
// paid, with their own payment dates; voided receipts are marked and never
// counted; months without payments show "Not paid"; Term / One-time and
// "Month not recorded" are separate; unlinked receipts are never attached.
// Every student is included, with or without fees. Read-only. Synthetic
// test data only.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/academic_year_model.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/settings/providers/academic_year_provider.dart';
import 'package:montessori_app/modules/admin/settings/providers/school_identity_provider.dart';
import 'package:montessori_app/modules/fees/models/fee_component_model.dart';
import 'package:montessori_app/modules/fees/models/fee_list_filter.dart';
import 'package:montessori_app/modules/fees/models/fee_report.dart';
import 'package:montessori_app/modules/fees/services/fee_report_pdf.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/admin_fees_screen.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_receipt_view_dialog.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';

import 'support/buffered_transaction_firestore.dart';

/// The words of an uncompressed PDF's text (the PDF writes each word as its
/// own string), so a phrase is found as its words in order.
List<String> _pdfWords(Uint8List bytes) =>
    [for (final m in RegExp(r'\(((?:[^()\\]|\\.)*)\)').allMatches(latin1.decode(bytes))) m.group(1)!.replaceAll(r'\(', '(').replaceAll(r'\)', ')')];

bool _hasPhrase(List<String> words, String phrase) {
  final want = phrase.split(' ');
  for (var i = 0; i + want.length <= words.length; i++) {
    var ok = true;
    for (var j = 0; j < want.length && ok; j++) {
      ok = words[i + j] == want[j];
    }
    if (ok) return true;
  }
  return false;
}

int _phraseCount(List<String> words, String phrase) {
  final want = phrase.split(' ');
  var n = 0;
  for (var i = 0; i + want.length <= words.length; i++) {
    var ok = true;
    for (var j = 0; j < want.length && ok; j++) {
      ok = words[i + j] == want[j];
    }
    if (ok) n++;
  }
  return n;
}

int _pages(Uint8List bytes) => RegExp(r'/Type\s*/Page(?![s\w])').allMatches(latin1.decode(bytes)).length;

void main() {
  late BufferedTransactionFirestore firestore;
  late FeeService fees;
  late AcademicYearModel year;
  late Map<String, String> ids;

  Future<String> assign(String student, String structure, String name, double total, {String? month, double discount = 0}) async =>
      (await fees.assignFee({
        'studentId': student, 'studentName': student, 'admissionNo': 'ADM-$student', 'classId': 'c1', 'className': 'Mont 1',
        'feeStructureId': structure, 'feeStructureName': name, 'academicYearId': year.id, 'academicYear': year.name,
        'totalFee': total, 'discountAmount': discount, 'payableAmount': total - discount, 'paidAmount': 0, 'balanceAmount': total - discount, 'status': 'unpaid',
        'feeMonth': ?month, 'dueDate': DateTime(2026, 6, 10),
      }))!;
  Future<String> collect(String id, double amount, DateTime on) async =>
      (await fees.collectFee(assignmentId: id, amount: amount, paymentDate: on, paymentMode: 'cash', referenceNo: '', remarks: '')).id;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    final auth = MockFirebaseAuth();
    final finance = FinanceService(firestore: firestore, auth: auth);
    await finance.ensureDefaults();
    fees = FeeService(firestore: firestore, auth: auth, storage: MockFirebaseStorage(), financeService: finance, clock: () => DateTime(2026, 11, 7));
    final years = AcademicYearService(firestore: firestore);
    final yearId = await years.createAcademicYear(schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2026-2027',
        startDate: DateTime(2026, 6, 1), endDate: DateTime(2027, 5, 31), createdBy: 'admin-1', setAsCurrent: true);
    year = (await years.getAllAcademicYears(schoolId: kDefaultSchoolId)).singleWhere((y) => y.id == yearId);
    await firestore.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
    for (final (id, name, active, admitted) in [
      ('s1', 'Anu', true, DateTime(2026, 6, 1)),
      ('s2', 'Bala', true, DateTime(2026, 6, 1)),
      ('s3', 'Chitra', true, DateTime(2026, 6, 1)),
      ('s4', 'Dev', true, null),
      ('s5', 'Esha', false, DateTime(2026, 6, 1)),
    ]) {
      await firestore.collection('students').doc(id).set({'name': name, 'admissionNo': 'ADM-$id', 'classId': 'c1', 'isActive': active, 'admissionDate': ?admitted});
    }
    Future<void> structure(String id, String name, String freq, double amount) => firestore.collection('fee_structures').doc(id).set({
          'name': name, 'description': '', 'totalAmount': amount, 'academicYear': year.name, 'academicYearId': year.id, 'isActive': true, 'createdBy': 't',
          'createdAt': DateTime(2026, 1, 1),
          'components': [FeeComponentModel(name: name, amount: amount, frequency: freq, termName: freq == 'term' ? 'Term 1' : null, isOptional: false).toMap()],
        });
    await structure('care', 'Day Care', 'monthly', 2500);
    await structure('term', 'Term Fees', 'term', 8000);

    ids = {
      'anu-jun': await assign('s1', 'care', 'Day Care', 2500, month: '2026-06'),
      'anu-jul': await assign('s1', 'care', 'Day Care', 2500, month: '2026-07'),
      'anu-aug': await assign('s1', 'care', 'Day Care', 2500, month: '2026-08'),
      'anu-term': await assign('s1', 'term', 'Term Fees', 8000),
      'bala-jun': await assign('s2', 'care', 'Day Care', 2500, month: '2026-06', discount: 500),
      'chitra-jun': await assign('s3', 'care', 'Day Care', 2500, month: '2026-06'),
      'esha-jun': await assign('s5', 'care', 'Day Care', 2500, month: '2026-06'),
    };
    ids['r1'] = await collect(ids['anu-jun']!, 1500, DateTime(2026, 6, 5));
    ids['r2'] = await collect(ids['anu-jun']!, 1000, DateTime(2026, 6, 12));
    ids['r3'] = await collect(ids['anu-aug']!, 1000, DateTime(2026, 9, 5)); // August's fee, paid in September
    ids['r4'] = await collect(ids['anu-term']!, 3000, DateTime(2026, 7, 1));
    ids['r5'] = await collect(ids['anu-term']!, 2000, DateTime(2026, 7, 2));
    await fees.voidReceipt(ids['r5']!);
    ids['r6'] = await collect(ids['bala-jun']!, 2000, DateTime(2026, 6, 3));
    // An older Monthly assignment with no month recorded, and a receipt whose assignment is gone.
    await firestore.collection('student_fee_assignments').doc('chitra-legacy').set({
      'studentId': 's3', 'studentName': 'Chitra', 'classId': 'c1', 'feeStructureId': 'care', 'feeStructureName': 'Day Care', 'academicYearId': year.id,
      'academicYear': year.name, 'totalFee': 2500, 'discountAmount': 0, 'payableAmount': 2500, 'paidAmount': 0, 'balanceAmount': 2500, 'status': 'unpaid',
    });
    await firestore.collection('fee_receipts').doc('orphan').set({
      'receiptNo': 'RCPT-ORPHAN', 'assignmentId': 'gone', 'studentId': 's1', 'studentName': 'Anu', 'amount': 700, 'paymentMode': 'upi',
      'paymentDate': DateTime(2026, 6, 20), 'feeStructureName': 'Old Fee',
    });
  });

  FeeListFilter base({String? month, String? classId, String? studentId}) =>
      FeeListFilter(year: year, classId: classId, studentId: studentId, feeMonth: month, monthlyStructureIds: const {'care'});
  Future<FeeSchoolReport> report([FeeReportFilter? filter]) async => FeeReport.build(
        students: await fees.getStudents(),
        data: await fees.getReportData(),
        classNames: await fees.getClassNames(),
        filter: filter ?? FeeReportFilter(base: base()),
      );
  FeeStudentStatement of(FeeSchoolReport r, String id) => r.students.singleWhere((s) => s.student.id == id);

  group('individual statement', () {
    test('14, 15, 16. one row per payment with the month’s totals repeated; payment date kept apart from fee month; unpaid months shown', () async {
      final anu = of(await report(), 's1');
      expect([for (final l in anu.monthly) l.feeMonthLabel], ['June 2026', 'July 2026', 'August 2026']);
      final june = anu.monthly[0].rows;
      expect([for (final r in june) (FeeReport.date(r.payment?.receipt.paymentDate), r.status, r.amount, r.line.paid, r.line.outstanding, r.line.payable)], [
        ('5 Jun 2026', 'Completed', 1500, 2500, 0, 2500),
        ('12 Jun 2026', 'Completed', 1000, 2500, 0, 2500),
      ]);
      final july = anu.monthly[1].rows.single;
      expect((july.payment, july.status, july.amount, july.line.outstanding, july.line.payable), (null, 'Not paid', 0, 2500, 2500));
      final aug = anu.monthly[2].rows.single;
      expect((aug.line.feeMonthLabel, FeeReport.date(aug.payment!.receipt.paymentDate), aug.amount, aug.line.outstanding), ('August 2026', '5 Sep 2026', 1000, 1500),
          reason: 'September payment for the August fee: under August, dated September');
    });

    test('17, 18, 21. a voided payment is marked Cancelled, not counted, and its amount is outstanding again; Term fees are separate', () async {
      final anu = of(await report(), 's1');
      final term = anu.nonMonthly.single;
      expect((term.assignment.feeStructureName, term.assignment.feeMonth, term.feeMonthLabel), ('Term Fees', '', ''), reason: 'no month invented');
      expect([for (final r in term.rows) (r.status, r.amount)], [('Completed', 3000), ('Cancelled (voided)', 0)]);
      expect((term.paid, term.outstanding, term.receiptsTotal, term.reconciliationWarning), (3000, 5000, 3000, null));
    });

    test('19, 20. an unlinked receipt is listed apart and not counted; a Monthly assignment with no month is "Month not recorded"', () async {
      final r = await report();
      final anu = of(r, 's1');
      expect(anu.unlinked.single.receipt.receiptNo, 'RCPT-ORPHAN');
      expect(anu.lines.expand((l) => l.payments).any((p) => p.receipt.id == 'orphan'), isFalse);
      final chitra = of(r, 's3');
      expect(chitra.noMonth.single.assignment.id, 'chitra-legacy');
      expect(chitra.monthly.single.feeMonthLabel, 'June 2026');
    });

    test('22. totals reconcile with the assignments as recorded', () async {
      final anu = of(await report(), 's1');
      expect([anu.assigned, anu.discounts, anu.payable, anu.collected, anu.outstanding], [15500, 0, 15500, 6500, 9000]);
      expect(anu.collectionPercent, closeTo(41.94, 0.01));
      expect(anu.status, FeePaymentStatus.partial);
      final bala = of(await report(), 's2');
      expect([bala.assigned, bala.discounts, bala.payable, bala.collected, bala.outstanding], [2500, 500, 2000, 2000, 0]);
      expect(anu.warnings, isEmpty);
    });

    test('a recorded paid amount the receipts don’t add up to: a warning, figures unchanged', () async {
      await firestore.doc('student_fee_assignments/${ids['esha-jun']}').update({'paidAmount': 500, 'balanceAmount': 2000});
      final esha = of(await report(), 's5');
      expect((esha.collected, esha.outstanding), (500, 2000));
      expect(esha.warnings.single, contains('receipts total ₹0 but the recorded paid amount is ₹500'));
    });
  });

  group('school-wide report', () {
    test('23, 24. every student: paid, partly paid, not paid, inactive and without assignments', () async {
      final r = await report();
      expect([for (final s in r.students) (s.student.name, s.status.label)], [
        ('Anu', 'Partially Paid'), ('Bala', 'Paid'), ('Chitra', 'Not Paid'), ('Dev', 'No assignments'), ('Esha', 'Not Paid'),
      ]);
      expect(of(r, 's5').student.isActive, isFalse, reason: 'inactive students are included');
      expect([r.totalStudents, r.withAssignments, r.count(FeePaymentStatus.paid), r.count(FeePaymentStatus.partial), r.count(FeePaymentStatus.unpaid)], [5, 4, 1, 1, 2]);
      expect([r.assigned, r.discounts, r.payable, r.collected, r.outstanding], [25500, 500, 25000, 8500, 16500]);
    });

    test('25. the monthly, Term and Month-not-recorded summaries add up to the school totals', () async {
      final r = await report();
      expect([for (final m in r.monthlySummary) (m.label, m.students.length, m.payable, m.collected, m.outstanding)], [
        ('June 2026', 4, 9500, 4500, 5000), ('July 2026', 1, 2500, 0, 2500), ('August 2026', 1, 2500, 1000, 1500),
      ]);
      expect([for (final m in r.nonMonthlySummary) (m.label, m.payable, m.collected)], [('Term Fees', 8000, 3000)]);
      final all = [...r.monthlySummary, ...r.nonMonthlySummary, ?r.noMonthSummary];
      expect(all.fold<double>(0, (s, m) => s + m.payable), r.payable);
      expect(all.fold<double>(0, (s, m) => s + m.collected), r.collected);
      expect(all.fold<double>(0, (s, m) => s + m.outstanding), r.outstanding);
    });

    test('30. filters: fee month (with Term fees), payment status, search, class and admission range', () async {
      final june = await report(FeeReportFilter(base: base(month: '2026-06')));
      expect([for (final l in of(june, 's1').lines) l.assignment.id], [ids['anu-jun'], ids['anu-term']], reason: 'June and the Term fee');
      expect(of(june, 's3').noMonth, isEmpty, reason: 'Month not recorded only under All Months');
      expect(of(june, 's4').hasAssignments, isFalse, reason: 'still listed');
      expect([for (final s in (await report(FeeReportFilter(base: base(), status: FeePaymentStatus.paid))).students) s.student.id], ['s2']);
      expect([for (final s in (await report(FeeReportFilter(base: base(), search: 'adm-s3'))).students) s.student.id], ['s3']);
      expect((await report(FeeReportFilter(base: base(classId: 'other')))).students, isEmpty);
      final ranged = await report(FeeReportFilter(base: base(), admittedFrom: DateTime(2026, 5, 1), admittedTo: DateTime(2026, 6, 30)));
      expect(ranged.students.map((s) => s.student.id), isNot(contains('s4')), reason: 'no admission date: not in a range');
    });

    test('29. reports read only: no writes, no Finance entries', () async {
      final before = firestore.dump();
      final r = await report();
      await FeeReportPdf.school(r, FeeReportPdfHeader(schoolName: 'Test School', title: FeeReport.schoolTitle, filters: const [], generatedAt: DateTime(2026, 11, 7)));
      await FeeReportPdf.statement(of(r, 's1'), FeeReportPdfHeader(schoolName: 'Test School', title: FeeReport.statementTitle, filters: const [], generatedAt: DateTime(2026, 11, 7)));
      expect(firestore.dump(), before);
    });
  });

  group('PDF', () {
    FeeReportPdfHeader header(String title) => FeeReportPdfHeader(
        schoolName: 'Test School', title: title, filters: const ['Academic Year: 2026-2027', 'Fee Month: All Months'], generatedAt: DateTime(2026, 11, 7, 9, 30));

    test('26, 27, 28, 31. every filtered student and payment, unpaid and cancelled rows, Term fees, page numbers and repeated headings', () async {
      // 120 more students: far more than one screen page (10).
      for (var i = 0; i < 120; i++) {
        await firestore.collection('students').doc('x$i').set({'name': 'Pupil$i', 'admissionNo': 'ADM-X$i', 'classId': 'c1', 'isActive': true, 'admissionDate': DateTime(2026, 6, 1)});
      }
      for (var i = 0; i < 40; i++) {
        await assign('x$i', 'care', 'Day Care', 2500, month: '2026-06');
      }
      final r = await report();
      expect(r.totalStudents, 125);
      final bytes = await FeeReportPdf.school(r, header(FeeReport.schoolTitle), compress: false);
      final words = _pdfWords(bytes);
      for (final s in r.students) {
        expect(words, contains(s.student.name), reason: '${s.student.name} is in the PDF');
      }
      final pages = _pages(bytes);
      expect(pages, greaterThan(3));
      expect(_hasPhrase(words, 'Page $pages of $pages'), isTrue);
      expect(_hasPhrase(words, 'Page 2 of $pages'), isTrue);
      expect(_hasPhrase(words, 'All Students - Fee Collection and Outstanding Report'), isTrue, reason: 'dash written plainly');
      expect(_hasPhrase(words, 'Generated 7 Nov 2026, 9:30 AM'), isTrue);
      expect(_hasPhrase(words, 'Rs. 1,500'), isTrue);
      expect(_hasPhrase(words, '5 Sep 2026'), isTrue, reason: 'August’s payment date');
      expect(_hasPhrase(words, 'Not paid'), isTrue);
      expect(_hasPhrase(words, 'Cancelled (voided)'), isTrue);
      expect(_hasPhrase(words, 'Rs. 2,000 (cancelled)'), isTrue);
      expect(_hasPhrase(words, 'Term and One-time Fees'), isTrue);
      expect(_hasPhrase(words, 'Month not recorded'), isTrue);
      expect(_hasPhrase(words, 'No fee assignments for the selected period.'), isTrue);
      expect(words, contains('RCPT-ORPHAN'));
      for (final p in of(r, 's1').lines.expand((l) => l.payments)) {
        expect(words.join(), contains(p.receipt.receiptNo), reason: 'receipt ${p.receipt.receiptNo}');
      }
    });

    test('27. a table longer than a page repeats its headings on the next page', () async {
      // 70 payments of ₹10 on one fee: one table over more than a page.
      for (var i = 0; i < 70; i++) {
        await collect(ids['chitra-jun']!, 10, DateTime(2026, 6, 1));
      }
      final r = await report(FeeReportFilter(base: base(studentId: 's3')));
      final bytes = await FeeReportPdf.statement(of(r, 's3'), header(FeeReport.statementTitle), compress: false);
      final words = _pdfWords(bytes);
      expect(_pages(bytes), greaterThan(1));
      expect(_phraseCount(words, 'Fee Month Fee Payment Date Receipt No'), _pages(bytes) >= 2 ? greaterThanOrEqualTo(2) : 1);
      expect(_phraseCount(words, 'Chitra (ADM-s3) Monthly fees'), greaterThanOrEqualTo(2), reason: 'the student’s name repeats with the headings');
    });

    test('an empty result says so instead of producing a misleading report', () async {
      final r = await report(FeeReportFilter(base: base(), search: 'nobody'));
      final words = _pdfWords(await FeeReportPdf.school(r, header(FeeReport.schoolTitle), compress: false));
      expect(_hasPhrase(words, 'No students match the selected filters. Nothing to report.'), isTrue);
    });
  });

  group('Reports tab', () {
    final exported = <(String, Uint8List)>[];
    setUp(exported.clear);

    Future<void> pumpReports(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore)),
          schoolIdentityProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          home: AdminFeesScreen(
            service: fees,
            clock: () => DateTime(2026, 11, 7),
            exportPdf: (bytes, name) async => exported.add((name, bytes)),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Reports'));
      await tester.pumpAndSettle();
    }

    Finder key(String k) => find.byKey(Key(k));
    String text(WidgetTester tester, String k) => tester.widget<Text>(key(k)).data!;

    testWidgets('the existing tabs keep their order; Reports is added last; the summary and students show; the PDF holds every student', (tester) async {
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(() => firestore.collection('students').doc('x$i').set({'name': 'Pupil$i', 'admissionNo': 'ADM-X$i', 'classId': 'c1', 'isActive': true}));
      }
      await pumpReports(tester);
      expect([for (final c in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip))) (c.label as Text).data],
          ['Collections', 'Receipts', 'Dues', 'Assignments', 'Structures', 'Students', 'Reports']);
      expect(key('fee-statement-hint'), findsOneWidget);
      expect(text(tester, 'fee-report-summary-students'), '20');
      expect(text(tester, 'fee-report-summary-collected'), '₹8,500');
      expect(text(tester, 'fee-report-summary-outstanding'), '₹16,500');
      expect(text(tester, 'fee-report-page'), 'Showing 1–10 of 20 students');
      expect(key('fee-statement-no-assignments-s4'), findsOneWidget);
      expect(text(tester, 'fee-report-export-note'), 'The PDF contains all 20 matching students, not just this page.');

      await tester.tap(key('fee-report-export'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pumpAndSettle();
      expect(exported.single.$1, 'all-students-fee-report.pdf');
      expect(exported.single.$2.length, greaterThan(1000));
      expect(utf8.decode(exported.single.$2.sublist(0, 5), allowMalformed: true), '%PDF-');
    });

    testWidgets('a status filter and search narrow both the screen and the PDF', (tester) async {
      await pumpReports(tester);
      await tester.enterText(key('fee-report-search'), 'chi');
      await tester.pumpAndSettle();
      expect(text(tester, 'fee-report-summary-students'), '1');
      expect(key('fee-report-student-s3'), findsOneWidget);
      expect(key('fee-report-student-s1'), findsNothing);
    });

    testWidgets('statement for the selected student: rows per payment, a receipt opens the receipt view; class view lists each student', (tester) async {
      await pumpReports(tester);
      // Choose the student in the shared filter.
      await tester.tap(key('fees-filter-class'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mont 1').last);
      await tester.pumpAndSettle();
      expect(key('fee-statement-class'), findsOneWidget);
      expect(key('fee-statement-view-s1'), findsOneWidget);
      await tester.tap(key('fee-statement-view-s1'));
      await tester.pumpAndSettle();
      expect(key('fee-statement-monthly-s1'), findsWidgets);
      expect(find.text('Not paid'), findsWidgets);
      expect(find.text('Cancelled (voided)'), findsWidgets);
      await tester.tap(key('fee-statement-receipt-${ids['r3']}').last);
      await tester.pumpAndSettle();
      expect(find.byType(FeeReceiptViewDialog), findsOneWidget);
    });

    testWidgets('a permission failure is explained and nothing is shown as if empty', (tester) async {
      final denied = _DeniedFeeService(firestore);
      tester.view.physicalSize = const Size(1600, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore)),
          schoolIdentityProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(home: AdminFeesScreen(service: denied, clock: () => DateTime(2026, 11, 7))),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Reports'));
      await tester.pumpAndSettle();
      expect(text(tester, 'fee-report-error'), contains('don’t have permission'));
      expect(key('fee-report-export'), findsNothing);
    });
  });
}

class _DeniedFeeService extends FeeService {
  _DeniedFeeService(BufferedTransactionFirestore firestore) : super(firestore: firestore, auth: MockFirebaseAuth(), storage: MockFirebaseStorage());

  @override
  Future<FeeReportData> getReportData() async => throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
}

// Fees: month-specific assignments for Monthly fee structures (every
// component monthly). The Assign Fee dialog asks for a required "Fee
// Month" (January–December, shown with its year in the academic year) and
// stores it as `feeMonth` = YYYY-MM; each month is its own assignment,
// with duplicates prevented per month; collections, receipts, dues and the
// Finance entry follow the assignment's month. Other structures and older
// assignments without a month are unchanged. Synthetic test data only.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/settings/providers/academic_year_provider.dart';
import 'package:montessori_app/modules/fees/models/fee_component_model.dart';
import 'package:montessori_app/modules/fees/models/fee_month.dart';
import 'package:montessori_app/modules/fees/models/fee_structure_model.dart';
import 'package:montessori_app/modules/fees/models/student_fee_assignment_model.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/admin_fees_screen.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_assignment_dialog.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';

import 'support/buffered_transaction_firestore.dart';

void main() {
  // ---------------------------------------------------------------- FeeMonth
  group('FeeMonth', () {
    test('months of an academic year get their own calendar year; labels; format', () {
      final start = DateTime(2026, 6, 1), end = DateTime(2027, 5, 31);
      expect(FeeMonth.inAcademicYear(1, start, end), '2027-01');
      expect(FeeMonth.inAcademicYear(6, start, end), '2026-06');
      expect(FeeMonth.inAcademicYear(12, start, end), '2026-12');
      expect(FeeMonth.inAcademicYear(7, DateTime(2026, 1, 1), DateTime(2026, 3, 31)), isNull, reason: 'not in a short year');
      expect(FeeMonth.label('2027-01'), 'January 2027');
      expect(FeeMonth.label(''), '');
      expect([FeeMonth.isValid('2027-01'), FeeMonth.isValid('2027-13'), FeeMonth.isValid('Jan')], [true, false, false]);
      expect(FeeMonth.monthOf('2027-02'), 2);
    });

    test('Monthly means every component is monthly', () {
      FeeStructureModel s(List<String> freqs) => FeeStructureModel.fromMap('x', {
            'name': 'S',
            'components': [for (final f in freqs) FeeComponentModel(name: f, amount: 1, frequency: f, isOptional: false).toMap()],
          });
      expect(FeeMonth.isMonthlyStructure(s(['monthly'])), isTrue);
      expect(FeeMonth.isMonthlyStructure(s(['monthly', 'monthly'])), isTrue);
      expect(FeeMonth.isMonthlyStructure(s(['monthly', 'oneTime'])), isFalse);
      expect(FeeMonth.isMonthlyStructure(s(['term'])), isFalse);
      expect(FeeMonth.isMonthlyStructure(s([])), isFalse);
    });
  });

  // ---------------------------------------------------------------- setup
  late BufferedTransactionFirestore firestore;
  late FinanceService finance;
  late FeeService fees;
  late String yearId;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    final auth = MockFirebaseAuth();
    finance = FinanceService(firestore: firestore, auth: auth);
    await finance.ensureDefaults();
    fees = FeeService(firestore: firestore, auth: auth, storage: MockFirebaseStorage(), financeService: finance);
    yearId = await AcademicYearService(firestore: firestore).createAcademicYear(
      schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2026-2027',
      startDate: DateTime(2026, 6, 1), endDate: DateTime(2027, 5, 31), createdBy: 'admin-1', setAsCurrent: true,
    );
    await firestore.collection('classes').doc('class-1').set({'name': 'Mont 1', 'isActive': true});
    for (final (id, name) in [('s1', 'Anu'), ('s2', 'Bala'), ('s3', 'Chitra')]) {
      await firestore.collection('students').doc(id).set({'name': name, 'admissionNo': 'ADM-$id', 'classId': 'class-1', 'isActive': true, 'admissionDate': DateTime(2020, 1, 1)}); // admitted long before every fee month (Admission Date rule)
    }
    Future<void> structure(String id, String name, double amount, List<String> freqs) => firestore.collection('fee_structures').doc(id).set({
          'name': name, 'description': '', 'totalAmount': amount, 'academicYear': '2026-2027', 'academicYearId': yearId, 'isActive': true, 'createdBy': 't',
          'components': [for (final f in freqs) FeeComponentModel(name: '$name $f', amount: amount / freqs.length, frequency: f, isOptional: false).toMap()],
        });
    await structure('daycare', 'Day Care', 3000, ['monthly']);
    await structure('term1', 'Term Fees', 20000, ['term']);
  });

  // Every new assignment needs a due date (FeeService); any date will do here.
  Map<String, dynamic> single(String studentId, String structureId, {String? feeMonth, String name = 'Day Care', double total = 3000, DateTime? dueDate}) => {
        'studentId': studentId, 'studentName': studentId, 'admissionNo': 'ADM-$studentId', 'classId': 'class-1', 'className': 'Mont 1',
        'feeStructureId': structureId, 'feeStructureName': name, 'academicYearId': yearId, 'academicYear': '2026-2027',
        'totalFee': total, 'discountAmount': 0, 'payableAmount': total, 'paidAmount': 0, 'balanceAmount': total, 'status': 'unpaid',
        'feeMonth': ?feeMonth,
        'dueDate': dueDate ?? DateTime(2027, 1, 10),
      };

  Future<List<Map<String, dynamic>>> assignments() async => [for (final d in (await firestore.collection('student_fee_assignments').get()).docs) {'id': d.id, ...d.data()}];
  Future<Map<String, dynamic>> doc(String path) async => (await firestore.doc(path).get()).data()!;

  // ---------------------------------------------------------------- service
  group('service', () {
    test('6, 8, 10. January and February are separate assignments; academic year and month persist', () async {
      final jan = await fees.assignFee(single('s1', 'daycare', feeMonth: '2027-01'));
      final feb = await fees.assignFee(single('s1', 'daycare', feeMonth: '2027-02'));
      expect(jan, isNotNull);
      expect(feb, isNotNull);
      expect(jan, isNot(feb));
      final janDoc = await doc('student_fee_assignments/$jan');
      expect([janDoc['feeMonth'], janDoc['academicYearId'], janDoc['academicYear']], ['2027-01', yearId, '2026-2027']);
      expect((await doc('student_fee_assignments/$feb'))['feeMonth'], '2027-02');
      expect(StudentFeeAssignmentModel.fromMap(jan!, janDoc).feeMonth, '2027-01');
    });

    test('7. the same month twice is refused (single and full class); other months still go through', () async {
      await fees.assignFee(single('s1', 'daycare', feeMonth: '2027-01'));
      expect(await fees.assignFee(single('s1', 'daycare', feeMonth: '2027-01')), isNull);
      final janClass = await fees.bulkAssignClassFees(classId: 'class-1', className: 'Mont 1', feeStructureId: 'daycare', feeStructureName: 'Day Care', academicYearId: yearId, academicYear: '2026-2027', totalFee: 3000, discountAmount: 0, feeMonth: '2027-01', dueDate: DateTime(2027, 1, 10));
      expect(janClass, {'assigned': 2, 'skipped': 1, 'admissionSkipped': 0, 'manualReview': 0, 'studentDiscounted': 0, 'discountConflict': 0}, reason: 's1 already has January');
      final febClass = await fees.bulkAssignClassFees(classId: 'class-1', className: 'Mont 1', feeStructureId: 'daycare', feeStructureName: 'Day Care', academicYearId: yearId, academicYear: '2026-2027', totalFee: 3000, discountAmount: 0, feeMonth: '2027-02', dueDate: DateTime(2027, 2, 10));
      expect(febClass, {'assigned': 3, 'skipped': 0, 'admissionSkipped': 0, 'manualReview': 0, 'studentDiscounted': 0, 'discountConflict': 0});
      final all = await assignments();
      expect(all.where((a) => a['feeMonth'] == '2027-01'), hasLength(3));
      expect(all.where((a) => a['feeMonth'] == '2027-02'), hasLength(3));
    });

    test('3. a Monthly structure needs a month; another structure takes none; the month must be YYYY-MM', () async {
      await expectLater(fees.assignFee(single('s1', 'daycare')), throwsA(isA<StateError>().having((e) => e.message, 'message', FeeService.feeMonthRequiredMessage)));
      await expectLater(
        fees.bulkAssignClassFees(classId: 'class-1', className: 'Mont 1', feeStructureId: 'daycare', feeStructureName: 'Day Care', academicYearId: yearId, academicYear: '2026-2027', totalFee: 3000, discountAmount: 0, dueDate: DateTime(2027, 1, 10)),
        throwsA(isA<StateError>()),
      );
      await expectLater(fees.assignFee(single('s1', 'term1', feeMonth: '2027-01', name: 'Term Fees', total: 20000)), throwsA(isA<StateError>()));
      await expectLater(fees.assignFee(single('s1', 'daycare', feeMonth: 'January')), throwsA(isA<StateError>()));
      expect(await assignments(), isEmpty);
    });

    test('15. other structures: as before (no month stored, one per student and year)', () async {
      final id = await fees.assignFee(single('s1', 'term1', name: 'Term Fees', total: 20000));
      expect((await doc('student_fee_assignments/$id')).containsKey('feeMonth'), isFalse);
      expect(await fees.assignFee(single('s1', 'term1', name: 'Term Fees', total: 20000)), isNull);
      final receipt = await fees.collectFee(assignmentId: id!, amount: 5000, paymentDate: DateTime(2026, 7, 1), paymentMode: 'cash', referenceNo: '', remarks: '');
      expect((await doc('fee_receipts/${receipt.id}')).containsKey('feeMonth'), isFalse);
      final income = (await firestore.collection('finance_income').get()).docs.single.data();
      expect(income['title'], 'Fee collected from s1 - Term Fees', reason: 'Finance wording unchanged');
    });

    test('12, 13, 14, 16. a payment goes to its month only; receipts and the Finance entry carry the month; voiding restores that month', () async {
      final jan = (await fees.assignFee(single('s1', 'daycare', feeMonth: '2027-01')))!;
      final feb = (await fees.assignFee(single('s1', 'daycare', feeMonth: '2027-02')))!;
      final receipt = await fees.collectFee(assignmentId: jan, amount: 3000, paymentDate: DateTime(2027, 1, 5), paymentMode: 'cash', referenceNo: 'R1', remarks: '');
      expect([(await doc('student_fee_assignments/$jan'))['balanceAmount'], (await doc('student_fee_assignments/$jan'))['status']], [0, 'paid']);
      expect([(await doc('student_fee_assignments/$feb'))['balanceAmount'], (await doc('student_fee_assignments/$feb'))['status']], [3000, 'unpaid'], reason: 'February still due');
      expect(receipt.feeMonth, '2027-01');
      expect((await doc('fee_receipts/${receipt.id}'))['feeMonth'], '2027-01');
      expect((await doc('fee_transactions/${receipt.transactionId}'))['feeMonth'], '2027-01');
      expect((await fees.getReceiptById(receipt.id))!.feeMonth, '2027-01');
      // One Finance entry, linked to this receipt as before.
      final ledger = (await firestore.collection('finance_ledger').get()).docs;
      expect(ledger, hasLength(1));
      expect(ledger.single.data()['sourceId'], receipt.id);
      expect(ledger.single.data()['title'], 'Fee collected from s1 - Day Care (January 2027)');
      // Dues: only February.
      final due = [for (final a in await fees.getAssignments()) if (a.balanceAmount > 0) a.feeMonth];
      expect(due, ['2027-02']);

      await fees.voidReceipt(receipt.id);
      expect((await doc('student_fee_assignments/$jan'))['balanceAmount'], 3000);
      expect((await doc('student_fee_assignments/$feb'))['balanceAmount'], 3000);
      expect((await firestore.collection('finance_ledger').get()).docs.single.data()['status'], 'cancelled');
      expect((await finance.watchDashboardSummary().first).totalIncome, 0);
    });

    test('17. an older Monthly assignment without a month: readable as is, blocks a new month until given one, and can be given one once', () async {
      final legacy = await firestore.collection('student_fee_assignments').add({...single('s1', 'daycare'), 'paidAmount': 1000, 'balanceAmount': 2000, 'status': 'partial'});
      final model = StudentFeeAssignmentModel.fromMap(legacy.id, await doc('student_fee_assignments/${legacy.id}'));
      expect(model.feeMonth, '');
      expect(model.paidAmount, 1000);
      // Its month is unknown, so it may be January: not silently doubled.
      expect(await fees.assignFee(single('s1', 'daycare', feeMonth: '2027-01')), isNull);
      // An explicit correction, even though paid: recorded once, then fixed.
      await fees.updateAssignment(legacy.id, {'feeMonth': '2026-12'});
      expect((await doc('student_fee_assignments/${legacy.id}'))['feeMonth'], '2026-12');
      expect((await doc('student_fee_assignments/${legacy.id}'))['paidAmount'], 1000, reason: 'nothing else changes');
      await expectLater(fees.updateAssignment(legacy.id, {'feeMonth': '2027-03'}), throwsA(isA<StateError>()));
      expect(await fees.assignFee(single('s1', 'daycare', feeMonth: '2027-01')), isNotNull, reason: 'now another month is free');
      // An unpaid one may move to a free month, not onto a taken one.
      final feb = (await fees.assignFee(single('s1', 'daycare', feeMonth: '2027-02')))!;
      await expectLater(fees.updateAssignment(feb, {'feeMonth': '2027-01'}), throwsA(isA<StateError>()));
      await fees.updateAssignment(feb, {'feeMonth': '2027-04'});
      expect((await doc('student_fee_assignments/$feb'))['feeMonth'], '2027-04');
    });
  });

  // ---------------------------------------------------------------- dialog
  group('Assign Fee dialog', () {
    Future<void> pumpDialog(WidgetTester tester, {StudentFeeAssignmentModel? edit}) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore))],
        child: MaterialApp(home: Scaffold(body: FeeAssignmentDialog(assignment: edit, service: fees))),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> choose(WidgetTester tester, Finder dropdown, String option) async {
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(option).last);
      await tester.pumpAndSettle();
    }

    Finder field(String label) => find.widgetWithText(DropdownButtonFormField<String>, label);
    Finder month() => find.byKey(const Key('fee-month'));
    int? monthValue(WidgetTester tester) => tester.widget<DropdownButton<int>>(find.descendant(of: month(), matching: find.byType(DropdownButton<int>))).value;

    // A new assignment needs a due date (these structures set no due day).
    Future<void> pickDueDay(WidgetTester tester, int day) async {
      await tester.ensureVisible(find.byKey(const Key('fee-due-date-pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('fee-due-date-pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('$day').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    Future<void> save(WidgetTester tester) async {
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
    }

    testWidgets('1, 2, 9. Monthly shows a required Fee Month (no default, with the year); Term hides it and clears the month', (tester) async {
      await pumpDialog(tester);
      await choose(tester, field('Select Class *'), 'Mont 1');
      expect(month(), findsNothing);
      await choose(tester, field('Fee Structure *'), 'Day Care');
      expect(find.text('Start Fee Month *'), findsOneWidget, reason: 'the first month of a recurring assignment');
      expect(monthValue(tester), isNull, reason: 'not defaulted to the current month');
      await tester.tap(month());
      await tester.pumpAndSettle();
      expect(find.text('January 2027'), findsWidgets);
      expect(find.text('June 2026'), findsWidgets);
      await tester.tap(find.text('January 2027').last);
      await tester.pumpAndSettle();
      expect(monthValue(tester), 1);

      await choose(tester, field('Fee Structure *'), 'Term Fees');
      expect(month(), findsNothing, reason: 'hidden for Term');
      await choose(tester, field('Fee Structure *'), 'Day Care');
      expect(monthValue(tester), isNull, reason: 'the January choice was cleared');
    });

    testWidgets('3, 4. a Monthly assignment can’t be saved without its month; with it, the single student gets that month', (tester) async {
      await pumpDialog(tester);
      await choose(tester, field('Select Class *'), 'Mont 1');
      await choose(tester, field('Select Student *'), 'Anu');
      await choose(tester, field('Fee Structure *'), 'Day Care');
      await save(tester);
      expect(find.text('Choose the month this fee is for'), findsOneWidget);
      expect(await tester.runAsync(assignments), isEmpty);

      await choose(tester, month(), 'January 2027');
      await pickDueDay(tester, 10);
      await save(tester);
      final saved = (await tester.runAsync(assignments))!;
      expect(saved.single['studentId'], 's1');
      expect([saved.single['feeMonth'], saved.single['academicYearId'], saved.single['academicYear']], ['2027-01', yearId, '2026-2027']);
    });

    testWidgets('5. Full Class: every student gets the chosen month', (tester) async {
      await pumpDialog(tester);
      await tester.tap(find.text('Full Class'));
      await tester.pumpAndSettle();
      await choose(tester, field('Select Class *'), 'Mont 1');
      await choose(tester, field('Fee Structure *'), 'Day Care');
      await choose(tester, month(), 'February 2027');
      await pickDueDay(tester, 10);
      await save(tester);
      // Full Class confirms the students, months and assignments first.
      expect(find.byKey(const Key('fee-bulk-confirm')), findsOneWidget);
      await tester.tap(find.byKey(const Key('fee-bulk-confirm-ok')));
      await tester.pumpAndSettle();
      final saved = (await tester.runAsync(assignments))!;
      expect(saved, hasLength(3));
      expect(saved.map((a) => a['feeMonth']).toSet(), {'2027-02'});
      expect(saved.map((a) => a['studentId']).toSet(), {'s1', 's2', 's3'});
    });

    testWidgets('15. a Term structure saves as before, with no month', (tester) async {
      await pumpDialog(tester);
      await choose(tester, field('Select Class *'), 'Mont 1');
      await choose(tester, field('Select Student *'), 'Bala');
      await choose(tester, field('Fee Structure *'), 'Term Fees');
      await pickDueDay(tester, 15);
      await save(tester);
      final saved = (await tester.runAsync(assignments))!;
      expect(saved.single.containsKey('feeMonth'), isFalse);
      expect(saved.single['totalFee'], 20000);
    });

    testWidgets('17. editing an older Monthly assignment asks for its month, without inventing one', (tester) async {
      final ref = await firestore.collection('student_fee_assignments').add(single('s1', 'daycare'));
      final legacy = StudentFeeAssignmentModel.fromMap(ref.id, await doc('student_fee_assignments/${ref.id}'));
      await pumpDialog(tester, edit: legacy);
      expect(find.byKey(const Key('fee-month-legacy')), findsOneWidget);
      expect(monthValue(tester), isNull);
      await save(tester);
      expect(find.text('Choose the month this fee is for'), findsOneWidget);
      expect((await tester.runAsync(() => doc('student_fee_assignments/${ref.id}')))!.containsKey('feeMonth'), isFalse);
    });
  });

  // ---------------------------------------------------------------- screen
  group('Fees screen', () {
    Future<void> pumpScreen(WidgetTester tester, String tab) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore))],
        child: MaterialApp(home: AdminFeesScreen(service: fees)),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, tab));
      await tester.pumpAndSettle();
    }

    testWidgets('11, 14. Assignments and Dues show each month (and an older one as "month not recorded"); search finds a month', (tester) async {
      await fees.assignFee(single('s1', 'daycare', feeMonth: '2027-01'));
      final feb = (await fees.assignFee(single('s1', 'daycare', feeMonth: '2027-02')))!;
      await firestore.collection('student_fee_assignments').add(single('s2', 'daycare'));
      await fees.assignFee(single('s3', 'term1', name: 'Term Fees', total: 20000));
      await fees.collectFee(assignmentId: feb, amount: 1000, paymentDate: DateTime(2027, 2, 2), paymentMode: 'cash', referenceNo: '', remarks: '');
      await pumpScreen(tester, 'Assignments');
      expect(find.text('Mont 1 • Day Care • January 2027'), findsOneWidget);
      expect(find.text('Mont 1 • Day Care • February 2027'), findsOneWidget);
      expect(find.text('Mont 1 • Day Care • month not recorded'), findsOneWidget);
      expect(find.text('Mont 1 • Term Fees'), findsOneWidget, reason: 'non-monthly unchanged');
      await tester.enterText(find.byType(TextField).first, 'february');
      await tester.pumpAndSettle();
      expect(find.text('Mont 1 • Day Care • February 2027'), findsOneWidget);
      expect(find.text('Mont 1 • Day Care • January 2027'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Dues'));
      await tester.pumpAndSettle();
      expect(find.text('Due: 3000 • January 2027'), findsOneWidget);
      expect(find.text('Due: 2000 • February 2027'), findsOneWidget, reason: 'each month’s own balance');
      expect(find.text('Due: 20000'), findsOneWidget);
    });

    testWidgets('13. Receipts show the month', (tester) async {
      final jan = (await fees.assignFee(single('s1', 'daycare', feeMonth: '2027-01')))!;
      await fees.collectFee(assignmentId: jan, amount: 3000, paymentDate: DateTime(2027, 1, 5), paymentMode: 'cash', referenceNo: '', remarks: '');
      await pumpScreen(tester, 'Receipts');
      expect(find.text('Day Care • January 2027 • 3000 • cash'), findsOneWidget);
    });
  });
}

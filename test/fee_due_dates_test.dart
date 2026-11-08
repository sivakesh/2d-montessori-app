// Fees: assignment due dates (defaulted from the structure's Due Day of
// Month for a monthly fee, chosen otherwise, stored on each assignment)
// and overdue worked out when read: an outstanding balance and a due date
// before today. Overdue Students counts distinct students. Synthetic test
// data only.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/settings/providers/academic_year_provider.dart';
import 'package:montessori_app/modules/fees/models/fee_component_model.dart';
import 'package:montessori_app/modules/fees/models/fee_due_date.dart';
import 'package:montessori_app/modules/fees/models/fee_month.dart';
import 'package:montessori_app/modules/fees/models/fee_structure_model.dart';
import 'package:montessori_app/modules/fees/models/student_fee_assignment_model.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/admin_fees_screen.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_assignment_dialog.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_structure_dialog.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';

import 'support/buffered_transaction_firestore.dart';

FeeStructureModel _structure(List<FeeComponentModel> components) => FeeStructureModel.fromMap('x', {'name': 'S', 'components': [for (final c in components) c.toMap()]});
FeeComponentModel _monthly({int? day, double amount = 3000}) => FeeComponentModel(name: 'Care', amount: amount, frequency: 'monthly', dueDayOfMonth: day, isOptional: false);

StudentFeeAssignmentModel _a(String id, {String student = 's1', double balance = 1000, DateTime? due, String status = 'unpaid', String classId = 'c1', String yearId = 'y'}) =>
    StudentFeeAssignmentModel.fromMap(id, {
      'studentId': student, 'classId': classId, 'academicYearId': yearId, 'totalFee': 3000, 'payableAmount': 3000,
      'paidAmount': 3000 - balance, 'balanceAmount': balance, 'status': status, 'dueDate': ?due,
    });

void main() {
  // ---------------------------------------------------------------- rules
  group('defaults from the structure', () {
    test('1. monthly: the structure’s due day in the chosen month', () {
      final d = FeeDueDate.defaultFor(_structure([_monthly(day: 5)]), '2027-01');
      expect(d.date, DateTime(2027, 1, 5));
      expect(d.note, contains('due day (5)'));
    });

    test('5. a day the month doesn’t have is its last day (February, leap years, 30-day months); invalid days give none', () {
      final s = _structure([_monthly(day: 31)]);
      expect(FeeDueDate.defaultFor(s, '2027-02').date, DateTime(2027, 2, 28));
      expect(FeeDueDate.defaultFor(s, '2028-02').date, DateTime(2028, 2, 29));
      expect(FeeDueDate.defaultFor(s, '2026-06').date, DateTime(2026, 6, 30));
      expect(FeeDueDate.defaultFor(s, '2027-02').note, contains('has no day 31'));
      expect(FeeDueDate.defaultFor(_structure([_monthly(day: 30)]), '2027-02').date, DateTime(2027, 2, 28));
      expect(FeeDueDate.defaultFor(_structure([_monthly(day: 40)]), '2027-01').date, isNull);
      expect(FeeDueDate.defaultFor(_structure([_monthly(day: 0)]), '2027-01').date, isNull);
    });

    test('6. academic-year boundary months take their own calendar year', () {
      final s = _structure([_monthly(day: 10)]);
      final start = DateTime(2026, 6, 1), end = DateTime(2027, 5, 31);
      expect(FeeDueDate.defaultFor(s, FeeMonth.inAcademicYear(6, start, end)!).date, DateTime(2026, 6, 10));
      expect(FeeDueDate.defaultFor(s, FeeMonth.inAcademicYear(12, start, end)!).date, DateTime(2026, 12, 10));
      expect(FeeDueDate.defaultFor(s, FeeMonth.inAcademicYear(1, start, end)!).date, DateTime(2027, 1, 10));
      expect(FeeDueDate.defaultFor(s, FeeMonth.inAcademicYear(5, start, end)!).date, DateTime(2027, 5, 10));
    });

    test('3, 4, 12. no due day, different days, no month yet, or a non-monthly structure without its own date: a date must be chosen', () {
      expect(FeeDueDate.defaultFor(_structure([_monthly()]), '2027-01').date, isNull);
      expect(FeeDueDate.defaultFor(_structure([_monthly(day: 5), _monthly(day: 10)]), '2027-01').note, contains('different due days (5, 10)'));
      expect(FeeDueDate.defaultFor(_structure([_monthly(day: 5)]), '').date, isNull);
      final term = FeeComponentModel(name: 'T', amount: 1, frequency: 'term', termName: 'Term 1', isOptional: false);
      expect(FeeDueDate.defaultFor(_structure([term]), '').date, isNull, reason: 'not from the term name or the year');
      final dated = FeeComponentModel(name: 'T', amount: 1, frequency: 'term', dueDate: DateTime(2026, 7, 15, 9), isOptional: false);
      expect(FeeDueDate.defaultFor(_structure([dated]), '').date, DateTime(2026, 7, 15), reason: 'its own stored due date');
    });
  });

  group('overdue', () {
    final today = DateTime(2027, 1, 6, 10);
    test('13–17, 19, 20. yesterday with a balance; today; future; paid; partly paid; no date; cancelled', () {
      expect(FeeDueDate.isOverdue(_a('a', due: DateTime(2027, 1, 5)), today), isTrue);
      expect(FeeDueDate.isOverdue(_a('a', due: DateTime(2027, 1, 6)), today), isFalse);
      expect(FeeDueDate.isOverdue(_a('a', due: DateTime(2027, 1, 7)), today), isFalse);
      expect(FeeDueDate.isOverdue(_a('a', due: DateTime(2027, 1, 5), balance: 0), today), isFalse);
      expect(FeeDueDate.isOverdue(_a('a', due: DateTime(2027, 1, 5), balance: 1), today), isTrue, reason: 'partly paid');
      expect(FeeDueDate.isOverdue(_a('a', due: DateTime(2027, 1, 5), balance: 0.001), today), isFalse, reason: 'rounding noise');
      expect(FeeDueDate.isOverdue(_a('a'), today), isFalse);
      expect(FeeDueDate.isOverdue(_a('a', status: 'overdue'), today), isFalse, reason: 'the stored status isn’t the rule');
      expect(FeeDueDate.isOverdue(_a('a', due: DateTime(2027, 1, 5), status: 'cancelled'), today), isFalse);
    });

    test('3. overdue goes by the due date, not the fee month', () {
      StudentFeeAssignmentModel monthly(String month, DateTime due) =>
          StudentFeeAssignmentModel.fromMap(month, {'studentId': 's', 'feeMonth': month, 'payableAmount': 3000, 'balanceAmount': 3000, 'dueDate': due});
      final today = DateTime(2027, 2, 3);
      expect(FeeDueDate.isOverdue(monthly('2027-01', DateTime(2027, 2, 5)), today), isFalse, reason: 'January’s fee, due 5 Feb: not yet');
      expect(FeeDueDate.isOverdue(monthly('2027-03', DateTime(2027, 2, 1)), today), isTrue, reason: 'March’s fee due early: overdue');
    });

    test('25. by local calendar day: due 5 Jan is not overdue until 6 Jan 00:00, whatever time it was stored with', () {
      final a = _a('a', due: DateTime(2027, 1, 5, 18));
      expect(FeeDueDate.isOverdue(a, DateTime(2027, 1, 5, 23, 59, 59)), isFalse);
      expect(FeeDueDate.isOverdue(a, DateTime(2027, 1, 6)), isTrue);
      expect(FeeDueDate.isOverdue(_a('b', due: DateTime(2026, 12, 31)), DateTime(2027, 1, 1)), isTrue, reason: 'across a year end');
    });

    test('21, 22. Overdue Students counts each student once', () {
      final list = [
        _a('1', student: 's1', due: DateTime(2027, 1, 1)),
        _a('2', student: 's1', due: DateTime(2027, 1, 2)),
        _a('3', student: 's2', due: DateTime(2027, 1, 3)),
        _a('4', student: 's3', due: DateTime(2027, 2, 1)),
        _a('5', student: 's4', due: DateTime(2027, 1, 1), balance: 0),
      ];
      expect(FeeDueDate.overdueStudents(list, today), 2);
    });
  });

  // ---------------------------------------------------------------- data
  late BufferedTransactionFirestore firestore;
  late FeeService fees;
  late String yearId, oldYearId;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    final auth = MockFirebaseAuth();
    final finance = FinanceService(firestore: firestore, auth: auth);
    await finance.ensureDefaults();
    fees = FeeService(firestore: firestore, auth: auth, storage: MockFirebaseStorage(), financeService: finance);
    final years = AcademicYearService(firestore: firestore);
    oldYearId = await years.createAcademicYear(schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2025-2026',
        startDate: DateTime(2025, 6, 1), endDate: DateTime(2026, 5, 31), createdBy: 'admin-1');
    yearId = await years.createAcademicYear(schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2026-2027',
        startDate: DateTime(2026, 6, 1), endDate: DateTime(2027, 5, 31), createdBy: 'admin-1', setAsCurrent: true);
    await firestore.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
    await firestore.collection('classes').doc('c2').set({'name': 'Mont 2', 'isActive': true});
    for (final (id, name, cls) in [('s1', 'Anu', 'c1'), ('s2', 'Bala', 'c1'), ('s3', 'Chitra', 'c2')]) {
      await firestore.collection('students').doc(id).set({'name': name, 'admissionNo': 'ADM-$id', 'classId': cls, 'isActive': true, 'admissionDate': DateTime(2020, 1, 1)}); // admitted long before every fee month (Admission Date rule)
    }
    Future<void> structure(String id, String name, List<FeeComponentModel> components) => firestore.collection('fee_structures').doc(id).set({
          'name': name, 'description': '', 'totalAmount': components.fold<double>(0, (s, c) => s + c.amount), 'academicYear': '2026-2027',
          'academicYearId': yearId, 'isActive': true, 'createdBy': 't', 'createdAt': DateTime(2026, 1, 1),
          'components': [for (final c in components) c.toMap()],
        });
    await structure('day5', 'Monthly Day5', [_monthly(day: 5)]);
    await structure('day31', 'Monthly Day31', [_monthly(day: 31)]);
    await structure('noday', 'Monthly NoDay', [_monthly()]);
    await structure('term', 'Term Plain', [FeeComponentModel(name: 'T', amount: 20000, frequency: 'term', termName: 'Term 1', isOptional: false)]);
    await structure('termdated', 'Term Dated', [FeeComponentModel(name: 'T', amount: 9000, frequency: 'term', dueDate: DateTime(2026, 7, 15), isOptional: false)]);
  });

  Map<String, dynamic> single(String student, String structureId, {String? feeMonth, DateTime? dueDate, String classId = 'c1', String? year, double total = 3000}) => {
        'studentId': student, 'studentName': student, 'admissionNo': 'ADM-$student', 'classId': classId, 'className': classId == 'c1' ? 'Mont 1' : 'Mont 2',
        'feeStructureId': structureId, 'feeStructureName': structureId, 'academicYearId': year ?? yearId, 'academicYear': year == oldYearId ? '2025-2026' : '2026-2027',
        'totalFee': total, 'discountAmount': 0, 'payableAmount': total, 'paidAmount': 0, 'balanceAmount': total, 'status': 'unpaid',
        'feeMonth': ?feeMonth, 'dueDate': ?dueDate,
      };
  Future<Map<String, dynamic>> doc(String id) async => (await firestore.doc('student_fee_assignments/$id').get()).data()!;
  Future<List<Map<String, dynamic>>> all() async => [for (final d in (await firestore.collection('student_fee_assignments').get()).docs) {'id': d.id, ...d.data()}];
  DateTime? dueOf(Map<String, dynamic> data) => (data['dueDate'] as Timestamp?)?.toDate();

  group('service', () {
    test('stored as a Timestamp at local midnight; read back as that date; legacy reads without one', () async {
      final id = (await fees.assignFee(single('s1', 'day5', feeMonth: '2027-01', dueDate: DateTime(2027, 1, 5, 14, 30))))!;
      final data = await doc(id);
      expect(data['dueDate'], isA<Timestamp>());
      expect(dueOf(data), DateTime(2027, 1, 5));
      expect(StudentFeeAssignmentModel.fromMap(id, data).dueDate, DateTime(2027, 1, 5));
      expect(StudentFeeAssignmentModel.fromMap('old', single('s1', 'term')).dueDate, isNull);
    });

    test('1, 2. a monthly fee may be due in another month: the following one, or (chosen explicitly) the previous one', () async {
      final jun = (await fees.assignFee(single('s1', 'day5', feeMonth: '2026-06', dueDate: DateTime(2026, 7, 5))))!;
      final jan = (await fees.assignFee(single('s1', 'day5', feeMonth: '2027-01', dueDate: DateTime(2027, 2, 5))))!;
      final feb = (await fees.assignFee(single('s1', 'day5', feeMonth: '2027-02', dueDate: DateTime(2027, 1, 25))))!;
      expect([dueOf(await doc(jun)), dueOf(await doc(jan)), dueOf(await doc(feb))], [DateTime(2026, 7, 5), DateTime(2027, 2, 5), DateTime(2027, 1, 25)]);
      expect([(await doc(jun))['feeMonth'], (await doc(jan))['feeMonth']], ['2026-06', '2027-01'], reason: 'the fee month is unchanged');
    });

    test('4. Single Student: a missing, non-date or out-of-range due date is refused, and nothing is written', () async {
      await expectLater(fees.assignFee(single('s1', 'term')), throwsA(isA<StateError>().having((e) => e.message, 'message', FeeService.dueDateRequiredMessage)));
      await expectLater(fees.assignFee(single('s1', 'day5', feeMonth: '2027-01')), throwsA(isA<StateError>()));
      await expectLater(fees.assignFee({...single('s1', 'term'), 'dueDate': 'soon'}), throwsA(isA<StateError>()));
      await expectLater(fees.assignFee(single('s1', 'term', dueDate: DateTime(1900, 1, 1))), throwsA(isA<StateError>()));
      expect(await all(), isEmpty);
      expect(await fees.assignFee(single('s1', 'term', dueDate: DateTime(2026, 9, 30))), isNotNull);
    });

    test('6. the other creation path (sync from a structure) needs a due date before it creates anything', () async {
      Future<Map<String, int>> sync({DateTime? dueDate}) => fees.syncAssignmentsForFeeStructure(feeStructureId: 'term', feeStructureName: 'Term Plain',
          academicYearId: yearId, academicYear: '2026-2027', totalFee: 20000, assignmentScope: 'class', classIds: ['c1'], studentIds: const [], dueDate: dueDate);
      await expectLater(sync(), throwsA(isA<StateError>().having((e) => e.message, 'message', FeeService.dueDateRequiredMessage)));
      expect(await all(), isEmpty);
      expect(await sync(dueDate: DateTime(2026, 8, 31)), {'created': 2, 'updated': 0, 'skipped': 0, 'admissionSkipped': 0, 'manualReview': 0});
      expect({for (final a in await all()) dueOf(a)}, {DateTime(2026, 8, 31)});
      expect(await sync(), {'created': 0, 'updated': 2, 'skipped': 0, 'admissionSkipped': 0, 'manualReview': 0}, reason: 'updating existing assignments needs no new date');
      expect({for (final a in await all()) dueOf(a)}, {DateTime(2026, 8, 31)}, reason: 'kept');
    });

    test('5, 8. Full Class: one due date for every new assignment, required', () async {
      final r = await fees.bulkAssignClassFees(classId: 'c1', className: 'Mont 1', feeStructureId: 'day5', feeStructureName: 'Monthly Day5', academicYearId: yearId,
          academicYear: '2026-2027', totalFee: 3000, discountAmount: 0, feeMonth: '2027-03', dueDate: DateTime(2027, 3, 5));
      expect(r, {'assigned': 2, 'skipped': 0, 'admissionSkipped': 0, 'manualReview': 0, 'studentDiscounted': 0, 'discountConflict': 0});
      expect({for (final a in await all()) dueOf(a)}, {DateTime(2027, 3, 5)});
      await expectLater(
        fees.bulkAssignClassFees(classId: 'c1', className: 'Mont 1', feeStructureId: 'day5', feeStructureName: 'Monthly Day5', academicYearId: yearId,
            academicYear: '2026-2027', totalFee: 3000, discountAmount: 0, feeMonth: '2027-04'),
        throwsA(isA<StateError>().having((e) => e.message, 'message', FeeService.dueDateRequiredMessage)),
      );
      expect(await all(), hasLength(2), reason: 'nothing written for April');
      final may = await fees.bulkAssignClassFees(classId: 'c1', className: 'Mont 1', feeStructureId: 'day5', feeStructureName: 'Monthly Day5', academicYearId: yearId,
          academicYear: '2026-2027', totalFee: 3000, discountAmount: 0, feeMonth: '2027-04', dueDate: DateTime(2027, 5, 5));
      expect(may['assigned'], 2, reason: 'April’s fee due in May');
    });

    test('7, 8, 9, 10, 11. edits keep the date unless given; a month move keeps it; a structure change touches nothing; a legacy one stays undated or is given a date', () async {
      final id = (await fees.assignFee(single('s1', 'day5', feeMonth: '2027-01', dueDate: DateTime(2027, 1, 5))))!;
      await fees.updateAssignment(id, {'discountAmount': 100});
      expect(dueOf(await doc(id)), DateTime(2027, 1, 5), reason: 'kept');
      await fees.updateAssignment(id, {'dueDate': DateTime(2027, 1, 20)});
      expect(dueOf(await doc(id)), DateTime(2027, 1, 20));
      await fees.updateAssignment(id, {'feeMonth': '2027-02'});
      expect([(await doc(id))['feeMonth'], dueOf(await doc(id))], ['2027-02', DateTime(2027, 1, 20)], reason: 'the due date is independent of the month');
      await fees.updateAssignment(id, {'dueDate': DateTime(2027, 2, 5)});
      expect(dueOf(await doc(id)), DateTime(2027, 2, 5));

      await firestore.collection('fee_structures').doc('day5').update({
        'components': [_monthly(day: 25).toMap()],
      });
      expect(dueOf(await doc(id)), DateTime(2027, 2, 5), reason: 'the structure’s new due day doesn’t reach existing assignments');

      final legacy = await firestore.collection('student_fee_assignments').add(single('s2', 'term'));
      expect(StudentFeeAssignmentModel.fromMap(legacy.id, await doc(legacy.id)).dueDate, isNull, reason: 'readable without one');
      await fees.updateAssignment(legacy.id, {'discountAmount': 0});
      expect((await doc(legacy.id)).containsKey('dueDate'), isFalse, reason: 'never inferred');
      await fees.updateAssignment(legacy.id, {'dueDate': DateTime(2026, 12, 15)});
      expect(dueOf(await doc(legacy.id)), DateTime(2026, 12, 15), reason: 'added explicitly');
    });

    test('18, 30. a voided payment puts the balance back, so it is overdue again; one Finance entry per collection', () async {
      final id = (await fees.assignFee(single('s1', 'term', dueDate: DateTime(2026, 7, 1), total: 20000)))!;
      final today = DateTime(2026, 11, 6);
      Future<bool> overdue() async => FeeDueDate.isOverdue(StudentFeeAssignmentModel.fromMap(id, await doc(id)), today);
      expect(await overdue(), isTrue);
      final r = await fees.collectFee(assignmentId: id, amount: 20000, paymentDate: DateTime(2026, 11, 1), paymentMode: 'cash', referenceNo: '', remarks: '');
      expect(await overdue(), isFalse, reason: 'paid in full');
      await fees.voidReceipt(r.id);
      expect(await overdue(), isTrue);
      final ledger = (await firestore.collection('finance_ledger').get()).docs;
      expect(ledger.length, 1);
      expect(ledger.single.data()['status'], 'cancelled');
    });

    test('32. the dashboard summary: unchanged except Overdue Students, now distinct students past a due date', () async {
      await fees.assignFee(single('s1', 'term', dueDate: DateTime(2026, 7, 1), total: 20000));
      await fees.assignFee(single('s1', 'day5', feeMonth: '2026-08', dueDate: DateTime(2026, 8, 5)));
      // An older assignment, stored as overdue but with no due date.
      await firestore.collection('student_fee_assignments').add({...single('s2', 'termdated', total: 9000), 'status': 'overdue'});
      final s = await fees.getDashboardSummary();
      expect([s['totalExpected'], s['totalCollected'], s['outstanding']], [32000, 0, 32000]);
      expect(s['overdueStudents'], 1, reason: 'Anu once (two overdue); Bala has no due date');
    });
  });

  // ---------------------------------------------------------------- dialog
  group('Assign Fee dialog', () {
    Future<void> pumpDialog(WidgetTester tester, {StudentFeeAssignmentModel? edit}) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore))],
        child: MaterialApp(home: Scaffold(body: FeeAssignmentDialog(assignment: edit, service: fees))),
      ));
      await tester.pumpAndSettle();
    }

    Finder field(String label) => find.widgetWithText(DropdownButtonFormField<String>, label);
    Finder key(String k) => find.byKey(Key(k));
    Future<void> choose(WidgetTester tester, Finder dropdown, String option) async {
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(option).last);
      await tester.pumpAndSettle();
    }

    Future<void> pickDueDay(WidgetTester tester, int day) async {
      await tester.ensureVisible(key('fee-due-date-pick'));
      await tester.pumpAndSettle();
      await tester.tap(key('fee-due-date-pick'));
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

    String dueShown(WidgetTester tester) => tester.widget<Text>(key('fee-due-date-value')).data!;

    Future<void> start(WidgetTester tester, String structure, {String? month, bool bulk = false}) async {
      await pumpDialog(tester);
      if (bulk) {
        await tester.tap(find.text('Full Class'));
        await tester.pumpAndSettle();
      }
      await choose(tester, field('Select Class *'), 'Mont 1');
      if (!bulk) await choose(tester, field('Select Student *'), 'Anu');
      await choose(tester, field('Fee Structure *'), structure);
      if (month != null) await choose(tester, key('fee-month'), month);
    }

    testWidgets('1, 7. Single Student, monthly: defaults to the structure’s due day in the chosen month, and saves it', (tester) async {
      await start(tester, 'Monthly Day5');
      expect(dueShown(tester), 'Choose a date', reason: 'no month yet');
      await choose(tester, key('fee-month'), 'January 2027');
      expect(dueShown(tester), '5 Jan 2027');
      expect(find.textContaining('Defaults to the structure’s due day (5)'), findsOneWidget);
      await save(tester);
      expect(dueOf((await tester.runAsync(all))!.single), DateTime(2027, 1, 5));
    });

    testWidgets('2. the default can be overridden; choosing another month suggests that month’s default again', (tester) async {
      await start(tester, 'Monthly Day5', month: 'January 2027');
      await pickDueDay(tester, 20);
      expect(dueShown(tester), '20 Jan 2027');
      await choose(tester, key('fee-month'), 'February 2027');
      expect(dueShown(tester), '5 Feb 2027');
      await pickDueDay(tester, 12);
      await save(tester);
      expect(dueOf((await tester.runAsync(all))!.single), DateTime(2027, 2, 12));
    });

    testWidgets('1. an override may be in another month (the picker isn’t limited to the fee month)', (tester) async {
      await start(tester, 'Monthly Day5', month: 'January 2027');
      await tester.ensureVisible(key('fee-due-date-pick'));
      await tester.pumpAndSettle();
      await tester.tap(key('fee-due-date-pick'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(dueShown(tester), '5 Feb 2027');
      await choose(tester, field('Fee Structure *'), 'Monthly Day31');
      expect(dueShown(tester), '5 Feb 2027', reason: 'an intentional override survives a structure change');
      await save(tester);
      final saved = (await tester.runAsync(all))!.single;
      expect([saved['feeMonth'], dueOf(saved)], ['2027-01', DateTime(2027, 2, 5)], reason: 'January’s fee, due 5 February');
    });

    testWidgets('3. no due day on the structure: a date must be chosen', (tester) async {
      await start(tester, 'Monthly NoDay', month: 'January 2027');
      expect(dueShown(tester), 'Choose a date');
      expect(find.textContaining('no due day of month set'), findsOneWidget);
      await save(tester);
      expect(find.text('Choose the due date'), findsOneWidget);
      expect(await tester.runAsync(all), isEmpty);
      await pickDueDay(tester, 9);
      await save(tester);
      expect(dueOf((await tester.runAsync(all))!.single), DateTime(2027, 1, 9));
    });

    testWidgets('4. non-monthly: an explicit date, or the structure’s own due date', (tester) async {
      await start(tester, 'Term Plain');
      expect(dueShown(tester), 'Choose a date');
      await save(tester);
      expect(find.text('Choose the due date'), findsOneWidget);
      await pickDueDay(tester, 15);
      await save(tester);
      expect(dueOf((await tester.runAsync(all))!.single)!.day, 15);
    });

    testWidgets('4. a structure with its own due date offers it', (tester) async {
      await start(tester, 'Term Dated');
      expect(dueShown(tester), '15 Jul 2026');
    });

    testWidgets('5. the 31st in February is its last day', (tester) async {
      await start(tester, 'Monthly Day31', month: 'February 2027');
      expect(dueShown(tester), '28 Feb 2027');
      expect(find.textContaining('has no day 31'), findsOneWidget);
    });

    testWidgets('8. Full Class: one date for the batch, said so, saved on every assignment', (tester) async {
      await start(tester, 'Monthly Day5', month: 'March 2027', bulk: true);
      expect(find.textContaining('Applies to every student assigned in this class'), findsOneWidget);
      expect(dueShown(tester), '5 Mar 2027');
      await save(tester);
      await tester.tap(key('fee-bulk-confirm-ok'));
      await tester.pumpAndSettle();
      final saved = (await tester.runAsync(all))!;
      expect(saved, hasLength(2));
      expect({for (final a in saved) dueOf(a)}, {DateTime(2027, 3, 5)});
    });

    testWidgets('9. Edit: shows the stored date (not the structure’s), and saves a change', (tester) async {
      final id = (await tester.runAsync(() => fees.assignFee(single('s1', 'day5', feeMonth: '2027-01', dueDate: DateTime(2027, 1, 8)))))!;
      await pumpDialog(tester, edit: StudentFeeAssignmentModel.fromMap(id, (await tester.runAsync(() => doc(id)))!));
      expect(dueShown(tester), '8 Jan 2027');
      await pickDueDay(tester, 25);
      await save(tester);
      expect(dueOf((await tester.runAsync(() => doc(id)))!), DateTime(2027, 1, 25));
    });

    testWidgets('11, 12. Edit a legacy assignment: "Due date not set", nothing inferred, it can be left unset', (tester) async {
      final ref = (await tester.runAsync(() => firestore.collection('student_fee_assignments').add(single('s1', 'day5', feeMonth: '2027-01'))))!;
      await pumpDialog(tester, edit: StudentFeeAssignmentModel.fromMap(ref.id, (await tester.runAsync(() => doc(ref.id)))!));
      expect(dueShown(tester), 'Due date not set');
      expect(find.textContaining('no due date recorded'), findsOneWidget);
      await save(tester);
      expect((await tester.runAsync(() => doc(ref.id)))!.containsKey('dueDate'), isFalse);
    });

    testWidgets('8. Edit a legacy assignment: a date can be added', (tester) async {
      final ref = (await tester.runAsync(() => firestore.collection('student_fee_assignments').add(single('s1', 'day5', feeMonth: '2027-01'))))!;
      await pumpDialog(tester, edit: StudentFeeAssignmentModel.fromMap(ref.id, (await tester.runAsync(() => doc(ref.id)))!));
      await pickDueDay(tester, 12);
      await save(tester);
      expect(dueOf((await tester.runAsync(() => doc(ref.id)))!)!.day, 12);
    });
  });

  // ---------------------------------------------------------------- screen
  group('Fees screen', () {
    Finder key(String k) => find.byKey(Key(k));
    Future<void> pumpFees(WidgetTester tester, String tab, {required DateTime Function() clock, Size size = const Size(1400, 2600)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore))],
        child: MaterialApp(home: AdminFeesScreen(service: fees, clock: clock)),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, tab));
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    String overdueCard(WidgetTester tester) => tester.widget<Text>(find.descendant(of: key('fees-overview-overdue'), matching: find.byType(Text)).at(1)).data!;

    /// Anu: two overdue (Mont 1); Bala: one overdue; Chitra (now Mont 2):
    /// last year's Mont 1 fee overdue, this year's not yet due; a legacy
    /// one with no due date; one paid past its date.
    Future<Map<String, String>> seed() async {
      final ids = <String, String>{
        'anu-jan': (await fees.assignFee(single('s1', 'day5', feeMonth: '2026-09', dueDate: DateTime(2026, 9, 5))))!,
        'anu-term': (await fees.assignFee(single('s1', 'term', dueDate: DateTime(2026, 7, 1), total: 20000)))!,
        'bala': (await fees.assignFee(single('s2', 'term', dueDate: DateTime(2026, 10, 1), total: 20000)))!,
        'chitra-old': (await fees.assignFee(single('s3', 'term', year: oldYearId, dueDate: DateTime(2026, 1, 10), total: 5000)))!,
        'chitra-now': (await fees.assignFee(single('s3', 'term', classId: 'c2', dueDate: DateTime(2026, 12, 1), total: 20000)))!,
        'paid': (await fees.assignFee(single('s2', 'day5', feeMonth: '2026-08', dueDate: DateTime(2026, 8, 5))))!,
      };
      ids['legacy'] = (await firestore.collection('student_fee_assignments').add({...single('s1', 'day5', feeMonth: '2026-10'), 'assignedAt': DateTime(2026, 6, 1)})).id;
      await fees.collectFee(assignmentId: ids['paid']!, amount: 3000, paymentDate: DateTime(2026, 8, 1), paymentMode: 'cash', referenceNo: '', remarks: '');
      await fees.collectFee(assignmentId: ids['anu-term']!, amount: 5000, paymentDate: DateTime(2026, 7, 1), paymentMode: 'cash', referenceNo: '', remarks: '');
      return ids;
    }

    Future<void> chooseFilter(WidgetTester tester, String filter, String label) async {
      await tap(tester, key('fees-filter-$filter'));
      await tap(tester, find.text(label).last);
    }

    testWidgets('6, 28. Assignments, Collections and Dues show the due date, an Overdue label with its balance, or "Due date not set"', (tester) async {
      final ids = await seed();
      await pumpFees(tester, 'Assignments', clock: () => DateTime(2026, 11, 6));
      expect(key('fees-overdue-${ids['anu-term']}'), findsOneWidget);
      expect(find.text('Overdue • due 1 Jul 2026 • outstanding 15000'), findsOneWidget, reason: 'partly paid, still overdue');
      expect(find.text('Overdue • due 5 Sep 2026 • outstanding 3000'), findsOneWidget);
      expect(find.text('Due 1 Dec 2026'), findsOneWidget);
      expect(find.text('Due 5 Aug 2026'), findsOneWidget, reason: 'paid: not overdue');
      expect(key('fees-overdue-${ids['paid']}'), findsNothing);
      expect(find.text('Due date not set'), findsOneWidget);
      for (final t in ['Collections', 'Dues']) {
        await tap(tester, find.widgetWithText(ChoiceChip, t));
        expect(find.text('Overdue • due 1 Oct 2026 • outstanding 20000'), findsOneWidget, reason: t);
        expect(key('fees-overdue-${ids['bala']}'), findsOneWidget, reason: t);
        expect(find.text('Due date not set'), findsOneWidget, reason: t);
      }
      await tap(tester, find.widgetWithText(ChoiceChip, 'Students'));
      expect(find.text('Overdue'), findsNothing, reason: 'students are not labelled overdue');
    });

    testWidgets('21–24. Overdue Students: distinct students, following year, class (as recorded on the assignment) and student', (tester) async {
      await seed();
      await pumpFees(tester, 'Assignments', clock: () => DateTime(2026, 11, 6));
      expect(overdueCard(tester), '2', reason: 'Anu once for two overdue; Bala');
      expect(find.text('Distinct students with an overdue balance'), findsOneWidget);
      await chooseFilter(tester, 'year', 'All Academic Years');
      expect(overdueCard(tester), '3', reason: 'Chitra’s overdue fee from last year');
      await chooseFilter(tester, 'class', 'Mont 2');
      expect(overdueCard(tester), '0', reason: 'Chitra is in Mont 2 now, but her overdue fee was recorded under Mont 1');
      await chooseFilter(tester, 'class', 'Mont 1');
      expect(overdueCard(tester), '3');
      await tap(tester, key('fees-filter-student'));
      await tap(tester, key('fees-student-option-s1'));
      expect(overdueCard(tester), '1');
      await tap(tester, key('fees-filter-reset'));
      expect(overdueCard(tester), '2');
    });

    testWidgets('25. the card moves to the new day at local midnight while the screen is open', (tester) async {
      await fees.assignFee(single('s1', 'term', dueDate: DateTime(2026, 11, 6), total: 20000));
      var now = DateTime(2026, 11, 6, 23, 59, 30);
      await pumpFees(tester, 'Assignments', clock: () => now);
      expect(overdueCard(tester), '0', reason: 'due today');
      now = DateTime(2026, 11, 7, 0, 0, 1);
      await tester.pump(const Duration(seconds: 32));
      expect(overdueCard(tester), '1');
      expect(find.text('Overdue • due 6 Nov 2026 • outstanding 20000'), findsOneWidget);
    });

    testWidgets('29, 31. Student Fee History and Collection Details show the due date and Overdue, read-only', (tester) async {
      final ids = await seed();
      await pumpFees(tester, 'Students', clock: () => DateTime(2026, 11, 6));
      await tap(tester, key('student-view-history-s1'));
      expect(tester.widget<Text>(find.descendant(of: key('student-history-due-date-${ids['anu-term']}'), matching: find.byType(Text)).last).data, '1 Jul 2026');
      expect(key('student-history-overdue-${ids['anu-term']}'), findsOneWidget);
      expect(find.descendant(of: key('student-history-overdue-${ids['anu-term']}'), matching: find.text('Overdue • outstanding ₹15,000')), findsOneWidget);
      expect(tester.widget<Text>(find.descendant(of: key('student-history-due-date-${ids['legacy']}'), matching: find.byType(Text)).last).data, 'Due date not set');
      await tap(tester, key('student-history-close'));
      await tap(tester, find.widgetWithText(ChoiceChip, 'Collections'));
      final before = firestore.dump();
      await tap(tester, key('collection-view-details-${ids['bala']}'));
      expect(key('collection-details-overdue-${ids['bala']}'), findsOneWidget);
      await tap(tester, key('collection-details-close'));
      expect(firestore.dump(), before);
    });

    testWidgets('26, 27. monthly assignments stay separate: each month its own due date and status', (tester) async {
      final jan = (await fees.assignFee(single('s1', 'day5', feeMonth: '2026-10', dueDate: DateTime(2026, 10, 5))))!;
      final nov = (await fees.assignFee(single('s1', 'day5', feeMonth: '2026-11', dueDate: DateTime(2026, 11, 5))))!;
      final dec = (await fees.assignFee(single('s1', 'day5', feeMonth: '2026-12', dueDate: DateTime(2026, 12, 5))))!;
      await fees.collectFee(assignmentId: nov, amount: 3000, paymentDate: DateTime(2026, 11, 2), paymentMode: 'upi', referenceNo: '', remarks: '');
      await pumpFees(tester, 'Dues', clock: () => DateTime(2026, 11, 6));
      expect(key('fees-overdue-$jan'), findsOneWidget);
      expect(key('fees-overdue-$nov'), findsNothing, reason: 'paid, and not in Dues');
      expect(key('fees-overdue-$dec'), findsNothing);
      expect(find.text('Due 5 Dec 2026'), findsOneWidget);
      expect(overdueCard(tester), '1');
    });
  });

  // ---------------------------------------------------------------- structure due day
  group('structure Due Day of Month', () {
    test('10, 11, 12. 1 to 31 or empty; not 0, negative, decimal, above 31 or text', () {
      for (final ok in <Object?>[1, 31, 15, '1', '31', ' 7 ', '', null]) {
        expect(FeeService.dueDayOfMonthError(ok), isNull, reason: '$ok');
      }
      for (final bad in <Object?>[0, -1, 32, 5.5, 5.0, '0', '-3', '32', '5.5', 'abc']) {
        expect(FeeService.dueDayOfMonthError(bad), FeeService.dueDayOfMonthMessage, reason: '$bad');
      }
    });

    test('the service refuses an invalid due day on create and update; empty and valid days save', () async {
      Map<String, dynamic> data(Object? day) => {
            'name': 'S', 'academicYearId': yearId, 'academicYear': '2026-2027', 'totalAmount': 1, 'isActive': true,
            'components': [{'name': 'C', 'amount': 1, 'frequency': 'monthly', 'dueDayOfMonth': day, 'isOptional': false}],
          };
      final before = (await firestore.collection('fee_structures').get()).docs.length;
      for (final bad in <Object?>[0, -2, 32, 2.5]) {
        await expectLater(fees.createFeeStructure(data(bad)), throwsA(isA<StateError>()), reason: '$bad');
      }
      expect((await firestore.collection('fee_structures').get()).docs.length, before);
      final id = await fees.createFeeStructure(data(31));
      await fees.createFeeStructure(data(null));
      await expectLater(fees.updateFeeStructure(id, data(40)), throwsA(isA<StateError>()));
      expect(((await firestore.doc('fee_structures/$id').get()).data()!['components'] as List).single['dueDayOfMonth'], 31, reason: 'unchanged');
      await fees.updateFeeStructure(id, data(1));
      expect(FeeStructureModel.fromMap(id, (await firestore.doc('fee_structures/day5').get()).data()!).components.single.dueDayOfMonth, 5,
          reason: 'existing structures still read');
    });

    testWidgets('the Add Component form shows the rule and won’t add an invalid day', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore))],
        child: MaterialApp(home: Scaffold(body: FeeStructureDialog(service: fees))),
      ));
      await tester.pumpAndSettle();
      Future<void> add(String day) async {
        await tester.tap(find.text('Add Component'));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextField, 'Component Name *'), 'Care');
        await tester.enterText(find.widgetWithText(TextField, 'Amount *'), '3000');
        await tester.enterText(find.byKey(const Key('fee-component-due-day')), day);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Add'));
        await tester.pumpAndSettle();
      }

      for (final bad in ['0', '32', '-1', '5.5']) {
        await add(bad);
        expect(find.text(FeeService.dueDayOfMonthMessage), findsOneWidget, reason: bad);
        expect(find.text('Add Component'), findsNWidgets(2), reason: 'still open');
        await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
        await tester.pumpAndSettle();
      }
      await add('31');
      expect(find.text(FeeService.dueDayOfMonthMessage), findsNothing);
      expect(find.textContaining('Care'), findsWidgets, reason: 'added');
      await add('');
      expect(find.text(FeeService.dueDayOfMonthMessage), findsNothing, reason: 'empty is fine');
    });
  });
}

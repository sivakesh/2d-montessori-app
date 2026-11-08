// Fees: recurring monthly assignments (Start Fee Month to Assign Until,
// one assignment per student per month, each with its own due date), the
// Fee Month filter and month sections on Collections, Receipts, Dues and
// Assignments, and the tab order (Collections first). Synthetic test data
// only.
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
import 'package:montessori_app/modules/fees/models/fee_component_model.dart';
import 'package:montessori_app/modules/fees/models/fee_month_range.dart';
import 'package:montessori_app/modules/fees/models/fee_student.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/admin_fees_screen.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_assignment_dialog.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_collection_dialog.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_structure_dialog.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';

import 'support/buffered_transaction_firestore.dart';

/// Counts batches, and can fail the [failOn]th commit.
class _CountingFirestore extends BufferedTransactionFirestore {
  int batches = 0;
  int? failOn;

  @override
  WriteBatch batch() {
    batches++;
    return _Batch(super.batch(), batches == failOn);
  }
}

class _Batch implements WriteBatch {
  _Batch(this._inner, this._fail);
  final WriteBatch _inner;
  final bool _fail;
  int writes = 0;

  @override
  Future<void> commit() {
    if (_fail) throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable', message: 'Injected batch failure');
    return _inner.commit();
  }

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    writes++;
    _inner.set(document, data, options);
  }

  @override
  void update<T>(DocumentReference<T> document, T data) => _inner.update(document, data);

  @override
  void delete(DocumentReference document) => _inner.delete(document);
}

AcademicYearModel _year(String id, String name, DateTime start, DateTime end) =>
    AcademicYearModel(id: id, schoolId: 's', name: name, startDate: start, endDate: end, isCurrent: false, isActive: true, createdAt: start, updatedAt: start);

void main() {
  // ---------------------------------------------------------------- ranges
  group('month ranges and due rules', () {
    final years = [
      _year('y26', '2026-2027', DateTime(2026, 6, 1), DateTime(2027, 5, 31)),
      _year('y27', '2027-2028', DateTime(2027, 6, 1), DateTime(2028, 5, 31)),
    ];

    test('start and end both included; reversed or invalid ranges are empty', () {
      expect(FeeMonthRange.months('2026-06', '2027-03'), hasLength(10));
      expect(FeeMonthRange.months('2026-06', '2027-03').first, '2026-06');
      expect(FeeMonthRange.months('2026-06', '2027-03').last, '2027-03');
      expect(FeeMonthRange.months('2027-01', '2027-01'), ['2027-01']);
      expect(FeeMonthRange.months('2027-03', '2026-06'), isEmpty);
      expect(FeeMonthRange.summary(FeeMonthRange.months('2026-06', '2027-03')), 'June 2026 – March 2027 (10 monthly assignments)');
      expect(() => FeeMonthRange.plan('2027-03', '2026-06', years, const FeeDueRule(day: 5)), throwsA(isA<StateError>()));
    });

    test('each month takes the academic year containing it (any start month), across a year boundary', () {
      final plans = FeeMonthRange.plan('2027-04', '2027-07', years, const FeeDueRule(day: 5));
      expect([for (final p in plans) (p.feeMonth, p.academicYear)], [
        ('2027-04', '2026-2027'), ('2027-05', '2026-2027'), ('2027-06', '2027-2028'), ('2027-07', '2027-2028'),
      ]);
      final aprilYears = [_year('a', '2026-27 (Apr)', DateTime(2026, 4, 1), DateTime(2027, 3, 31))];
      expect(FeeMonthRange.yearOf('2027-03', aprilYears)?.id, 'a');
      expect(FeeMonthRange.yearOf('2027-04', aprilYears), isNull);
      expect(() => FeeMonthRange.plan('2028-05', '2028-06', years, const FeeDueRule(day: 5)), throwsA(isA<StateError>()), reason: 'June 2028 is in no year');
    });

    test('due dates per month: the same day, the last day of a shorter month (leap years too), or the following month', () {
      expect([for (final m in ['2027-01', '2027-02', '2028-02', '2026-06']) const FeeDueRule(day: 31).dueFor(m)],
          [DateTime(2027, 1, 31), DateTime(2027, 2, 28), DateTime(2028, 2, 29), DateTime(2026, 6, 30)]);
      expect(const FeeDueRule(day: 5, monthOffset: 1).dueFor('2027-01'), DateTime(2027, 2, 5), reason: 'January’s fee due 5 February');
      expect(const FeeDueRule(day: 31, monthOffset: 1).dueFor('2026-12'), DateTime(2027, 1, 31), reason: 'across a year end');
    });
  });

  // ---------------------------------------------------------------- service
  late _CountingFirestore firestore;
  late FeeService fees;
  late String y26, y27;
  late AcademicYearService yearService;

  setUp(() async {
    firestore = _CountingFirestore();
    final auth = MockFirebaseAuth();
    final finance = FinanceService(firestore: firestore, auth: auth);
    await finance.ensureDefaults();
    fees = FeeService(firestore: firestore, auth: auth, storage: MockFirebaseStorage(), financeService: finance);
    yearService = AcademicYearService(firestore: firestore);
    y26 = await yearService.createAcademicYear(schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2026-2027',
        startDate: DateTime(2026, 6, 1), endDate: DateTime(2027, 5, 31), createdBy: 'admin-1', setAsCurrent: true);
    y27 = await yearService.createAcademicYear(schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2027-2028',
        startDate: DateTime(2027, 6, 1), endDate: DateTime(2028, 5, 31), createdBy: 'admin-1');
    await firestore.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
    await firestore.collection('classes').doc('c2').set({'name': 'Mont 2', 'isActive': true});
    for (final (id, name, cls) in [('s1', 'Anu', 'c1'), ('s2', 'Bala', 'c1'), ('s3', 'Chitra', 'c1'), ('s4', 'Dev', 'c2')]) {
      await firestore.collection('students').doc(id).set({'name': name, 'admissionNo': 'ADM-$id', 'classId': cls, 'isActive': true, 'admissionDate': DateTime(2020, 1, 1)}); // admitted long before every fee month (Admission Date rule)
    }
    Future<void> structure(String id, String name, List<FeeComponentModel> components) => firestore.collection('fee_structures').doc(id).set({
          'name': name, 'description': '', 'totalAmount': components.fold<double>(0, (s, c) => s + c.amount), 'academicYear': '2026-2027',
          'academicYearId': y26, 'isActive': true, 'createdBy': 't', 'createdAt': DateTime(2026, 1, 1),
          'components': [for (final c in components) c.toMap()],
        });
    FeeComponentModel monthly({int? day}) => FeeComponentModel(name: 'Care', amount: 3000, frequency: 'monthly', dueDayOfMonth: day, isOptional: false);
    await structure('day5', 'Monthly Day5', [monthly(day: 5)]);
    await structure('day31', 'Monthly Day31', [monthly(day: 31)]);
    await structure('noday', 'Monthly NoDay', [monthly()]);
    await structure('term', 'Term Plain', [FeeComponentModel(name: 'T', amount: 20000, frequency: 'term', termName: 'Term 1', isOptional: false)]);
  });

  List<FeeStudent> students(Iterable<String> ids) => [for (final id in ids) FeeStudent(id: id, name: 'Student $id', admissionNo: 'ADM-$id', classId: 'c1')];
  Future<List<AcademicYearModel>> years() => yearService.getAllAcademicYears(schoolId: kDefaultSchoolId);
  Future<FeeRecurringResult> assign(Iterable<String> ids, String start, String end, {String structure = 'day5', FeeDueRule rule = const FeeDueRule(day: 5)}) async {
    // Every student needs a record with an Admission Date (the recurring
    // path reads it); ids without one get an admitted record here.
    for (final id in ids) {
      final ref = firestore.collection('students').doc(id);
      if (!(await ref.get()).exists) await ref.set({'name': 'Student $id', 'classId': 'c1', 'isActive': true, 'admissionDate': DateTime(2020, 1, 1)});
    }
    return fees.assignMonthlyFees(
        students: students(ids), classId: 'c1', className: 'Mont 1', feeStructureId: structure, feeStructureName: structure,
        months: FeeMonthRange.plan(start, end, await years(), rule), totalFee: 3000, discountAmount: 500,
      );
  }
  Future<List<Map<String, dynamic>>> all() async => [for (final d in (await firestore.collection('student_fee_assignments').get()).docs) {'id': d.id, ...d.data()}];
  DateTime? dueOf(Map<String, dynamic> a) => (a['dueDate'] as Timestamp?)?.toDate();

  group('recurring assignments (service)', () {
    test('one student, one month', () async {
      final r = await assign(['s1'], '2027-01', '2027-01');
      expect([r.created, r.skipped, r.failed], [1, 0, 0]);
      final a = (await all()).single;
      expect([a['feeMonth'], dueOf(a), a['payableAmount'], a['paidAmount'], a['balanceAmount'], a['status']], ['2027-01', DateTime(2027, 1, 5), 2500, 0, 2500, 'unpaid']);
    });

    test('one student across months: a separate assignment each, start and end included, each with its own year and due date', () async {
      final r = await assign(['s1'], '2027-03', '2027-07');
      expect(r.created, 5);
      final list = (await all())..sort((a, b) => (a['feeMonth'] as String).compareTo(b['feeMonth'] as String));
      expect([for (final a in list) a['feeMonth']], ['2027-03', '2027-04', '2027-05', '2027-06', '2027-07']);
      expect([for (final a in list) a['academicYearId']], [y26, y26, y26, y27, y27], reason: 'June 2027 is in 2027-2028');
      expect([for (final a in list) dueOf(a)], [for (final m in [3, 4, 5, 6, 7]) DateTime(2027, m, 5)]);
      expect(list.map((a) => a['balanceAmount']).toSet(), {2500});
    });

    test('February and leap years with a day-31 structure', () async {
      await assign(['s1'], '2027-12', '2028-03', structure: 'day31', rule: const FeeDueRule(day: 31));
      final list = (await all())..sort((a, b) => (a['feeMonth'] as String).compareTo(b['feeMonth'] as String));
      expect([for (final a in list) dueOf(a)], [DateTime(2027, 12, 31), DateTime(2028, 1, 31), DateTime(2028, 2, 29), DateTime(2028, 3, 31)]);
    });

    test('Full Class across months: every student, every month, once each', () async {
      final r = await assign(['s1', 's2', 's3', 's1'], '2026-11', '2027-01');
      expect([r.created, r.skipped], [9, 0], reason: 'a student listed twice is assigned once');
      final keys = [for (final a in await all()) '${a['studentId']}/${a['feeMonth']}'];
      expect(keys.toSet().length, keys.length);
      expect(keys.length, 9);
      final again = await assign(['s1', 's2', 's3'], '2026-11', '2027-01');
      expect([again.created, again.skipped], [0, 9], reason: 'exactly one per student and month');
    });

    test('an existing month is skipped only for that student and month; an older one with no month blocks that structure’s year', () async {
      await fees.assignFee({'studentId': 's1', 'studentName': 'Anu', 'classId': 'c1', 'className': 'Mont 1', 'feeStructureId': 'day5', 'feeStructureName': 'day5',
        'academicYearId': y26, 'academicYear': '2026-2027', 'totalFee': 3000, 'discountAmount': 0, 'payableAmount': 3000, 'paidAmount': 0, 'balanceAmount': 3000,
        'status': 'unpaid', 'feeMonth': '2027-01', 'dueDate': DateTime(2027, 1, 5)});
      await firestore.collection('student_fee_assignments').add({'studentId': 's2', 'feeStructureId': 'day5', 'academicYearId': y26, 'academicYear': '2026-2027', 'totalFee': 3000});
      final r = await assign(['s1', 's2', 's3'], '2026-12', '2027-06');
      // s1: 7 months less January; s2: only June 2027 (another year); s3: 7.
      expect([r.created, r.skipped, r.failed], [6 + 1 + 7, 1 + 6, 0]);
      final s1 = [for (final a in await all()) if (a['studentId'] == 's1') a['feeMonth']]..sort();
      expect(s1, ['2026-12', '2027-01', '2027-02', '2027-03', '2027-04', '2027-05', '2027-06']);
      expect([for (final a in await all()) if (a['studentId'] == 's2' && a['feeMonth'] != null) a['feeMonth']], ['2027-06']);
    });

    test('the whole request is checked first: nothing is written when any month is invalid', () async {
      final plans = FeeMonthRange.plan('2027-01', '2027-03', await years(), const FeeDueRule(day: 5));
      final batchesBefore = firestore.batches;
      Future<FeeRecurringResult> run(List<FeeMonthPlan> months, {String structure = 'day5', double discount = 0}) => fees.assignMonthlyFees(
          students: students(['s1', 's2']), classId: 'c1', className: 'Mont 1', feeStructureId: structure, feeStructureName: structure,
          months: months, totalFee: 3000, discountAmount: discount);
      final badDue = [...plans.take(2), FeeMonthPlan(feeMonth: '2027-03', academicYearId: y26, academicYear: '2026-2027', dueDate: DateTime(1900))];
      await expectLater(run(badDue), throwsA(isA<StateError>()));
      await expectLater(run(plans.reversed.toList()), throwsA(isA<StateError>()), reason: 'out of order');
      await expectLater(run([plans.first, plans.first]), throwsA(isA<StateError>()), reason: 'a month twice');
      await expectLater(run(plans, structure: 'term'), throwsA(isA<StateError>()), reason: 'not monthly');
      await expectLater(run(plans, discount: 5000), throwsA(isA<StateError>()));
      await expectLater(run(const []), throwsA(isA<StateError>()));
      expect(await all(), isEmpty);
      expect(firestore.batches, batchesBefore, reason: 'no batch was even started');
    });

    test('large requests are written in batches of at most 400; a failed batch is reported, not claimed', () async {
      final many = [for (var i = 0; i < 41; i++) 'x$i'];
      final batchesBefore = firestore.batches;
      final r = await assign(many, '2026-06', '2027-03');
      expect([r.created, r.failed], [410, 0]);
      expect(firestore.batches - batchesBefore, 2, reason: '410 writes: 400 + 10');
      expect((await all()).length, 410);

      firestore.failOn = firestore.batches + 2;
      final r2 = await assign([for (var i = 0; i < 41; i++) 'z$i'], '2026-06', '2027-03');
      expect([r2.created, r2.failed], [400, 10]);
      expect(r2.error, contains('Injected batch failure'));
      expect(r2.message, startsWith('Created 400 assignments, skipped 0 as duplicates, skipped 0 before admission, 0 need manual review, failed 10.'));
    });

    test('no collection, receipt or Finance entry is created; a collection then makes exactly one', () async {
      await assign(['s1', 's2'], '2026-11', '2027-01');
      expect((await firestore.collection('fee_receipts').get()).docs, isEmpty);
      expect((await firestore.collection('fee_transactions').get()).docs, isEmpty);
      expect((await firestore.collection('finance_ledger').get()).docs, isEmpty);
      final jan = (await all()).firstWhere((a) => a['studentId'] == 's1' && a['feeMonth'] == '2027-01');
      await fees.collectFee(assignmentId: jan['id'] as String, amount: 1000, paymentDate: DateTime(2027, 1, 3), paymentMode: 'cash', referenceNo: '', remarks: '');
      final ledger = (await firestore.collection('finance_ledger').get()).docs;
      expect(ledger.length, 1);
      expect(ledger.single.data().toString(), contains('January 2027'));
      expect((await all()).where((a) => (a['paidAmount'] as num) > 0).single['feeMonth'], '2027-01', reason: 'only that month is paid');
    });
  });

  // ---------------------------------------------------------------- dialog
  group('Assign Fee dialog (recurring)', () {
    Finder key(String k) => find.byKey(Key(k));
    Finder field(String label) => find.widgetWithText(DropdownButtonFormField<String>, label);

    Future<void> pumpDialog(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore))],
        child: MaterialApp(home: Scaffold(body: FeeAssignmentDialog(service: fees))),
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

    Finder until() => find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('fee-month-until:'));
    Finder dueDay() => find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('fee-due-day:'));
    String text(WidgetTester tester, String k) => tester.widget<Text>(key(k)).data!;

    Future<void> save(WidgetTester tester) async {
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
    }

    Future<void> start(WidgetTester tester, String structure, {bool bulk = false}) async {
      await pumpDialog(tester);
      if (bulk) {
        await tester.tap(find.text('Full Class'));
        await tester.pumpAndSettle();
      }
      await choose(tester, field('Select Class *'), 'Mont 1');
      if (!bulk) await choose(tester, field('Select Student *'), 'Anu');
      await choose(tester, field('Fee Structure *'), structure);
    }

    testWidgets('Monthly: Start Fee Month and Assign Until (the start month by default), the range, and a due rule from the structure', (tester) async {
      await start(tester, 'Monthly Day5');
      expect(find.text('Start Fee Month *'), findsOneWidget);
      expect(until(), findsNothing, reason: 'shown once a start month is chosen');
      await choose(tester, key('fee-month'), 'June 2026');
      expect(text(tester, 'fee-month-range'), 'June 2026 (1 monthly assignment)');
      expect(key('fee-due-date-pick'), findsOneWidget, reason: 'one month: a single due date, as before');
      await tester.tap(until());
      await tester.pumpAndSettle();
      expect(find.textContaining('May 2026'), findsNothing, reason: 'nothing before the start month');
      expect(find.text('June 2027 (2027-2028)').hitTestable(), findsWidgets, reason: 'can run into the next academic year');
      await tester.tap(find.text('March 2027 (2026-2027)').last);
      await tester.pumpAndSettle();
      expect(text(tester, 'fee-month-range'), 'June 2026 – March 2027 (10 monthly assignments)');
      expect(key('fee-due-date-pick'), findsNothing);
      expect(text(tester, 'fee-due-preview'), contains('Due dates: 5 Jun 2026, 5 Jul 2026, 5 Aug 2026, … 5 Mar 2027.'));
      await save(tester);
      final saved = (await tester.runAsync(all))!;
      expect(saved, hasLength(10));
      expect({for (final a in saved) a['studentId']}, {'s1'});
      expect({for (final a in saved) dueOf(a)!.day}, {5});
    });

    testWidgets('a later start month moves Assign Until with it; the due rule can be due in the following month', (tester) async {
      await start(tester, 'Monthly Day5');
      await choose(tester, key('fee-month'), 'October 2026');
      await choose(tester, until(), 'November 2026');
      await choose(tester, key('fee-month'), 'January 2027');
      expect(text(tester, 'fee-month-range'), 'January 2027 (1 monthly assignment)', reason: 'Assign Until can’t precede the start');
      await choose(tester, until(), 'February 2027');
      await choose(tester, key('fee-due-offset'), 'The month after the fee month');
      expect(text(tester, 'fee-due-preview'), contains('Due dates: 5 Feb 2027, 5 Mar 2027.'));
      await save(tester);
      final saved = (await tester.runAsync(all))!..sort((a, b) => (a['feeMonth'] as String).compareTo(b['feeMonth'] as String));
      expect([for (final a in saved) (a['feeMonth'], dueOf(a))], [('2027-01', DateTime(2027, 2, 5)), ('2027-02', DateTime(2027, 3, 5))]);
    });

    testWidgets('no usable due day on the structure: the day must be chosen, then applies to every month', (tester) async {
      await start(tester, 'Monthly NoDay');
      await choose(tester, key('fee-month'), 'January 2027');
      await choose(tester, until(), 'March 2027');
      expect(text(tester, 'fee-due-preview'), contains('no usable due day of month'));
      await save(tester);
      expect(find.text('Choose the due day'), findsOneWidget);
      expect(await tester.runAsync(all), isEmpty);
      await choose(tester, dueDay(), '31');
      await save(tester);
      final saved = (await tester.runAsync(all))!..sort((a, b) => (a['feeMonth'] as String).compareTo(b['feeMonth'] as String));
      expect([for (final a in saved) dueOf(a)], [DateTime(2027, 1, 31), DateTime(2027, 2, 28), DateTime(2027, 3, 31)]);
    });

    testWidgets('Term structures keep the existing flow: no recurring controls', (tester) async {
      await start(tester, 'Term Plain');
      expect(key('fee-month'), findsNothing);
      expect(until(), findsNothing);
      expect(key('fee-due-date-pick'), findsOneWidget);
    });

    testWidgets('Full Class: a confirmation with students, months and at most how many; Cancel writes nothing; the result counts', (tester) async {
      await tester.runAsync(() => fees.assignFee({'studentId': 's2', 'studentName': 'Bala', 'classId': 'c1', 'className': 'Mont 1', 'feeStructureId': 'day5',
        'feeStructureName': 'Monthly Day5', 'academicYearId': y26, 'academicYear': '2026-2027', 'totalFee': 3000, 'discountAmount': 0, 'payableAmount': 3000,
        'paidAmount': 0, 'balanceAmount': 3000, 'status': 'unpaid', 'feeMonth': '2026-12', 'dueDate': DateTime(2026, 12, 5)}));
      await start(tester, 'Monthly Day5', bulk: true);
      await choose(tester, key('fee-month'), 'November 2026');
      await choose(tester, until(), 'January 2027');
      expect(text(tester, 'fee-due-preview'), contains('The same dates apply to every student in this class'));
      await save(tester);
      final summary = tester.widget<Text>(key('fee-bulk-confirm-summary')).data!;
      expect(summary, contains('3 students in Mont 1 for November 2026 – January 2027 (3 monthly assignments)'));
      expect(summary, contains('at most 9 assignments'));
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect((await tester.runAsync(all))!.length, 1, reason: 'only the existing one');
      await save(tester);
      await tester.tap(key('fee-bulk-confirm-ok'));
      await tester.pumpAndSettle();
      final saved = (await tester.runAsync(all))!;
      expect(saved.length, 9, reason: '8 created; Bala’s December skipped');
      expect(saved.where((a) => a['studentId'] == 's2' && a['feeMonth'] == '2026-12').length, 1);
    });
  });

  // ---------------------------------------------------------------- screen
  group('Fees screen: month filter, sections, tabs', () {
    Finder key(String k) => find.byKey(Key(k));
    final today = DateTime(2026, 11, 7);

    Future<void> pumpFees(WidgetTester tester, {String? tab, Size size = const Size(1400, 3000)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore))],
        child: MaterialApp(home: AdminFeesScreen(service: fees, clock: () => today)),
      ));
      await tester.pumpAndSettle();
      if (tab != null) {
        await tester.ensureVisible(find.widgetWithText(ChoiceChip, tab));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, tab));
        await tester.pumpAndSettle();
      }
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    Future<void> chooseFilter(WidgetTester tester, String filter, String label) async {
      await tap(tester, key('fees-filter-$filter'));
      await tap(tester, find.text(label).last);
    }

    /// Anu (Mont 1): Sep, Oct, Dec 2026 and Jan 2027 (October part paid);
    /// Bala: October 2026; Dev (Mont 2): Term; Bala: an older Monthly one
    /// with no month; one receipt with no assignment.
    Future<Map<String, String>> seed() async {
      await assign(['s1'], '2026-09', '2026-10');
      await assign(['s1'], '2026-12', '2027-01');
      await assign(['s2'], '2026-10', '2026-10');
      final ids = {for (final a in await all()) '${a['studentId']}-${a['feeMonth']}': a['id'] as String};
      ids['term'] = (await fees.assignFee({'studentId': 's4', 'studentName': 'Dev', 'classId': 'c2', 'className': 'Mont 2', 'feeStructureId': 'term', 'feeStructureName': 'Term Plain',
        'academicYearId': y26, 'academicYear': '2026-2027', 'totalFee': 20000, 'discountAmount': 0, 'payableAmount': 20000, 'paidAmount': 0, 'balanceAmount': 20000,
        'status': 'unpaid', 'dueDate': DateTime(2026, 12, 1)}))!;
      ids['legacy'] = (await firestore.collection('student_fee_assignments').add({'studentId': 's2', 'studentName': 'Student s2', 'classId': 'c1', 'className': 'Mont 1',
        'feeStructureId': 'noday', 'feeStructureName': 'Monthly NoDay', 'academicYearId': y26, 'academicYear': '2026-2027', 'totalFee': 3000, 'payableAmount': 3000,
        'paidAmount': 0, 'balanceAmount': 3000, 'status': 'unpaid', 'assignedAt': DateTime(2026, 6, 1)})).id;
      ids['r-oct'] = (await fees.collectFee(assignmentId: ids['s1-2026-10']!, amount: 1000, paymentDate: DateTime(2026, 11, 2), paymentMode: 'cash', referenceNo: '', remarks: '')).id;
      ids['r-term'] = (await fees.collectFee(assignmentId: ids['term']!, amount: 5000, paymentDate: DateTime(2026, 10, 2), paymentMode: 'upi', referenceNo: '', remarks: '')).id;
      await firestore.collection('fee_receipts').add({'receiptNo': 'OLD-1', 'studentId': 's1', 'studentName': 'Anu', 'feeStructureName': 'Day Care', 'amount': 99, 'paymentMode': 'cash', 'createdAt': DateTime(2024)});
      return ids;
    }

    List<String> headings(WidgetTester tester, String list) {
      final found = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('fees-$list-section-') && !(w.key! as ValueKey<String>).value.contains('-empty-'));
      final elements = found.evaluate().toList()..sort((a, b) => tester.getTopLeft(find.byWidget(a.widget)).dy.compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy));
      return [for (final e in elements) tester.widget<Text>(find.descendant(of: find.byWidget(e.widget), matching: find.byType(Text))).data!];
    }

    testWidgets('Collections opens first; the tabs are Collections, Receipts, Dues, Assignments, Structures, Students', (tester) async {
      await seed();
      await pumpFees(tester);
      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
      expect([for (final c in chips) (c.label as Text).data], ['Collections', 'Receipts', 'Dues', 'Assignments', 'Structures', 'Students', 'Reports'], reason: 'Reports is added after the existing tabs');
      expect(chips.first.selected, isTrue);
      expect(key('fees-collections-search'), findsOneWidget);
    });

    testWidgets('the Add button does each tab’s own thing', (tester) async {
      await seed();
      await pumpFees(tester);
      await tap(tester, find.byKey(const Key('admin-fab')).evaluate().isEmpty ? find.byType(FloatingActionButton) : find.byKey(const Key('admin-fab')));
      expect(find.byType(FeeCollectionDialog), findsOneWidget, reason: 'Collections: collect');
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      for (final t in ['Receipts', 'Dues', 'Students']) {
        await tap(tester, find.widgetWithText(ChoiceChip, t));
        await tap(tester, find.byType(FloatingActionButton));
        expect(find.byType(FeeAssignmentDialog), findsNothing, reason: t);
        expect(find.byType(FeeStructureDialog), findsNothing, reason: t);
        expect(find.byType(FeeCollectionDialog), findsNothing, reason: t);
      }
      await tap(tester, find.widgetWithText(ChoiceChip, 'Assignments'));
      await tap(tester, find.byType(FloatingActionButton));
      expect(find.byType(FeeAssignmentDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      await tap(tester, find.widgetWithText(ChoiceChip, 'Structures'));
      await tap(tester, find.byType(FloatingActionButton));
      expect(find.byType(FeeStructureDialog), findsOneWidget);
    });

    testWidgets('All Months: the current month first (even empty), the rest in date order, then term fees and Month not recorded', (tester) async {
      await seed();
      await pumpFees(tester, tab: 'Assignments');
      expect(headings(tester, 'assignments'), [
        'November 2026 – Current Month', 'September 2026', 'October 2026', 'December 2026', 'January 2027', 'Term and One-time Fees', 'Month not recorded',
      ]);
      expect(key('fees-assignments-section-empty-2026-11'), findsOneWidget);
      expect(find.text('Nothing for November 2026.'), findsOneWidget);
      await tap(tester, find.widgetWithText(ChoiceChip, 'Collections'));
      expect(headings(tester, 'collections').first, 'November 2026 – Current Month');
      expect(headings(tester, 'collections'), contains('Month not recorded'));
    });

    testWidgets('a month shows only that month, with the other filters and search; the empty state clears the month', (tester) async {
      await seed();
      await pumpFees(tester, tab: 'Collections');
      await chooseFilter(tester, 'month', 'October 2026');
      expect(headings(tester, 'collections'), ['October 2026 – Selected Month', 'Term and One-time Fees']);
      expect(find.text('Student s1'), findsOneWidget, reason: 'October only, not September or December');
      expect(find.text('Student s2'), findsOneWidget, reason: 'October; the older one with no month is not shown');
      expect(find.text('Dev'), findsOneWidget, reason: 'the Term fee is never hidden by a month');
      await tap(tester, key('fees-filter-student'));
      await tap(tester, key('fees-student-option-s2'));
      expect(find.text('Student s1'), findsNothing);
      expect(find.text('Student s2'), findsOneWidget);
      await tap(tester, key('fees-filter-student-clear'));
      await tester.enterText(key('fees-collections-search'), 'adm-s1');
      await tester.pumpAndSettle();
      expect(find.text('Student s1'), findsOneWidget);
      expect(find.text('Student s2'), findsNothing);
      await tester.enterText(key('fees-collections-search'), '');
      await chooseFilter(tester, 'class', 'Mont 2');
      expect(headings(tester, 'collections'), ['October 2026 – Selected Month', 'Term and One-time Fees']);
      expect(key('fees-collections-section-empty-2026-10'), findsOneWidget, reason: 'the selected month leads, even when empty');
      expect(find.text('Dev'), findsOneWidget);
      await chooseFilter(tester, 'class', 'Mont 1');
      await tap(tester, key('fees-filter-student'));
      await tap(tester, key('fees-student-option-s3'));
      expect(key('fees-collections-filter-empty'), findsOneWidget, reason: 'Chitra has no fees');
      await tap(tester, key('fees-collections-month-clear'));
      expect(find.descendant(of: key('fees-filter-month'), matching: find.text('All Months')), findsOneWidget, reason: 'All Months again, Mont 1 and Chitra kept');
      await tap(tester, key('fees-filter-reset'));
      expect(find.text('Student s1'), findsWidgets);
    });

    testWidgets('Receipts take their linked assignment’s month; an unlinked receipt is never given one', (tester) async {
      final ids = await seed();
      await pumpFees(tester, tab: 'Receipts');
      expect(find.text('OLD-1'), findsNothing, reason: 'no assignment, so no academic year to place it in');
      await chooseFilter(tester, 'year', 'All Academic Years');
      expect(headings(tester, 'receipts'), ['November 2026 – Current Month', 'October 2026', 'Term and One-time Fees', 'Not linked to a fee assignment']);
      expect(find.text('OLD-1'), findsOneWidget);
      await chooseFilter(tester, 'month', 'October 2026');
      expect(headings(tester, 'receipts'), ['October 2026 – Selected Month', 'Term and One-time Fees'], reason: 'paid 2 November, for October; Term receipts stay');
      expect(find.text('OLD-1'), findsNothing);
      expect(key('fees-receipts-unlinked'), findsOneWidget);
      expect(find.textContaining('All Months'), findsWidgets);
      expect(ids['r-oct'], isNotNull);
    });

    testWidgets('pagination returns to page 1 when the month changes; a month the new year lacks is cleared', (tester) async {
      await assign([for (var i = 0; i < 12; i++) 'p$i'], '2026-10', '2026-11');
      await pumpFees(tester, tab: 'Assignments');
      await tap(tester, find.descendant(of: key('fees-assignments-pagination'), matching: find.byTooltip('Next page')));
      expect(find.textContaining('Page 2 of'), findsOneWidget);
      await chooseFilter(tester, 'month', 'October 2026');
      expect(find.textContaining('Page 1 of 2'), findsOneWidget);
      await chooseFilter(tester, 'year', '2027-2028');
      expect(find.descendant(of: key('fees-filter-month'), matching: find.text('All Months')), findsOneWidget);
    });

    testWidgets('the overview follows the month too (Today’s Collection stays by date)', (tester) async {
      await seed();
      await pumpFees(tester);
      String card(String k) => tester.widget<Text>(find.descendant(of: key('fees-overview-$k'), matching: find.byType(Text)).at(1)).data!;
      await chooseFilter(tester, 'month', 'October 2026');
      expect(card('expected'), '₹25,000', reason: 'two October assignments of ₹2,500, and the ₹20,000 Term fee (never hidden by a month)');
      expect(card('collected'), '₹6,000');
      expect(tester.widget<Text>(key('fees-overview-scope')).data, endsWith('• October 2026'));
    });

    for (final size in const [Size(1400, 1200), Size(800, 1400), Size(360, 900)]) {
      testWidgets('${size.width.toInt()}px: sections and the month filter fit', (tester) async {
        await seed();
        await pumpFees(tester, size: size);
        for (final t in ['Collections', 'Receipts', 'Dues', 'Assignments']) {
          await tap(tester, find.widgetWithText(ChoiceChip, t));
          expect(tester.takeException(), isNull, reason: t);
        }
        expect(tester.getRect(key('fees-filter-month')).right, lessThanOrEqualTo(size.width));
      });
    }
  });
}

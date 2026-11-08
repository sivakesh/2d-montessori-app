// Fees: a default due date configured on every fee structure component —
// Due Day of Month (Monthly) or Default Due Date (Term, One-time) — used to
// prefill new assignments, which can override it and then keep their own
// stored dueDate. Mixed structures use a shared configuration or ask for
// an explicit date. Synthetic test data only.
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
import 'package:montessori_app/modules/fees/models/fee_due_date.dart';
import 'package:montessori_app/modules/fees/models/fee_month_range.dart';
import 'package:montessori_app/modules/fees/models/fee_structure_model.dart';
import 'package:montessori_app/modules/fees/models/student_fee_assignment_model.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_assignment_dialog.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_structure_dialog.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';

import 'support/buffered_transaction_firestore.dart';

FeeStructureModel _structure(List<FeeComponentModel> components) => FeeStructureModel.fromMap('x', {'name': 'S', 'components': [for (final c in components) c.toMap()]});
FeeComponentModel _monthly({int? day}) => FeeComponentModel(name: 'Care', amount: 3000, frequency: 'monthly', dueDayOfMonth: day, isOptional: false);
FeeComponentModel _term({DateTime? due}) => FeeComponentModel(name: 'Term', amount: 8000, frequency: 'term', termName: 'Term 1', dueDate: due, isOptional: false);
FeeComponentModel _once({DateTime? due}) => FeeComponentModel(name: 'Kit', amount: 1500, frequency: 'oneTime', dueDate: due, isOptional: false);

void main() {
  // ---------------------------------------------------------------- rules
  group('defaults by frequency', () {
    test('1, 8. Monthly: 1–31 or empty; the day in the month, or its last day (31 Jan, 28/29 Feb, 30 Apr)', () {
      for (final bad in <Object>['0', '-3', '32', '2.5', 'ten', 0, 32]) {
        expect(FeeService.dueDayOfMonthError(bad), FeeService.dueDayOfMonthMessage, reason: '$bad');
      }
      for (final ok in <Object?>[null, '', '1', '31', 15]) {
        expect(FeeService.dueDayOfMonthError(ok), isNull, reason: '$ok');
      }
      final s = _structure([_monthly(day: 31)]);
      expect(FeeDueDate.defaultFor(s, '2027-01').date, DateTime(2027, 1, 31));
      expect(FeeDueDate.defaultFor(s, '2027-02').date, DateTime(2027, 2, 28));
      expect(FeeDueDate.defaultFor(s, '2028-02').date, DateTime(2028, 2, 29), reason: 'leap year');
      expect(FeeDueDate.defaultFor(s, '2027-04').date, DateTime(2027, 4, 30));
    });

    test('2, 3. Term and One-time: the configured calendar date (time of day ignored)', () {
      final term = FeeDueDate.defaultFor(_structure([_term(due: DateTime(2026, 7, 15, 9, 30))]), '');
      expect(term.date, DateTime(2026, 7, 15));
      expect(term.note, contains('Defaults to the structure’s due date'));
      expect(FeeDueDate.defaultFor(_structure([_once(due: DateTime(2026, 9, 30))]), '').date, DateTime(2026, 9, 30));
      expect(FeeDueDate.defaultFor(_structure([_term(due: DateTime(2026, 7, 15)), _once()]), '').date, DateTime(2026, 7, 15),
          reason: 'a component with nothing set doesn’t conflict');
    });

    test('10. mixed, compatible: the Term/One-time date when the monthly day falls on it', () {
      expect(FeeDueDate.defaultFor(_structure([_monthly(day: 10), _term(due: DateTime(2027, 6, 10))]), '').date, DateTime(2027, 6, 10));
      expect(FeeDueDate.defaultFor(_structure([_monthly(day: 31), _once(due: DateTime(2027, 4, 30))]), '').date, DateTime(2027, 4, 30),
          reason: 'day 31 in April is the 30th');
      expect(FeeDueDate.defaultFor(_structure([_monthly(), _once(due: DateTime(2027, 6, 10))]), '').date, DateTime(2027, 6, 10), reason: 'no monthly day set');
      expect(FeeDueDate.configurationConflict(_structure([_monthly(day: 10), _term(due: DateTime(2027, 6, 10))])), isNull);
    });

    test('11. mixed, conflicting: no date, and the reason says an explicit date is needed', () {
      final cases = {
        'day vs date': _structure([_monthly(day: 5), _once(due: DateTime(2027, 6, 10))]),
        'two dates': _structure([_monthly(), _term(due: DateTime(2027, 6, 10)), _once(due: DateTime(2027, 7, 1))]),
        'two days': _structure([_monthly(day: 5), _monthly(day: 7), _once(due: DateTime(2027, 6, 5))]),
        'day without a month': _structure([_monthly(day: 5), _once()]),
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        final d = FeeDueDate.defaultFor(value, '');
        expect(d.date, isNull, reason: key);
        expect(d.note, contains('Choose the due date'), reason: key);
        expect(FeeDueDate.configurationConflict(value), d.note, reason: key);
      }
      expect(FeeDueDate.defaultFor(cases['day vs date']!, '').note, contains('does not fall on the term or one-time due date (10 Jun 2027)'));
      expect(FeeDueDate.defaultFor(cases['two dates']!, '').note, contains('different due dates (10 Jun 2027, 1 Jul 2027)'));
    });

    test('12. structures without any configuration still read and give no date', () {
      final legacy = FeeStructureModel.fromMap('old', {
        'name': 'Old', 'components': [{'name': 'Kit', 'amount': 500, 'dueType': 'oneTime'}, {'name': 'Care', 'amount': 1000, 'frequency': 'monthly'}],
      });
      expect([for (final c in legacy.components) (c.dueDate, c.dueDayOfMonth)], [(null, null), (null, null)]);
      expect(FeeDueDate.defaultFor(legacy, '').date, isNull);
      expect(FeeDueDate.defaultFor(legacy, '').note, 'This fee structure has no default due date set. Choose the due date for this fee.');
      expect(FeeDueDate.configurationConflict(legacy), isNull, reason: 'nothing set, nothing to conflict');
      expect(FeeDueDate.defaultFor(_structure([_monthly()]), '2027-01').date, isNull);
    });

    test('9. recurring: every month its own date from the structure’s day', () {
      final plans = FeeMonthRange.plan('2028-01', '2028-04', [_year('y', DateTime(2027, 6, 1), DateTime(2028, 5, 31))], const FeeDueRule(day: 31));
      expect([for (final p in plans) p.dueDate], [DateTime(2028, 1, 31), DateTime(2028, 2, 29), DateTime(2028, 3, 31), DateTime(2028, 4, 30)]);
    });

    test('15. overdue is unchanged: from the stored due date and balance only', () {
      StudentFeeAssignmentModel a(double balance, DateTime? due, {String status = 'unpaid'}) =>
          StudentFeeAssignmentModel.fromMap('a', {'studentId': 's', 'payableAmount': 1000, 'balanceAmount': balance, 'status': status, 'dueDate': ?due});
      final today = DateTime(2026, 7, 16);
      expect(FeeDueDate.isOverdue(a(1000, DateTime(2026, 7, 15)), today), isTrue);
      expect(FeeDueDate.isOverdue(a(1000, DateTime(2026, 7, 16)), today), isFalse);
      expect(FeeDueDate.isOverdue(a(0, DateTime(2026, 7, 15)), today), isFalse);
      expect(FeeDueDate.isOverdue(a(1000, DateTime(2026, 7, 15), status: 'cancelled'), today), isFalse);
      expect(FeeDueDate.isOverdue(a(1000, null), today), isFalse);
    });
  });

  // ---------------------------------------------------------------- data
  late BufferedTransactionFirestore firestore;
  late FeeService fees;
  late String yearId;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    final auth = MockFirebaseAuth();
    final finance = FinanceService(firestore: firestore, auth: auth);
    await finance.ensureDefaults();
    fees = FeeService(firestore: firestore, auth: auth, storage: MockFirebaseStorage(), financeService: finance);
    yearId = await AcademicYearService(firestore: firestore).createAcademicYear(schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2026-2027',
        startDate: DateTime(2026, 6, 1), endDate: DateTime(2027, 5, 31), createdBy: 'admin-1', setAsCurrent: true);
    await firestore.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
    for (final (id, name) in [('s1', 'Anu'), ('s2', 'Bala')]) {
      await firestore.collection('students').doc(id).set({'name': name, 'admissionNo': 'ADM-$id', 'classId': 'c1', 'isActive': true, 'admissionDate': DateTime(2020, 1, 1)}); // admitted long before every fee month (Admission Date rule)
    }
    Future<void> structure(String id, String name, List<FeeComponentModel> components) => firestore.collection('fee_structures').doc(id).set({
          'name': name, 'description': '', 'totalAmount': components.fold<double>(0, (s, c) => s + c.amount), 'academicYear': '2026-2027',
          'academicYearId': yearId, 'isActive': true, 'createdBy': 't', 'createdAt': DateTime(2026, 1, 1),
          'components': [for (final c in components) c.toMap()],
        });
    await structure('termcfg', 'Term Configured', [_term(due: DateTime(2026, 7, 15))]);
    await structure('oncecfg', 'Kit Configured', [_once(due: DateTime(2026, 9, 30))]);
    await structure('plain', 'Kit Plain', [_once()]);
    await structure('mixok', 'Mixed Agreeing', [_monthly(day: 10), _term(due: DateTime(2027, 6, 10))]);
    await structure('mixbad', 'Mixed Conflicting', [_monthly(day: 5), _once(due: DateTime(2027, 6, 10))]);
  });

  Map<String, dynamic> single(String student, String structureId, {DateTime? dueDate}) => {
        'studentId': student, 'studentName': student, 'admissionNo': 'ADM-$student', 'classId': 'c1', 'className': 'Mont 1',
        'feeStructureId': structureId, 'feeStructureName': structureId, 'academicYearId': yearId, 'academicYear': '2026-2027',
        'totalFee': 8000, 'discountAmount': 0, 'payableAmount': 8000, 'paidAmount': 0, 'balanceAmount': 8000, 'status': 'unpaid', 'dueDate': ?dueDate,
      };
  Future<Map<String, dynamic>> doc(String path) async => (await firestore.doc(path).get()).data()!;
  Future<List<Map<String, dynamic>>> assignments() async => [for (final d in (await firestore.collection('student_fee_assignments').get()).docs) d.data()];
  Future<FeeStructureModel> load(String id) async => FeeStructureModel.fromMap(id, await doc('fee_structures/$id'));
  DateTime? dueOf(Map<String, dynamic> data) => (data['dueDate'] as Timestamp?)?.toDate();
  Map<String, dynamic> structureData(String name, Object? componentDue, {String frequency = 'oneTime'}) => {
        'name': name, 'academicYearId': yearId, 'academicYear': '2026-2027', 'totalAmount': 1, 'isActive': true,
        'components': [{'name': 'C', 'amount': 1, 'frequency': frequency, 'dueDate': componentDue, 'isOptional': false}],
      };

  group('service', () {
    test('2, 3, 4. a Default Due Date saves on create and update; a non-date or a year outside 2000–2100 is refused and nothing is written', () async {
      final before = firestore.dump();
      for (final bad in <Object>[DateTime(1999, 12, 31), DateTime(2101, 1, 1), '2026-07-15', 20260715]) {
        await expectLater(fees.createFeeStructure(structureData('Bad', bad)), throwsA(isA<StateError>().having((e) => e.message, 'm', FeeService.componentDueDateMessage)),
            reason: '$bad');
      }
      expect(firestore.dump(), before);
      final id = await fees.createFeeStructure(structureData('Kit', DateTime(2026, 9, 30)));
      Future<DateTime?> stored() async => FeeStructureModel.fromMap(id, await doc('fee_structures/$id')).components.single.dueDate;
      expect(await stored(), DateTime(2026, 9, 30));
      await expectLater(fees.updateFeeStructure(id, structureData('Kit', DateTime(2200, 1, 1))), throwsA(isA<StateError>()));
      expect(await stored(), DateTime(2026, 9, 30), reason: 'kept');
      await fees.updateFeeStructure(id, structureData('Kit', DateTime(2026, 10, 15), frequency: 'term'));
      expect(await stored(), DateTime(2026, 10, 15));
      await fees.updateFeeStructure(id, structureData('Kit', null));
      expect(await stored(), isNull, reason: 'clearing it is allowed');
    });

    test('13. editing a structure’s due-date configuration leaves every existing assignment’s due date as stored', () async {
      final a = (await fees.assignFee(single('s1', 'termcfg', dueDate: DateTime(2026, 7, 15))))!;
      final b = (await fees.assignFee(single('s2', 'termcfg', dueDate: DateTime(2026, 8, 1))))!;
      final legacy = await firestore.collection('student_fee_assignments').add(single('s1', 'oncecfg'));
      final before = [await doc('student_fee_assignments/$a'), await doc('student_fee_assignments/$b'), await doc('student_fee_assignments/${legacy.id}')];
      await fees.updateFeeStructure('termcfg', {...structureData('Term Configured', DateTime(2026, 12, 1), frequency: 'term')});
      await fees.updateFeeStructure('oncecfg', structureData('Kit Configured', DateTime(2027, 1, 1)));
      expect([await doc('student_fee_assignments/$a'), await doc('student_fee_assignments/$b'), await doc('student_fee_assignments/${legacy.id}')], before);
      expect((await doc('student_fee_assignments/${legacy.id}')).containsKey('dueDate'), isFalse, reason: 'never inferred');
    });
  });

  // ---------------------------------------------------------------- structure dialog
  group('Add / Edit Component', () {
    void bigView(WidgetTester tester) {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    /// The structure dialog opened over a page, so Save and Cancel pop it.
    Future<void> openStructure(WidgetTester tester, {FeeStructureModel? edit}) async {
      bigView(tester);
      await tester.pumpWidget(const SizedBox()); // closes any dialog left open
      await tester.pumpWidget(ProviderScope(
        overrides: [academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore))],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<bool>(context: context, builder: (_) => FeeStructureDialog(structure: edit, service: fees)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Finder key(String k) => find.byKey(Key(k));
    String text(WidgetTester tester, String k) => tester.widget<Text>(key(k)).data!;
    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    Future<void> frequency(WidgetTester tester, String value) async {
      await tap(tester, find.widgetWithText(DropdownButtonFormField<String>, 'Frequency *'));
      await tester.tap(find.text(value).last);
      await tester.pumpAndSettle();
    }

    /// Picks day [day] of the month the picker opens on; returns the date.
    Future<DateTime> pickDay(WidgetTester tester, int day) async {
      await tap(tester, key('fee-component-due-date-pick'));
      final now = DateTime.now();
      await tester.tap(find.text('$day').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      return DateTime(now.year, now.month, day);
    }

    testWidgets('1. Monthly shows the Due Day of Month rule; Term and One-time show a Default Due Date picker instead', (tester) async {
      await openStructure(tester);
      await tap(tester, find.text('Add Component'));
      expect(key('fee-component-due-day'), findsOneWidget);
      expect(find.textContaining('Used as the default due date when monthly assignments are created'), findsOneWidget);
      expect(find.textContaining('31 → 28 or 29 Feb, 30 Apr'), findsOneWidget);
      expect(key('fee-component-due-date'), findsNothing);
      for (final f in ['term', 'oneTime']) {
        await frequency(tester, f);
        expect(key('fee-component-due-day'), findsNothing, reason: f);
        expect(find.text('Default Due Date (optional)'), findsOneWidget, reason: f);
        expect(text(tester, 'fee-component-due-date-value'), 'Not set', reason: f);
      }
    });

    testWidgets('2, 4. a Term component with a picked date: shown on the card, saved, then shown again in Edit Component', (tester) async {
      await openStructure(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Fee Structure Name *'), 'Term 2026');
      await tap(tester, find.text('Add Component'));
      await tester.enterText(find.widgetWithText(TextField, 'Component Name *'), 'Tuition');
      await tester.enterText(find.widgetWithText(TextField, 'Amount *'), '8000');
      await frequency(tester, 'term');
      await tester.enterText(find.widgetWithText(TextField, 'Term Name *'), 'Term 1');
      final picked = await pickDay(tester, 20);
      expect(text(tester, 'fee-component-due-date-value'), FeeDueDate.label(picked));
      await tap(tester, key('fee-component-submit'));
      expect(text(tester, 'fee-component-summary-0'), contains('Due ${FeeDueDate.label(picked)}'));
      await tap(tester, find.widgetWithText(FilledButton, 'Save'));

      final saved = (await tester.runAsync(() => firestore.collection('fee_structures').where('name', isEqualTo: 'Term 2026').get()))!.docs.single;
      final component = FeeStructureModel.fromMap(saved.id, saved.data()).components.single;
      expect((component.frequency, component.termName, component.dueDate, component.dueDayOfMonth), ('term', 'Term 1', picked, null));
      expect((saved.data()['components'] as List).single['dueDate'], isA<Timestamp>());

      final model = (await tester.runAsync(() => load(saved.id)))!;
      await openStructure(tester, edit: model);
      await tap(tester, key('fee-component-edit-0'));
      expect(find.text('Edit Component'), findsWidgets);
      expect(text(tester, 'fee-component-due-date-value'), FeeDueDate.label(picked), reason: 'the configured date is shown');
      expect(find.widgetWithText(TextField, 'Tuition'), findsOneWidget);
    });

    testWidgets('3, 4. a One-time component’s date can be changed or cleared in Edit Component; the rest is kept', (tester) async {
      await openStructure(tester, edit: (await tester.runAsync(() => load('oncecfg')))!);
      expect(text(tester, 'fee-component-summary-0'), contains('Due 30 Sep 2026'));
      await tap(tester, key('fee-component-edit-0'));
      expect(text(tester, 'fee-component-due-date-value'), '30 Sep 2026');
      await tap(tester, key('fee-component-due-date-pick'));
      await tester.tap(find.text('15').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(text(tester, 'fee-component-due-date-value'), '15 Sep 2026', reason: 'the picker opens on the configured month');
      await tap(tester, key('fee-component-submit'));
      expect(text(tester, 'fee-component-summary-0'), contains('Due 15 Sep 2026'));
      await tap(tester, find.widgetWithText(FilledButton, 'Save'));
      var c = (await tester.runAsync(() => load('oncecfg')))!.components.single;
      expect((c.name, c.amount, c.frequency, c.dueDate), ('Kit', 1500, 'oneTime', DateTime(2026, 9, 15)));

      await openStructure(tester, edit: (await tester.runAsync(() => load('oncecfg')))!);
      await tap(tester, key('fee-component-edit-0'));
      await tap(tester, key('fee-component-due-date-clear'));
      expect(text(tester, 'fee-component-due-date-value'), 'Not set');
      await tap(tester, key('fee-component-submit'));
      expect(text(tester, 'fee-component-summary-0'), contains('No default due date'));
      await tap(tester, find.widgetWithText(FilledButton, 'Save'));
      c = (await tester.runAsync(() => load('oncecfg')))!.components.single;
      expect(c.dueDate, isNull);
    });

    testWidgets('1, 4. a Monthly component’s due day is shown and kept in Edit Component, and still validated', (tester) async {
      await openStructure(tester, edit: (await tester.runAsync(() => load('mixok')))!);
      expect(text(tester, 'fee-component-summary-0'), contains('Due day 10'));
      await tap(tester, key('fee-component-edit-0'));
      expect(tester.widget<TextFormField>(key('fee-component-due-day')).controller!.text, '10');
      await tester.enterText(key('fee-component-due-day'), '0');
      await tester.pumpAndSettle();
      await tap(tester, key('fee-component-submit'));
      expect(find.text(FeeService.dueDayOfMonthMessage), findsOneWidget);
      expect(find.text('Edit Component'), findsWidgets, reason: 'still open');
    });

    testWidgets('11. a mixed structure whose settings conflict says so, and its settings are left as they are', (tester) async {
      await openStructure(tester, edit: (await tester.runAsync(() => load('mixbad')))!);
      expect(text(tester, 'fee-structure-due-conflict'), contains('does not fall on the term or one-time due date'));
      expect(text(tester, 'fee-component-summary-0'), contains('Due day 5'));
      expect(text(tester, 'fee-component-summary-1'), contains('Due 10 Jun 2027'));
      await openStructure(tester, edit: (await tester.runAsync(() => load('mixok')))!);
      expect(key('fee-structure-due-conflict'), findsNothing, reason: 'compatible');
    });

    testWidgets('16. opening and cancelling Add Component, Edit Component and the structure dialog writes nothing', (tester) async {
      final before = firestore.dump();
      await openStructure(tester, edit: (await tester.runAsync(() => load('termcfg')))!);
      await tap(tester, key('fee-component-edit-0'));
      await tap(tester, key('fee-component-due-date-clear'));
      await tap(tester, find.widgetWithText(TextButton, 'Cancel').last);
      expect(text(tester, 'fee-component-summary-0'), contains('Due 15 Jul 2026'), reason: 'cancel discards the change');
      await tap(tester, find.text('Add Component'));
      await tap(tester, find.widgetWithText(TextButton, 'Cancel').last);
      await tap(tester, find.widgetWithText(TextButton, 'Cancel').last);
      expect(find.byType(FeeStructureDialog), findsNothing);
      expect(firestore.dump(), before);
    });
  });

  // ---------------------------------------------------------------- assignment dialog
  group('Assign Fee dialog uses the defaults', () {
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

    Future<void> save(WidgetTester tester) async {
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
    }

    String dueShown(WidgetTester tester) => tester.widget<Text>(key('fee-due-date-value')).data!;

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

    testWidgets('5, 2. Single Student, Term: prefilled with the configured date and saved', (tester) async {
      await start(tester, 'Term Configured');
      expect(dueShown(tester), '15 Jul 2026');
      expect(find.textContaining('Defaults to the structure’s due date. You can change it.'), findsOneWidget);
      await save(tester);
      expect(dueOf((await tester.runAsync(assignments))!.single), DateTime(2026, 7, 15));
    });

    testWidgets('7, 3. the administrator overrides a One-time default; the override is what’s saved', (tester) async {
      await start(tester, 'Kit Configured');
      expect(dueShown(tester), '30 Sep 2026');
      await tester.ensureVisible(key('fee-due-date-pick'));
      await tester.pumpAndSettle();
      await tester.tap(key('fee-due-date-pick'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('12').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(dueShown(tester), '12 Sep 2026');
      await save(tester);
      expect(dueOf((await tester.runAsync(assignments))!.single), DateTime(2026, 9, 12));
      expect((await tester.runAsync(() => load('oncecfg')))!.components.single.dueDate, DateTime(2026, 9, 30), reason: 'the structure is untouched');
    });

    testWidgets('6. Full Class: the configured date for the whole batch, said to apply to every student', (tester) async {
      await start(tester, 'Kit Configured', bulk: true);
      expect(dueShown(tester), '30 Sep 2026');
      expect(find.textContaining('Applies to every student assigned in this class'), findsOneWidget);
      expect(find.textContaining('can be changed later with Edit'), findsOneWidget);
      await save(tester);
      final saved = (await tester.runAsync(assignments))!;
      expect(saved, hasLength(2));
      expect({for (final a in saved) dueOf(a)}, {DateTime(2026, 9, 30)});
    });

    testWidgets('12. no configured date: one must be chosen; nothing is saved until then', (tester) async {
      await start(tester, 'Kit Plain');
      expect(dueShown(tester), 'Choose a date');
      expect(find.textContaining('no default due date set'), findsOneWidget);
      await save(tester);
      expect(find.text('Choose the due date'), findsOneWidget);
      expect(await tester.runAsync(assignments), isEmpty);
    });

    testWidgets('10. mixed, compatible: the shared date is offered', (tester) async {
      await start(tester, 'Mixed Agreeing');
      expect(dueShown(tester), '10 Jun 2027');
      expect(key('fee-month'), findsNothing, reason: 'a mixed structure has no fee month');
    });

    testWidgets('11. mixed, conflicting: no date is chosen for the administrator; the reason is shown and a date is required', (tester) async {
      await start(tester, 'Mixed Conflicting');
      expect(dueShown(tester), 'Choose a date');
      expect(find.textContaining('due dates conflict'), findsOneWidget);
      await save(tester);
      expect(find.text('Choose the due date'), findsOneWidget);
      expect(await tester.runAsync(assignments), isEmpty);
    });

    testWidgets('13. Edit shows the assignment’s stored date, not the structure’s current default', (tester) async {
      final id = (await tester.runAsync(() => fees.assignFee(single('s1', 'termcfg', dueDate: DateTime(2026, 8, 1)))))!;
      await tester.runAsync(() => fees.updateFeeStructure('termcfg', structureData('Term Configured', DateTime(2026, 12, 1), frequency: 'term')));
      await pumpDialog(tester, edit: StudentFeeAssignmentModel.fromMap(id, (await tester.runAsync(() => doc('student_fee_assignments/$id')))!));
      expect(dueShown(tester), '1 Aug 2026');
      expect(find.textContaining('Defaults to the structure'), findsNothing);
      await save(tester);
      expect(dueOf((await tester.runAsync(() => doc('student_fee_assignments/$id')))!), DateTime(2026, 8, 1));
    });

    testWidgets('14. Edit an older assignment without a due date: "Due date not set", the default isn’t applied', (tester) async {
      final ref = (await tester.runAsync(() => firestore.collection('student_fee_assignments').add(single('s1', 'termcfg'))))!;
      await pumpDialog(tester, edit: StudentFeeAssignmentModel.fromMap(ref.id, (await tester.runAsync(() => doc('student_fee_assignments/${ref.id}')))!));
      expect(dueShown(tester), 'Due date not set');
      await save(tester);
      expect((await tester.runAsync(() => doc('student_fee_assignments/${ref.id}')))!.containsKey('dueDate'), isFalse);
    });

    testWidgets('16. opening, choosing a structure and leaving the dialog writes nothing', (tester) async {
      final before = firestore.dump();
      await start(tester, 'Term Configured');
      expect(dueShown(tester), '15 Jul 2026');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(firestore.dump(), before);
    });
  });
}

AcademicYearModel _year(String id, DateTime start, DateTime end) =>
    AcademicYearModel(id: id, schoolId: 's', name: id, startDate: start, endDate: end, isCurrent: false, isActive: true, createdAt: start, updatedAt: start);

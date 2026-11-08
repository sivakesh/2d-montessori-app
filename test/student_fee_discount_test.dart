// Student-level global fee discounts: configuration and validation, the
// central calculation (percentage; fixed once per fee period; capped at the
// gross fee; proportional component allocation in paise), every assignment
// path (Single Student, Full Class, recurring, structure sync), idempotency
// and the manual-discount policy, Apply Student Discounts to Existing Fees
// (preview, re-checked apply, partial payments, concurrency, safe retry,
// audit snapshot), and reports/PDF reconciliation. Synthetic data only.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/settings/providers/academic_year_provider.dart';
import 'package:montessori_app/modules/admin/students/data/admin_student_service.dart';
import 'package:montessori_app/modules/admin/students/data/student_enrollment_service.dart';
import 'package:montessori_app/modules/admin/students/models/admin_student_model.dart';
import 'package:montessori_app/modules/admin/students/providers/student_enrollment_provider.dart';
import 'package:montessori_app/modules/admin/ui/admin_student_form.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/fees/models/fee_component_model.dart';
import 'package:montessori_app/modules/fees/models/fee_discount.dart';
import 'package:montessori_app/modules/fees/models/fee_discount_apply.dart';
import 'package:montessori_app/modules/fees/models/fee_list_filter.dart';
import 'package:montessori_app/modules/fees/models/fee_month_range.dart';
import 'package:montessori_app/modules/fees/models/fee_receipt_model.dart';
import 'package:montessori_app/modules/fees/models/fee_report.dart';
import 'package:montessori_app/modules/fees/models/fee_student.dart';
import 'package:montessori_app/modules/fees/models/student_fee_assignment_model.dart';
import 'package:montessori_app/modules/fees/services/fee_report_pdf.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_assignment_dialog.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_discount_apply_dialog.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';

import 'support/buffered_transaction_firestore.dart';

FeeComponentModel _c(String name, double amount, [String frequency = 'term']) =>
    FeeComponentModel(name: name, amount: amount, frequency: frequency, termName: frequency == 'term' ? 'Term 1' : null, dueDayOfMonth: frequency == 'monthly' ? 5 : null, isOptional: false);

StudentFeeDiscount _d(FeeDiscountType type, double value, {DateTime? from, DateTime? until, bool active = true, String id = 'cfg-1'}) =>
    StudentFeeDiscount(id: id, type: type, value: value, effectiveFrom: from ?? DateTime(2026, 6, 1), effectiveUntil: until, isActive: active);

Map<String, dynamic> _stored(StudentFeeDiscount d) => {...d.toMap(), 'createdAt': Timestamp.fromDate(DateTime(2026, 6, 1))};

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

void main() {
  // ================================================================ configuration
  group('configuration', () {
    test('percentage: more than 0 and at most 100; non-finite and missing refused', () {
      String? v(double? value) => StudentFeeDiscount.validate(type: FeeDiscountType.percentage, value: value, effectiveFrom: DateTime(2026, 6, 1));
      expect(v(10), isNull);
      expect(v(100), isNull);
      expect(v(12.5), isNull);
      expect(v(0), contains('greater than 0'));
      expect(v(-5), contains('greater than 0'));
      expect(v(100.01), contains('more than 100%'));
      expect(v(double.nan), contains('number'));
      expect(v(double.infinity), contains('number'));
      expect(v(null), contains('number'));
    });

    test('fixed: more than 0 (to the paisa); zero and negative refused', () {
      String? v(double value) => StudentFeeDiscount.validate(type: FeeDiscountType.fixed, value: value, effectiveFrom: DateTime(2026, 6, 1));
      expect(v(500), isNull);
      expect(v(5000), isNull, reason: 'more than 100 is fine for a fixed amount');
      expect(v(0), isNotNull);
      expect(v(-500), isNotNull);
      expect(v(0.001), contains('0.01'));
      expect(StudentFeeDiscount.validate(type: null, value: 5, effectiveFrom: DateTime(2026, 6, 1)), contains('type'));
    });

    test('dates: Effective From required; Until not before From (same day allowed)', () {
      String? v(DateTime? from, DateTime? until) => StudentFeeDiscount.validate(type: FeeDiscountType.fixed, value: 5, effectiveFrom: from, effectiveUntil: until);
      expect(v(null, null), contains('effective from'));
      expect(v(DateTime(2026, 6, 1), DateTime(2026, 5, 31)), contains('cannot be earlier'));
      expect(v(DateTime(2026, 6, 1), DateTime(2026, 6, 1)), isNull);
      expect(v(DateTime(1990, 1, 1), null), contains('2000 to 2100'));
    });

    test('effective-date boundaries: the whole period must be inside, both ends included', () {
      final d = _d(FeeDiscountType.fixed, 500, from: DateTime(2027, 1, 1), until: DateTime(2027, 3, 31));
      expect(d.appliesTo(FeeDiscountPeriod.month('2027-01')), isTrue, reason: 'from the first day');
      expect(d.appliesTo(FeeDiscountPeriod.month('2027-03')), isTrue, reason: 'until the last day');
      expect(d.appliesTo(FeeDiscountPeriod.month('2026-12')), isFalse);
      expect(d.appliesTo(FeeDiscountPeriod.month('2027-04')), isFalse);
      final mid = _d(FeeDiscountType.fixed, 500, from: DateTime(2027, 1, 15));
      expect(mid.appliesTo(FeeDiscountPeriod.month('2027-01')), isFalse, reason: 'January is not wholly inside: from February');
      expect(mid.appliesTo(FeeDiscountPeriod.month('2027-02')), isTrue);
      expect(d.appliesTo(FeeDiscountPeriod.date(DateTime(2027, 1, 1))), isTrue);
      expect(d.appliesTo(FeeDiscountPeriod.date(DateTime(2027, 3, 31))), isTrue);
      expect(d.appliesTo(FeeDiscountPeriod.date(DateTime(2027, 4, 1))), isFalse);
      expect(d.notApplicableReason(FeeDiscountPeriod.month('2027-04')), contains('after the discount ends'));
    });

    test('inactive, missing and malformed configurations never apply', () {
      expect(_d(FeeDiscountType.percentage, 10, active: false).notApplicableReason(FeeDiscountPeriod.month('2026-08')), contains('inactive'));
      expect(StudentFeeDiscount.fromStudent({'name': 'No discount'}), isNull);
      expect(StudentFeeDiscount.fromStudent(null), isNull);
      final bad = StudentFeeDiscount.fromMap({'type': 'percentage', 'value': 150, 'effectiveFrom': Timestamp.fromDate(DateTime(2026, 6, 1)), 'isActive': true})!;
      expect(bad.isValid, isFalse);
      expect(bad.appliesTo(FeeDiscountPeriod.month('2026-08')), isFalse);
      final noDate = StudentFeeDiscount.fromMap({'type': 'fixed', 'value': 100, 'isActive': true})!;
      expect(noDate.effectiveFrom, isNull, reason: 'never inferred');
      expect(noDate.appliesTo(FeeDiscountPeriod.month('2026-08')), isFalse);
    });

    group('stored on the student (AdminStudentService)', () {
      late FakeFirebaseFirestore firestore;
      late AdminStudentService students;
      setUp(() {
        firestore = FakeFirebaseFirestore();
        students = AdminStudentService(firestore: firestore, storage: MockFirebaseStorage());
      });
      AdminStudentModel model() => AdminStudentModel.fromMap('', {'name': 'Anu', 'admissionNo': 'ADM-1', 'classId': 'c1', 'isActive': true});

      test('created with a discount: one map with an id, dates as Timestamps and timestamps; none: no field', () async {
        final id = await students.createStudent(
            student: model(), createdBy: 'admin', feeDiscount: _d(FeeDiscountType.percentage, 10, until: DateTime(2027, 5, 31), id: ''));
        final data = (await firestore.doc('students/$id').get()).data()!;
        final m = data['feeDiscount'] as Map;
        expect([m['type'], m['value'], m['isActive'], (m['effectiveFrom'] as Timestamp).toDate(), (m['effectiveUntil'] as Timestamp).toDate()],
            ['percentage', 10, true, DateTime(2026, 6, 1), DateTime(2027, 5, 31)]);
        expect(m['id'], isNotEmpty);
        expect(m['createdAt'], isA<Timestamp>());
        expect(AdminStudentModel.fromMap(id, data).feeDiscount!.summary, '10% · 1 Jun 2026 – 31 May 2027 · Active');
        final plain = await students.createStudent(student: model(), createdBy: 'admin');
        expect((await firestore.doc('students/$plain').get()).data()!.containsKey('feeDiscount'), isFalse, reason: 'no default discount');
      });

      test('saving a discount preserves admission date, parent links and other stored fields', () async {
        await firestore.doc('students/s9').set({
          'name': 'Anu', 'admissionNo': 'ADM-9', 'classId': 'c1', 'isActive': true, 'admissionDate': Timestamp.fromDate(DateTime(2025, 6, 2)),
          'parentLinks': [{'userId': 'p1', 'name': 'Parent', 'email': '', 'relation': 'Mother'}], 'customNote': 'kept', 'medical': {'allergy': 'none'},
        });
        final current = AdminStudentModel.fromMap('s9', (await firestore.doc('students/s9').get()).data()!);
        await students.updateStudent(studentId: 's9', student: current, feeDiscount: _d(FeeDiscountType.fixed, 400, id: ''));
        var data = (await firestore.doc('students/s9').get()).data()!;
        expect([(data['admissionDate'] as Timestamp).toDate(), data['customNote'], data['medical'], (data['parentLinks'] as List).length],
            [DateTime(2025, 6, 2), 'kept', {'allergy': 'none'}, 1]);
        expect((data['feeDiscount'] as Map)['value'], 400);
        await students.updateStudent(studentId: 's9', student: AdminStudentModel.fromMap('s9', data));
        data = (await firestore.doc('students/s9').get()).data()!;
        expect([(data['admissionDate'] as Timestamp).toDate(), data['customNote'], (data['feeDiscount'] as Map)['value']], [DateTime(2025, 6, 2), 'kept', 400]);
      });

      test('edits: kept when not given; same terms keep the id; new terms a new id; invalid refused with nothing written', () async {
        final id = await students.createStudent(student: model(), createdBy: 'admin', feeDiscount: _d(FeeDiscountType.fixed, 500, id: ''));
        Future<Map> stored() async => (await firestore.doc('students/$id').get()).data()!['feeDiscount'] as Map;
        final first = await stored();
        await students.updateStudent(studentId: id, student: model());
        expect((await stored())['id'], first['id'], reason: 'an unrelated edit keeps the discount');
        expect((await stored())['value'], 500);

        final current = StudentFeeDiscount.fromMap(await stored())!;
        await students.updateStudent(
          studentId: id,
          student: model(),
          feeDiscount: StudentFeeDiscount(id: current.id, type: current.type, value: 500, effectiveFrom: current.effectiveFrom, reason: 'Sibling', isActive: false),
        );
        final deactivated = await stored();
        expect([deactivated['id'], deactivated['isActive'], deactivated['reason']], [first['id'], false, 'Sibling']);
        expect((deactivated['createdAt'] as Timestamp).toDate(), (first['createdAt'] as Timestamp).toDate(), reason: 'createdAt kept');

        await students.updateStudent(studentId: id, student: model(), feeDiscount: _d(FeeDiscountType.fixed, 750, id: current.id));
        expect((await stored())['id'], isNot(first['id']), reason: 'new terms: a new configuration id');

        final before = await stored();
        await expectLater(
          students.updateStudent(studentId: id, student: model(), feeDiscount: _d(FeeDiscountType.percentage, 120)),
          throwsA(isA<StateError>()),
        );
        expect(await stored(), before);
      });
    });
  });

  // ================================================================ calculation
  group('calculation', () {
    test('percentage on the gross fee', () {
      final c = FeeDiscountCalculator.calculate(_d(FeeDiscountType.percentage, 10), 5000, [_c('Tuition', 5000)]);
      expect([c.gross, c.discount, c.net], [5000, 500, 4500]);
      final r = FeeDiscountCalculator.calculate(_d(FeeDiscountType.percentage, 12.5), 333.33, const []);
      expect(r.discount, 41.67, reason: '4166.625 paise rounds half away from zero');
      expect(r.net, 291.66);
    });

    test('fixed: once per assignment, capped at the gross fee (never negative)', () {
      expect(FeeDiscountCalculator.calculate(_d(FeeDiscountType.fixed, 500), 3000, [_c('Care', 3000, 'monthly')]).discount, 500);
      final capped = FeeDiscountCalculator.calculate(_d(FeeDiscountType.fixed, 500), 300, [_c('Care', 300, 'monthly')]);
      expect([capped.discount, capped.net], [300, 0]);
      expect(FeeDiscountCalculator.calculate(_d(FeeDiscountType.percentage, 100), 3000, const []).net, 0);
      expect(FeeDiscountCalculator.calculate(_d(FeeDiscountType.fixed, 500), 0, const []).discount, 0);
    });

    test('term fixed discount across three components: one discount, allocated proportionally to the paisa', () {
      final c = FeeDiscountCalculator.calculate(_d(FeeDiscountType.fixed, 1000), 6000, [_c('Tuition', 4000), _c('Books', 1500), _c('Activity', 500)]);
      expect(c.discount, 1000, reason: 'not 1000 per component');
      expect([for (final a in c.allocation) (a.name, a.discount)], [('Tuition', 666.67), ('Books', 250.0), ('Activity', 83.33)]);
      expect(c.allocation.fold<int>(0, (s, a) => s + (a.discount * 100).round()), 100000, reason: 'shares add up exactly');
    });

    test('allocation: never above a component; ties to the earlier component; unmatched components: one Whole fee line', () {
      final full = FeeDiscountCalculator.calculate(_d(FeeDiscountType.fixed, 9999), 6000, [_c('A', 4000), _c('B', 1500), _c('C', 500)]);
      expect([for (final a in full.allocation) a.discount], [4000, 1500, 500]);
      final tie = FeeDiscountCalculator.calculate(_d(FeeDiscountType.fixed, 1), 300, [_c('A', 100), _c('B', 100), _c('C', 100)]);
      expect([for (final a in tie.allocation) a.discount], [0.34, 0.33, 0.33]);
      final odd = FeeDiscountCalculator.calculate(_d(FeeDiscountType.fixed, 100), 5000, [_c('A', 4000)]);
      expect([for (final a in odd.allocation) (a.name, a.gross, a.discount)], [(FeeDiscountCalculator.wholeFee, 5000.0, 100.0)]);
      final zero = FeeDiscountCalculator.calculate(_d(FeeDiscountType.fixed, 100), 1000, [_c('A', 1000), _c('Free', 0)]);
      expect(zero.allocation.map((a) => a.name), ['A'], reason: 'zero components get nothing');
    });

    test('mixed structure: one discount period, never multiplied by components', () {
      final c = FeeDiscountCalculator.calculate(_d(FeeDiscountType.fixed, 500), 3000, [_c('Care', 1000, 'monthly'), _c('Term', 2000)]);
      expect(c.discount, 500);
      expect([for (final a in c.allocation) a.discount], [166.67, 333.33]);
    });
  });

  // ================================================================ FeeService
  group('FeeService', () {
    late BufferedTransactionFirestore firestore;
    late FeeService fees;
    late FinanceService finance;
    late String year;
    final today = DateTime(2027, 1, 15);

    setUp(() async {
      firestore = BufferedTransactionFirestore();
      final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'admin-uid'));
      finance = FinanceService(firestore: firestore, auth: auth);
      await finance.ensureDefaults();
      fees = FeeService(firestore: firestore, auth: auth, storage: MockFirebaseStorage(), financeService: finance, clock: () => today);
      year = await AcademicYearService(firestore: firestore).createAcademicYear(schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2026-2027',
          startDate: DateTime(2026, 6, 1), endDate: DateTime(2027, 5, 31), createdBy: 'admin-1', setAsCurrent: true);
      await firestore.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
      for (final (id, name, discount) in [
        ('pct', 'Asha Percent', _d(FeeDiscountType.percentage, 10, id: 'cfg-pct')),
        ('fix', 'Bala Fixed', _d(FeeDiscountType.fixed, 500, until: DateTime(2027, 3, 31), id: 'cfg-fix')),
        ('none', 'Chitra None', null),
        ('off', 'Dev Off', _d(FeeDiscountType.percentage, 50, active: false, id: 'cfg-off')),
      ]) {
        await firestore.collection('students').doc(id).set({
          'name': name, 'admissionNo': 'ADM-$id', 'classId': 'c1', 'isActive': true, 'admissionDate': DateTime(2020, 1, 1),
          if (discount != null) 'feeDiscount': _stored(discount),
        });
      }
      Future<void> structure(String id, String name, List<FeeComponentModel> cs) => firestore.collection('fee_structures').doc(id).set({
            'name': name, 'description': '', 'totalAmount': cs.fold<double>(0, (s, c) => s + c.amount), 'academicYear': '2026-2027', 'academicYearId': year,
            'isActive': true, 'createdBy': 't', 'createdAt': DateTime(2026, 1, 1), 'components': [for (final c in cs) c.toMap()],
          });
      await structure('care', 'Day Care', [_c('Care', 3000, 'monthly')]);
      await structure('term', 'Term Fees', [_c('Tuition', 4000), _c('Books', 1500), _c('Activity', 500)]);
      await structure('once', 'Admission Kit', [_c('Kit', 2000, 'oneTime')]);
      await structure('mixed', 'Combined', [_c('Care', 1000, 'monthly'), _c('Term', 2000)]);
    });

    Map<String, dynamic> single(String student, String structure, double total, {String? month, double discount = 0}) => {
          'studentId': student, 'studentName': student, 'admissionNo': 'ADM-$student', 'classId': 'c1', 'className': 'Mont 1',
          'feeStructureId': structure, 'feeStructureName': structure, 'academicYearId': year, 'academicYear': '2026-2027',
          'totalFee': total, 'discountAmount': discount, 'payableAmount': total - discount, 'paidAmount': 0, 'balanceAmount': total - discount, 'status': 'unpaid',
          'feeMonth': ?month, 'dueDate': DateTime(2027, 1, 10),
        };
    Future<Map<String, dynamic>> doc(String id) async => (await firestore.doc('student_fee_assignments/$id').get()).data()!;
    Future<List<Map<String, dynamic>>> all() async => [for (final d in (await firestore.collection('student_fee_assignments').get()).docs) d.data()];
    Future<List<FeeMonthPlan>> plan(String from, String to) async =>
        FeeMonthRange.plan(from, to, await AcademicYearService(firestore: firestore).getAllAcademicYears(schoolId: kDefaultSchoolId), const FeeDueRule(day: 5));
    Future<String> money() async => [
          for (final c in ['fee_receipts', 'fee_transactions', 'finance_ledger'])
            [for (final d in (await firestore.collection(c).get()).docs) '${d.id}:${d.data()}'].join('|'),
        ].join('\n');

    // ---------------------------------------------------------------- new assignments
    group('new assignments', () {
      test('Single Student monthly: percentage and fixed discounts with snapshots; no discount and inactive unchanged', () async {
        final pct = await doc((await fees.assignFee(single('pct', 'care', 3000, month: '2027-01')))!);
        expect([pct['totalFee'], pct['discountAmount'], pct['payableAmount'], pct['balanceAmount'], pct['paidAmount']], [3000, 300, 2700, 2700, 0]);
        final snap = FeeDiscountSnapshot.fromMap(pct['studentDiscount'])!;
        expect([snap.configId, snap.type, snap.value, snap.amount, snap.gross, snap.periodReference, snap.source, snap.appliedBy],
            ['cfg-pct', FeeDiscountType.percentage, 10, 300, 3000, 'month:2027-01', FeeDiscountSource.assignment, 'admin-uid']);
        expect(snap.appliedAt, isNotNull);
        expect(snap.effectiveFrom, DateTime(2026, 6, 1));
        expect([for (final a in snap.allocation) (a.name, a.discount)], [('Care', 300.0)]);

        final fix = await doc((await fees.assignFee(single('fix', 'care', 3000, month: '2027-01')))!);
        expect([fix['discountAmount'], fix['payableAmount']], [500, 2500]);
        for (final s in ['none', 'off']) {
          final a = await doc((await fees.assignFee(single(s, 'care', 3000, month: '2027-01')))!);
          expect([a['discountAmount'], a['payableAmount'], a.containsKey('studentDiscount')], [0, 3000, false], reason: s);
        }
        final model = StudentFeeAssignmentModel.fromMap('x', pct);
        expect([model.studentDiscountAmount, model.manualDiscountAmount], [300, 0]);
      });

      test('recurring monthly: the fixed discount once in each month inside the dates (not after Until)', () async {
        final r = await fees.assignMonthlyFees(
          students: [FeeStudent(id: 'fix', name: 'Bala Fixed'), FeeStudent(id: 'none', name: 'Chitra None')],
          classId: 'c1', className: 'Mont 1', feeStructureId: 'care', feeStructureName: 'Day Care',
          months: await plan('2027-01', '2027-05'), totalFee: 3000, discountAmount: 0,
        );
        expect([r.created, r.studentDiscounted, r.discountConflict], [10, 3, 0]);
        expect(r.message, contains("3 with the student's discount"));
        final fix = {for (final a in await all()) if (a['studentId'] == 'fix') a['feeMonth']: a['discountAmount']};
        expect(fix, {'2027-01': 500, '2027-02': 500, '2027-03': 500, '2027-04': 0, '2027-05': 0});
        expect((await all()).where((a) => a['studentId'] == 'none').every((a) => a['discountAmount'] == 0), isTrue);
      });

      test('Term (three components), One-time and mixed: one fixed discount per assignment, allocated', () async {
        final term = await doc((await fees.assignFee(single('fix', 'term', 6000)))!);
        expect([term['discountAmount'], term['payableAmount']], [500, 5500], reason: 'not 500 × 3 components');
        final snap = FeeDiscountSnapshot.fromMap(term['studentDiscount'])!;
        expect(snap.periodReference, 'date:2027-01-15', reason: 'Term: the assignment date');
        expect([for (final a in snap.allocation) a.discount], [333.33, 125.0, 41.67]);
        expect((await doc((await fees.assignFee(single('fix', 'once', 2000)))!))['discountAmount'], 500);
        expect((await doc((await fees.assignFee(single('fix', 'mixed', 3000)))!))['discountAmount'], 500, reason: 'mixed: one period');
        expect((await doc((await fees.assignFee(single('pct', 'term', 6000)))!))['discountAmount'], 600);
      });

      test('Full Class: discounts per student; retry adds no second assignment or discount', () async {
        Future<Map<String, int>> run() => fees.bulkAssignClassFees(classId: 'c1', className: 'Mont 1', feeStructureId: 'care', feeStructureName: 'Day Care',
            academicYearId: year, academicYear: '2026-2027', totalFee: 3000, discountAmount: 0, feeMonth: '2027-02', dueDate: DateTime(2027, 2, 5));
        expect(await run(), {'assigned': 4, 'skipped': 0, 'admissionSkipped': 0, 'manualReview': 0, 'studentDiscounted': 2, 'discountConflict': 0});
        expect({for (final a in await all()) a['studentId']: a['payableAmount']}, {'pct': 2700, 'fix': 2500, 'none': 3000, 'off': 3000});
        expect(await run(), {'assigned': 0, 'skipped': 4, 'admissionSkipped': 0, 'manualReview': 0, 'studentDiscounted': 0, 'discountConflict': 0});
        expect((await all()).length, 4);
      });

      test('manual discount policy: never combined; Single refused, Full Class and recurring skipped for manual review', () async {
        await expectLater(
          fees.assignFee(single('pct', 'care', 3000, month: '2027-01', discount: 200)),
          throwsA(isA<StateError>().having((e) => e.message, 'message', allOf(contains('not combined'), contains('10%')))),
        );
        expect(await all(), isEmpty, reason: 'nothing written');
        final manual = await doc((await fees.assignFee(single('none', 'care', 3000, month: '2027-01', discount: 200)))!);
        expect([manual['discountAmount'], manual['payableAmount'], manual.containsKey('studentDiscount')], [200, 2800, false], reason: 'manual discounts still work');
        final outside = await doc((await fees.assignFee(single('fix', 'care', 3000, month: '2027-04', discount: 200)))!);
        expect(outside['discountAmount'], 200, reason: 'no student discount applies to April: no conflict');

        final bulk = await fees.bulkAssignClassFees(classId: 'c1', className: 'Mont 1', feeStructureId: 'care', feeStructureName: 'Day Care',
            academicYearId: year, academicYear: '2026-2027', totalFee: 3000, discountAmount: 200, feeMonth: '2027-02', dueDate: DateTime(2027, 2, 5));
        expect(bulk, {'assigned': 2, 'skipped': 0, 'admissionSkipped': 0, 'manualReview': 0, 'studentDiscounted': 0, 'discountConflict': 2});
        final r = await fees.assignMonthlyFees(students: [FeeStudent(id: 'pct', name: 'Asha Percent')], classId: 'c1', className: 'Mont 1',
            feeStructureId: 'care', feeStructureName: 'Day Care', months: await plan('2027-03', '2027-04'), totalFee: 3000, discountAmount: 100);
        expect([r.created, r.discountConflict, r.conflictStudents], [0, 2, ['Asha Percent']]);
        expect(r.message, contains('skipped 2 for manual review (student discount not combined with the manual discount: Asha Percent)'));
      });

      test('structure sync: new assignments discounted once; re-sync never doubles; a changed fee leaves a discounted one untouched', () async {
        Future<Map<String, int>> sync(double total) => fees.syncAssignmentsForFeeStructure(feeStructureId: 'term', feeStructureName: 'Term Fees',
            academicYearId: year, academicYear: '2026-2027', totalFee: total, assignmentScope: 'student', classIds: const [], studentIds: ['pct', 'none'],
            dueDate: DateTime(2027, 2, 28));
        expect(await sync(6000), {'created': 2, 'updated': 0, 'skipped': 0, 'admissionSkipped': 0, 'manualReview': 0});
        Future<Map<String, List<Object?>>> figures() async =>
            {for (final a in await all()) a['studentId'] as String: [a['totalFee'], a['discountAmount'], a['payableAmount'], a['balanceAmount']]};
        expect(await figures(), {'pct': [6000, 600, 5400, 5400], 'none': [6000, 0, 6000, 6000]});
        expect(await sync(6000), {'created': 0, 'updated': 2, 'skipped': 0, 'admissionSkipped': 0, 'manualReview': 0});
        expect(await figures(), {'pct': [6000, 600, 5400, 5400], 'none': [6000, 0, 6000, 6000]}, reason: 'not discounted twice');
        expect(await sync(7000), {'created': 0, 'updated': 1, 'skipped': 1, 'admissionSkipped': 0, 'manualReview': 0});
        expect((await figures())['pct'], [6000, 600, 5400, 5400], reason: 'its snapshot was for ₹6,000: left as it is');
      });

      test('edit restrictions: locked financial fields refused with an explanation; unchanged values and other fields accepted', () async {
        final id = (await fees.assignFee(single('pct', 'care', 3000, month: '2027-01')))!;
        final before = await doc(id);
        for (final (change, field) in <(Map<String, dynamic>, String)>[
          ({'discountAmount': 0.0}, 'discount'),
          ({'discountAmount': 500.0}, 'discount'),
          ({'totalFee': 3500.0}, 'gross fee'),
          ({'studentId': 'none'}, 'student'),
          ({'classId': 'c2', 'className': 'Mont 2'}, 'class'),
          ({'feeMonth': '2027-02'}, 'fee month'),
          ({'feeStructureId': 'once'}, 'fee structure'),
          ({'academicYear': '2027-2028'}, 'academic year'),
          ({'paidAmount': 100.0}, 'payable, collected or outstanding amount'),
        ]) {
          await expectLater(
            fees.updateAssignment(id, change),
            throwsA(isA<StateError>().having((e) => e.message, 'm', allOf(contains('Cannot change the $field'), contains('due date can still be edited')))),
            reason: '$change',
          );
          expect(await doc(id), before, reason: 'nothing written for $change');
        }
        // An ordinary due-date correction, sent with the locked fields unchanged (as the dialog does).
        await fees.updateAssignment(id, {
          'dueDate': DateTime(2027, 1, 20), 'className': 'Mont 1 (renamed)', 'studentId': 'pct', 'feeStructureId': 'care', 'academicYearId': year,
          'academicYear': '2026-2027', 'feeMonth': '2027-01', 'discountAmount': 300.0, 'totalFee': 3000.0,
        });
        final a = await doc(id);
        expect([(a['dueDate'] as Timestamp).toDate(), a['className'], a['totalFee'], a['discountAmount'], a['payableAmount'], a['balanceAmount']],
            [DateTime(2027, 1, 20), 'Mont 1 (renamed)', 3000, 300, 2700, 2700]);
        expect(a['studentDiscount'], before['studentDiscount'], reason: 'snapshot unchanged');
      });

      test('class: a direct service call cannot move a discounted assignment to another class; plain assignments still can', () async {
        await firestore.collection('classes').doc('c2').set({'name': 'Mont 2', 'isActive': true});
        final id = (await fees.assignFee(single('pct', 'care', 3000, month: '2027-01')))!;
        final before = await doc(id);
        await expectLater(
          fees.updateAssignment(id, {'classId': 'c2', 'className': 'Mont 2', 'dueDate': DateTime(2027, 1, 20)}),
          throwsA(isA<StateError>().having((e) => e.message, 'm', allOf(contains('Cannot change the class'), contains('student discount')))),
        );
        expect(await doc(id), before, reason: 'nothing written, not even the due date');
        await fees.updateAssignment(id, {'classId': 'c1', 'dueDate': DateTime(2027, 1, 20)});
        expect([(await doc(id))['classId'], ((await doc(id))['dueDate'] as Timestamp).toDate()], ['c1', DateTime(2027, 1, 20)],
            reason: 'the same class with a due-date correction is accepted');
        final plain = (await fees.assignFee(single('none', 'care', 3000, month: '2027-01')))!;
        await fees.updateAssignment(plain, {'classId': 'c2', 'className': 'Mont 2'});
        expect([(await doc(plain))['classId'], (await doc(plain))['className']], ['c2', 'Mont 2'], reason: 'no student discount: unchanged behaviour');
      });

      test('the snapshot cannot be written, replaced or removed through editing or assigning', () async {
        final id = (await fees.assignFee(single('pct', 'care', 3000, month: '2027-01')))!;
        final original = (await doc(id))['studentDiscount'];
        final forged = {'configId': 'x', 'type': 'fixed', 'value': 3000, 'amount': 3000, 'gross': 3000, 'period': 'month:2027-01', 'source': 'assignment'};
        await fees.updateAssignment(id, {'studentDiscount': forged, 'dueDate': DateTime(2027, 1, 12)});
        expect((await doc(id))['studentDiscount'], original);
        await fees.updateAssignment(id, {'studentDiscount': FieldValue.delete()});
        expect((await doc(id))['studentDiscount'], original);
        // A plain assignment can't be given a snapshot by an edit…
        final plain = (await fees.assignFee(single('none', 'care', 3000, month: '2027-01')))!;
        await fees.updateAssignment(plain, {'studentDiscount': forged});
        expect((await doc(plain)).containsKey('studentDiscount'), isFalse);
        // …nor by the caller of assignFee.
        final made = (await fees.assignFee({...single('none', 'once', 2000), 'studentDiscount': forged}))!;
        expect([(await doc(made)).containsKey('studentDiscount'), (await doc(made))['discountAmount']], [false, 0]);
        // A paid-in-part discounted assignment: due date still editable, amounts kept.
        await fees.collectFee(assignmentId: id, amount: 1000, paymentDate: today, paymentMode: 'cash', referenceNo: '', remarks: '');
        await fees.updateAssignment(id, {'dueDate': DateTime(2027, 1, 25), 'totalFee': 3000.0, 'discountAmount': 300.0});
        final a = await doc(id);
        expect([(a['dueDate'] as Timestamp).toDate(), a['paidAmount'], a['balanceAmount'], a['status']], [DateTime(2027, 1, 25), 1000, 1700, 'partial']);
      });

      test('a changed student configuration never recalculates assignments that already have a discount', () async {
        final id = (await fees.assignFee(single('pct', 'care', 3000, month: '2027-01')))!;
        final before = await doc(id);
        await AdminStudentService(firestore: firestore, storage: MockFirebaseStorage()).updateStudent(
          studentId: 'pct',
          student: AdminStudentModel.fromMap('pct', (await firestore.doc('students/pct').get()).data()!),
          feeDiscount: _d(FeeDiscountType.percentage, 25, id: 'cfg-pct'),
        );
        expect(await doc(id), before);
        final p = await fees.previewStudentDiscounts();
        expect(p.items.single.category, FeeDiscountApplyCategory.alreadyProcessed);
        expect((await fees.applyStudentDiscounts(p)).applied, isEmpty);
        expect(await doc(id), before);
      });

      test('every creation path stores the assignment date (server time) and the period the discount used', () async {
        await fees.assignFee({...single('pct', 'once', 2000), 'assignedAt': DateTime(2001, 1, 1)});
        await fees.bulkAssignClassFees(classId: 'c1', className: 'Mont 1', feeStructureId: 'care', feeStructureName: 'Day Care',
            academicYearId: year, academicYear: '2026-2027', totalFee: 3000, discountAmount: 0, feeMonth: '2027-02', dueDate: DateTime(2027, 2, 5));
        await fees.assignMonthlyFees(students: [FeeStudent(id: 'fix', name: 'Bala Fixed')], classId: 'c1', className: 'Mont 1',
            feeStructureId: 'care', feeStructureName: 'Day Care', months: await plan('2027-03', '2027-03'), totalFee: 3000, discountAmount: 0);
        await fees.syncAssignmentsForFeeStructure(feeStructureId: 'term', feeStructureName: 'Term Fees', academicYearId: year, academicYear: '2026-2027',
            totalFee: 6000, assignmentScope: 'student', classIds: const [], studentIds: ['pct'], dueDate: DateTime(2027, 2, 28));
        final list = await all();
        expect(list.length, 7);
        for (final a in list) {
          expect(a['assignedAt'], isA<Timestamp>(), reason: '${a['studentId']} ${a['feeStructureId']} ${a['feeMonth']}');
          expect((a['assignedAt'] as Timestamp).toDate().year, isNot(2001), reason: 'the caller cannot set it');
          if (a['studentDiscount'] case final Map snap) {
            expect(snap['period'], a['feeMonth'] == null ? 'date:2027-01-15' : 'month:${a['feeMonth']}');
          }
        }
      });

      testWidgets('the edit dialog: a due-date correction saves even after the structure total changed; locked fields shown locked', (tester) async {
        tester.view.physicalSize = const Size(1200, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late String id;
        await tester.runAsync(() async {
          id = (await fees.assignFee(single('pct', 'care', 3000, month: '2027-01')))!;
          await firestore.doc('fee_structures/care').update({'totalAmount': 3500, 'components': [_c('Care', 3500, 'monthly').toMap()]});
        });
        final current = (await tester.runAsync(() => fees.getAssignmentById(id)))!;
        await tester.pumpWidget(ProviderScope(
          overrides: [academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore))],
          child: MaterialApp(home: Scaffold(body: FeeAssignmentDialog(assignment: current, service: fees))),
        ));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('fee-assignment-discount-locked')), findsOneWidget);
        expect(tester.widget<TextField>(find.descendant(of: find.byKey(const Key('fee-assignment-discount')), matching: find.byType(TextField))).readOnly, isTrue);
        await tester.ensureVisible(find.byKey(const Key('fee-due-date-pick')));
        await tester.tap(find.byKey(const Key('fee-due-date-pick')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('20').last);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
        final a = (await tester.runAsync(() => doc(id)))!;
        expect([(a['dueDate'] as Timestamp).toDate(), a['totalFee'], a['discountAmount'], a['payableAmount'], a['feeMonth']],
            [DateTime(2027, 1, 20), 3000, 300, 2700, '2027-01']);
        expect(a['studentDiscount'], isNotNull);
      });

      test('existing assignments are not recalculated when a student is given a discount', () async {
        final id = (await fees.assignFee(single('none', 'care', 3000, month: '2027-01')))!;
        final before = await doc(id);
        await AdminStudentService(firestore: firestore, storage: MockFirebaseStorage()).updateStudent(
          studentId: 'none',
          student: AdminStudentModel.fromMap('none', (await firestore.doc('students/none').get()).data()!),
          feeDiscount: _d(FeeDiscountType.percentage, 20, id: ''),
        );
        expect(await doc(id), before);
        final next = await doc((await fees.assignFee(single('none', 'care', 3000, month: '2027-02')))!);
        expect(next['discountAmount'], 600, reason: 'new assignments get it');
      });

      test('collecting after a discount: the discount reduces what is due, never what was collected', () async {
        final id = (await fees.assignFee(single('fix', 'care', 3000, month: '2027-01')))!;
        await expectLater(fees.collectFee(assignmentId: id, amount: 3000, paymentDate: today, paymentMode: 'cash', referenceNo: '', remarks: ''), throwsA(isA<StateError>()));
        final receipt = await fees.collectFee(assignmentId: id, amount: 2500, paymentDate: today, paymentMode: 'cash', referenceNo: '', remarks: '');
        expect(receipt.amount, 2500);
        final a = await doc(id);
        expect([a['paidAmount'], a['balanceAmount'], a['status']], [2500, 0, 'paid']);
        final income = (await firestore.collection('finance_ledger').get()).docs.where((d) => d.data()['sourceId'] == receipt.id).toList();
        expect(income.single.data()['amount'], 2500, reason: 'Finance records only what was collected; no discount entry');
      });
    });

    // ---------------------------------------------------------------- existing assignments
    group('Apply Student Discounts to Existing Fees', () {
      Future<void> seed(String id, String student, String structure, double total,
          {String? month, double discount = 0, double paid = 0, DateTime? assignedAt, Map<String, dynamic> extra = const {}}) async {
        final payable = total - discount;
        await firestore.collection('student_fee_assignments').doc(id).set({
          ...single(student, structure, total, month: month, discount: discount),
          'id': id, 'paidAmount': paid, 'balanceAmount': payable - paid, 'payableAmount': payable,
          'status': paid >= payable ? 'paid' : paid > 0 ? 'partial' : 'unpaid',
          'assignedAt': assignedAt ?? DateTime(2026, 9, 1),
          ...extra,
        });
      }

      Future<void> seedAll() async {
        await seed('unpaid', 'pct', 'care', 3000, month: '2026-09');
        await seed('partial', 'fix', 'care', 3000, month: '2026-10', paid: 1000);
        await seed('exact', 'fix', 'care', 3000, month: '2026-11', paid: 2500);
        await seed('over', 'fix', 'care', 3000, month: '2026-12', paid: 2800);
        await seed('paid', 'pct', 'care', 3000, month: '2026-10', paid: 3000);
        await seed('manual', 'pct', 'care', 3000, month: '2026-11', discount: 200);
        await seed('after', 'fix', 'care', 3000, month: '2027-04');
        await seed('nomonth', 'pct', 'care', 3000);
        await seed('term', 'fix', 'term', 6000, assignedAt: DateTime(2026, 7, 1));
        await seed('broken', 'pct', 'care', 3000, month: '2026-12', extra: {'balanceAmount': 2000});
        await seed('inactive', 'off', 'care', 3000, month: '2026-09');
        await seed('nodisc', 'none', 'care', 3000, month: '2026-09');
        await seed('deleted', 'pct', 'care', 3000, month: '2027-01', extra: {'isDeleted': true});
      }

      Future<String> dump() async => [
            for (final c in ['student_fee_assignments', 'fee_receipts', 'fee_transactions', 'finance_ledger', 'students'])
              [for (final d in (await firestore.collection(c).get()).docs) '${d.id}:${d.data()}'].join('|'),
          ].join('\n');

      test('preview: every category with reasons and totals; writes nothing', () async {
        await seedAll();
        expect(await fees.assignFee(single('pct', 'once', 2000)), isNotNull); // already processed
        final before = await dump();
        final p = await fees.previewStudentDiscounts();
        expect(await dump(), before, reason: 'preview writes nothing');
        Map<String, FeeDiscountApplyCategory> cats() => {for (final i in p.items) i.assignment.id: i.category};
        final processed = p.items.firstWhere((i) => i.assignment.feeStructureId == 'once').assignment.id;
        expect(cats(), {
          'unpaid': FeeDiscountApplyCategory.eligible,
          'partial': FeeDiscountApplyCategory.eligible,
          'exact': FeeDiscountApplyCategory.eligible,
          'term': FeeDiscountApplyCategory.eligible,
          'over': FeeDiscountApplyCategory.manualReview,
          'manual': FeeDiscountApplyCategory.manualReview,
          'nomonth': FeeDiscountApplyCategory.manualReview,
          'broken': FeeDiscountApplyCategory.manualReview,
          'paid': FeeDiscountApplyCategory.fullyPaid,
          'after': FeeDiscountApplyCategory.outsideDates,
          'inactive': FeeDiscountApplyCategory.outsideDates,
          processed: FeeDiscountApplyCategory.alreadyProcessed,
        }, reason: 'students without a configuration and deleted assignments are not listed');
        FeeDiscountApplyItem item(String id) => p.items.firstWhere((i) => i.assignment.id == id);
        expect([item('partial').proposed, item('partial').revisedPayable, item('partial').revisedOutstanding, item('partial').revisedStatus], [500, 2500, 1500, 'partial']);
        expect([item('exact').revisedOutstanding, item('exact').revisedStatus], [0, 'paid'], reason: 'discount equal to the outstanding amount');
        expect(item('over').reason, allOf(contains('more than the outstanding'), contains('No refund or credit')));
        expect(item('manual').reason, contains('not combined'));
        expect(item('nomonth').reason, contains('no fee month'));
        expect(item('after').reason, contains('after the discount ends'));
        expect(item('term').proposed, 500);
        expect(item('broken').reason, contains('do not reconcile'));
        expect([p.count(FeeDiscountApplyCategory.eligible), p.totalProposed], [4, 300 + 500 + 500 + 500]);
        expect(p.gross(FeeDiscountApplyCategory.fullyPaid), 3000);
      });

      test('expired configuration and assignments outside the effective dates are excluded', () async {
        await firestore.doc('students/pct').update({'feeDiscount': _stored(_d(FeeDiscountType.percentage, 10, from: DateTime(2026, 6, 1), until: DateTime(2026, 8, 31)))});
        await seed('sep', 'pct', 'care', 3000, month: '2026-09');
        await seed('aug', 'pct', 'care', 3000, month: '2026-08');
        final p = await fees.previewStudentDiscounts();
        expect({for (final i in p.items) i.assignment.id: i.category}, {'sep': FeeDiscountApplyCategory.outsideDates, 'aug': FeeDiscountApplyCategory.eligible});
      });

      test('apply: only eligible assignments; collected amounts, receipts and Finance untouched; snapshot is the audit record; never twice', () async {
        await seedAll();
        final id = (await fees.assignFee(single('fix', 'care', 3000, month: '2027-01')))!;
        await fees.collectFee(assignmentId: id, amount: 1000, paymentDate: today, paymentMode: 'cash', referenceNo: '', remarks: '');
        final moneyBefore = await money();
        final untouched = {for (final i in ['over', 'paid', 'manual', 'after', 'nomonth', 'broken', 'inactive', 'nodisc', 'deleted', id]) i: await doc(i)};
        final r = await fees.applyStudentDiscounts(await fees.previewStudentDiscounts());
        expect([r.applied.length, r.skipped.length, r.failed.length, r.totalApplied], [4, 0, 0, 1800]);
        expect(r.message, 'Applied the student discount to 4 assignments, skipped 0 (changed since the preview), failed 0.');
        expect(await money(), moneyBefore, reason: 'receipts, transactions and Finance never touched');
        for (final MapEntry(:key, :value) in untouched.entries) {
          expect(await doc(key), value, reason: '$key unchanged');
        }
        List<Object?> figures(Map<String, dynamic> a) => [a['totalFee'], a['discountAmount'], a['payableAmount'], a['paidAmount'], a['balanceAmount'], a['status']];
        expect(figures(await doc('unpaid')), [3000, 300, 2700, 0, 2700, 'unpaid']);
        expect(figures(await doc('partial')), [3000, 500, 2500, 1000, 1500, 'partial']);
        expect(figures(await doc('exact')), [3000, 500, 2500, 2500, 0, 'paid']);
        expect(figures(await doc('term')), [6000, 500, 5500, 0, 5500, 'unpaid']);
        final snap = FeeDiscountSnapshot.fromMap((await doc('partial'))['studentDiscount'])!;
        expect([snap.source, snap.operationId, snap.appliedBy, snap.configId, snap.amount, snap.periodReference],
            [FeeDiscountSource.existing, r.operationId, 'admin-uid', 'cfg-fix', 500, 'month:2026-10']);
        expect(snap.previous, {'totalFee': 3000, 'discountAmount': 0, 'payableAmount': 3000, 'paidAmount': 1000, 'balanceAmount': 2000, 'status': 'partial'});
        expect(snap.appliedAt, isNotNull);
        expect([for (final a in FeeDiscountSnapshot.fromMap((await doc('term'))['studentDiscount'])!.allocation) a.discount], [333.33, 125.0, 41.67]);

        final again = await fees.previewStudentDiscounts();
        expect(again.eligible, isEmpty);
        expect(again.count(FeeDiscountApplyCategory.alreadyProcessed), 5);
        final after = await dump();
        final r2 = await fees.applyStudentDiscounts(again);
        expect(r2.applied, isEmpty);
        expect(await dump(), after, reason: 'running it again changes nothing');
      });

      test('changed between preview and apply: re-checked and skipped, never applied from stale data', () async {
        await seed('a', 'pct', 'care', 3000, month: '2026-09');
        await seed('b', 'fix', 'care', 3000, month: '2026-10');
        await seed('c', 'fix', 'care', 3000, month: '2026-11');
        await seed('d', 'pct', 'care', 3000, month: '2026-12');
        final p = await fees.previewStudentDiscounts();
        expect(p.eligible.length, 4);
        // a: a payment since; now the discount exceeds what's outstanding.
        await firestore.doc('student_fee_assignments/a').update({'paidAmount': 2900, 'balanceAmount': 100, 'status': 'partial'});
        // b: paid in full since.
        await firestore.doc('student_fee_assignments/b').update({'paidAmount': 3000, 'balanceAmount': 0, 'status': 'paid'});
        // c: a manual discount given since.
        await firestore.doc('student_fee_assignments/c').update({'discountAmount': 100, 'payableAmount': 2900, 'balanceAmount': 2900});
        // d: the student's percentage changed since (new terms).
        await firestore.doc('students/pct').update({'feeDiscount': _stored(_d(FeeDiscountType.percentage, 20, id: 'cfg-pct-2'))});
        final before = {for (final i in ['a', 'b', 'c', 'd']) i: await doc(i)};
        final r = await fees.applyStudentDiscounts(p);
        expect([r.applied.length, r.skipped.length], [0, 4]);
        for (final i in ['a', 'b', 'c', 'd']) {
          expect(await doc(i), before[i], reason: '$i unchanged');
        }
        final reasons = {for (final s in r.skipped) s.assignment.id: s.reason};
        expect(reasons['a'], contains('more than the outstanding'));
        expect(reasons['b'], contains('Fully paid'));
        expect(reasons['c'], contains('not combined'));
        expect(reasons['d'], contains('Preview again'));
      });

      test('safe retry after a partially completed run: failed chunk unchanged, retry applies it once', () async {
        await seed('a', 'pct', 'care', 3000, month: '2026-09');
        await seed('b', 'pct', 'care', 3000, month: '2026-10');
        await seed('c', 'pct', 'care', 3000, month: '2026-11');
        firestore.failCommitWhen = (path) => path.endsWith('/b');
        final r = await fees.applyStudentDiscounts(await fees.previewStudentDiscounts(), chunkSize: 1);
        expect([r.applied.length, r.failed.length, r.failed.single.assignment.id], [2, 1, 'b']);
        expect(r.failed.single.reason, contains('Not saved'));
        expect([(await doc('b'))['discountAmount'], (await doc('b')).containsKey('studentDiscount')], [0, false]);
        firestore.failCommitWhen = null;
        final retry = await fees.applyStudentDiscounts(await fees.previewStudentDiscounts(), chunkSize: 1);
        expect([for (final i in retry.applied) i.assignment.id], ['b']);
        expect({for (final i in ['a', 'b', 'c']) i: (await doc(i))['discountAmount']}, {'a': 300, 'b': 300, 'c': 300}, reason: 'each exactly once');
      });

      test('changes to the gross fee, the structure or a payment after the preview are detected and skipped', () async {
        await seed('gross', 'pct', 'care', 3000, month: '2026-09');
        await seed('term', 'fix', 'once', 2000, assignedAt: DateTime(2026, 7, 1));
        await seed('paidnow', 'pct', 'care', 3000, month: '2026-10');
        await seed('fine', 'pct', 'care', 3000, month: '2026-11');
        final p = await fees.previewStudentDiscounts();
        expect(p.eligible.length, 4);
        await firestore.doc('student_fee_assignments/gross').update({'totalFee': 4000, 'payableAmount': 4000, 'balanceAmount': 4000});
        await firestore.doc('fee_structures/once').update({'isDeleted': true});
        await firestore.doc('student_fee_assignments/paidnow').update({'paidAmount': 500, 'balanceAmount': 2500, 'status': 'partial'});
        final r = await fees.applyStudentDiscounts(p);
        final reasons = {for (final i in r.skipped) i.assignment.id: i.reason};
        expect([for (final i in r.applied) i.assignment.id], ['paidnow', 'fine'],
            reason: 'a part payment that still leaves room for the same discount is applied, with the current collected amount');
        expect(reasons['gross'], allOf(contains('would now be ₹400'), contains('previewed ₹300')));
        expect(reasons['term'], contains('fee structure was not found'));
        expect([(await doc('gross'))['discountAmount'], (await doc('term'))['discountAmount']], [0, 0]);
        final paidnow = await doc('paidnow');
        expect([paidnow['paidAmount'], paidnow['payableAmount'], paidnow['balanceAmount'], paidnow['status']], [500, 2700, 2200, 'partial']);
        expect((FeeDiscountSnapshot.fromMap(paidnow['studentDiscount'])!.previous!)['paidAmount'], 500);
      });

      test('an interrupted chunk (a failed read) writes nothing for any of its assignments; a retry completes them once', () async {
        for (final m in ['09', '10', '11', '12']) {
          await seed('a$m', 'pct', 'care', 3000, month: '2026-$m');
        }
        firestore.failReadWhen = (path) => path.endsWith('/a10');
        final r = await fees.applyStudentDiscounts(await fees.previewStudentDiscounts(), chunkSize: 2);
        expect([r.applied.length, r.failed.length], [2, 2]);
        expect({for (final m in ['09', '10', '11', '12']) m: (await doc('a$m'))['discountAmount']}, {'09': 0, '10': 0, '11': 300, '12': 300},
            reason: 'all-or-nothing per chunk');
        firestore.failReadWhen = null;
        final retry = await fees.applyStudentDiscounts(await fees.previewStudentDiscounts(), chunkSize: 2);
        expect(retry.applied.length, 2);
        expect({for (final m in ['09', '10', '11', '12']) m: (await doc('a$m'))['discountAmount']}, {'09': 300, '10': 300, '11': 300, '12': 300});
      });

      test('after applying: collections are limited to the revised outstanding amount; nothing becomes a credit', () async {
        await seed('partial', 'fix', 'care', 3000, month: '2026-10', paid: 1000);
        await fees.applyStudentDiscounts(await fees.previewStudentDiscounts());
        await expectLater(fees.collectFee(assignmentId: 'partial', amount: 1600, paymentDate: today, paymentMode: 'cash', referenceNo: '', remarks: ''),
            throwsA(isA<StateError>()));
        await fees.collectFee(assignmentId: 'partial', amount: 1500, paymentDate: today, paymentMode: 'cash', referenceNo: '', remarks: '');
        final a = await doc('partial');
        expect([a['paidAmount'], a['payableAmount'], a['balanceAmount'], a['status']], [2500, 2500, 0, 'paid']);
      });

      test('report totals reconcile with the stored assignment records after applying', () async {
        await seedAll();
        await fees.assignFee(single('pct', 'once', 2000));
        await fees.applyStudentDiscounts(await fees.previewStudentDiscounts());
        final data = await fees.getReportData();
        final r = FeeReport.build(
          students: await fees.getStudents(),
          data: data,
          classNames: const {'c1': 'Mont 1'},
          filter: FeeReportFilter(base: FeeListFilter(monthlyStructureIds: const {'care'})),
        );
        final live = [for (final a in await all()) if (a['isDeleted'] != true) a];
        double sum(String k) => live.fold<double>(0, (s, a) => s + (a[k] as num).toDouble());
        double snapSum() => live.fold<double>(0, (s, a) => s + ((a['studentDiscount'] as Map?)?['amount'] as num? ?? 0).toDouble());
        expect([r.assigned, r.discounts, r.payable, r.collected, r.outstanding],
            [sum('totalFee'), sum('discountAmount'), sum('payableAmount'), sum('paidAmount'), sum('balanceAmount')]);
        expect(r.studentDiscounts, snapSum());
        expect(r.manualDiscounts, sum('discountAmount') - snapSum());
        final rows = [...r.monthlySummary, ...r.nonMonthlySummary, ?r.noMonthSummary];
        expect(rows.fold<double>(0, (s, x) => s + x.discounts), r.discounts);
        final h = FeeReportPdfHeader(schoolName: 'Test School', title: FeeReport.schoolTitle, filters: const [], generatedAt: today);
        final words = _pdfWords(await FeeReportPdf.school(r, h, compress: false));
        expect(_hasPhrase(words, 'Student discounts: ${FeeReport.money(r.studentDiscounts, symbol: 'Rs. ')}'), isTrue);
        expect(_hasPhrase(words, 'Total payable: ${FeeReport.money(r.payable, symbol: 'Rs. ')}'), isTrue);
      });

      testWidgets('the dialog: preview counts, confirmation, then the result', (tester) async {
        await tester.runAsync(() async {
          await seed('unpaid', 'pct', 'care', 3000, month: '2026-09');
          await seed('paid', 'pct', 'care', 3000, month: '2026-10', paid: 3000);
        });
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: FeeDiscountApplyDialog(service: fees))));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
        expect(find.text('Preview only: nothing has been changed.'), findsOneWidget);
        expect(find.byKey(const Key('discount-apply-eligible-title')), findsOneWidget);
        expect(tester.widget<Text>(find.byKey(const Key('discount-apply-eligible-title'))).data, startsWith('Eligible: 1 (gross ₹3,000'));
        expect(find.textContaining('Fully paid (excluded): 1'), findsOneWidget);
        expect(find.textContaining('revised payable ₹2,700'), findsOneWidget);
        await tester.tap(find.byKey(const Key('discount-apply-apply')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('discount-apply-confirm')), findsOneWidget);
        await tester.tap(find.byKey(const Key('discount-apply-confirm-ok')));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('discount-apply-summary')), findsOneWidget);
        expect(find.textContaining('Applied the student discount to 1 assignment'), findsOneWidget);
        expect((await tester.runAsync(() => doc('unpaid')))!['payableAmount'], 2700);
      });
    });
  });

  // ================================================================ reports
  group('reports and reconciliation', () {
    StudentFeeAssignmentModel a(String id, String student, double total,
            {String month = '', double discount = 0, double paid = 0, FeeDiscountSnapshot? snap, String structure = 'care'}) =>
        StudentFeeAssignmentModel.fromMap(id, {
          'studentId': student, 'studentName': student, 'feeStructureId': structure, 'feeStructureName': structure == 'care' ? 'Day Care' : 'Term Fees',
          'academicYearId': 'y1', 'academicYear': '2026-2027', 'totalFee': total, 'discountAmount': discount, 'payableAmount': total - discount,
          'paidAmount': paid, 'balanceAmount': total - discount - paid, 'feeMonth': month,
          if (snap != null) 'studentDiscount': {...snap.toMap(), 'appliedAt': Timestamp.fromDate(DateTime(2026, 9, 1))},
        });
    FeeDiscountSnapshot snap(double amount, double gross, String period) => FeeDiscountSnapshot(
          configId: 'cfg', type: FeeDiscountType.fixed, value: amount, effectiveFrom: DateTime(2026, 6, 1), periodReference: period,
          gross: gross, amount: amount, allocation: const [], source: FeeDiscountSource.assignment);
    FeeReportPayment pay(String id, String assignment, String student, double amount, {bool voided = false}) => FeeReportPayment(
        FeeReceiptModel.fromMap(id, {'receiptNo': 'REC-$id', 'assignmentId': assignment, 'studentId': student, 'amount': amount, 'paymentMode': 'cash', 'paymentDate': DateTime(2026, 9, 20)}),
        voided: voided);

    FeeSchoolReport build() => FeeReport.build(
          students: [
            for (final s in ['asha', 'bala', 'chitra', 'dev']) FeeStudent(id: s, name: s, classId: 'c1'),
          ],
          data: FeeReportData(assignments: [
            a('a-sep', 'asha', 3000, month: '2026-09', discount: 300, paid: 1000, snap: snap(300, 3000, 'month:2026-09')),
            a('a-oct', 'asha', 3000, month: '2026-10', discount: 300, snap: snap(300, 3000, 'month:2026-10')),
            a('b-sep', 'bala', 3000, month: '2026-09', discount: 200, paid: 2800), // manual
            a('b-term', 'bala', 6000, discount: 500, paid: 500, snap: snap(500, 6000, 'date:2026-07-01'), structure: 'term'),
            a('c-legacy', 'chitra', 3000, month: '2026-09'), // no discount fields at all
          ], payments: [
            pay('r1', 'a-sep', 'asha', 1000),
            pay('r2', 'a-sep', 'asha', 700, voided: true),
            pay('r3', 'b-sep', 'bala', 2800),
            pay('r4', 'b-term', 'bala', 500),
          ]),
          classNames: const {'c1': 'Mont 1'},
          filter: FeeReportFilter(base: FeeListFilter(monthlyStructureIds: const {'care'})),
        );

    test('gross, discounts (student and manual), net payable, collected, outstanding and % on net payable', () {
      final r = build();
      expect([r.assigned, r.discounts, r.studentDiscounts, r.manualDiscounts, r.payable, r.collected, r.outstanding],
          [18000, 1300, 1100, 200, 16700, 4300, 12400]);
      expect(r.collectionPercent, closeTo(4300 / 16700 * 100, 1e-9));
      expect(r.assigned - r.discounts, r.payable);
      expect(r.collected + r.outstanding, r.payable);
      final asha = r.students.firstWhere((s) => s.student.id == 'asha');
      expect([asha.studentDiscounts, asha.manualDiscounts, asha.collected], [600, 0, 1000], reason: 'the voided ₹700 not counted');
      expect(r.students.firstWhere((s) => s.student.id == 'dev').status, FeePaymentStatus.none, reason: 'no-assignment students included');
      final legacy = r.students.firstWhere((s) => s.student.id == 'chitra').lines.single;
      expect([legacy.discount, legacy.studentDiscount, legacy.manualDiscount, legacy.payable], [0, 0, 0, 3000], reason: 'legacy assignment loads');
      expect(r.count(FeePaymentStatus.paid), 0);
    });

    test('monthly summary shows discounts in their own fee month; Term separately; summaries add up to the totals', () {
      final r = build();
      final months = {for (final row in r.monthlySummary) row.label: [row.assigned, row.discounts, row.payable, row.collected, row.outstanding]};
      expect(months, {
        'September 2026': [9000, 500, 8500, 3800, 4700],
        'October 2026': [3000, 300, 2700, 0, 2700],
      });
      final term = r.nonMonthlySummary.single;
      expect([term.label, term.assigned, term.discounts, term.payable], ['Term Fees', 6000, 500, 5500]);
      final rows = [...r.monthlySummary, ...r.nonMonthlySummary, ?r.noMonthSummary];
      expect(rows.fold<double>(0, (s, x) => s + x.discounts), r.discounts, reason: 'each discount counted once');
      expect(rows.fold<double>(0, (s, x) => s + x.payable), r.payable);
    });

    test('PDF shows the same totals as the screen, with the discount breakdown', () async {
      final r = build();
      final h = FeeReportPdfHeader(schoolName: 'Test School', title: FeeReport.schoolTitle, filters: const [], generatedAt: DateTime(2027, 1, 15, 9, 30));
      final words = _pdfWords(await FeeReportPdf.school(r, h, compress: false));
      for (final (label, value) in [
        ('Total assigned', r.assigned),
        ('Total discounts', r.discounts),
        ('Student discounts', r.studentDiscounts),
        ('Manual discounts', r.manualDiscounts),
        ('Total payable', r.payable),
        ('Total collected', r.collected),
        ('Total outstanding', r.outstanding),
      ]) {
        expect(_hasPhrase(words, '$label:'), isTrue, reason: label);
        expect(_hasPhrase(words, FeeReport.money(value, symbol: 'Rs. ')), isTrue, reason: '$label ${FeeReport.money(value)}');
      }
      expect(_hasPhrase(words, 'Gross Assigned'), isTrue);
      expect(_hasPhrase(words, '(student Rs. 600, manual Rs. 0)'), isTrue, reason: "Asha's breakdown");
      final statement = _pdfWords(await FeeReportPdf.statement(r.students.first, h, compress: false));
      expect(_hasPhrase(statement, 'Student discounts: Rs. 600'), isTrue);
    });
  });

  // ================================================================ student form
  group('Add / Edit Student form', () {
    late FakeFirebaseFirestore firestore;
    late AdminStudentService students;
    setUp(() {
      firestore = FakeFirebaseFirestore();
      students = AdminStudentService(firestore: firestore, storage: MockFirebaseStorage());
    });
    Widget form(Map<String, dynamic> initial) => ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => AppUser(id: 'admin-1', phone: '9999999999', role: 'admin', isActive: true)),
            academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore)),
            studentEnrollmentServiceProvider.overrideWithValue(StudentEnrollmentService(firestore: firestore)),
          ],
          child: MaterialApp(
            home: AdminStudentForm(
              studentId: 's1', initialData: initial, service: students, firestore: firestore, enrollmentService: StudentEnrollmentService(firestore: firestore),
            ),
          ),
        );
    Map<String, dynamic> existing({Map<String, dynamic>? discount}) => {
          'name': 'Anu', 'admissionNo': 'ADM-1', 'classId': 'c1', 'addressLine1': '12 Garden Road', 'city': 'Coimbatore', 'state': 'Tamil Nadu',
          'pincode': '641001', 'isActive': true, 'feeDiscount': ?discount,
        };
    Future<void> save(WidgetTester tester) async {
      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the discount; deactivating saves it inactive with the same id; an unrelated save keeps it', (tester) async {
      final stored = _stored(_d(FeeDiscountType.fixed, 500, until: DateTime(2027, 3, 31), id: 'cfg-1'))..['reason'] = 'Sibling';
      await firestore.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
      await firestore.doc('students/s1').set(existing(discount: stored));
      await tester.pumpWidget(form(existing(discount: stored)));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('student-fee-discount-summary'))).data, '₹500 per fee period · 1 Jun 2026 – 31 Mar 2027 · Active');
      expect(find.text('Reason: Sibling'), findsOneWidget);
      await save(tester);
      expect(((await firestore.doc('students/s1').get()).data()!['feeDiscount'] as Map)['isActive'], isTrue, reason: 'kept on an unrelated save');

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(form(existing(discount: stored)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('student-fee-discount-deactivate')));
      await tester.tap(find.byKey(const Key('student-fee-discount-deactivate')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('student-fee-discount-summary'))).data, endsWith('Inactive'));
      await save(tester);
      final m = (await firestore.doc('students/s1').get()).data()!['feeDiscount'] as Map;
      expect([m['id'], m['isActive'], m['value'], m['reason']], ['cfg-1', false, 500, 'Sibling']);
    });

    testWidgets('editing in the dialog: invalid values are refused; a valid percentage is saved with a new id', (tester) async {
      final stored = _stored(_d(FeeDiscountType.fixed, 500, id: 'cfg-1'));
      await firestore.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
      await firestore.doc('students/s1').set(existing(discount: stored));
      await tester.pumpWidget(form(existing(discount: stored)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('student-fee-discount-edit')));
      await tester.tap(find.byKey(const Key('student-fee-discount-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Percentage'));
      await tester.enterText(find.byKey(const Key('fee-discount-value')), '150');
      await tester.tap(find.byKey(const Key('fee-discount-save')));
      await tester.pumpAndSettle();
      expect(find.text('A percentage discount cannot be more than 100%.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('fee-discount-value')), '15');
      await tester.enterText(find.byKey(const Key('fee-discount-reason')), 'Staff child');
      await tester.tap(find.byKey(const Key('fee-discount-save')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('student-fee-discount-summary'))).data, '15% · From 1 Jun 2026 (no end date) · Active');
      await save(tester);
      final m = (await firestore.doc('students/s1').get()).data()!['feeDiscount'] as Map;
      expect([m['type'], m['value'], m['reason'], m['id'] == 'cfg-1'], ['percentage', 15, 'Staff child', false]);
    });
  });
}

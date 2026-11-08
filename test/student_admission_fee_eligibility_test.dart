// Student Admission Date (optional, never inferred) and admission-aware
// fee assignment: a Monthly fee month is eligible when the student was
// admitted on or before its last day (the admission month in full); a Term
// or One-time fee when admitted on or before the assignment date. Full
// Class, recurring and sync skip students not yet admitted and, with no
// admission date recorded, skip them for manual review. Enforced in
// FeeService. Existing assignments are never changed. Synthetic data only.
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
import 'package:montessori_app/modules/admin/students/models/admission_date.dart';
import 'package:montessori_app/modules/admin/students/providers/student_enrollment_provider.dart';
import 'package:montessori_app/modules/admin/ui/admin_student_form.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/fees/models/fee_admission.dart';
import 'package:montessori_app/modules/fees/models/fee_component_model.dart';
import 'package:montessori_app/modules/fees/models/fee_month_range.dart';
import 'package:montessori_app/modules/fees/models/fee_student.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_assignment_dialog.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';

import 'support/buffered_transaction_firestore.dart';

void main() {
  // ---------------------------------------------------------------- the rule
  group('eligibility rule', () {
    test('4, 5, 6. a month is eligible when admitted on or before its last day', () {
      expect(FeeAdmission.forMonth(DateTime(2026, 8, 15), '2026-08'), FeeAdmissionStatus.eligible, reason: 'mid-month: the full month');
      expect(FeeAdmission.forMonth(DateTime(2026, 9, 1), '2026-08'), FeeAdmissionStatus.notYetAdmitted);
      expect(FeeAdmission.forMonth(DateTime(2026, 9, 1), '2026-09'), FeeAdmissionStatus.eligible);
      expect(FeeAdmission.forMonth(DateTime(2026, 8, 31), '2026-08'), FeeAdmissionStatus.eligible, reason: 'the last day');
      expect(FeeAdmission.forMonth(DateTime(2026, 8, 31, 23, 59), '2026-08'), FeeAdmissionStatus.eligible, reason: 'time of day ignored');
      expect(FeeAdmission.forMonth(DateTime(2028, 2, 29), '2028-02'), FeeAdmissionStatus.eligible, reason: 'leap day');
      expect(FeeAdmission.forMonth(DateTime(2026, 8, 15), '2026-12'), FeeAdmissionStatus.eligible, reason: 'later months');
      expect(FeeAdmission.forMonth(null, '2026-08'), FeeAdmissionStatus.notRecorded, reason: '10. never assumed');
    });

    test('11. Term and One-time: admitted on or before the assignment date', () {
      final today = DateTime(2026, 8, 20);
      expect(FeeAdmission.forDate(DateTime(2026, 8, 20), today), FeeAdmissionStatus.eligible);
      expect(FeeAdmission.forDate(DateTime(2026, 8, 21), today), FeeAdmissionStatus.notYetAdmitted);
      expect(FeeAdmission.forDate(null, today), FeeAdmissionStatus.notRecorded);
      expect(FeeAdmission.check(DateTime(2026, 9, 1), feeMonth: '', assignmentDate: today), FeeAdmissionStatus.notYetAdmitted);
    });
  });

  // ---------------------------------------------------------------- student records
  group('Admission Date on the student record', () {
    late FakeFirebaseFirestore firestore;
    late AdminStudentService students;
    setUp(() {
      firestore = FakeFirebaseFirestore();
      students = AdminStudentService(firestore: firestore, storage: MockFirebaseStorage());
    });

    AdminStudentModel model({String name = 'Anu', DateTime? admitted}) => AdminStudentModel.fromMap('', {
          'name': name, 'admissionNo': 'ADM-1', 'classId': 'c1', 'isActive': true, 'admissionDate': ?admitted,
        });

    test('1. stored as a Timestamp at the local calendar date and read back', () async {
      final id = await students.createStudent(student: model(admitted: DateTime(2026, 8, 15, 14, 30)), createdBy: 'admin');
      final data = (await firestore.doc('students/$id').get()).data()!;
      expect(data['admissionDate'], isA<Timestamp>());
      expect((data['admissionDate'] as Timestamp).toDate(), DateTime(2026, 8, 15));
      expect(AdminStudentModel.fromMap(id, data).admissionDate, DateTime(2026, 8, 15));
      expect(FeeStudent.fromMap(id, data).admissionDate, DateTime(2026, 8, 15));
    });

    test('2. an older record without one reads as not recorded; nothing is inferred or written', () async {
      final id = await students.createStudent(student: model(), createdBy: 'admin');
      final data = (await firestore.doc('students/$id').get()).data()!;
      expect(data.containsKey('admissionDate'), isFalse, reason: 'not the creation date');
      expect(AdminStudentModel.fromMap(id, data).admissionDate, isNull);
      expect(AdmissionDate.label(null), 'Admission date not recorded');
      expect(AdmissionDate.parse('2026-08-15'), isNull, reason: 'only a real date');
    });

    test('3. editing other fields keeps the date; it is removed only explicitly; an impossible year is refused', () async {
      await firestore.doc('students/s1').set({'name': 'Anu', 'admissionNo': 'ADM-1', 'admissionDate': Timestamp.fromDate(DateTime(2026, 8, 15))});
      await students.updateStudent(studentId: 's1', student: model(name: 'Anu R'));
      var data = (await firestore.doc('students/s1').get()).data()!;
      expect([data['name'], (data['admissionDate'] as Timestamp).toDate()], ['Anu R', DateTime(2026, 8, 15)]);
      await expectLater(students.updateStudent(studentId: 's1', student: model(admitted: DateTime(1900))), throwsA(isA<StateError>()));
      await students.updateStudent(studentId: 's1', student: model(admitted: DateTime(2026, 9, 1)));
      expect(((await firestore.doc('students/s1').get()).data()!['admissionDate'] as Timestamp).toDate(), DateTime(2026, 9, 1));
      await students.updateStudent(studentId: 's1', student: model(), clearAdmissionDate: true);
      data = (await firestore.doc('students/s1').get()).data()!;
      expect(data.containsKey('admissionDate'), isFalse);
    });

    Widget form({String? id, Map<String, dynamic>? initial}) => ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => AppUser(id: 'admin-1', phone: '9999999999', role: 'admin', isActive: true)),
            academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore)),
            studentEnrollmentServiceProvider.overrideWithValue(StudentEnrollmentService(firestore: firestore)),
          ],
          child: MaterialApp(
            home: AdminStudentForm(
              studentId: id, initialData: initial, service: students, firestore: firestore, enrollmentService: StudentEnrollmentService(firestore: firestore),
            ),
          ),
        );
    Map<String, dynamic> existing({Object? admitted}) => {
          'name': 'Anu', 'admissionNo': 'ADM-1', 'classId': 'c1', 'addressLine1': '12 Garden Road', 'city': 'Coimbatore', 'state': 'Tamil Nadu',
          'pincode': '641001', 'isActive': true, 'admissionDate': ?admitted,
        };
    Future<void> save(WidgetTester tester) async {
      await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();
    }

    String shown(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('student-admission-date-value'))).data!;

    testWidgets('1, 3. the edit form shows the stored date and keeps it when another field changes', (tester) async {
      await firestore.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
      await firestore.doc('students/s1').set(existing(admitted: Timestamp.fromDate(DateTime(2026, 8, 15))));
      await tester.pumpWidget(form(id: 's1', initial: existing(admitted: Timestamp.fromDate(DateTime(2026, 8, 15)))));
      await tester.pumpAndSettle();
      expect(shown(tester), '15 Aug 2026');
      await tester.enterText(find.byType(TextFormField).at(0), 'Anu Raj');
      await save(tester);
      final data = (await firestore.doc('students/s1').get()).data()!;
      expect([data['name'], (data['admissionDate'] as Timestamp).toDate()], ['Anu Raj', DateTime(2026, 8, 15)]);
    });

    testWidgets('2. an older student: "Admission date not recorded", saves without inventing one; a date can be picked', (tester) async {
      await firestore.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
      await firestore.doc('students/s1').set(existing());
      await tester.pumpWidget(form(id: 's1', initial: existing()));
      await tester.pumpAndSettle();
      expect(shown(tester), 'Admission date not recorded');
      await save(tester);
      expect((await firestore.doc('students/s1').get()).data()!.containsKey('admissionDate'), isFalse);

      // Saving closes the form; open it again to pick a date.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(form(id: 's1', initial: existing()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('student-admission-date-pick')));
      await tester.tap(find.byKey(const Key('student-admission-date-pick')));
      await tester.pumpAndSettle();
      final now = DateTime.now();
      await tester.tap(find.text('10').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await save(tester);
      final saved = (await firestore.doc('students/s1').get()).data()!;
      expect((saved['admissionDate'] as Timestamp).toDate(), DateTime(now.year, now.month, 10));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(form(id: 's1', initial: saved));
      await tester.pumpAndSettle();
      expect(shown(tester), AdmissionDate.label(DateTime(now.year, now.month, 10)));
      await tester.ensureVisible(find.byKey(const Key('student-admission-date-clear')));
      await tester.tap(find.byKey(const Key('student-admission-date-clear')));
      await tester.pumpAndSettle();
      expect(shown(tester), 'Admission date not recorded');
      await save(tester);
      expect((await firestore.doc('students/s1').get()).data()!.containsKey('admissionDate'), isFalse, reason: 'cleared explicitly');
    });
  });

  // ---------------------------------------------------------------- assignment paths
  group('admission-aware assignments (FeeService)', () {
    late BufferedTransactionFirestore firestore;
    late FeeService fees;
    late String year;
    final today = DateTime(2026, 8, 20);

    setUp(() async {
      firestore = BufferedTransactionFirestore();
      final auth = MockFirebaseAuth();
      final finance = FinanceService(firestore: firestore, auth: auth);
      await finance.ensureDefaults();
      fees = FeeService(firestore: firestore, auth: auth, storage: MockFirebaseStorage(), financeService: finance, clock: () => today);
      year = await AcademicYearService(firestore: firestore).createAcademicYear(schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2026-2027',
          startDate: DateTime(2026, 6, 1), endDate: DateTime(2027, 5, 31), createdBy: 'admin-1', setAsCurrent: true);
      await firestore.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
      for (final (id, name, admitted) in [
        ('aug15', 'Aug Fifteen', DateTime(2026, 8, 15)),
        ('aug31', 'Aug ThirtyOne', DateTime(2026, 8, 31)),
        ('sep1', 'Sep One', DateTime(2026, 9, 1)),
        ('old', 'Old Timer', DateTime(2020, 1, 1)),
        ('none', 'No Date', null),
      ]) {
        await firestore.collection('students').doc(id).set({'name': name, 'admissionNo': 'ADM-$id', 'classId': 'c1', 'isActive': true, 'admissionDate': ?admitted});
      }
      Future<void> structure(String id, String name, FeeComponentModel c) => firestore.collection('fee_structures').doc(id).set({
            'name': name, 'description': '', 'totalAmount': c.amount, 'academicYear': '2026-2027', 'academicYearId': year, 'isActive': true,
            'createdBy': 't', 'createdAt': DateTime(2026, 1, 1), 'components': [c.toMap()],
          });
      await structure('care', 'Day Care', FeeComponentModel(name: 'Care', amount: 3000, frequency: 'monthly', dueDayOfMonth: 5, isOptional: false));
      await structure('term', 'Term Fees', FeeComponentModel(name: 'T', amount: 8000, frequency: 'term', termName: 'Term 1', isOptional: false));
    });

    Map<String, dynamic> single(String student, String structure, {String? month, double total = 3000}) => {
          'studentId': student, 'studentName': student, 'admissionNo': 'ADM-$student', 'classId': 'c1', 'className': 'Mont 1',
          'feeStructureId': structure, 'feeStructureName': structure, 'academicYearId': year, 'academicYear': '2026-2027',
          'totalFee': total, 'discountAmount': 0, 'payableAmount': total, 'paidAmount': 0, 'balanceAmount': total, 'status': 'unpaid',
          'feeMonth': ?month, 'dueDate': DateTime(2026, 9, 5),
        };
    Future<List<Map<String, dynamic>>> all() async => [for (final d in (await firestore.collection('student_fee_assignments').get()).docs) d.data()];
    Set<String> keys(List<Map<String, dynamic>> list) => {for (final a in list) '${a['studentId']}:${a['feeMonth'] ?? a['feeStructureId']}'};

    test('7. Single Student: a month ending before admission is refused with the reason; the admission month and later are allowed', () async {
      await expectLater(
        fees.assignFee(single('sep1', 'care', month: '2026-08')),
        throwsA(isA<StateError>().having((e) => e.message, 'message', allOf(contains('admitted on 1 Sep 2026'), contains('The first eligible month is September 2026')))),
      );
      expect(await all(), isEmpty, reason: 'nothing written');
      expect(await fees.assignFee(single('sep1', 'care', month: '2026-09')), isNotNull);
      expect(await fees.assignFee(single('aug15', 'care', month: '2026-08')), isNotNull, reason: 'admitted mid-month: the full month');
      expect(await fees.assignFee(single('aug31', 'care', month: '2026-08')), isNotNull, reason: 'admitted on the last day');
      expect((await all()).map((a) => a['payableAmount']).toSet(), {3000}, reason: 'never prorated');
      expect(await fees.assignFee(single('none', 'care', month: '2026-08')), isNotNull, reason: 'a single, deliberate assignment is the manual review');
    });

    test('8, 10, 12. Full Class: each student by their own date; not yet admitted and no date are skipped and counted apart from duplicates', () async {
      final r = await fees.bulkAssignClassFees(classId: 'c1', className: 'Mont 1', feeStructureId: 'care', feeStructureName: 'Day Care', academicYearId: year,
          academicYear: '2026-2027', totalFee: 3000, discountAmount: 0, feeMonth: '2026-08', dueDate: DateTime(2026, 8, 5));
      expect(r, {'assigned': 3, 'skipped': 0, 'admissionSkipped': 1, 'manualReview': 1, 'studentDiscounted': 0, 'discountConflict': 0});
      expect(keys(await all()), {'aug15:2026-08', 'aug31:2026-08', 'old:2026-08'});
      final again = await fees.bulkAssignClassFees(classId: 'c1', className: 'Mont 1', feeStructureId: 'care', feeStructureName: 'Day Care', academicYearId: year,
          academicYear: '2026-2027', totalFee: 3000, discountAmount: 0, feeMonth: '2026-08', dueDate: DateTime(2026, 8, 5));
      expect(again, {'assigned': 0, 'skipped': 3, 'admissionSkipped': 1, 'manualReview': 1, 'studentDiscounted': 0, 'discountConflict': 0}, reason: 'duplicates still detected, separately');
      expect((await all()).length, 3);
    });

    test('9, 10, 12. recurring: each student from their own eligible month; no date: manual review; duplicates (incl. no-month legacy) still skipped', () async {
      // An older assignment of the structure and year with no month recorded blocks Old Timer's months.
      await firestore.collection('student_fee_assignments').doc('legacy').set({...single('old', 'care'), 'feeMonth': null});
      final r = await fees.assignMonthlyFees(
        students: [for (final id in ['aug15', 'aug31', 'sep1', 'old', 'none']) FeeStudent(id: id, name: id)],
        classId: 'c1', className: 'Mont 1', feeStructureId: 'care', feeStructureName: 'Day Care',
        months: FeeMonthRange.plan('2026-07', '2026-10', await AcademicYearService(firestore: firestore).getAllAcademicYears(schoolId: kDefaultSchoolId),
            const FeeDueRule(day: 5)),
        totalFee: 3000, discountAmount: 0,
      );
      expect([r.created, r.skipped, r.admissionSkipped, r.manualReview, r.failed], [8, 4, 4, 4, 0]);
      expect(r.reviewStudents, ['none']);
      expect(r.message, 'Created 8 assignments, skipped 4 as duplicates, skipped 4 before admission, 4 need manual review (no admission date: none), failed 0.');
      expect(keys((await all()).where((a) => a['feeMonth'] != null).toList()), {
        'aug15:2026-08', 'aug15:2026-09', 'aug15:2026-10',
        'aug31:2026-08', 'aug31:2026-09', 'aug31:2026-10',
        'sep1:2026-09', 'sep1:2026-10',
      });
    });

    test('9. the service reads the admission date itself, not from the caller', () async {
      final r = await fees.assignMonthlyFees(
        students: [FeeStudent(id: 'sep1', name: 'Sep One', admissionDate: DateTime(2020, 1, 1))],
        classId: 'c1', className: 'Mont 1', feeStructureId: 'care', feeStructureName: 'Day Care',
        months: FeeMonthRange.plan('2026-08', '2026-08', await AcademicYearService(firestore: firestore).getAllAcademicYears(schoolId: kDefaultSchoolId),
            const FeeDueRule(day: 5)),
        totalFee: 3000, discountAmount: 0,
      );
      expect([r.created, r.admissionSkipped], [0, 1]);
    });

    test('11. Term: against the assignment date (today) for Single Student, Full Class and sync', () async {
      await expectLater(fees.assignFee(single('sep1', 'term', total: 8000)), throwsA(isA<StateError>().having((e) => e.message, 'm', contains('after the assignment date (20 Aug 2026)'))));
      expect(await fees.assignFee(single('aug15', 'term', total: 8000)), isNotNull);
      final bulk = await fees.bulkAssignClassFees(classId: 'c1', className: 'Mont 1', feeStructureId: 'term', feeStructureName: 'Term Fees', academicYearId: year,
          academicYear: '2026-2027', totalFee: 8000, discountAmount: 0, dueDate: DateTime(2026, 9, 30));
      expect(bulk, {'assigned': 1, 'skipped': 1, 'admissionSkipped': 2, 'manualReview': 1, 'studentDiscounted': 0, 'discountConflict': 0}, reason: 'old assigned; aug15 duplicate; aug31 and sep1 after today');
      final sync = await fees.syncAssignmentsForFeeStructure(feeStructureId: 'term', feeStructureName: 'Term Fees', academicYearId: year, academicYear: '2026-2027',
          totalFee: 8000, assignmentScope: 'class', classIds: ['c1'], studentIds: const [], dueDate: DateTime(2026, 9, 30));
      expect(sync, {'created': 0, 'updated': 2, 'skipped': 0, 'admissionSkipped': 2, 'manualReview': 1});
      expect(keys(await all()), {'aug15:term', 'old:term'});
      expect((await all()).any((a) => a.containsKey('feeMonth')), isFalse, reason: 'no month invented');
    });

    test('13. existing assignments and payment records are never changed by the admission rule', () async {
      // Sep One has an older August assignment (before the rule) with a payment.
      final id = (await fees.assignFee({...single('old', 'care', month: '2026-07')}))!;
      await firestore.doc('student_fee_assignments/$id').update({'studentId': 'sep1', 'studentName': 'sep1', 'feeMonth': '2026-08'});
      await fees.collectFee(assignmentId: id, amount: 1000, paymentDate: DateTime(2026, 8, 10), paymentMode: 'cash', referenceNo: '', remarks: '');
      final assignment = (await firestore.doc('student_fee_assignments/$id').get()).data();
      Future<String> money() async => [
            for (final c in ['fee_receipts', 'fee_transactions', 'finance_ledger'])
              [for (final d in (await firestore.collection(c).get()).docs) '${d.id}:${d.data()}'].join('|'),
          ].join('\n');
      final before = await money();
      await fees.bulkAssignClassFees(classId: 'c1', className: 'Mont 1', feeStructureId: 'care', feeStructureName: 'Day Care', academicYearId: year,
          academicYear: '2026-2027', totalFee: 3000, discountAmount: 0, feeMonth: '2026-08', dueDate: DateTime(2026, 8, 5));
      await fees.assignMonthlyFees(
        students: [const FeeStudent(id: 'sep1', name: 'Sep One')], classId: 'c1', className: 'Mont 1', feeStructureId: 'care', feeStructureName: 'Day Care',
        months: FeeMonthRange.plan('2026-08', '2026-09', await AcademicYearService(firestore: firestore).getAllAcademicYears(schoolId: kDefaultSchoolId),
            const FeeDueRule(day: 5)),
        totalFee: 3000, discountAmount: 0,
      );
      expect((await firestore.doc('student_fee_assignments/$id').get()).data(), assignment, reason: 'kept as it was');
      expect(await money(), before);
    });
  });

  // ---------------------------------------------------------------- dialog
  group('Assign Fee dialog', () {
    late BufferedTransactionFirestore firestore;
    late FeeService fees;
    setUp(() async {
      firestore = BufferedTransactionFirestore();
      fees = FeeService(firestore: firestore, auth: MockFirebaseAuth(), storage: MockFirebaseStorage());
      final year = await AcademicYearService(firestore: firestore).createAcademicYear(schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2026-2027',
          startDate: DateTime(2026, 6, 1), endDate: DateTime(2027, 5, 31), createdBy: 'admin-1', setAsCurrent: true);
      await firestore.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
      for (final (id, name, admitted) in [('a', 'Anu', DateTime(2026, 8, 15)), ('b', 'Bala', DateTime(2026, 9, 1)), ('c', 'Chitra', null)]) {
        await firestore.collection('students').doc(id).set({'name': name, 'admissionNo': 'ADM-$id', 'classId': 'c1', 'isActive': true, 'admissionDate': ?admitted});
      }
      await firestore.collection('fee_structures').doc('care').set({
        'name': 'Day Care', 'description': '', 'totalAmount': 3000, 'academicYear': '2026-2027', 'academicYearId': year, 'isActive': true, 'createdBy': 't',
        'createdAt': DateTime(2026, 1, 1),
        'components': [FeeComponentModel(name: 'Care', amount: 3000, frequency: 'monthly', dueDayOfMonth: 5, isOptional: false).toMap()],
      });
    });

    Future<void> choose(WidgetTester tester, Finder dropdown, String option) async {
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining(option).last);
      await tester.pumpAndSettle();
    }

    Finder field(String label) => find.widgetWithText(DropdownButtonFormField<String>, label);
    String note(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('fee-admission-note'))).data!;

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore))],
        child: MaterialApp(home: Scaffold(body: FeeAssignmentDialog(service: fees))),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('Single Student shows the admission date, warns for an earlier month, and flags a missing date', (tester) async {
      await pump(tester);
      await choose(tester, field('Select Class *'), 'Mont 1');
      await choose(tester, field('Select Student *'), 'Bala');
      await choose(tester, field('Fee Structure *'), 'Day Care');
      await choose(tester, find.byKey(const Key('fee-month')), 'August 2026');
      expect(note(tester), 'Admitted 1 Sep 2026. Months before September 2026 are not assigned.');
      await choose(tester, field('Select Student *'), 'Chitra');
      expect(note(tester), contains('Admission date not recorded for Chitra'));
      await choose(tester, field('Select Student *'), 'Anu');
      expect(note(tester), 'Admitted 15 Aug 2026.');
    });

    testWidgets('8. Full Class: the confirmation counts students skipped by admission date and for manual review', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Full Class'));
      await tester.pumpAndSettle();
      await choose(tester, field('Select Class *'), 'Mont 1');
      await choose(tester, field('Fee Structure *'), 'Day Care');
      await choose(tester, find.byKey(const Key('fee-month')), 'August 2026');
      expect(note(tester), 'By admission date: 1 eligible, 1 skipped (not yet admitted), 1 skipped for manual review (no admission date recorded).');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('fee-bulk-confirm-summary'))).data, contains('By admission date: 1 eligible, 1 skipped'));
      await tester.tap(find.byKey(const Key('fee-bulk-confirm-ok')));
      await tester.pumpAndSettle();
      final saved = (await tester.runAsync(() => firestore.collection('student_fee_assignments').get()))!.docs;
      expect(saved.map((d) => d.data()['studentId']), ['a']);
    });
  });
}

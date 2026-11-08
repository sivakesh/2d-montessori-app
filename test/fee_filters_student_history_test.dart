// Fees: the shared Academic Year / Class / Student filters (Assignments,
// Collections, Receipts, Dues, Students), the Students tab and the
// read-only Student Fee History. Filters go by stored ids: an assignment's
// own academic year and class, a receipt through its linked assignment,
// students by id. Synthetic test data only.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/settings/providers/academic_year_provider.dart';
import 'package:montessori_app/modules/fees/models/fee_collection_record.dart';
import 'package:montessori_app/modules/fees/models/fee_component_model.dart';
import 'package:montessori_app/modules/fees/models/fee_list_filter.dart';
import 'package:montessori_app/modules/fees/models/fee_overview.dart';
import 'package:montessori_app/modules/fees/models/fee_receipt_model.dart';
import 'package:montessori_app/modules/fees/models/student_fee_assignment_model.dart';
import 'package:montessori_app/modules/fees/models/student_fee_history.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/admin_fees_screen.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_receipt_view_dialog.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';

import 'support/buffered_transaction_firestore.dart';

void main() {
  late BufferedTransactionFirestore firestore;
  late FeeService fees;
  late String oldYear, year;
  late Map<String, String> receipts;

  Future<void> assign(String id, String student, String name, String adm, String classId, String className, String structureId, String structureName, {
    String? yearId, String yearName = '2026-2027', String? feeMonth, DateTime? assignedAt, double total = 3000, double discount = 0,
  }) =>
      firestore.collection('student_fee_assignments').doc(id).set({
        'studentId': student, 'studentName': name, 'admissionNo': adm, 'classId': classId, 'className': className,
        'feeStructureId': structureId, 'feeStructureName': structureName, 'academicYearId': ?yearId, 'academicYear': yearName,
        'totalFee': total, 'discountAmount': discount, 'payableAmount': total - discount, 'paidAmount': 0, 'balanceAmount': total - discount,
        'status': 'unpaid', 'feeMonth': ?feeMonth, 'assignedAt': ?assignedAt,
      });

  Future<String> collect(String id, double amount, DateTime date, String mode, {String ref = '', String notes = ''}) async =>
      (await fees.collectFee(assignmentId: id, amount: amount, paymentDate: date, paymentMode: mode, referenceNo: ref, remarks: notes)).id;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    final auth = MockFirebaseAuth();
    final finance = FinanceService(firestore: firestore, auth: auth);
    await finance.ensureDefaults();
    fees = FeeService(firestore: firestore, auth: auth, storage: MockFirebaseStorage(), financeService: finance);
    final years = AcademicYearService(firestore: firestore);
    oldYear = await years.createAcademicYear(schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2025-2026',
        startDate: DateTime(2025, 6, 1), endDate: DateTime(2026, 5, 31), createdBy: 'admin-1');
    year = await years.createAcademicYear(schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2026-2027',
        startDate: DateTime(2026, 6, 1), endDate: DateTime(2027, 5, 31), createdBy: 'admin-1', setAsCurrent: true);
    await firestore.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
    await firestore.collection('classes').doc('c2').set({'name': 'Mont 2', 'isActive': true});
    // Dev was in Mont 1 last year and is in Mont 2 now; Chitra has no fees.
    for (final (id, name, adm, cls) in [('s1', 'Anu', 'ADM-1', 'c1'), ('s2', 'Bala', 'ADM-2', 'c2'), ('s3', 'Chitra', 'ADM-3', 'c1'), ('s4', 'Dev', 'ADM-4', 'c2')]) {
      await firestore.collection('students').doc(id).set({'name': name, 'admissionNo': adm, 'classId': cls, 'isActive': true});
    }
    Future<void> structure(String id, String name, double amount, String freq, String yearId, String yearName) => firestore.collection('fee_structures').doc(id).set({
          'name': name, 'description': '', 'totalAmount': amount, 'academicYear': yearName, 'academicYearId': yearId, 'isActive': true, 'createdBy': 't',
          'createdAt': DateTime(2026, 1, 1),
          'components': [FeeComponentModel(name: '$name part', amount: amount, frequency: freq, isOptional: false).toMap()],
        });
    await structure('daycare', 'Day Care', 3000, 'monthly', year, '2026-2027');
    await structure('term1', 'Term Fees', 20000, 'term', year, '2026-2027');
    await structure('old', 'Old Fees', 15000, 'term', oldYear, '2025-2026');

    await assign('a-term', 's1', 'Anu', 'ADM-1', 'c1', 'Mont 1', 'term1', 'Term Fees', yearId: year, assignedAt: DateTime(2026, 6, 10), total: 20000, discount: 2000);
    await assign('a-jan', 's1', 'Anu', 'ADM-1', 'c1', 'Mont 1', 'daycare', 'Day Care', yearId: year, feeMonth: '2027-01', assignedAt: DateTime(2026, 12, 1));
    await assign('a-feb', 's1', 'Anu', 'ADM-1', 'c1', 'Mont 1', 'daycare', 'Day Care', yearId: year, feeMonth: '2027-02', assignedAt: DateTime(2027, 1, 1));
    await assign('a-bala', 's2', 'Bala', 'ADM-2', 'c2', 'Mont 2', 'term1', 'Term Fees', yearId: year, assignedAt: DateTime(2026, 6, 12), total: 20000);
    // An older Monthly assignment: no month, no year id (its stored label
    // only), no assigned date.
    await assign('a-legacy', 's2', 'Bala', 'ADM-2', 'c2', 'Mont 2', 'daycare', 'Day Care');
    await assign('a-dev-old', 's4', 'Dev', 'ADM-4', 'c1', 'Mont 1', 'old', 'Old Fees', yearId: oldYear, yearName: '2025-2026', assignedAt: DateTime(2025, 6, 5), total: 15000);

    // January's fee paid in February: ₹1000 cash, ₹500 UPI (voided), ₹1500
    // bank transfer. February ₹3000 cheque. Term ₹5000. Dev ₹15000 last
    // year. Bala ₹2000.
    receipts = {
      'jan1': await collect('a-jan', 1000, DateTime(2027, 2, 5), 'cash', notes: 'First part'),
      'jan2': await collect('a-jan', 500, DateTime(2027, 2, 10), 'upi', ref: 'UPI-1'),
      'jan3': await collect('a-jan', 1500, DateTime(2027, 2, 20), 'bank_transfer', ref: 'NEFT-1'),
      'feb': await collect('a-feb', 3000, DateTime(2027, 2, 3), 'cheque', ref: 'CHQ-1'),
      'term': await collect('a-term', 5000, DateTime(2026, 7, 1), 'cash'),
      'dev': await collect('a-dev-old', 15000, DateTime(2025, 7, 1), 'cash'),
      'bala': await collect('a-bala', 2000, DateTime(2026, 6, 15), 'upi'),
    };
    await fees.voidReceipt(receipts['jan2']!);
    // A fixed void date (the service stamps the time of voiding).
    await firestore.collection('fee_receipts').doc(receipts['jan2']).update({'voidedAt': DateTime(2027, 2, 25)});
    // An old receipt for Anu with no assignment and no payment date.
    receipts['old'] = (await firestore.collection('fee_receipts').add({
      'receiptNo': 'OLD-1', 'studentId': 's1', 'studentName': 'Anu', 'feeStructureName': 'Day Care', 'amount': 99, 'paymentMode': 'cash', 'createdAt': DateTime(2024, 1, 1),
    })).id;
  });

  Finder key(String k) => find.byKey(Key(k));
  String textOf(WidgetTester tester, Finder f) {
    final w = tester.widget(f);
    return w is Text ? w.data! : tester.widget<Text>(find.descendant(of: f, matching: find.byType(Text)).last).data!;
  }

  Future<void> pumpFees(WidgetTester tester, String tab, {Size size = const Size(1400, 2600), DateTime Function()? clock}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore))],
      child: MaterialApp(home: AdminFeesScreen(service: fees, clock: clock ?? DateTime.now)),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, tab));
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

  Future<void> tab(WidgetTester tester, String name) => tap(tester, find.widgetWithText(ChoiceChip, name));

  Future<void> chooseYear(WidgetTester tester, String label) async {
    await tap(tester, key('fees-filter-year'));
    await tap(tester, find.text(label).last);
  }

  Future<void> chooseClass(WidgetTester tester, String label) async {
    await tap(tester, key('fees-filter-class'));
    await tap(tester, find.text(label).last);
  }

  Future<void> chooseStudent(WidgetTester tester, String id, {String? search}) async {
    await tap(tester, key('fees-filter-student'));
    if (search != null) {
      await tester.enterText(key('fees-student-picker-search'), search);
      await tester.pumpAndSettle();
    }
    await tap(tester, key('fees-student-option-$id'));
  }

  // The value a filter field shows (its label is also a Text inside it).
  String shown(WidgetTester tester, String k) => find
      .descendant(of: key(k), matching: find.byType(Text))
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .firstWhere((t) => !{'Academic Year', 'Class', 'Student'}.contains(t));
  String yearShown(WidgetTester tester) => shown(tester, 'fees-filter-year');
  Finder text(String t) => find.text(t);

  group('shared filters', () {
    testWidgets('1. the academic year starts on the current year; Assignments shows only that year (by id, or an older one’s stored label)', (tester) async {
      await pumpFees(tester, 'Assignments');
      expect(yearShown(tester), '2026-2027 (current)');
      expect(text('Mont 1 • Day Care • January 2027'), findsOneWidget);
      expect(text('Mont 1 • Term Fees'), findsOneWidget);
      expect(text('Mont 2 • Day Care • month not recorded'), findsOneWidget, reason: 'matched by its own stored label');
      expect(text('Mont 1 • Old Fees'), findsNothing, reason: 'last year');
      expect(tester.widget<ButtonStyleButton>(key('fees-filter-reset')).onPressed, isNull);
    });

    testWidgets('2, 9. changing the year filters every tab; an empty result says so and Reset returns to the current year', (tester) async {
      await pumpFees(tester, 'Assignments');
      await chooseYear(tester, '2025-2026');
      expect(text('Mont 1 • Old Fees'), findsOneWidget);
      expect(text('Mont 1 • Term Fees'), findsNothing);

      await tab(tester, 'Collections');
      expect(text('Old Fees'), findsOneWidget, reason: 'last year is paid, and still listed');
      expect(find.byKey(const Key('collection-collect-a-dev-old')), findsNothing, reason: 'nothing to collect');
      await tab(tester, 'Dues');
      expect(key('fees-dues-filter-empty'), findsOneWidget);
      await tab(tester, 'Receipts');
      expect(find.textContaining('Old Fees • 15000'), findsOneWidget);
      expect(find.textContaining('Day Care'), findsNothing);
      expect(key('fees-receipts-unlinked'), findsOneWidget, reason: 'OLD-1 has no assignment to place it');
      await tab(tester, 'Students');
      expect(text('1 fee assignment in 2025-2026 • Outstanding: 0'), findsOneWidget, reason: 'Dev');
      expect(text('No fee assignments in 2025-2026'), findsNWidgets(3));

      await tab(tester, 'Dues');
      await tap(tester, key('fees-dues-filter-empty-reset'));
      expect(yearShown(tester), '2026-2027 (current)');
      expect(text('Due: 500 • January 2027'), findsOneWidget);

      await chooseYear(tester, 'All Academic Years');
      await tab(tester, 'Receipts');
      expect(text('OLD-1'), findsOneWidget, reason: 'unplaceable receipts show under All Academic Years');
      expect(key('fees-receipts-unlinked'), findsNothing);
    });

    testWidgets('3. class: the class an assignment was made under (history stays with its class); Students by current class', (tester) async {
      await pumpFees(tester, 'Assignments');
      await chooseClass(tester, 'Mont 2');
      expect(text('Mont 2 • Term Fees'), findsOneWidget);
      expect(text('Mont 1 • Term Fees'), findsNothing);
      await chooseYear(tester, 'All Academic Years');
      await chooseClass(tester, 'Mont 1');
      expect(text('Mont 1 • Old Fees'), findsOneWidget, reason: 'Dev’s Mont 1 assignment, though Dev is now in Mont 2');
      await tab(tester, 'Students');
      expect(text('Anu'), findsOneWidget);
      expect(text('Chitra'), findsOneWidget);
      expect(text('Dev'), findsNothing, reason: 'current class is Mont 2');
      expect(text('Bala'), findsNothing);
    });

    testWidgets('4. student: by id, chosen in a searchable picker; Receipts follow the linked assignment', (tester) async {
      await pumpFees(tester, 'Assignments');
      await chooseStudent(tester, 's2', search: 'adm-2');
      expect(shown(tester, 'fees-filter-student'), 'Bala (ADM-2)');
      expect(find.text('Bala'), findsNWidgets(2));
      expect(find.text('Anu'), findsNothing);
      await tab(tester, 'Receipts');
      expect(find.textContaining('Bala • ADM-2'), findsOneWidget);
      expect(find.textContaining('Anu • '), findsNothing);
      await tap(tester, key('fees-filter-student-clear'));
      expect(shown(tester, 'fees-filter-student'), 'All Students');
    });

    testWidgets('5. combined: year, class and student together (Collections keeps each assignment and month)', (tester) async {
      await pumpFees(tester, 'Collections');
      await chooseClass(tester, 'Mont 1');
      await chooseStudent(tester, 's1');
      expect(text('Day Care • January 2027'), findsOneWidget);
      expect(text('Term Fees'), findsOneWidget);
      expect(text('Day Care • February 2027'), findsOneWidget, reason: 'paid, still listed');
      expect(key('collection-collect-a-feb'), findsNothing, reason: 'paid: no Collect');
      expect(key('collection-collect-a-jan'), findsOneWidget);
      expect(find.text('Bala'), findsNothing);
      expect(find.text('Anu'), findsNWidgets(3));
      await chooseYear(tester, '2025-2026');
      expect(key('fees-collections-filter-empty'), findsOneWidget);
    });

    testWidgets('6. the student is cleared when the new class isn’t theirs (current class or a class they had fees under)', (tester) async {
      await pumpFees(tester, 'Assignments');
      await chooseStudent(tester, 's2');
      await chooseClass(tester, 'Mont 1');
      expect(shown(tester, 'fees-filter-student'), 'All Students', reason: 'Bala was never in Mont 1');
      await chooseClass(tester, 'All Classes');
      await chooseStudent(tester, 's4');
      await chooseClass(tester, 'Mont 1');
      expect(shown(tester, 'fees-filter-student'), 'Dev (ADM-4)', reason: 'Dev had fees under Mont 1');
      await chooseClass(tester, 'Mont 2');
      expect(shown(tester, 'fees-filter-student'), 'Dev (ADM-4)', reason: 'Dev’s current class');
      // The picker offers only the class's students.
      await tap(tester, key('fees-filter-student'));
      expect(key('fees-student-option-s1'), findsNothing);
      expect(key('fees-student-option-s2'), findsOneWidget);
    });

    testWidgets('7. text search works within the filters', (tester) async {
      await pumpFees(tester, 'Assignments');
      await chooseClass(tester, 'Mont 1');
      await tester.enterText(key('fees-assignments-search'), 'february');
      await tester.pumpAndSettle();
      expect(text('Mont 1 • Day Care • February 2027'), findsOneWidget);
      expect(text('Mont 1 • Day Care • January 2027'), findsNothing);
      await chooseClass(tester, 'Mont 2');
      expect(key('fees-assignments-search-empty'), findsOneWidget, reason: 'the query is kept');
    });

    testWidgets('8. pagination returns to page 1 when a filter changes', (tester) async {
      for (var i = 0; i < 15; i++) {
        await assign('x$i', 's3', 'Chitra', 'ADM-3', 'c1', 'Mont 1', 'term1', 'Term Fees', yearId: year, assignedAt: DateTime(2026, 6, 1 + i), total: 100);
      }
      await pumpFees(tester, 'Assignments');
      await tap(tester, find.descendant(of: key('fees-assignments-pagination'), matching: find.byTooltip('Next page')));
      expect(find.textContaining('Page 2 of'), findsOneWidget);
      await chooseClass(tester, 'Mont 1');
      expect(find.textContaining('Page 1 of 2'), findsOneWidget);
      await tap(tester, find.descendant(of: key('fees-assignments-pagination'), matching: find.byTooltip('Next page')));
      await chooseStudent(tester, 's3');
      expect(find.textContaining('Page 1 of 2'), findsOneWidget);
    });

    for (final size in const [Size(1400, 1200), Size(800, 1400), Size(360, 900)]) {
      testWidgets('${size.width.toInt()}px: the filters fit', (tester) async {
        await pumpFees(tester, 'Dues', size: size);
        expect(tester.takeException(), isNull);
        for (final k in ['fees-filter-year', 'fees-filter-class', 'fees-filter-student', 'fees-filter-reset']) {
          expect(tester.getRect(key(k)).right, lessThanOrEqualTo(size.width), reason: k);
        }
        if (size.width < 600) {
          expect(tester.getRect(key('fees-filter-year')).bottom, lessThanOrEqualTo(tester.getRect(key('fees-filter-class')).top), reason: 'stacked');
        }
      });
    }
  });

  group('Students tab', () {
    testWidgets('10, 11, 12. every student (one without fees too); search by name or admission no.; class filter', (tester) async {
      await pumpFees(tester, 'Students');
      for (final n in ['Anu', 'Bala', 'Chitra', 'Dev']) {
        expect(text(n), findsOneWidget, reason: n);
      }
      expect(text('ADM-3 • Mont 1'), findsOneWidget);
      expect(text('No fee assignments in 2026-2027'), findsNWidgets(2), reason: 'Chitra, and Dev this year');
      expect(text('3 fee assignments in 2026-2027 • Outstanding: 13500'), findsOneWidget, reason: 'Anu');
      await tester.enterText(key('fees-students-search'), 'chit');
      await tester.pumpAndSettle();
      expect(text('Chitra'), findsOneWidget);
      expect(text('Anu'), findsNothing);
      await tester.enterText(key('fees-students-search'), 'adm-2');
      await tester.pumpAndSettle();
      expect(text('Bala'), findsOneWidget);
      await tester.enterText(key('fees-students-search'), '');
      await chooseClass(tester, 'Mont 2');
      expect([for (final n in ['Anu', 'Bala', 'Chitra', 'Dev']) text(n).evaluate().length], [0, 1, 0, 1]);
    });

    testWidgets('13, 14. View Fee History opens that student, for the selected year', (tester) async {
      await pumpFees(tester, 'Students');
      await tap(tester, key('student-view-history-s4'));
      expect(find.descendant(of: key('student-history-student'), matching: text('Dev')), findsOneWidget);
      expect(textOf(tester, key('student-history-year')), '2026-2027');
      expect(key('student-history-empty'), findsOneWidget);
      await tap(tester, key('student-history-close'));
      await chooseYear(tester, '2025-2026');
      await tap(tester, key('student-view-history-s4'));
      expect(textOf(tester, key('student-history-year')), '2025-2026');
      expect(key('student-history-assignment-a-dev-old'), findsOneWidget);
      expect(textOf(tester, key('student-history-collected')), '₹15,000');
    });
  });

  group('Student Fee History', () {
    Future<void> openAnu(WidgetTester tester, {String? yearLabel}) async {
      await pumpFees(tester, 'Students');
      if (yearLabel != null) await chooseYear(tester, yearLabel);
      await tap(tester, key('student-view-history-s1'));
    }

    testWidgets('15, 16, 20, 21. assignments (each month separate), totals, cancelled payment shown but not counted', (tester) async {
      await openAnu(tester);
      for (final id in ['a-term', 'a-jan', 'a-feb']) {
        expect(key('student-history-assignment-$id'), findsOneWidget, reason: id);
      }
      expect(tester.getRect(key('student-history-assignment-a-term')).top, lessThan(tester.getRect(key('student-history-assignment-a-jan')).top), reason: 'by assigned date');
      expect(textOf(tester, key('student-history-month-a-jan')), 'January 2027');
      expect(textOf(tester, key('student-history-month-a-feb')), 'February 2027');
      expect(find.descendant(of: key('student-history-assignment-a-jan'), matching: key('collection-payment-${receipts['feb']}')), findsNothing);
      expect(find.descendant(of: key('student-history-assignment-a-feb'), matching: key('collection-payment-${receipts['feb']}')), findsOneWidget);
      expect(find.descendant(of: key('student-history-assignment-a-term'), matching: find.textContaining('Term Fees part ₹20,000 (term)')), findsOneWidget);
      expect(
        [for (final k in ['assigned', 'discounts', 'payable', 'collected', 'outstanding']) textOf(tester, key('student-history-$k'))],
        ['₹26,000', '₹2,000', '₹24,000', '₹10,500', '₹13,500'],
      );
      expect([textOf(tester, key('student-history-paid-a-jan')), textOf(tester, key('student-history-balance-a-jan'))], ['₹2,500', '₹500']);
      expect(tester.widget<Text>(key('student-history-payments-count')).data, '5 payments: completed payments total ₹10,500; 1 cancelled, not counted.');
      expect(key('student-history-total-mismatch'), findsNothing);
      expect(textOf(tester, key('collection-payment-status-${receipts['jan2']}')), 'Cancelled (voided)');
    });

    testWidgets('17, 18, 19. fee month vs payment date; partial payments; payment methods; the timeline in date order', (tester) async {
      await openAnu(tester);
      expect(textOf(tester, key('student-history-assigned-on-a-jan')), '1 Dec 2026');
      final jan1 = key('collection-payment-${receipts['jan1']}');
      expect(find.descendant(of: jan1, matching: text('5 Feb 2027')), findsOneWidget);
      for (final (r, method) in [('jan1', 'Cash'), ('jan2', 'UPI'), ('jan3', 'Bank Transfer'), ('feb', 'Cheque')]) {
        expect(find.descendant(of: key('collection-payment-${receipts[r]}'), matching: text(method)), findsOneWidget, reason: r);
      }
      expect(find.descendant(of: jan1, matching: text('First part')), findsOneWidget);

      final events = <(String, String, String)>[];
      for (var i = 0; key('student-history-event-$i').evaluate().isNotEmpty; i++) {
        events.add((textOf(tester, key('student-history-event-date-$i')), textOf(tester, key('student-history-event-title-$i')), textOf(tester, key('student-history-event-details-$i'))));
      }
      expect([for (final e in events) (e.$1, e.$2)], [
        ('10 Jun 2026', 'Fee assigned'),
        ('1 Jul 2026', 'Partial payment'),
        ('1 Dec 2026', 'Fee assigned'),
        ('1 Jan 2027', 'Fee assigned'),
        ('3 Feb 2027', 'Payment (paid in full)'),
        ('5 Feb 2027', 'Partial payment'),
        ('10 Feb 2027', 'Payment, later voided'),
        ('20 Feb 2027', 'Partial payment'),
        ('25 Feb 2027', 'Payment voided'),
      ]);
      expect(events[5].$3, startsWith('Day Care • Fee month: January 2027 • ₹1,000 • Cash'));
      expect(events[8].$1, isNot('Date not recorded'), reason: 'the void’s own recorded date');
    });

    testWidgets('22. View Receipt opens the existing receipt view for that payment', (tester) async {
      await openAnu(tester);
      await tap(tester, key('collection-receipt-${receipts['jan3']}'));
      final view = tester.widget<FeeReceiptViewDialog>(find.byType(FeeReceiptViewDialog));
      expect([view.receipt.id, view.receipt.assignmentId, view.receipt.feeMonth, view.voided], [receipts['jan3'], 'a-jan', '2027-01', false]);
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();
      await tap(tester, key('collection-receipt-${receipts['jan2']}'));
      expect(key('fee-receipt-voided'), findsOneWidget);
    });

    testWidgets('23. a legacy Monthly assignment: "Month not recorded", no assigned date', (tester) async {
      await pumpFees(tester, 'Students');
      await tap(tester, key('student-view-history-s2'));
      expect(textOf(tester, key('student-history-month-a-legacy')), 'Month not recorded');
      expect(textOf(tester, key('student-history-assigned-on-a-legacy')), 'Date not recorded');
      expect(textOf(tester, key('student-history-assigned')), '₹23,000');
    });

    testWidgets('24. missing dates and an unlinked receipt: listed apart, never counted, never dated by guess', (tester) async {
      await openAnu(tester);
      expect(key('student-history-unlinked'), findsOneWidget);
      expect(find.text('Choose All Academic Years to list them.'), findsOneWidget);
      expect(key('collection-payment-${receipts['old']}'), findsNothing);
      await tap(tester, key('student-history-close'));
      await chooseYear(tester, 'All Academic Years');
      await tap(tester, key('student-view-history-s1'));
      final old = key('collection-payment-${receipts['old']}');
      expect(old, findsOneWidget);
      expect(find.descendant(of: old, matching: text('Date not recorded')), findsOneWidget, reason: 'no payment date; its createdAt is not used');
      expect(textOf(tester, key('student-history-collected')), '₹10,500', reason: 'not counted');
      // Bala: the undated legacy assignment comes last in the timeline.
      await tap(tester, key('student-history-close'));
      await tap(tester, key('student-view-history-s2'));
      var last = 0;
      while (key('student-history-event-${last + 1}').evaluate().isNotEmpty) {
        last++;
      }
      expect(textOf(tester, key('student-history-event-date-$last')), 'Date not recorded');
    });

    testWidgets('26. a long history pages: 10 assignments and 20 events at a time', (tester) async {
      for (var i = 0; i < 25; i++) {
        await assign('big$i', 's3', 'Chitra', 'ADM-3', 'c1', 'Mont 1', 'term1', 'Term Fees', yearId: year, assignedAt: DateTime(2026, 6, 1 + i), total: 100);
      }
      await pumpFees(tester, 'Students');
      await tap(tester, key('student-view-history-s3'));
      int cards() => find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('student-history-assignment-big')).evaluate().length;
      expect(cards(), 10);
      await tap(tester, key('student-history-assignments-more'));
      expect(cards(), 20);
      await tap(tester, key('student-history-assignments-more'));
      expect(cards(), 25);
      expect(key('student-history-assignments-more'), findsNothing);
      expect(key('student-history-event-19'), findsOneWidget);
      expect(key('student-history-event-20'), findsNothing);
      await tap(tester, key('student-history-timeline-more'));
      expect(key('student-history-event-24'), findsOneWidget);
    });

    testWidgets('no writes: opening the Students tab, a history and a receipt changes nothing', (tester) async {
      await pumpFees(tester, 'Students');
      final before = firestore.dump();
      await tap(tester, key('student-view-history-s1'));
      await tap(tester, key('collection-receipt-${receipts['jan1']}'));
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();
      await tap(tester, key('student-history-close'));
      expect(firestore.dump(), before);
    });

    for (final size in const [Size(1400, 1200), Size(360, 900)]) {
      testWidgets('${size.width.toInt()}px: the history fits', (tester) async {
        await pumpFees(tester, 'Students', size: size);
        await tap(tester, key('student-view-history-s1'));
        expect(tester.takeException(), isNull);
        for (final k in ['student-history-summary', 'student-history-assignment-a-jan', 'student-history-timeline']) {
          await tester.ensureVisible(key(k));
          await tester.pumpAndSettle();
          expect(tester.getRect(key(k)).right, lessThanOrEqualTo(size.width), reason: k);
        }
        if (size.width >= 800) expect(tester.getRect(key('student-history-summary')).width, lessThanOrEqualTo(760));
      });
    }
  });

  group('history rules', () {
    StudentFeeAssignmentModel a(String id, {double payable = 1000, double paid = 0}) => StudentFeeAssignmentModel.fromMap(id, {
          'studentId': 's', 'totalFee': payable, 'payableAmount': payable, 'paidAmount': paid, 'balanceAmount': payable - paid, 'assignedAt': DateTime(2026, 6, 1),
        });
    FeeCollectionRecord r(String id, String assignmentId, double amount, {bool voided = false}) => FeeCollectionRecord(
          receipt: FeeReceiptModel.fromMap(id, {'assignmentId': assignmentId, 'amount': amount, 'paymentDate': DateTime(2026, 7, 1)}),
          isVoided: voided,
        );

    test('25. a payment is counted once, against its own assignment; voided ones never', () {
      final h = StudentFeeHistory.of(
        [a('x', paid: 600)],
        [r('p1', 'x', 400), r('p1', 'x', 400), r('p2', 'x', 200), r('p3', 'x', 300, voided: true), r('p4', 'other', 999)],
        unlinked: [r('p1', 'x', 400), r('u1', '', 50)],
      );
      expect(h.paymentsByAssignment['x']!.map((p) => p.receipt.id), ['p1', 'p2', 'p3']);
      expect(h.completedPaymentsTotal, 600);
      expect(h.totalCollected, 600);
      expect(h.paymentsMatchCollected, isTrue);
      expect(h.unlinked.map((p) => p.receipt.id), ['u1']);
      expect([for (final e in h.timeline) e.kind], [
        FeeTimelineKind.assigned, FeeTimelineKind.partialPayment, FeeTimelineKind.partialPayment, FeeTimelineKind.cancelledPayment,
        FeeTimelineKind.voided, // no void date recorded: last
      ]);
      expect(h.timeline.last.date, isNull);
    });

    test('a recorded paid amount the receipts don’t explain is flagged, not recalculated', () {
      final h = StudentFeeHistory.of([a('x', paid: 700)], [r('p1', 'x', 400)]);
      expect([h.totalCollected, h.completedPaymentsTotal, h.paymentsMatchCollected], [700, 400, false]);
    });
  });

  group('regression', () {
    testWidgets('27, 30. Collect and Void work with filters on; one Finance entry per collection, cancelled once', (tester) async {
      final term = receipts['term']!;
      await tester.runAsync(() => fees.voidReceipt(term));
      final ledger = (await tester.runAsync(() => firestore.collection('finance_ledger').get()))!.docs;
      expect(ledger.length, 7, reason: 'one per collection (OLD-1 was never collected)');
      expect(ledger.where((d) => d.data()['status'] == 'cancelled').length, 2);
      await pumpFees(tester, 'Collections');
      await chooseClass(tester, 'Mont 1');
      final row = find.ancestor(of: key('collection-view-details-a-term'), matching: find.byType(Row)).first;
      await tap(tester, find.descendant(of: row, matching: find.widgetWithText(TextButton, 'Collect')));
      expect(key('fee-collection-for'), findsOneWidget);
    });
  });

  group('overview cards', () {
    List<String> cards(WidgetTester tester) => [
          for (final k in ['expected', 'collected', 'outstanding', 'percent', 'overdue', 'today'])
            tester.widget<Text>(find.descendant(of: key('fees-overview-$k'), matching: find.byType(Text)).at(1)).data!,
        ];
    String scope(WidgetTester tester) => tester.widget<Text>(key('fees-overview-scope')).data!;
    String todaySubtitle(WidgetTester tester) => tester.widget<Text>(find.descendant(of: key('fees-overview-today'), matching: find.byType(Text)).at(2)).data!;

    test('with no filter the figures are exactly getDashboardSummary’s', () async {
      await collect('a-bala', 700, DateTime.now(), 'cash');
      await firestore.collection('student_fee_assignments').doc('a-legacy').update({'dueDate': DateTime(2026, 7, 1)});
      final summary = await fees.getDashboardSummary();
      final o = FeeOverview.of(assignments: await fees.getAssignments(), receipts: await fees.getReceipts(), filter: const FeeListFilter(), today: DateTime.now());
      expect([o.totalExpected, o.totalCollected, o.outstanding, o.collectionPercent, o.overdue, o.todayCollection],
          [summary['totalExpected'], summary['totalCollected'], summary['outstanding'], summary['collectionPercent'], summary['overdueStudents'], summary['todayCollection']]);
    });

    testWidgets('the current year by default; year, class, student and combinations; Reset restores the default', (tester) async {
      // Bala's term fee is past due (an outstanding balance and a due date
      // before today); Overdue Students counts Bala.
      await tester.runAsync(() => firestore.collection('student_fee_assignments').doc('a-bala').update({'dueDate': DateTime(2026, 7, 1)}));
      await pumpFees(tester, 'Assignments', clock: () => DateTime(2026, 11, 6));
      expect(scope(tester), 'Fee assignments: 2026-2027 • All classes • All students • All months');
      // 18000+3000+3000+20000+3000 expected; 5000+2500+3000+2000 collected.
      expect(cards(tester).take(5), ['₹47,000', '₹12,500', '₹34,500', '26.6%', '1']);
      await chooseYear(tester, '2025-2026');
      expect(cards(tester).take(5), ['₹15,000', '₹15,000', '₹0', '100.0%', '0']);
      await chooseYear(tester, 'All Academic Years');
      expect(cards(tester).take(4), ['₹62,000', '₹27,500', '₹34,500', '44.4%']);
      await chooseClass(tester, 'Mont 1');
      expect(cards(tester).take(4), ['₹39,000', '₹25,500', '₹13,500', '65.4%'], reason: 'Dev’s Mont 1 assignment from last year counts under Mont 1');
      await chooseYear(tester, '2026-2027 (current)');
      expect(cards(tester).take(5), ['₹24,000', '₹10,500', '₹13,500', '43.8%', '0']);
      await chooseClass(tester, 'All Classes');
      await chooseStudent(tester, 's2');
      expect(scope(tester), 'Fee assignments: 2026-2027 • All classes • Bala (ADM-2) • All months');
      expect(cards(tester).take(5), ['₹23,000', '₹2,000', '₹21,000', '8.7%', '1']);
      await tap(tester, key('fees-filter-reset'));
      expect(scope(tester), 'Fee assignments: 2026-2027 • All classes • All students • All months');
      expect(cards(tester).take(5), ['₹47,000', '₹12,500', '₹34,500', '26.6%', '1']);
    });

    testWidgets('Today’s Collection is by payment date (any academic year), with class and student through the linked assignment', (tester) async {
      await tester.runAsync(() async {
        await collect('a-bala', 700, DateTime(2027, 2, 5), 'upi');
        await firestore.collection('fee_receipts').add({'receiptNo': 'OLD-2', 'studentId': 's1', 'studentName': 'Anu', 'amount': 50, 'paymentMode': 'cash', 'paymentDate': DateTime(2027, 2, 5)});
      });
      await pumpFees(tester, 'Receipts', clock: () => DateTime(2027, 2, 5, 15));
      expect(cards(tester)[5], '₹1,750', reason: 'Anu ₹1000 (January’s fee) + Bala ₹700 + unlinked ₹50');
      expect(todaySubtitle(tester), 'Feb 5, 2027 • any academic year');
      await chooseYear(tester, '2025-2026');
      expect(cards(tester)[5], '₹1,750', reason: 'not an academic-year figure');
      await chooseClass(tester, 'Mont 1');
      expect(cards(tester)[5], '₹1,000', reason: 'the unlinked receipt has no class');
      await chooseClass(tester, 'All Classes');
      await chooseStudent(tester, 's1');
      expect(cards(tester)[5], '₹1,050', reason: 'the unlinked receipt’s own student id');
      await chooseStudent(tester, 's2');
      expect(cards(tester)[5], '₹700');
    });

    testWidgets('a voided payment dated today isn’t in Today’s Collection', (tester) async {
      await pumpFees(tester, 'Receipts', clock: () => DateTime(2027, 2, 10));
      expect(cards(tester)[5], '₹0', reason: 'the ₹500 UPI payment of 10 Feb was voided');
    });

    test('Collection % uses one set of assignments for both parts', () async {
      final all = await fees.getAssignments();
      for (final filter in [const FeeListFilter(), FeeListFilter(classId: 'c1'), const FeeListFilter(studentId: 's2')]) {
        final o = FeeOverview.of(assignments: all, receipts: const [], filter: filter, today: DateTime(2027));
        final shown = all.where(filter.matchesAssignment);
        expect(o.totalCollected, shown.fold<double>(0, (s, a) => s + a.paidAmount));
        expect(o.totalExpected, shown.fold<double>(0, (s, a) => s + a.payableAmount));
        expect(o.collectionPercent, closeTo(o.totalCollected / o.totalExpected * 100, 1e-9));
      }
    });

    testWidgets('the scope note says which class each tab uses', (tester) async {
      await pumpFees(tester, 'Dues');
      expect(tester.widget<Text>(key('fees-filter-scope')).data, contains('class recorded on each fee assignment'));
      await tab(tester, 'Students');
      expect(tester.widget<Text>(key('fees-filter-scope')).data, contains('each student’s current class'));
      await tab(tester, 'Structures');
      expect(tester.widget<Text>(key('fees-filter-scope')).data, contains('Fee structures are not filtered'));
    });
  });

  group('layout and empty states', () {
    testWidgets('no students yet: the Students tab says so', (tester) async {
      await tester.runAsync(() async {
        for (final d in (await firestore.collection('students').get()).docs) {
          await d.reference.delete();
        }
      });
      await pumpFees(tester, 'Students');
      expect(key('fees-students-empty'), findsOneWidget);
    });

    for (final size in const [Size(1400, 1000), Size(800, 1200), Size(360, 800)]) {
      testWidgets('${size.width.toInt()}px: long names and admission numbers fit every tab, the picker and the history', (tester) async {
        const long = 'Anantharamakrishnan Venkatasubramanian Raghavendra Iyer';
        await tester.runAsync(() async {
          await firestore.collection('students').doc('s1').update({'name': long, 'admissionNo': 'ADM-2026-LONG-0000000001'});
          await firestore.collection('student_fee_assignments').doc('a-jan').update({'studentName': long, 'admissionNo': 'ADM-2026-LONG-0000000001'});
        });
        await pumpFees(tester, 'Assignments', size: size);
        for (final t in ['Assignments', 'Collections', 'Receipts', 'Dues', 'Students']) {
          await tab(tester, t);
          expect(tester.takeException(), isNull, reason: t);
          final search = key('fees-${t.toLowerCase()}-search');
          expect(tester.getRect(search).top, greaterThanOrEqualTo(tester.getRect(key('fees-filters')).bottom), reason: '$t: search below the filters');
        }
        await chooseStudent(tester, 's1');
        expect(tester.takeException(), isNull);
        await tap(tester, key('student-view-history-s1'));
        expect(tester.takeException(), isNull);
        for (final k in ['student-history-student', 'collection-payment-${receipts['jan1']}', 'student-history-timeline']) {
          await tester.ensureVisible(key(k));
          await tester.pumpAndSettle();
          expect(tester.getRect(key(k)).right, lessThanOrEqualTo(size.width), reason: k);
        }
        await tap(tester, key('student-history-close'));
        if (size.width < 800) {
          expect(find.byTooltip('View Fee History'), findsOneWidget, reason: 'the icon-only action is named');
        }
        // The last row scrolls clear of the Add button.
        final row = key('student-view-history-s1');
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
        await tester.pumpAndSettle();
        expect(tester.getRect(row).overlaps(tester.getRect(find.byType(FloatingActionButton))), isFalse);
      });
    }
  });
}

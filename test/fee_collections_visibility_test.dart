// Fees -> Collections lists every fee assignment (paid, partly paid and
// unpaid), with a status and Collect only while a balance is due; Term,
// One-time and mixed-frequency fees (no fee month) are never hidden by a
// Fee Month and appear in their own "Term and One-time Fees" section on
// every tab. Receipts still list payments, Dues only balances due.
// Synthetic test data only.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/settings/providers/academic_year_provider.dart';
import 'package:montessori_app/modules/fees/models/fee_component_model.dart';
import 'package:montessori_app/modules/fees/models/fee_list_filter.dart';
import 'package:montessori_app/modules/fees/models/fee_overview.dart';
import 'package:montessori_app/modules/fees/models/student_fee_assignment_model.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/admin_fees_screen.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_collection_details_dialog.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_collection_dialog.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';

import 'support/buffered_transaction_firestore.dart';

void main() {
  late BufferedTransactionFirestore firestore;
  late FeeService fees;
  late String year;
  late Map<String, String> ids;

  Future<String> assign(String student, String name, String structure, String structureName, double total, {String? month}) async =>
      (await fees.assignFee({
        'studentId': student, 'studentName': name, 'admissionNo': 'ADM-$student', 'classId': 'c1', 'className': 'Mont 1',
        'feeStructureId': structure, 'feeStructureName': structureName, 'academicYearId': year, 'academicYear': '2026-2027',
        'totalFee': total, 'discountAmount': 0, 'payableAmount': total, 'paidAmount': 0, 'balanceAmount': total, 'status': 'unpaid',
        'feeMonth': ?month, 'dueDate': DateTime(2026, 6, 10),
      }))!;

  Future<String> collect(String id, double amount) async =>
      (await fees.collectFee(assignmentId: id, amount: amount, paymentDate: DateTime(2026, 6, 8), paymentMode: 'cash', referenceNo: '', remarks: '')).id;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    final auth = MockFirebaseAuth();
    final finance = FinanceService(firestore: firestore, auth: auth);
    await finance.ensureDefaults();
    fees = FeeService(firestore: firestore, auth: auth, storage: MockFirebaseStorage(), financeService: finance);
    year = await AcademicYearService(firestore: firestore).createAcademicYear(schoolId: kDefaultSchoolId, requesterRole: 'admin', name: '2026-2027',
        startDate: DateTime(2026, 6, 1), endDate: DateTime(2027, 5, 31), createdBy: 'admin-1', setAsCurrent: true);
    await firestore.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
    for (final (id, name) in [('s1', 'Anu'), ('s2', 'Bala'), ('s3', 'Chitra'), ('s4', 'Dev')]) {
      await firestore.collection('students').doc(id).set({'name': name, 'admissionNo': 'ADM-$id', 'classId': 'c1', 'isActive': true});
    }
    Future<void> structure(String id, String name, List<(String, double)> parts) => firestore.collection('fee_structures').doc(id).set({
          'name': name, 'description': '', 'totalAmount': parts.fold<double>(0, (s, p) => s + p.$2), 'academicYear': '2026-2027', 'academicYearId': year,
          'isActive': true, 'createdBy': 't', 'createdAt': DateTime(2026, 1, 1),
          'components': [for (final (freq, amount) in parts) FeeComponentModel(name: '$name $freq', amount: amount, frequency: freq, termName: freq == 'term' ? 'Term 1' : null, isOptional: false).toMap()],
        });
    await structure('care', 'Day Care', [('monthly', 3000)]);
    await structure('term', 'Term Fees', [('term', 8000)]);
    await structure('once', 'Admission Kit', [('oneTime', 1500)]);
    await structure('mixed', 'Care Plus Kit', [('monthly', 1000), ('oneTime', 600)]);

    // June: Anu paid in full, Bala part paid, Chitra unpaid. July: Anu.
    // Dev: Term (unpaid), One-time (paid), mixed (unpaid).
    ids = {
      'anu-jun': await assign('s1', 'Anu', 'care', 'Day Care', 3000, month: '2026-06'),
      'bala-jun': await assign('s2', 'Bala', 'care', 'Day Care', 3000, month: '2026-06'),
      'chitra-jun': await assign('s3', 'Chitra', 'care', 'Day Care', 3000, month: '2026-06'),
      'anu-jul': await assign('s1', 'Anu', 'care', 'Day Care', 3000, month: '2026-07'),
      'dev-term': await assign('s4', 'Dev', 'term', 'Term Fees', 8000),
      'dev-once': await assign('s4', 'Dev', 'once', 'Admission Kit', 1500),
      'dev-mixed': await assign('s4', 'Dev', 'mixed', 'Care Plus Kit', 1600),
    };
    ids['r-anu'] = await collect(ids['anu-jun']!, 3000);
    ids['r-bala'] = await collect(ids['bala-jun']!, 1000);
    ids['r-once'] = await collect(ids['dev-once']!, 1500);
  });

  Finder key(String k) => find.byKey(Key(k));

  Future<void> pumpFees(WidgetTester tester, {String? tab, Size size = const Size(1400, 3200)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore))],
      child: MaterialApp(home: AdminFeesScreen(service: fees, clock: () => DateTime(2026, 6, 20))),
    ));
    await tester.pumpAndSettle();
    if (tab != null) await tester.tap(find.widgetWithText(ChoiceChip, tab));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> chooseMonth(WidgetTester tester, String label) async {
    await tap(tester, key('fees-filter-month'));
    await tap(tester, find.text(label).last);
  }

  String status(WidgetTester tester, String id) => tester.widget<Text>(find.descendant(of: key('fees-status-$id'), matching: find.byType(Text))).data!;
  bool listed(String id) => key('collection-view-details-$id').evaluate().isNotEmpty;
  bool canCollect(String id) => key('collection-collect-$id').evaluate().isNotEmpty;
  List<String> headings(WidgetTester tester, String list) {
    final found = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('fees-$list-section-') && !(w.key! as ValueKey<String>).value.contains('-empty-'));
    final els = found.evaluate().toList()..sort((a, b) => tester.getTopLeft(find.byWidget(a.widget)).dy.compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy));
    return [for (final e in els) tester.widget<Text>(find.descendant(of: find.byWidget(e.widget), matching: find.byType(Text))).data!];
  }

  group('Collections', () {
    testWidgets('1–3, 5–7, 10. June: paid, part-paid and unpaid June fees with their status; Term, One-time and mixed fees in their own section; never July', (tester) async {
      await pumpFees(tester);
      await chooseMonth(tester, 'June 2026');
      expect(headings(tester, 'collections'), ['June 2026 – Selected Month', 'Term and One-time Fees']);
      expect([for (final id in ['anu-jun', 'bala-jun', 'chitra-jun']) status(tester, ids[id]!)], ['Paid', 'Partially Paid', 'Unpaid']);
      expect(listed(ids['anu-jun']!), isTrue, reason: 'fully paid, still listed');
      expect(canCollect(ids['anu-jun']!), isFalse, reason: 'nothing left to collect');
      expect(canCollect(ids['bala-jun']!), isTrue);
      expect(canCollect(ids['chitra-jun']!), isTrue);
      for (final id in ['dev-term', 'dev-once', 'dev-mixed']) {
        expect(listed(ids[id]!), isTrue, reason: id);
      }
      expect(status(tester, ids['dev-once']!), 'Paid');
      expect(canCollect(ids['dev-term']!), isTrue);
      expect(listed(ids['anu-jul']!), isFalse, reason: 'a June filter never shows July');
      expect(find.text('Overdue'), findsNWidgets(4), reason: 'due 10 June with a balance: Bala, Chitra, and Dev’s Term and mixed fees');
    });

    testWidgets('a paid row opens View Details with its payment', (tester) async {
      await pumpFees(tester);
      await tap(tester, key('collection-view-details-${ids['anu-jun']}'));
      expect(find.byType(FeeCollectionDetailsDialog), findsOneWidget);
      expect(key('collection-payment-${ids['r-anu']}'), findsOneWidget);
    });

    testWidgets('4, 8, 9, 16. Collect opens the exact assignment (part-paid June, Term, One-time), saves once, and Finance gets one entry each', (tester) async {
      await pumpFees(tester);
      await chooseMonth(tester, 'June 2026');
      for (final (id, amount) in [('bala-jun', '2000'), ('dev-term', '3000'), ('dev-mixed', '1600')]) {
        await tap(tester, key('collection-collect-${ids[id]}'));
        final dialog = tester.widget<FeeCollectionDialog>(find.byType(FeeCollectionDialog));
        expect(dialog.assignment.id, ids[id], reason: 'the exact assignment, not another student’s');
        await tester.enterText(find.widgetWithText(TextField, 'Amount'), amount);
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        // The save (and its receipt PDF) runs in real async time.
        for (var i = 0; i < 100 && find.byType(FeeCollectionDialog).evaluate().isNotEmpty; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
          await tester.pump();
        }
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(find.byType(FeeCollectionDialog), findsNothing, reason: id);
      }
      expect(status(tester, ids['bala-jun']!), 'Paid');
      expect(canCollect(ids['bala-jun']!), isFalse);
      expect(status(tester, ids['dev-term']!), 'Partially Paid');
      expect(status(tester, ids['dev-mixed']!), 'Paid');
      final ledger = (await tester.runAsync(() => firestore.collection('finance_ledger').get()))!.docs;
      expect(ledger.length, 6, reason: 'three earlier collections and three here, one entry each');
      final receipts = (await tester.runAsync(() => firestore.collection('fee_receipts').get()))!.docs;
      expect(receipts.length, 6);
    });

    testWidgets('11. All Months: the current month first, months in order, Term and One-time Fees after', (tester) async {
      await pumpFees(tester);
      expect(headings(tester, 'collections'), ['June 2026 – Current Month', 'July 2026', 'Term and One-time Fees']);
    });

    testWidgets('17. voiding a payment brings the balance back: status and Collect follow, and Dues lists it again', (tester) async {
      await tester.runAsync(() => fees.voidReceipt(ids['r-anu']!));
      await pumpFees(tester);
      expect(status(tester, ids['anu-jun']!), 'Unpaid');
      expect(canCollect(ids['anu-jun']!), isTrue);
      await tap(tester, key('collection-view-details-${ids['anu-jun']}'));
      expect(find.text('Cancelled (voided)'), findsOneWidget);
      await tap(tester, key('collection-details-close'));
      await tap(tester, find.widgetWithText(ChoiceChip, 'Dues'));
      expect(find.text('Due: 3000 • June 2026'), findsNWidgets(2), reason: 'Anu and Chitra');
    });
  });

  group('other tabs', () {
    testWidgets('12. Receipts list payments only (June, and Term/One-time under June); 13. Dues only balances due; 14. Assignments everything for the month', (tester) async {
      await pumpFees(tester, tab: 'Receipts');
      await chooseMonth(tester, 'June 2026');
      expect(find.textContaining('Day Care • June 2026 • 3000'), findsOneWidget, reason: 'Anu’s payment');
      expect(find.textContaining('Day Care • June 2026 • 1000'), findsOneWidget, reason: 'Bala’s payment');
      expect(find.textContaining('Admission Kit • 1500'), findsOneWidget);
      expect(find.textContaining('Chitra'), findsNothing, reason: 'no payment, no receipt');
      expect(headings(tester, 'receipts'), ['June 2026 – Selected Month', 'Term and One-time Fees']);

      await tap(tester, find.widgetWithText(ChoiceChip, 'Dues'));
      expect(find.text('Due: 2000 • June 2026'), findsOneWidget);
      expect(find.text('Due: 3000 • June 2026'), findsOneWidget);
      expect(find.text('Anu'), findsNothing, reason: 'paid in full: not due');
      expect(find.text('Due: 8000'), findsOneWidget, reason: 'Term');
      expect(find.text('Due: 1600'), findsOneWidget, reason: 'mixed');
      expect(find.textContaining('Due: 1500'), findsNothing, reason: 'One-time paid');

      await tap(tester, find.widgetWithText(ChoiceChip, 'Assignments'));
      for (final t in ['Mont 1 • Day Care • June 2026', 'Mont 1 • Term Fees', 'Mont 1 • Admission Kit', 'Mont 1 • Care Plus Kit']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      expect(find.text('Mont 1 • Day Care • June 2026'), findsNWidgets(3));
      expect(find.text('Mont 1 • Day Care • July 2026'), findsNothing);
      expect(headings(tester, 'assignments'), ['June 2026 – Selected Month', 'Term and One-time Fees']);
    });

    testWidgets('15. the overview and the list cover the same assignments, counted once', (tester) async {
      await pumpFees(tester);
      String card(String k) => tester.widget<Text>(find.descendant(of: key('fees-overview-$k'), matching: find.byType(Text)).at(1)).data!;
      await chooseMonth(tester, 'June 2026');
      // June 3 × ₹3,000 + Term ₹8,000 + One-time ₹1,500 + mixed ₹1,600.
      expect([card('expected'), card('collected'), card('outstanding')], ['₹20,100', '₹5,500', '₹14,600']);
      final shown = [for (final id in ids.entries) if (id.key.contains('-') && !id.key.startsWith('r-') && listed(id.value)) id.key];
      expect(shown.toSet(), {'anu-jun', 'bala-jun', 'chitra-jun', 'dev-term', 'dev-once', 'dev-mixed'});
      final all = (await tester.runAsync(fees.getAssignments))!;
      final o = FeeOverview.of(assignments: all, receipts: const [], filter: FeeListFilter(feeMonth: '2026-06', monthlyStructureIds: const {'care'}), today: DateTime(2026, 6, 20));
      expect([o.totalExpected, o.totalCollected, o.outstanding], [20100, 5500, 14600]);
      expect(o.totalCollected + o.outstanding, o.totalExpected);
    });
  });

  group('filter rule', () {
    StudentFeeAssignmentModel a(String structure, {String month = ''}) =>
        StudentFeeAssignmentModel.fromMap(structure, {'feeStructureId': structure, 'feeMonth': month});

    test('a month keeps its own monthly fees and every non-monthly fee; never another month or a monthly fee with no month', () {
      const f = FeeListFilter(feeMonth: '2026-06', monthlyStructureIds: {'care'});
      expect(f.matchesAssignment(a('care', month: '2026-06')), isTrue);
      expect(f.matchesAssignment(a('care', month: '2026-07')), isFalse);
      expect(f.matchesAssignment(a('care')), isFalse, reason: 'Month not recorded: All Months only');
      expect(f.matchesAssignment(a('term')), isTrue);
      expect(f.matchesAssignment(a('mixed')), isTrue);
      expect(const FeeListFilter(monthlyStructureIds: {'care'}).matchesAssignment(a('care')), isTrue, reason: 'All Months');
    });
  });
}

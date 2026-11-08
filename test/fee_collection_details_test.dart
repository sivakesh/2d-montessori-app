// Fees -> Collections -> View Details: a read-only view of one fee
// assignment and every payment recorded against it (its fee receipts,
// matched by `assignmentId`; voided ones shown and marked), with each
// receipt opening in the existing receipt view. Opening and closing it
// writes nothing. Synthetic test data only.
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/settings/providers/academic_year_provider.dart';
import 'package:montessori_app/modules/fees/models/fee_component_model.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/admin_fees_screen.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_collection_details_dialog.dart';
import 'package:montessori_app/modules/fees/ui/dialogs/fee_receipt_view_dialog.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';

import 'support/buffered_transaction_firestore.dart';

void main() {
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
    Future<void> structure(String id, String name, double amount, String freq) => firestore.collection('fee_structures').doc(id).set({
          'name': name, 'description': '', 'totalAmount': amount, 'academicYear': '2026-2027', 'academicYearId': yearId, 'isActive': true, 'createdBy': 't',
          'components': [FeeComponentModel(name: name, amount: amount, frequency: freq, isOptional: false).toMap()],
        });
    await structure('daycare', 'Day Care', 3000, 'monthly');
    await structure('term1', 'Term Fees', 20000, 'term');
  });

  Map<String, dynamic> assignment(String structureId, {String? feeMonth, String name = 'Day Care', double total = 3000, double discount = 0}) => {
        'studentId': 's1', 'studentName': 'Anu', 'admissionNo': 'ADM-1', 'classId': 'class-1', 'className': 'Mont 1',
        'feeStructureId': structureId, 'feeStructureName': name, 'academicYearId': yearId, 'academicYear': '2026-2027',
        'totalFee': total, 'discountAmount': discount, 'payableAmount': total - discount, 'paidAmount': 0, 'balanceAmount': total - discount, 'status': 'unpaid',
        'feeMonth': ?feeMonth,
        'dueDate': DateTime(2027, 1, 10),
      };

  Future<String> collect(String id, double amount, DateTime date, String mode, {String ref = '', String notes = ''}) async =>
      (await fees.collectFee(assignmentId: id, amount: amount, paymentDate: date, paymentMode: mode, referenceNo: ref, remarks: notes)).id;

  /// January: ₹500 cash (notes), ₹1000 UPI (voided), ₹700 by bank transfer
  /// (reference); February: ₹3000 cheque. Term (discount ₹2000): ₹5000.
  Future<Map<String, String>> seed() async {
    final jan = (await fees.assignFee(assignment('daycare', feeMonth: '2027-01')))!;
    final feb = (await fees.assignFee(assignment('daycare', feeMonth: '2027-02')))!;
    final term = (await fees.assignFee(assignment('term1', name: 'Term Fees', total: 20000, discount: 2000)))!;
    final r1 = await collect(jan, 500, DateTime(2027, 1, 3), 'cash', notes: 'First instalment');
    final r2 = await collect(jan, 1000, DateTime(2027, 1, 10), 'upi', ref: 'UPI-77');
    final r3 = await collect(jan, 700, DateTime(2027, 1, 20), 'bank_transfer', ref: 'NEFT-9');
    await fees.voidReceipt(r2);
    final r4 = await collect(feb, 3000, DateTime(2027, 2, 2), 'cheque', ref: 'CHQ-1');
    final r5 = await collect(term, 5000, DateTime(2026, 7, 1), 'cash');
    return {'jan': jan, 'feb': feb, 'term': term, 'r1': r1, 'r2': r2, 'r3': r3, 'r4': r4, 'r5': r5};
  }

  group('service', () {
    test('history: that assignment’s payments only, oldest first, voided marked, notes from the transaction; reads only', () async {
      final ids = await seed();
      final before = firestore.dump();
      final jan = await fees.getCollectionHistory(ids['jan']!);
      expect([for (final r in jan) r.receipt.id], [ids['r1'], ids['r2'], ids['r3']]);
      expect([for (final r in jan) r.isVoided], [false, true, false]);
      expect(jan[1].voidedAt, isNotNull);
      expect([for (final r in jan) r.remarks], ['First instalment', '', '']);
      expect([for (final r in jan) r.receipt.feeMonth], everyElement('2027-01'));
      final feb = await fees.getCollectionHistory(ids['feb']!);
      expect([for (final r in feb) r.receipt.id], [ids['r4']], reason: 'January’s payments never appear under February');
      expect(await fees.getCollectionHistory(''), isEmpty);
      expect(firestore.dump(), before);
    });

    test('a receipt with no assignmentId (older data) is never guessed into a history', () async {
      final ids = await seed();
      await firestore.collection('fee_receipts').add({'receiptNo': 'OLD-1', 'studentId': 's1', 'studentName': 'Anu', 'feeStructureName': 'Day Care', 'amount': 99, 'paymentMode': 'cash'});
      expect([for (final r in await fees.getCollectionHistory(ids['jan']!)) r.receipt.receiptNo], isNot(contains('OLD-1')));
    });
  });

  group('screen', () {
    Future<void> pumpCollections(WidgetTester tester, {Size size = const Size(1400, 2400)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore))],
        child: MaterialApp(home: AdminFeesScreen(service: fees)),
      ));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Collections'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Collections'));
      await tester.pumpAndSettle();
    }

    // The receipt view's Generate / Regenerate PDF button.
    TextButton pdfButton(WidgetTester tester) =>
        tester.widget<TextButton>(find.descendant(of: find.byType(FeeReceiptViewDialog), matching: find.byType(TextButton)).at(1));

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    Finder key(String k) => find.byKey(Key(k));
    String textOf(WidgetTester tester, Finder f) => tester.widget<Text>(find.descendant(of: f, matching: find.byType(Text)).last).data!;
    Finder within(String k, String text) => find.descendant(of: key(k), matching: find.text(text));

    testWidgets('opening details: student and month, the summary, each partial payment with method, reference, notes and status', (tester) async {
      final ids = await seed();
      await pumpCollections(tester);
      expect(key('collection-view-details-${ids['jan']}'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Collect'), findsNWidgets(2), reason: 'Collect is still there (February is paid, so not listed)');
      await tap(tester, key('collection-view-details-${ids['jan']}'));
      expect(find.byType(FeeCollectionDetailsDialog), findsOneWidget);
      for (final t in ['Anu', 'ADM-1', 'Mont 1', 'Day Care', '2026-2027']) {
        expect(within('collection-details-assignment', t), findsOneWidget, reason: t);
      }
      expect(textOf(tester, key('collection-details-month')), 'January 2027');
      expect(
        [for (final k in ['total-fee', 'discount', 'payable', 'paid', 'balance']) textOf(tester, key('collection-details-$k'))],
        ['₹3,000', '₹0', '₹3,000', '₹1,200', '₹1,800'],
      );
      expect(key('collection-details-total-mismatch'), findsNothing);
      expect(tester.widget<Text>(key('collection-details-receipts-total')).data, '3 payments: 2 completed, totalling ₹1,200; 1 cancelled, not counted.');

      final p1 = 'collection-payment-${ids['r1']}', p2 = 'collection-payment-${ids['r2']}', p3 = 'collection-payment-${ids['r3']}';
      for (final (p, amount, method, date) in [(p1, '₹500', 'Cash', '3 Jan 2027'), (p2, '₹1,000', 'UPI', '10 Jan 2027'), (p3, '₹700', 'Bank Transfer', '20 Jan 2027')]) {
        expect(within(p, amount), findsOneWidget, reason: p);
        expect(within(p, method), findsOneWidget, reason: p);
        expect(within(p, date), findsOneWidget, reason: p);
      }
      expect(within(p1, 'First instalment'), findsOneWidget);
      expect(within(p2, 'UPI-77'), findsOneWidget);
      expect(within(p3, 'NEFT-9'), findsOneWidget);
      expect(within(p1, 'Notes'), findsOneWidget);
      expect(within(p3, 'Notes'), findsNothing, reason: 'no notes, no row');
      expect(textOf(tester, key('collection-payment-status-${ids['r1']}')), 'Completed');
      expect(textOf(tester, key('collection-payment-status-${ids['r2']}')), 'Cancelled (voided)');
      expect(tester.widget<Text>(key('collection-payment-amount-${ids['r2']}')).style!.decoration, TextDecoration.lineThrough);
      expect(find.descendant(of: key(p2), matching: find.textContaining('not counted in Total collected')), findsOneWidget);

      await tap(tester, key('collection-details-close'));
      expect(find.byType(FeeCollectionDetailsDialog), findsNothing);
    });

    testWidgets('a discounted Term assignment: original, discount, payable, collected and outstanding; no month row', (tester) async {
      final ids = await seed();
      await pumpCollections(tester);
      await tap(tester, key('collection-view-details-${ids['term']}'));
      expect(
        [for (final k in ['total-fee', 'discount', 'payable', 'paid', 'balance']) textOf(tester, key('collection-details-$k'))],
        ['₹20,000', '₹2,000', '₹18,000', '₹5,000', '₹13,000'],
      );
      expect(key('collection-details-month'), findsNothing);
      expect(key('collection-details-month-legacy'), findsNothing);
    });

    testWidgets('monthly: February shows only February’s payment and its own balance', (tester) async {
      final ids = await seed();
      // February partly paid so it stays in Collections.
      await firestore.collection('student_fee_assignments').doc(ids['feb']).update({'payableAmount': 4000, 'totalFee': 4000, 'balanceAmount': 1000, 'status': 'partial'});
      await pumpCollections(tester);
      await tap(tester, key('collection-view-details-${ids['feb']}'));
      expect(textOf(tester, key('collection-details-month')), 'February 2027');
      expect(key('collection-payment-${ids['r4']}'), findsOneWidget);
      for (final r in ['r1', 'r2', 'r3']) {
        expect(key('collection-payment-${ids[r]}'), findsNothing, reason: r);
      }
      expect(textOf(tester, key('collection-details-balance')), '₹1,000');
    });

    testWidgets('receipt navigation: the existing receipt view, for that payment; a voided one is marked and can’t make a new PDF', (tester) async {
      final ids = await seed();
      await pumpCollections(tester);
      await tap(tester, key('collection-view-details-${ids['jan']}'));
      await tap(tester, key('collection-receipt-${ids['r3']}'));
      final view = tester.widget<FeeReceiptViewDialog>(find.byType(FeeReceiptViewDialog));
      expect([view.receipt.id, view.receipt.assignmentId, view.receipt.studentId, view.receipt.feeMonth], [ids['r3'], ids['jan'], 's1', '2027-01']);
      expect(find.text('January 2027'), findsWidgets);
      expect(find.text('Rs. 700'), findsOneWidget);
      expect(key('fee-receipt-voided'), findsNothing);
      expect(pdfButton(tester).onPressed, isNotNull, reason: 'print/PDF kept');
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();
      expect(find.byType(FeeReceiptViewDialog), findsNothing);
      expect(find.byType(FeeCollectionDetailsDialog), findsOneWidget, reason: 'back on the details');

      await tap(tester, key('collection-receipt-${ids['r2']}'));
      expect(key('fee-receipt-voided'), findsOneWidget);
      expect(pdfButton(tester).onPressed, isNull);
    });

    testWidgets('legacy: a Monthly assignment with no month says "Month not recorded"', (tester) async {
      final legacy = await firestore.collection('student_fee_assignments').add({...assignment('daycare'), 'assignedAt': DateTime(2026, 6, 2)});
      await collect(legacy.id, 1000, DateTime(2026, 6, 5), 'cash');
      await pumpCollections(tester);
      await tap(tester, key('collection-view-details-${legacy.id}'));
      expect(textOf(tester, key('collection-details-month-legacy')), 'Month not recorded');
      expect(find.textContaining('before fee months were recorded'), findsOneWidget);
      expect(textOf(tester, key('collection-details-paid')), '₹1,000');
    });

    testWidgets('a recorded paid amount with no matching receipts is flagged, not recalculated', (tester) async {
      final ref = await firestore.collection('student_fee_assignments').add({
        ...assignment('term1', name: 'Term Fees', total: 20000), 'paidAmount': 4000, 'balanceAmount': 16000, 'status': 'partial', 'assignedAt': DateTime(2026, 6, 2),
      });
      await pumpCollections(tester);
      await tap(tester, key('collection-view-details-${ref.id}'));
      expect(textOf(tester, key('collection-details-paid')), '₹4,000');
      expect(textOf(tester, key('collection-details-balance')), '₹16,000');
      expect(key('collection-details-empty'), findsOneWidget);
      expect(key('collection-details-total-mismatch'), findsOneWidget);
    });

    testWidgets('no writes: opening and closing the details and a receipt changes nothing in Fees or Finance', (tester) async {
      final ids = await seed();
      await pumpCollections(tester);
      // After the screen's own loading reads (the fake Firestore lists a
      // collection it was asked to read, even an empty one).
      final before = firestore.dump();
      await tap(tester, key('collection-view-details-${ids['jan']}'));
      await tap(tester, key('collection-receipt-${ids['r1']}'));
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();
      await tap(tester, key('collection-details-close'));
      expect(firestore.dump(), before);
    });

    testWidgets('Collect still opens the collection dialog for that assignment', (tester) async {
      final ids = await seed();
      await pumpCollections(tester);
      final card = find.ancestor(of: key('collection-view-details-${ids['jan']}'), matching: find.byType(Row)).first;
      await tap(tester, find.descendant(of: card, matching: find.widgetWithText(TextButton, 'Collect')));
      expect(key('fee-collection-for'), findsOneWidget);
      expect(find.textContaining('January 2027'), findsWidgets);
    });

    for (final size in const [Size(1400, 1000), Size(800, 1200), Size(360, 800)]) {
      testWidgets('${size.width.toInt()}px: the entry point and the details fit', (tester) async {
        final ids = await seed();
        await pumpCollections(tester, size: size);
        expect(tester.takeException(), isNull);
        final entry = key('collection-view-details-${ids['jan']}');
        await tester.ensureVisible(entry);
        await tester.pumpAndSettle();
        expect(tester.getRect(entry).right, lessThanOrEqualTo(size.width));
        expect(find.descendant(of: entry, matching: find.text('View Details')), size.width < 800 ? findsNothing : findsOneWidget);
        if (size.width < 800) expect(find.byTooltip('View Details'), findsWidgets);
        await tap(tester, entry);
        expect(tester.takeException(), isNull);
        final history = tester.getRect(key('collection-details-history'));
        expect(history.right, lessThanOrEqualTo(size.width));
        if (size.width >= 800) expect(history.width, lessThanOrEqualTo(640));
        for (final r in ['r1', 'r2', 'r3']) {
          final card = key('collection-payment-${ids[r]}');
          await tester.ensureVisible(card);
          await tester.pumpAndSettle();
          expect(tester.getRect(card).right, lessThanOrEqualTo(size.width), reason: r);
        }
        expect(tester.takeException(), isNull);
      });
    }
  });
}

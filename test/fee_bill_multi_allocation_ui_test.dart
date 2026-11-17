// Fee Bill Issuance Phase 2 screens: choosing several payments, the
// allocation matrix (live remaining amounts, validation, automatic
// allocation, confirmation), bill details and cancel-and-reissue for a bill
// supported by several payments, the report's allocation figures, and the
// Parent Dashboard bill details' allocation table.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_details_dialog.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_issuance_page.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_issue_dialog.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_models.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_service.dart';
import 'package:montessori_app/modules/parent/ui/parent_family_overview.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FeeBillService service;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    service = FeeBillService(firestore: firestore, auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'admin-1')), clock: () => DateTime(2026, 11, 16));
    await firestore.collection('students').doc('s1').set({'name': 'Anu Raman', 'admissionNo': 'ADM-101', 'classId': 'c1', 'isActive': true});
  });

  /// A collected payment: its receipt and matching Fees transaction record.
  Future<void> seedReceipt(String id, double amount, DateTime date, {bool withTransaction = true}) async {
    if (withTransaction) {
      await firestore.collection('fee_transactions').doc('t-$id').set({'studentId': 's1', 'amount': amount, 'paymentDate': date});
    }
    await firestore.collection('fee_receipts').doc(id).set({
      'receiptNo': 'REC-$id', 'transactionId': withTransaction ? 't-$id' : '', 'studentId': 's1', 'studentName': 'Anu Raman', 'admissionNo': 'ADM-101',
      'className': 'Mont 1', 'feeStructureName': 'Monthly tuition fee', 'amount': amount, 'paymentMode': 'cash', 'referenceNo': 'REF', 'paymentDate': date,
    });
  }

  Future<void> view(WidgetTester tester, {double width = 1200}) async {
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await settle(tester);
  }

  Future<void> type(WidgetTester tester, String key, String text) async {
    final f = find.byKey(Key(key));
    await tester.ensureVisible(f);
    await tester.enterText(f, text);
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;
  String field(WidgetTester tester, String key) => tester.widget<TextField>(find.byKey(Key(key))).controller!.text;
  ButtonStyleButton button(WidgetTester tester, String key) => tester.widget<ButtonStyleButton>(find.byKey(Key(key)));

  Future<List<String>> openDialogWithTwoPayments(WidgetTester tester, {double width = 1200}) async {
    await seedReceipt('r1', 8000, DateTime(2026, 11, 1));
    await seedReceipt('r2', 7000, DateTime(2026, 11, 3));
    await seedReceipt('r3', 3000, DateTime(2026, 11, 4), withTransaction: false);
    await view(tester, width: width);
    final popped = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FeeBillIssueDialog(
          service: service,
          role: 'admin',
          loadSchool: () async => SchoolSettingsModel.fromMap(kDefaultSchoolId, {'name': '2D Montessori'}),
          loadLogo: (_) async => null,
          savePdf: (_, name) async => popped.add(name),
        ),
      ),
    ));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('fee-bill-student-search')), 'anu');
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const Key('fee-bill-student-s1')));
    return popped;
  }

  testWidgets('several payments: the matrix updates remaining amounts as typed, validates, allocates automatically, and issues after confirming', (tester) async {
    await openDialogWithTwoPayments(tester);
    // A payment that can't be verified is shown with why, and can't be chosen.
    expect(find.textContaining('REC-r3 · ₹3,000.00 · CAN\'T BE USED'), findsOneWidget);
    expect(find.textContaining(FeeBillService.noTransactionMessage('REC-r3')), findsOneWidget);
    expect(tester.widget<ListTile>(find.descendant(of: find.byKey(const Key('fee-bill-payment-r3')), matching: find.byType(ListTile))).enabled, isFalse);

    await tap(tester, find.byKey(const Key('fee-bill-payment-r1')));
    expect(find.byKey(const Key('fee-bill-matrix')), findsNothing, reason: 'one payment: the usual single-payment summary');
    expect(find.byKey(const Key('fee-bill-summary-payment')), findsOneWidget);
    await tap(tester, find.byKey(const Key('fee-bill-payment-r2')));
    expect(find.byKey(const Key('fee-bill-matrix')), findsOneWidget);
    expect(text(tester, 'fee-bill-summary-selected'), '2');

    await type(tester, 'fee-bill-line-0-gross', '6000');
    await tap(tester, find.byKey(const Key('fee-bill-add-line')));
    await type(tester, 'fee-bill-line-1-gross', '5000');
    await tap(tester, find.byKey(const Key('fee-bill-add-line')));
    await type(tester, 'fee-bill-line-2-gross', '4000');
    expect(text(tester, 'fee-bill-summary-bills'), '3');
    expect(find.byKey(const Key('fee-bill-error')), findsOneWidget, reason: 'nothing allocated yet');
    expect(button(tester, 'fee-bill-review').onPressed, isNull);

    // Typing updates each payment's remaining amount immediately.
    await type(tester, 'fee-bill-line-0-alloc-r1', '6000');
    expect(text(tester, 'fee-bill-matrix-r1-remaining'), '₹2,000.00');
    expect(text(tester, 'fee-bill-line-0-allocated'), 'Allocated ₹6,000.00 of ₹6,000.00 net');
    await type(tester, 'fee-bill-line-1-alloc-r1', '3000');
    expect(text(tester, 'fee-bill-error'), contains('Bill line 2: its payment allocations total ₹3,000.00, but its net bill amount is ₹5,000.00'));
    await type(tester, 'fee-bill-line-1-alloc-r2', '2000');
    await type(tester, 'fee-bill-line-2-alloc-r2', '4000');
    expect(text(tester, 'fee-bill-error'), contains('These bills use ₹9,000.00 of receipt REC-r1, but only ₹8,000.00 of it is not yet billed'));
    await type(tester, 'fee-bill-line-0-alloc-r2', '-5');
    expect(text(tester, 'fee-bill-error'), contains('enter a valid amount for receipt REC-r2'));

    // Automatic allocation: earliest payment first.
    await tap(tester, find.byKey(const Key('fee-bill-auto-allocate')));
    expect([for (final k in ['0-alloc-r1', '0-alloc-r2', '1-alloc-r1', '1-alloc-r2', '2-alloc-r1', '2-alloc-r2']) field(tester, 'fee-bill-line-$k')],
        ['6000', '0', '2000', '3000', '0', '4000']);
    expect((text(tester, 'fee-bill-matrix-r1-remaining'), text(tester, 'fee-bill-matrix-r2-remaining')), ('₹0.00', '₹0.00'));
    expect((text(tester, 'fee-bill-summary-allocated'), text(tester, 'fee-bill-summary-unallocated')), ('₹15,000.00', '₹0.00'));
    expect(find.byKey(const Key('fee-bill-error')), findsNothing);

    await tap(tester, find.byKey(const Key('fee-bill-review')));
    expect(find.textContaining('Supported by REC-r1 ₹2,000.00, REC-r2 ₹3,000.00'), findsOneWidget);
    await tap(tester, find.byKey(const Key('fee-bill-issue')));
    expect(text(tester, 'fee-bill-confirm-text'), contains('supported by 2 payments: REC-r1 (₹8,000.00 of ₹8,000.00), REC-r2 (₹7,000.00 of ₹7,000.00)'));
    await tap(tester, find.byKey(const Key('fee-bill-confirm-issue')));
    for (final ref in ['REC-r1-000001', 'REC-r1-000002', 'REC-r2-000001']) {
      expect(find.byKey(Key('fee-bill-issued-$ref')), findsOneWidget, reason: ref);
    }
    final bill = (await tester.runAsync(() => service.getBill(FeeIssuedBill.idFor(kDefaultSchoolId, 'REC-r1-000002'))))!;
    expect([for (final a in bill.allocations) (a.receiptNo, a.allocatedPaise)], [('REC-r1', 200000), ('REC-r2', 300000)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('partial allocation: what is left stays available, and is shown', (tester) async {
    await openDialogWithTwoPayments(tester);
    await tap(tester, find.byKey(const Key('fee-bill-payment-r1')));
    await tap(tester, find.byKey(const Key('fee-bill-payment-r2')));
    await type(tester, 'fee-bill-line-0-gross', '10000');
    await tap(tester, find.byKey(const Key('fee-bill-auto-allocate')));
    expect((field(tester, 'fee-bill-line-0-alloc-r1'), field(tester, 'fee-bill-line-0-alloc-r2')), ('8000', '2000'));
    expect(text(tester, 'fee-bill-summary-unallocated'), '₹5,000.00');
    expect(find.textContaining('₹5,000.00 of these payments stays available for future bills.'), findsOneWidget);
    // Un-choosing a payment returns to the one-payment form.
    await tap(tester, find.byKey(const Key('fee-bill-payment-r2')));
    expect(find.byKey(const Key('fee-bill-matrix')), findsNothing);
    expect(find.byKey(const Key('fee-bill-line-0-alloc-r1')), findsNothing);
  });

  testWidgets('phone width: the payments, matrix and allocation fields lay out without overflow', (tester) async {
    await openDialogWithTwoPayments(tester, width: 390);
    await tap(tester, find.byKey(const Key('fee-bill-payment-r1')));
    await tap(tester, find.byKey(const Key('fee-bill-payment-r2')));
    await type(tester, 'fee-bill-line-0-gross', '6000');
    await tap(tester, find.byKey(const Key('fee-bill-auto-allocate')));
    expect(find.byKey(const Key('fee-bill-matrix')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  Future<FeeIssuedBill> multiBill(WidgetTester tester) async {
    await seedReceipt('r1', 8000, DateTime(2026, 11, 1));
    await seedReceipt('r2', 7000, DateTime(2026, 11, 3));
    return (await tester.runAsync(() => service.issueAllocatedBills(
          requesterRole: 'admin', studentId: 's1', requestId: 'req-1', school: const FeeBillSchool(name: '2D Montessori'),
          drafts: const [FeeBillDraft(line: FeeBillLine(billingMonth: '2026-10', description: 'Monthly tuition fee', grossPaise: 500000), allocations: {'r1': 200000, 'r2': 300000})],
        )))!.single;
  }

  testWidgets('bill details list every payment; cancel and reissue edits the replacement\'s allocations', (tester) async {
    final bill = await multiBill(tester);
    await view(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FeeBillDetailsDialog(bill: bill, service: service, role: 'admin', loadLogo: (_) async => null, savePdf: (a, b) async {})),
    ));
    await settle(tester);
    expect(find.byKey(const Key('fee-bill-details-allocations')), findsOneWidget);
    expect(find.text('REC-r1, REC-r2'), findsOneWidget, reason: 'Receipt Reference lists both');
    expect(find.textContaining('Bill Reference from REC-r1, the earliest'), findsOneWidget);
    await tap(tester, find.byKey(const Key('fee-bill-details-payment')));
    expect(find.text('Used by this bill'), findsNWidgets(2));

    await tap(tester, find.byKey(const Key('fee-bill-details-cancel')));
    await type(tester, 'fee-bill-cancel-reason', 'Lower amount');
    await tap(tester, find.byKey(const Key('fee-bill-cancel-reissue')));
    expect((field(tester, 'fee-bill-reissue-alloc-r1'), field(tester, 'fee-bill-reissue-alloc-r2')), ('2000', '3000'), reason: 'prefilled from the cancelled bill');
    await type(tester, 'fee-bill-reissue-gross', '4500');
    await tap(tester, find.byKey(const Key('fee-bill-cancel-confirm')));
    expect(text(tester, 'fee-bill-cancel-error'), contains('total ₹5,000.00, but its net bill amount is ₹4,500.00'));
    await type(tester, 'fee-bill-reissue-alloc-r2', '2500');
    await tap(tester, find.byKey(const Key('fee-bill-cancel-confirm')));
    expect(find.textContaining('was cancelled and replaced by REC-r1-000002'), findsOneWidget);
    final replacement = (await tester.runAsync(() => service.getBill(FeeIssuedBill.idFor(kDefaultSchoolId, 'REC-r1-000002'))))!;
    expect([for (final a in replacement.allocations) a.allocatedPaise], [200000, 250000]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the report: allocated to active bills, collected on usable payments, not yet allocated, and per-payment details', (tester) async {
    await multiBill(tester);
    await seedReceipt('r3', 3000, DateTime(2026, 11, 4), withTransaction: false);
    await view(tester, width: 1400);
    await tester.pumpWidget(ProviderScope(
      overrides: [currentUserProvider.overrideWith((ref) => AppUser(id: 'u1', phone: '9999999999', role: 'admin', isActive: true))],
      child: MaterialApp(
        home: FeeBillIssuancePage(
          service: service,
          loadSchool: () async => SchoolSettingsModel.fromMap(kDefaultSchoolId, {'name': '2D Montessori'}),
          loadLogo: (_) async => null,
          savePdf: (a, b) async {},
        ),
      ),
    ));
    await settle(tester);
    expect(text(tester, 'fee-bills-total-net'), '₹5,000.00');
    expect(text(tester, 'fee-bills-total-allocated'), '₹5,000.00');
    expect(text(tester, 'fee-bills-total-eligible'), '₹15,000.00', reason: 'the unverifiable ₹3,000 payment is not counted');
    expect(text(tester, 'fee-bills-total-unallocated'), '₹10,000.00');
    expect(find.byKey(const Key('fee-bills-needs-review')), findsNothing);
    await tap(tester, find.byKey(const Key('fee-bills-payment-allocations')));
    expect(find.byKey(const Key('fee-bills-payment-allocation-r2')), findsOneWidget);
    expect(find.textContaining('Collected ₹7,000.00 · Allocated ₹3,000.00 · Not yet allocated ₹4,000.00'), findsOneWidget);
    expect(find.textContaining('Can\'t support new bills'), findsOneWidget);
    expect(find.textContaining('Receipt Reference REC-r1, REC-r2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the report flags a payment edited in Fees to below what its bills use', (tester) async {
    await multiBill(tester);
    await tester.runAsync(() => firestore.collection('fee_receipts').doc('r2').update({'amount': 2000}));
    await view(tester, width: 1400);
    await tester.pumpWidget(ProviderScope(
      overrides: [currentUserProvider.overrideWith((ref) => AppUser(id: 'u1', phone: '9999999999', role: 'admin', isActive: true))],
      child: MaterialApp(
        home: FeeBillIssuancePage(
          service: service,
          loadSchool: () async => SchoolSettingsModel.fromMap(kDefaultSchoolId, {'name': '2D Montessori'}),
          loadLogo: (_) async => null,
          savePdf: (a, b) async {},
        ),
      ),
    ));
    await settle(tester);
    expect(text(tester, 'fee-bills-needs-review'), contains('REC-r2 (₹3,000.00 billed of ₹2,000.00)'));
  });

  testWidgets('Parent Dashboard bill details: the payment allocation table, and one payment is still one payment', (tester) async {
    final bill = await multiBill(tester);
    await view(tester, width: 390);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => TextButton(onPressed: () => showParentBillDetail(context, bill: bill, childName: 'Anu'), child: const Text('open')))),
    ));
    await tap(tester, find.text('open'));
    expect(find.byKey(const Key('parent-bill-detail-allocations')), findsOneWidget);
    expect(find.text('REC-r1 (01 Nov 2026)'), findsOneWidget);
    expect(find.text('Rs. 2,000.00'), findsOneWidget);
    expect(find.text('REC-r2 (03 Nov 2026)'), findsOneWidget);
    expect(find.text('Rs. 5,000.00'), findsNWidgets(3), reason: 'gross, total allocated, net');
    expect(find.textContaining('it was paid only once'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

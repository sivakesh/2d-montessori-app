// Fee Bill Issuance → Issue Bills dialog: opening safely in every empty or
// fully billed state, and drafting and previewing a valid bill.
//
// Regression for "RangeError: max must be in range 0 < max ≤ 2^32, was 0"
// when the dialog opened on Flutter Web: its request id used
// Random().nextInt(1 << 32), and on the web `1 << 32` is 0. These tests use
// no dart:io, so they also run in a browser, where that bug occurred:
//
//   flutter test --platform chrome test/fee_bill_issue_dialog_test.dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_issue_dialog.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_models.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FeeBillService service;
  late List<String> saved;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = FeeBillService(firestore: firestore, auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'admin-1')), clock: () => DateTime(2026, 11, 16));
    saved = [];
  });

  Future<void> seedStudent({String id = 's1', String name = 'Anu Raman'}) =>
      firestore.collection('students').doc(id).set({'name': name, 'admissionNo': 'ADM-101', 'classId': 'c1', 'isActive': true});

  /// A collected payment: its receipt and its matching Fees transaction
  /// record, written together as collectFee does.
  Future<void> seedReceipt(String id, {double amount = 12500, bool voided = false, DateTime? date, String? transactionId}) async {
    final tid = transactionId ?? 't-$id';
    if (tid.isNotEmpty) {
      await firestore.collection('fee_transactions').doc(tid).set({
        'studentId': 's1', 'studentName': 'Anu Raman', 'amount': amount, 'paymentMode': 'upi', 'referenceNo': 'UPI-1', 'paymentDate': date ?? DateTime(2026, 11, 5),
      });
    }
    await firestore.collection('fee_receipts').doc(id).set({
      'receiptNo': 'REC-$id', 'transactionId': tid, 'studentId': 's1', 'studentName': 'Anu Raman', 'admissionNo': 'ADM-101', 'className': 'Mont 1',
      'feeStructureName': 'Monthly tuition fee', 'amount': amount, 'paymentMode': 'upi', 'referenceNo': 'UPI-1',
      'paymentDate': date ?? DateTime(2026, 11, 5), if (voided) 'isDeleted': true,
    });
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FeeBillIssueDialog(
          service: service,
          role: 'admin',
          loadSchool: () async => SchoolSettingsModel.fromMap(kDefaultSchoolId, {'name': '2D Montessori'}),
          loadLogo: (_) async => null,
          savePdf: (_, name) async => saved.add(name),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'the dialog opens without an error');
    expect(find.text('Issue Fee Bills'), findsOneWidget);
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> chooseStudent(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('fee-bill-student-search')), 'anu');
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const Key('fee-bill-student-s1')));
  }

  ButtonStyleButton button(WidgetTester tester, String key) => tester.widget<ButtonStyleButton>(find.byKey(Key(key)));

  test('a request id is a fresh 20-character id each time, with no integer arithmetic', () {
    final ids = {for (var i = 0; i < 50; i++) service.newRequestId()};
    expect(ids, hasLength(50));
    expect(ids.every((id) => RegExp(r'^[A-Za-z0-9]{20}$').hasMatch(id)), isTrue);
  });

  testWidgets('opens with no students: says so, and nothing can be issued', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('fee-bill-no-students')), findsOneWidget);
    expect(find.byKey(const Key('fee-bill-student-search')), findsNothing);
    expect(button(tester, 'fee-bill-review').onPressed, isNull);
    expect(find.byKey(const Key('fee-bill-error')), findsNothing);
  });

  testWidgets('a student with no payments, or only a voided one: nothing to choose', (tester) async {
    await seedStudent();
    await open(tester);
    await chooseStudent(tester);
    expect(find.byKey(const Key('fee-bill-no-payments')), findsOneWidget);
    expect(button(tester, 'fee-bill-review').onPressed, isNull);

    await seedReceipt('r9', voided: true);
    await tap(tester, find.byKey(const Key('fee-bill-student-change')));
    await chooseStudent(tester);
    expect(find.textContaining('VOIDED'), findsOneWidget);
    expect(tester.widget<ListTile>(find.descendant(of: find.byKey(const Key('fee-bill-payment-r9')), matching: find.byType(ListTile))).enabled, isFalse);
    await tap(tester, find.byKey(const Key('fee-bill-payment-r9')));
    expect(find.byKey(const Key('fee-bill-payment-details')), findsNothing);
  });

  testWidgets('a fully billed payment is shown as such and can’t be chosen', (tester) async {
    await seedStudent();
    await seedReceipt('r1', amount: 4200);
    await service.issueBills(
      requesterRole: 'admin', studentId: 's1', receiptId: 'r1', requestId: service.newRequestId(), school: const FeeBillSchool(name: 'x'),
      lines: const [FeeBillLine(billingMonth: '2026-09', description: 'Monthly tuition fee', grossPaise: 420000)],
    );
    await open(tester);
    await chooseStudent(tester);
    expect(find.textContaining('FULLY BILLED'), findsOneWidget);
    expect(find.textContaining('Cancel a bill to bill this payment again'), findsOneWidget);
    expect(tester.widget<ListTile>(find.descendant(of: find.byKey(const Key('fee-bill-payment-r1')), matching: find.byType(ListTile))).enabled, isFalse);
    await tap(tester, find.byKey(const Key('fee-bill-payment-r1')));
    expect(find.byKey(const Key('fee-bill-payment-details')), findsNothing);
    expect(button(tester, 'fee-bill-review').onPressed, isNull);
  });

  testWidgets('before any amount is entered: one empty line, no error, Preview disabled; lines can be added and removed', (tester) async {
    await seedStudent();
    await seedReceipt('r1');
    await open(tester);
    await chooseStudent(tester);
    await tap(tester, find.byKey(const Key('fee-bill-payment-r1')));
    expect(find.byKey(const Key('fee-bill-payment-details')), findsOneWidget);
    expect(find.byKey(const Key('fee-bill-line-0-gross')), findsOneWidget);
    expect(find.byKey(const Key('fee-bill-line-0-remove')), findsNothing, reason: 'the only line can’t be removed');
    expect(tester.widget<Text>(find.byKey(const Key('fee-bill-line-0-net'))).data, 'Net bill amount: -');
    expect(find.byKey(const Key('fee-bill-error')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('fee-bill-summary-new'))).data, '₹0.00');
    expect(tester.widget<Text>(find.byKey(const Key('fee-bill-summary-remaining'))).data, '₹12,500.00');
    expect(button(tester, 'fee-bill-review').onPressed, isNull);

    await tap(tester, find.byKey(const Key('fee-bill-add-line')));
    await tap(tester, find.byKey(const Key('fee-bill-add-line')));
    expect(find.byKey(const Key('fee-bill-line-2-gross')), findsOneWidget);
    await tap(tester, find.byKey(const Key('fee-bill-line-1-remove')));
    expect(find.byKey(const Key('fee-bill-line-2-gross')), findsNothing);
    await tap(tester, find.byKey(const Key('fee-bill-line-1-remove')));
    expect(find.byKey(const Key('fee-bill-line-1-gross')), findsNothing);
    expect(find.byKey(const Key('fee-bill-line-0-remove')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a valid draft: net, allocation and Preview; the preview lists the bill and its PDF writes nothing', (tester) async {
    await seedStudent();
    await seedReceipt('r1');
    await open(tester);
    await chooseStudent(tester);
    await tap(tester, find.byKey(const Key('fee-bill-payment-r1')));
    await tester.enterText(find.byKey(const Key('fee-bill-line-0-gross')), '4200');
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('fee-bill-line-0-net'))).data, 'Net bill amount: ₹4,200.00');
    expect(tester.widget<Text>(find.byKey(const Key('fee-bill-summary-remaining'))).data, '₹8,300.00');
    expect(find.textContaining('Partly billed: ₹8,300.00'), findsOneWidget);
    expect(button(tester, 'fee-bill-review').onPressed, isNotNull);

    await tap(tester, find.byKey(const Key('fee-bill-review')));
    expect(find.byKey(const Key('fee-bill-preview')), findsOneWidget);
    expect(find.textContaining('November 2026 · Monthly tuition fee'), findsOneWidget);
    expect(button(tester, 'fee-bill-issue').onPressed, isNotNull);
    await tester.ensureVisible(find.byKey(const Key('fee-bill-preview-pdf-0')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('fee-bill-preview-pdf-0')));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pumpAndSettle();
    expect(saved, ['fee-bill-preview-1.pdf']);
    expect((await firestore.collection(FeeBillService.billsCollection).get()).docs, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Show GSTIN on bill needs a valid GSTIN in School Settings', (tester) async {
    await seedStudent();
    await seedReceipt('r1');
    await open(tester);
    await chooseStudent(tester);
    await tap(tester, find.byKey(const Key('fee-bill-payment-r1')));
    await tester.enterText(find.byKey(const Key('fee-bill-line-0-gross')), '4200');
    await tester.pumpAndSettle();
    expect(button(tester, 'fee-bill-review').onPressed, isNotNull);
    await tap(tester, find.byKey(const Key('fee-bill-show-gstin')));
    expect(tester.widget<Text>(find.byKey(const Key('fee-bill-error'))).data, contains('No GSTIN is configured'));
    expect(button(tester, 'fee-bill-review').onPressed, isNull);
    await tap(tester, find.byKey(const Key('fee-bill-show-gstin')));
    expect(button(tester, 'fee-bill-review').onPressed, isNotNull);
  });

  testWidgets('the parent shown and the class selector default to the student’s linked father and the receipt’s class', (tester) async {
    await firestore.collection('students').doc('s1').set({
      'name': 'Anu Raman', 'admissionNo': 'ADM-101', 'classId': 'c1', 'isActive': true,
      'parentLinks': [
        {'name': 'Lakshmi R', 'relation': 'Mother'},
        {'name': 'Raman K', 'relation': 'Father'},
      ],
    });
    await firestore.collection('classes').doc('c1').set({'name': 'Mont 1'});
    await firestore.collection('classes').doc('c2').set({'name': 'Mont 2'});
    await seedReceipt('r1');
    await open(tester);
    await chooseStudent(tester);
    await tap(tester, find.byKey(const Key('fee-bill-payment-r1')));
    expect(tester.widget<Text>(find.byKey(const Key('fee-bill-parent'))).data, "Father's Name on the bills: Raman K");
    final selector = find.descendant(of: find.byKey(const Key('fee-bill-line-0-class')), matching: find.byType(DropdownButton<String>));
    expect(tester.widget<DropdownButton<String>>(selector).value, 'Mont 1');
    await tap(tester, find.byKey(const Key('fee-bill-line-0-class')));
    expect(find.text('Mont 2'), findsWidgets);
  });

  testWidgets('a payment whose receipt number can’t form a Bill Reference is shown with the reason and can’t be chosen', (tester) async {
    await seedStudent();
    await firestore.collection('fee_receipts').doc('legacy').set({
      'receiptNo': 'REC/OLD 1', 'studentId': 's1', 'studentName': 'Anu Raman', 'amount': 1000.0, 'paymentMode': 'cash', 'paymentDate': DateTime(2026, 6, 1),
    });
    await open(tester);
    await chooseStudent(tester);
    expect(find.textContaining("can't be used for Bill References"), findsOneWidget);
    expect(tester.widget<ListTile>(find.descendant(of: find.byKey(const Key('fee-bill-payment-legacy')), matching: find.byType(ListTile))).enabled, isFalse);
    await tap(tester, find.byKey(const Key('fee-bill-payment-legacy')));
    expect(find.byKey(const Key('fee-bill-payment-details')), findsNothing);
  });
}

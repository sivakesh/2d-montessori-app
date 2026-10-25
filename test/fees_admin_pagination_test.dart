// Admin Fees: UI pagination (10/25/50 per page) on all five lists —
// Structures, Assignments, Collections, Receipts, Dues.
// - Only the current page's rows are built, in the existing service order
//   (newest first); Collections/Dues are assignments with a balance.
// - Previous/Next (disabled at the ends), "Showing x–y of n", "Page p of q";
//   back to page 1 when records are added/removed/reordered or the page
//   becomes invalid; no controls for an empty list.
// - Each list keeps its own page, also across tab switches.
// - The dashboard summary (getDashboardSummary over all records) is
//   unchanged by paging.
// - Row actions work on later pages. Collect and receipt View open dialogs
//   that build their own FeeService() (real Firebase), so those two are
//   checked as present/enabled only; Edit, Delete and Void are exercised.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/providers/academic_year_provider.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/admin_fees_screen.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';

import 'support/buffered_transaction_firestore.dart';

String _nn(int n) => n.toString().padLeft(2, '0');
final _base = DateTime(2026, 8, 1);

class _List {
  const _List(this.key, this.chip, this.titlePattern, this.titles);
  final String key; // pagination key segment
  final String chip; // tab ChoiceChip label
  final String titlePattern; // regex for this list's row titles
  final List<String> titles; // all rows, in display order
}

// 27 structures/assignments/receipts; odd-numbered assignments have a
// balance, so Collections and Dues list 14 rows.
final _lists = [
  _List('structures', 'Structures', r'^Structure \d\d$', [for (var n = 27; n >= 1; n--) 'Structure ${_nn(n)}']),
  _List('assignments', 'Assignments', r'^Student \d\d$', [for (var n = 27; n >= 1; n--) 'Student ${_nn(n)}']),
  _List('collections', 'Collections', r'^Student \d\d$', [for (var n = 27; n >= 1; n -= 2) 'Student ${_nn(n)}']),
  _List('receipts', 'Receipts', r'^REC-\d\d$', [for (var n = 27; n >= 1; n--) 'REC-${_nn(n)}']),
  _List('dues', 'Dues', r'^Student \d\d$', [for (var n = 27; n >= 1; n -= 2) 'Student ${_nn(n)}']),
];

void main() {
  late BufferedTransactionFirestore firestore;
  late FeeService fees;

  setUp(() async {
    firestore = BufferedTransactionFirestore();
    final auth = MockFirebaseAuth();
    final finance = FinanceService(firestore: firestore, auth: auth);
    await finance.ensureDefaults();
    fees = FeeService(firestore: firestore, auth: auth, storage: MockFirebaseStorage(), financeService: finance);
  });

  Future<void> seedStructure(int n) => firestore.collection('fee_structures').doc('s-${_nn(n)}').set({
        'name': 'Structure ${_nn(n)}', 'components': <Map<String, dynamic>>[], 'academicYear': '2026-2027',
        'totalAmount': 0, 'isActive': true, 'createdAt': _base.add(Duration(minutes: n)),
      });

  Future<void> seed({int count = 27}) async {
    for (var n = 1; n <= count; n++) {
      await seedStructure(n);
      final payable = n * 100;
      final paid = n.isEven ? payable : 0;
      await firestore.collection('student_fee_assignments').doc('a-${_nn(n)}').set({
        'studentId': 'st-$n', 'studentName': 'Student ${_nn(n)}', 'admissionNo': 'ADM-${_nn(n)}',
        'classId': 'class-1', 'className': 'Mont 1', 'feeStructureId': 's-01', 'feeStructureName': 'Core Fees',
        'totalFee': payable, 'discountAmount': 0, 'payableAmount': payable, 'paidAmount': paid,
        'balanceAmount': payable - paid, 'status': n.isEven ? 'paid' : 'unpaid',
        'assignedAt': Timestamp.fromDate(_base.add(Duration(minutes: n))),
        'updatedAt': Timestamp.fromDate(_base.add(Duration(minutes: n))),
      });
      await firestore.collection('fee_receipts').doc('r-${_nn(n)}').set({
        'receiptNo': 'REC-${_nn(n)}', 'studentName': 'Student ${_nn(n)}', 'admissionNo': 'ADM-${_nn(n)}',
        'className': 'Mont 1', 'feeStructureName': 'Core Fees', 'amount': 10, 'paymentMode': 'cash',
        'assignmentId': 'a-02', 'studentId': 'st-2', 'transactionId': '', 'pdfUrl': '', 'isDeleted': false,
        'paymentDate': Timestamp.fromDate(DateTime(2026, 7, 1)),
        'createdAt': Timestamp.fromDate(_base.add(Duration(minutes: n))),
      });
    }
  }

  Future<void> pumpFees(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [academicYearServiceProvider.overrideWithValue(AcademicYearService(firestore: firestore))],
      child: MaterialApp(home: AdminFeesScreen(service: fees)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, _List list) =>
      tapAndSettle(tester, find.widgetWithText(ChoiceChip, list.chip));

  List<String> shown(WidgetTester tester, _List list) =>
      tester.widgetList<Text>(find.textContaining(RegExp(list.titlePattern))).map((t) => t.data!).toList();

  Finder next() => find.byTooltip('Next page');
  Finder previous() => find.byTooltip('Previous page');
  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<IconButton>(find.ancestor(of: button, matching: find.byType(IconButton))).onPressed != null;

  Future<void> choosePageSize(WidgetTester tester, _List list, int size) async {
    await tapAndSettle(tester, find.byKey(Key('fees-${list.key}-page-size')));
    await tester.tap(find.text('$size').last);
    await tester.pumpAndSettle();
  }

  /// Summary over all 27 assignments: expected ₹100 × 1..27, collected the
  /// even ones, outstanding the odd ones.
  void expectSummary(WidgetTester tester) {
    expect(find.text('₹37,800'), findsOneWidget); // Total Expected
    expect(find.text('₹18,200'), findsOneWidget); // Total Collected
    expect(find.text('₹19,600'), findsOneWidget); // Outstanding
  }

  int pageCount(int total, int size) => (total + size - 1) ~/ size;

  for (final list in _lists) {
    group('${list.chip} pagination', () {
      final total = list.titles.length;

      testWidgets('1. first page in service order, range and page count', (tester) async {
        await seed();
        await pumpFees(tester);
        await openTab(tester, list);
        expect(shown(tester, list), list.titles.take(10).toList());
        expect(find.text('Showing 1–10 of $total'), findsOneWidget);
        expect(find.text('Page 1 of ${pageCount(total, 10)}'), findsOneWidget);
        expect(find.byKey(Key('fees-${list.key}-pagination')), findsOneWidget);
      });

      testWidgets('2 + 7. Next/Previous with disabled ends; summary unchanged on every page', (tester) async {
        await seed();
        await pumpFees(tester);
        await openTab(tester, list);
        expect(enabled(tester, previous()), isFalse);
        final pages = pageCount(total, 10);
        for (var p = 2; p <= pages; p++) {
          await tapAndSettle(tester, next());
          final from = (p - 1) * 10;
          final to = (from + 10).clamp(0, total);
          expect(shown(tester, list), list.titles.sublist(from, to));
          expect(find.text('Showing ${from + 1}–$to of $total'), findsOneWidget);
          expect(find.text('Page $p of $pages'), findsOneWidget);
          expect(enabled(tester, previous()), isTrue);
          expectSummary(tester);
        }
        expect(enabled(tester, next()), isFalse);
        for (var p = pages; p > 1; p--) {
          await tapAndSettle(tester, previous());
        }
        expect(shown(tester, list), list.titles.take(10).toList());
        expect(enabled(tester, previous()), isFalse);
        expectSummary(tester);
      });

      testWidgets('3. page sizes: a still-valid page is kept, an invalid one returns to page 1', (tester) async {
        await seed();
        await pumpFees(tester);
        await openTab(tester, list);
        await tapAndSettle(tester, next()); // page 2 at 10 per page

        await choosePageSize(tester, list, 25);
        if (total > 25) {
          expect(shown(tester, list), list.titles.sublist(25));
          expect(find.text('Showing 26–$total of $total'), findsOneWidget);
          expect(find.text('Page 2 of 2'), findsOneWidget);
        } else {
          expect(shown(tester, list), list.titles);
          expect(find.text('Showing 1–$total of $total'), findsOneWidget);
          expect(find.text('Page 1 of 1'), findsOneWidget);
        }

        await choosePageSize(tester, list, 50);
        expect(shown(tester, list), list.titles);
        expect(find.text('Page 1 of 1'), findsOneWidget);
        expect(enabled(tester, previous()), isFalse);
        expect(enabled(tester, next()), isFalse);

        await choosePageSize(tester, list, 10);
        expect(shown(tester, list), list.titles.take(10).toList());
        expectSummary(tester);
      });

      testWidgets('4. empty list: no rows and no pagination controls', (tester) async {
        await pumpFees(tester);
        await openTab(tester, list);
        expect(shown(tester, list), isEmpty);
        expect(find.byKey(Key('fees-${list.key}-pagination')), findsNothing);
        expect(find.byTooltip('Next page'), findsNothing);
      });
    });
  }

  group('page state and list changes', () {
    testWidgets('each list keeps its own page, also across tab switches', (tester) async {
      await seed();
      await pumpFees(tester);
      await tapAndSettle(tester, next());
      await tapAndSettle(tester, next());
      expect(find.text('Page 3 of 3'), findsOneWidget); // Structures

      await openTab(tester, _lists[3]); // Receipts
      expect(find.text('Page 1 of 3'), findsOneWidget);
      await tapAndSettle(tester, next());
      expect(find.text('Page 2 of 3'), findsOneWidget);

      await openTab(tester, _lists[4]); // Dues: independent of Collections
      expect(find.text('Page 1 of 2'), findsOneWidget);
      await tapAndSettle(tester, next());
      await openTab(tester, _lists[2]); // Collections
      expect(find.text('Page 1 of 2'), findsOneWidget);

      await openTab(tester, _lists[0]);
      expect(find.text('Page 3 of 3'), findsOneWidget);
      expect(shown(tester, _lists[0]), _lists[0].titles.sublist(20));
      await openTab(tester, _lists[3]);
      expect(find.text('Page 2 of 3'), findsOneWidget);
      await openTab(tester, _lists[4]);
      expect(find.text('Page 2 of 2'), findsOneWidget);
    });

    testWidgets('5a + 6. Edit on a later page; a record added meanwhile returns that list to page 1', (tester) async {
      await seed();
      await pumpFees(tester);
      await tapAndSettle(tester, next()); // Structures page 2
      expect(find.byTooltip('Edit'), findsNWidgets(10));

      await seedStructure(28); // added elsewhere; picked up by the reload after the dialog
      await tapAndSettle(tester, find.byTooltip('Edit').first);
      expect(find.text('Edit Fee Structure'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();

      expect(find.text('Showing 1–10 of 28'), findsOneWidget);
      expect(shown(tester, _lists[0]).first, 'Structure 28');
    });

    testWidgets('5b + 6. Delete a structure on page 2: removed, list returns to page 1', (tester) async {
      await seed();
      await pumpFees(tester);
      await tapAndSettle(tester, next());
      await tapAndSettle(tester, find.byTooltip('Delete').first); // Structure 17
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect((await firestore.doc('fee_structures/s-17').get()).data()!['isDeleted'], isTrue);
      expect(find.text('Showing 1–10 of 26'), findsOneWidget);
      expect(find.text('Structure 17'), findsNothing);
    });

    testWidgets('6. Assignments/Collections/Dues: Delete works from page 2; Collect is available there', (tester) async {
      await seed();
      await pumpFees(tester);

      await openTab(tester, _lists[2]); // Collections page 2: Student 07, 05, 03, 01
      await tapAndSettle(tester, next());
      final collect = find.widgetWithText(TextButton, 'Collect');
      expect(collect, findsNWidgets(4));
      expect(tester.widget<TextButton>(collect.first).onPressed, isNotNull);

      await tapAndSettle(tester, find.byTooltip('Delete').first);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect((await firestore.doc('student_fee_assignments/a-07').get()).data()!['isDeleted'], isTrue);
      expect(find.text('Showing 1–10 of 13'), findsOneWidget);

      await openTab(tester, _lists[4]); // Dues reflects the same reload
      await tapAndSettle(tester, next());
      expect(shown(tester, _lists[4]), ['Student 05', 'Student 03', 'Student 01']);
      await tapAndSettle(tester, find.byTooltip('Delete').first);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect((await firestore.doc('student_fee_assignments/a-05').get()).data()!['isDeleted'], isTrue);

      await openTab(tester, _lists[1]); // Assignments page 2
      await tapAndSettle(tester, next());
      expect(find.byTooltip('Edit'), findsNWidgets(10));
      await tapAndSettle(tester, find.byTooltip('Delete').first);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Showing 1–10 of 24'), findsOneWidget);
    });

    testWidgets('6. Receipts: Void works from page 2 and the list returns to page 1', (tester) async {
      await seed();
      await pumpFees(tester);
      await openTab(tester, _lists[3]);
      await tapAndSettle(tester, next());
      expect(shown(tester, _lists[3]).first, 'REC-17');

      await tapAndSettle(tester, find.byIcon(Icons.more_vert).first);
      expect(find.text('View'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      await tester.tap(find.text('Void'));
      await tester.pumpAndSettle();
      expect(find.text('Void Payment'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Void'));
      await tester.pumpAndSettle();

      expect((await firestore.doc('fee_receipts/r-17').get()).data()!['isDeleted'], isTrue);
      expect(find.text('Showing 1–10 of 26'), findsOneWidget);
      expect(find.text('REC-17'), findsNothing);
    });
  });
}

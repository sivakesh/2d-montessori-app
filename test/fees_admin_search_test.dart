// Admin Fees: free-text search above each of the five lists (display only).
// - Trimmed, case-insensitive substring match over the model's own fields:
//   Structures: name, description, academic year (stored and resolved
//   label), component frequencies. Assignments / Collections / Dues:
//   student name, admission no., class, fee structure, academic year,
//   status. Receipts: receipt no., student name, admission no., class,
//   fee structure, payment mode, reference no.
// - Updates while typing; Clear restores the list; "No … match "query"."
//   when nothing matches (no pagination then); a genuinely empty list
//   renders as before, with no search box.
// - Paging applies to the matches; a query change returns only that list
//   to page 1; page size kept; each list's query and page survive tab
//   switches and reloads.
// - The dashboard summary (getDashboardSummary) is unchanged by searching.
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
  const _List(this.key, this.chip, this.noun, this.titlePattern, this.total, this.matchAll);
  final String key;
  final String chip;
  final String noun; // no-match message noun
  final String titlePattern;
  final int total;
  final String matchAll; // a query every row matches
}

// As the pagination test: 27 rows each; Collections/Dues are the 14
// odd-numbered (unpaid) assignments.
const _structures = _List('structures', 'Structures', 'fee structures', r'^Structure \d\d$', 27, 'structure');
const _assignments = _List('assignments', 'Assignments', 'assignments', r'^Student \d\d$', 27, 'student');
const _collections = _List('collections', 'Collections', 'collections', r'^Student \d\d$', 14, 'student');
const _receipts = _List('receipts', 'Receipts', 'receipts', r'^REC-\d\d$', 27, 'rec-');
const _dues = _List('dues', 'Dues', 'dues', r'^Student \d\d$', 14, 'student');
const _all = [_structures, _assignments, _collections, _receipts, _dues];

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

  Future<void> seedStructure(int n, {String description = ''}) => firestore.collection('fee_structures').doc('s-${_nn(n)}').set({
        'name': 'Structure ${_nn(n)}', 'description': n == 5 ? 'Transport fees' : description,
        'components': [
          if (n == 7) {'name': 'Tuition', 'amount': 100, 'frequency': 'monthly'},
        ],
        'academicYear': n <= 13 ? '2026-2027' : '2025-2026', 'totalAmount': 0, 'isActive': true,
        'createdAt': _base.add(Duration(minutes: n)),
      });

  /// The pagination test's data plus searchable variety: every 3rd student
  /// in "Mont 2", assignment 4 on "Transport Fees", assignment 9 in
  /// 2025-2026; every 3rd receipt by UPI, receipt 6 with a reference.
  Future<void> seed() async {
    for (var n = 1; n <= 27; n++) {
      await seedStructure(n);
      final payable = n * 100;
      final paid = n.isEven ? payable : 0;
      final className = n % 3 == 0 ? 'Mont 2' : 'Mont 1';
      await firestore.collection('student_fee_assignments').doc('a-${_nn(n)}').set({
        'studentId': 'st-$n', 'studentName': 'Student ${_nn(n)}', 'admissionNo': 'ADM-${_nn(n)}',
        'classId': 'class-1', 'className': className, 'feeStructureId': 's-01',
        'feeStructureName': n == 4 ? 'Transport Fees' : 'Core Fees', 'academicYear': n == 9 ? '2025-2026' : '2026-2027',
        'totalFee': payable, 'discountAmount': 0, 'payableAmount': payable, 'paidAmount': paid,
        'balanceAmount': payable - paid, 'status': n.isEven ? 'paid' : 'unpaid',
        'assignedAt': Timestamp.fromDate(_base.add(Duration(minutes: n))),
        'updatedAt': Timestamp.fromDate(_base.add(Duration(minutes: n))),
      });
      await firestore.collection('fee_receipts').doc('r-${_nn(n)}').set({
        'receiptNo': 'REC-${_nn(n)}', 'studentName': 'Student ${_nn(n)}', 'admissionNo': 'ADM-${_nn(n)}',
        'className': className, 'feeStructureName': 'Core Fees', 'amount': 10, 'paymentMode': n % 3 == 0 ? 'upi' : 'cash',
        'referenceNo': n == 6 ? 'UTR-778899' : '',
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
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, _List list) => tapAndSettle(tester, find.widgetWithText(ChoiceChip, list.chip));
  Finder searchBox(_List list) => find.byKey(Key('fees-${list.key}-search'));
  Future<void> search(WidgetTester tester, _List list, String text) async {
    await tester.enterText(searchBox(list), text);
    await tester.pumpAndSettle();
  }

  Future<void> clear(WidgetTester tester, _List list) => tapAndSettle(tester, find.byKey(Key('fees-${list.key}-search-clear')));
  String query(WidgetTester tester, _List list) => tester.widget<TextField>(searchBox(list)).controller!.text;

  List<String> shown(WidgetTester tester, _List list) =>
      tester.widgetList<Text>(find.textContaining(RegExp(list.titlePattern))).map((t) => t.data!).toList();
  List<String> students(Iterable<int> ns) => [for (final n in ns) 'Student ${_nn(n)}'];
  List<String> structures(Iterable<int> ns) => [for (final n in ns) 'Structure ${_nn(n)}'];
  List<String> receipts(Iterable<int> ns) => [for (final n in ns) 'REC-${_nn(n)}'];

  Finder next() => find.byTooltip('Next page');
  Future<void> choosePageSize(WidgetTester tester, _List list, int size) async {
    await tapAndSettle(tester, find.byKey(Key('fees-${list.key}-page-size')));
    await tester.tap(find.text('$size').last);
    await tester.pumpAndSettle();
  }

  int pageSize(WidgetTester tester, _List list) => tester.widget<DropdownButton<int>>(find.byKey(Key('fees-${list.key}-page-size'))).value!;

  /// Summary over all 27 assignments, as in the pagination test.
  void expectSummary() {
    expect(find.text('₹37,800'), findsOneWidget); // Total Expected
    expect(find.text('₹18,200'), findsOneWidget); // Total Collected
    expect(find.text('₹19,600'), findsOneWidget); // Outstanding
  }

  group('1. fields, case and trimming', () {
    testWidgets('Structures: name, description, academic year, frequency', (tester) async {
      await seed();
      await pumpFees(tester);
      await search(tester, _structures, '  STRUCTURE 2  ');
      expect(shown(tester, _structures), structures([27, 26, 25, 24, 23, 22, 21, 20]));
      await search(tester, _structures, 'transport');
      expect(shown(tester, _structures), structures([5]));
      await search(tester, _structures, '2025-2026');
      expect(find.text('Showing 1–10 of 14'), findsOneWidget);
      await search(tester, _structures, 'MONTHLY');
      expect(shown(tester, _structures), structures([7]));
      expectSummary();
    });

    testWidgets('Assignments: student, admission no., class, structure, year, status', (tester) async {
      await seed();
      await pumpFees(tester);
      await openTab(tester, _assignments);
      await search(tester, _assignments, 'adm-03');
      expect(shown(tester, _assignments), students([3]));
      await search(tester, _assignments, ' Mont 2 ');
      expect(shown(tester, _assignments), students([27, 24, 21, 18, 15, 12, 9, 6, 3]));
      await search(tester, _assignments, 'transport FEES');
      expect(shown(tester, _assignments), students([4]));
      await search(tester, _assignments, '2025-2026');
      expect(shown(tester, _assignments), students([9]));
      await search(tester, _assignments, 'UNPAID');
      expect(find.text('Showing 1–10 of 14'), findsOneWidget);
      expectSummary();
    });

    testWidgets('Collections and Dues: assignment fields, within the balance-due rows only', (tester) async {
      await seed();
      await pumpFees(tester);
      for (final list in [_collections, _dues]) {
        await openTab(tester, list);
        await search(tester, list, 'MONT 2');
        expect(shown(tester, list), students([27, 21, 15, 9, 3]));
        await search(tester, list, ' adm-1 ');
        expect(shown(tester, list), students([19, 17, 15, 13, 11]));
        await search(tester, list, 'transport'); // assignment 4 is fully paid
        expect(find.text('No ${list.noun} match "transport".'), findsOneWidget);
      }
      expectSummary();
    });

    testWidgets('Receipts: receipt no., student, mode, reference', (tester) async {
      await seed();
      await pumpFees(tester);
      await openTab(tester, _receipts);
      await search(tester, _receipts, 'rec-12');
      expect(shown(tester, _receipts), receipts([12]));
      await search(tester, _receipts, 'UPI');
      expect(shown(tester, _receipts), receipts([27, 24, 21, 18, 15, 12, 9, 6, 3]));
      await search(tester, _receipts, '  utr-778899 ');
      expect(shown(tester, _receipts), receipts([6]));
      await search(tester, _receipts, 'student 1');
      expect(shown(tester, _receipts), receipts([19, 18, 17, 16, 15, 14, 13, 12, 11, 10]));
      await search(tester, _receipts, 'adm-2');
      expect(find.text('Showing 1–8 of 8'), findsOneWidget);
      expectSummary();
    });
  });

  for (final list in _all) {
    group(list.chip, () {
      testWidgets('2 + 3 + 4. no-match, Clear, paging of matches, page 1 on query change, page size kept', (tester) async {
        await seed();
        await pumpFees(tester);
        if (list != _structures) await openTab(tester, list);

        await search(tester, list, 'no such thing');
        expect(find.text('No ${list.noun} match "no such thing".'), findsOneWidget);
        expect(find.byKey(Key('fees-${list.key}-pagination')), findsNothing);
        expect(shown(tester, list), isEmpty);
        await clear(tester, list);
        expect(query(tester, list), '');
        expect(find.byKey(Key('fees-${list.key}-search-clear')), findsNothing);
        expect(find.text('Showing 1–10 of ${list.total}'), findsOneWidget);

        await tapAndSettle(tester, next());
        expect(find.text('Page 2 of ${(list.total + 9) ~/ 10}'), findsOneWidget);
        await search(tester, list, list.matchAll); // same rows, new query
        expect(find.text('Page 1 of ${(list.total + 9) ~/ 10}'), findsOneWidget);
        await tapAndSettle(tester, next());
        expect(find.text('Showing 11–${list.total < 20 ? list.total : 20} of ${list.total}'), findsOneWidget);

        await choosePageSize(tester, list, 25);
        // A page that still exists is kept (existing pager rule).
        expect(find.text('Page ${list.total > 25 ? 2 : 1} of ${(list.total + 24) ~/ 25}'), findsOneWidget);
        await search(tester, list, 'zzz');
        expect(find.byKey(Key('fees-${list.key}-pagination')), findsNothing);
        await clear(tester, list);
        expect(pageSize(tester, list), 25);
        expect(find.text('Showing 1–${list.total < 25 ? list.total : 25} of ${list.total}'), findsOneWidget);
        expectSummary();
      });

      testWidgets('6. an empty list keeps its existing (blank) state: no search box, no controls', (tester) async {
        await pumpFees(tester);
        if (list != _structures) await openTab(tester, list);
        expect(searchBox(list), findsNothing);
        expect(find.byKey(Key('fees-${list.key}-pagination')), findsNothing);
        expect(find.textContaining('match "'), findsNothing);
      });
    });
  }

  testWidgets('4 + 5. each list keeps its own query and page across tabs; a query change resets only its list', (tester) async {
    await seed();
    await pumpFees(tester);
    await search(tester, _structures, '2025-2026'); // 14 matches
    await tapAndSettle(tester, next());
    expect(find.text('Page 2 of 2'), findsOneWidget);

    await openTab(tester, _receipts);
    expect(query(tester, _receipts), '');
    await tapAndSettle(tester, next());
    expect(find.text('Page 2 of 3'), findsOneWidget);

    await openTab(tester, _collections);
    await tapAndSettle(tester, next());
    expect(find.text('Page 2 of 2'), findsOneWidget);
    await openTab(tester, _dues);
    expect(query(tester, _dues), '', reason: 'independent of Collections');
    await search(tester, _dues, 'adm-1');
    expect(shown(tester, _dues), students([19, 17, 15, 13, 11]));

    await openTab(tester, _collections);
    expect(find.text('Page 2 of 2'), findsOneWidget, reason: 'Dues query change left Collections alone');
    expect(query(tester, _collections), '');
    await openTab(tester, _receipts);
    expect(find.text('Page 2 of 3'), findsOneWidget);
    await openTab(tester, _structures);
    expect(query(tester, _structures), '2025-2026');
    expect(find.text('Page 2 of 2'), findsOneWidget);
    await openTab(tester, _dues);
    expect(query(tester, _dues), 'adm-1');
    expect(shown(tester, _dues), students([19, 17, 15, 13, 11]));
    await openTab(tester, _assignments);
    expect(query(tester, _assignments), '');
    expect(find.text('Showing 1–10 of 27'), findsOneWidget);
    expectSummary();
  });

  group('8. actions on filtered rows', () {
    testWidgets('Structures: Edit opens; Delete removes the match and the query stays', (tester) async {
      await seed();
      await pumpFees(tester);
      await search(tester, _structures, 'structure 17');
      await tapAndSettle(tester, find.byTooltip('Edit'));
      expect(find.text('Edit Fee Structure'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(shown(tester, _structures), structures([17]));

      await tapAndSettle(tester, find.byTooltip('Delete'));
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect((await firestore.doc('fee_structures/s-17').get()).data()!['isDeleted'], isTrue);
      expect(query(tester, _structures), 'structure 17');
      expect(find.text('No fee structures match "structure 17".'), findsOneWidget);
    });

    testWidgets('Assignments / Collections / Dues: Delete on a match; Collect available on a match', (tester) async {
      await seed();
      await pumpFees(tester);
      await openTab(tester, _collections);
      await search(tester, _collections, 'adm-07');
      final collect = find.widgetWithText(TextButton, 'Collect');
      expect(collect, findsOneWidget);
      expect(tester.widget<TextButton>(collect).onPressed, isNotNull);
      await tapAndSettle(tester, find.byTooltip('Delete'));
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect((await firestore.doc('student_fee_assignments/a-07').get()).data()!['isDeleted'], isTrue);
      expect(find.text('No collections match "adm-07".'), findsOneWidget);

      await openTab(tester, _dues);
      await search(tester, _dues, 'student 05');
      await tapAndSettle(tester, find.byTooltip('Delete'));
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect((await firestore.doc('student_fee_assignments/a-05').get()).data()!['isDeleted'], isTrue);

      await openTab(tester, _assignments);
      await search(tester, _assignments, 'adm-1');
      expect(find.byTooltip('Edit'), findsNWidgets(10));
      expect(find.text('Showing 1–10 of 10'), findsOneWidget);
    });

    testWidgets('Receipts: Void on a match; the voided receipt leaves the results', (tester) async {
      await seed();
      await pumpFees(tester);
      await openTab(tester, _receipts);
      await search(tester, _receipts, 'REC-17');
      await tapAndSettle(tester, find.byIcon(Icons.more_vert));
      expect(find.text('View'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      await tester.tap(find.text('Void'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Void'));
      await tester.pumpAndSettle();
      expect((await firestore.doc('fee_receipts/r-17').get()).data()!['isDeleted'], isTrue);
      expect(find.text('No receipts match "REC-17".'), findsOneWidget);
      await clear(tester, _receipts);
      expect(find.text('Showing 1–10 of 26'), findsOneWidget);
    });
  });

  testWidgets('9. records added elsewhere appear in a matching search after a reload; other queries untouched', (tester) async {
    await seed();
    await pumpFees(tester);
    await openTab(tester, _receipts);
    await search(tester, _receipts, 'upi');
    await openTab(tester, _structures);
    await search(tester, _structures, 'transport');
    expect(shown(tester, _structures), structures([5]));

    await seedStructure(28, description: 'Transport (second bus)');
    await seedStructure(29, description: 'Library');
    // Any dialog closing reloads the screen's data.
    await tapAndSettle(tester, find.byTooltip('Edit'));
    await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
    await tester.pumpAndSettle();

    expect(query(tester, _structures), 'transport');
    expect(shown(tester, _structures), structures([28, 5]));
    await openTab(tester, _receipts);
    expect(query(tester, _receipts), 'upi');
    expect(shown(tester, _receipts), receipts([27, 24, 21, 18, 15, 12, 9, 6, 3]));
    expectSummary();
  });
}

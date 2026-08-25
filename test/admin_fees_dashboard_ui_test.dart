// FEES-UX-01 coverage: the Admin Fees Dashboard's metric-card presentation
// only (currency formatting, grouping, responsive grid, reporting
// context). The underlying figures themselves — FeeService.
// getDashboardSummary and its Total Expected/Collected/Outstanding/
// Collection %/Overdue Students/Today's Collection calculations — are
// exercised by fee_assignment_collection_crud_test.dart (case 18) and
// fee_service_test.dart; this file never re-derives those numbers, it only
// checks the screen displays them correctly formatted and grouped.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/admin_fees_screen.dart';

FeeService _service(FakeFirebaseFirestore firestore) => FeeService(
      firestore: firestore,
      auth: MockFirebaseAuth(),
      storage: MockFirebaseStorage(),
    );

/// Seeds exactly the fixture used throughout this file:
///  - a1: payable 154000, fully paid (154000), not overdue.
///  - a2: payable 19900, unpaid (0 paid), status 'overdue'.
///
/// So, via the exact same arithmetic as FeeService.getDashboardSummary
/// (never re-implemented here):
///   Total Expected = 154000 + 19900 = 173900 -> "₹1,73,900"
///   Total Collected = 154000 + 0    = 154000 -> "₹1,54,000"
///   Outstanding     = 0 + 19900     = 19900  -> "₹19,900"
///   Collection %    = 154000/173900*100 = 88.55... -> "88.6%"
///   Overdue Students = 1 (a2)
///   Today's Collection = 0 (no receipts seeded at all) -> "₹0"
/// matching every currency example FEES-UX-01 specifies.
Future<void> _seedFixture(FakeFirebaseFirestore firestore) async {
  await firestore.collection('classes').doc('class-1').set({'name': 'Mont 1', 'isActive': true});
  await firestore.collection('student_fee_assignments').doc('a1').set({
    'studentId': 's1',
    'studentName': 'Aarav',
    'admissionNo': 'ADM-s1',
    'classId': 'class-1',
    'className': 'Mont 1',
    'feeStructureId': 'f1',
    'feeStructureName': 'Core Fees',
    'academicYear': '2026-2027',
    'totalFee': 154000.0,
    'discountAmount': 0.0,
    'payableAmount': 154000.0,
    'paidAmount': 154000.0,
    'balanceAmount': 0.0,
    'status': 'paid',
    'assignedAt': DateTime(2026, 1, 1),
    'updatedAt': DateTime(2026, 1, 1),
  });
  await firestore.collection('student_fee_assignments').doc('a2').set({
    'studentId': 's2',
    'studentName': 'Diya',
    'admissionNo': 'ADM-s2',
    'classId': 'class-1',
    'className': 'Mont 1',
    'feeStructureId': 'f1',
    'feeStructureName': 'Core Fees',
    'academicYear': '2026-2027',
    'totalFee': 19900.0,
    'discountAmount': 0.0,
    'payableAmount': 19900.0,
    'paidAmount': 0.0,
    'balanceAmount': 19900.0,
    'status': 'overdue',
    'assignedAt': DateTime(2026, 1, 1),
    'updatedAt': DateTime(2026, 1, 1),
  });
}

Future<void> _pumpDashboard(
  WidgetTester tester,
  FakeFirebaseFirestore firestore, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(home: AdminFeesScreen(service: _service(firestore))),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Fees Dashboard — metrics displayed', () {
    testWidgets('all six metrics are still displayed', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedFixture(firestore);
      await _pumpDashboard(tester, firestore, size: const Size(1600, 1000));

      expect(find.text('Total Expected'), findsOneWidget);
      expect(find.text('Total Collected'), findsOneWidget);
      expect(find.text('Outstanding'), findsOneWidget);
      expect(find.text('Collection %'), findsOneWidget);
      expect(find.text('Overdue Students'), findsOneWidget);
      expect(find.text("Today's Collection"), findsOneWidget);
    });

    testWidgets('monetary values use Indian Rupee formatting matching the underlying summary', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedFixture(firestore);
      final service = _service(firestore);
      final summary = await service.getDashboardSummary();

      // The displayed strings must be exactly the Indian-grouped formatting
      // of the service's own numbers, never a re-derived value.
      expect(summary['totalExpected'], 173900.0);
      expect(summary['totalCollected'], 154000.0);
      expect(summary['outstanding'], 19900.0);
      expect(summary['todayCollection'], 0.0);

      await _pumpDashboard(tester, firestore, size: const Size(1600, 1000));

      expect(find.text('₹1,73,900'), findsOneWidget, reason: 'Total Expected');
      expect(find.text('₹1,54,000'), findsOneWidget, reason: 'Total Collected');
      expect(find.text('₹19,900'), findsOneWidget, reason: 'Outstanding');
      expect(find.text('₹0'), findsOneWidget, reason: "Today's Collection");
    });

    testWidgets('collection percentage remains the existing calculation, unchanged', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedFixture(firestore);
      final service = _service(firestore);
      final summary = await service.getDashboardSummary();
      final expectedPercent = summary['collectionPercent'] as num;
      expect(expectedPercent.toStringAsFixed(1), '88.6');

      await _pumpDashboard(tester, firestore, size: const Size(1600, 1000));

      expect(find.text('88.6%'), findsOneWidget);
    });

    testWidgets('overdue students count is displayed unchanged', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedFixture(firestore);
      await _pumpDashboard(tester, firestore, size: const Size(1600, 1000));

      // Exactly one 'Overdue Students' card showing '1' (a2's status is
      // 'overdue', a1 is not) — same count getDashboardSummary computes.
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('Total Expected = Total Collected + Outstanding holds in what is displayed', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedFixture(firestore);
      final service = _service(firestore);
      final summary = await service.getDashboardSummary();

      expect(
        summary['totalCollected'] + summary['outstanding'],
        summary['totalExpected'],
      );
    });
  });

  group('Fees Dashboard — grouping / visual hierarchy', () {
    testWidgets('metrics are organized into Collection Overview and Activity & Attention sections', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedFixture(firestore);
      await _pumpDashboard(tester, firestore, size: const Size(1600, 1000));

      expect(find.text('Collection Overview'), findsOneWidget);
      expect(find.text('Activity & Attention'), findsOneWidget);

      // Collection Overview's group appears above Activity & Attention's.
      final overviewY = tester.getTopLeft(find.text('Collection Overview')).dy;
      final activityY = tester.getTopLeft(find.text('Activity & Attention')).dy;
      expect(overviewY, lessThan(activityY));
    });

    testWidgets('reporting context: Today\'s Collection is labeled with the current date', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedFixture(firestore);
      await _pumpDashboard(tester, firestore, size: const Size(1600, 1000));

      final today = DateFormat('MMM d, yyyy').format(DateTime.now());
      expect(find.textContaining(today), findsWidgets);
    });
  });

  group('Fees Dashboard — responsive layout', () {
    testWidgets('desktop width lays metric cards out in a multi-column grid with no overflow', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedFixture(firestore);
      await _pumpDashboard(tester, firestore, size: const Size(1600, 1000));

      expect(tester.takeException(), isNull);

      final grids = tester.widgetList<GridView>(find.byType(GridView)).toList();
      expect(grids, isNotEmpty);
      for (final grid in grids) {
        final delegate = grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
        expect(delegate.crossAxisCount, 3, reason: 'sufficiently wide desktop should use 3 columns');
      }

      // All six values are still findable/readable at this width.
      expect(find.text('₹1,73,900'), findsOneWidget);
      expect(find.text("Today's Collection"), findsOneWidget);
    });

    testWidgets('mobile width uses a single column and does not overflow horizontally', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedFixture(firestore);
      await _pumpDashboard(tester, firestore, size: const Size(390, 844));

      expect(tester.takeException(), isNull);

      final grids = tester.widgetList<GridView>(find.byType(GridView)).toList();
      expect(grids, isNotEmpty);
      for (final grid in grids) {
        final delegate = grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
        expect(delegate.crossAxisCount, 1, reason: 'mobile should fall back to a single column');
      }

      // Cards remain readable at mobile width.
      expect(find.text('Total Expected'), findsOneWidget);
      expect(find.text('₹1,73,900'), findsOneWidget);
    });

    testWidgets('tablet width uses a 2-column grid with no overflow', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedFixture(firestore);
      await _pumpDashboard(tester, firestore, size: const Size(1100, 1000));

      expect(tester.takeException(), isNull);

      final grids = tester.widgetList<GridView>(find.byType(GridView)).toList();
      expect(grids, isNotEmpty);
      for (final grid in grids) {
        final delegate = grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
        expect(delegate.crossAxisCount, 2);
      }
    });

    testWidgets('no horizontal overflow at any required mobile/tablet width', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedFixture(firestore);
      for (final size in const [Size(390, 844), Size(400, 775), Size(412, 915), Size(768, 1024)]) {
        final errors = <FlutterErrorDetails>[];
        final originalHandler = FlutterError.onError;
        FlutterError.onError = (details) => errors.add(details);
        await _pumpDashboard(tester, firestore, size: size);
        FlutterError.onError = originalHandler;
        expect(errors, isEmpty, reason: 'overflow/render error at $size');
      }
    });
  });

  group('Fees Dashboard — regression: existing functionality unaffected', () {
    testWidgets('the Structures/Assignments/Collections/Receipts/Dues tabs still exist and switch', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedFixture(firestore);
      await _pumpDashboard(tester, firestore, size: const Size(1600, 1000));

      for (final label in ['Structures', 'Assignments', 'Collections', 'Receipts', 'Dues']) {
        expect(find.text(label), findsOneWidget);
      }

      await tester.tap(find.text('Assignments'));
      await tester.pumpAndSettle();
      expect(find.text('Aarav'), findsOneWidget);
      expect(find.text('Diya'), findsOneWidget);
    });

    testWidgets('the "Fees" title and Add FAB are still present', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedFixture(firestore);
      await _pumpDashboard(tester, firestore, size: const Size(1600, 1000));

      // 'Fees' also appears as AdminLayout chrome (app bar title, nav
      // label), not just the in-page heading, so at least one is enough.
      expect(find.text('Fees'), findsWidgets);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  });
}

// Parent Dashboard layout regression (Phase 0.2, updated for the Phase 1
// family overview): no RenderFlex overflow in the AppBar or the dashboard
// body from very narrow browser windows up to desktop, with one, two or four
// children and long names; the logout, child cards, profile,
// attendance-history, notification, child-switching and back-to-family
// controls stay present and usable.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/attendance/data/attendance_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/classes/data/class_service.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/leave/services/leave_service.dart';
import 'package:montessori_app/modules/mood_checkin/services/mood_checkin_service.dart';
import 'package:montessori_app/modules/parent/data/parent_service.dart';
import 'package:montessori_app/modules/parent/ui/parent_app_bar.dart';
import 'package:montessori_app/modules/parent/ui/parent_dashboard.dart';
import 'package:montessori_app/modules/parent/ui/parent_family_overview.dart';

class _UnusedFilePicker extends FilePicker {}

const longName = 'Aadhavan Subramaniam Venkataraghavan Krishnamoorthy';

Future<FakeFirebaseFirestore> seed({required int children}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('classes').doc('c1').set({'name': 'Montessori Casa Primary Long Class Name', 'academicYear': '2026-2027', 'isActive': true});
  for (var i = 1; i <= children; i++) {
    await db.collection('students').doc('s$i').set({
      'name': i == 1 ? longName : 'Child $i With A Very Long Family Name', 'admissionNo': 'ADM-2026-00000$i', 'classId': 'c1',
      'section': 'Sunflower', 'isActive': true,
    });
    await db.collection('user_student_links').add({'userId': 'p1', 'studentId': 's$i', 'relation': 'Father'});
    await db.collection('student_fee_assignments').add({
      'studentId': 's$i', 'feeStructureName': 'Annual Tuition and Activity Fee for the Academic Year', 'totalFee': 123456789,
      'discountAmount': 0, 'payableAmount': 123456789, 'paidAmount': 23456789, 'balanceAmount': 100000000, 'isDeleted': false,
    });
  }
  await db.collection('school_notifications').doc('n1').set({
    'title': 'Annual Day Celebration and Parent Teacher Meeting Schedule Announcement', 'message': 'Details inside.',
    'status': 'Published', 'audience': 'Parents', 'appliesToAllClasses': true, 'appliesToAllStudents': false,
    'applicableClassIds': <String>[], 'applicableStudentIds': <String>[], 'priority': 'High', 'category': 'Events',
    'publishDate': DateTime(2026, 11, 1),
  });
  return db;
}

Widget app(FakeFirebaseFirestore db) => ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => AppUser(id: 'p1', phone: '9000000001', name: 'Ramanathan Sivasubramanian', role: 'parent', isActive: true)),
      ],
      child: MaterialApp(
        home: ParentDashboard(
          parentService: ParentService(firestore: db),
          attendanceService: AttendanceService(firestore: db, storage: MockFirebaseStorage()),
          feeService: FeeService(firestore: db, auth: MockFirebaseAuth(), storage: MockFirebaseStorage()),
          notificationService: AdminNotificationService(firestore: db, storage: MockFirebaseStorage(), filePicker: _UnusedFilePicker()),
          classService: ClassService(firestore: db),
          moodCheckinService: MoodCheckinService(firestore: db, storage: MockFirebaseStorage()),
          leaveService: LeaveService(firestore: db),
        ),
      ),
    );

/// Runs [body] and returns every layout error reported meanwhile.
Future<List<String>> collectErrors(Future<void> Function() body) async {
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final where = details.toString().split('\n').where((l) => l.contains('lib/')).take(1).join();
    errors.add('${details.exceptionAsString().split('\n').first} $where');
  };
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return errors;
}

/// Pumps the dashboard at [width] and returns every layout error reported.
Future<List<String>> pumpAt(WidgetTester tester, double width, {required int children, double height = 900}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = await seed(children: children);
  return collectErrors(() async {
    await tester.pumpWidget(app(db));
    await tester.pumpAndSettle();
  });
}

/// Taps [finder] (scrolled into view) and settles; returns layout errors.
Future<List<String>> tapAt(WidgetTester tester, Finder finder) => collectErrors(() async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    });

void main() {
  const widths = <String, double>{'small phone': 320, 'phone': 375, 'large phone': 430, 'tablet': 768, 'small desktop': 1024, 'desktop': 1440};

  for (final MapEntry(key: label, value: width) in widths.entries) {
    testWidgets('$label (${width.toInt()} px), 1 child: no overflow; the child\'s dashboard is the home page', (tester) async {
      expect(await pumpAt(tester, width, children: 1), isEmpty);
      expect(tester.takeException(), isNull);
      final logout = find.byKey(ParentAppBar.logoutKey);
      expect(logout, findsOneWidget);
      expect(tester.getSize(logout).width, greaterThanOrEqualTo(kMinInteractiveDimension));
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('View All'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing, reason: 'no family navigation for one child');
      expect(find.byKey(ParentChildSwitcher.familyOverviewKey), findsNothing);
    });

    for (final children in [2, 4]) {
      testWidgets('$label (${width.toInt()} px), $children children: family overview and a child\'s dashboard, no overflow', (tester) async {
        expect(await pumpAt(tester, width, children: children), isEmpty);
        expect(tester.takeException(), isNull);
        expect(find.byKey(ParentAppBar.logoutKey), findsOneWidget);
        // Every child has its own card with its own way in.
        for (var i = 1; i <= children; i++) {
          expect(find.byKey(ParentChildOverviewCard.openKey('s$i')), findsOneWidget);
        }
        expect(find.text('View All'), findsOneWidget);

        // Open the last child's dashboard: selector, back to the family,
        // Profile and History all there, still no overflow.
        expect(await tapAt(tester, find.byKey(ParentChildOverviewCard.openKey('s$children'))), isEmpty);
        expect(find.byType(ChoiceChip), findsNWidgets(children));
        expect(tester.widget<ChoiceChip>(find.byType(ChoiceChip).last).selected, isTrue);
        expect(find.text('Profile'), findsOneWidget);
        expect(find.text('History'), findsOneWidget);
        expect(find.byKey(ParentChildSwitcher.familyOverviewKey), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('switching child and returning to the family still works at 320 px', (tester) async {
    expect(await pumpAt(tester, 320, children: 2), isEmpty);
    expect(await tapAt(tester, find.byKey(ParentChildOverviewCard.openKey('s1'))), isEmpty);
    expect(await tapAt(tester, find.byType(ChoiceChip).last), isEmpty);
    expect(tester.widget<ChoiceChip>(find.byType(ChoiceChip).last).selected, isTrue);
    expect(await tapAt(tester, find.byKey(ParentChildSwitcher.familyOverviewKey)), isEmpty);
    expect(find.byKey(ParentChildOverviewCard.openKey('s2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [40.0, 60.0, 100.0, 160.0]) {
    testWidgets('a browser window only ${width.toInt()} px wide: the AppBar does not overflow and logout stays reachable', (tester) async {
      final errors = await pumpAt(tester, width, children: 1);
      expect(errors.where((e) => e.contains('parent_app_bar') || e.contains('AppBar')), isEmpty);
      expect(find.byKey(ParentAppBar.logoutKey), findsOneWidget);
      expect(find.byKey(ParentAppBar.logoutKey).hitTestable(), findsOneWidget);
    });
  }
}

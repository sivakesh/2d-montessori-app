// A parent account with no linked child has no notification access: once
// the lookup has succeeded and found none, the dashboard shows no
// Notifications section, no View All and no notifications button, never
// opens the Notifications screen, and never queries parent notifications.
// While loading nothing is exposed early; a failed lookup keeps its error
// and Retry (and is never treated as "unlinked"); linked parents (one
// child, two, or a Guardian) and other roles keep notifications as before.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/admin/notifications/models/admin_notification_model.dart';
import 'package:montessori_app/modules/attendance/data/attendance_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/calendar/services/calendar_service.dart';
import 'package:montessori_app/modules/classes/data/class_service.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/leave/services/leave_service.dart';
import 'package:montessori_app/modules/mood_checkin/services/mood_checkin_service.dart';
import 'package:montessori_app/modules/parent/data/parent_access_service.dart';
import 'package:montessori_app/modules/parent/data/parent_link_service.dart';
import 'package:montessori_app/modules/parent/data/parent_projection_service.dart';
import 'package:montessori_app/modules/parent/data/parent_service.dart';
import 'package:montessori_app/modules/parent/ui/parent_dashboard.dart';
import 'package:montessori_app/modules/parent/ui/parent_family_overview.dart';
import 'package:montessori_app/modules/parent/ui/parent_notifications_screen.dart';

class _UnusedFilePicker extends FilePicker {}

/// The real service, counting the parent-notification queries.
class _CountingNotifications extends AdminNotificationService {
  _CountingNotifications(FirebaseFirestore db) : super(firestore: db, storage: MockFirebaseStorage(), filePicker: _UnusedFilePicker());
  int queries = 0;
  @override
  Future<List<AdminNotificationModel>> getNotificationsForParent({required String parentUserId, required Set<String> childStudentIds, Set<String> childClassIds = const {}}) {
    queries++;
    return super.getNotificationsForParent(parentUserId: parentUserId, childStudentIds: childStudentIds, childClassIds: childClassIds);
  }
}

/// A family lookup held until [release] (loading), or failing.
class _HeldParentService extends ParentService {
  _HeldParentService(FirebaseFirestore db, {this.fail = false}) : super(firestore: db);
  final bool fail;
  final gate = Completer<void>();
  void release() => gate.complete();
  @override
  Future<ParentFamily> getFamily(String parentUserId) async {
    if (fail) throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
    await gate.future;
    return super.getFamily(parentUserId);
  }
}

const _unlinked = '9000000077';
const _father = '9000000001';
const _guardian = '9000000003';
const _title = 'Your account is not linked to a student yet';

AppUser _user(String id, String role) => AppUser(id: id, phone: id, name: 'Test', role: role, isActive: true);

/// One class; [_father] is the father of one child (or two), [_guardian]
/// the first child's Guardian.
Future<FakeFirebaseFirestore> school({bool twoChildren = false}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
  final links = ParentLinkService(firestore: db);
  for (final (id, name) in [('s1', 'Anu Raman'), if (twoChildren) ('s2', 'Bala Raman')]) {
    await db.collection('students').doc(id).set({'name': name, 'admissionNo': 'ADM-$id', 'classId': 'c1', 'section': 'Rose', 'isActive': true});
    await links.saveLinksForStudent(studentId: id, parents: [
      const ParentLinkEntry(userId: _father, relation: 'Father', name: 'Ravi', phone: _father),
      if (id == 's1') const ParentLinkEntry(userId: _guardian, relation: 'Guardian', name: 'Kala', phone: _guardian),
    ]);
  }
  final access = ParentAccessService(firestore: db);
  await access.apply(await access.preview(requesterRole: 'admin'), requesterRole: 'admin', updatedBy: 'admin');
  await ParentProjectionService(firestore: db).syncAll(requesterRole: 'admin');
  return db;
}

void main() {
  Finder key(String k) => find.byKey(Key(k));
  final viewAll = find.text('View All');
  final bell = find.byKey(ParentFamilyHeader.notificationsKey);
  final section = find.text('Notifications');

  late _CountingNotifications notifications;

  Future<void> pump(WidgetTester tester, FakeFirebaseFirestore db, AppUser user, {ParentService? parentService, bool settle = true}) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(currentUserProvider.notifier).state = user;
    notifications = _CountingNotifications(db);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: ParentDashboard(
          parentService: parentService ?? ParentService(firestore: db),
          attendanceService: AttendanceService(firestore: db, storage: MockFirebaseStorage()),
          feeService: FeeService(firestore: db, auth: MockFirebaseAuth(), storage: MockFirebaseStorage()),
          notificationService: notifications,
          classService: ClassService(firestore: db),
          moodCheckinService: MoodCheckinService(firestore: db, storage: MockFirebaseStorage()),
          leaveService: LeaveService(firestore: db, parentService: ParentService(firestore: db)),
          calendarService: CalendarService(firestore: db),
        ),
      ),
    ));
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Notifications available: the section, View All and the bell, which
  /// opens the Notifications screen.
  Future<void> expectNotifications(WidgetTester tester) async {
    expect(section, findsWidgets);
    expect(viewAll, findsOneWidget);
    expect(bell, findsOneWidget);
    expect(notifications.queries, 1);
    await tester.tap(viewAll);
    await tester.pumpAndSettle();
    expect(find.byType(ParentNotificationsScreen), findsOneWidget);
  }

  group('a parent with no linked child', () {
    testWidgets('no Notifications section, no View All, no notifications button', (tester) async {
      await pump(tester, await school(), _user(_unlinked, 'parent'));
      expect(find.text(_title), findsOneWidget);
      expect(section, findsNothing);
      expect(viewAll, findsNothing);
      expect(bell, findsNothing);
      expect(find.byTooltip('Notifications'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Notifications screen cannot be opened (no way in on the dashboard)', (tester) async {
      await pump(tester, await school(), _user(_unlinked, 'parent'));
      for (final f in [viewAll, bell, find.byTooltip('Notifications'), find.text('School notices')]) {
        expect(f, findsNothing);
      }
      // Pull to refresh reloads, still without access.
      await tester.fling(find.byType(SingleChildScrollView).first, const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.byType(ParentNotificationsScreen), findsNothing);
      expect(find.text(_title), findsOneWidget);
      expect(bell, findsNothing);
    });

    testWidgets('no parent notification query is issued', (tester) async {
      await pump(tester, await school(), _user(_unlinked, 'parent'));
      expect(notifications.queries, 0);
    });
  });

  testWidgets('one linked child: notifications as before', (tester) async {
    await pump(tester, await school(), _user(_father, 'parent'));
    expect(find.text(_title), findsNothing);
    expect(key('parent-summary-outstanding'), findsOneWidget, reason: 'a Father has finance access');
    await expectNotifications(tester);
  });

  testWidgets('two linked children: notifications as before', (tester) async {
    await pump(tester, await school(twoChildren: true), _user(_father, 'parent'));
    expect(find.text('Bala Raman'), findsWidgets);
    await expectNotifications(tester);
  });

  testWidgets('a Guardian (linked): notifications as before; Guardian restrictions unchanged (no fees)', (tester) async {
    await pump(tester, await school(), _user(_guardian, 'parent'));
    expect(find.text(_title), findsNothing);
    expect(find.text('Anu Raman'), findsWidgets);
    expect(key('parent-summary-outstanding'), findsNothing, reason: 'Guardian has no finance access');
    await expectNotifications(tester);
  });

  testWidgets('while loading: nothing hidden or exposed early, no query; then a linked parent gets notifications', (tester) async {
    final db = await school();
    final held = _HeldParentService(db);
    await pump(tester, db, _user(_father, 'parent'), parentService: held, settle: false);
    await frames(tester);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.text(_title), findsNothing);
    expect(viewAll, findsNothing);
    expect(bell, findsNothing);
    expect(notifications.queries, 0);
    held.release();
    await tester.pumpAndSettle();
    await expectNotifications(tester);
  });

  testWidgets('the lookup fails: the existing error and Retry, not "unlinked" (notifications kept as before)', (tester) async {
    final db = await school();
    await pump(tester, db, _user(_unlinked, 'parent'), parentService: _HeldParentService(db, fail: true));
    expect(key('parent-family-error'), findsOneWidget);
    expect(key('parent-family-retry'), findsOneWidget);
    expect(find.text(_title), findsNothing);
    expect(bell, findsOneWidget);
    expect(viewAll, findsOneWidget);
  });

  for (final role in ['admin', 'staff', 'user']) {
    testWidgets('role $role shown this dashboard unlinked: notifications unchanged', (tester) async {
      await pump(tester, await school(), _user(_unlinked, role));
      expect(find.text(_title), findsNothing);
      expect(bell, findsOneWidget);
      expect(viewAll, findsOneWidget);
      expect(notifications.queries, 1);
    });
  }
}

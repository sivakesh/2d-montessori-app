// A parent account signed in but not linked to any child: the dashboard
// says so plainly (contact the school administrator) only once the lookup
// has succeeded and found none — never while loading, never when the
// lookup failed (that is an error with Retry), never for a linked parent,
// and only in the parent wording for a parent account. Opened before the
// session user is set, the dashboard keeps loading and loads once it is.
import 'package:cloud_firestore/cloud_firestore.dart';
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

class _UnusedFilePicker extends FilePicker {}

/// A family lookup that fails (an unreadable access record, or the network)
/// until [failing] is turned off.
class _FailingParentService extends ParentService {
  _FailingParentService(FirebaseFirestore db) : super(firestore: db);
  bool failing = true;
  @override
  Future<ParentFamily> getFamily(String parentUserId) {
    if (failing) throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
    return super.getFamily(parentUserId);
  }
}

class _OfflineClasses extends ClassService {
  _OfflineClasses(FirebaseFirestore db) : super(firestore: db);
  @override
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getClasses() => Future.error(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
}

const _parent = '9000000077';
const _linked = '9000000001';
const _title = 'Your account is not linked to a student yet';

AppUser _user(String id, String role) => AppUser(id: id, phone: id, name: 'Test', role: role, isActive: true);

/// A school with one class; [_linked] is the father of one child (or two).
Future<FakeFirebaseFirestore> school({bool twoChildren = false}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('classes').doc('c1').set({'name': 'Mont 1', 'isActive': true});
  final links = ParentLinkService(firestore: db);
  for (final (id, name) in [('s1', 'Anu Raman'), if (twoChildren) ('s2', 'Bala Raman')]) {
    await db.collection('students').doc(id).set({'name': name, 'admissionNo': 'ADM-$id', 'classId': 'c1', 'section': 'Rose', 'isActive': true});
    await links.saveLinksForStudent(studentId: id, parents: const [ParentLinkEntry(userId: _linked, relation: 'Father', name: 'Ravi', phone: _linked)]);
  }
  final access = ParentAccessService(firestore: db);
  await access.apply(await access.preview(requesterRole: 'admin'), requesterRole: 'admin', updatedBy: 'admin');
  await ParentProjectionService(firestore: db).syncAll(requesterRole: 'admin');
  return db;
}

Widget app(FakeFirebaseFirestore db, ProviderContainer container, {ParentService? parentService, ClassService? classService}) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: ParentDashboard(
          parentService: parentService ?? ParentService(firestore: db),
          attendanceService: AttendanceService(firestore: db, storage: MockFirebaseStorage()),
          feeService: FeeService(firestore: db, auth: MockFirebaseAuth(), storage: MockFirebaseStorage()),
          notificationService: AdminNotificationService(firestore: db, storage: MockFirebaseStorage(), filePicker: _UnusedFilePicker()),
          classService: classService ?? ClassService(firestore: db),
          moodCheckinService: MoodCheckinService(firestore: db, storage: MockFirebaseStorage()),
          leaveService: LeaveService(firestore: db, parentService: ParentService(firestore: db)),
          calendarService: CalendarService(firestore: db),
        ),
      ),
    );

void main() {
  Finder key(String k) => find.byKey(Key(k));

  ProviderContainer signedIn(AppUser? user) {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(currentUserProvider.notifier).state = user;
    return c;
  }

  Future<void> size(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('a parent with no linked child: the contact-the-administrator message, once loaded (not while loading)', (tester) async {
    await size(tester);
    final db = await school();
    await tester.pumpWidget(app(db, signedIn(_user(_parent, 'parent'))));
    expect(find.text(_title), findsNothing, reason: 'still loading');
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    await tester.pumpAndSettle();
    expect(find.text(_title), findsOneWidget);
    expect(find.textContaining('Your login was successful'), findsOneWidget);
    expect(find.textContaining('contact the school administrator'), findsOneWidget);
    expect(find.textContaining('Once your account is linked'), findsOneWidget);
    expect(key('parent-family-error'), findsNothing);
    expect(find.textContaining(_linked), findsNothing, reason: 'nothing about other families');
    expect(find.text('Anu Raman'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the access lookup fails: an error with Retry, never "not linked"; Retry loads', (tester) async {
    await size(tester);
    final db = await school();
    final service = _FailingParentService(db);
    await tester.pumpWidget(app(db, signedIn(_user(_linked, 'parent')), parentService: service));
    await tester.pumpAndSettle();
    expect(key('parent-family-error'), findsOneWidget);
    expect(find.text(_title), findsNothing);
    service.failing = false;
    await tester.tap(key('parent-family-retry'));
    await tester.pumpAndSettle();
    expect(key('parent-family-error'), findsNothing);
    expect(find.text('Anu Raman'), findsWidgets, reason: 'the linked child');
  });

  testWidgets('the network fails: an error with Retry, never "not linked"', (tester) async {
    await size(tester);
    final db = await school();
    await tester.pumpWidget(app(db, signedIn(_user(_parent, 'parent')), classService: _OfflineClasses(db)));
    await tester.pumpAndSettle();
    expect(key('parent-family-error'), findsOneWidget);
    expect(key('parent-family-retry'), findsOneWidget);
    expect(find.text(_title), findsNothing);
  });

  testWidgets('a linked parent sees the dashboard (one child), or the family overview (two)', (tester) async {
    await size(tester);
    await tester.pumpWidget(app(await school(), signedIn(_user(_linked, 'parent'))));
    await tester.pumpAndSettle();
    expect(find.text(_title), findsNothing);
    expect(find.text('Anu Raman'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(await school(twoChildren: true), signedIn(_user(_linked, 'parent'))));
    await tester.pumpAndSettle();
    expect(find.text(_title), findsNothing);
    expect(find.text('Bala Raman'), findsWidgets);
  });

  testWidgets('another role shown this dashboard keeps the earlier wording, not the parent message', (tester) async {
    await size(tester);
    await tester.pumpWidget(app(await school(), signedIn(_user(_parent, 'user'))));
    await tester.pumpAndSettle();
    expect(find.text(_title), findsNothing);
    expect(find.text('No children linked to your account yet.'), findsOneWidget);
  });

  testWidgets('opened before the session user is set: keeps loading (no "not linked"), then loads for the user', (tester) async {
    await size(tester);
    final db = await school();
    final container = signedIn(null);
    await tester.pumpWidget(app(db, container));
    // Loading (an animated spinner never settles): a few frames.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(_title), findsNothing, reason: 'unknown yet: never "not linked"');
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    container.read(currentUserProvider.notifier).state = _user(_linked, 'parent');
    await tester.pumpAndSettle();
    expect(find.text('Anu Raman'), findsWidgets);
  });
}

// Parent Dashboard Phase 0 (docs/parent_access_security.md): the
// parent_access mapping, its reconciliation, and the parent queries that no
// longer download other families' records. The server-side half — the
// Firestore and Storage rules — is tested against the emulator by
// test/firebase_rules/parent_access_rules_test.py.
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
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/parent_fee_history_view.dart';
import 'package:montessori_app/modules/leave/services/leave_service.dart';
import 'package:montessori_app/modules/parent/data/parent_access.dart';
import 'package:montessori_app/modules/parent/data/parent_access_service.dart';
import 'package:montessori_app/modules/parent/data/parent_projection_service.dart';
import 'package:montessori_app/modules/parent/data/parent_service.dart';

class _UnusedFilePicker extends FilePicker {}

const father = '9000000001';
const mother = '9000000002';
const guardian = '9000000003';
const stranger = '9000000009';

Map<String, dynamic> student(String name, {List<Map<String, dynamic>> parentLinks = const []}) =>
    {'name': name, 'admissionNo': 'ADM-$name', 'classId': 'class-1', 'isActive': true, 'parentLinks': parentLinks};

Future<void> link(FakeFirebaseFirestore db, String userId, String studentId, [String? relation]) =>
    db.collection('user_student_links').add({'userId': userId, 'studentId': studentId, 'relation': ?relation});

Future<void> seedFamily(FakeFirebaseFirestore db) async {
  await db.collection('students').doc('s1').set(student('Anu'));
  await db.collection('students').doc('s2').set(student('Bala'));
  await db.collection('students').doc('s9').set(student('Other child'));
  for (final id in [father, mother, guardian, stranger]) {
    await db.collection('users').doc(id).set({'role': 'parent', 'isActive': true});
  }
  await link(db, father, 's1', 'Father');
  await link(db, father, 's2', 'Father');
  await link(db, mother, 's1', 'Mother');
  await link(db, guardian, 's1', 'Guardian');
  await link(db, stranger, 's9', 'Father');
}

void main() {
  group('buildParentAccessPlan', () {
    ParentAccessPlan plan(List<Map<String, dynamic>> links, Map<String, Map<String, dynamic>?> students, {Set<String>? users, bool all = false}) =>
        buildParentAccessPlan(links: links, students: students, userIds: users, checkParentLinksOnly: all);

    test('one parent with several children, several parents per child; only Father and Mother get fees', () {
      final p = plan([
        {'userId': father, 'studentId': 's1', 'relation': 'Father'},
        {'userId': father, 'studentId': 's2', 'relation': 'father'},
        {'userId': mother, 'studentId': 's1', 'relation': ' Mother '},
        {'userId': guardian, 'studentId': 's1', 'relation': 'Guardian'},
        {'userId': '9000000004', 'studentId': 's2', 'relation': 'Other'},
      ], {'s1': student('Anu'), 's2': student('Bala')});

      expect(p.records[father]!.studentIds, ['s1', 's2']);
      expect(p.records[father]!.financeStudentIds, ['s1', 's2']);
      expect(p.records[mother]!.financeStudentIds, ['s1']);
      expect(p.records[guardian]!.studentIds, ['s1']);
      expect(p.records[guardian]!.financeStudentIds, isEmpty);
      expect(p.records['9000000004']!.financeStudentIds, isEmpty);
      expect(p.records[guardian]!.relations, {'s1': 'Guardian'});
      expect(p.unresolved, isEmpty);
    });

    test('duplicate link records are reported (not deleted) and grant once', () {
      final p = plan([
        {'userId': father, 'studentId': 's1', 'relation': 'Father'},
        {'userId': father, 'studentId': 's1', 'relation': 'Father'},
      ], {'s1': student('Anu')});
      expect(p.records[father]!.studentIds, ['s1']);
      expect(p.records[father]!.financeStudentIds, ['s1']);
      expect(p.issues.single.kind, ParentAccessIssueKind.duplicateLink);
      expect(p.unresolved, isEmpty);
    });

    test('contradictory relationships keep the child linked but withhold fees, and are reported', () {
      final p = plan([
        {'userId': father, 'studentId': 's1', 'relation': 'Father'},
        {'userId': father, 'studentId': 's1', 'relation': 'Guardian'},
      ], {'s1': student('Anu')});
      expect(p.records[father]!.studentIds, ['s1']);
      expect(p.records[father]!.financeStudentIds, isEmpty);
      expect(p.records[father]!.relations['s1'], ParentRelation.unresolved);
      expect(p.unresolved.map((i) => i.kind), contains(ParentAccessIssueKind.conflictingRelation));
    });

    test('a missing relationship is taken from the student record when it has one, otherwise left unresolved', () {
      final p = plan([
        {'userId': mother, 'studentId': 's1'},
        {'userId': father, 'studentId': 's2'},
      ], {
        's1': student('Anu', parentLinks: [{'userId': mother, 'relation': 'Mother'}]),
        's2': student('Bala'),
      });
      expect(p.records[mother]!.financeStudentIds, ['s1']);
      expect(p.issues.where((i) => i.userId == mother).single.kind, ParentAccessIssueKind.relationFromStudentRecord);
      expect(p.records[father]!.studentIds, ['s2']);
      expect(p.records[father]!.financeStudentIds, isEmpty);
      expect(p.unresolved.single.kind, ParentAccessIssueKind.missingRelation);
    });

    test('link and student record disagreeing, or an unrecognised value, withholds fees', () {
      final p = plan([
        {'userId': father, 'studentId': 's1', 'relation': 'Father'},
        {'userId': mother, 'studentId': 's2', 'relation': 'xYz123'},
      ], {
        's1': student('Anu', parentLinks: [{'userId': father, 'relation': 'Guardian'}]),
        's2': student('Bala'),
      });
      expect(p.records[father]!.financeStudentIds, isEmpty);
      expect(p.records[mother]!.financeStudentIds, isEmpty);
      expect(p.unresolved.map((i) => i.kind).toSet(), {ParentAccessIssueKind.relationMismatch, ParentAccessIssueKind.unrecognizedRelation, ParentAccessIssueKind.missingRelation}.intersection({
        ParentAccessIssueKind.relationMismatch,
        ParentAccessIssueKind.unrecognizedRelation,
      }));
    });

    test('nothing is granted from a student record alone, or for a missing student; odd ids are reported', () {
      final p = plan(
        [
          {'userId': father, 'studentId': 'gone', 'relation': 'Father'},
          {'userId': 'uid-abc', 'studentId': 's1', 'relation': 'Mother'},
          {'userId': '', 'studentId': 's1'},
        ],
        {'s1': student('Anu', parentLinks: [{'userId': guardian, 'relation': 'Guardian'}]), 'gone': null},
        users: {father},
        all: true,
      );
      expect(p.records[father]!.studentIds, isEmpty);
      expect(p.records.containsKey(guardian), isFalse);
      final kinds = p.unresolved.map((i) => i.kind).toSet();
      expect(kinds, containsAll([
        ParentAccessIssueKind.missingStudent,
        ParentAccessIssueKind.parentLinksOnly,
        ParentAccessIssueKind.userIdNotPhone,
        ParentAccessIssueKind.missingUser,
        ParentAccessIssueKind.incompleteLink,
      ]));
    });
  });

  group('ParentAccessService', () {
    test('only an administrator can check, apply or rebuild', () async {
      final service = ParentAccessService(firestore: FakeFirebaseFirestore());
      expect(() => service.preview(requesterRole: 'parent'), throwsA(isA<ParentAccessDeniedException>()));
      expect(() => service.preview(requesterRole: 'staff'), throwsA(isA<ParentAccessDeniedException>()));
      expect(() => service.rebuildForParents({father}, requesterRole: 'parent', updatedBy: father), throwsA(isA<ParentAccessDeniedException>()));
    });

    test('apply writes the records, and applying again changes nothing (idempotent)', () async {
      final db = FakeFirebaseFirestore();
      await seedFamily(db);
      final service = ParentAccessService(firestore: db);

      final first = await service.apply(await service.preview(requesterRole: 'admin'), requesterRole: 'admin', updatedBy: 'admin-1');
      expect(first.written, 4);
      final again = await service.apply(await service.preview(requesterRole: 'admin'), requesterRole: 'admin', updatedBy: 'admin-1');
      expect((again.written, again.unchanged, again.cleared), (0, 4, 0));

      final fatherDoc = (await db.collection('parent_access').doc(father).get()).data()!;
      expect(fatherDoc['studentIds'], ['s1', 's2']);
      expect(fatherDoc['financeStudentIds'], ['s1', 's2']);
      expect((await db.collection('parent_access').doc(guardian).get()).data()!['financeStudentIds'], isEmpty);
    });

    test('a parent whose links were all removed is emptied, never left with access', () async {
      final db = FakeFirebaseFirestore();
      await seedFamily(db);
      final service = ParentAccessService(firestore: db);
      await service.apply(await service.preview(requesterRole: 'admin'), requesterRole: 'admin', updatedBy: 'a');

      for (final d in (await db.collection('user_student_links').where('userId', isEqualTo: guardian).get()).docs) {
        await d.reference.delete();
      }
      final result = await service.apply(await service.preview(requesterRole: 'admin'), requesterRole: 'admin', updatedBy: 'a');
      expect(result.cleared, 1);
      expect((await db.collection('parent_access').doc(guardian).get()).data()!['studentIds'], isEmpty);
    });

    test('rebuildForParents follows an admin link change (removed parent loses the child)', () async {
      final db = FakeFirebaseFirestore();
      await seedFamily(db);
      final service = ParentAccessService(firestore: db);
      await service.apply(await service.preview(requesterRole: 'admin'), requesterRole: 'admin', updatedBy: 'a');

      for (final d in (await db.collection('user_student_links').where('userId', isEqualTo: mother).get()).docs) {
        await d.reference.delete();
      }
      await link(db, mother, 's2', 'Mother');
      await service.rebuildForParents({mother}, requesterRole: 'admin', updatedBy: 'a');

      final doc = (await db.collection('parent_access').doc(mother).get()).data()!;
      expect(doc['studentIds'], ['s2']);
      expect(doc['financeStudentIds'], ['s2']);
    });
  });

  group('ParentService uses the access record', () {
    test('children and fee permission come from parent_access once it exists', () async {
      final db = FakeFirebaseFirestore();
      await seedFamily(db);
      final service = ParentAccessService(firestore: db);
      await service.apply(await service.preview(requesterRole: 'admin'), requesterRole: 'admin', updatedBy: 'a');
      await ParentProjectionService(firestore: db).syncAll(requesterRole: 'admin');
      // A link record added without an admin rebuild grants nothing.
      await link(db, guardian, 's9', 'Father');

      final children = await ParentService(firestore: db).getLinkedChildren(guardian);
      expect(children.map((c) => c.student.id), ['s1']);
      expect(children.single.canViewFinance, isFalse);
      expect(children.single.relation, 'Guardian');
      final fatherChildren = await ParentService(firestore: db).getLinkedChildren(father);
      expect({for (final c in fatherChildren) c.student.id: c.canViewFinance}, {'s1': true, 's2': true});
    });

    test('before reconciliation, the legacy link records are used and fee permission is unknown', () async {
      final db = FakeFirebaseFirestore();
      await seedFamily(db);
      final children = await ParentService(firestore: db).getLinkedChildren(father);
      expect(children.map((c) => c.student.id).toSet(), {'s1', 's2'});
      expect(children.every((c) => c.canViewFinance == null), isTrue);
    });
  });

  group('parent queries return only linked children\'s records', () {
    test('legacy payments (before reconciliation) come from one student\'s receipts, voided and internal fields left out', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('fee_receipts').doc('r1').set({'studentId': 's1', 'amount': 100, 'feeStructureName': 'Tuition', 'paymentDate': DateTime(2026, 8, 1), 'pdfUrl': 'https://x/token', 'createdBy': 'Office'});
      await db.collection('fee_receipts').doc('r2').set({'studentId': 's1', 'amount': 50, 'isDeleted': true});
      await db.collection('fee_receipts').doc('r9').set({'studentId': 's9', 'amount': 999});
      final payments = await ParentService(firestore: db).projections.getLegacyPayments('s1');
      expect(payments.map((p) => p['amount']), [100]);
      expect(payments.single.keys, isNot(anyOf(contains('pdfUrl'), contains('createdBy'))));
    });

    test('leave history: only linked children\'s student leave, never staff leave or other students', () async {
      final db = FakeFirebaseFirestore();
      await seedFamily(db);
      Future<void> leave(Map<String, dynamic> d) => db.collection('staff_leave_requests').add({'createdAt': DateTime(2026, 9, 1), ...d});
      await leave({'subjectType': 'student', 'studentId': 's1', 'studentName': 'Anu'});
      await leave({'subjectType': 'student', 'studentId': 's9', 'studentName': 'Other child'});
      await leave({'subjectType': 'staff', 'requesterId': 'staff-1'});
      final requests = await LeaveService(firestore: db, parentService: ParentService(firestore: db)).getStudentRequestsForParent(guardian);
      expect(requests.map((r) => r.studentId), ['s1']);
    });

    test('notifications: a notice targeted at another student is not returned', () async {
      final db = FakeFirebaseFirestore();
      Future<void> notice(String id, Map<String, dynamic> d) => db.collection('school_notifications').doc(id).set({
            'title': id, 'status': 'Published', 'audience': 'Parents', 'appliesToAllClasses': false, 'appliesToAllStudents': false,
            'applicableClassIds': <String>[], 'applicableStudentIds': <String>[], ...d,
          });
      await notice('all', {'appliesToAllClasses': true});
      await notice('mine', {'applicableStudentIds': ['s1']});
      await notice('theirs', {'applicableStudentIds': ['s9']});
      await notice('class', {'applicableClassIds': ['class-1']});
      await notice('public', {'audience': 'Public'});
      await notice('draft', {'status': 'Draft', 'applicableStudentIds': ['s1']});
      await notice('staff', {'audience': 'Staff'});
      final service = AdminNotificationService(firestore: db, storage: MockFirebaseStorage(), filePicker: _UnusedFilePicker());
      final ids = (await service.getNotificationsForParent(parentUserId: '', childStudentIds: {'s1'})).map((n) => n.id).toSet();
      expect(ids, containsAll(['all', 'mine', 'public']));
      expect(ids, isNot(anyOf(contains('theirs'), contains('draft'), contains('staff'))));
      // The class-targeted notice is fetched by `applicableStudentIds == []`,
      // which real Firestore matches but fake_cloud_firestore does not; that
      // query is covered against the emulator in parent_access_rules_test.py.
    });

    test('attendance history is read one linked child\'s day at a time', () async {
      final db = FakeFirebaseFirestore();
      final attendance = AttendanceService(firestore: db, storage: MockFirebaseStorage());
      final today = attendance.dateKeyFor(DateTime.now());
      await db.collection('attendance').doc('${today}_student_s1').set({'date': today, 'status': 'present'});
      await db.collection('attendance').doc('${today}_student_s9').set({'date': today, 'status': 'absent'});
      final days = await attendance.getAttendanceHistoryForEntity(entityType: 'student', entityId: 's1', days: 3);
      expect(days.first['status'], 'present');
      expect(days.skip(1).map((d) => d['status']), ['not_marked', 'not_marked']);
    });
  });

  group('parent Fees view', () {
    Future<void> pump(WidgetTester tester, FakeFirebaseFirestore db, String parentId) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [currentUserProvider.overrideWith((ref) => AppUser(id: parentId, phone: parentId, role: 'parent', isActive: true))],
        child: MaterialApp(
          home: Scaffold(
            body: ParentFeeHistoryView(
              feeService: FeeService(firestore: db, auth: MockFirebaseAuth(), storage: MockFirebaseStorage()),
              parentService: ParentService(firestore: db),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<FakeFirebaseFirestore> seeded() async {
      final db = FakeFirebaseFirestore();
      await seedFamily(db);
      await db.collection('student_fee_assignments').add({
        'studentId': 's1', 'feeStructureName': 'Tuition', 'totalFee': 30000, 'discountAmount': 0,
        'payableAmount': 30000, 'paidAmount': 12345, 'balanceAmount': 17655, 'isDeleted': false,
      });
      final service = ParentAccessService(firestore: db);
      await service.apply(await service.preview(requesterRole: 'admin'), requesterRole: 'admin', updatedBy: 'a');
      await ParentProjectionService(firestore: db).syncAll(requesterRole: 'admin');
      return db;
    }

    testWidgets('a Guardian sees the child but no fees', (tester) async {
      await pump(tester, await seeded(), guardian);
      expect(find.text('Anu'), findsOneWidget);
      expect(find.byKey(const Key('parent-fees-restricted')), findsOneWidget);
      expect(find.text('₹12345'), findsNothing);
    });

    testWidgets('a Mother sees the fees', (tester) async {
      await pump(tester, await seeded(), mother);
      expect(find.text('₹12345'), findsOneWidget);
      expect(find.byKey(const Key('parent-fees-restricted')), findsNothing);
    });
  });
}

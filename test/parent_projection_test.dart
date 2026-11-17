// Parent Dashboard Phase 0.1 (docs/parent_access_security.md): the
// parent-safe projections, class-targeted notices, protected downloads, the
// parent-unlinking fix and the account checks. The server-side half is in
// test/firebase_rules/parent_access_rules_test.py.
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/finance/services/finance_service.dart';
import 'package:montessori_app/modules/parent/data/parent_access.dart';
import 'package:montessori_app/modules/parent/data/parent_access_service.dart';
import 'package:montessori_app/modules/parent/data/parent_file_service.dart';
import 'package:montessori_app/modules/parent/data/parent_link_service.dart';
import 'package:montessori_app/modules/parent/data/parent_projection_service.dart';
import 'package:montessori_app/modules/parent/data/parent_projections.dart';
import 'package:montessori_app/modules/parent/data/parent_service.dart';
import 'package:montessori_app/modules/parent/ui/parent_child_profile_view.dart';

import 'support/buffered_transaction_firestore.dart';

class _UnusedFilePicker extends FilePicker {}

const father = '9000000001';
const mother = '9000000002';
const guardian = '9000000003';
const url = 'https://firebasestorage.googleapis.com/v0/b/app.appspot.com/o/students%2Fs1%2F1700.pdf?alt=media&token=SECRET';
const photoUrl = 'https://firebasestorage.googleapis.com/v0/b/app.appspot.com/o/students%2Fs1.jpg?alt=media&token=SECRET';

Map<String, dynamic> fullStudent() => {
      'name': 'Anu', 'admissionNo': 'ADM-1', 'classId': 'c1', 'section': 'A', 'rollNumber': '7', 'dateOfBirth': '2021-04-02',
      'gender': 'F', 'bloodGroup': 'O+', 'nationality': 'Indian', 'motherTongue': 'Tamil', 'addressLine1': '1 Lake Road',
      'city': 'Chennai', 'state': 'TN', 'pincode': '600001', 'isActive': true, 'isApproved': true,
      'profileImageUrl': photoUrl, 'createdBy': 'admin-1', 'createdAt': DateTime(2026, 6, 1),
      'feeDiscount': {'type': 'percent', 'value': 10, 'reason': 'Sibling', 'isActive': true},
      'parentLinks': [
        {'userId': father, 'name': 'Ravi', 'phone': father, 'email': 'ravi@example.com', 'relation': 'Father'},
        {'userId': mother, 'name': 'Meena', 'phone': mother, 'email': 'meena@example.com', 'relation': 'Mother'},
      ],
      'documents': [
        {'name': 'Birth certificate', 'type': 'Certificate', 'url': url, 'uploadedBy': 'admin-1'},
      ],
    };

/// Links, access records and parent copies for one family: Anu (s1, class
/// c1) with Father, Mother and Guardian; Bala (s2, class c2) with Father.
Future<FakeFirebaseFirestore> family() async {
  final db = FakeFirebaseFirestore();
  await db.collection('students').doc('s1').set(fullStudent());
  await db.collection('students').doc('s2').set({'name': 'Bala', 'classId': 'c2', 'isActive': true});
  await db.collection('students').doc('s9').set({'name': 'Other', 'classId': 'c9', 'isActive': true});
  final links = ParentLinkService(firestore: db);
  await links.saveLinksForStudent(studentId: 's1', parents: const [
    ParentLinkEntry(userId: father, relation: 'Father', name: 'Ravi', phone: father),
    ParentLinkEntry(userId: mother, relation: 'Mother', name: 'Meena', phone: mother),
    ParentLinkEntry(userId: guardian, relation: 'Guardian', name: 'Kala', phone: guardian),
  ]);
  await links.saveLinksForStudent(studentId: 's2', parents: const [ParentLinkEntry(userId: father, relation: 'Father', name: 'Ravi')]);
  final access = ParentAccessService(firestore: db);
  await access.apply(await access.preview(requesterRole: 'admin'), requesterRole: 'admin', updatedBy: 'admin');
  await ParentProjectionService(firestore: db).syncAll(requesterRole: 'admin');
  return db;
}

Future<List<Map<String, dynamic>>> linksOf(FakeFirebaseFirestore db, String field, String value) async =>
    [for (final d in (await db.collection('user_student_links').where(field, isEqualTo: value).get()).docs) d.data()];

Future<List<String>> parentLinkIds(FakeFirebaseFirestore db, String studentId) async =>
    [for (final e in ((await db.collection('students').doc(studentId).get()).data()?['parentLinks'] as List? ?? const [])) (e as Map)['userId'].toString()]..sort();

void main() {
  group('parent-safe student profile', () {
    test('every-parent profile keeps the student\'s own details; Father/Mother details hold blood group, address and documents', () {
      final p = parentStudentProfile('s1', fullStudent());
      for (final k in ['name', 'admissionNo', 'classId', 'section', 'rollNumber', 'dateOfBirth', 'gender', 'nationality', 'motherTongue']) {
        expect(p[k], fullStudent()[k], reason: k);
      }
      for (final k in ['feeDiscount', 'parentLinks', 'profileImageUrl', 'createdBy', 'createdAt', 'isApproved', 'bloodGroup', 'addressLine1', 'city', 'pincode', 'documents']) {
        expect(p.containsKey(k), isFalse, reason: k);
      }
      expect(p['photoPath'], 'students/s1.jpg');
      expect(p['guardians'], [
        {'name': 'Ravi', 'relation': 'Father'},
        {'name': 'Meena', 'relation': 'Mother'},
      ]);
      expect(p.toString(), isNot(anyOf(contains('SECRET'), contains('@example.com'), contains(father), contains('Sibling'))));

      final d = parentStudentDetails('s1', fullStudent());
      expect([d['bloodGroup'], d['addressLine1'], d['city'], d['pincode']], ['O+', '1 Lake Road', 'Chennai', '600001']);
      expect(d['documents'], [
        {'name': 'Birth certificate', 'type': 'Certificate', 'fileName': '', 'storagePath': 'students/s1/1700.pdf'},
      ]);
      expect(d.toString(), isNot(anyOf(contains('SECRET'), contains('uploadedBy'), contains('isApproved'))));
    });

    test('an unknown future field is never copied (allowlist)', () {
      final extra = {...fullStudent(), 'medicalNotes': 'x', 'internalFlag': true};
      expect(parentStudentProfile('s1', extra).keys, isNot(anyOf(contains('medicalNotes'), contains('internalFlag'))));
      expect(parentStudentDetails('s1', extra).keys, isNot(anyOf(contains('medicalNotes'), contains('internalFlag'))));
    });

    test('Father, Mother and Guardian get the profile; only Father and Mother get blood group, address and documents', () async {
      final db = await family();
      for (final parent in [father, mother, guardian]) {
        final child = (await ParentService(firestore: db).getLinkedChildren(parent)).firstWhere((c) => c.student.id == 's1');
        final family = parent != guardian;
        expect(child.fromProjection, isTrue);
        expect(child.student.feeDiscount, isNull);
        expect(child.student.parentLinks, isEmpty);
        expect(child.student.profileImageUrl, isEmpty);
        expect(child.student.isApproved, isFalse, reason: 'approval status is never copied');
        expect(child.photoPath, 'students/s1.jpg');
        expect(child.student.bloodGroup, family ? 'O+' : '');
        expect(child.student.addressLine1, family ? '1 Lake Road' : '');
        expect(child.student.city, family ? 'Chennai' : '');
        expect(child.documents.length, family ? 1 : 0);
        expect(child.guardians.map((g) => g.relation), ['Father', 'Mother', 'Guardian']);
      }
    });

    test('an admin change to the student refreshes the copies and the parents\' class list', () async {
      final db = await family();
      await db.collection('students').doc('s1').update({'classId': 'c5', 'bloodGroup': 'A+'});
      await ParentProjectionService(firestore: db).syncStudent('s1');
      expect((await db.collection('parent_student_details').doc('s1').get()).data()!['bloodGroup'], 'A+');
      expect((await db.collection('parent_student_profiles').doc('s1').get()).data()!['classId'], 'c5');
      expect((await db.collection('parent_access').doc(mother).get()).data()!['classIds'], ['c5']);
      expect((await db.collection('parent_access').doc(father).get()).data()!['classIds'], ['c2', 'c5']);
    });

    Future<void> openProfile(WidgetTester tester, LinkedChild child) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showChildProfile(context,
                  child: child.student, className: 'Mont 1', academicYear: '2026-2027', documents: child.documents, guardians: child.guardians),
              child: const Text('Open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a Mother\'s profile view shows all approved details, parents by name only, and documents', (tester) async {
      final db = await family();
      await openProfile(tester, (await ParentService(firestore: db).getLinkedChildren(mother)).single);
      for (final t in ['Blood Group', 'O+', 'Address', 'Mother Tongue', 'Tamil', 'Nationality', 'Parents & Guardians', 'Ravi', 'Meena', 'Kala', 'Birth certificate']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      expect(find.textContaining('@example.com'), findsNothing);
      expect(find.textContaining(father), findsNothing);
    });

    testWidgets('a Guardian\'s profile view has no blood group, address or documents, but names the parents', (tester) async {
      final db = await family();
      await openProfile(tester, (await ParentService(firestore: db).getLinkedChildren(guardian)).single);
      for (final t in ['Blood Group', 'O+', 'Address', '1 Lake Road', 'Documents', 'Birth certificate']) {
        expect(find.text(t), findsNothing, reason: t);
      }
      for (final t in ['Mother Tongue', 'Parents & Guardians', 'Ravi', 'Meena', 'Kala']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
    });
  });

  group('parent-safe payments', () {
    test('only date, amount, mode, references, fee and month; voided receipts removed', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('fee_receipts').doc('r1').set({
        'studentId': 's1', 'assignmentId': 'a1', 'receiptNo': 'REC-1', 'amount': 1500.0, 'paymentDate': DateTime(2026, 8, 1),
        'paymentMode': 'UPI', 'referenceNo': 'UPI-1', 'feeStructureName': 'Tuition', 'feeMonth': '2026-08', 'transactionId': 't1',
        'pdfUrl': 'https://x/token', 'pdfPath': 'fee_receipts/r1/REC-1.pdf', 'createdBy': 'Office', 'remarks': 'internal note', 'collectedBy': 'Office',
      });
      await db.collection('fee_receipts').doc('r2').set({'studentId': 's1', 'amount': 99.0, 'isDeleted': true});
      final projections = ParentProjectionService(firestore: db);
      await projections.syncPaymentsForStudent('s1');
      final payments = await projections.getPayments('s1');
      expect(payments, hasLength(1));
      expect(payments.single.keys.toSet().difference({'syncedAt'}), {
        'receiptId', 'studentId', 'assignmentId', 'receiptNo', 'amount', 'paymentDate', 'paymentMode', 'referenceNo', 'feeStructureName', 'feeMonth', 'schemaVersion',
      });

      await db.collection('fee_receipts').doc('r1').update({'isDeleted': true});
      await projections.syncPaymentsForStudent('s1');
      expect(await projections.getPayments('s1'), isEmpty);
    });

    test('collecting and voiding a fee refresh the copy without changing the collection', () async {
      final db = BufferedTransactionFirestore();
      final auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'admin-uid'));
      final finance = FinanceService(firestore: db, auth: auth);
      await finance.ensureDefaults();
      final fees = FeeService(firestore: db, auth: auth, storage: MockFirebaseStorage(), financeService: finance);
      final a = (await db.collection('student_fee_assignments').add({
        'studentId': 's1', 'studentName': 'Anu', 'admissionNo': 'ADM-1', 'classId': 'c1', 'className': 'Mont 1', 'feeStructureId': 'f',
        'feeStructureName': 'Tuition', 'feeMonth': '2026-08', 'totalFee': 5000, 'discountAmount': 0, 'payableAmount': 5000,
        'paidAmount': 0, 'balanceAmount': 5000, 'status': 'unpaid',
      })).id;
      final receipt = await fees.collectFee(assignmentId: a, amount: 2000, paymentDate: DateTime(2026, 8, 3), paymentMode: 'cash', referenceNo: '', remarks: 'paid at desk');
      final copy = (await db.collection('parent_payments').doc(receipt.id).get()).data()!;
      expect(copy['amount'], 2000);
      expect(copy.containsKey('remarks'), isFalse);
      expect((await db.collection('student_fee_assignments').doc(a).get()).data()!['balanceAmount'], 3000);

      await fees.voidReceipt(receipt.id);
      expect((await db.collection('parent_payments').doc(receipt.id).get()).exists, isFalse);
    });

    test('a Guardian has no fee permission on the access record (the rules refuse parent_payments)', () async {
      final db = await family();
      final children = await ParentService(firestore: db).getLinkedChildren(guardian);
      expect(children.single.canViewFinance, isFalse);
    });
  });

  group('class-targeted notices', () {
    Map<String, dynamic> notice(Map<String, dynamic> extra) => {
          'title': 'N', 'status': 'Published', 'audience': 'Parents', 'appliesToAllClasses': false, 'appliesToAllStudents': false,
          'applicableClassIds': <String>[], 'applicableClassNames': <String>[], 'applicableStudentIds': <String>[],
          'applicableStudentNames': <String>[], 'createdBy': 'admin-1', 'createdByName': 'Principal', ...extra,
        };

    test('a notice naming students targets only them (its class filter is dropped); names and authors withheld', () {
      final p = parentNotice('n1', notice({'applicableClassIds': ['c1'], 'applicableStudentIds': ['s9'], 'applicableStudentNames': ['Other']}))!;
      expect(p['applicableStudentIds'], ['s9']);
      expect(p['applicableClassIds'], isEmpty);
      expect(p.keys, isNot(anyOf(contains('applicableStudentNames'), contains('createdByName'), contains('createdBy'), contains('attachmentUrl'))));
      expect(parentNotice('n2', notice({'status': 'Draft'})), isNull);
      expect(parentNotice('n3', notice({'audience': 'Staff'})), isNull);
    });

    test('the attachment is referenced by Storage path, never by URL', () {
      final p = parentNotice('n1', notice({'attachmentName': '17_menu.pdf', 'attachmentUrl': 'https://firebasestorage.googleapis.com/v0/b/b/o/school_notifications%2Fn1%2F17_menu.pdf?alt=media&token=SECRET'}))!;
      expect(p['attachmentPath'], 'school_notifications/n1/17_menu.pdf');
      expect(p.toString(), isNot(contains('SECRET')));
    });

    test('a parent receives their class\'s and children\'s notices, never another class\'s', () async {
      final db = await family();
      final service = AdminNotificationService(firestore: db, storage: MockFirebaseStorage(), filePicker: _UnusedFilePicker());
      await db.collection('school_notifications').doc('mine-class').set(notice({'applicableClassIds': ['c1']}));
      await db.collection('school_notifications').doc('other-class').set(notice({'applicableClassIds': ['c9']}));
      await db.collection('school_notifications').doc('student-in-my-class').set(notice({'applicableClassIds': ['c1'], 'applicableStudentIds': ['s9']}));
      await db.collection('school_notifications').doc('my-child').set(notice({'applicableStudentIds': ['s1']}));
      await db.collection('school_notifications').doc('all').set(notice({'appliesToAllClasses': true}));
      await db.collection('school_notifications').doc('public').set(notice({'audience': 'Public', 'isPublic': true}));
      for (final id in ['mine-class', 'other-class', 'student-in-my-class', 'my-child', 'all', 'public']) {
        await ParentProjectionService(firestore: db).syncNotice(id);
      }
      final got = (await service.getNotificationsForParent(parentUserId: mother, childStudentIds: {'s1'}, childClassIds: {'c1'})).map((n) => n.id).toSet();
      expect(got, {'mine-class', 'my-child', 'all', 'public'});
    });

    test('publishing, archiving and deleting keep the parent copy in step', () async {
      final db = FakeFirebaseFirestore();
      final service = AdminNotificationService(firestore: db, storage: MockFirebaseStorage(), filePicker: _UnusedFilePicker());
      final id = await service.createNotification(notice({'status': 'Draft', 'appliesToAllClasses': true}));
      expect((await db.collection('parent_notices').doc(id).get()).exists, isFalse);
      await service.publishNotification(id);
      expect((await db.collection('parent_notices').doc(id).get()).exists, isTrue);
      await service.archiveNotification(id);
      expect((await db.collection('parent_notices').doc(id).get()).exists, isFalse);
      await service.publishNotification(id);
      await service.deleteNotification(id);
      expect((await db.collection('parent_notices').doc(id).get()).exists, isFalse);
    });
  });

  group('parent unlinking', () {
    test('un-ticking a child in the parent form removes this parent in both places and keeps the other parents', () async {
      final db = await family();
      final links = ParentLinkService(firestore: db);
      final saved = await links.saveLinksForParent(userId: father, relations: {'s2': 'Father'});
      await links.refresh(saved, requesterRole: 'admin', updatedBy: 'admin');

      expect((await linksOf(db, 'userId', father)).map((l) => l['studentId']), ['s2']);
      expect(await parentLinkIds(db, 's1'), [mother, guardian]..sort());
      expect(await parentLinkIds(db, 's2'), [father]);
      expect((await linksOf(db, 'studentId', 's1')).map((l) => l['userId']).toSet(), {mother, guardian});
      final access = (await db.collection('parent_access').doc(father).get()).data()!;
      expect(access['studentIds'], ['s2']);
      expect(access['financeStudentIds'], ['s2']);
      expect((await ParentService(firestore: db).getLinkedChildren(father)).map((c) => c.student.id), ['s2']);
      expect((await db.collection('parent_access').doc(mother).get()).data()!['studentIds'], ['s1']);
      final guardians = (await db.collection('parent_student_profiles').doc('s1').get()).data()!['guardians'] as List;
      expect(guardians.map((g) => (g as Map)['relation']), isNot(contains('Father')));
    });

    test('ticking a child adds this parent without touching the child\'s other parents', () async {
      final db = await family();
      final links = ParentLinkService(firestore: db);
      await links.refresh(await links.saveLinksForParent(userId: mother, relations: {'s1': 'Mother', 's2': 'Mother'}), requesterRole: 'admin', updatedBy: 'a');
      expect(await parentLinkIds(db, 's2'), [father, mother]..sort());
      expect(await parentLinkIds(db, 's1'), [father, mother, guardian]..sort());
      expect((await db.collection('parent_access').doc(mother).get()).data()!['financeStudentIds'], ['s1', 's2']);
    });

    test('the student form\'s save replaces both copies and removed parents lose access', () async {
      final db = await family();
      final links = ParentLinkService(firestore: db);
      final saved = await links.saveLinksForStudent(studentId: 's1', parents: const [ParentLinkEntry(userId: mother, relation: 'Mother', name: 'Meena')]);
      await links.refresh(saved, requesterRole: 'admin', updatedBy: 'a');
      expect(saved.parentIds, {father, mother, guardian});
      expect(await parentLinkIds(db, 's1'), [mother]);
      expect((await db.collection('parent_access').doc(guardian).get()).data()!['studentIds'], isEmpty);
      expect((await db.collection('parent_access').doc(father).get()).data()!['studentIds'], ['s2']);
    });

    test('a non-administrator cannot refresh access', () async {
      final db = await family();
      final links = ParentLinkService(firestore: db);
      expect(() => links.refresh(const ParentLinkSaveResult(parentIds: {father}, studentIds: {'s1'}), requesterRole: 'parent', updatedBy: father),
          throwsA(isA<ParentAccessDeniedException>()));
    });
  });

  group('account checks', () {
    test('accounts the rules cannot recognise are reported, with their role', () {
      final issues = auditAccounts({
        '9000000100': {'role': 'admin', 'phoneNumber': '9000000100'},
        'uid-abc': {'role': 'staff', 'phoneNumber': '9000000200'},
        '9000000300': {'role': 'staff', 'phoneNumber': '9000000999'},
        '9000000999': {'role': 'parent', 'phone': '+91 90000 00999'},
      });
      String kinds(String id) => issues.where((i) => i.userId == id).map((i) => i.kind.name).join(',');
      expect(kinds('uid-abc'), 'accountIdNotPhone');
      expect(issues.firstWhere((i) => i.userId == 'uid-abc').detail, 'role: staff');
      expect(kinds('9000000300'), 'accountPhoneMismatch');
      expect(kinds('9000000999'), 'duplicateAccountPhone');
      expect(kinds('9000000100'), isEmpty);
    });
  });

  group('protected downloads', () {
    test('documents download by Storage path for a Father, never for a Guardian or an unlinked parent', () async {
      final db = await family();
      final storage = MockFirebaseStorage();
      await storage.ref('students/s1/1700.pdf').putData(Uint8List.fromList([1, 2, 3]));
      final saved = <String, Uint8List>{};
      ParentFileService files(String parent) => ParentFileService(parentUserId: parent, storage: storage, firestore: db, save: (b, n) async => saved[n] = b);

      expect(await files(father).downloadChildDocument(studentId: 's1', storagePath: 'students/s1/1700.pdf', fileName: 'birth.pdf'), isTrue);
      expect(saved['birth.pdf'], [1, 2, 3]);
      await expectLater(files(guardian).downloadChildDocument(studentId: 's1', storagePath: 'students/s1/1700.pdf'), throwsA(isA<ParentFileAccessDenied>()));
      await expectLater(files('9000000999').downloadChildDocument(studentId: 's1', storagePath: 'students/s1/1700.pdf'), throwsA(isA<ParentFileAccessDenied>()));
      await expectLater(files(father).downloadChildDocument(studentId: 's1', storagePath: 'students/s9/other.pdf'), throwsA(isA<ParentFileAccessDenied>()));
    });

    test('fee bills for a child come from the parent copies, Father/Mother only', () async {
      final db = await family();
      await db.collection('fee_issued_bills').doc('b1').set({'studentId': 's1', 'billNo': 'REC-1-000001', 'status': 'issued', 'issuedBy': 'admin-uid'});
      await db.collection('fee_issued_bills').doc('b9').set({'studentId': 's9', 'billNo': 'REC-9-000001', 'status': 'issued'});
      await ParentProjectionService(firestore: db).syncFeesForStudent('s1');
      final files = ParentFileService(parentUserId: mother, storage: MockFirebaseStorage(), firestore: db, save: (_, _) async {});
      expect((await files.feeBillsForStudent('s1')).map((b) => b.billNo), ['REC-1-000001']);
      await expectLater(ParentFileService(parentUserId: guardian, firestore: db, storage: MockFirebaseStorage()).feeBillsForStudent('s1'), throwsA(isA<ParentFileAccessDenied>()));
    });
  });
}

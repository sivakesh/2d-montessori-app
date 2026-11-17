// Parent Dashboard Phase 0.2 (docs/parent_access_security.md): parent-safe
// fee assignments and fee bills, attendance photos by path, Father/Mother-
// only details and documents, and the reliability of the parent copies.
// These are application-level protections; server-side enforcement still
// depends on the rules review (§9 of the doc).
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_models.dart';
import 'package:montessori_app/modules/fees/bill_issuance/fee_bill_pdf.dart';
import 'package:montessori_app/modules/fees/models/student_fee_assignment_model.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/parent_fee_history_view.dart';
import 'package:montessori_app/modules/parent/data/parent_access_service.dart';
import 'package:montessori_app/modules/parent/data/parent_file_service.dart';
import 'package:montessori_app/modules/parent/data/parent_link_service.dart';
import 'package:montessori_app/modules/parent/data/parent_projection_service.dart';
import 'package:montessori_app/modules/parent/data/parent_projections.dart';
import 'package:montessori_app/modules/parent/data/parent_service.dart';

const father = '9000000001';
const mother = '9000000002';
const guardian = '9000000003';
const stranger = '9000000009';

/// An assignment as the Fees module stores it, with every internal field.
Map<String, dynamic> assignmentDoc({String studentId = 's1'}) => {
      'studentId': studentId, 'studentName': 'Anu', 'admissionNo': 'ADM-1', 'classId': 'c1', 'className': 'Mont 1',
      'feeStructureId': 'fs1', 'feeStructureName': 'Tuition', 'academicYearId': 'ay1', 'academicYear': '2026-2027', 'feeMonth': '2026-08',
      'dueDate': DateTime(2026, 8, 10), 'totalFee': 10000.0, 'discountAmount': 1000.0, 'payableAmount': 9000.0, 'paidAmount': 4000.0,
      'balanceAmount': 5000.0, 'status': 'partial', 'assignedBy': 'admin-uid', 'deletedBy': null, 'lastRevisedAt': DateTime(2026, 8, 2),
      'feeRevision': 1,
      'feeRevisions': [
        {'revision': 1, 'previousTotalFee': 12000.0, 'newTotalFee': 10000.0, 'reason': 'Board approved reduction', 'revisedBy': 'admin-uid', 'revisedByName': 'Principal Rao'},
      ],
      'studentDiscount': {
        'configId': 'cfg-1', 'type': 'percent', 'value': 10.0, 'reason': 'Sibling concession', 'gross': 10000.0, 'amount': 1000.0,
        'allocation': [
          {'name': 'Tuition', 'gross': 8000.0, 'discount': 800.0},
          {'name': 'Activity', 'gross': 2000.0, 'discount': 200.0},
        ],
        'appliedBy': 'admin-uid', 'operationId': 'op-1',
      },
    };

/// A supplementary bill as Fee Bill Issuance stores it.
Map<String, dynamic> billDoc() => {
      'schoolId': 'default_school', 'billNo': 'REC-1-000001', 'status': 'issued', 'receiptId': 'r1', 'studentId': 's1',
      'studentName': 'Anu', 'admissionNo': 'ADM-1', 'className': 'Mont 1',
      'payment': {'receiptId': 'r1', 'receiptNo': 'REC-1', 'amountPaise': 900000, 'paymentMode': 'upi', 'referenceNo': 'UPI-1', 'paymentDate': DateTime(2026, 8, 3)},
      'issueDate': DateTime(2026, 8, 3), 'parentRelation': 'Father', 'parentName': 'Ravi', 'amountIncludesGst': true,
      'billingMonth': '2026-08', 'description': 'Monthly fee', 'grossPaise': 900000, 'adjustmentType': 'discount', 'adjustmentPaise': 10000,
      'adjustmentReason': 'Rounding', 'netPaise': 890000,
      'adjustment': {'type': 'discount', 'amountPaise': 10000, 'reason': 'Rounding', 'createdBy': 'admin-uid', 'createdAt': DateTime(2026, 8, 3)},
      'school': {'name': '2D Montessori', 'addressLines': ['1 Main Rd'], 'contactLines': ['044-1'], 'gstin': '33ABCDE',
        'logoUrl': 'https://firebasestorage.googleapis.com/v0/b/b/o/school_settings%2Fdefault_school%2Flogo.png?alt=media&token=SECRET'},
      'issuedAt': DateTime(2026, 8, 3, 10), 'issuedBy': 'admin-uid', 'issueRequestId': 'req-1', 'replacesBillId': '', 'replacedByBillId': '',
      'createdAt': DateTime(2026, 8, 3, 10),
    };

/// Anu (s1): Father, Mother, Guardian. Other child (s9): a stranger.
Future<FakeFirebaseFirestore> family() async {
  final db = FakeFirebaseFirestore();
  await db.collection('students').doc('s1').set({
    'name': 'Anu', 'classId': 'c1', 'isActive': true, 'isApproved': true, 'bloodGroup': 'O+', 'addressLine1': '1 Lake Road', 'city': 'Chennai',
    'documents': [{'name': 'Birth certificate', 'url': 'https://firebasestorage.googleapis.com/v0/b/b/o/students%2Fs1%2Fbirth.pdf?alt=media&token=SECRET'}],
  });
  await db.collection('students').doc('s9').set({'name': 'Other', 'classId': 'c9', 'isActive': true});
  await db.collection('fee_structures').doc('fs1').set({'name': 'Tuition', 'components': [{'name': 'Tuition', 'amount': 8000}, {'name': 'Activity', 'amount': 2000}]});
  await db.collection('student_fee_assignments').doc('a1').set(assignmentDoc());
  await db.collection('fee_issued_bills').doc('default_school_REC-1-000001').set(billDoc());
  final links = ParentLinkService(firestore: db);
  await links.saveLinksForStudent(studentId: 's1', parents: const [
    ParentLinkEntry(userId: father, relation: 'Father', name: 'Ravi', phone: father, email: 'ravi@example.com'),
    ParentLinkEntry(userId: mother, relation: 'Mother', name: 'Meena', phone: mother),
    ParentLinkEntry(userId: guardian, relation: 'Guardian', name: 'Kala', phone: guardian),
  ]);
  await links.saveLinksForStudent(studentId: 's9', parents: const [ParentLinkEntry(userId: stranger, relation: 'Father')]);
  final access = ParentAccessService(firestore: db);
  await access.apply(await access.preview(requesterRole: 'admin'), requesterRole: 'admin', updatedBy: 'admin');
  await ParentProjectionService(firestore: db).syncAll(requesterRole: 'admin');
  return db;
}

Future<Map<String, Map<String, dynamic>>> originals(FakeFirebaseFirestore db) async => {
      for (final c in ['students', 'student_fee_assignments', 'fee_receipts', 'fee_transactions', 'fee_issued_bills', 'school_notifications', 'attendance', 'user_student_links'])
        for (final d in (await db.collection(c).get()).docs) '$c/${d.id}': d.data(),
    };

void main() {
  group('student profile policy', () {
    test('Father and Mother see blood group and address; Guardian does not; nobody sees approval status or contacts', () async {
      final db = await family();
      for (final (parent, family) in [(father, true), (mother, true), (guardian, false)]) {
        final child = (await ParentService(firestore: db).getLinkedChildren(parent)).single;
        expect(child.student.bloodGroup, family ? 'O+' : '', reason: parent);
        expect([child.student.addressLine1, child.student.city], family ? ['1 Lake Road', 'Chennai'] : ['', ''], reason: parent);
        expect(child.student.isApproved, isFalse, reason: 'never copied');
        expect({for (final g in child.guardians) g.relation: g.name}, {'Father': 'Ravi', 'Mother': 'Meena', 'Guardian': 'Kala'});
      }
      final copies = [
        (await db.collection('parent_student_profiles').doc('s1').get()).data().toString(),
        (await db.collection('parent_student_details').doc('s1').get()).data().toString(),
      ];
      for (final c in copies) {
        expect(c, isNot(anyOf(contains('ravi@example.com'), contains(father), contains(mother), contains('isApproved'), contains('SECRET'))));
      }
      expect(copies.first, isNot(anyOf(contains('O+'), contains('Lake Road'), contains('birth.pdf'))), reason: 'the every-parent copy has no Father/Mother details');
    });
  });

  group('student documents', () {
    test('Father and Mother get the documents (by path); Guardian and unlinked parents get none and cannot download', () async {
      final db = await family();
      final storage = MockFirebaseStorage();
      await storage.ref('students/s1/birth.pdf').putData(Uint8List.fromList([7, 7]));
      final saved = <String>[];
      ParentFileService files(String p) => ParentFileService(parentUserId: p, storage: storage, firestore: db, save: (_, n) async => saved.add('$p:$n'));

      for (final p in [father, mother]) {
        final child = (await ParentService(firestore: db).getLinkedChildren(p)).single;
        expect(child.documents.map((d) => d.storagePath), ['students/s1/birth.pdf']);
        expect(await files(p).downloadChildDocument(studentId: 's1', storagePath: 'students/s1/birth.pdf', fileName: 'birth.pdf'), isTrue);
      }
      expect(saved, ['$father:birth.pdf', '$mother:birth.pdf']);
      expect((await ParentService(firestore: db).getLinkedChildren(guardian)).single.documents, isEmpty);
      for (final p in [guardian, stranger, '9000000777']) {
        await expectLater(files(p).downloadChildDocument(studentId: 's1', storagePath: 'students/s1/birth.pdf'), throwsA(isA<ParentFileAccessDenied>()), reason: p);
      }
      // A school-internal document is never on the list, so never downloadable.
      await expectLater(files(father).downloadChildDocument(studentId: 's1', storagePath: 'school_documents/d1/policy.pdf'), throwsA(isA<ParentFileAccessDenied>()));
      expect((await db.collection('parent_student_details').doc('s1').get()).data().toString(), isNot(contains('SECRET')));
    });
  });

  group('parent-safe fee assignments', () {
    test('only the parent fee breakdown: actual discount shown; revisions, admin ids and discount configuration hidden', () async {
      final db = await family();
      final copy = (await db.collection('parent_fee_assignments').doc('a1').get()).data()!;
      expect(copy.keys.toSet().difference({'syncedAt'}), {
        'assignmentId', 'studentId', 'feeStructureName', 'academicYear', 'feeMonth', 'dueDate', 'totalFee', 'discountAmount',
        'payableAmount', 'paidAmount', 'balanceAmount', 'status', 'components', 'schemaVersion',
      });
      expect(copy['discountAmount'], 1000);
      expect(copy['components'], [
        {'name': 'Tuition', 'gross': 8000, 'discount': 800},
        {'name': 'Activity', 'gross': 2000, 'discount': 200},
      ]);
      expect(copy.toString(), isNot(anyOf(contains('Board approved'), contains('Principal Rao'), contains('admin-uid'), contains('Sibling'), contains('cfg-1'), contains('op-1'))));
    });

    test('totals and balances are exactly those of the existing assignment model', () async {
      final db = await family();
      final original = StudentFeeAssignmentModel.fromMap('a1', (await db.collection('student_fee_assignments').doc('a1').get()).data()!);
      final parent = (await ParentProjectionService(firestore: db).getFeeAssignments('s1')).single;
      expect([parent.totalFee, parent.discountAmount, parent.payableAmount, parent.paidAmount, parent.balanceAmount, parent.status, parent.feeMonth, parent.dueDate],
          [original.totalFee, original.discountAmount, original.payableAmount, original.paidAmount, original.balanceAmount, original.status, original.feeMonth, original.dueDate]);
      expect(parent.revisions, isEmpty);
      expect(parent.studentDiscount, isNull);
    });

    test('structure particulars are shown only when they add up to the fee', () {
      final model = StudentFeeAssignmentModel.fromMap('a', {...assignmentDoc(), 'studentDiscount': null});
      expect(parentFeeAssignment(model, isDeleted: false, structureComponents: const [('Tuition', 8000), ('Activity', 2000)])!['components'], hasLength(2));
      expect(parentFeeAssignment(model, isDeleted: false, structureComponents: const [('Tuition', 9000)])!['components'], isEmpty);
      expect(parentFeeAssignment(model, isDeleted: true), isNull);
    });

    test('an assignment edit and a deletion refresh the copy (Fees calculations unchanged)', () async {
      final db = await family();
      final fees = FeeService(firestore: db, auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'admin-uid')), storage: MockFirebaseStorage());
      await fees.updateAssignment('a1', {'dueDate': DateTime(2026, 8, 20)});
      final stored = StudentFeeAssignmentModel.fromMap('a1', (await db.collection('student_fee_assignments').doc('a1').get()).data()!);
      final copy = (await ParentProjectionService(firestore: db).getFeeAssignments('s1')).single;
      expect(copy.dueDate, DateTime(2026, 8, 20));
      expect([copy.dueDate, copy.payableAmount, copy.balanceAmount], [stored.dueDate, stored.payableAmount, stored.balanceAmount]);
      await fees.deleteAssignment('a1');
      expect((await db.collection('parent_fee_assignments').doc('a1').get()).exists, isFalse);
    });

    testWidgets('a Guardian sees no fees or amounts; a Father sees the parent copy', (tester) async {
      final db = await family();
      Future<void> pump(String parent) async {
        await tester.pumpWidget(ProviderScope(
          key: ValueKey(parent),
          overrides: [currentUserProvider.overrideWith((ref) => AppUser(id: parent, phone: parent, role: 'parent', isActive: true))],
          child: MaterialApp(
            home: Scaffold(
              body: ParentFeeHistoryView(feeService: FeeService(firestore: db, auth: MockFirebaseAuth(), storage: MockFirebaseStorage()), parentService: ParentService(firestore: db)),
            ),
          ),
        ));
        await tester.pumpAndSettle();
      }

      await pump(guardian);
      expect(find.byKey(const Key('parent-fees-restricted')), findsOneWidget);
      expect(find.text('₹9000'), findsNothing);
      await pump(father);
      expect(find.text('₹9000'), findsOneWidget);
      expect(find.text('₹5000'), findsOneWidget);
    });
  });

  group('parent-safe fee bills', () {
    test('keeps every billing field and the receipt reference; drops admin ids, request ids and the logo URL', () async {
      final db = await family();
      final copy = (await db.collection('parent_fee_bills').doc('default_school_REC-1-000001').get()).data()!;
      expect(copy.toString(), isNot(anyOf(contains('admin-uid'), contains('req-1'), contains('SECRET'), contains("receiptId: r1"))));
      expect(copy['school'], containsPair('logoPath', 'school_settings/default_school/logo.png'));
      final fromCopy = FeeIssuedBill.fromMap('default_school_REC-1-000001', copy);
      final fromOriginal = FeeIssuedBill.fromMap('default_school_REC-1-000001', billDoc());
      expect(fromCopy.issuedBy, isEmpty);
      expect(FeeBillPdf.billRows(fromCopy), FeeBillPdf.billRows(fromOriginal));
      expect(FeeBillPdf.studentRows(fromCopy), FeeBillPdf.studentRows(fromOriginal));
      expect(FeeBillPdf.netLabel(fromCopy), FeeBillPdf.netLabel(fromOriginal));
      expect([fromCopy.billNo, fromCopy.issueDate, fromCopy.payment.receiptNo, fromCopy.line.grossPaise, fromCopy.line.adjustmentPaise, fromCopy.line.netPaise],
          ['REC-1-000001', DateTime(2026, 8, 3), 'REC-1', 900000, 10000, 890000]);
    });

    test('Father/Mother only; the original bill is unchanged', () async {
      final db = await family();
      final before = (await db.collection('fee_issued_bills').doc('default_school_REC-1-000001').get()).data();
      final saved = <String>[];
      final files = ParentFileService(parentUserId: father, firestore: db, storage: MockFirebaseStorage(), save: (_, n) async => saved.add(n));
      final bills = await files.feeBillsForStudent('s1');
      await files.downloadFeeBill(bills.single);
      expect(saved, ['REC-1-000001.pdf']);
      for (final p in [guardian, stranger]) {
        await expectLater(ParentFileService(parentUserId: p, firestore: db, storage: MockFirebaseStorage()).feeBillsForStudent('s1'), throwsA(isA<ParentFileAccessDenied>()));
        await expectLater(ParentFileService(parentUserId: p, firestore: db, storage: MockFirebaseStorage()).downloadFeeBill(bills.single), throwsA(isA<ParentFileAccessDenied>()));
      }
      expect((await db.collection('fee_issued_bills').doc('default_school_REC-1-000001').get()).data(), before);
    });
  });

  group('attendance photos', () {
    test('parent-facing records carry the photo path, never its URL; the original record is unchanged', () async {
      final record = {
        'date': '2026-11-16', 'status': 'present', 'entityType': 'student', 'entityId': 's1', 'markedBy': 'staff-1', 'environment': 'prod',
        'photoUrl': 'https://firebasestorage.googleapis.com/v0/b/b/o/attendance_photos%2Fstudents%2F2026-11-16%2Fs1.jpg?alt=media&token=SECRET',
      };
      final copy = Map<String, dynamic>.of(record);
      final parent = parentAttendanceRecord(record);
      expect(parent['photoPath'], 'attendance_photos/students/2026-11-16/s1.jpg');
      expect(parent.keys, isNot(anyOf(contains('photoUrl'), contains('markedBy'), contains('environment'))));
      expect(parent['status'], 'present');
      expect(record, copy);
      expect(parentAttendanceRecord({...record, 'photoUrl': ''})['photoPath'], '');
    });

    test('a linked parent (any relation) downloads the photo; an unlinked parent cannot', () async {
      final db = await family();
      final storage = MockFirebaseStorage();
      await storage.ref(attendancePhotoPath('2026-11-16', 's1')).putData(Uint8List.fromList([1]));
      await storage.ref(attendancePhotoPath('2026-11-16', 's9')).putData(Uint8List.fromList([9]));
      ParentFileService files(String p) => ParentFileService(parentUserId: p, storage: storage, firestore: db);
      expect(await files(guardian).readAttendancePhoto('s1', '2026-11-16'), [1]);
      expect(await files(mother).readAttendancePhoto('s1', '2026-11-16'), [1]);
      await expectLater(files(father).readAttendancePhoto('s9', '2026-11-16'), throwsA(isA<ParentFileAccessDenied>()));
      await expectLater(files(stranger).readAttendancePhoto('s1', '2026-11-16'), throwsA(isA<ParentFileAccessDenied>()));
    });
  });

  group('refresh reliability', () {
    test('a successful refresh updates the copy; a repeated rebuild changes nothing; originals stay unchanged', () async {
      final db = await family();
      final before = await originals(db);
      final service = ParentProjectionService(firestore: db);
      final again = await service.syncAll(requesterRole: 'admin');
      expect(again.totalWritten, 0);
      expect(again.totalRemoved, 0);
      expect(again.totalFailed, 0);
      expect((await service.health(requesterRole: 'admin')).every((h) => h.isCurrent), isTrue);
      expect(await originals(db), before);
    });

    test('a failed refresh is recorded (not treated as success), reported, and repaired by a rebuild', () async {
      final db = await family();
      final service = ParentProjectionService(firestore: db);
      // Malformed data written outside the app (parentLinks must be a list).
      await db.collection('students').doc('s1').update({'parentLinks': 'corrupt', 'name': 'Anu R'});
      expect(await service.syncStudentQuietly('s1'), isFalse);
      final failures = await service.failures(requesterRole: 'admin');
      expect(failures.single.scope, 'profile');
      expect(failures.single.sourceId, 's1');
      expect(failures.single.error, isNotEmpty);
      expect((await db.collection('parent_student_profiles').doc('s1').get()).data()!['name'], 'Anu', reason: 'the last good copy is kept, not deleted');
      final health = {for (final h in await service.health(requesterRole: 'admin')) h.kind: h};
      expect(health[ParentProjectionKind.profile]!.isCurrent, isFalse);

      // A rebuild with the data still bad continues with everything else.
      final partial = await service.syncAll(requesterRole: 'admin');
      expect(partial.failed[ParentProjectionKind.profile], 1);
      expect(partial.failed[ParentProjectionKind.feeAssignments], 0);

      // Fixed: the rebuild repairs the copy and clears the failure.
      await db.collection('students').doc('s1').update({'parentLinks': []});
      final repaired = await service.syncAll(requesterRole: 'admin');
      expect(repaired.totalFailed, 0);
      expect((await db.collection('parent_student_profiles').doc('s1').get()).data()!['name'], 'Anu R');
      expect(await service.failures(requesterRole: 'admin'), isEmpty);
      expect((await service.health(requesterRole: 'admin')).every((h) => h.isCurrent), isTrue);
    });

    test('a copy changed or lost outside the app is found by health and repaired by the rebuild', () async {
      final db = await family();
      final service = ParentProjectionService(firestore: db);
      await db.collection('student_fee_assignments').doc('a1').update({'paidAmount': 9000.0, 'balanceAmount': 0.0, 'status': 'paid'});
      await db.collection('parent_fee_bills').doc('default_school_REC-1-000001').delete();
      await db.collection('parent_payments').doc('orphan').set({'studentId': 's1', 'amount': 1});
      final health = {for (final h in await service.health(requesterRole: 'admin')) h.kind: h};
      expect(health[ParentProjectionKind.feeAssignments]!.outdated, 1);
      expect(health[ParentProjectionKind.feeBills]!.missing, 1);
      expect(health[ParentProjectionKind.payments]!.orphaned, 1);
      await service.syncAll(requesterRole: 'admin');
      expect((await db.collection('parent_fee_assignments').doc('a1').get()).data()!['balanceAmount'], 0);
      expect((await service.health(requesterRole: 'admin')).every((h) => h.isCurrent), isTrue);
    });

    test('only administrators can read diagnostics or rebuild', () async {
      final service = ParentProjectionService(firestore: FakeFirebaseFirestore());
      for (final role in ['parent', 'staff', '']) {
        expect(() => service.syncAll(requesterRole: role), throwsA(isA<ParentAccessDeniedException>()));
        expect(() => service.health(requesterRole: role), throwsA(isA<ParentAccessDeniedException>()));
        expect(() => service.failures(requesterRole: role), throwsA(isA<ParentAccessDeniedException>()));
      }
    });
  });
}

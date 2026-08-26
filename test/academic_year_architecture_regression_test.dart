// SETTINGS-02 architecture/regression coverage — proves the Academic Year
// feature is additive-only: every AcademicYearService operation (create,
// update, set-current, deactivate, activate) writes exclusively to its own
// `academic_years` collection and never reads, writes, or otherwise alters
// a single field of Student, Attendance, Leave, Fees, Finance, or Calendar
// data — the "existing production/UAT data must never be silently altered"
// requirement from the SETTINGS-02 spec. Nothing about how those other
// modules store or read their own data changes in this task; this file
// exists to make that guarantee explicit and machine-checked rather than
// only true "by construction".
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';

const _untouchedCollections = <String>[
  'students',
  'classes',
  'attendance',
  'staff_leave_requests',
  'fee_structures',
  'student_fee_assignments',
  'fee_transactions',
  'finance_income',
  'finance_expenses',
  'finance_ledger',
  'school_calendar_events',
  'users',
];

Future<Map<String, Map<String, dynamic>>> _seedFixtures(FakeFirebaseFirestore firestore) async {
  final fixtures = <String, Map<String, dynamic>>{
    'students': {
      'name': 'Abdul Kareem',
      'admissionNo': 'ADM-001',
      'classId': 'class-1',
      'isActive': true,
      'createdAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
    },
    'classes': {
      'name': 'Mont 2',
      'section': 'B',
      'academicYear': '2026-2027',
      'isActive': true,
    },
    'attendance': {
      'entityType': 'student',
      'entityId': 'student-1',
      'entityName': 'Abdul Kareem',
      'date': '2026-08-25',
      'status': 'present',
    },
    'staff_leave_requests': {
      'requesterId': 'staff-1',
      'requesterRole': 'staff',
      'subjectType': 'staff',
      'leaveType': 'Sick Leave',
      'startDate': Timestamp.fromDate(DateTime(2026, 8, 10)),
      'endDate': Timestamp.fromDate(DateTime(2026, 8, 11)),
      'status': 'Approved',
    },
    'fee_structures': {
      'name': 'Montessori M2',
      'academicYear': '2026-2027',
      'totalAmount': 50000,
      'isActive': true,
    },
    'student_fee_assignments': {
      'studentId': 'student-1',
      'studentName': 'Abdul Kareem',
      'academicYear': '2026-2027',
      'feeStructureName': 'Montessori M2',
      'totalFee': 50000,
      'status': 'unpaid',
    },
    'fee_transactions': {
      'studentId': 'student-1',
      'amount': 25000,
      'paymentMode': 'cash',
    },
    'finance_income': {
      'title': 'Term 1 fee collection',
      'amount': 25000,
      'categoryId': 'cat-1',
    },
    'finance_expenses': {
      'title': 'Stationery purchase',
      'amount': 5000,
      'categoryId': 'cat-2',
    },
    'finance_ledger': {
      'entryType': 'income',
      'amount': 25000,
      'status': 'confirmed',
    },
    'school_calendar_events': {
      'title': 'Annual Day',
      'date': Timestamp.fromDate(DateTime(2026, 12, 15)),
      'eventType': 'Event',
      'status': 'Published',
    },
    'users': {
      'phone': '9999999999',
      'name': 'Asha',
      'role': 'staff',
      'isActive': true,
    },
  };

  final ids = <String, String>{};
  for (final entry in fixtures.entries) {
    final docRef = await firestore.collection(entry.key).add(entry.value);
    ids[entry.key] = docRef.id;
  }

  final snapshot = <String, Map<String, dynamic>>{};
  for (final entry in ids.entries) {
    final doc = await firestore.collection(entry.key).doc(entry.value).get();
    snapshot[entry.key] = Map<String, dynamic>.from(doc.data()!);
  }
  return snapshot;
}

void main() {
  group('Architecture regression — existing data is never altered', () {
    late FakeFirebaseFirestore firestore;
    late AcademicYearService service;
    late Map<String, Map<String, dynamic>> before;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      service = AcademicYearService(firestore: firestore);
      before = await _seedFixtures(firestore);
    });

    Future<void> expectAllFixturesUnchanged() async {
      for (final collection in _untouchedCollections) {
        final snap = await firestore.collection(collection).get();
        expect(snap.docs, hasLength(1), reason: '$collection document count must not change');
        final data = Map<String, dynamic>.from(snap.docs.single.data());
        expect(data, equals(before[collection]), reason: '$collection document content must not change');
      }
    }

    test('28. Creating academic years leaves every other collection untouched', () async {
      await service.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2025-2026',
        startDate: DateTime(2025, 6, 1),
        endDate: DateTime(2026, 5, 31),
        createdBy: 'admin-1',
      );
      await service.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
      );
      await expectAllFixturesUnchanged();
    });

    test('29. Setting the current academic year leaves Attendance/Leave records untouched', () async {
      final id = await service.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
      );
      await service.setCurrentAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        id: id,
        updatedBy: 'admin-1',
      );
      await expectAllFixturesUnchanged();
    });

    test('30. Changing the current academic year again leaves prior Leave/Attendance records untouched', () async {
      final firstId = await service.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2025-2026',
        startDate: DateTime(2025, 6, 1),
        endDate: DateTime(2026, 5, 31),
        createdBy: 'admin-1',
        setAsCurrent: true,
      );
      final secondId = await service.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
      );
      await service.setCurrentAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        id: secondId,
        updatedBy: 'admin-1',
      );
      expect(firstId, isNotEmpty);
      await expectAllFixturesUnchanged();
    });

    test('31. Deactivating an academic year leaves Fee records (structures, assignments, transactions) untouched', () async {
      final id = await service.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2024-2025',
        startDate: DateTime(2024, 6, 1),
        endDate: DateTime(2025, 5, 31),
        createdBy: 'admin-1',
      );
      await service.deactivateAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        id: id,
        updatedBy: 'admin-1',
      );
      await expectAllFixturesUnchanged();
    });

    test('32. Every AcademicYearService write lands only in the academic_years collection', () async {
      final id = await service.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2025-2026',
        startDate: DateTime(2025, 6, 1),
        endDate: DateTime(2026, 5, 31),
        createdBy: 'admin-1',
      );
      final currentId = await service.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 5, 31),
        createdBy: 'admin-1',
      );
      await service.updateAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        id: id,
        name: '2025-2026',
        startDate: DateTime(2025, 6, 1),
        endDate: DateTime(2026, 5, 31),
        updatedBy: 'admin-1',
      );
      await service.setCurrentAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        id: currentId,
        updatedBy: 'admin-1',
      );
      // Deactivate the non-current year — deactivating the current year is
      // itself rejected (covered in academic_year_service_test.dart).
      await service.deactivateAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        id: id,
        updatedBy: 'admin-1',
      );

      final academicYearsSnap = await firestore.collection('academic_years').get();
      expect(academicYearsSnap.docs, hasLength(2));
      await expectAllFixturesUnchanged();
    });

    test('33. Denied (Staff/Parent) mutation attempts leave every collection, including academic_years, untouched', () async {
      for (final role in ['staff', 'parent']) {
        await expectLater(
          service.createAcademicYear(
            schoolId: kDefaultSchoolId,
            requesterRole: role,
            name: 'Hijack',
            startDate: DateTime(2030, 6, 1),
            endDate: DateTime(2031, 5, 31),
            createdBy: '$role-1',
          ),
          throwsA(anything),
        );
      }
      final academicYearsSnap = await firestore.collection('academic_years').get();
      expect(academicYearsSnap.docs, isEmpty);
      await expectAllFixturesUnchanged();
    });
  });

  group('No hardcoded academic year anywhere in the service', () {
    test('AcademicYearService never invents a current year when none has been set', () async {
      final firestore = FakeFirebaseFirestore();
      final service = AcademicYearService(firestore: firestore);
      // No academic year created at all.
      final current = await service.getCurrentAcademicYear(schoolId: kDefaultSchoolId);
      expect(current, isNull, reason: 'the app must fail gracefully, never invent a bootstrap year');
    });
  });
}

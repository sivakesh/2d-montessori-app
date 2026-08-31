// AY-IMPLEMENT-03 coverage (items 11-15): LeaveService.getStaffRequestsForAcademicYear
// and getStudentRequestsForAcademicYear — date-derived reporting support
// using the audit-approved startDate-only attribution rule. Never writes or
// reads academicYearId; the leave schema itself is untouched.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/data/academic_year_service.dart';
import 'package:montessori_app/modules/admin/settings/models/academic_year_date_range.dart';
import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/leave/services/leave_service.dart';

Future<void> _seedLeave(
  FakeFirebaseFirestore firestore, {
  required String id,
  required String subjectType,
  required DateTime startDate,
  required DateTime endDate,
  String status = 'pending',
  String? studentId,
}) {
  return firestore.collection('staff_leave_requests').doc(id).set({
    'requesterId': 'r1',
    'requesterName': 'Requester',
    'requesterRole': subjectType == 'staff' ? 'staff' : 'parent',
    'subjectType': subjectType,
    'studentId': studentId,
    'studentName': studentId != null ? 'Student $studentId' : null,
    'leaveType': 'sick',
    'startDate': startDate,
    'endDate': endDate,
    'reason': 'test',
    'status': status,
    'createdAt': startDate,
    'updatedAt': startDate,
  });
}

Future<AcademicYearDateRange> _seedCurrentYearRange(FakeFirebaseFirestore firestore) async {
  final ayService = AcademicYearService(firestore: firestore);
  final id = await ayService.createAcademicYear(
    schoolId: kDefaultSchoolId,
    requesterRole: 'admin',
    name: '2026-2027',
    startDate: DateTime(2026, 6, 1),
    endDate: DateTime(2027, 3, 30),
    createdBy: 'admin-1',
  );
  final year = await ayService.getAcademicYearById(schoolId: kDefaultSchoolId, id: id);
  return AcademicYearDateRange.fromAcademicYear(year!);
}

void main() {
  group('LeaveService academic-year reporting (AY-IMPLEMENT-03)', () {
    test('11. Staff leave whose startDate falls within the Academic Year is included', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedLeave(
        firestore,
        id: 'l1',
        subjectType: 'staff',
        startDate: DateTime(2026, 12, 25),
        endDate: DateTime(2026, 12, 27),
      );
      final range = await _seedCurrentYearRange(firestore);
      final service = LeaveService(firestore: firestore);

      final result = await service.getStaffRequestsForAcademicYear(range);
      expect(result.any((r) => r.id == 'l1'), isTrue);
    });

    test('12. A staff leave request is attributed by startDate only, even when endDate crosses the Academic Year boundary', () async {
      final firestore = FakeFirebaseFirestore();
      // Starts the day before the Academic Year begins, but ends well
      // inside it. The audit-approved rule says startDate alone decides —
      // this request must NOT appear in the 2026-2027 year's results.
      await _seedLeave(
        firestore,
        id: 'crossing',
        subjectType: 'staff',
        startDate: DateTime(2026, 5, 31),
        endDate: DateTime(2026, 6, 5),
      );
      final range = await _seedCurrentYearRange(firestore);
      final service = LeaveService(firestore: firestore);

      final result = await service.getStaffRequestsForAcademicYear(range);
      expect(result.any((r) => r.id == 'crossing'), isFalse);
    });

    test('13. Student leave whose startDate falls within the Academic Year is included (sibling of staff leave)', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedLeave(
        firestore,
        id: 'sl1',
        subjectType: 'student',
        startDate: DateTime(2026, 9, 10),
        endDate: DateTime(2026, 9, 11),
        studentId: 's1',
      );
      final range = await _seedCurrentYearRange(firestore);
      final service = LeaveService(firestore: firestore);

      final result = await service.getStudentRequestsForAcademicYear(range);
      expect(result.any((r) => r.id == 'sl1'), isTrue);
    });

    test('14. A leave request is never split across two Academic Years: it appears in exactly one year\'s results, never both', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedLeave(
        firestore,
        id: 'crossing2',
        subjectType: 'staff',
        startDate: DateTime(2026, 5, 31),
        endDate: DateTime(2026, 6, 5),
      );
      final ayService = AcademicYearService(firestore: firestore);
      final prevId = await ayService.createAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: 'admin',
        name: '2025-2026',
        startDate: DateTime(2025, 6, 1),
        endDate: DateTime(2026, 5, 31),
        createdBy: 'admin-1',
      );
      final currentRange = await _seedCurrentYearRange(firestore);
      final prevYear = await ayService.getAcademicYearById(schoolId: kDefaultSchoolId, id: prevId);
      final prevRange = AcademicYearDateRange.fromAcademicYear(prevYear!);
      final service = LeaveService(firestore: firestore);

      final inPrev = await service.getStaffRequestsForAcademicYear(prevRange);
      final inCurrent = await service.getStaffRequestsForAcademicYear(currentRange);

      expect(inPrev.any((r) => r.id == 'crossing2'), isTrue,
          reason: 'startDate 2026-05-31 belongs to the 2025-2026 year');
      expect(inCurrent.any((r) => r.id == 'crossing2'), isFalse,
          reason: 'must not also appear in 2026-2027 just because endDate crosses into it');
    });

    test('15. No academicYearId is written to any leave document by this feature', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedLeave(
        firestore,
        id: 'l2',
        subjectType: 'staff',
        startDate: DateTime(2026, 12, 25),
        endDate: DateTime(2026, 12, 27),
      );
      final range = await _seedCurrentYearRange(firestore);
      final service = LeaveService(firestore: firestore);

      await service.getStaffRequestsForAcademicYear(range);

      final doc = await firestore.collection('staff_leave_requests').doc('l2').get();
      expect(doc.data()!.containsKey('academicYearId'), isFalse);
    });
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/student_enrollment_model.dart';

/// Reads/writes Student Enrollments — the historical record of which class
/// a student belonged to in a given academic year. One document per
/// `(studentId, academicYearId)` "episode" in a top-level
/// `student_enrollments` collection, each carrying an explicit `schoolId`
/// field — the exact same "many records scoped by a `schoolId` field"
/// shape [AcademicYearService] uses for `academic_years`, so this is
/// already correct for whenever real multi-tenancy is introduced.
///
/// This service never touches `Student.classId`, `AdminClassModel`, or any
/// other existing collection except via [assignStudentToClassForYear]'s
/// opt-in `syncStudentClassId` — see that method's doc comment. Every
/// existing Student/Class/Attendance/Fees query keeps reading
/// `Student.classId` exactly as it always has; this service is purely
/// additive.
///
/// Mutating methods take an explicit `requesterRole` and re-check it's
/// Admin *or* Staff (throwing [UnauthorizedStudentEnrollmentException]
/// otherwise) — see that exception's doc comment for why Staff is allowed,
/// unlike [AcademicYearService]'s Admin-only mutations.
class StudentEnrollmentService {
  StudentEnrollmentService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _enrollments =>
      _firestore.collection('student_enrollments');
  CollectionReference<Map<String, dynamic>> get _students =>
      _firestore.collection('students');

  void _requireStaffOrAdmin(String requesterRole) {
    final role = requesterRole.toLowerCase();
    if (role != 'admin' && role != 'staff') {
      throw UnauthorizedStudentEnrollmentException(requesterRole);
    }
  }

  /// Every enrollment episode for [studentId] (any academic year, any
  /// status), newest [enrollmentDate] first — a student's full "Academic
  /// History". Never a different school's records — the `schoolId` field
  /// is this service's isolation boundary, exactly like
  /// [AcademicYearService.getAllAcademicYears].
  Future<List<StudentEnrollmentModel>> getEnrollmentsForStudent({
    required String schoolId,
    required String studentId,
  }) async {
    final snapshot = await _enrollments
        .where('schoolId', isEqualTo: schoolId)
        .where('studentId', isEqualTo: studentId)
        .get();
    final list = snapshot.docs
        .map((doc) => StudentEnrollmentModel.fromMap(doc.id, doc.data()))
        .toList()
      ..sort((a, b) => b.enrollmentDate.compareTo(a.enrollmentDate));
    return list;
  }

  /// Every Active enrollment for [classId] within [academicYearId] — the
  /// class roster for that specific year, derived from enrollment history
  /// rather than the student's current `classId`. Not yet wired into any
  /// existing Class UI (see AY-01's architecture report) — offered for
  /// Reports and future year-aware class rosters.
  Future<List<StudentEnrollmentModel>> getEnrollmentsForClass({
    required String schoolId,
    required String classId,
    required String academicYearId,
  }) async {
    final snapshot = await _enrollments
        .where('schoolId', isEqualTo: schoolId)
        .where('classId', isEqualTo: classId)
        .get();
    return snapshot.docs
        .map((doc) => StudentEnrollmentModel.fromMap(doc.id, doc.data()))
        .where((e) => e.academicYearId == academicYearId && e.isActive)
        .toList();
  }

  /// The single Active enrollment for [studentId] within [academicYearId],
  /// or null if none exists — the basis of the "at most one active
  /// enrollment per student per academic year" rule enforced in
  /// [createEnrollment].
  Future<StudentEnrollmentModel?> getActiveEnrollment({
    required String schoolId,
    required String studentId,
    required String academicYearId,
  }) async {
    final list = await getEnrollmentsForStudent(schoolId: schoolId, studentId: studentId);
    for (final enrollment in list) {
      if (enrollment.academicYearId == academicYearId && enrollment.isActive) return enrollment;
    }
    return null;
  }

  /// A single enrollment by [id], or null if it doesn't exist or belongs to
  /// a different school.
  Future<StudentEnrollmentModel?> getEnrollmentById({
    required String schoolId,
    required String id,
  }) async {
    final doc = await _enrollments.doc(id).get();
    final data = doc.data();
    if (!doc.exists || data == null) return null;
    if (data['schoolId']?.toString() != schoolId) return null;
    return StudentEnrollmentModel.fromMap(doc.id, data);
  }

  /// Creates a new enrollment episode. Validates [studentId]/
  /// [academicYearId]/[classId] are non-empty, and — when [status] is
  /// Active (the default) — that [studentId] has no other Active
  /// enrollment for [academicYearId] yet, throwing
  /// [DuplicateActiveEnrollmentException] otherwise. Never validates
  /// against `Student.classId` or writes to it — see
  /// [assignStudentToClassForYear] for the one path that keeps both in
  /// sync.
  Future<String> createEnrollment({
    required String schoolId,
    required String requesterRole,
    required String studentId,
    required String academicYearId,
    required String classId,
    String status = StudentEnrollmentStatus.active,
    DateTime? enrollmentDate,
    required String createdBy,
  }) async {
    _requireStaffOrAdmin(requesterRole);

    if (studentId.trim().isEmpty) {
      throw StudentEnrollmentValidationException('A student is required.');
    }
    if (academicYearId.trim().isEmpty) {
      throw StudentEnrollmentValidationException('An academic year is required.');
    }
    if (classId.trim().isEmpty) {
      throw StudentEnrollmentValidationException('A class is required.');
    }
    if (!StudentEnrollmentStatus.all.contains(status)) {
      throw StudentEnrollmentValidationException('"$status" is not a valid enrollment status.');
    }

    if (status == StudentEnrollmentStatus.active) {
      final existingActive = await getActiveEnrollment(
        schoolId: schoolId,
        studentId: studentId,
        academicYearId: academicYearId,
      );
      if (existingActive != null) {
        throw DuplicateActiveEnrollmentException(studentId: studentId, academicYearId: academicYearId);
      }
    }

    final docRef = _enrollments.doc();
    await docRef.set({
      'schoolId': schoolId,
      'studentId': studentId,
      'academicYearId': academicYearId,
      'classId': classId,
      'status': status,
      'enrollmentDate': Timestamp.fromDate(enrollmentDate ?? DateTime.now()),
      'leavingDate': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
      'updatedBy': createdBy,
    });
    return docRef.id;
  }

  /// Updates an existing enrollment episode's [classId]/[status]/
  /// [leavingDate] in place. This is how a student's class changes
  /// *within* the same academic year (e.g. moved from one section to
  /// another) without creating a second enrollment row for that year, and
  /// how an episode is marked Completed/Withdrawn at year-end. Never
  /// changes [StudentEnrollmentModel.studentId]/[StudentEnrollmentModel.academicYearId]
  /// — an enrollment always belongs to the same student and year it was
  /// created for; a student moving to a *different* academic year gets a
  /// new episode via [createEnrollment] instead. Past episodes (any
  /// enrollment other than the one [id] identifies) are never touched.
  Future<void> updateEnrollment({
    required String schoolId,
    required String requesterRole,
    required String id,
    String? classId,
    String? status,
    DateTime? leavingDate,
    required String updatedBy,
  }) async {
    _requireStaffOrAdmin(requesterRole);

    final existing = await getEnrollmentById(schoolId: schoolId, id: id);
    if (existing == null) throw StudentEnrollmentNotFoundException(id);

    if (classId != null && classId.trim().isEmpty) {
      throw StudentEnrollmentValidationException('A class is required.');
    }
    if (status != null && !StudentEnrollmentStatus.all.contains(status)) {
      throw StudentEnrollmentValidationException('"$status" is not a valid enrollment status.');
    }

    final payload = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
    };
    if (classId != null) payload['classId'] = classId;
    if (status != null) payload['status'] = status;
    if (leavingDate != null) payload['leavingDate'] = Timestamp.fromDate(leavingDate);
    await _enrollments.doc(id).update(payload);
  }

  /// The "smallest necessary mechanism" for an Admin/Staff to assign
  /// [studentId] to [classId] for [academicYearId]: reuses (and re-points)
  /// the student's existing Active enrollment for that year if one exists,
  /// otherwise creates a new one — never creates a second Active episode
  /// for the same student+year (the caller never has to check first).
  ///
  /// [syncStudentClassId] (default false) additionally writes [classId]
  /// onto `Student.classId` — the *current-placement convenience field*
  /// every existing Student/Class/Attendance/Fees query still reads. Pass
  /// `true` only when [academicYearId] is the currently-selected academic
  /// year (the UI is responsible for that decision, via
  /// `currentAcademicYearProvider` — this service deliberately has no
  /// notion of "current" itself, to stay decoupled from SETTINGS-02's
  /// AcademicYearService). Assigning a *past* year's class must never
  /// overwrite the student's current placement, so callers must pass
  /// `false` (the default) in that case.
  Future<void> assignStudentToClassForYear({
    required String schoolId,
    required String requesterRole,
    required String studentId,
    required String academicYearId,
    required String classId,
    bool syncStudentClassId = false,
    required String actorId,
  }) async {
    _requireStaffOrAdmin(requesterRole);

    final existing = await getActiveEnrollment(
      schoolId: schoolId,
      studentId: studentId,
      academicYearId: academicYearId,
    );
    if (existing == null) {
      await createEnrollment(
        schoolId: schoolId,
        requesterRole: requesterRole,
        studentId: studentId,
        academicYearId: academicYearId,
        classId: classId,
        createdBy: actorId,
      );
    } else if (existing.classId != classId) {
      await updateEnrollment(
        schoolId: schoolId,
        requesterRole: requesterRole,
        id: existing.id,
        classId: classId,
        updatedBy: actorId,
      );
    }

    if (syncStudentClassId) {
      await _students.doc(studentId).set({
        'classId': classId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }
}

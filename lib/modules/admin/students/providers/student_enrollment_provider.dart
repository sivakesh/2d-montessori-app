import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/models/school_settings_model.dart' show kDefaultSchoolId;
import '../data/admin_student_service.dart';
import '../data/student_enrollment_service.dart';
import '../models/student_enrollment_model.dart';

/// Shared [StudentEnrollmentService] instance — the same "one provider
/// wraps the real service, tests override it" shape as
/// `academicYearServiceProvider`.
final studentEnrollmentServiceProvider =
    Provider<StudentEnrollmentService>((ref) => StudentEnrollmentService());

/// Shared [AdminStudentService] instance — introduced so
/// [StudentEnrollmentAssignDialog] (opened directly from
/// [AcademicHistorySection], with no constructor-injection path of its
/// own for that in-app entry point) can be overridden in tests the same
/// way, rather than always constructing the real Firebase-backed default.
final adminStudentServiceProvider = Provider<AdminStudentService>((ref) => AdminStudentService());

/// A student's full Academic History (every enrollment episode, any
/// academic year, newest first) for [kDefaultSchoolId] — the Student View
/// dialog's "Academic History" tab. Keyed by `studentId` so each open
/// dialog watches only its own student.
///
/// `autoDispose` so history for a closed dialog isn't kept alive. Call
/// `ref.invalidate(studentEnrollmentsProvider(studentId))` after
/// `createEnrollment`/`updateEnrollment`/`assignStudentToClassForYear` so
/// an already-open "Academic History" tab reflects the change immediately.
final studentEnrollmentsProvider =
    FutureProvider.autoDispose.family<List<StudentEnrollmentModel>, String>((ref, studentId) {
  final service = ref.watch(studentEnrollmentServiceProvider);
  return service.getEnrollmentsForStudent(schoolId: kDefaultSchoolId, studentId: studentId);
});

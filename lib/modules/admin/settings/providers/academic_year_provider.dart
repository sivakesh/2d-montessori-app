import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/academic_year_service.dart';
import '../models/academic_year_model.dart';
import '../models/school_settings_model.dart' show kDefaultSchoolId;

/// Shared [AcademicYearService] instance — lets every provider/screen below
/// depend on the same service (and tests override it with a fake-Firestore-
/// backed instance) rather than each constructing its own.
final academicYearServiceProvider = Provider<AcademicYearService>((ref) => AcademicYearService());

/// Every academic year for [kDefaultSchoolId], newest first — the Academic
/// Year Settings screen's list. `autoDispose` so a stale list isn't kept
/// alive once the screen is popped; call
/// `ref.invalidate(academicYearsProvider)` after any create/update/
/// set-current/(de)activate so an already-open list picks up the change
/// immediately, the same refresh convention [schoolIdentityProvider] uses
/// after a School Settings save.
final academicYearsProvider = FutureProvider.autoDispose<List<AcademicYearModel>>((ref) {
  final service = ref.watch(academicYearServiceProvider);
  return service.getAllAcademicYears(schoolId: kDefaultSchoolId);
});

/// The single source of truth for "which academic year is current right
/// now" — every future module (Students, Classes, Fees, Attendance, Leave,
/// Finance, Reports) should read the current academic year through this
/// provider instead of each implementing its own query.
///
/// Resolves to null — never throws — both when nothing has been set current
/// yet (no academic year exists, or one exists but isn't current) and on a
/// transient read failure, exactly like [schoolIdentityProvider]'s own
/// null-safe contract. Every consumer must treat null as "no current
/// academic year" and fail gracefully (e.g. prompt to create one in
/// Settings) rather than guessing or inventing one.
///
/// Call `ref.invalidate(currentAcademicYearProvider)` after
/// `setCurrentAcademicYear` (or after creating a year with
/// `setAsCurrent: true`) so already-open screens pick up the new current
/// year without an app restart.
final currentAcademicYearProvider = FutureProvider<AcademicYearModel?>((ref) async {
  final service = ref.watch(academicYearServiceProvider);
  try {
    return await service.getCurrentAcademicYear(schoolId: kDefaultSchoolId);
  } catch (_) {
    return null;
  }
});

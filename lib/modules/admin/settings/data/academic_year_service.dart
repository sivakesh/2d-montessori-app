import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../models/academic_year_model.dart';

/// Reads/writes Academic Years — one document per year in a top-level
/// `academic_years` collection, each carrying an explicit `schoolId` field.
/// Mirrors [SchoolSettingsService]'s own `kDefaultSchoolId`-scoped shape
/// (every method takes an explicit `schoolId` rather than hardcoding it, so
/// the isolation boundary is already correct for whenever real
/// multi-tenancy is introduced) — the only difference is School Settings is
/// one document per school (`school_settings/{schoolId}`), while a school
/// has *many* academic years, so those live as multiple documents in one
/// collection, each scoped by a `schoolId` field instead of by document id.
///
/// Every mutating method (`create`/`update`/`setCurrent`/`deactivate`/
/// `activate`) takes an explicit `requesterRole` and re-checks it's 'admin'
/// itself (throwing [UnauthorizedAcademicYearException] otherwise) — the
/// same "never trust the caller, verify server-side" shape
/// [SchoolSettingsService] and [LeaveService] already use. Reads
/// (`getAllAcademicYears`/`getCurrentAcademicYear`/`getAcademicYearById`)
/// are never role-gated, since other modules across the app need to read
/// the current academic year regardless of the signed-in role.
///
/// There is deliberately no `deleteAcademicYear` — the SETTINGS-02 spec
/// requires never allowing deletion where it could orphan historical
/// records, and nothing in this service can prove a year is unreferenced,
/// so deletion simply isn't offered. [deactivateAcademicYear] is the only
/// way to retire a year, and it never removes data.
class AcademicYearService {
  AcademicYearService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _academicYears =>
      _firestore.collection('academic_years');

  final DateFormat _dateFormat = DateFormat('MMM d, yyyy');

  void _requireAdmin(String requesterRole) {
    if (requesterRole.toLowerCase() != 'admin') {
      throw UnauthorizedAcademicYearException(requesterRole);
    }
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Every academic year for [schoolId], newest ([startDate]) first. Never
  /// a different school's years — the `schoolId` field is this service's
  /// isolation boundary, exactly like the document-id boundary
  /// [SchoolSettingsService] uses for its single settings document.
  /// Filters/sorts client-side (rather than `.orderBy()` in the query) so
  /// this never requires a Firestore composite index — a school's academic
  /// year count is small (one document per year), so this is cheap.
  Future<List<AcademicYearModel>> getAllAcademicYears({
    required String schoolId,
  }) async {
    final snapshot = await _academicYears.where('schoolId', isEqualTo: schoolId).get();
    final years = snapshot.docs
        .map((doc) => AcademicYearModel.fromMap(doc.id, doc.data()))
        .toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    return years;
  }

  /// The one academic year for [schoolId] with `isCurrent == true`, or null
  /// if none has ever been set current yet (e.g. no academic year exists,
  /// or one exists but nobody has set it current). Callers must treat null
  /// as "no current academic year" and fail gracefully — never invent one.
  Future<AcademicYearModel?> getCurrentAcademicYear({
    required String schoolId,
  }) async {
    final years = await getAllAcademicYears(schoolId: schoolId);
    for (final year in years) {
      if (year.isCurrent) return year;
    }
    return null;
  }

  /// A single academic year by [id], or null if it doesn't exist *or*
  /// belongs to a different school — the same "never a different school's
  /// record" isolation [getAllAcademicYears] provides, applied to a direct
  /// by-id lookup.
  Future<AcademicYearModel?> getAcademicYearById({
    required String schoolId,
    required String id,
  }) async {
    final doc = await _academicYears.doc(id).get();
    final data = doc.data();
    if (!doc.exists || data == null) return null;
    if (data['schoolId']?.toString() != schoolId) return null;
    return AcademicYearModel.fromMap(doc.id, data);
  }

  void _validateRange(DateTime startDate, DateTime endDate) {
    final error = AcademicYearValidation.validateDates(startDate, endDate);
    if (error != null) throw AcademicYearValidationException(error);
  }

  Future<void> _checkNoOverlap({
    required String schoolId,
    required DateTime startDate,
    required DateTime endDate,
    String? excludeId,
  }) async {
    final years = await getAllAcademicYears(schoolId: schoolId);
    for (final year in years) {
      if (excludeId != null && year.id == excludeId) continue;
      if (year.overlaps(startDate, endDate)) {
        throw AcademicYearOverlapException(
          'This date range overlaps with "${year.name}" '
          '(${_dateFormat.format(year.startDate)} - ${_dateFormat.format(year.endDate)}).',
        );
      }
    }
  }

  Future<void> _checkNoDuplicateName({
    required String schoolId,
    required String name,
    String? excludeId,
  }) async {
    final years = await getAllAcademicYears(schoolId: schoolId);
    final normalized = name.trim().toLowerCase();
    final duplicate = years.any(
      (year) => year.id != excludeId && year.name.trim().toLowerCase() == normalized,
    );
    if (duplicate) {
      throw AcademicYearValidationException('An academic year named "${name.trim()}" already exists.');
    }
  }

  /// Creates a new academic year for [schoolId]. Validates [name] (required,
  /// no duplicate) and the date range (end after start, no overlap with any
  /// existing year for this school) before writing anything — a direct
  /// service call can never persist an invalid/overlapping record even if a
  /// UI slip skipped its own validation. The new document's id is a
  /// Firestore auto-id, never derived from [name], so a later rename can
  /// never change its identity.
  ///
  /// If [setAsCurrent] is true, [setCurrentAcademicYear] runs immediately
  /// after creation (unsetting any previous current year) — offered so the
  /// UI can create-and-activate in one admin action rather than two.
  Future<String> createAcademicYear({
    required String schoolId,
    required String requesterRole,
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required String createdBy,
    bool setAsCurrent = false,
  }) async {
    _requireAdmin(requesterRole);

    final nameError = AcademicYearValidation.validateName(name);
    if (nameError != null) throw AcademicYearValidationException(nameError);
    final start = _dateOnly(startDate);
    final end = _dateOnly(endDate);
    _validateRange(start, end);
    await _checkNoDuplicateName(schoolId: schoolId, name: name);
    await _checkNoOverlap(schoolId: schoolId, startDate: start, endDate: end);

    final docRef = _academicYears.doc();
    await docRef.set({
      'schoolId': schoolId,
      'name': name.trim(),
      'startDate': Timestamp.fromDate(start),
      'endDate': Timestamp.fromDate(end),
      'isCurrent': false,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
      'updatedBy': createdBy,
    });

    if (setAsCurrent) {
      await setCurrentAcademicYear(
        schoolId: schoolId,
        requesterRole: requesterRole,
        id: docRef.id,
        updatedBy: createdBy,
      );
    }
    return docRef.id;
  }

  /// Updates an existing academic year's [name]/date range. Re-validates
  /// exactly like [createAcademicYear] (required name, no duplicate, valid
  /// range, no overlap with any *other* year — [id] itself is excluded from
  /// both the duplicate-name and overlap checks so a year can keep its own
  /// name/dates unchanged). Never touches [AcademicYearModel.isCurrent] or
  /// [AcademicYearModel.isActive] — those are only ever changed by
  /// [setCurrentAcademicYear]/[deactivateAcademicYear]/[activateAcademicYear].
  Future<void> updateAcademicYear({
    required String schoolId,
    required String requesterRole,
    required String id,
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required String updatedBy,
  }) async {
    _requireAdmin(requesterRole);

    final existing = await getAcademicYearById(schoolId: schoolId, id: id);
    if (existing == null) throw AcademicYearNotFoundException(id);

    final nameError = AcademicYearValidation.validateName(name);
    if (nameError != null) throw AcademicYearValidationException(nameError);
    final start = _dateOnly(startDate);
    final end = _dateOnly(endDate);
    _validateRange(start, end);
    await _checkNoDuplicateName(schoolId: schoolId, name: name, excludeId: id);
    await _checkNoOverlap(schoolId: schoolId, startDate: start, endDate: end, excludeId: id);

    await _academicYears.doc(id).update({
      'name': name.trim(),
      'startDate': Timestamp.fromDate(start),
      'endDate': Timestamp.fromDate(end),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
    });
  }

  /// Sets [id] as the current academic year for [schoolId] and atomically
  /// unsets whichever year was previously current (via a single Firestore
  /// batch — either both writes land or neither does, so there is never a
  /// moment with zero or two current years visible to a reader). This is
  /// the *only* code path that can change which year is current: changing
  /// the current year never alters any other year's name/dates/isActive,
  /// and never touches Student/Attendance/Leave/Fees/Finance/Calendar data.
  Future<void> setCurrentAcademicYear({
    required String schoolId,
    required String requesterRole,
    required String id,
    required String updatedBy,
  }) async {
    _requireAdmin(requesterRole);

    final target = await getAcademicYearById(schoolId: schoolId, id: id);
    if (target == null) throw AcademicYearNotFoundException(id);
    if (!target.isActive) {
      throw AcademicYearValidationException(
        'Cannot set an inactive academic year as current. Activate it first.',
      );
    }
    if (target.isCurrent) return;

    final years = await getAllAcademicYears(schoolId: schoolId);
    final batch = _firestore.batch();
    for (final year in years) {
      if (year.id != id && year.isCurrent) {
        batch.update(_academicYears.doc(year.id), {
          'isCurrent': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    batch.update(_academicYears.doc(id), {
      'isCurrent': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
    });
    await batch.commit();
  }

  /// Deactivates (never deletes) an academic year — it stops being offered
  /// as a target for "Set as Current" but every historical record that
  /// relates to it is completely untouched. Refuses to deactivate the
  /// *current* year (there must always be an active current year, or none
  /// at all — never a deactivated one silently left "current") — the admin
  /// must set a different year current first.
  Future<void> deactivateAcademicYear({
    required String schoolId,
    required String requesterRole,
    required String id,
    required String updatedBy,
  }) async {
    _requireAdmin(requesterRole);

    final target = await getAcademicYearById(schoolId: schoolId, id: id);
    if (target == null) throw AcademicYearNotFoundException(id);
    if (target.isCurrent) {
      throw AcademicYearValidationException(
        'Cannot deactivate the current academic year. Set another year as current first.',
      );
    }

    await _academicYears.doc(id).update({
      'isActive': false,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
    });
  }

  /// Reactivates a previously deactivated academic year, making it eligible
  /// again as a "Set as Current" target. Symmetric counterpart to
  /// [deactivateAcademicYear], offered so the Settings UI's
  /// Activate/Deactivate toggle can go both ways.
  Future<void> activateAcademicYear({
    required String schoolId,
    required String requesterRole,
    required String id,
    required String updatedBy,
  }) async {
    _requireAdmin(requesterRole);

    final target = await getAcademicYearById(schoolId: schoolId, id: id);
    if (target == null) throw AcademicYearNotFoundException(id);

    await _academicYears.doc(id).update({
      'isActive': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': updatedBy,
    });
  }
}

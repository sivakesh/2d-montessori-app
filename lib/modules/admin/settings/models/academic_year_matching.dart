import 'academic_year_model.dart';

/// The shared "safe matching strategy" between a free-text Class
/// `academicYear` string (`AdminClassModel.academicYear` — still a plain
/// string, not `academicYearId`; see AY-01-R1/AY-02's architecture reports
/// for why introducing that foreign key is explicitly out of scope) and
/// the canonical [AcademicYearModel]. Used by both:
///
/// - AY-01-R1's Add/Edit Student form, to filter the Class dropdown down
///   to classes belonging to the selected Academic Year, and
/// - AY-02's Add/Edit Class form, to resolve an existing class's own
///   stored `academicYear` string back to a canonical [AcademicYearModel]
///   so the correct year can be preselected in its own dropdown.
///
/// A class is considered part of [year] only if its existing free-text
/// `academicYear` field matches [year]'s display [AcademicYearModel.name]
/// exactly, ignoring case/surrounding whitespace. This is deliberately a
/// known, documented limitation rather than a guess: a class whose
/// free-text field uses a different label/format than the academic year's
/// name (e.g. was typed by hand, or the year was renamed after the class
/// was created) simply won't match — there is no reliable way to match
/// them otherwise without the Class migration both tasks explicitly
/// exclude. Callers that need to detect this ("orphaned" academicYear —
/// AY-02) should check whether *any* year in the full list satisfies this
/// match, not just the current one.
bool classMatchesAcademicYear(Map<String, dynamic> classData, AcademicYearModel year) {
  final raw = classData['academicYear']?.toString().trim().toLowerCase() ?? '';
  if (raw.isEmpty) return false;
  return raw == year.name.trim().toLowerCase();
}

/// AY-IMPLEMENT-02-B: the additive-migration version of the match above.
/// `academicYearId` (once a Class has one) is authoritative — a migrated
/// Class is matched by id only, never by name, and the free-text
/// `academicYear` is never consulted once an id is present, even if the two
/// disagree. [classMatchesAcademicYear] remains the fallback for legacy
/// Class documents that have no `academicYearId` yet. This is the single
/// place that rule lives, so every caller filtering/resolving Classes by
/// year (the Student form's Class dropdown, the Class form's own Edit
/// resolution) applies it identically.
bool classBelongsToAcademicYear(Map<String, dynamic> classData, AcademicYearModel year) {
  final id = classData['academicYearId']?.toString().trim() ?? '';
  if (id.isNotEmpty) return id == year.id;
  return classMatchesAcademicYear(classData, year);
}

/// Resolves the *display* value for a Class's academic year from a
/// `{academicYearId: displayName}` lookup built once per screen (e.g. from
/// `academicYearsProvider`) — never fetched per row/dialog, so listing
/// Classes never issues one Academic Year query per Class. Mirrors
/// [classBelongsToAcademicYear]'s "id wins when present" rule: a resolvable
/// [academicYearId] always wins over the legacy [academicYear] string,
/// which is consulted only when the id is absent *or* doesn't resolve (the
/// lookup hasn't loaded yet, or that year was since deactivated out of it)
/// — exactly the fallback this function already had before `academicYearId`
/// existed. Returns `''` when neither can produce anything to display; never
/// invents a value.
///
/// Deliberately does not decide *how* to render an empty/unresolved result
/// (a dash, an "Unresolved" state, or omitting the row entirely) — that
/// differs by caller (an admin-facing list vs. a parent-facing profile) and
/// is each caller's own choice, checked via `academicYearId.isNotEmpty` to
/// tell "nothing at all" apart from "there was an id, it just didn't
/// resolve" where that distinction matters.
String resolveClassAcademicYearLabel({
  required String academicYearId,
  required String academicYear,
  required Map<String, String> academicYearNamesById,
}) {
  final id = academicYearId.trim();
  if (id.isNotEmpty) {
    final resolved = academicYearNamesById[id];
    if (resolved != null) return resolved;
  }
  return academicYear.trim();
}

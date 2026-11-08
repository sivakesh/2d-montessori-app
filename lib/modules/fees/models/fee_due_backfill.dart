import 'fee_due_date.dart';
import 'fee_month.dart';
import 'fee_structure_model.dart';
import 'student_fee_assignment_model.dart';

/// Where an existing assignment stands for Set Missing Due Dates.
enum FeeDueBackfillCategory {
  /// Already has a `dueDate`: never changed.
  hasDueDate('Already have a due date'),

  /// One unambiguous date from its structure's configuration.
  eligible('Eligible for automatic due date'),

  /// The structure's settings conflict or aren't usable (different days or
  /// dates, a mixed structure whose settings disagree, an invalid day).
  manualReview('Require manual review'),

  /// Its fee structure can't be found or has been deleted.
  structureMissing('Fee structure missing or unavailable'),

  /// No fee month (Monthly) or no due-date configuration to use.
  configMissing('Fee month or due-date configuration missing');

  const FeeDueBackfillCategory(this.label);
  final String label;

  /// Not updatable automatically and still without a due date.
  bool get needsAttention => this == manualReview || this == structureMissing || this == configMissing;
}

/// One assignment's classification: [proposedDate] for an eligible one,
/// otherwise [reason] says why it can't be calculated.
class FeeDueBackfillItem {
  const FeeDueBackfillItem(this.assignment, this.category, {this.proposedDate, this.reason = ''});

  final StudentFeeAssignmentModel assignment;
  final FeeDueBackfillCategory category;
  final DateTime? proposedDate;
  final String reason;

  FeeDueBackfillItem withReason(String reason) => FeeDueBackfillItem(assignment, category, proposedDate: proposedDate, reason: reason);
}

/// The read-only scan shown before anything is written.
class FeeDueBackfillPreview {
  FeeDueBackfillPreview(this.items);

  final List<FeeDueBackfillItem> items;

  int get scanned => items.length;
  List<FeeDueBackfillItem> of(FeeDueBackfillCategory c) => [for (final i in items) if (i.category == c) i];
  int count(FeeDueBackfillCategory c) => items.where((i) => i.category == c).length;
  List<FeeDueBackfillItem> get eligible => of(FeeDueBackfillCategory.eligible);
}

/// What Set Missing Due Dates did, record by record. Every list holds the
/// assignment and the saved or proposed date, or why it was skipped.
class FeeDueBackfillResult {
  const FeeDueBackfillResult({
    required this.updated,
    required this.alreadyHadDate,
    required this.changed,
    required this.failed,
    required this.stillNeedAttention,
    this.errors = const [],
  });

  /// Saved: each with its saved date ([FeeDueBackfillItem.proposedDate]).
  final List<FeeDueBackfillItem> updated;

  /// Skipped: a due date had been set since the preview.
  final List<FeeDueBackfillItem> alreadyHadDate;

  /// Skipped: the assignment or its structure changed or disappeared, so
  /// no date could be calculated any more.
  final List<FeeDueBackfillItem> changed;

  /// Not saved because a write failed ([errors]).
  final List<FeeDueBackfillItem> failed;

  /// Still without a due date and not updatable automatically: the
  /// preview's manual-review records plus any that became so.
  final List<FeeDueBackfillItem> stillNeedAttention;

  final List<String> errors;

  String get message => [
        'Updated ${updated.length}',
        'skipped ${alreadyHadDate.length} that already had a due date',
        'skipped ${changed.length} that changed or disappeared',
        'failed ${failed.length}',
        '${stillNeedAttention.length} still need manual review',
      ].join(', ') + (failed.isEmpty ? '.' : '. Some updates could not be saved: ${errors.join('; ')}');
}

abstract final class FeeDueBackfill {
  /// Classifies [a] with its fee structure [structure] (null when it can't
  /// be used, with [structureProblem] saying why), using
  /// FeeDueDate.defaultFor for the date itself:
  /// - A stored due date: [FeeDueBackfillCategory.hasDueDate].
  /// - Monthly (FeeMonth.isMonthlyStructure): the assignment's own stored
  ///   `feeMonth` with the components' Due Day of Month (the month's last
  ///   day when shorter). No or an invalid fee month, or no due day:
  ///   configuration missing; different or invalid days: manual review.
  /// - Term, One-time and mixed: the one unambiguous default defaultFor
  ///   gives. Nothing configured: configuration missing; settings that
  ///   conflict: manual review.
  /// Nothing else (creation or payment dates, academic year) is used.
  static FeeDueBackfillItem classify(StudentFeeAssignmentModel a, FeeStructureModel? structure, {String structureProblem = ''}) {
    if (a.dueDate != null) return FeeDueBackfillItem(a, FeeDueBackfillCategory.hasDueDate, reason: 'Has a due date (${FeeDueDate.label(a.dueDate!)}); left unchanged.');
    if (structure == null) {
      return FeeDueBackfillItem(a, FeeDueBackfillCategory.structureMissing,
          reason: structureProblem.isEmpty ? 'Its fee structure is not available.' : structureProblem);
    }
    FeeDueBackfillItem missing(String reason) => FeeDueBackfillItem(a, FeeDueBackfillCategory.configMissing, reason: reason);
    FeeDueBackfillItem review(String reason) => FeeDueBackfillItem(a, FeeDueBackfillCategory.manualReview, reason: reason);
    if (structure.components.isEmpty) return missing('Its fee structure has no components, so it has no due-date settings.');

    final String feeMonth;
    if (FeeMonth.isMonthlyStructure(structure)) {
      if (a.feeMonth.isEmpty) return missing('No fee month is recorded on this monthly assignment, so its due day can’t be placed in a month.');
      if (!FeeMonth.isValid(a.feeMonth)) return missing('Its fee month "${a.feeMonth}" is not a valid month.');
      if (structure.components.every((c) => c.dueDayOfMonth == null)) return missing('Its fee structure has no Due Day of Month configured.');
      feeMonth = a.feeMonth;
    } else {
      final configured = structure.components.any((c) => c.frequency == 'monthly' ? c.dueDayOfMonth != null : c.dueDate != null);
      if (!configured) return missing('Its fee structure has no Default Due Date configured.');
      feeMonth = '';
    }
    final d = FeeDueDate.defaultFor(structure, feeMonth);
    final date = d.date;
    if (date == null) return review(d.note);
    if (date.year < 2000 || date.year > 2100) return review('The configured due date ${FeeDueDate.label(date)} is outside 2000–2100.');
    return FeeDueBackfillItem(a, FeeDueBackfillCategory.eligible, proposedDate: date, reason: d.note);
  }
}

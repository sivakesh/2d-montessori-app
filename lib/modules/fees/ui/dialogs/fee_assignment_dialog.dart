import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../../admin/settings/models/academic_year_matching.dart';
import '../../../admin/settings/models/academic_year_model.dart';
import '../../../admin/settings/models/school_settings_model.dart' show kDefaultSchoolId;
import '../../../admin/settings/providers/academic_year_provider.dart';
import '../../../admin/students/models/admission_date.dart';
import '../../models/fee_admission.dart';
import '../../models/fee_discount.dart';
import '../../models/fee_due_date.dart';
import '../../models/fee_month.dart';
import '../../models/fee_month_range.dart';
import '../../models/fee_student.dart';
import '../../models/fee_structure_model.dart';
import '../../models/student_fee_assignment_model.dart';
import '../../services/fee_service.dart';

class FeeAssignmentDialog extends ConsumerStatefulWidget {
  const FeeAssignmentDialog({super.key, this.assignment, this.service});

  final StudentFeeAssignmentModel? assignment;

  /// Overridable only so tests can inject a fake-Firestore-backed
  /// FeeService — the same DI seam every other injectable Admin
  /// dialog/service in this app already exposes. Production callers never
  /// pass this.
  final FeeService? service;

  @override
  ConsumerState<FeeAssignmentDialog> createState() => _FeeAssignmentDialogState();
}

/// Resolved Academic Year for the currently-selected Fee Structure —
/// [year] non-null means it resolved to a canonical [AcademicYearModel]
/// (via the structure's own `academicYearId`, or a legacy `academicYear`
/// string match); [legacyLabel] carries the stored string only when it
/// exists but matched nothing, so the unresolved message can show exactly
/// what's stored, the same way ClassFormDialog's orphaned-value message
/// does.
class _ResolvedStructureYear {
  const _ResolvedStructureYear({this.year, this.legacyLabel = ''});
  final AcademicYearModel? year;
  final String legacyLabel;
}

class _FeeAssignmentDialogState extends ConsumerState<FeeAssignmentDialog> {
  late final _service = widget.service ?? FeeService();
  final _discount = TextEditingController(text: '0');
  final _formKey = GlobalKey<FormState>();
  String _mode = 'single';
  List<dynamic> _classes = [];
  List<dynamic> _students = [];
  List<FeeStructureModel> _structures = [];
  String? _classId;
  String? _studentId;
  String? _structureId;

  /// The Fee Month (1–12) for a Monthly structure; never defaulted.
  int? _feeMonth;

  /// The assignment's due date. For a new assignment it follows the
  /// structure's default ([FeeDueDate.defaultFor]) until the administrator
  /// picks one ([_dueTouched]); an existing assignment keeps its stored
  /// date (none is ever inferred for it).
  DateTime? _dueDate;
  bool _dueTouched = false;

  /// Recurring monthly assignment (new assignments only): the last month
  /// to assign, `YYYY-MM` (null: just the start month), and, for more than
  /// one month, the due-date rule: the same day of every month
  /// ([_dueRuleDay]; null follows the structure's due day) in the fee month
  /// or the next ([_dueRuleOffset]).
  String? _until;
  int? _dueRuleDay;
  int _dueRuleOffset = 0;
  bool _saving = false;
  String? _resultMessage;

  // FEES-AY-IMPLEMENT-01: the Assignment's Academic Year is no longer a
  // manually-typed field — it is always derived from the selected Fee
  // Structure (`FeeStructure.academicYearId`/`academicYear`), never
  // independently selectable here. `_academicYears` is loaded once (active
  // years only, same convention as FeeStructureDialog/ClassFormDialog) so
  // `_resolveStructureYear` can resolve the currently-selected structure's
  // year on every rebuild — recomputed, never cached, so switching the Fee
  // Structure always updates the displayed year immediately.
  bool _loadingAcademicYears = true;
  List<AcademicYearModel> _academicYears = [];

  bool get _identityLocked =>
      widget.assignment != null && (widget.assignment!.paidAmount > 0 || _discountLocked);

  /// Has a student discount: its student, fee structure, year, gross fee,
  /// fee month and discount are fixed (FeeService refuses changes); other
  /// details, such as the due date, are still edited here.
  bool get _discountLocked => widget.assignment?.studentDiscount != null;

  @override
  void initState() {
    super.initState();
    final a = widget.assignment;
    if (a != null) {
      _mode = 'single';
      _discount.text = a.discountAmount.toStringAsFixed(0);
      _classId = a.classId;
      _studentId = a.studentId;
      _structureId = a.feeStructureId;
      _feeMonth = FeeMonth.monthOf(a.feeMonth);
      _dueDate = a.dueDate;
    }
    _loadClasses();
    _loadAcademicYears();
  }

  Future<void> _loadAcademicYears() async {
    final service = ref.read(academicYearServiceProvider);
    final years = await service.getAllAcademicYears(schoolId: kDefaultSchoolId);
    if (!mounted) return;
    setState(() {
      _academicYears = years.where((y) => y.isActive).toList();
      _loadingAcademicYears = false;
      _applyDueDefault();
    });
  }

  /// Resolves [structure]'s Academic Year — `academicYearId` first
  /// (authoritative when it resolves), falling back to matching the legacy
  /// `academicYear` string (reusing the same entity-agnostic
  /// `classMatchesAcademicYear` helper ClassFormDialog/FeeStructureDialog
  /// already use — it only ever compares a free-text string against an
  /// AcademicYearModel.name, nothing Class-specific). Returns a null
  /// [_ResolvedStructureYear.year] whenever neither resolves — including
  /// when a non-empty `academicYearId` simply doesn't match any configured
  /// year — never inventing a value.
  _ResolvedStructureYear _resolveStructureYear(FeeStructureModel structure) {
    final id = structure.academicYearId.trim();
    if (id.isNotEmpty) {
      final match = _academicYears.where((y) => y.id == id);
      if (match.isNotEmpty) return _ResolvedStructureYear(year: match.first);
      return const _ResolvedStructureYear();
    }
    final text = structure.academicYear.trim();
    if (text.isEmpty) return const _ResolvedStructureYear();
    final match = _academicYears.where(
      (y) => classMatchesAcademicYear({'academicYear': text}, y),
    );
    if (match.isNotEmpty) return _ResolvedStructureYear(year: match.first);
    return _ResolvedStructureYear(legacyLabel: text);
  }

  FeeStructureModel? get _selectedStructure {
    if (_structureId == null) return null;
    final match = _structures.where((f) => f.id == _structureId);
    return match.isEmpty ? null : match.first;
  }

  /// Whether the selected structure is Monthly (FeeMonth.isMonthlyStructure).
  bool get _isMonthly => _selectedStructure != null && FeeMonth.isMonthlyStructure(_selectedStructure!);

  /// The month field can't change once a paid assignment has a recorded
  /// month (one made before months were recorded may be given its month).
  bool get _monthLocked => _identityLocked && widget.assignment!.feeMonth.isNotEmpty;

  void _selectStructure(String? id) => setState(() {
        _structureId = id;
        if (!_isMonthly) {
          _feeMonth = null;
          _until = null;
        }
        _dueRuleDay = null;
        _applyDueDefault();
      });

  /// The chosen fee month as `YYYY-MM` ('' when not monthly, not chosen,
  /// or the year doesn't resolve).
  String get _resolvedFeeMonth {
    final structure = _selectedStructure, month = _feeMonth;
    if (structure == null || month == null || !_isMonthly || _loadingAcademicYears) return '';
    final year = _resolveStructureYear(structure).year;
    return year == null ? '' : FeeMonth.inAcademicYear(month, year.startDate, year.endDate) ?? '';
  }

  bool get _recurring => widget.assignment == null && _isMonthly;

  /// Months Assign Until can be: from the start month to the end of the
  /// latest configured academic year, each in a configured year.
  List<String> get _untilOptions {
    final start = _resolvedFeeMonth;
    if (start.isEmpty || _academicYears.isEmpty) return const [];
    final latest = _academicYears.map((y) => y.endDate).reduce((a, b) => a.isAfter(b) ? a : b);
    return [
      for (final m in FeeMonthRange.months(start, FeeMonth.of(latest.year, latest.month)))
        if (FeeMonthRange.yearOf(m, _academicYears) != null) m,
    ];
  }

  /// The effective Assign Until: the chosen month, or the start month.
  String get _untilMonth {
    final start = _resolvedFeeMonth, until = _until;
    return until != null && start.isNotEmpty && until.compareTo(start) >= 0 ? until : start;
  }

  List<String> get _rangeMonths => _recurring ? FeeMonthRange.months(_resolvedFeeMonth, _untilMonth) : const [];

  /// More than one month: assigned with a due-date rule, not one date.
  bool get _isRange => _rangeMonths.length > 1;

  /// The structure's single valid Due Day of Month, or null.
  int? get _structureDueDay {
    final structure = _selectedStructure;
    if (structure == null) return null;
    final days = {for (final c in structure.components) if (c.dueDayOfMonth != null) c.dueDayOfMonth!};
    return days.length == 1 && days.single >= 1 && days.single <= 31 ? days.single : null;
  }

  int? get _ruleDay => _dueRuleDay ?? _structureDueDay;

  FeeDueDefault? get _dueDefault {
    final structure = _selectedStructure;
    return structure == null || widget.assignment != null ? null : FeeDueDate.defaultFor(structure, _resolvedFeeMonth);
  }

  /// Call inside setState after the structure, month or mode changes. A
  /// new assignment follows the structure's suggested default until the
  /// administrator picks a date ([_dueTouched]); a picked date is kept,
  /// except that choosing a different fee month suggests that month's
  /// default again ([monthChanged]). An existing assignment's date is never
  /// changed here.
  void _applyDueDefault({bool monthChanged = false}) {
    if (widget.assignment != null) return;
    if (monthChanged) _dueTouched = false;
    if (_dueTouched) return;
    _dueDate = _dueDefault?.date;
  }

  /// Any valid date, in any month (a fee month is the period the fee is
  /// for; the due date is when it is to be paid). The picker opens on the
  /// current choice, else the fee month, else today.
  Future<void> _pickDueDate(FormFieldState<DateTime> field) async {
    final feeMonth = _resolvedFeeMonth;
    final first = DateTime(2000), last = DateTime(2100, 12, 31);
    final initial = _dueDate ?? (feeMonth.isEmpty ? FeeDueDate.dateOnly(DateTime.now()) : FeeDueDate.monthRange(feeMonth).$1);
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: first, lastDate: last, helpText: 'Due date');
    if (picked == null || !mounted) return;
    setState(() {
      _dueDate = FeeDueDate.dateOnly(picked);
      _dueTouched = true;
    });
    field.didChange(_dueDate);
  }

  /// "Due Date *": defaults from the structure for a new assignment, and
  /// can be changed; for Full Class, one date for every student.
  Widget _buildDueDateField() {
    final existing = widget.assignment;
    final legacy = existing != null && existing.dueDate == null;
    final helper = [
      if (existing == null && _mode == 'bulk') 'Applies to every student assigned in this class; each assignment’s due date can be changed later with Edit.',
      if (_dueDefault case final d?) d.note,
      if (legacy) 'This assignment has no due date recorded. Choose one to set it, or leave it unset.',
    ].join(' ');
    return FormField<DateTime>(
      key: const Key('fee-due-date'),
      validator: (_) {
        final due = _dueDate;
        if (due == null) return legacy ? null : 'Choose the due date';
        return null;
      },
      builder: (field) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: InkWell(
          key: const Key('fee-due-date-pick'),
          onTap: () => _pickDueDate(field),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: legacy ? 'Due Date' : 'Due Date *',
              errorText: field.errorText,
              helperText: helper.isEmpty ? null : helper,
              helperMaxLines: 4,
              suffixIcon: const Icon(Icons.event),
            ),
            child: Text(
              _dueDate == null ? (existing == null ? 'Choose a date' : 'Due date not set') : FeeDueDate.label(_dueDate!),
              key: const Key('fee-due-date-value'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadClasses() async {
    var classes = await _service.getActiveClasses();
    final a = widget.assignment;
    if (a != null && a.classId.isNotEmpty && !classes.any((c) => c.id == a.classId)) {
      final current = await _service.getClassById(a.classId);
      if (current != null) classes = [...classes, current];
    }
    if (!mounted) return;
    setState(() => _classes = classes);
    if (a != null && a.classId.isNotEmpty) {
      await _loadStudents(a.classId, preserveSelection: true);
    }
  }

  Future<void> _loadStudents(String classId, {bool preserveSelection = false}) async {
    var students = await _service.getStudentsByClassId(classId);
    final allStructures = await _service.getFeeStructures();
    final a = widget.assignment;
    if (preserveSelection && a != null && a.studentId.isNotEmpty && !students.any((s) => s.id == a.studentId)) {
      final current = await _service.getStudentById(a.studentId);
      if (current != null) students = [...students, current];
    }
    final currentStructureId = a?.feeStructureId;
    final classStructures = allStructures
        .where((s) => s.isActive || s.id == currentStructureId)
        .toList();
    if (!mounted) return;
    setState(() {
      _students = students;
      _structures = classStructures;
      if (!preserveSelection) {
        _studentId = null;
        _structureId = null;
        _feeMonth = null;
        _until = null;
        _dueRuleDay = null;
        _dueTouched = false;
        _applyDueDefault();
      }
    });
  }

  Future<void> _save() async {
    // A structure whose academic year doesn't resolve can't be saved
    // whatever else is filled in, so that is said first.
    final chosen = _selectedStructure;
    if (chosen != null && !_loadingAcademicYears && _resolveStructureYear(chosen).year == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a Fee Structure with a resolvable Academic Year before saving.')),
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_classId == null || _structureId == null) return;
    final classDoc = _classes.firstWhere((e) => e.id == _classId);
    final classData = classDoc.data() as Map<String, dynamic>;
    final selectedFee = _selectedStructure;
    if (selectedFee == null) return;
    final resolvedYear = _resolveStructureYear(selectedFee);
    if (resolvedYear.year == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a Fee Structure with a resolvable Academic Year before saving.'),
        ),
      );
      return;
    }
    var feeMonth = '';
    if (_isMonthly) {
      final month = _feeMonth;
      if (month == null) return; // the field's validator says so
      final year = resolvedYear.year!;
      final resolved = FeeMonth.inAcademicYear(month, year.startDate, year.endDate);
      if (resolved == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${FeeMonth.names[month - 1]} is not within the academic year ${year.name}.')),
        );
        return;
      }
      feeMonth = resolved;
    }
    // A discounted assignment keeps its own gross fee (locked), whatever the
    // structure's total is now.
    final totalFee = _discountLocked ? widget.assignment!.totalFee : selectedFee.totalAmount;
    final discountAmount = double.tryParse(_discount.text) ?? 0;
    if (discountAmount < 0 || discountAmount > totalFee) return;
    final className = classData['name']?.toString() ?? '';
    if (_isRange) {
      await _saveRange(selectedFee, classDoc.id as String, className, totalFee, discountAmount);
      return;
    }
    if (widget.assignment == null && _mode == 'bulk' && feeMonth.isNotEmpty) {
      final confirmed = await _confirmBulk(structure: selectedFee.name, className: className, students: _students.length, months: [feeMonth]);
      if (!confirmed || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      final existingAssignment = widget.assignment;
      if (existingAssignment != null) {
        if (_studentId == null) return;
        final studentDoc = _students.firstWhere((e) => e.id == _studentId);
        final studentData = studentDoc.data() as Map<String, dynamic>;
        try {
          await _service.updateAssignment(existingAssignment.id, {
            'studentId': studentDoc.id,
            'studentName': studentData['name']?.toString() ?? '',
            'admissionNo': studentData['admissionNo']?.toString() ?? '',
            'classId': classDoc.id,
            'className': classData['name']?.toString() ?? '',
            'feeStructureId': selectedFee.id,
            'feeStructureName': selectedFee.name,
            'academicYearId': resolvedYear.year!.id,
            'academicYear': resolvedYear.year!.name,
            'feeMonth': feeMonth,
            'dueDate': ?_dueDate,
            'totalFee': totalFee,
            'discountAmount': discountAmount,
            // Locked by its student discount: the assignment's own values,
            // so an ordinary edit isn't refused because the structure's
            // current total or year resolution has changed since.
            if (_discountLocked) ...{
              'studentId': existingAssignment.studentId,
              'feeStructureId': existingAssignment.feeStructureId,
              'feeStructureName': existingAssignment.feeStructureName,
              'academicYearId': existingAssignment.academicYearId,
              'academicYear': existingAssignment.academicYear,
              'feeMonth': existingAssignment.feeMonth,
              'totalFee': existingAssignment.totalFee,
              'discountAmount': existingAssignment.discountAmount,
            },
          });
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to update assignment: $e')),
            );
          }
          return;
        }
        _resultMessage = 'Assignment updated successfully.';
      } else if (_mode == 'single') {
        if (_studentId == null) return;
        final studentDoc = _students.firstWhere((e) => e.id == _studentId);
        final studentData = studentDoc.data() as Map<String, dynamic>;
        final String? res;
        try {
          res = await _service.assignFee({
            'studentId': studentDoc.id,
            'studentName': studentData['name']?.toString() ?? '',
            'admissionNo': studentData['admissionNo']?.toString() ?? '',
            'classId': classDoc.id,
            'className': classData['name']?.toString() ?? '',
            'feeStructureId': selectedFee.id,
            'feeStructureName': selectedFee.name,
            'academicYearId': resolvedYear.year!.id,
            'academicYear': resolvedYear.year!.name,
            'totalFee': totalFee,
            'discountAmount': discountAmount,
            'payableAmount': totalFee - discountAmount,
            'paidAmount': 0,
            'balanceAmount': totalFee - discountAmount,
            'status': 'unpaid',
            if (feeMonth.isNotEmpty) 'feeMonth': feeMonth,
            'dueDate': ?_dueDate,
          });
        } on StateError catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
          return;
        }
        _resultMessage = res != null
            ? 'Student assigned successfully.'
            : feeMonth.isEmpty
                ? 'Assignment already exists.'
                : 'An assignment for ${FeeMonth.label(feeMonth)} already exists (or one with no month recorded: set its month with Edit).';
      } else {
        final summary = await _service.bulkAssignClassFees(
          classId: classDoc.id,
          className: classData['name']?.toString() ?? '',
          feeStructureId: selectedFee.id,
          feeStructureName: selectedFee.name,
          academicYearId: resolvedYear.year!.id,
          academicYear: resolvedYear.year!.name,
          totalFee: totalFee,
          discountAmount: discountAmount,
          feeMonth: feeMonth,
          dueDate: _dueDate,
        );
        _resultMessage = 'Assigned ${summary['assigned']} students${feeMonth.isEmpty ? '' : ' for ${FeeMonth.label(feeMonth)}'}, '
            'skipped ${summary['skipped']} duplicates, skipped ${summary['admissionSkipped'] ?? 0} not yet admitted, '
            '${summary['manualReview'] ?? 0} need manual review (no admission date)'
            '${(summary['studentDiscounted'] ?? 0) > 0 ? ', ${summary['studentDiscounted']} with the student\'s discount' : ''}'
            '${(summary['discountConflict'] ?? 0) > 0 ? ', skipped ${summary['discountConflict']} for manual review (student discount not combined with the manual discount)' : ''}.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_resultMessage ?? 'Saved')));
        Navigator.pop(context, true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Saves a recurring monthly assignment (more than one month): every
  /// month planned and checked first (its academic year and due date),
  /// then created by FeeService.assignMonthlyFees.
  Future<void> _saveRange(FeeStructureModel structure, String classId, String className, double totalFee, double discountAmount) async {
    final day = _ruleDay;
    if (day == null) return; // the due-day field's validator says so
    final List<FeeMonthPlan> plans;
    try {
      plans = FeeMonthRange.plan(_resolvedFeeMonth, _untilMonth, _academicYears, FeeDueRule(day: day, monthOffset: _dueRuleOffset));
    } on StateError catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    final students = _targetStudents;
    if (_mode == 'bulk') {
      final confirmed = await _confirmBulk(structure: structure.name, className: className, students: students.length, months: [for (final p in plans) p.feeMonth]);
      if (!confirmed || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      final result = await _service.assignMonthlyFees(
        students: students,
        classId: classId,
        className: className,
        feeStructureId: structure.id,
        feeStructureName: structure.name,
        months: plans,
        totalFee: totalFee,
        discountAmount: discountAmount,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message, key: const Key('fee-recurring-result'))));
      if (result.failed == 0) Navigator.pop(context, true);
    } on StateError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildAcademicYearInfo() {
    final structure = _selectedStructure;
    if (structure == null) return const SizedBox.shrink();
    if (_loadingAcademicYears) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }

    final resolved = _resolveStructureYear(structure);
    if (resolved.year != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Academic Year'),
          child: Text('${resolved.year!.name} • ${resolved.year!.isCurrent ? 'Current' : 'Historical'}'),
        ),
      );
    }

    final message = resolved.legacyLabel.isNotEmpty
        ? 'This Fee Structure\'s academic year "${resolved.legacyLabel}" does not match any '
            'configured Academic Year. Update the Fee Structure first.'
        : 'This Fee Structure has no resolvable Academic Year. Update the Fee Structure first.';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(message, style: const TextStyle(color: Colors.orange, fontSize: 12)),
    );
  }

  /// "Assign Until *": the last month to assign (the start month by
  /// default), labelled with its academic year, and the whole range.
  Widget _buildUntilField() {
    final options = _untilOptions;
    final value = _untilMonth;
    String yearOf(String m) => FeeMonthRange.yearOf(m, _academicYears)?.name ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('fee-month-until:$_resolvedFeeMonth:$value'),
          initialValue: options.contains(value) ? value : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Assign Until *', helperText: 'The last month to assign; one assignment is made for each month.'),
          items: [
            for (final m in options)
              DropdownMenuItem(value: m, child: Text('${FeeMonth.label(m)} (${yearOf(m)})', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() {
            _until = v;
            if (!_isRange) _applyDueDefault();
          }),
          validator: (v) => v == null ? 'Choose the last month to assign' : null,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            FeeMonthRange.summary(_rangeMonths),
            key: const Key('fee-month-range'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  /// For more than one month: the due day of every month and whether it
  /// falls in the fee month or the next, with the dates it gives.
  Widget _buildDueRuleField() {
    final day = _ruleDay;
    final months = _rangeMonths;
    final rule = day == null ? null : FeeDueRule(day: day, monthOffset: _dueRuleOffset);
    final dates = rule == null ? const <DateTime>[] : [for (final m in months) rule.dueFor(m)];
    final preview = dates.length <= 4
        ? dates.map(FeeDueDate.label).join(', ')
        : '${dates.take(3).map(FeeDueDate.label).join(', ')}, … ${FeeDueDate.label(dates.last)}';
    final structureDay = _structureDueDay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<int>(
                key: ValueKey('fee-due-day:$day'),
                initialValue: day,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Due day of each month *'),
                items: [for (var d = 1; d <= 31; d++) DropdownMenuItem(value: d, child: Text('$d'))],
                onChanged: (v) => setState(() => _dueRuleDay = v),
                validator: (v) => v == null ? 'Choose the due day' : null,
              ),
            ),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<int>(
                key: const Key('fee-due-offset'),
                initialValue: _dueRuleOffset,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Due in'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('The fee month')),
                  DropdownMenuItem(value: 1, child: Text('The month after the fee month')),
                ],
                onChanged: (v) => setState(() => _dueRuleOffset = v ?? 0),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            [
              if (structureDay == null && _dueRuleDay == null) 'This fee structure has no usable due day of month: choose the day for every month.',
              if (structureDay != null && _dueRuleDay == null) 'Defaults to the structure’s due day ($structureDay). You can change it.',
              'Each month gets its own due date; a shorter month uses its last day.',
              if (_mode == 'bulk') 'The same dates apply to every student in this class; each can be changed later with Edit.',
              if (dates.isNotEmpty) 'Due dates: $preview.',
            ].join(' '),
            key: const Key('fee-due-preview'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ),
      ],
    );
  }

  /// The students this dialog would assign (the class for Full Class, the
  /// chosen student otherwise), with their Admission Dates.
  List<FeeStudent> get _targetStudents => [
        for (final doc in _students)
          if (_mode == 'bulk' || doc.id == _studentId) FeeStudent.fromMap(doc.id as String, doc.data() as Map<String, dynamic>),
      ];

  /// Admission-date counts over [months] ('' for a Term / One-time fee,
  /// checked against today): student-months eligible, before admission,
  /// and without an admission date (manual review). The same rule
  /// FeeService applies when saving.
  ({int eligible, int notYet, int review}) _admissionCounts(List<String> months) {
    var eligible = 0, notYet = 0, review = 0;
    final today = DateTime.now();
    for (final s in _targetStudents) {
      for (final m in months) {
        switch (FeeAdmission.check(s.admissionDate, feeMonth: m, assignmentDate: today)) {
          case FeeAdmissionStatus.eligible:
            eligible++;
          case FeeAdmissionStatus.notYetAdmitted:
            notYet++;
          case FeeAdmissionStatus.notRecorded:
            review++;
        }
      }
    }
    return (eligible: eligible, notYet: notYet, review: review);
  }

  String _admissionSummary(List<String> months) {
    final c = _admissionCounts(months);
    return 'By admission date: ${c.eligible} eligible, ${c.notYet} skipped (not yet admitted), '
        '${c.review} skipped for manual review (no admission date recorded).';
  }

  /// New assignments: the student's Admission Date and whether it allows
  /// the chosen month (Single Student), or the class's admission counts
  /// (Full Class). Existing assignments are never affected by it.
  Widget _buildAdmissionNote() {
    if (widget.assignment != null || _selectedStructure == null) return const SizedBox.shrink();
    final month = _isMonthly ? _resolvedFeeMonth : '';
    if (_isMonthly && month.isEmpty) return const SizedBox.shrink();
    final months = _isRange ? _rangeMonths : [month];
    String text;
    var warn = false;
    if (_mode == 'bulk') {
      text = _admissionSummary(months);
      warn = _admissionCounts(months).eligible < _targetStudents.length * months.length;
    } else {
      final student = _targetStudents.firstOrNull;
      if (student == null) return const SizedBox.shrink();
      final admitted = student.admissionDate;
      if (admitted == null) {
        text = 'Admission date not recorded for ${student.name}: check their admission before assigning (manual review).';
        warn = true;
      } else {
        final blocked = [for (final m in months) if (FeeAdmission.check(admitted, feeMonth: m, assignmentDate: DateTime.now()) == FeeAdmissionStatus.notYetAdmitted) m];
        warn = blocked.isNotEmpty;
        text = 'Admitted ${AdmissionDate.label(admitted)}.'
            '${!warn ? '' : month.isEmpty ? ' This fee can’t be assigned before the admission date.' : ' Months before ${FeeMonth.label(FeeAdmission.firstMonth(admitted))} are not assigned.'}';
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(text, key: const Key('fee-admission-note'), style: TextStyle(fontSize: 12, color: warn ? Colors.orange.shade800 : Colors.grey.shade700)),
    );
  }

  /// Student discounts over [months] ('' for a Term / One-time fee, the
  /// assignment date today), with the same calculation FeeService applies
  /// when saving: (student, month, calculation) for each that applies.
  List<(String, String, FeeDiscountCalculation)> _discountsFor(List<String> months) {
    final structure = _selectedStructure;
    if (structure == null) return const [];
    final out = <(String, String, FeeDiscountCalculation)>[];
    for (final doc in _students) {
      if (_mode != 'bulk' && doc.id != _studentId) continue;
      final data = doc.data() as Map<String, dynamic>;
      final d = StudentFeeDiscount.fromStudent(data);
      if (d == null) continue;
      for (final m in months) {
        final period = FeeMonth.isValid(m) ? FeeDiscountPeriod.month(m) : FeeDiscountPeriod.date(DateTime.now());
        if (!d.appliesTo(period)) continue;
        final calc = FeeDiscountCalculator.calculate(d, structure.totalAmount, structure.components);
        if ((calc.discount * 100).round() > 0) out.add((data['name']?.toString() ?? doc.id as String, m, calc));
      }
    }
    return out;
  }

  double get _manualDiscount => double.tryParse(_discount.text.trim()) ?? 0;

  /// New assignments: the student discount that will be applied (Single
  /// Student), or how many students/months have one (Full Class); and,
  /// with a manual discount entered, that the two are not combined.
  Widget _buildDiscountNote() {
    if (widget.assignment != null || _selectedStructure == null) return const SizedBox.shrink();
    final month = _isMonthly ? _resolvedFeeMonth : '';
    if (_isMonthly && month.isEmpty) return const SizedBox.shrink();
    final months = _isRange ? _rangeMonths : [month];
    final found = _discountsFor(months);
    if (found.isEmpty) return const SizedBox.shrink();
    final manual = (_manualDiscount * 100).round() > 0;
    final String text;
    if (_mode == 'bulk') {
      final students = {for (final f in found) f.$1}.length;
      text = manual
          ? '$students ${students == 1 ? 'student has' : 'students have'} a student discount for this period. With a manual discount entered, '
              'they are skipped for manual review (the two are never combined). Set Discount Amount to 0 to apply their student discounts.'
          : '$students ${students == 1 ? 'student has' : 'students have'} a student discount for this period (${found.length} '
              '${found.length == 1 ? 'assignment' : 'assignments'}); it is applied automatically and recorded on each assignment.';
    } else {
      final c = found.first.$3;
      text = manual
          ? '${found.first.$1} has a student discount for this period. It is not combined with a manual discount: set Discount Amount to 0 to apply it.'
          : 'Student discount: ${_money(c.discount)} off ${_money(c.gross)}; net payable ${_money(c.net)}'
              '${found.length > 1 ? ' for each of ${found.length} months' : ''}.';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(text, key: const Key('fee-discount-note'), style: TextStyle(fontSize: 12, color: manual ? Colors.orange.shade800 : Colors.grey.shade700)),
    );
  }

  static String _money(double v) => '₹${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}';

  /// Full Class: how many students, months and (at most) assignments,
  /// confirmed before anything is saved.
  Future<bool> _confirmBulk({required String structure, required String className, required int students, required List<String> months}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('fee-bulk-confirm'),
        title: const Text('Assign to the whole class?'),
        content: Text(
          'Assign $structure to $students ${students == 1 ? 'student' : 'students'} in $className for '
          '${FeeMonthRange.summary(months)}.\n\n'
          'This creates at most ${students * months.length} ${students * months.length == 1 ? 'assignment' : 'assignments'} '
          '(one per student per month). A student who already has a month is skipped for that month only.\n\n'
          '${_admissionSummary(months)}',
          key: const Key('fee-bulk-confirm-summary'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('fee-bulk-confirm-ok'), onPressed: () => Navigator.pop(context, true), child: const Text('Assign')),
        ],
      ),
    );
    return ok == true;
  }

  /// "Fee Month *" for a Monthly structure: January to December, each
  /// shown with its calendar year in the structure's academic year.
  Widget _buildFeeMonthField() {
    final structure = _selectedStructure!;
    final year = _loadingAcademicYears ? null : _resolveStructureYear(structure).year;
    String label(int m) {
      final inYear = year == null ? null : FeeMonth.inAcademicYear(m, year.startDate, year.endDate);
      return inYear == null ? FeeMonth.names[m - 1] : FeeMonth.label(inYear);
    }

    final legacy = widget.assignment != null && widget.assignment!.feeMonth.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<int>(
          key: const Key('fee-month'),
          initialValue: _feeMonth,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: _recurring ? 'Start Fee Month *' : 'Fee Month *',
            helperText: _recurring ? 'The first month the fee is assigned for.' : 'The month of this academic year the fee is for.',
          ),
          items: [for (var m = 1; m <= 12; m++) DropdownMenuItem<int>(value: m, child: Text(label(m)))],
          onChanged: _monthLocked
              ? null
              : (v) => setState(() {
                    final changed = v != _feeMonth;
                    _feeMonth = v;
                    _applyDueDefault(monthChanged: changed);
                  }),
          validator: (v) => v == null ? 'Choose the month this fee is for' : null,
        ),
        if (_recurring && _resolvedFeeMonth.isNotEmpty) _buildUntilField(),
        if (legacy)
          Padding(
            key: const Key('fee-month-legacy'),
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'This assignment was made before fee months were recorded, so its month is not known. Choose the month it is for.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.assignment != null;
    return ResponsiveDialogShell.form(
      desktopWidth: 720,
      desktopHeight: 640,
      title: isEdit ? 'Edit Assignment' : 'Assign Fee',
      content: Form(
          key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isEdit) ...[
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'single', label: Text('Single Student')),
                      ButtonSegment(value: 'bulk', label: Text('Full Class')),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() {
                      _mode = s.first;
                      _studentId = null;
                      _structureId = null;
                      _feeMonth = null;
                      _until = null;
                      _dueRuleDay = null;
                      _dueTouched = false;
                      _applyDueDefault();
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_discountLocked)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'This assignment has a student discount, calculated for its student, fee, academic year and period, '
                      'so those and the discount cannot be changed. The due date can still be edited.',
                      key: const Key('fee-assignment-discount-locked'),
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  )
                else if (_identityLocked)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'This assignment already has a payment recorded against it, '
                      'so the student, fee structure, and total fee cannot be changed. '
                      'Only the discount can be edited here.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ),
                DropdownButtonFormField<String>(
                  initialValue: _classId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Select Class *'),
                  items: _classes
                      .map<DropdownMenuItem<String>>(
                        (e) => DropdownMenuItem<String>(
                          value: e.id as String,
                          child: Text(e.data()['name']?.toString() ?? '', overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: _identityLocked
                      ? null
                      : (v) {
                          setState(() => _classId = v);
                          if (v != null) _loadStudents(v);
                        },
                  validator: (v) => v == null ? 'Required' : null,
                ),
                if (_mode == 'single') ...[
                  DropdownButtonFormField<String>(
                    initialValue: _studentId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Select Student *'),
                    items: _students
                        .map<DropdownMenuItem<String>>(
                          (e) => DropdownMenuItem<String>(
                            value: e.id as String,
                            child: Text(e.data()['name']?.toString() ?? '', overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: _identityLocked ? null : (v) => setState(() => _studentId = v),
                    validator: (v) => v == null ? 'Required' : null,
                  ),
                ],
                DropdownButtonFormField<String>(
                  initialValue: _structureId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Fee Structure *'),
                  items: _structures
                      .map<DropdownMenuItem<String>>(
                        (fee) => DropdownMenuItem<String>(
                          value: fee.id,
                          child: Text(
                            '${fee.name} - ₹${fee.totalAmount.toStringAsFixed(0)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _identityLocked ? null : _selectStructure,
                  validator: (v) => v == null ? 'Required' : null,
                ),
                _buildAcademicYearInfo(),
                if (_isMonthly) _buildFeeMonthField(),
                _buildAdmissionNote(),
                _buildDiscountNote(),
                if (_selectedStructure != null) _isRange ? _buildDueRuleField() : _buildDueDateField(),
                const SizedBox(height: 16),
                if (widget.assignment?.studentDiscount case final snap?)
                  TextFormField(
                    key: const Key('fee-assignment-discount'),
                    controller: _discount,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Discount Amount',
                      helperText: 'Includes the student discount ${snap.label}; manual discount '
                          '${_money(widget.assignment!.manualDiscountAmount)}. It cannot be changed here.',
                      helperMaxLines: 3,
                    ),
                  )
                else
                  TextFormField(
                    key: const Key('fee-assignment-discount'),
                    controller: _discount,
                    decoration: const InputDecoration(labelText: 'Discount Amount'),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
              ],
            ),
          ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save')),
      ],
    );
  }
}

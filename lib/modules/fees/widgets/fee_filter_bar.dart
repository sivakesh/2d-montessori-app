import 'package:flutter/material.dart';

import '../../admin/settings/models/academic_year_model.dart';
import '../models/fee_month.dart';
import '../models/fee_student.dart';

/// The shared Academic Year / Class / Student filter row for the Fees
/// lists. Stateless: the screen holds one filter state for every tab and
/// passes it in. Lays out as a row of fixed-width fields on wide screens
/// and as full-width stacked fields on a phone.
///
/// Keys: `fees-filter-year`, `fees-filter-class`, `fees-filter-student`
/// (opens a searchable picker: `fees-student-picker-search`,
/// `fees-student-option-<id>`, `fees-student-option-all`) and
/// `fees-filter-reset`.
class FeeFilterBar extends StatelessWidget {
  const FeeFilterBar({
    super.key,
    required this.years,
    required this.yearKey,
    required this.classes,
    required this.classId,
    required this.students,
    required this.selectedStudent,
    required this.onYearChanged,
    required this.onClassChanged,
    required this.onStudentChanged,
    required this.onReset,
    required this.isDefault,
    this.scopeNote,
    this.months = const [],
    this.feeMonth,
    this.onMonthChanged,
  });

  /// The Fee Month options (`YYYY-MM`, in order) and the chosen one (null:
  /// All Months). The field shows when [onMonthChanged] is given.
  final List<String> months;
  final String? feeMonth;
  final ValueChanged<String?>? onMonthChanged;

  /// What the filters mean on the current tab, shown under them.
  final String? scopeNote;

  /// The value of the All Academic Years option.
  static const allYears = '__all__';

  final List<AcademicYearModel> years;

  /// A year id, or [allYears].
  final String yearKey;

  /// Class id -> name, in display order.
  final Map<String, String> classes;
  final String? classId;

  /// The Student picker's options (already narrowed to the class).
  final List<FeeStudent> students;
  final FeeStudent? selectedStudent;
  final ValueChanged<String> onYearChanged;
  final ValueChanged<String?> onClassChanged;
  final ValueChanged<String?> onStudentChanged;
  final VoidCallback onReset;

  /// Whether the filters are at their defaults (Reset is then disabled).
  final bool isDefault;

  Future<void> _pickStudent(BuildContext context) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _StudentPicker(students: students, selectedId: selectedStudent?.id),
    );
    if (picked == null) return;
    onStudentChanged(picked == _StudentPicker.all ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final yearField = DropdownButtonFormField<String>(
      // Keyed by the value, so a change from outside (Reset) is shown.
      key: ValueKey('year:$yearKey'),
      initialValue: yearKey,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Academic Year', isDense: true, border: OutlineInputBorder()),
      items: [
        for (final y in years)
          DropdownMenuItem(value: y.id, child: Text(y.isCurrent ? '${y.name} (current)' : y.name, overflow: TextOverflow.ellipsis)),
        const DropdownMenuItem(value: allYears, child: Text('All Academic Years')),
      ],
      onChanged: (v) => v == null ? null : onYearChanged(v),
    );
    final classField = DropdownButtonFormField<String?>(
      key: ValueKey('class:$classId'),
      initialValue: classId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Class', isDense: true, border: OutlineInputBorder()),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('All Classes')),
        for (final MapEntry(key: id, value: name) in classes.entries)
          DropdownMenuItem<String?>(value: id, child: Text(name.isEmpty ? '(unnamed class)' : name, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onClassChanged,
    );
    final monthField = onMonthChanged == null
        ? null
        : DropdownButtonFormField<String?>(
            key: ValueKey('month:$feeMonth'),
            initialValue: feeMonth,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Fee Month', isDense: true, border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All Months')),
              for (final m in {...months, ?feeMonth}.toList()..sort())
                DropdownMenuItem<String?>(value: m, child: Text(FeeMonth.label(m), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: onMonthChanged,
          );
    final studentField = InkWell(
      key: const Key('fees-filter-student'),
      onTap: () => _pickStudent(context),
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Student',
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: selectedStudent == null
              ? const Icon(Icons.search, size: 20)
              : IconButton(
                  key: const Key('fees-filter-student-clear'),
                  tooltip: 'All Students',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => onStudentChanged(null),
                ),
        ),
        child: Text(
          selectedStudent == null ? 'All Students' : _studentLabel(selectedStudent!),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
    final reset = TextButton.icon(
      key: const Key('fees-filter-reset'),
      onPressed: isDefault ? null : onReset,
      icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
      label: const Text('Reset filters'),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 600;
        final width = narrow ? constraints.maxWidth : 240.0;
        return Padding(
          key: const Key('fees-filters'),
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(key: const Key('fees-filter-year'), width: width, child: yearField),
              SizedBox(key: const Key('fees-filter-class'), width: width, child: classField),
              if (monthField != null) SizedBox(key: const Key('fees-filter-month'), width: width, child: monthField),
              SizedBox(width: width, child: studentField),
              reset,
              if (scopeNote != null)
                SizedBox(
                  width: constraints.maxWidth,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1, right: 6),
                        child: Icon(Icons.info_outline, size: 16, color: Colors.black45),
                      ),
                      Expanded(
                        child: Text(
                          scopeNote!,
                          key: const Key('fees-filter-scope'),
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

String _studentLabel(FeeStudent s) => s.admissionNo.isEmpty ? s.name : '${s.name} (${s.admissionNo})';

/// The searchable student list behind the Student filter; pops the chosen
/// student's id, or [all].
class _StudentPicker extends StatefulWidget {
  const _StudentPicker({required this.students, required this.selectedId});

  static const all = '__all__';

  final List<FeeStudent> students;
  final String? selectedId;

  @override
  State<_StudentPicker> createState() => _StudentPickerState();
}

class _StudentPickerState extends State<_StudentPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final shown = query.isEmpty
        ? widget.students
        : widget.students.where((s) => s.name.toLowerCase().contains(query) || s.admissionNo.toLowerCase().contains(query)).toList();
    return AlertDialog(
      title: const Text('Choose a student'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              key: const Key('fees-student-picker-search'),
              controller: _search,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Search name or admission no.', prefixIcon: Icon(Icons.search), isDense: true, border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            ListTile(
              key: const Key('fees-student-option-all'),
              dense: true,
              title: const Text('All Students'),
              selected: widget.selectedId == null,
              onTap: () => Navigator.of(context).pop(_StudentPicker.all),
            ),
            const Divider(height: 1),
            Expanded(
              child: shown.isEmpty
                  ? const Center(child: Text('No students match.', key: Key('fees-student-picker-empty')))
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final s = shown[i];
                        return ListTile(
                          key: Key('fees-student-option-${s.id}'),
                          dense: true,
                          title: Text(s.name.isEmpty ? '(no name)' : s.name),
                          subtitle: s.admissionNo.isEmpty ? null : Text(s.admissionNo),
                          selected: s.id == widget.selectedId,
                          onTap: () => Navigator.of(context).pop(s.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'))],
    );
  }
}

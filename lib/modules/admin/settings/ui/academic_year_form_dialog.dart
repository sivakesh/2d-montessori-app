import 'package:flutter/material.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../data/academic_year_service.dart';
import '../models/academic_year_model.dart';
import '../models/school_settings_model.dart' show kDefaultSchoolId;

/// Add/Edit Academic Year — pushed as a dialog from AcademicYearScreen.
/// Pass [existing] to edit that year in place; omit it to create a new one.
/// Never touches [AcademicYearModel.isCurrent]/[AcademicYearModel.isActive]
/// — those are only ever changed via the "Set as Current"/Activate-
/// Deactivate actions on the list screen itself, not from this form.
class AcademicYearFormDialog extends StatefulWidget {
  const AcademicYearFormDialog({
    super.key,
    required this.role,
    required this.userId,
    this.existing,
    this.service,
  });

  final String role;
  final String userId;
  final AcademicYearModel? existing;

  /// Lets tests inject a fake-Firestore-backed service instead of the real
  /// Firebase-backed default, the same DI shape every other injectable
  /// Admin dialog/service in this app uses.
  final AcademicYearService? service;

  @override
  State<AcademicYearFormDialog> createState() => _AcademicYearFormDialogState();
}

class _AcademicYearFormDialogState extends State<AcademicYearFormDialog> {
  late final _service = widget.service ?? AcademicYearService();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _saving = false;
  String? _errorText;

  /// Tracks whether the admin has manually edited the name — while false,
  /// picking a date auto-fills the suggested name derived from the range
  /// (see [AcademicYearValidation.suggestName]) so a new year starts with a
  /// sensible label without forcing the admin to type it, but never
  /// overwrites a name they've already typed themselves.
  bool _nameEdited = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _startDate = existing?.startDate;
    _endDate = existing?.endDate;
    _nameEdited = existing != null;
    _nameController.addListener(_markNameEdited);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _maybeSuggestName() {
    if (_nameEdited || _startDate == null || _endDate == null) return;
    final suggestion = AcademicYearValidation.suggestName(_startDate!, _endDate!);
    _nameController.removeListener(_markNameEdited);
    _nameController.text = suggestion;
    _nameEdited = false;
    _nameController.addListener(_markNameEdited);
  }

  // Split out so it can be temporarily detached while programmatically
  // setting the suggested name above, without permanently losing the
  // "the admin typed something" listener.
  void _markNameEdited() => _nameEdited = true;

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _startDate : _endDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: initial,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
      _maybeSuggestName();
    });
  }

  Future<void> _save() async {
    setState(() => _errorText = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final datesError = AcademicYearValidation.validateDates(_startDate, _endDate);
    if (datesError != null) {
      setState(() => _errorText = datesError);
      return;
    }

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await _service.updateAcademicYear(
          schoolId: kDefaultSchoolId,
          requesterRole: widget.role,
          id: widget.existing!.id,
          name: _nameController.text,
          startDate: _startDate!,
          endDate: _endDate!,
          updatedBy: widget.userId,
        );
      } else {
        await _service.createAcademicYear(
          schoolId: kDefaultSchoolId,
          requesterRole: widget.role,
          name: _nameController.text,
          startDate: _startDate!,
          endDate: _endDate!,
          createdBy: widget.userId,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Select date';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogShell.form(
      desktopWidth: 480,
      title: _isEdit ? 'Edit Academic Year' : 'Add Academic Year',
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Academic Year Name *'),
              validator: AcademicYearValidation.validateName,
            ),
            const SizedBox(height: 16),
            _DatePickerField(
              label: 'Start Date *',
              value: _formatDate(_startDate),
              onTap: () => _pickDate(isStart: true),
            ),
            const SizedBox(height: 16),
            _DatePickerField(
              label: 'End Date *',
              value: _formatDate(_endDate),
              onTap: () => _pickDate(isStart: false),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 16),
              Text(_errorText!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_today_outlined)),
        child: Text(value),
      ),
    );
  }
}

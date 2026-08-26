import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../settings/models/academic_year_model.dart';
import '../../settings/models/school_settings_model.dart' show kDefaultSchoolId;
import '../../settings/providers/academic_year_provider.dart';
import '../data/admin_student_service.dart';
import '../data/student_enrollment_service.dart';
import '../providers/student_enrollment_provider.dart';

/// "Assign to Academic Year" — the smallest necessary mechanism for an
/// Admin/Staff to place [studentId] into a class for the *current*
/// academic year (per AY-01's scope: no future/past-year assignment, no
/// bulk promotion — those are separate follow-up work). Reuses
/// [AdminStudentService.getClasses] — the exact same class list
/// AdminStudentForm's own Class dropdown already loads — rather than
/// introducing a second class-loading path.
///
/// On save, calls [StudentEnrollmentService.assignStudentToClassForYear]
/// with `syncStudentClassId: true` (safe here specifically because this
/// dialog only ever targets the *current* academic year — see that
/// method's doc comment for why that flag must never be true for a past
/// year), then invalidates [studentEnrollmentsProvider] for this student so
/// the Academic History tab reflects the change immediately.
class StudentEnrollmentAssignDialog extends ConsumerStatefulWidget {
  const StudentEnrollmentAssignDialog({
    super.key,
    required this.studentId,
    this.currentClassId,
    this.adminStudentService,
    this.enrollmentService,
  });

  final String studentId;
  final String? currentClassId;

  /// Lets tests inject fake-Firestore-backed services, the same DI shape
  /// every other injectable Admin dialog in this app uses.
  final AdminStudentService? adminStudentService;
  final StudentEnrollmentService? enrollmentService;

  @override
  ConsumerState<StudentEnrollmentAssignDialog> createState() => _StudentEnrollmentAssignDialogState();
}

class _StudentEnrollmentAssignDialogState extends ConsumerState<StudentEnrollmentAssignDialog> {
  late final AdminStudentService _studentService =
      widget.adminStudentService ?? ref.read(adminStudentServiceProvider);
  late final StudentEnrollmentService _enrollmentService =
      widget.enrollmentService ?? ref.read(studentEnrollmentServiceProvider);
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _classes = [];
  String? _classId;
  bool _loadingClasses = true;
  bool _saving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _classId = widget.currentClassId;
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    final classes = await _studentService.getClasses();
    if (!mounted) return;
    setState(() {
      _classes = classes;
      if (_classId != null && !classes.any((c) => c.id == _classId)) _classId = null;
      _loadingClasses = false;
    });
  }

  Future<void> _save(AcademicYearModel currentYear) async {
    if (_classId == null) {
      setState(() => _errorText = 'A class is required.');
      return;
    }
    final user = ref.read(currentUserProvider);
    final role = (user?.role ?? '').toLowerCase();
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await _enrollmentService.assignStudentToClassForYear(
        schoolId: kDefaultSchoolId,
        requesterRole: role,
        studentId: widget.studentId,
        academicYearId: currentYear.id,
        classId: _classId!,
        syncStudentClassId: true,
        actorId: user?.id ?? '',
      );
      if (!mounted) return;
      ref.invalidate(studentEnrollmentsProvider(widget.studentId));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentYearAsync = ref.watch(currentAcademicYearProvider);

    return currentYearAsync.when(
      loading: () => const ResponsiveDialogShell(
        desktopWidth: 420,
        desktopHeight: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _NoCurrentYearDialog(message: 'Could not load the current academic year: $error'),
      data: (currentYear) {
        if (currentYear == null) {
          return const _NoCurrentYearDialog(
            message: 'No current academic year is set. Set one in Settings -> Academic Year first.',
          );
        }
        return ResponsiveDialogShell.form(
          desktopWidth: 460,
          title: 'Assign to Academic Year',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Academic Year', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(currentYear.name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 20),
              _loadingClasses
                  ? const Center(child: CircularProgressIndicator())
                  : DropdownButtonFormField<String>(
                      initialValue: _classId,
                      decoration: const InputDecoration(labelText: 'Class *'),
                      items: [
                        for (final doc in _classes)
                          DropdownMenuItem(
                            value: doc.id,
                            child: Text(doc.data()['name']?.toString() ?? doc.id),
                          ),
                      ],
                      onChanged: (value) => setState(() => _classId = value),
                    ),
              if (_errorText != null) ...[
                const SizedBox(height: 16),
                Text(_errorText!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _saving ? null : () => _save(currentYear),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}

class _NoCurrentYearDialog extends StatelessWidget {
  const _NoCurrentYearDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogShell.form(
      desktopWidth: 420,
      title: 'Assign to Academic Year',
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

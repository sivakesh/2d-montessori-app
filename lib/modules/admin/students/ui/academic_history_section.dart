import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/models/academic_year_model.dart';
import '../../settings/providers/academic_year_provider.dart';
import '../providers/student_enrollment_provider.dart';
import 'student_enrollment_assign_dialog.dart';

/// A student's full enrollment history — every academic year they've been
/// placed in a class for, newest first — plus (unless [readOnly]) the
/// "Assign to Academic Year" action. Extracted as its own [ConsumerWidget]
/// (rather than a private method on [AdminStudentViewDialog], which
/// hardcodes `FirebaseFirestore.instance` throughout and has no test
/// coverage of its own) so this new AY-01 surface can be exercised
/// end-to-end with fake-Firestore-backed providers in isolation, without
/// needing to touch or add DI to that larger, pre-existing, already
/// crash-history-prone file (see admin_student_form_class_dropdown_test.dart).
class AcademicHistorySection extends ConsumerWidget {
  const AcademicHistorySection({
    super.key,
    required this.studentId,
    required this.currentClassId,
    this.classNames = const {},
    this.readOnly = false,
    this.onAssigned,
  });

  final String studentId;
  final String? currentClassId;

  /// classId -> display name, so each history row can show a class name
  /// without a second class-loading round trip — the caller (Student View
  /// dialog) already has this map loaded for its own Profile tab.
  final Map<String, String> classNames;
  final bool readOnly;

  /// Called after a successful "Assign to Academic Year" save, so the
  /// caller can refresh anything it owns outside this widget (e.g. the
  /// Student View dialog's own `_studentData`, which shows the *current*
  /// class on the Profile tab).
  final VoidCallback? onAssigned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enrollmentsAsync = ref.watch(studentEnrollmentsProvider(studentId));
    final academicYearsAsync = ref.watch(academicYearsProvider);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
            child: enrollmentsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Could not load academic history: $error')),
              data: (enrollments) {
                if (enrollments.isEmpty) {
                  return const Center(child: Text('No academic history yet'));
                }
                final years = academicYearsAsync.valueOrNull ?? const <AcademicYearModel>[];
                final yearById = {for (final y in years) y.id: y};
                return ListView.separated(
                  itemCount: enrollments.length,
                  separatorBuilder: (context, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final enrollment = enrollments[index];
                    final year = yearById[enrollment.academicYearId];
                    final className = classNames[enrollment.classId] ?? enrollment.classId;
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.event_note_outlined, color: Colors.green),
                        title: Text('${year?.name ?? 'Unknown Academic Year'} — $className'),
                        subtitle: Text(enrollment.status),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (!readOnly) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () async {
                  final saved = await showDialog<bool>(
                    context: context,
                    builder: (_) => StudentEnrollmentAssignDialog(
                      studentId: studentId,
                      currentClassId: currentClassId,
                    ),
                  );
                  if (saved == true) onAssigned?.call();
                },
                icon: const Icon(Icons.event_available_outlined),
                label: const Text('Assign to Academic Year'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

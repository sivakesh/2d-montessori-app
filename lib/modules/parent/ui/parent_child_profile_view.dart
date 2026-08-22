import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/responsive_dialog_shell.dart';
import '../../admin/students/models/admin_student_model.dart';
import '../../finance/widgets/finance_status_chip.dart';

/// Read-only Child Profile — reached from the Parent Dashboard's selected
/// child card, never as its own navigation destination. Displays only
/// fields that already exist on [AdminStudentModel] (plus the linked
/// class's name/academicYear, resolved by the caller exactly the way
/// ParentDashboard already resolves class names for the dashboard card); no
/// field is invented, and empty ones are simply omitted rather than shown
/// blank.
///
/// Uses [ResponsiveDialogShell.form] — the same mobile-full-screen /
/// desktop-dialog convention already established by AdminStudentViewDialog
/// and every other admin dialog — so this needs no bespoke breakpoint
/// handling of its own.
void showChildProfile(
  BuildContext context, {
  required AdminStudentModel child,
  required String className,
  required String academicYear,
}) {
  showDialog<void>(
    context: context,
    builder: (_) => ResponsiveDialogShell.form(
      desktopWidth: 480,
      desktopHeight: 640,
      title: 'Child Profile',
      content: _ChildProfileContent(
        child: child,
        className: className,
        academicYear: academicYear,
      ),
    ),
  );
}

class _ChildProfileContent extends StatelessWidget {
  const _ChildProfileContent({
    required this.child,
    required this.className,
    required this.academicYear,
  });

  final AdminStudentModel child;
  final String className;
  final String academicYear;

  @override
  Widget build(BuildContext context) {
    final sectionLine = [
      if (className.isNotEmpty && className != '-') className,
      if (child.section.isNotEmpty) 'Section ${child.section}',
    ].join(' · ');

    final rows = <(String, String)>[
      if (child.admissionNo.isNotEmpty)
        ('Admission Number', child.admissionNo),
      if (className.isNotEmpty && className != '-') ('Class', className),
      if (child.section.isNotEmpty) ('Section', child.section),
      if (academicYear.isNotEmpty) ('Academic Year', academicYear),
      if (child.rollNumber.isNotEmpty) ('Roll Number', child.rollNumber),
      if (_formatDate(child.dateOfBirth) case final dob?)
        ('Date of Birth', dob),
      if (child.gender.isNotEmpty) ('Gender', child.gender),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              backgroundImage: child.profileImageUrl.isNotEmpty
                  ? NetworkImage(child.profileImageUrl)
                  : null,
              child: child.profileImageUrl.isEmpty
                  ? Text(
                      child.name.isNotEmpty ? child.name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            Text(
              child.name.isNotEmpty ? child.name : 'Unnamed student',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            if (sectionLine.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                sectionLine,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 10),
            FinanceStatusChip(
              label: child.isActive ? 'Active' : 'Inactive',
              color: child.isActive ? AppColors.secondary : Colors.grey,
            ),
          ],
        ),
        const SizedBox(height: 24),
        _ProfileSection(title: 'Student Details', rows: rows),
      ],
    );
  }

  static String? _formatDate(dynamic value) {
    final date = value is Timestamp
        ? value.toDate()
        : value is DateTime
        ? value
        : value is String
        ? DateTime.tryParse(value)
        : null;
    if (date == null) return null;
    return DateFormat('d MMM yyyy').format(date);
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _ProfileRow(label: rows[i].$1, value: rows[i].$2),
          ],
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

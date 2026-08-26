import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../ui/admin_layout.dart';
import '../data/academic_year_service.dart';
import '../data/school_settings_service.dart';
import 'access_restricted_view.dart';
import 'academic_year_screen.dart';
import 'school_settings_screen.dart';

/// Settings landing area (AdminSidebar/mobile "More Modules" destination
/// 11) — a small hub of settings categories. Per SETTINGS-01's scope,
/// "School" was the first category implemented; SETTINGS-02 adds "Academic
/// Year" alongside it. Users & Roles, Notification Settings and Application
/// Settings remain explicitly out of scope and are not stubbed here (unlike
/// Reports, which keeps its own separate "coming soon" placeholder on the
/// sidebar).
class AdminSettingsScreen extends ConsumerWidget {
  const AdminSettingsScreen({super.key, this.service, this.academicYearService});

  /// Threaded through to the pushed [SchoolSettingsScreen] — lets tests
  /// (and any future settings category added here) inject a fake service
  /// instead of the real Firebase-backed default, the same DI shape as
  /// every other injectable Admin screen/service in this app.
  final SchoolSettingsService? service;

  /// Threaded through to the pushed [AcademicYearScreen] — same DI shape as
  /// [service] above.
  final AcademicYearService? academicYearService;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = (ref.watch(currentUserProvider)?.role ?? '').toLowerCase();
    final isAdmin = role == 'admin';

    return AdminLayout(
      selectedIndex: 11,
      title: 'Settings',
      body: isAdmin
          ? _SettingsList(service: service, academicYearService: academicYearService)
          : const AccessRestrictedView(),
    );
  }
}

class _SettingsList extends StatelessWidget {
  const _SettingsList({this.service, this.academicYearService});

  final SchoolSettingsService? service;
  final AcademicYearService? academicYearService;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: AppColors.card,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.school_outlined, color: AppColors.primary, size: 20),
            ),
            title: const Text(
              'School',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            subtitle: const Text(
              'School name, contact information and logo',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SchoolSettingsScreen(service: service)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: AppColors.card,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.event_note_outlined, color: AppColors.primary, size: 20),
            ),
            title: const Text(
              'Academic Year',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            subtitle: const Text(
              'Manage academic years and the current school year',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AcademicYearScreen(service: academicYearService)),
            ),
          ),
        ),
      ],
    );
  }
}

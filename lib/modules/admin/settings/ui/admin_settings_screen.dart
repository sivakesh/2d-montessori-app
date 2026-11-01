import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../ui/admin_layout.dart';
import '../../website/data/website_content_admin_service.dart';
import '../../website/ui/website_content_screen.dart';
import '../../../forms/data/form_submissions_inbox_service.dart';
import '../../../forms/data/website_forms_service.dart';
import '../../../forms/ui/forms_manager_screen.dart';
import '../data/academic_year_service.dart';
import '../data/public_submission_settings_service.dart';
import '../data/school_settings_service.dart';
import 'access_restricted_view.dart';
import 'public_submissions_settings_screen.dart';
import 'academic_year_screen.dart';
import 'school_settings_screen.dart';

/// Settings landing area (AdminSidebar/mobile "More Modules" destination
/// 11) — a small hub of settings categories. Per SETTINGS-01's scope,
/// "School" was the first category implemented; SETTINGS-02 adds "Academic
/// Year" alongside it, and "Website" manages the public website's images,
/// gallery and page content. Users & Roles, Notification Settings and Application
/// Settings remain explicitly out of scope and are not stubbed here (unlike
/// Reports, which keeps its own separate "coming soon" placeholder on the
/// sidebar).
class AdminSettingsScreen extends ConsumerWidget {
  const AdminSettingsScreen({super.key, this.service, this.academicYearService, this.websiteService, this.formsService, this.formsInbox, this.publicSubmissions});

  /// Threaded through to the pushed [SchoolSettingsScreen] — lets tests
  /// (and any future settings category added here) inject a fake service
  /// instead of the real Firebase-backed default, the same DI shape as
  /// every other injectable Admin screen/service in this app.
  final SchoolSettingsService? service;

  /// Threaded through to the pushed [AcademicYearScreen] — same DI shape as
  /// [service] above.
  final AcademicYearService? academicYearService;

  /// Threaded through to the pushed [WebsiteContentScreen] — same DI shape
  /// as [service] above.
  final WebsiteContentAdminService? websiteService;

  /// Threaded through to the pushed [FormsManagerScreen] — same DI shape.
  final WebsiteFormsService? formsService;
  final FormSubmissionsInboxService? formsInbox;

  /// Threaded through to the pushed [PublicSubmissionsSettingsScreen].
  final PublicSubmissionSettingsService? publicSubmissions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = (ref.watch(currentUserProvider)?.role ?? '').toLowerCase();
    final isAdmin = role == 'admin';

    return AdminLayout(
      selectedIndex: 11,
      title: 'Settings',
      body: isAdmin
          ? _SettingsList(service: service, academicYearService: academicYearService, websiteService: websiteService, formsService: formsService, formsInbox: formsInbox, publicSubmissions: publicSubmissions)
          : const AccessRestrictedView(),
    );
  }
}

class _SettingsList extends StatelessWidget {
  const _SettingsList({this.service, this.academicYearService, this.websiteService, this.formsService, this.formsInbox, this.publicSubmissions});

  final SchoolSettingsService? service;
  final AcademicYearService? academicYearService;
  final WebsiteContentAdminService? websiteService;
  final WebsiteFormsService? formsService;
  final FormSubmissionsInboxService? formsInbox;
  final PublicSubmissionSettingsService? publicSubmissions;

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
        const SizedBox(height: 12),
        Card(
          color: AppColors.card,
          child: ListTile(
            key: const Key('settings-website'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.photo_library_outlined, color: AppColors.primary, size: 20),
            ),
            title: const Text(
              'Website',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            subtitle: const Text(
              'Public website images, gallery and page content',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => WebsiteContentScreen(service: websiteService)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: AppColors.card,
          child: ListTile(
            key: const Key('settings-website-forms'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.assignment_outlined, color: AppColors.primary, size: 20),
            ),
            title: const Text(
              'Website forms',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            subtitle: const Text(
              'Enquiry and registration forms, and their submissions',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => FormsManagerScreen(forms: formsService, inbox: formsInbox, publicSubmissions: publicSubmissions)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: AppColors.card,
          child: ListTile(
            key: const Key('settings-public-submissions'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.toggle_on_outlined, color: AppColors.primary, size: 20),
            ),
            title: const Text(
              'Public form submissions',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            subtitle: const Text(
              'Whether website visitors can send forms, and what they see while they can’t',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => PublicSubmissionsSettingsScreen(service: publicSubmissions)),
            ),
          ),
        ),
      ],
    );
  }
}

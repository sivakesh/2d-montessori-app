import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../auth/providers/auth_provider.dart';
import '../data/academic_year_service.dart';
import '../models/academic_year_model.dart';
import '../models/school_settings_model.dart' show kDefaultSchoolId;
import '../providers/academic_year_provider.dart';
import 'access_restricted_view.dart';
import 'academic_year_form_dialog.dart';

/// Admin -> Settings -> Academic Year. Pushed from AdminSettingsScreen, the
/// same "plain Scaffold with its own AppBar/back button" shape
/// SchoolSettingsScreen uses for its own drill-down. Lists every academic
/// year for [kDefaultSchoolId] (newest first), surfaces the current year
/// prominently, and offers Add/Edit/Set as Current/Activate-Deactivate —
/// never Delete, per the SETTINGS-02 spec (deleting a year could orphan
/// historical records, so it isn't offered at all).
class AcademicYearScreen extends StatelessWidget {
  const AcademicYearScreen({super.key, this.service});

  /// Lets tests inject a fake-Firestore-backed service, the same DI shape
  /// SchoolSettingsScreen uses.
  final AcademicYearService? service;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: const Text('Academic Year')),
      body: _AcademicYearBody(service: service),
    );
  }
}

class _AcademicYearBody extends ConsumerWidget {
  const _AcademicYearBody({this.service});

  final AcademicYearService? service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = (ref.watch(currentUserProvider)?.role ?? '').toLowerCase();
    if (role != 'admin') return const AccessRestrictedView();

    final AcademicYearService effectiveService = service ?? ref.watch(academicYearServiceProvider);
    final yearsAsync = service != null
        ? null // Test-injected service reads directly below instead of via the provider.
        : ref.watch(academicYearsProvider);

    return _AcademicYearListView(service: effectiveService, overrideAsync: yearsAsync);
  }
}

/// Separated from [_AcademicYearBody] so it can either watch the shared
/// [academicYearsProvider] (production) or manage its own load state when a
/// test injects a fake [AcademicYearService] directly (bypassing the
/// provider, which always constructs the real Firebase-backed service) —
/// same "provider in prod, direct service + local state in tests" split
/// SchoolSettingsScreen doesn't need (it has no provider-backed list), but
/// AdminFeesScreen-style screens elsewhere in this app do.
class _AcademicYearListView extends ConsumerStatefulWidget {
  const _AcademicYearListView({required this.service, required this.overrideAsync});

  final AcademicYearService service;
  final AsyncValue<List<AcademicYearModel>>? overrideAsync;

  @override
  ConsumerState<_AcademicYearListView> createState() => _AcademicYearListViewState();
}

class _AcademicYearListViewState extends ConsumerState<_AcademicYearListView> {
  List<AcademicYearModel>? _localYears;
  bool _localLoading = false;

  bool get _usingProvider => widget.overrideAsync != null;

  @override
  void initState() {
    super.initState();
    if (!_usingProvider) _loadLocal();
  }

  Future<void> _loadLocal() async {
    setState(() => _localLoading = true);
    final years = await widget.service.getAllAcademicYears(schoolId: kDefaultSchoolId);
    if (!mounted) return;
    setState(() {
      _localYears = years;
      _localLoading = false;
    });
  }

  void _refresh() {
    if (_usingProvider) {
      ref.invalidate(academicYearsProvider);
      ref.invalidate(currentAcademicYearProvider);
    } else {
      _loadLocal();
    }
  }

  String get _role => (ref.read(currentUserProvider)?.role ?? '').toLowerCase();
  String get _userId => ref.read(currentUserProvider)?.id ?? '';

  Future<void> _openForm({AcademicYearModel? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AcademicYearFormDialog(
        role: _role,
        userId: _userId,
        existing: existing,
        service: widget.service,
      ),
    );
    if (saved == true) {
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(existing == null ? 'Academic year created' : 'Academic year updated')),
        );
      }
    }
  }

  Future<void> _confirmSetCurrent(AcademicYearModel year) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set as Current Academic Year?'),
        content: Text(
          'This changes the application\'s current academic context to "${year.name}". '
          'Existing Attendance, Leave, Fees, Finance and Calendar records are never changed, '
          'deleted, or migrated by this action, and no student\'s class history is altered.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Set as Current')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.service.setCurrentAcademicYear(
        schoolId: kDefaultSchoolId,
        requesterRole: _role,
        id: year.id,
        updatedBy: _userId,
      );
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${year.name}" is now the current academic year')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _toggleActive(AcademicYearModel year) async {
    try {
      if (year.isActive) {
        await widget.service.deactivateAcademicYear(
          schoolId: kDefaultSchoolId,
          requesterRole: _role,
          id: year.id,
          updatedBy: _userId,
        );
      } else {
        await widget.service.activateAcademicYear(
          schoolId: kDefaultSchoolId,
          requesterRole: _role,
          id: year.id,
          updatedBy: _userId,
        );
      }
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(year.isActive ? 'Academic year deactivated' : 'Academic year activated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final years = _usingProvider ? widget.overrideAsync!.valueOrNull : _localYears;
    final isLoading = _usingProvider ? widget.overrideAsync!.isLoading : _localLoading;
    final hasError = _usingProvider ? widget.overrideAsync!.hasError : false;

    if (isLoading && years == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (hasError) {
      return Center(child: Text('Could not load academic years: ${widget.overrideAsync!.error}'));
    }

    final list = years ?? const <AcademicYearModel>[];
    final current = list.where((y) => y.isCurrent).cast<AcademicYearModel?>().firstOrNull;

    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 700;
            return ListView(
              padding: EdgeInsets.fromLTRB(isWide ? 24 : 16, 20, isWide ? 24 : 16, 96),
              children: [
                _CurrentYearCard(current: current),
                const SizedBox(height: 20),
                const Text(
                  'ACADEMIC YEARS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  const _EmptyState()
                else
                  ...list.map(
                    (year) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _AcademicYearCard(
                        year: year,
                        onEdit: () => _openForm(existing: year),
                        onSetCurrent: year.isCurrent ? null : () => _confirmSetCurrent(year),
                        onToggleActive: year.isCurrent ? null : () => _toggleActive(year),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add),
            label: const Text('Add Academic Year'),
          ),
        ),
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _CurrentYearCard extends StatelessWidget {
  const _CurrentYearCard({required this.current});

  final AcademicYearModel? current;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppSizes.borderRadiusWeb),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CURRENT ACADEMIC YEAR',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            current?.name ?? 'No current academic year set',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppSizes.borderRadiusWeb),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: const Column(
        children: [
          Icon(Icons.event_note_outlined, size: 40, color: AppColors.textSecondary),
          SizedBox(height: 12),
          Text('No academic years yet', style: TextStyle(fontWeight: FontWeight.w700)),
          SizedBox(height: 4),
          Text(
            'Add one to start assigning classes, fees, and reports to a school year.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _AcademicYearCard extends StatelessWidget {
  const _AcademicYearCard({
    required this.year,
    required this.onEdit,
    required this.onSetCurrent,
    required this.onToggleActive,
  });

  final AcademicYearModel year;
  final VoidCallback onEdit;
  final VoidCallback? onSetCurrent;
  final VoidCallback? onToggleActive;

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final statusLabel = year.isCurrent ? 'Active' : (year.isActive ? 'Historical' : 'Inactive');
    final statusColor = year.isCurrent
        ? AppColors.primary
        : (year.isActive ? AppColors.textSecondary : Colors.red);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppSizes.borderRadiusWeb),
        border: Border.all(
          color: year.isCurrent ? AppColors.primary.withValues(alpha: 0.4) : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              Text(
                year.name,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary),
              ),
              if (year.isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'CURRENT',
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_formatDate(year.startDate)} - ${_formatDate(year.endDate)}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
              ),
              if (onSetCurrent != null)
                OutlinedButton.icon(
                  onPressed: onSetCurrent,
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Set as Current'),
                ),
              if (onToggleActive != null)
                OutlinedButton.icon(
                  onPressed: onToggleActive,
                  icon: Icon(year.isActive ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 16),
                  label: Text(year.isActive ? 'Deactivate' : 'Activate'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/bottom_nav.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/layout/sidebar.dart';
import '../../auth/models/app_user.dart';
import '../../auth/data/user_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../attendance/providers/attendance_provider.dart';
import '../../attendance/ui/attendance_screen.dart';
import '../../classes/providers/class_provider.dart';
import '../../classes/ui/class_list_screen.dart';
import '../../mood_checkin/models/mood_checkin_model.dart';
import '../../mood_checkin/models/mood_option_model.dart';
import '../../mood_checkin/providers/mood_checkin_provider.dart';
import '../../mood_checkin/ui/mood_checkin_dialog.dart';
import '../../mood_checkin/widgets/mood_option_chip.dart';
import '../../students/providers/student_provider.dart';
import '../../students/ui/student_list_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int selectedIndex = 0;
  bool _loadingMetrics = true;
  bool _savingCheckin = false;
  List<_DashboardMetric> _metrics = const [];
  List<MoodCheckinModel> _recentMoodCheckins = const [];
  final Map<String, String> _classNames = {};

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _loadingMetrics = true);
    try {
      final attendanceService = ref.read(attendanceServiceProvider);
      final moodService = ref.read(moodCheckinServiceProvider);
      final studentService = ref.read(studentServiceProvider);
      final classService = ref.read(classServiceProvider);
      final userService = UserService();

      final classes = await classService.getClasses();
      final students = await studentService.getAllStudents();
      final staff = await userService.getStaffUsers();
      final attendanceMap = await attendanceService.getTodayAttendanceMap();
      final overview = await attendanceService.getAttendanceOverview();
      final moodCount = await moodService.getTodayMoodCheckinCount();
      final alertCount = await moodService.getTodayAlertCount();
      final recentMoodCheckins = await moodService.getLatestTodayMoodCheckins(limit: 5);

      final classNames = <String, String>{
        for (final doc in classes) doc.id: doc.data()['name']?.toString() ?? '-',
      };
      _classNames
        ..clear()
        ..addAll(classNames);

      final activeStudents = students.where((doc) => doc.data()['isActive'] == true).length;
      const staffRoles = {'staff', 'teacher', 'admin_staff'};
      final activeStaff = staff.where((user) => staffRoles.contains(user.role.toLowerCase())).length;
      final presentCount = overview.presentCount;
      final absentCount = overview.absentCount;
      final notMarked = (activeStudents + activeStaff - presentCount - absentCount).clamp(0, 99999);
      final staffPresentToday = attendanceMap.values.where((record) {
        final entityType = record['entityType']?.toString() ?? '';
        final status = record['status']?.toString() ?? '';
        return entityType == 'staff' && status == 'present';
      }).length;
      final studentPresentToday = attendanceMap.values.where((record) {
        final entityType = record['entityType']?.toString() ?? '';
        final status = record['status']?.toString() ?? '';
        return entityType == 'student' && status == 'present';
      }).length;

      final metrics = <_DashboardMetric>[
        _DashboardMetric('Total Students', activeStudents.toString(), Icons.groups_outlined),
        _DashboardMetric('Staff Present Today', staffPresentToday.toString(), Icons.badge_outlined),
        _DashboardMetric('Students Present Today', studentPresentToday.toString(), Icons.verified_outlined),
        _DashboardMetric('Not Marked Today', notMarked.toString(), Icons.pending_actions_outlined),
        _DashboardMetric('Mood Check-ins Today', moodCount.toString(), Icons.favorite_outline),
        _DashboardMetric('Alerts / Distress', alertCount.toString(), Icons.warning_amber_outlined),
      ];

      if (!mounted) return;
      setState(() {
        _metrics = metrics;
        _recentMoodCheckins = recentMoodCheckins;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _metrics = const [];
        _recentMoodCheckins = const [];
      });
    } finally {
      if (mounted) setState(() => _loadingMetrics = false);
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _showManualStudentCheckIn() async {
    final student = await _selectStudent();
    if (student == null) return;
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;
    await _saveManualMoodCheckIn(
      entityType: 'student',
      entityId: student.id,
      entityName: student.data()['name']?.toString() ?? '',
      classId: student.data()['classId']?.toString(),
      className: _classNames[student.data()['classId']?.toString() ?? ''],
      createdBy: currentUser.id,
    );
  }

  Future<void> _showManualStaffCheckIn() async {
    final staff = await _selectStaff();
    if (staff == null) return;
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;
    await _saveManualMoodCheckIn(
      entityType: 'staff',
      entityId: staff.id,
      entityName: staff.name?.isNotEmpty == true ? staff.name! : staff.phone,
      createdBy: currentUser.id,
    );
  }

  Future<void> _saveManualMoodCheckIn({
    required String entityType,
    required String entityId,
    required String entityName,
    required String createdBy,
    String? classId,
    String? className,
  }) async {
    final mood = await MoodCheckinDialog.show(context, entityType: entityType);
    if (mood == null) return;
    final service = ref.read(moodCheckinServiceProvider);
    String? photoUrl;
    setState(() => _savingCheckin = true);
    try {
      final wantPhoto = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Add photo?'),
          content: const Text('Would you like to attach an optional photo?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Add Photo'),
            ),
          ],
        ),
      );

      if (wantPhoto == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Uploading photo...')),
        );
        photoUrl = await service.uploadOptionalMoodPhoto(
          entityType: entityType,
          entityId: entityId,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saving check-in...')),
      );
      await service.createMoodCheckin(
        entityType: entityType,
        entityId: entityId,
        entityName: entityName,
        classId: classId,
        className: className,
        moodCode: mood.moodCode,
        moodLabel: mood.moodLabel,
        moodCategory: mood.moodCategory,
        intensity: mood.intensity,
        notes: mood.notes,
        source: 'manual',
        photoUrl: photoUrl,
        createdBy: createdBy,
      );
      await _loadDashboardData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mood check-in saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save mood check-in: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingCheckin = false);
    }
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _selectStudent() async {
    final studentService = ref.read(studentServiceProvider);
    final classes = await ref.read(classServiceProvider).getClasses();
    final classNames = {for (final doc in classes) doc.id: doc.data()['name']?.toString() ?? '-'};
    final students = await studentService.getAllStudents();
    if (!mounted) return null;

    String query = '';
    String? selectedClassId;
    return showDialog<QueryDocumentSnapshot<Map<String, dynamic>>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = students.where((doc) {
              final data = doc.data();
              if (data['isActive'] != true) return false;
              final classId = data['classId']?.toString();
              if (selectedClassId != null && classId != selectedClassId) return false;
              final name = data['name']?.toString().toLowerCase() ?? '';
              final admissionNo = data['admissionNo']?.toString().toLowerCase() ?? '';
              final className = classNames[classId ?? '']?.toLowerCase() ?? '';
              return query.isEmpty ||
                  name.contains(query) ||
                  admissionNo.contains(query) ||
                  className.contains(query);
            }).toList();

            return Dialog(
              insetPadding: const EdgeInsets.all(20),
              child: SizedBox(
                width: 600,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Select Student', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Search student',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) => setDialogState(() => query = value.toLowerCase()),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('All Classes'),
                            selected: selectedClassId == null,
                            onSelected: (_) => setDialogState(() => selectedClassId = null),
                          ),
                          for (final doc in classes)
                            FilterChip(
                              label: Text(doc.data()['name']?.toString() ?? ''),
                              selected: selectedClassId == doc.id,
                              onSelected: (_) => setDialogState(() => selectedClassId = doc.id),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final student = filtered[index];
                            final data = student.data();
                            return ListTile(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              tileColor: Colors.grey.shade50,
                              title: Text(data['name']?.toString() ?? ''),
                              subtitle: Text(
                                'Admission: ${data['admissionNo']?.toString() ?? '-'} • Class: ${classNames[data['classId']?.toString() ?? ''] ?? '-'}',
                              ),
                              onTap: () => Navigator.of(dialogContext).pop(student),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<AppUser?> _selectStaff() async {
    final users = await UserService().getStaffUsers();
    if (!mounted) return null;
    String query = '';
    return showDialog<AppUser>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = users.where((user) {
              final name = (user.name ?? '').toLowerCase();
              final phone = user.phone.toLowerCase();
              final role = user.role.toLowerCase();
              return query.isEmpty || name.contains(query) || phone.contains(query) || role.contains(query);
            }).toList();

            return Dialog(
              insetPadding: const EdgeInsets.all(20),
              child: SizedBox(
                width: 560,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Select Staff Member', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Search staff',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) => setDialogState(() => query = value.toLowerCase()),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final staff = filtered[index];
                            final name = staff.name?.isNotEmpty == true ? staff.name! : staff.phone;
                            return ListTile(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              tileColor: Colors.grey.shade50,
                              title: Text(name),
                              subtitle: Text('${staff.phone} • ${staff.role}'),
                              onTap: () => Navigator.of(dialogContext).pop(staff),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final dashboardContent = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.fromLTRB(isMobile ? 20 : 32, 24, isMobile ? 20 : 32, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DashboardHeader(
              userName: user.name?.isNotEmpty == true ? user.name! : user.phone,
              userPhone: user.phone,
              dateLabel: _formatDate(DateTime.now().toLocal()),
            ),
            const SizedBox(height: 14),
            _PersonalWellbeingCard(
              onSaved: () async {
                await _loadDashboardData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Wellbeing check-in saved')),
                  );
                }
              },
            ),
            const SizedBox(height: 20),
            if (_loadingMetrics)
              const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ))
            else ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1200
                      ? 3
                      : constraints.maxWidth >= 700
                          ? 2
                          : 1;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final metric in _metrics)
                        SizedBox(
                          width: (constraints.maxWidth - (16 * (columns - 1))) / columns,
                          child: _MetricCard(metric: metric),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              Text('Quick Actions', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1000
                      ? 4
                      : constraints.maxWidth >= 600
                          ? 2
                          : 1;
                  final actions = [
                    _QuickActionCard(
                      icon: Icons.fact_check_outlined,
                      title: 'Mark Student Attendance',
                      subtitle: 'Go to attendance screen',
                      onTap: () => setState(() => selectedIndex = 3),
                    ),
                    _QuickActionCard(
                      icon: Icons.badge_outlined,
                      title: 'Mark Staff Attendance',
                      subtitle: 'Go to attendance screen',
                      onTap: () => setState(() => selectedIndex = 3),
                    ),
                    _QuickActionCard(
                      icon: Icons.favorite_border,
                      title: 'Student Mood Check-In',
                      subtitle: 'Manual mood observation',
                      onTap: _savingCheckin ? null : _showManualStudentCheckIn,
                    ),
                    _QuickActionCard(
                      icon: Icons.health_and_safety_outlined,
                      title: 'Staff Wellbeing Check-In',
                      subtitle: 'Manual wellbeing check-in',
                      onTap: _savingCheckin ? null : _showManualStaffCheckIn,
                    ),
                  ];
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final action in actions)
                        SizedBox(
                          width: (constraints.maxWidth - (12 * (columns - 1))) / columns,
                          child: action,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              Text('Recent Mood Check-ins', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (_recentMoodCheckins.isEmpty)
                const Text('No mood check-ins today.')
              else
                _ExpandableRecentMoodList(items: _recentMoodCheckins, showCount: 3),
            ],
          ],
        ),
      ),
    );

    return ResponsiveLayout(
      mobile: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          centerTitle: false,
          title: const Text('Dashboard'),
          actions: [
            if (user.role.toLowerCase() == 'admin')
              IconButton(
                icon: const Icon(Icons.admin_panel_settings),
                onPressed: () => Navigator.of(context).pushNamed('/admin_dashboard'),
              ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await ref.read(authServiceProvider).logout(ref, context);
                if (context.mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                }
              },
            ),
          ],
        ),
        body: SafeArea(
          child: switch (selectedIndex) {
            0 => RefreshIndicator(onRefresh: _loadDashboardData, child: dashboardContent),
            1 => const ClassListScreen(readOnly: true),
            2 => const StudentListScreen(),
            3 => const AttendanceScreen(),
            _ => RefreshIndicator(onRefresh: _loadDashboardData, child: dashboardContent),
          },
        ),
        bottomNavigationBar: AppBottomNav(
          selectedIndex: selectedIndex,
          onItemTapped: (index) => setState(() => selectedIndex = index),
        ),
      ),
      web: Scaffold(
        backgroundColor: Colors.grey[50],
        body: Row(
          children: [
            AppSidebar(
              selectedIndex: selectedIndex,
              onItemTapped: (index) => setState(() => selectedIndex = index),
            ),
            Expanded(
              child: Column(
                children: [
                  AppBar(
                    title: const Text('Dashboard'),
                    actions: [
                      if (user.role.toLowerCase() == 'admin')
                        IconButton(
                          icon: const Icon(Icons.admin_panel_settings),
                          onPressed: () => Navigator.of(context).pushNamed('/admin_dashboard'),
                        ),
                      IconButton(
                        icon: const Icon(Icons.logout),
                        onPressed: () async {
                          await ref.read(authServiceProvider).logout(ref, context);
                          if (context.mounted) {
                            Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                          }
                        },
                      ),
                    ],
                  ),
                  Expanded(
                    child: switch (selectedIndex) {
                      0 => RefreshIndicator(onRefresh: _loadDashboardData, child: dashboardContent),
                      1 => const ClassListScreen(readOnly: true),
                      2 => const StudentListScreen(),
                      3 => const AttendanceScreen(),
                      _ => RefreshIndicator(onRefresh: _loadDashboardData, child: dashboardContent),
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.userName,
    required this.userPhone,
    required this.dateLabel,
  });

  final String userName;
  final String userPhone;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Welcome back', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Text(userName, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(userPhone, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Text(dateLabel, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }
}

class _DashboardMetric {
  const _DashboardMetric(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
}

class _PersonalWellbeingCard extends ConsumerStatefulWidget {
  const _PersonalWellbeingCard({
    required this.onSaved,
  });

  final Future<void> Function() onSaved;

  @override
  ConsumerState<_PersonalWellbeingCard> createState() => _PersonalWellbeingCardState();
}

class _PersonalWellbeingCardState extends ConsumerState<_PersonalWellbeingCard> {
  bool _saving = false;
  String? _savingMoodCode;
  String? _latestMoodCode;
  List<MoodCheckinModel> _todayHistory = const [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;
    final service = ref.read(moodCheckinServiceProvider);
    final entityId = _getCurrentStaffEntityId(currentUser);
    debugPrint('FETCH PERSONAL TODAY CHECKINS');
    debugPrint('entityId used: $entityId');
    final today = DateTime.now().toLocal();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));
    debugPrint('startOfToday: $startOfToday');
    debugPrint('endOfToday: $endOfToday');
    final history = await service.getTodayMoodCheckinsForEntity(
      entityType: 'staff',
      entityId: entityId,
    );
    debugPrint('count fetched: ${history.length}');
    debugPrint('count after filtering: ${history.length}');
    if (!mounted) return;
    setState(() {
      _todayHistory = history;
    });
  }

  Future<void> _saveMood(MoodOptionModel option) async {
    if (_saving) return;
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;
    final service = ref.read(moodCheckinServiceProvider);
    final entityId = _getCurrentStaffEntityId(currentUser);
    final entityName = currentUser.name?.isNotEmpty == true
        ? currentUser.name!
        : currentUser.phone.isNotEmpty
            ? currentUser.phone
            : 'Staff';
    final createdBy = FirebaseAuth.instance.currentUser?.uid.isNotEmpty == true
        ? FirebaseAuth.instance.currentUser!.uid
        : currentUser.id.isNotEmpty
            ? currentUser.id
            : currentUser.phone.isNotEmpty
                ? currentUser.phone
                : 'staff';
    final checkInAt = DateTime.now().toUtc();
    debugPrint('Inline staff wellbeing check-in payload:');
    debugPrint('current user id: ${currentUser.id}');
    debugPrint('current user name/phone: ${currentUser.name ?? currentUser.phone}');
    debugPrint('selected moodCode: ${option.moodCode}');
    debugPrint('selected moodLabel: ${option.moodLabel}');
    debugPrint('moodCategory: ${option.moodCategory}');
    debugPrint('entityType: staff');
    debugPrint('source: manual');
    debugPrint('checkInAt: $checkInAt');
    setState(() {
      _saving = true;
      _savingMoodCode = option.moodCode;
      _latestMoodCode = option.moodCode;
    });
    try {
      debugPrint('Saving inline staff wellbeing check-in with entityId: $entityId');
      await service.createMoodCheckin(
        entityType: 'staff',
        entityId: entityId,
        entityName: entityName,
        moodCode: option.moodCode,
        moodLabel: option.moodLabel,
        moodCategory: option.moodCategory,
        intensity: 3,
        notes: '',
        source: 'manual',
        photoUrl: null,
        checkInAt: checkInAt,
        createdBy: createdBy,
      );
      await _loadHistory();
      await widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wellbeing check-in saved')),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (mounted) {
        setState(() {
          _latestMoodCode = null;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Could not save inline staff wellbeing check-in: $e');
      debugPrint('Stack trace: $stackTrace');
      if (e is FirebaseException && e.code.toLowerCase() == 'permission-denied') {
        debugPrint('Mood check-in save failed due to Firestore permission/rules');
      }
      if (mounted) {
        setState(() {
          _latestMoodCode = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save check-in. Please try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _savingMoodCode = null;
        });
      }
    }
  }

  String _getCurrentStaffEntityId(dynamic currentUser) {
    final appUserId = currentUser.id.toString().trim();
    if (appUserId.isNotEmpty) return appUserId;
    final authUid = FirebaseAuth.instance.currentUser?.uid.trim();
    if (authUid != null && authUid.isNotEmpty) return authUid;
    final phone = currentUser.phone.toString().trim();
    if (phone.isNotEmpty) return phone;
    return 'staff';
  }

  String? _latestLabelAndTime(BuildContext context) {
    if (_todayHistory.isEmpty) return null;
    final latest = _todayHistory.first;
    final time = latest.checkInAt;
    if (time == null) return latest.moodLabel;
    return '${latest.moodLabel} · ${TimeOfDay.fromDateTime(time).format(context)}';
  }

  @override
  Widget build(BuildContext context) {
    final latestLine = _latestLabelAndTime(context);
    final inlineOptions = staffMoodOptions.where((option) => option.moodCode != 'not_observed').toList();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.self_improvement_outlined, color: Colors.green.shade700),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('How are you feeling now?', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          'Take a quick wellbeing check-in for yourself.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (latestLine != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Latest: $latestLine',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in inlineOptions)
                    _InlineMoodChip(
                      option: option,
                      selected: _latestMoodCode == option.moodCode,
                      saving: _savingMoodCode == option.moodCode,
                      disabled: _saving,
                      onTap: () => _saveMood(option),
                    ),
                ],
              ),
              if (_saving) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Saving check-in...',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Text('Today\'s check-ins', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              if (_todayHistory.isEmpty)
                Text(
                  'No check-ins yet today.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                )
              else
                _ExpandableHistoryList(items: _todayHistory, showCount: 3),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayHistoryItem extends StatelessWidget {
  const _TodayHistoryItem({required this.item});

  final MoodCheckinModel item;

  @override
  Widget build(BuildContext context) {
    final time = item.checkInAt;
    final timeLabel = time == null ? '-' : TimeOfDay.fromDateTime(time).format(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$timeLabel · ${item.moodLabel}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ExpandableHistoryList extends StatefulWidget {
  const _ExpandableHistoryList({
    required this.items,
    required this.showCount,
  });

  final List<MoodCheckinModel> items;
  final int showCount;

  @override
  State<_ExpandableHistoryList> createState() => _ExpandableHistoryListState();
}

class _ExpandableHistoryListState extends State<_ExpandableHistoryList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final visibleItems = _expanded || widget.items.length <= widget.showCount
        ? widget.items
        : widget.items.take(widget.showCount).toList();
    final hasMore = widget.items.length > widget.showCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: Column(
            children: [
              for (final item in visibleItems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _TodayHistoryItem(item: item),
                ),
            ],
          ),
        ),
        if (hasMore)
          TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
            label: Text(_expanded ? 'Show less' : 'Show more'),
          ),
      ],
    );
  }
}

class _InlineMoodChip extends StatelessWidget {
  const _InlineMoodChip({
    required this.option,
    required this.selected,
    required this.saving,
    required this.disabled,
    required this.onTap,
  });

  final MoodOptionModel option;
  final bool selected;
  final bool saving;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled && !saving ? 0.75 : 1,
      child: Stack(
        alignment: Alignment.center,
        children: [
          MoodOptionChip(
            option: option,
            selected: selected || saving,
            onTap: disabled ? () {} : onTap,
          ),
          if (saving)
            Positioned(
              right: 8,
              top: 8,
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _DashboardMetric metric;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(metric.icon, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(metric.label, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 6),
                  Text(metric.value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentMoodCard extends StatelessWidget {
  const _RecentMoodCard({required this.item});

  final MoodCheckinModel item;

  @override
  Widget build(BuildContext context) {
    final time = item.checkInAt;
    final timeLabel = time == null ? '-' : TimeOfDay.fromDateTime(time).format(context);
    final isStaff = item.entityType == 'staff';
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.entityName, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '${isStaff ? 'Staff' : 'Student'} • ${item.moodLabel} • Intensity ${item.intensity}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Text(timeLabel, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if ((item.notes ?? '').trim().isNotEmpty)
              Icon(Icons.sticky_note_2_outlined, color: Colors.grey.shade600),
          ],
        ),
      ),
    );
  }
}

class _ExpandableRecentMoodList extends StatefulWidget {
  const _ExpandableRecentMoodList({
    required this.items,
    required this.showCount,
  });

  final List<MoodCheckinModel> items;
  final int showCount;

  @override
  State<_ExpandableRecentMoodList> createState() => _ExpandableRecentMoodListState();
}

class _ExpandableRecentMoodListState extends State<_ExpandableRecentMoodList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final visibleItems = _expanded || widget.items.length <= widget.showCount
        ? widget.items
        : widget.items.take(widget.showCount).toList();
    final hasMore = widget.items.length > widget.showCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: Column(
            children: [
              for (final item in visibleItems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RecentMoodCard(item: item),
                ),
            ],
          ),
        ),
        if (hasMore)
          TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
            label: Text(_expanded ? 'Show less' : 'Show more'),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/layout/bottom_nav.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/layout/sidebar.dart';
import '../../../core/theme/app_spacing.dart';
import '../../attendance/providers/attendance_provider.dart';
import '../../attendance/ui/attendance_screen.dart';
import '../../classes/ui/class_list_screen.dart';
import '../../auth/providers/auth_provider.dart';
import '../../students/ui/student_list_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final hasMarkedTodayAsync = ref.watch(hasMarkedTodayProvider(user.id));

    Widget dashboardContent = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 20 : 32,
            vertical: isMobile ? 20 : 32,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(
                'Welcome back',
                style: isMobile
                    ? Theme.of(context).textTheme.titleLarge
                    : Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                user.phone,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ActionChip(
                    label: const Text('Manage Classes'),
                    onPressed: () => setState(() => selectedIndex = 1),
                  ),
                  ActionChip(
                    label: const Text('Manage Students'),
                    onPressed: () => setState(() => selectedIndex = 2),
                  ),
                  ActionChip(
                    label: const Text('Mark Student Attendance'),
                    onPressed: () => setState(() => selectedIndex = 3),
                  ),
                  ActionChip(
                    label: const Text('Mark Staff Attendance'),
                    onPressed: () => setState(() => selectedIndex = 4),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (user.role == 'staff') ...[
                SizedBox(
                  width: double.infinity,
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Today's Actions",
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          hasMarkedTodayAsync.when(
                            data: (hasMarkedToday) {
                              if (hasMarkedToday) {
                                return SizedBox(
                                  width: double.infinity,
                                  height: isMobile ? 48 : 52,
                                  child: ElevatedButton(
                                    onPressed: null,
                                    child: const Text('Attendance marked today'),
                                  ),
                                );
                              }

                              return SizedBox(
                                height: isMobile ? 48 : 52,
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () async {
                                    final attendanceService =
                                        ref.read(attendanceServiceProvider);
                                    try {
                                      await attendanceService.markAttendance(
                                        userId: user.id,
                                        name: user.name ?? user.phone,
                                        role: user.role,
                                      );
                                      ref.invalidate(
                                        hasMarkedTodayProvider(user.id),
                                      );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Attendance marked successfully.'),
                                          ),
                                        );
                                      }
                                    } on StateError catch (error) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text(error.message)),
                                        );
                                      }
                                    } catch (error) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Failed to mark attendance: $error',
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  child: const Text('Mark Attendance'),
                                ),
                              );
                            },
                            loading: () => const SizedBox(
                              height: 52,
                              child: Center(child: CircularProgressIndicator()),
                            ),
                        error: (_, _) => SizedBox(
                              height: isMobile ? 48 : 52,
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () async {
                                  final attendanceService =
                                      ref.read(attendanceServiceProvider);
                                  try {
                                    await attendanceService.markAttendance(
                                      userId: user.id,
                                      name: user.name ?? user.phone,
                                      role: user.role,
                                    );
                                    ref.invalidate(hasMarkedTodayProvider(user.id));
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Attendance marked successfully.'),
                                        ),
                                      );
                                    }
                                  } catch (error) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Failed to mark attendance: $error',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                                child: const Text('Mark Attendance'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    return ResponsiveLayout(
      mobile: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          centerTitle: false,
          title: Row(
            children: [
              Image.asset(
                'assets/logo.png',
                height: 28,
              ),
              const SizedBox(width: 12),
              const Text('Dashboard'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await ref.read(authServiceProvider).logout(ref, context);
                if (context.mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    '/login',
                    (route) => false,
                  );
                }
              },
            ),
          ],
        ),
        body: SafeArea(
          child: switch (selectedIndex) {
            0 => dashboardContent,
            1 => const ClassListScreen(),
            2 => const StudentListScreen(),
            3 => const AttendanceScreen(),
            4 => const AttendanceScreen(),
            _ => dashboardContent,
          },
        ),
        bottomNavigationBar: AppBottomNav(
          selectedIndex: selectedIndex,
          onItemTapped: (index) {
            setState(() {
              selectedIndex = index;
            });
          },
        ),
      ),
      web: Scaffold(
        backgroundColor: Colors.grey[50],
        body: Row(
          children: [
            AppSidebar(
              selectedIndex: selectedIndex,
              onItemTapped: (index) {
                setState(() {
                  selectedIndex = index;
                });
              },
            ),
            Expanded(
              child: Column(
                children: [
                  AppBar(
                    title: const Text('Dashboard'),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.logout),
                        onPressed: () async {
                          await ref.read(authServiceProvider).logout(ref, context);
                          if (context.mounted) {
                            Navigator.of(context).pushNamedAndRemoveUntil(
                              '/login',
                              (route) => false,
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  Expanded(
                    child: switch (selectedIndex) {
                      0 => dashboardContent,
                      1 => const ClassListScreen(),
                      2 => const StudentListScreen(),
                      3 => const AttendanceScreen(),
                      4 => const AttendanceScreen(),
                      _ => dashboardContent,
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

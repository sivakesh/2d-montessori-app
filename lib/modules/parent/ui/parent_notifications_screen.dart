import 'package:flutter/material.dart';

import '../../../core/layout/bottom_nav.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/layout/sidebar.dart';
import '../../notifications/ui/notifications_feed_screen.dart';

/// Parent's full notification feed, inside the exact same
/// ResponsiveLayout/AppSidebar/AppBottomNav shell ParentDashboard uses —
/// same background, same AppBar structure, same single "Dashboard"
/// destination. Only the AppBar title and body content differ from
/// ParentDashboard; the actual notification loading/error/list/detail
/// behavior is untouched, reused as-is from NotificationsFeedScreen via
/// showOwnScaffold: false.
///
/// Pushed from ParentDashboard's "View All", so the automatic back arrow
/// already returns to it; tapping the shell's "Dashboard" destination does
/// the same via an explicit pop (there's only ever one place to return to).
class ParentNotificationsScreen extends StatelessWidget {
  const ParentNotificationsScreen({
    super.key,
    required this.childStudentIds,
    required this.childClassIds,
  });

  final Set<String> childStudentIds;
  final Set<String> childClassIds;

  @override
  Widget build(BuildContext context) {
    final content = NotificationsFeedScreen.forParent(
      title: 'Notifications',
      childStudentIds: childStudentIds,
      childClassIds: childClassIds,
      showOwnScaffold: false,
    );

    void goToDashboard(int _) => Navigator.of(context).maybePop();

    return ResponsiveLayout(
      mobile: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(centerTitle: false, title: const Text('Notifications')),
        body: SafeArea(child: content),
        bottomNavigationBar: AppBottomNav(
          selectedIndex: 0,
          onItemTapped: goToDashboard,
        ),
      ),
      web: Scaffold(
        backgroundColor: Colors.grey[50],
        body: Row(
          children: [
            AppSidebar(selectedIndex: 0, onItemTapped: goToDashboard),
            Expanded(
              child: Column(
                children: [
                  AppBar(title: const Text('Notifications')),
                  Expanded(child: content),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

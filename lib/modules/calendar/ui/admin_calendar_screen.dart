import 'package:flutter/material.dart';

import '../../admin/ui/admin_layout.dart';
import 'calendar_view.dart';

/// Thin wrapper so the Admin back-office "More Modules" navigation can push
/// Calendar the same way it pushes AdminFeesScreen/AdminFinanceScreen —
/// AdminLayout provides the sidebar/AppBar chrome, CalendarView (already
/// role-adaptive) provides the content and its own "Add" FAB.
class AdminCalendarScreen extends StatelessWidget {
  const AdminCalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminLayout(
      selectedIndex: 12,
      title: 'Calendar',
      body: CalendarView(),
    );
  }
}

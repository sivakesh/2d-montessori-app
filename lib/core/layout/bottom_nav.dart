import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/admin/ui/admin_dashboard.dart';
import '../theme/app_colors.dart';

/// One role-aware bottom-nav destination — icon/selectedIcon/label only, no
/// screen/body reference (that mapping lives solely in DashboardScreen's/
/// ParentDashboard's own `tabs` list, keyed by this entry's position in
/// [AppBottomNav]'s `entries`). This is the single definition every visual
/// surface of the mobile nav renders from — the primary NavigationBar row
/// and the "More" overflow sheet both read the same `entries` list, so
/// (unlike the previous Staff nav bug, where label and body mapping were
/// defined twice and drifted apart) there is nowhere left for the two to
/// disagree.
class _NavEntry {
  const _NavEntry({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class AppBottomNav extends ConsumerWidget {
  final int selectedIndex;
  final Function(int) onItemTapped;

  const AppBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
  });

  /// Mobile bottom navigation must never show more than 5 items — the first
  /// 4 are the role's most-used destinations, and (only when there are more
  /// than [_maxVisible] destinations to show) the 5th is always a "More"
  /// overflow entry for the rest. Desktop's AppSidebar is untouched by this
  /// — it still renders every destination directly via NavigationRail.
  static const int _maxVisible = 5;
  static const int _primaryCount = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserProvider)?.role ?? 'parent';
    // Same operational-relevance order as AppSidebar (see its comment) —
    // Dashboard, then the daily-use destinations, then the lower-frequency
    // roster/setup screens, then Parent's own read-only Fees. For Parent
    // this yields exactly [Dashboard, Calendar, Leave, Fees] — 4 entries,
    // at or under the 5-item cap, so Parent never gets a "More" entry.
    // Staff (6) and Admin (7) both exceed the cap, so both get exactly
    // [Dashboard, Attendance, Calendar, Leave, More], with the remaining
    // destinations (Students/Classes, plus Admin for the admin role) moved
    // into the "More" sheet below rather than dropped.
    final entries = <_NavEntry>[
      const _NavEntry(
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
        label: 'Dashboard',
      ),
      if (role != 'parent')
        const _NavEntry(
          icon: Icons.check_circle_outline,
          selectedIcon: Icons.check_circle,
          label: 'Attendance',
        ),
      const _NavEntry(
        icon: Icons.calendar_month_outlined,
        selectedIcon: Icons.calendar_month,
        label: 'Calendar',
      ),
      const _NavEntry(
        icon: Icons.event_available_outlined,
        selectedIcon: Icons.event_available,
        label: 'Leave',
      ),
      if (role != 'parent') ...[
        const _NavEntry(
          icon: Icons.people_outline,
          selectedIcon: Icons.people,
          label: 'Students',
        ),
        const _NavEntry(
          icon: Icons.class_outlined,
          selectedIcon: Icons.class_,
          label: 'Classes',
        ),
      ],
      if (role == 'parent')
        const _NavEntry(
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long,
          label: 'Fees',
        ),
      if (role == 'admin')
        const _NavEntry(
          icon: Icons.admin_panel_settings_outlined,
          selectedIcon: Icons.admin_panel_settings,
          label: 'Admin',
        ),
    ];

    // Admin's destination doesn't map to a DashboardScreen tab at all — it
    // pushes the separate Admin back-office instead, exactly as before this
    // change (see the identical check AppSidebar makes for the same entry).
    final adminEntryIndex = role == 'admin' ? entries.length - 1 : -1;

    // Material's NavigationBar hard-asserts destinations.length >= 2 (it's
    // built for switching between multiple views), so a role with exactly
    // one destination — today only Parent — would crash it. Every role with
    // 2+ destinations (Staff, Admin) keeps using NavigationBar exactly as
    // before; this branch only ever engages for the single-destination case.
    if (entries.length < 2) {
      final only = entries.single;
      return _SingleDestinationNavBar(
        destination: NavigationDestination(
          icon: Icon(only.icon),
          selectedIcon: Icon(only.selectedIcon),
          label: only.label,
        ),
        onTap: () => onItemTapped(0),
      );
    }

    final overflowing = entries.length > _maxVisible;
    final primaryEntries = overflowing
        ? entries.sublist(0, _primaryCount)
        : entries;
    final overflowEntries = overflowing
        ? entries.sublist(_primaryCount)
        : const <_NavEntry>[];
    final moreSlotIndex = primaryEntries.length;

    final navDestinations = <NavigationDestination>[
      for (final entry in primaryEntries)
        NavigationDestination(
          icon: Icon(entry.icon),
          selectedIcon: Icon(entry.selectedIcon),
          label: entry.label,
        ),
      if (overflowing)
        const NavigationDestination(
          // "..." — the More/overflow entry the UX spec requires whenever a
          // role has more destinations than fit in the 5-item cap.
          icon: Icon(Icons.more_horiz),
          selectedIcon: Icon(Icons.more_horiz),
          label: 'More',
        ),
    ];

    // When the currently-active destination lives inside the overflow sheet
    // (e.g. Students/Classes/Admin), the primary bar shows "More" itself as
    // selected — never swapping one of the four primary icons/labels for
    // whatever's active inside More.
    final navSelectedIndex = overflowing
        ? (selectedIndex < primaryEntries.length
              ? selectedIndex.clamp(0, primaryEntries.length - 1)
              : moreSlotIndex)
        : selectedIndex.clamp(0, entries.length - 1);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: NavigationBar(
        selectedIndex: navSelectedIndex,
        onDestinationSelected: (index) {
          if (overflowing && index == moreSlotIndex) {
            _showMoreSheet(
              context: context,
              entries: overflowEntries,
              overflowStartIndex: _primaryCount,
              selectedIndex: selectedIndex,
              adminEntryIndex: adminEntryIndex,
              onItemTapped: onItemTapped,
            );
            return;
          }
          if (index == adminEntryIndex) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdminDashboard()),
            );
            return;
          }
          onItemTapped(index);
        },
        destinations: navDestinations,
      ),
    );
  }

  /// Opens the "More" overflow sheet for the destinations that don't fit in
  /// the primary 5-item bar. Selecting one closes the sheet and either
  /// navigates via [onItemTapped] with that destination's real, unchanged
  /// index (same index DashboardScreen's/ParentDashboard's `tabs` list
  /// already expects — no second mapping introduced), or — for the one
  /// Admin entry — pushes the Admin back-office exactly like tapping it
  /// used to, before it moved into this sheet.
  static void _showMoreSheet({
    required BuildContext context,
    required List<_NavEntry> entries,
    required int overflowStartIndex,
    required int selectedIndex,
    required int adminEntryIndex,
    required void Function(int) onItemTapped,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              for (var i = 0; i < entries.length; i++)
                _MoreMenuTile(
                  entry: entries[i],
                  selected: selectedIndex == overflowStartIndex + i,
                  onTap: () {
                    final originalIndex = overflowStartIndex + i;
                    Navigator.of(sheetContext).pop();
                    if (originalIndex == adminEntryIndex) {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AdminDashboard()),
                      );
                      return;
                    }
                    onItemTapped(originalIndex);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One row in the "More" sheet — same icon/label the primary bar would use
/// for this destination, plus a green selected treatment (mirroring
/// [_SingleDestinationNavBar]'s existing pill styling and AppColors.secondary
/// as the app's established selected/active color) when the destination it
/// represents is the one currently open.
class _MoreMenuTile extends StatelessWidget {
  const _MoreMenuTile({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final _NavEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tileColor: selected ? AppColors.secondary.withValues(alpha: 0.1) : null,
        leading: Icon(
          selected ? entry.selectedIcon : entry.icon,
          color: selected ? AppColors.secondary : AppColors.textSecondary,
        ),
        title: Text(
          entry.label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.secondary : AppColors.textPrimary,
          ),
        ),
        trailing: selected
            ? const Icon(Icons.check, color: AppColors.secondary, size: 18)
            : null,
        onTap: onTap,
      ),
    );
  }
}

/// Bottom navigation for a role with exactly one destination. Not a second
/// widget system — it mirrors NavigationBar's own selected-pill treatment
/// (using the same AppColors tokens the app's ThemeData actually resolves
/// NavigationBar's Material 3 colors from) for the one destination it's
/// given, which is always shown selected since there is nothing else to
/// select. This is not a placeholder/fake destination: it renders the real
/// single destination it's handed, just without going through a widget that
/// refuses to render fewer than two.
class _SingleDestinationNavBar extends StatelessWidget {
  const _SingleDestinationNavBar({
    required this.destination,
    required this.onTap,
  });

  final NavigationDestination destination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 80,
          width: double.infinity,
          child: InkWell(
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: IconTheme(
                    data: const IconThemeData(color: Colors.white, size: 22),
                    child: destination.selectedIcon ?? destination.icon,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  destination.label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

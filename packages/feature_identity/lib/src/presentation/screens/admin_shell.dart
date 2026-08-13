import 'package:flutter/material.dart';

import '../../domain/auth_session.dart';
import '../identity_scope.dart';
import '../widgets/admin_nav_entry.dart';

/// The authenticated admin app shell — a Home placeholder plus whatever
/// [additionalSections] the composition root (`apps/admin_web/lib/
/// main.dart`) supplies (Users, Pages, ...). This widget is deliberately
/// feature-agnostic: it renders a drawer + selected section body and
/// nothing else, so adding a new admin section never requires editing
/// `feature_identity` again — see `AdminNavEntry`'s doc comment for why.
class AdminShell extends StatefulWidget {
  const AdminShell({
    super.key,
    required this.session,
    this.additionalSections = const [],
  });

  final AuthSession session;
  final List<AdminNavEntry> additionalSections;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  /// Selection is tracked by label, not by [AdminNavEntry] object
  /// identity — the composition root typically rebuilds a fresh list of
  /// entries on every `AdminShell` rebuild, so comparing instances would
  /// silently lose the selection on any unrelated rebuild. `null` means
  /// Home. Labels are assumed unique across one shell's entries.
  String? _selectedLabel;

  @override
  Widget build(BuildContext context) {
    final scope = IdentityScope.of(context);
    final session = widget.session;
    final visibleSections = widget.additionalSections
        .where((s) => s.visible)
        .toList();
    AdminNavEntry? selectedEntry;
    for (final entry in visibleSections) {
      if (entry.label == _selectedLabel) {
        selectedEntry = entry;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(selectedEntry?.label ?? '2D Montessori Admin'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                '${session.displayName} · ${session.role.claimValue}',
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => scope.signOut(),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            DrawerHeader(child: Text(session.email)),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Home'),
              selected: _selectedLabel == null,
              onTap: () {
                setState(() => _selectedLabel = null);
                Navigator.of(context).pop();
              },
            ),
            for (final entry in visibleSections)
              ListTile(
                leading: Icon(entry.icon),
                title: Text(entry.label),
                selected: entry.label == _selectedLabel,
                onTap: () {
                  setState(() => _selectedLabel = entry.label);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
      body: selectedEntry == null
          ? _HomePlaceholder(session: session)
          : Builder(builder: selectedEntry.builder),
    );
  }
}

class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder({required this.session});

  final AuthSession session;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Signed in as ${session.email} (${session.role.claimValue}).',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

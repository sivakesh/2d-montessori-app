import 'package:core_contracts/core_contracts.dart';
import 'package:flutter/material.dart';

import '../../domain/auth_session.dart';
import '../identity_scope.dart';
import '../widgets/role_guarded_section.dart';
import 'user_management_screen.dart';

enum _AdminSection { home, users }

/// The authenticated admin app shell. Phase 1 Foundation scope only:
/// a Home placeholder and User Management — the rest of the CMS (pages,
/// media, publishing, ...) is later phases, per the milestone boundary
/// ("do not implement later CMS modules beyond the minimum interfaces or
/// contracts needed for the identity and security foundation").
class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.session});

  final AuthSession session;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  _AdminSection _section = _AdminSection.home;

  @override
  Widget build(BuildContext context) {
    final scope = IdentityScope.of(context);
    final session = widget.session;
    final canManageUsers = RolePermissionMatrix.hasFull(
      session.role,
      Capability.manageUsersAndRoles,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_titleFor(_section)),
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
              selected: _section == _AdminSection.home,
              onTap: () {
                setState(() => _section = _AdminSection.home);
                Navigator.of(context).pop();
              },
            ),
            // Hidden (not just disabled) for roles that can't use it — SRS
            // §3 gives Editor/Publisher no user-management capability at
            // all, so showing a permanently-disabled entry would be noise,
            // not a real affordance. RoleGuardedSection below still
            // re-checks this if the section is ever reachable another way.
            if (canManageUsers)
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: const Text('Users'),
                selected: _section == _AdminSection.users,
                onTap: () {
                  setState(() => _section = _AdminSection.users);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
      body: switch (_section) {
        _AdminSection.home => _HomePlaceholder(session: session),
        _AdminSection.users => RoleGuardedSection(
          role: session.role,
          capability: Capability.manageUsersAndRoles,
          builder: (_) => UserManagementScreen(
            currentUid: session.uid,
            actingRole: session.role,
          ),
        ),
      },
    );
  }

  String _titleFor(_AdminSection section) => switch (section) {
    _AdminSection.home => '2D Montessori Admin',
    _AdminSection.users => 'User management',
  };
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
          'Signed in as ${session.email} (${session.role.claimValue}).\n'
          'Content modules (Pages, Media, Publishing, ...) land in Phase 2.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

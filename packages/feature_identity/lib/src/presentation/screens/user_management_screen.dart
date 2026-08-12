import 'dart:async';

import 'package:core_contracts/core_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/user_account.dart';
import '../identity_scope.dart';

/// SRS AUTH-01/AUTH-05 admin foundations: create users, assign roles,
/// activate/deactivate access, trigger password resets. Only ever reached
/// through a `RoleGuardedSection(capability: Capability.manageUsersAndRoles)`
/// — see admin_shell.dart.
///
/// Deliberately has no `Scaffold`/`AppBar` of its own: it is always
/// embedded inside `AdminShell`'s single Scaffold, which already owns the
/// app bar (title, signed-in-as indicator, sign-out) and drawer. A nested
/// Scaffold here would render a second, redundant app bar.
class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({
    super.key,
    required this.currentUid,
    required this.actingRole,
  });

  final String currentUid;

  /// The signed-in user's own role — always `superAdmin` in practice
  /// since this screen is only reachable through a `RoleGuardedSection`,
  /// but threaded through explicitly rather than assumed so the use
  /// cases' own defense-in-depth check means something.
  final UserRole actingRole;

  @override
  Widget build(BuildContext context) {
    final scope = IdentityScope.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _showCreateUserDialog(context, actingRole),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('New user'),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<Result<List<UserAccount>>>(
            stream: scope.userAdminRepository.observeUsers(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final result = snapshot.data!;
              if (result.isFailure) {
                return Center(
                  child: Text(result.fold((_) => '', (f) => f.message)),
                );
              }
              final users = result.fold(
                (users) => users,
                (_) => const <UserAccount>[],
              );
              if (users.isEmpty) {
                return const Center(child: Text('No users yet.'));
              }

              final activeSuperAdminCount = users
                  .where((u) => u.role == UserRole.superAdmin && u.isActive)
                  .length;

              return ListView.separated(
                itemCount: users.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final user = users[index];
                  final isLastActiveSuperAdmin =
                      user.role == UserRole.superAdmin &&
                      user.isActive &&
                      activeSuperAdminCount <= 1;
                  return _UserRow(
                    user: user,
                    isSelf: user.uid == currentUid,
                    isLastActiveSuperAdmin: isLastActiveSuperAdmin,
                    actingRole: actingRole,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showCreateUserDialog(
    BuildContext context,
    UserRole actingRole,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CreateUserDialog(actingRole: actingRole),
    );
  }
}

class _UserRow extends StatefulWidget {
  const _UserRow({
    required this.user,
    required this.isSelf,
    required this.isLastActiveSuperAdmin,
    required this.actingRole,
  });

  final UserAccount user;
  final bool isSelf;
  final bool isLastActiveSuperAdmin;
  final UserRole actingRole;

  @override
  State<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends State<_UserRow> {
  bool _isBusy = false;
  String? _errorMessage;

  Future<void> _changeRole(UserRole role) async {
    if (role == widget.user.role) return;
    final scope = IdentityScope.of(context);
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    final result = await scope.setUserRole(
      actingRole: widget.actingRole,
      uid: widget.user.uid,
      role: role,
    );
    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _errorMessage = result.isFailure
          ? result.fold((_) => null, (f) => f.message)
          : null;
    });
  }

  Future<void> _toggleStatus() async {
    final scope = IdentityScope.of(context);
    final newStatus = widget.user.isActive
        ? AccountStatus.suspended
        : AccountStatus.active;
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    final result = await scope.setUserStatus(
      actingRole: widget.actingRole,
      uid: widget.user.uid,
      status: newStatus,
    );
    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _errorMessage = result.isFailure
          ? result.fold((_) => null, (f) => f.message)
          : null;
    });
  }

  Future<void> _resetPassword() async {
    final scope = IdentityScope.of(context);
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    final result = await scope.resetUserPassword(
      actingRole: widget.actingRole,
      uid: widget.user.uid,
    );
    if (!mounted) return;
    setState(() => _isBusy = false);
    result.fold(
      (success) {
        unawaited(
          _showTemporaryPasswordDialog(
            context,
            email: widget.user.email,
            temporaryPassword: success.temporaryPassword,
          ),
        );
      },
      (failure) {
        setState(() => _errorMessage = failure.message);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return ListTile(
      title: Text(user.displayName.isEmpty ? user.email : user.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(user.email),
          if (user.mustChangePassword)
            const Text('Must change password at next sign-in'),
          if (_errorMessage != null)
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      isThreeLine: true,
      trailing: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<UserRole>(
            value: user.role,
            onChanged: _isBusy || (widget.isLastActiveSuperAdmin)
                ? null
                : (role) => role == null ? null : _changeRole(role),
            items: UserRole.values
                .map(
                  (role) => DropdownMenuItem(
                    value: role,
                    child: Text(role.claimValue),
                  ),
                )
                .toList(growable: false),
          ),
          Chip(label: Text(user.status.claimValue)),
          IconButton(
            tooltip: user.isActive ? 'Suspend' : 'Reactivate',
            icon: Icon(
              user.isActive ? Icons.block : Icons.check_circle_outline,
            ),
            onPressed:
                _isBusy || (widget.isSelf && widget.isLastActiveSuperAdmin)
                ? null
                : _toggleStatus,
          ),
          IconButton(
            tooltip: 'Reset password',
            icon: const Icon(Icons.password),
            onPressed: _isBusy ? null : _resetPassword,
          ),
        ],
      ),
    );
  }
}

Future<void> _showTemporaryPasswordDialog(
  BuildContext context, {
  required String email,
  required String temporaryPassword,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Temporary password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Share this with $email through a trusted channel — it will not be shown again and no email is sent (Phase 1).',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  temporaryPassword,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Copy',
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: temporaryPassword)),
              ),
            ],
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog({required this.actingRole});

  final UserRole actingRole;

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  UserRole _role = UserRole.editor;
  bool _isBusy = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final scope = IdentityScope.of(context);
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    final result = await scope.createUser(
      actingRole: widget.actingRole,
      email: _emailController.text,
      displayName: _nameController.text,
      role: _role,
    );
    if (!mounted) return;
    setState(() => _isBusy = false);
    result.fold((success) {
      Navigator.of(context).pop();
      unawaited(
        _showTemporaryPasswordDialog(
          context,
          email: _emailController.text,
          temporaryPassword: success.temporaryPassword,
        ),
      );
    }, (failure) => setState(() => _errorMessage = failure.message));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New user'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_errorMessage != null) ...[
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Required.' : null,
            ),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (value) => (value == null || !value.contains('@'))
                  ? 'Enter a valid email address.'
                  : null,
            ),
            DropdownButtonFormField<UserRole>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: UserRole.values
                  .map(
                    (role) => DropdownMenuItem(
                      value: role,
                      child: Text(role.claimValue),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (role) => setState(() => _role = role ?? _role),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isBusy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isBusy ? null : _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

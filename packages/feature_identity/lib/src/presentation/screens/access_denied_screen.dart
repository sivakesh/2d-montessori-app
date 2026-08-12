import 'package:flutter/material.dart';

/// Shown when a signed-in, active user navigates to a section their role
/// does not permit (SRS §3 role matrix) — see `RoleGuardedSection` in
/// admin_shell.dart. Distinct from suspension/unprovisioning: this user's
/// account is fine, this specific action just isn't theirs to take.
class AccessDeniedScreen extends StatelessWidget {
  const AccessDeniedScreen({
    super.key,
    this.message = 'You do not have permission to view this page.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.block,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            const Text(
              'Access denied',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

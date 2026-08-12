import 'package:flutter/material.dart';

import '../identity_scope.dart';

/// SRS AUTH-05: shown instead of the admin app when the signed-in
/// account's status claim is `suspended`. The account is not signed out
/// automatically on arrival here (see AuthState docs) so the user gets an
/// explanation rather than an unexplained bounce to the login screen.
class SuspendedAccountScreen extends StatelessWidget {
  const SuspendedAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = IdentityScope.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              const Text(
                'Account suspended',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your access has been suspended by a Super Admin. Contact your Super Admin if you believe this is a mistake.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => scope.signOut(),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

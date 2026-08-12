import 'package:flutter/material.dart';

import '../identity_scope.dart';

/// Shown when a Firebase Auth account exists but has no valid `role`
/// custom claim — see `AuthStateUnprovisioned`. Only Cloud Functions ever
/// set claims (functions/src/auth), so a signed-in user landing here needs
/// a Super Admin to fix their account, not a client-side retry.
class UnprovisionedAccountScreen extends StatelessWidget {
  const UnprovisionedAccountScreen({super.key, required this.email});

  final String email;

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
              const Icon(Icons.person_off_outlined, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Account not set up',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                '$email is signed in but has not been assigned a role yet. Contact your Super Admin.',
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

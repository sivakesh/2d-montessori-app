import 'package:flutter/material.dart';

/// Shown in place of a School Settings screen's body when the current user
/// isn't Admin — the same "locked" treatment
/// AdminDashboardScreen's own `_AdminAccessRestrictedScreen` uses, shared
/// here between AdminSettingsScreen and SchoolSettingsScreen (both gate on
/// this identically) rather than duplicated between the two.
class AccessRestrictedView extends StatelessWidget {
  const AccessRestrictedView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'You do not have access to this section.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }
}

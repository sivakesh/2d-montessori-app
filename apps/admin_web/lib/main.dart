import 'package:firebase_adapters/firebase_adapters.dart';
import 'package:flutter/material.dart';

/// Admin/CMS entrypoint. Bootstraps against the local Firebase Emulator
/// Suite via [demoEmulatorFirebaseOptions] until the real dev/staging/prod
/// projects exist — see docs/architecture/environments.md. Auth gating
/// (feature_identity) lands in Phase 1.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await bootstrapFirebase(
    options: demoEmulatorFirebaseOptions,
    environment: AppEnvironment.dev,
  );

  runApp(const AdminWebApp());
}

class AdminWebApp extends StatelessWidget {
  const AdminWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '2D Montessori — Admin',
      debugShowCheckedModeBanner: false,
      home: const _ScaffoldPlaceholder(),
    );
  }
}

/// Phase 0 placeholder. Replaced by the Firebase-Auth-gated CMS shell
/// (feature_identity) in Phase 1/2.
class _ScaffoldPlaceholder extends StatelessWidget {
  const _ScaffoldPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '2D Montessori — admin_web scaffold\n'
            'Connected to the local Firebase Emulator Suite.\n'
            'Authentication and CMS screens land in Phase 1/2.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

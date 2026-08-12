import 'package:firebase_adapters/firebase_adapters.dart';
import 'package:flutter/material.dart';

/// Public site entrypoint. Today this always bootstraps against the local
/// Firebase Emulator Suite using the safe `demo-` project (see
/// [demoEmulatorFirebaseOptions]) — there is no real dev/staging/prod
/// Firebase project wired up yet (Phase 0). Once those projects exist,
/// Phase 1 replaces this with environment-selected entrypoints that load
/// the generated `firebase_options_<env>.dart` files; see
/// docs/architecture/environments.md for the exact steps.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await bootstrapFirebase(
    options: demoEmulatorFirebaseOptions,
    environment: AppEnvironment.dev,
  );

  runApp(const PublicWebApp());
}

class PublicWebApp extends StatelessWidget {
  const PublicWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '2D Montessori',
      debugShowCheckedModeBanner: false,
      home: const _ScaffoldPlaceholder(),
    );
  }
}

/// Phase 0 placeholder home screen. Replaced by real routing (PRD §3
/// Information Architecture) once feature_pages/feature_programs/etc. are
/// wired in during Phase 2/3.
class _ScaffoldPlaceholder extends StatelessWidget {
  const _ScaffoldPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '2D Montessori — public_web scaffold\n'
            'Connected to the local Firebase Emulator Suite.\n'
            'Public routes land in Phase 3.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

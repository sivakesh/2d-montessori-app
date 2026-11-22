import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/deploy_target.dart';
import 'core/config/firebase_environment.dart';
import 'core/config/firestore_emulator.dart';
import 'core/config/hosted_firebase_startup.dart';
import 'core/navigation/app_router.dart';
import 'core/theme/app_theme.dart';
import 'modules/auth/utils/recaptcha_web_view.dart';
import 'modules/parent/data/parent_fee_bill_refresh.dart';
import 'modules/public_website/url_strategy/public_url_strategy.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Clean web addresses (`/pages/about`); old `/#/...` links still work.
  configurePublicUrlStrategy();
  if (currentDeployTarget == DeployTarget.hosted) {
    // Hosted web build: the serving Firebase Hosting project's own
    // configuration, checked against EXPECTED_PROJECT_ID; an error with
    // Retry otherwise — never compiled options.
    await initializeHostedFirebase();
  } else {
    await Firebase.initializeApp(options: firebaseOptionsFor(currentDeployTarget));
  }
  // Development only: --dart-define=FIRESTORE_EMULATOR_HOST (never prod).
  connectFirestoreEmulatorIfConfigured(FirebaseFirestore.instance);
  registerRecaptchaView();
  // Parent-safe fee-bill copies follow Fee Bill Issuance (after commit).
  registerParentFeeBillRefresh();
  // ignore: avoid_print
  print('Firebase initialized');
  runApp(const ProviderScope(child: MontessoriApp()));
}

class MontessoriApp extends StatefulWidget {
  const MontessoriApp({super.key});

  @override
  State<MontessoriApp> createState() => _MontessoriAppState();
}

class _MontessoriAppState extends State<MontessoriApp> {
  // Flutter's Router (lib/core/navigation/app_router.dart): the browser's
  // Back and Forward follow the public website's pages. `/` is the public
  // website, open without signing in; the management app is entered at
  // `/app` (PublicRoutes.management), the same AuthGate that used to be the
  // home route, with its routes (ManagementRoutes) unchanged.
  late final RouterConfig<AppLocation> _router = createAppRouterConfig();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '2D Montessori',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: _router,
    );
  }
}

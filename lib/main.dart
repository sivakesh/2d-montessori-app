import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/deploy_target.dart';
import 'core/config/firebase_environment.dart';
import 'core/config/firestore_emulator.dart';
import 'core/theme/app_theme.dart';
import 'modules/auth/ui/auth_gate.dart';
import 'modules/auth/ui/login_screen.dart';
import 'modules/auth/ui/otp_screen.dart';
import 'modules/auth/ui/role_based_home.dart';
import 'modules/admin/ui/admin_dashboard_screen.dart';
import 'modules/admin/ui/admin_profile_form.dart';
import 'admin/screens/admin_session_logs_screen.dart';
import 'modules/auth/utils/recaptcha_web_view.dart';
import 'modules/public_website/public_routes.dart';
import 'modules/public_website/ui/public_announcement_page.dart';
import 'modules/public_website/ui/public_custom_page.dart';
import 'modules/public_website/ui/public_event_page.dart';
import 'modules/public_website/ui/public_gallery_page.dart';
import 'modules/public_website/ui/public_home_page.dart';
import 'modules/public_website/ui/public_section_page.dart';
import 'modules/public_website/url_strategy/public_url_strategy.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Clean web addresses (`/pages/about`); old `/#/...` links still work.
  configurePublicUrlStrategy();
  await Firebase.initializeApp(options: firebaseOptionsFor(currentDeployTarget));
  // Development only: --dart-define=FIRESTORE_EMULATOR_HOST (never prod).
  connectFirestoreEmulatorIfConfigured(FirebaseFirestore.instance);
  registerRecaptchaView();
  // ignore: avoid_print
  print('Firebase initialized');
  runApp(const ProviderScope(child: MontessoriApp()));
}

class MontessoriApp extends StatelessWidget {
  const MontessoriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '2D Montessori',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // `/` is the public website, open without signing in. The management
      // app is entered at `/app` (PublicRoutes.management), which is the
      // same AuthGate that used to be the home route.
      home: const PublicHomePage(),
      routes: {
        PublicRoutes.management: (context) => const AuthGate(),
        PublicRoutes.admissions: (context) => const PublicSectionPage(route: PublicRoutes.admissions),
        PublicRoutes.teacherTraining: (context) => const PublicSectionPage(route: PublicRoutes.teacherTraining),
        PublicRoutes.programs: (context) => const PublicSectionPage(route: PublicRoutes.programs),
        PublicRoutes.gallery: (context) => const PublicGalleryPage(),
        PublicRoutes.contact: (context) => const PublicSectionPage(route: PublicRoutes.contact),
        '/login': (context) => const LoginScreen(),
        '/dashboard': (context) => const DashboardRoute(),
        '/admin_dashboard': (context) => const AdminDashboardScreen(),
        '/admin_session_logs': (context) => const AdminSessionLogsScreen(),
        '/admin_profile_form': (context) => const AdminProfileForm(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/otp') {
          final arguments = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (_) =>
                OtpScreen(phoneNumber: arguments['phone'] as String),
          );
        }
        // Additional public pages: /pages/<slug>. The page itself shows only
        // published content and "page not found" otherwise — including for
        // any other address under /pages/ (e.g. /pages/a/b), whose empty
        // slug never matches a page.
        final name = settings.name ?? '';
        if (name.startsWith(PublicRoutes.customPagePrefix)) {
          final slug = PublicRoutes.slugFromRoute(name) ?? '';
          return MaterialPageRoute(
            settings: RouteSettings(name: slug.isEmpty ? name : PublicRoutes.customPage(slug)),
            builder: (_) => PublicCustomPage(slug: slug),
          );
        }
        // An event's details: /events/<id> (shareable). The page shows
        // "not available" for an unknown, withdrawn or past event,
        // including any other address under /events/.
        if (name.startsWith(PublicRoutes.eventPrefix)) {
          final id = PublicRoutes.eventIdFromRoute(name) ?? '';
          return MaterialPageRoute(
            settings: RouteSettings(name: id.isEmpty ? name : PublicRoutes.event(id)),
            builder: (_) => PublicEventPage(sourceId: id),
          );
        }
        // An announcement: /announcements/<id> (shareable), the same way.
        if (name.startsWith(PublicRoutes.announcementPrefix)) {
          final id = PublicRoutes.announcementIdFromRoute(name) ?? '';
          return MaterialPageRoute(
            settings: RouteSettings(name: id.isEmpty ? name : PublicRoutes.announcement(id)),
            builder: (_) => PublicAnnouncementPage(sourceId: id),
          );
        }
        return null;
      },
    );
  }
}

import 'package:core_contracts/core_contracts.dart';
import 'package:feature_identity/feature_identity.dart';
import 'package:feature_pages/feature_pages.dart';
import 'package:firebase_adapters/firebase_adapters.dart';
import 'package:flutter/material.dart';

/// Admin/CMS entrypoint. Bootstraps against the local Firebase Emulator
/// Suite via [demoEmulatorFirebaseOptions] until the real dev/staging/prod
/// projects exist — see docs/architecture/environments.md.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await bootstrapFirebase(
    options: demoEmulatorFirebaseOptions,
    useEmulators: true,
  );

  final authRepository = FirebaseAuthRepository(
    auth: FirebaseAuth.instance,
    firestore: FirebaseFirestore.instance,
    functions: FirebaseFunctions.instance,
  );
  final userAdminRepository = UserAdminFunctionsRepository(
    firestore: FirebaseFirestore.instance,
    functions: FirebaseFunctions.instance,
  );
  final pagesRepository = FirestorePagesRepository(
    firestore: FirebaseFirestore.instance,
    functions: FirebaseFunctions.instance,
  );
  final authController = AuthController(authRepository);

  runApp(
    AdminWebApp(
      authController: authController,
      authRepository: authRepository,
      userAdminRepository: userAdminRepository,
      pagesRepository: pagesRepository,
    ),
  );
}

class AdminWebApp extends StatelessWidget {
  const AdminWebApp({
    super.key,
    required this.authController,
    required this.authRepository,
    required this.userAdminRepository,
    required this.pagesRepository,
  });

  final AuthController authController;
  final AuthRepository authRepository;
  final UserAdminRepository userAdminRepository;
  final PagesRepository pagesRepository;

  /// The standard Firebase password-reset action link is
  /// `?mode=resetPassword&oobCode=...`. Detected here (once, at startup)
  /// from the browser URL rather than through a routing package — see
  /// docs/architecture/decisions.md "Admin routing" for why Phase 1
  /// Foundation doesn't introduce one yet.
  static String? _resetPasswordOobCodeFromUrl() {
    final params = Uri.base.queryParameters;
    if (params['mode'] != 'resetPassword') return null;
    return params['oobCode'];
  }

  /// Every admin nav section beyond Home, built here rather than inside
  /// `feature_identity`'s `AdminShell` — see `AdminNavEntry`'s doc
  /// comment for why `feature_identity` must never import a sibling
  /// feature package like `feature_pages` directly.
  List<AdminNavEntry> _adminSections(AuthSession session) => [
    AdminNavEntry(
      icon: Icons.people_outline,
      label: 'Users',
      visible: RolePermissionMatrix.hasFull(
        session.role,
        Capability.manageUsersAndRoles,
      ),
      builder: (_) => RoleGuardedSection(
        role: session.role,
        capability: Capability.manageUsersAndRoles,
        builder: (_) => UserManagementScreen(
          currentUid: session.uid,
          actingRole: session.role,
        ),
      ),
    ),
    AdminNavEntry(
      icon: Icons.description_outlined,
      label: 'Pages',
      // SRS §3: "Create/edit own drafts" is full for all three roles, so
      // every signed-in CMS user can see Pages — capability-gating within
      // it (who can edit which page, who can approve/publish) is handled
      // page-by-page inside feature_pages itself, not at the nav level.
      visible: true,
      builder: (_) => PagesSection(
        repository: pagesRepository,
        actingRole: session.role,
        actorId: session.uid,
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return IdentityScope(
      controller: authController,
      authRepository: authRepository,
      userAdminRepository: userAdminRepository,
      child: MaterialApp(
        title: '2D Montessori — Admin',
        debugShowCheckedModeBanner: false,
        home: Builder(
          builder: (context) {
            final oobCode = _resetPasswordOobCodeFromUrl();
            return oobCode != null
                ? ResetPasswordScreen(oobCode: oobCode)
                : AuthGate(adminSections: _adminSections);
          },
        ),
      ),
    );
  }
}

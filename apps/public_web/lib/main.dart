import 'package:feature_pages/feature_pages.dart';
import 'package:firebase_adapters/firebase_adapters.dart';
import 'package:flutter/material.dart';

import 'src/page_by_slug_screen.dart';
import 'src/url_strategy.dart';

/// Local/emulator entrypoint (`flutter run`/`flutter build web` with no
/// `-t` override default to this file) — always boots against the local
/// Firebase Emulator Suite using the safe `demo-` project (see
/// [demoEmulatorFirebaseOptions]). Environment-selected entrypoints
/// (`main_dev.dart`, and `main_staging.dart`/`main_prod.dart` once those
/// projects exist) call the same [bootstrapAndRunPublicWebApp] with a
/// real project's generated options and `useEmulators: false` instead of
/// duplicating the bootstrap/wiring logic — see `main_dev.dart`.
///
/// No authentication wiring lives here: public visitors never sign in
/// (SRS — "Public visitor" is not an account), so `feature_identity` is
/// deliberately not a dependency of this app.
Future<void> main() async {
  await bootstrapAndRunPublicWebApp(
    options: demoEmulatorFirebaseOptions,
    useEmulators: true,
  );
}

/// Bootstraps Firebase against [options] (the real backend when
/// [useEmulators] is `false`, or the local Emulator Suite when `true`)
/// and runs [PublicWebApp] — the one place this wiring is written, so
/// every entrypoint (`main.dart`, `main_dev.dart`, ...) stays a thin,
/// environment-specific one-liner instead of a second copy of this
/// repository construction that could drift out of sync.
Future<void> bootstrapAndRunPublicWebApp({
  required FirebaseOptions options,
  required bool useEmulators,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Real (`/slug`) URLs instead of Flutter's default `#/slug` hash
  // routes — SRS/PRD both require real, bookmarkable, crawlable public
  // routes; hash routes are a materially worse starting point for SEO
  // (see SeoHead's doc comment for the rest of this milestone's SEO
  // limitations, stated explicitly rather than assumed away).
  configureUrlStrategy();

  await bootstrapFirebase(options: options, useEmulators: useEmulators);

  final publicPagesRepository = FirestorePublicPagesRepository(
    firestore: FirebaseFirestore.instance,
  );

  runApp(PublicWebApp(publicPagesRepository: publicPagesRepository));
}

class PublicWebApp extends StatelessWidget {
  const PublicWebApp({super.key, required this.publicPagesRepository});

  final PublicPagesRepository publicPagesRepository;

  /// Single-level `/:slug` routing (PRD §3's route table for CMS-managed
  /// pages) via `Navigator`'s classic `onGenerateRoute` API — no routing
  /// package dependency, the same "not needed yet" call
  /// `docs/architecture/decisions.md`'s "Admin routing" made for
  /// `apps/admin_web`, extended here since `usePathUrlStrategy()` already
  /// gives real URLs without one. Anything other than a single flat
  /// segment (multiple `/`s) is treated as an invalid slug and falls
  /// through to [PageBySlugScreen]'s own not-found handling rather than
  /// a special route-parsing error path.
  Route<void> _onGenerateRoute(RouteSettings settings) {
    final name = settings.name ?? '/';
    if (name == '/' || name.isEmpty) {
      return MaterialPageRoute<void>(
        builder: (_) => _HomePlaceholder(repository: publicPagesRepository),
      );
    }
    final slug = name.startsWith('/') ? name.substring(1) : name;
    return MaterialPageRoute<void>(
      builder: (_) =>
          PageBySlugScreen(slug: slug, repository: publicPagesRepository),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '2D Montessori',
      debugShowCheckedModeBanner: false,
      onGenerateRoute: _onGenerateRoute,
    );
  }
}

/// Minimal placeholder for `/` — SRS WEB-01's full homepage (fixed
/// controlled sections: hero, featured Programs, Montessori Way
/// highlights, ...) is a distinct, larger milestone this one does not
/// build; `/` here exists only so real CMS pages have somewhere to link
/// from and this app has *a* landing route.
class _HomePlaceholder extends StatefulWidget {
  const _HomePlaceholder({required this.repository});

  final PublicPagesRepository repository;

  @override
  State<_HomePlaceholder> createState() => _HomePlaceholderState();
}

class _HomePlaceholderState extends State<_HomePlaceholder> {
  List<PublicPageView> _navPages = const [];

  @override
  void initState() {
    super.initState();
    widget.repository.listNavigationPages().then((result) {
      if (!mounted) return;
      result.fold((pages) => setState(() => _navPages = pages), (_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '2D Montessori',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              for (final page in _navPages)
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/${page.slug}'),
                  child: Text(
                    page.navigationLabel?.isNotEmpty == true
                        ? page.navigationLabel!
                        : page.title,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

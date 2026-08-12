/// Which of the three Firebase projects (dev / staging / prod) this build
/// targets. Selected at build time via `--dart-define=APP_ENV=dev|staging|prod`
/// — see config/env/README.md. Never hardcode a project ID; that always
/// comes from the matching `firebase_options_<env>.dart`, generated later
/// by `flutterfire configure` once the three projects exist.
enum AppEnvironment {
  dev,
  staging,
  prod;

  static AppEnvironment fromName(String name) => switch (name) {
    'dev' => AppEnvironment.dev,
    'staging' => AppEnvironment.staging,
    'prod' => AppEnvironment.prod,
    _ => throw ArgumentError.value(
      name,
      'name',
      'Expected dev, staging or prod',
    ),
  };

  /// True for any environment that should connect to the local Firebase
  /// Emulator Suite instead of a live project. Only `dev` does today;
  /// kept as a method (not a hardcoded check) so a future local-against-
  /// staging workflow doesn't require touching call sites.
  bool get usesEmulators => this == AppEnvironment.dev;
}

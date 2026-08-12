/// Which of the three Firebase projects (dev / staging / prod) this build
/// targets. Selected at build time via `--dart-define=APP_ENV=dev|staging|prod`
/// — see config/env/README.md. Never hardcode a project ID; that always
/// comes from the matching `firebase_options_<env>.dart`, generated later
/// by `flutterfire configure` once the three projects exist.
///
/// Deliberately independent of emulator usage — see [useEmulators] on
/// [bootstrapFirebase]. A `dev`-flavored build may run against either the
/// local Emulator Suite or the real dev project; which one is a separate,
/// explicit choice, not implied by the environment name.
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
}

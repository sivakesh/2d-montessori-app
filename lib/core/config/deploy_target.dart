/// Controls which Firebase *backend* the app connects to.
///
/// This is deliberately independent of [AppEnvironment] (see `app_env.dart`),
/// which controls application *behaviour* (e.g. the dev-only OTP bypass in
/// `getAuthService()`). `APP_ENV` must never be used to pick a Firebase
/// project, and `DEPLOY_TARGET` must never gate application behaviour.
enum DeployTarget { dev, prod }

const _deployTargetValue = String.fromEnvironment(
  'DEPLOY_TARGET',
  defaultValue: '',
);

/// Resolves a raw `--dart-define=DEPLOY_TARGET=...` value to a
/// [DeployTarget].
///
/// - Omitted / empty -> [DeployTarget.dev] (the existing DEV/UAT Firebase
///   project). This is a safety default: any command that predates
///   `DEPLOY_TARGET` (e.g. `flutter run --dart-define=APP_ENV=prod`) keeps
///   connecting to DEV/UAT exactly as it does today.
/// - `'dev'` -> [DeployTarget.dev].
/// - `'prod'` -> [DeployTarget.prod]. Only explicit `DEPLOY_TARGET=prod`
///   selects production.
/// - Anything else -> throws [StateError]. An unrecognised value must fail
///   the build/run rather than guess, and must never resolve to production.
DeployTarget resolveDeployTarget(String rawValue) {
  switch (rawValue) {
    case '':
    case 'dev':
      return DeployTarget.dev;
    case 'prod':
      return DeployTarget.prod;
    default:
      throw StateError(
        'Invalid DEPLOY_TARGET "$rawValue". Expected "dev", "prod", or '
        'omitted (defaults to dev/UAT). Refusing to start rather than guess '
        'which Firebase project to use.',
      );
  }
}

final DeployTarget currentDeployTarget = resolveDeployTarget(_deployTargetValue);

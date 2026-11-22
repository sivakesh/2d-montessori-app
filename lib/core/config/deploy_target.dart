import 'package:flutter/foundation.dart' show kIsWeb;

/// Controls which Firebase *backend* the app connects to.
///
/// This is deliberately independent of [AppEnvironment] (see `app_env.dart`),
/// which controls application *behaviour* (e.g. the dev-only OTP bypass in
/// `getAuthService()`). `APP_ENV` must never be used to pick a Firebase
/// project, and `DEPLOY_TARGET` must never gate application behaviour.
///
/// [hosted] (web only): the Firebase project that serves the page, read at
/// startup from Firebase Hosting's `/__/firebase/init.json` and checked
/// against the build's `EXPECTED_PROJECT_ID` (see `hosted_firebase_config.dart`).
/// It never uses the compiled DEV or production options.
enum DeployTarget { dev, prod, hosted }

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
/// - `'hosted'` -> [DeployTarget.hosted], on the web only ([isWeb]); on any
///   other platform it throws, so a native build can never enter hosted mode.
/// - Anything else -> throws [StateError]. An unrecognised value must fail
///   the build/run rather than guess, and must never resolve to production.
DeployTarget resolveDeployTarget(String rawValue, {bool isWeb = kIsWeb}) {
  switch (rawValue) {
    case '':
    case 'dev':
      return DeployTarget.dev;
    case 'prod':
      return DeployTarget.prod;
    case 'hosted':
      if (!isWeb) {
        throw StateError(
          'DEPLOY_TARGET "hosted" is for web builds served by Firebase Hosting '
          'only. Refusing to start on this platform.',
        );
      }
      return DeployTarget.hosted;
    default:
      throw StateError(
        'Invalid DEPLOY_TARGET "$rawValue". Expected "dev", "prod", "hosted", or '
        'omitted (defaults to dev/UAT). Refusing to start rather than guess '
        'which Firebase project to use.',
      );
  }
}

final DeployTarget currentDeployTarget = resolveDeployTarget(_deployTargetValue);

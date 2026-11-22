import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import 'hosted_config_error_app.dart';
import 'hosted_config_fetch.dart';
import 'hosted_firebase_config.dart';

/// The project a hosted build must be served by (`--dart-define`).
const expectedProjectIdFromBuild = String.fromEnvironment('EXPECTED_PROJECT_ID');

/// Firebase initialization for a hosted build ([DeployTarget.hosted]).
///
/// Loads the serving project's options and initializes the default app with
/// them. When that fails, [showError] shows why and completes when the user
/// asks to retry; then the whole attempt runs again. There is no fallback
/// to compiled options, and the default app is never initialized twice:
/// once it exists (even from an attempt that failed afterwards) nothing is
/// initialized again.
class HostedFirebaseStartup {
  HostedFirebaseStartup({required this.load, required this.initialize, required this.isInitialized, required this.showError});

  final Future<FirebaseOptions> Function() load;
  final Future<void> Function(FirebaseOptions options) initialize;
  final bool Function() isInitialized;
  final Future<void> Function(HostedConfigException error) showError;

  /// Completes once Firebase is initialized.
  Future<void> run() async {
    while (!isInitialized()) {
      try {
        final options = await load();
        await initialize(options);
        return;
      } on HostedConfigException catch (error) {
        await showError(error);
      } catch (_) {
        await showError(const HostedConfigException(HostedConfigProblem.unavailable, 'Firebase could not be started.'));
      }
    }
  }
}

/// [HostedFirebaseStartup] for this page: options from Firebase Hosting on
/// this page's origin, checked against [expectedProjectIdFromBuild]; errors
/// shown with [HostedConfigErrorApp] until Retry.
Future<void> initializeHostedFirebase() => HostedFirebaseStartup(
      load: () => loadHostedFirebaseOptions(page: Uri.base, expectedProjectId: expectedProjectIdFromBuild, fetch: fetchHostedConfig),
      initialize: (options) => Firebase.initializeApp(options: options),
      isInitialized: () => Firebase.apps.isNotEmpty,
      showError: (error) {
        final retry = Completer<void>();
        runApp(HostedConfigErrorApp(error: error, onRetry: retry.complete));
        return retry.future;
      },
    ).run();

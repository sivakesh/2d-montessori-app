import 'package:firebase_core/firebase_core.dart';

import '../../firebase_options.dart' as dev_options;
import '../../firebase_options_prod.dart' as prod_options;
import 'deploy_target.dart';

/// Resolves the [FirebaseOptions] to initialize Firebase with for a given
/// [DeployTarget]. A pure function of [target] (rather than reading
/// [currentDeployTarget] directly) so it is trivially unit-testable.
FirebaseOptions firebaseOptionsFor(DeployTarget target) {
  switch (target) {
    case DeployTarget.dev:
      return dev_options.DefaultFirebaseOptions.currentPlatform;
    case DeployTarget.prod:
      return prod_options.DefaultFirebaseOptionsProd.currentPlatform;
    case DeployTarget.hosted:
      // Hosted builds read the serving project's options at startup
      // (hosted_firebase_startup.dart). There is deliberately no compiled
      // fallback: a hosted build must never reach the DEV or production
      // project by accident.
      throw StateError(
        'DEPLOY_TARGET "hosted" has no compiled Firebase options; they are '
        'loaded from Firebase Hosting at startup.',
      );
  }
}

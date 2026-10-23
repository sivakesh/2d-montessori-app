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
  }
}

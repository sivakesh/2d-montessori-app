/// Public API of the Firebase adapters package. Feature `data/` layers and
/// app composition roots import this barrel only — this is the single
/// place in the workspace allowed to depend on the Firebase SDKs directly
/// (PRD §11.1). Re-exporting the full SDK packages (rather than a hand-
/// curated `show` list) keeps that choke point maintainable: feature data
/// layers get the full `User`, `FirebaseAuthException`, `IdTokenResult`,
/// `DocumentSnapshot`, `HttpsCallable`, etc. surface without this package
/// having to re-declare every type it forwards.
library;

export 'package:cloud_firestore/cloud_firestore.dart';
// `Result` is cloud_functions' streaming-callable result wrapper; hidden
// because it collides with core_contracts' domain `Result<T>` — every
// feature package depends on the latter far more often than on streaming
// callables (unused in Phase 1). Import cloud_functions directly (not
// through this barrel) in the rare case a feature needs streaming Result.
export 'package:cloud_functions/cloud_functions.dart' hide Result;
export 'package:firebase_auth/firebase_auth.dart';
export 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
export 'package:firebase_storage/firebase_storage.dart';

export 'src/app_environment.dart';
export 'src/demo_firebase_options.dart';
export 'src/emulator_config.dart';
export 'src/firebase_bootstrap.dart';

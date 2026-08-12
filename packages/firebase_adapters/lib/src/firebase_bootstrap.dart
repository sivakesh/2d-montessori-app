import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'app_environment.dart';
import 'emulator_config.dart';

/// Initializes Firebase for the given [environment] and, for `dev`, points
/// every SDK at the local Emulator Suite instead of a live backend. Apps
/// call this once from `main()` — see apps/public_web/lib/main.dart.
///
/// [options] must come from the caller (a generated `firebase_options_*.dart`
/// or, for local dev, [demoEmulatorFirebaseOptions]) so this package never
/// needs to know which project IDs exist.
Future<void> bootstrapFirebase({
  required FirebaseOptions options,
  required AppEnvironment environment,
}) async {
  await Firebase.initializeApp(options: options);

  if (!environment.usesEmulators) return;

  await FirebaseAuth.instance.useAuthEmulator(
    EmulatorConfig.host,
    EmulatorConfig.authPort,
  );
  FirebaseFirestore.instance.useFirestoreEmulator(
    EmulatorConfig.host,
    EmulatorConfig.firestorePort,
  );
  await FirebaseStorage.instance.useStorageEmulator(
    EmulatorConfig.host,
    EmulatorConfig.storagePort,
  );
  FirebaseFunctions.instance.useFunctionsEmulator(
    EmulatorConfig.host,
    EmulatorConfig.functionsPort,
  );
}

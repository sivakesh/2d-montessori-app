import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'emulator_config.dart';

/// Initializes Firebase and, when [useEmulators] is true, points every SDK
/// at the local Emulator Suite instead of a live backend. Apps call this
/// once from `main()` — see apps/admin_web/lib/main.dart.
///
/// [useEmulators] is intentionally a separate parameter from
/// [AppEnvironment] rather than derived from it: which Firebase *project*
/// a build targets (dev/staging/prod, chosen by [options]) and whether
/// that build talks to the emulators or the real backend are independent
/// choices. Today only one combination is wired up in the apps (`dev` +
/// emulators, via `demoEmulatorFirebaseOptions`), but the signature does
/// not bake that assumption in.
Future<void> bootstrapFirebase({
  required FirebaseOptions options,
  required bool useEmulators,
}) async {
  await Firebase.initializeApp(options: options);

  if (!useEmulators) return;

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

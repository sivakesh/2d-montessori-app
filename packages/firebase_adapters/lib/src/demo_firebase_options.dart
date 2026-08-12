import 'package:firebase_core/firebase_core.dart';

/// Firebase's own reserved convention for emulator-only "offline" projects:
/// any project ID prefixed `demo-` is treated by the Firebase Emulator
/// Suite as a local-only project and never resolves to real infrastructure,
/// so these values are safe to commit — they are not credentials and
/// cannot authenticate against any live Firebase project. This is what lets
/// `flutter run -d chrome` work against the emulators today, before the
/// real dev/staging/prod projects exist (see docs/architecture/environments.md).
///
/// Do NOT reuse these values for staging or production. Those load real,
/// generated `firebase_options_<env>.dart` files (gitignored — see
/// lib/firebase_options_staging.dart.template in each app) once the actual
/// Firebase projects have been created.
const FirebaseOptions demoEmulatorFirebaseOptions = FirebaseOptions(
  apiKey: 'demo-api-key',
  appId: '1:000000000000:web:0000000000000000000000',
  messagingSenderId: '000000000000',
  projectId: 'demo-montessori-2d',
  authDomain: 'demo-montessori-2d.firebaseapp.com',
  storageBucket: 'demo-montessori-2d.appspot.com',
);

/// Public API of the Firebase adapters package. Feature `data/` layers and
/// app composition roots import this barrel only.
library;

export 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore;
export 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth, User;
export 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

export 'src/app_environment.dart';
export 'src/demo_firebase_options.dart';
export 'src/emulator_config.dart';
export 'src/firebase_bootstrap.dart';

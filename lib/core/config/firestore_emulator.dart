import 'package:cloud_firestore/cloud_firestore.dart';

import 'deploy_target.dart';

/// Local development against the Firestore emulator, opted into with
/// `--dart-define=FIRESTORE_EMULATOR_HOST=127.0.0.1:8086`.
///
/// Only a loopback host is accepted, and never together with
/// `DEPLOY_TARGET=prod`: an emulator setting can't point the app at
/// anything but this machine. Without it, nothing changes.
///
/// Website form submissions then go to the emulator too, like every other
/// write.
class FirestoreEmulatorConfig {
  const FirestoreEmulatorConfig(this.host, this.port);

  final String host;
  final int port;

  /// [raw] as `host:port`; null when empty. Throws for anything that
  /// isn't a loopback address with a valid port, or for production.
  static FirestoreEmulatorConfig? parse(String raw, {DeployTarget target = DeployTarget.dev}) {
    if (raw.trim().isEmpty) return null;
    final match = RegExp(r'^(localhost|127\.0\.0\.1):(\d{2,5})$').firstMatch(raw.trim());
    final port = match == null ? null : int.parse(match.group(2)!);
    if (match == null || port! < 1 || port > 65535) {
      throw StateError('Invalid FIRESTORE_EMULATOR_HOST "$raw". Expected localhost:<port> or 127.0.0.1:<port>.');
    }
    if (target == DeployTarget.prod) {
      throw StateError('FIRESTORE_EMULATOR_HOST can’t be used with DEPLOY_TARGET=prod.');
    }
    return FirestoreEmulatorConfig(match.group(1)!, port);
  }
}

const _rawHost = String.fromEnvironment('FIRESTORE_EMULATOR_HOST');

/// This build's emulator setting, or null (the normal case).
final FirestoreEmulatorConfig? firestoreEmulator = FirestoreEmulatorConfig.parse(_rawHost, target: currentDeployTarget);

/// Points [firestore] at the emulator when one is configured. Call once,
/// right after Firebase is initialised and before any read or write.
void connectFirestoreEmulatorIfConfigured(FirebaseFirestore firestore) {
  final emulator = firestoreEmulator;
  if (emulator != null) firestore.useFirestoreEmulator(emulator.host, emulator.port);
}

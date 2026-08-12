/// Local Firebase Emulator Suite ports. Must stay in sync with the `emulators`
/// block in /firebase.json — see docs/architecture/environments.md.
abstract final class EmulatorConfig {
  static const String host = 'localhost';
  static const int authPort = 9099;
  static const int firestorePort = 8080;
  static const int storagePort = 9199;
  static const int functionsPort = 5001;
}

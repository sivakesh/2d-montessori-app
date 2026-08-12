import 'package:firebase_adapters/firebase_adapters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppEnvironment', () {
    test('parses known names', () {
      expect(AppEnvironment.fromName('dev'), AppEnvironment.dev);
      expect(AppEnvironment.fromName('staging'), AppEnvironment.staging);
      expect(AppEnvironment.fromName('prod'), AppEnvironment.prod);
    });

    test('rejects unknown names', () {
      expect(() => AppEnvironment.fromName('production'), throwsArgumentError);
    });

    test('only dev uses emulators', () {
      expect(AppEnvironment.dev.usesEmulators, isTrue);
      expect(AppEnvironment.staging.usesEmulators, isFalse);
      expect(AppEnvironment.prod.usesEmulators, isFalse);
    });
  });

  test('demo emulator options use the reserved demo- project prefix', () {
    expect(demoEmulatorFirebaseOptions.projectId, startsWith('demo-'));
  });
}

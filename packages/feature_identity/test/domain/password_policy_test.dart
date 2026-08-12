import 'package:feature_identity/feature_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PasswordPolicy', () {
    test('rejects passwords shorter than the minimum length', () {
      expect(PasswordPolicy.isValid('a1234'), isFalse);
    });

    test('rejects passwords without a letter', () {
      expect(PasswordPolicy.isValid('12345678'), isFalse);
    });

    test('rejects passwords without a digit', () {
      expect(PasswordPolicy.isValid('abcdefgh'), isFalse);
    });

    test('accepts a password meeting length + letter + digit', () {
      expect(PasswordPolicy.isValid('abcd1234'), isTrue);
    });

    test('validate reports every violation, not just the first', () {
      expect(
        PasswordPolicy.validate('abc'),
        hasLength(2),
      ); // too short + no digit
    });

    test('validate returns empty for a compliant password', () {
      expect(PasswordPolicy.validate('Sunshine42'), isEmpty);
    });
  });
}

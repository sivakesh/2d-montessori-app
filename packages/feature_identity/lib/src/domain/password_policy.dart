/// Minimum password policy for Phase 1. The SRS does not specify password
/// complexity rules explicitly (AUTH-02 only says "Firebase Authentication"
/// handles passwords) — this is a reasonable baseline (length only, no
/// invented complexity rules) pending stakeholder confirmation; see
/// docs/architecture/decisions.md "Open Phase 1 assumptions".
///
/// functions/src/auth/passwordPolicy.ts enforces the same minimum
/// server-side — the two are not code-shared (Dart vs TypeScript) but
/// must be kept numerically in sync.
abstract final class PasswordPolicy {
  static const int minLength = 8;

  /// Returns a list of human-readable violations, empty if [password]
  /// satisfies the policy.
  static List<String> validate(String password) {
    final violations = <String>[];
    if (password.length < minLength) {
      violations.add('Must be at least $minLength characters long.');
    }
    if (!password.contains(RegExp('[A-Za-z]'))) {
      violations.add('Must contain at least one letter.');
    }
    if (!password.contains(RegExp('[0-9]'))) {
      violations.add('Must contain at least one number.');
    }
    return violations;
  }

  static bool isValid(String password) => validate(password).isEmpty;
}

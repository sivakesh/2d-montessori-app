/// Minimum password policy for Phase 1: at least [minLength] characters,
/// one letter and one digit. The SRS does not specify password complexity
/// rules explicitly (AUTH-02 only says "Firebase Authentication" handles
/// passwords) — this is a reasonable baseline pending stakeholder
/// confirmation, retained as-is at the Foundation Verification checkpoint
/// (see docs/architecture/decisions.md "Open Phase 1 assumptions").
///
/// This class is the single place the client-side policy is defined —
/// every screen that collects a new password (login, forgot/reset,
/// forced first-login change, and any future My Profile change) calls
/// [validate] or [isValid] rather than re-implementing checks, so
/// strengthening the policy later (e.g. adding an uppercase or special-
/// character requirement) means editing only this file.
///
/// functions/src/auth/validators.ts's `isPasswordPolicyCompliant` enforces
/// the same minimum server-side, the actual authority — see that file's
/// doc comment. The two are not code-shared (Dart vs TypeScript) and must
/// be kept numerically in sync by hand.
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

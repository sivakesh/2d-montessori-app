/**
 * Server-side input validation for every callable in this module. The
 * client (feature_identity's use cases) validates the same shapes for UX,
 * but nothing here trusts that — every value is re-validated from
 * `request.data` before touching Auth/Firestore.
 */
import { HttpsError } from 'firebase-functions/v2/https';
import { randomInt } from 'node:crypto';

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export const ROLES = ['editor', 'publisher', 'superAdmin'] as const;
export type Role = (typeof ROLES)[number];

export const STATUSES = ['active', 'suspended'] as const;
export type Status = (typeof STATUSES)[number];

export function validateEmail(value: unknown): string {
  if (typeof value !== 'string' || !EMAIL_REGEX.test(value.trim())) {
    throw new HttpsError('invalid-argument', 'A valid email address is required.');
  }
  return value.trim().toLowerCase();
}

export function validateDisplayName(value: unknown): string {
  const trimmed = typeof value === 'string' ? value.trim() : '';
  if (trimmed.length === 0 || trimmed.length > 80) {
    throw new HttpsError('invalid-argument', 'A name between 1 and 80 characters is required.');
  }
  return trimmed;
}

export function validateRole(value: unknown): Role {
  if (typeof value !== 'string' || !(ROLES as readonly string[]).includes(value)) {
    throw new HttpsError('invalid-argument', `role must be one of: ${ROLES.join(', ')}.`);
  }
  return value as Role;
}

export function validateStatus(value: unknown): Status {
  if (typeof value !== 'string' || !(STATUSES as readonly string[]).includes(value)) {
    throw new HttpsError('invalid-argument', `status must be one of: ${STATUSES.join(', ')}.`);
  }
  return value as Status;
}

export function validateUid(value: unknown): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'A target user id is required.');
  }
  return value;
}

/**
 * Minimum password policy — the server-side authority (the client's copy
 * in packages/feature_identity/lib/src/domain/password_policy.dart is a
 * UX convenience; this is what actually gates password changes, since
 * every callable re-validates regardless of what the client already
 * checked). Retained as-is at the Foundation Verification checkpoint.
 * `MIN_PASSWORD_LENGTH` is the single place this policy is configured on
 * the server side — strengthen it (or add character-class checks) here
 * only; must stay numerically in sync with the Dart copy by hand (not
 * code-shared — Dart vs TypeScript).
 */
const MIN_PASSWORD_LENGTH = 8;

export function isPasswordPolicyCompliant(password: string): boolean {
  return password.length >= MIN_PASSWORD_LENGTH && /[A-Za-z]/.test(password) && /[0-9]/.test(password);
}

// Excludes visually ambiguous characters (0/O, 1/l/I).
const TEMP_PASSWORD_LETTERS = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz';
const TEMP_PASSWORD_DIGITS = '23456789';
const TEMP_PASSWORD_CHARSET = TEMP_PASSWORD_LETTERS + TEMP_PASSWORD_DIGITS;
const TEMP_PASSWORD_LENGTH = 12;

/**
 * Cryptographically random, guaranteed by construction to satisfy
 * [isPasswordPolicyCompliant]: the first two characters are drawn one
 * each from the letter and digit pools (then the whole string is
 * shuffled), so length and "contains a letter and a digit" hold on every
 * call — not just with high probability, which a naive draw from the
 * combined charset would only give you. Returned once to the caller (SRS
 * AUTH-01/AUTH-05 — no email is sent in Phase 1) and never logged or
 * persisted in plaintext.
 */
export function generateTemporaryPassword(): string {
  const chars = [
    TEMP_PASSWORD_LETTERS[randomInt(TEMP_PASSWORD_LETTERS.length)],
    TEMP_PASSWORD_DIGITS[randomInt(TEMP_PASSWORD_DIGITS.length)],
  ];
  while (chars.length < TEMP_PASSWORD_LENGTH) {
    chars.push(TEMP_PASSWORD_CHARSET[randomInt(TEMP_PASSWORD_CHARSET.length)]);
  }
  for (let i = chars.length - 1; i > 0; i--) {
    const j = randomInt(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join('');
}

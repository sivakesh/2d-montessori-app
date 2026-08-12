import { HttpsError } from 'firebase-functions/v2/https';

import {
  generateTemporaryPassword,
  isPasswordPolicyCompliant,
  validateDisplayName,
  validateEmail,
  validateRole,
  validateStatus,
  validateUid,
} from '../src/auth/validators';

describe('validateEmail', () => {
  it('accepts and normalizes a valid email', () => {
    expect(validateEmail(' Someone@Example.com ')).toBe('someone@example.com');
  });

  it.each([undefined, null, 123, '', 'not-an-email', 'missing-domain@'])('rejects %p', (value) => {
    expect(() => validateEmail(value)).toThrow(HttpsError);
  });
});

describe('validateDisplayName', () => {
  it('trims and accepts a valid name', () => {
    expect(validateDisplayName('  Jane Doe  ')).toBe('Jane Doe');
  });

  it('rejects empty names', () => {
    expect(() => validateDisplayName('   ')).toThrow(HttpsError);
  });

  it('rejects names over 80 characters', () => {
    expect(() => validateDisplayName('a'.repeat(81))).toThrow(HttpsError);
  });
});

describe('validateRole', () => {
  it.each(['editor', 'publisher', 'superAdmin'])('accepts %p', (role) => {
    expect(validateRole(role)).toBe(role);
  });

  it.each([undefined, 'owner', 'Editor', 123])('rejects %p', (value) => {
    expect(() => validateRole(value)).toThrow(HttpsError);
  });
});

describe('validateStatus', () => {
  it.each(['active', 'suspended'])('accepts %p', (status) => {
    expect(validateStatus(status)).toBe(status);
  });

  it.each([undefined, 'disabled', 1])('rejects %p', (value) => {
    expect(() => validateStatus(value)).toThrow(HttpsError);
  });
});

describe('validateUid', () => {
  it('accepts a non-empty string', () => {
    expect(validateUid('abc123')).toBe('abc123');
  });

  it.each([undefined, '', '   '])('rejects %p', (value) => {
    expect(() => validateUid(value)).toThrow(HttpsError);
  });
});

describe('generateTemporaryPassword', () => {
  it('always satisfies the password policy by construction', () => {
    for (let i = 0; i < 50; i++) {
      expect(isPasswordPolicyCompliant(generateTemporaryPassword())).toBe(true);
    }
  });

  it('generates different passwords across calls', () => {
    const passwords = new Set(Array.from({ length: 20 }, () => generateTemporaryPassword()));
    expect(passwords.size).toBeGreaterThan(1);
  });
});

describe('isPasswordPolicyCompliant', () => {
  it.each(['short1', 'nodigitshere', '12345678', 'goodpass1'])('%s', (password) => {
    const expected = password === 'goodpass1';
    expect(isPasswordPolicyCompliant(password)).toBe(expected);
  });
});

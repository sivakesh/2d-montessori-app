import { HttpsError } from 'firebase-functions/v2/https';

import {
  validateAction,
  validateContentId,
  validateContentType,
  validateOptionalComment,
  validateOptionalScheduledAt,
  validateTitle,
} from '../src/publishing/validators';

describe('validateContentId', () => {
  it('accepts a non-empty string', () => {
    expect(validateContentId('abc123')).toBe('abc123');
  });

  it.each([undefined, '', '   ', 42])('rejects %p', (value) => {
    expect(() => validateContentId(value)).toThrow(HttpsError);
  });
});

describe('validateContentType / validateTitle', () => {
  it('trims and accepts valid values', () => {
    expect(validateContentType('  page  ')).toBe('page');
    expect(validateTitle('  Home  ')).toBe('Home');
  });

  it('rejects empty or over-length values', () => {
    expect(() => validateContentType('')).toThrow(HttpsError);
    expect(() => validateContentType('a'.repeat(41))).toThrow(HttpsError);
    expect(() => validateTitle('')).toThrow(HttpsError);
    expect(() => validateTitle('a'.repeat(201))).toThrow(HttpsError);
  });
});

describe('validateAction', () => {
  it('accepts every declared action', () => {
    expect(validateAction('submitForReview')).toBe('submitForReview');
    expect(validateAction('restore')).toBe('restore');
  });

  it.each([undefined, 'delete', 42])('rejects %p', (value) => {
    expect(() => validateAction(value)).toThrow(HttpsError);
  });
});

describe('validateOptionalComment', () => {
  it('returns undefined when absent', () => {
    expect(validateOptionalComment(undefined)).toBeUndefined();
    expect(validateOptionalComment(null)).toBeUndefined();
  });

  it('trims and returns a provided comment', () => {
    expect(validateOptionalComment('  needs work  ')).toBe('needs work');
  });

  it('rejects a blank comment when provided', () => {
    expect(() => validateOptionalComment('   ')).toThrow(HttpsError);
    expect(() => validateOptionalComment(42)).toThrow(HttpsError);
  });
});

describe('validateOptionalScheduledAt', () => {
  it('returns undefined when absent', () => {
    expect(validateOptionalScheduledAt(undefined)).toBeUndefined();
  });

  it('parses a valid ISO date string', () => {
    const result = validateOptionalScheduledAt('2030-01-01T00:00:00.000Z');
    expect(result).toBeInstanceOf(Date);
    expect(result?.getUTCFullYear()).toBe(2030);
  });

  it('rejects a non-date string or non-string value', () => {
    expect(() => validateOptionalScheduledAt('not-a-date')).toThrow(HttpsError);
    expect(() => validateOptionalScheduledAt(12345)).toThrow(HttpsError);
  });
});

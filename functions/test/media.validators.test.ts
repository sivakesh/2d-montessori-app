import { HttpsError } from 'firebase-functions/v2/https';

import { approvedMediaTypeFor, validateAltText, validateMediaId, validateOptionalDescription, validateTitle } from '../src/media/validators';

function expectHttpsError(fn: () => unknown, code: string): void {
  try {
    fn();
  } catch (error) {
    expect(error).toBeInstanceOf(HttpsError);
    expect((error as HttpsError).code).toBe(code);
    return;
  }
  throw new Error('Expected an HttpsError to be thrown, but the function returned normally.');
}

describe('approvedMediaTypeFor', () => {
  it('recognizes every approved image/video/document MIME type with its size limit', () => {
    expect(approvedMediaTypeFor('image/png')).toMatchObject({ category: 'image', maxSizeBytes: 10 * 1024 * 1024 });
    expect(approvedMediaTypeFor('video/mp4')).toMatchObject({ category: 'video', maxSizeBytes: 200 * 1024 * 1024 });
    expect(approvedMediaTypeFor('application/pdf')).toMatchObject({ category: 'document', maxSizeBytes: 25 * 1024 * 1024 });
  });

  it('returns undefined for an unapproved MIME type', () => {
    expect(approvedMediaTypeFor('application/x-msdownload')).toBeUndefined();
    expect(approvedMediaTypeFor('')).toBeUndefined();
  });
});

describe('validateMediaId', () => {
  it('accepts a well-formed id', () => {
    expect(validateMediaId('abc-123_XYZ')).toBe('abc-123_XYZ');
  });

  it('rejects a non-string, empty, or path-traversal-shaped id', () => {
    expectHttpsError(() => validateMediaId(undefined), 'invalid-argument');
    expectHttpsError(() => validateMediaId(''), 'invalid-argument');
    expectHttpsError(() => validateMediaId('../etc/passwd'), 'invalid-argument');
    expectHttpsError(() => validateMediaId('has spaces'), 'invalid-argument');
  });
});

describe('validateTitle', () => {
  it('trims and accepts a non-empty title', () => {
    expect(validateTitle('  Logo  ')).toBe('Logo');
  });

  it('rejects a blank or missing title', () => {
    expectHttpsError(() => validateTitle(''), 'invalid-argument');
    expectHttpsError(() => validateTitle('   '), 'invalid-argument');
    expectHttpsError(() => validateTitle(undefined), 'invalid-argument');
  });

  it('rejects a title over 200 characters', () => {
    expectHttpsError(() => validateTitle('a'.repeat(201)), 'invalid-argument');
  });
});

describe('validateAltText', () => {
  it('trims and accepts non-empty alt text', () => {
    expect(validateAltText('  A description  ')).toBe('A description');
  });

  it('rejects blank or missing alt text (SRS accessible alt text is required)', () => {
    expectHttpsError(() => validateAltText(''), 'invalid-argument');
    expectHttpsError(() => validateAltText(undefined), 'invalid-argument');
  });
});

describe('validateOptionalDescription', () => {
  it('defaults to an empty string when omitted', () => {
    expect(validateOptionalDescription(undefined)).toBe('');
    expect(validateOptionalDescription(null)).toBe('');
  });

  it('trims a provided description', () => {
    expect(validateOptionalDescription('  hello  ')).toBe('hello');
  });

  it('rejects a non-string value', () => {
    expectHttpsError(() => validateOptionalDescription(42), 'invalid-argument');
  });
});

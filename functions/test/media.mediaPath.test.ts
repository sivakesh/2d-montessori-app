import { mediaIdFromStoragePath, originalStoragePath, publicVariantStoragePath } from '../src/media/mediaPath';

describe('originalStoragePath / publicVariantStoragePath', () => {
  it('builds the expected private and public paths', () => {
    expect(originalStoragePath('m1', 'png')).toBe('private/media/m1/original.png');
    expect(publicVariantStoragePath('m1', 'w640.webp')).toBe('public/media/m1/w640.webp');
  });
});

describe('mediaIdFromStoragePath', () => {
  it('extracts the mediaId from a real original storage path', () => {
    expect(mediaIdFromStoragePath('private/media/m1/original.png')).toBe('m1');
  });

  it('returns undefined for a plain external URL with no storagePath', () => {
    expect(mediaIdFromStoragePath(undefined)).toBeUndefined();
    expect(mediaIdFromStoragePath(null)).toBeUndefined();
  });

  it('returns undefined for a path outside the private/media/ convention', () => {
    expect(mediaIdFromStoragePath('public/media/m1/w640.webp')).toBeUndefined();
    expect(mediaIdFromStoragePath('private/other/m1/original.png')).toBeUndefined();
  });
});

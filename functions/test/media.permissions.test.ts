import { canManageAllMedia, canManageMediaAsset } from '../src/media/permissions';

describe('canManageAllMedia', () => {
  it('is true for Publisher and Super Admin, false for Editor', () => {
    expect(canManageAllMedia('publisher')).toBe(true);
    expect(canManageAllMedia('superAdmin')).toBe(true);
    expect(canManageAllMedia('editor')).toBe(false);
  });
});

describe('canManageMediaAsset', () => {
  it('allows an Editor to manage their own upload', () => {
    expect(canManageMediaAsset('editor', 'u1', 'u1')).toBe(true);
  });

  it('denies an Editor managing someone else’s upload', () => {
    expect(canManageMediaAsset('editor', 'u1', 'u2')).toBe(false);
  });

  it('allows a Publisher or Super Admin to manage any upload, including one they do not own', () => {
    expect(canManageMediaAsset('publisher', 'u1', 'u2')).toBe(true);
    expect(canManageMediaAsset('superAdmin', 'u1', 'u2')).toBe(true);
  });
});

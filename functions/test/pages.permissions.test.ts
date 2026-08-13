import { canEditAllContent } from '../src/pages/permissions';

describe('canEditAllContent', () => {
  it('is false for editor (owner-only editing)', () => {
    expect(canEditAllContent('editor')).toBe(false);
  });

  it('is true for publisher and superAdmin', () => {
    expect(canEditAllContent('publisher')).toBe(true);
    expect(canEditAllContent('superAdmin')).toBe(true);
  });
});

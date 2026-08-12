import { hasFullCapability, isUserRole } from '../src/publishing/capabilities';

describe('hasFullCapability', () => {
  it('submitForReview: full for every role', () => {
    expect(hasFullCapability('editor', 'submitForReview')).toBe(true);
    expect(hasFullCapability('publisher', 'submitForReview')).toBe(true);
    expect(hasFullCapability('superAdmin', 'submitForReview')).toBe(true);
  });

  it('approveRejectPublish: not Editor, full for Publisher/Super Admin', () => {
    expect(hasFullCapability('editor', 'approveRejectPublish')).toBe(false);
    expect(hasFullCapability('publisher', 'approveRejectPublish')).toBe(true);
    expect(hasFullCapability('superAdmin', 'approveRejectPublish')).toBe(true);
  });

  it('schedulePublishing: not Editor ("suggest only" is not full access), full for Publisher/Super Admin', () => {
    expect(hasFullCapability('editor', 'schedulePublishing')).toBe(false);
    expect(hasFullCapability('publisher', 'schedulePublishing')).toBe(true);
    expect(hasFullCapability('superAdmin', 'schedulePublishing')).toBe(true);
  });

  it('returns false for an undefined role', () => {
    expect(hasFullCapability(undefined, 'submitForReview')).toBe(false);
  });
});

describe('isUserRole', () => {
  it.each(['editor', 'publisher', 'superAdmin'])('accepts %s', (role) => {
    expect(isUserRole(role)).toBe(true);
  });

  it.each([undefined, 'owner', 'Editor', 42])('rejects %p', (value) => {
    expect(isUserRole(value)).toBe(false);
  });
});

import {
  isPublishingAction,
  isPublishingStatus,
  PUBLISHING_ACTIONS,
  PUBLISHING_STATUSES,
  resolveTransition,
} from '../src/publishing/stateMachine';

describe('resolveTransition', () => {
  it.each([
    ['draft', 'submitForReview', 'inReview'],
    ['draft', 'archive', 'archived'],
    ['inReview', 'reject', 'draft'],
    ['inReview', 'approve', 'approved'],
    ['inReview', 'archive', 'archived'],
    ['approved', 'reject', 'draft'],
    ['approved', 'schedule', 'scheduled'],
    ['approved', 'publish', 'published'],
    ['approved', 'archive', 'archived'],
    ['scheduled', 'unschedule', 'approved'],
    ['scheduled', 'publish', 'published'],
    ['scheduled', 'archive', 'archived'],
    ['published', 'unpublish', 'archived'],
    ['archived', 'restore', 'draft'],
  ] as const)('%s --%s--> %s', (from, action, to) => {
    expect(resolveTransition(from, action)?.to).toBe(to);
  });

  it('returns undefined for an edge that does not exist', () => {
    expect(resolveTransition('draft', 'publish')).toBeUndefined();
    expect(resolveTransition('published', 'submitForReview')).toBeUndefined();
    expect(resolveTransition('archived', 'publish')).toBeUndefined();
  });

  it('marks reject as requiring a comment', () => {
    expect(resolveTransition('inReview', 'reject')?.requiresComment).toBe(true);
    expect(resolveTransition('approved', 'reject')?.requiresComment).toBe(true);
  });

  it('marks schedule as requiring a future scheduledAt', () => {
    expect(resolveTransition('approved', 'schedule')?.requiresFutureScheduledAt).toBe(true);
  });

  it('does not require a comment or schedule for other actions', () => {
    expect(resolveTransition('draft', 'submitForReview')?.requiresComment).toBeUndefined();
    expect(resolveTransition('approved', 'publish')?.requiresFutureScheduledAt).toBeUndefined();
  });

  it('every status has at least one outgoing edge except the terminal-in-practice ones', () => {
    // draft, inReview, approved, scheduled, published, archived all have
    // at least one outgoing edge in this workflow (archived -> restore).
    for (const status of PUBLISHING_STATUSES) {
      const hasOutgoingEdge = PUBLISHING_ACTIONS.some((action) => resolveTransition(status, action) !== undefined);
      expect(hasOutgoingEdge).toBe(true);
    }
  });
});

describe('isPublishingStatus / isPublishingAction', () => {
  it('accepts every declared status/action', () => {
    for (const status of PUBLISHING_STATUSES) expect(isPublishingStatus(status)).toBe(true);
    for (const action of PUBLISHING_ACTIONS) expect(isPublishingAction(action)).toBe(true);
  });

  it('rejects unknown or non-string values', () => {
    expect(isPublishingStatus('deleted')).toBe(false);
    expect(isPublishingStatus(42)).toBe(false);
    expect(isPublishingStatus(undefined)).toBe(false);
    expect(isPublishingAction('delete')).toBe(false);
    expect(isPublishingAction(null)).toBe(false);
  });
});

/**
 * Server-side authority for the publishing workflow — the TypeScript
 * counterpart to packages/feature_publishing/lib/src/domain/
 * publishing_state_machine.dart. Not code-shared (Dart vs TypeScript);
 * kept in sync by hand. This copy is what actually gets enforced —
 * applyTransition.ts never trusts the client's own state-machine check.
 */

export const PUBLISHING_STATUSES = ['draft', 'inReview', 'approved', 'scheduled', 'published', 'archived'] as const;
export type PublishingStatus = (typeof PUBLISHING_STATUSES)[number];

export const PUBLISHING_ACTIONS = [
  'submitForReview',
  'approve',
  'reject',
  'publish',
  'unpublish',
  'schedule',
  'unschedule',
  'archive',
  'restore',
] as const;
export type PublishingAction = (typeof PUBLISHING_ACTIONS)[number];

/** Mirrors core_contracts' `Capability` enum values used by this module. */
export type PublishingCapability = 'submitForReview' | 'approveRejectPublish' | 'schedulePublishing';

export interface PublishingTransitionRule {
  from: PublishingStatus;
  action: PublishingAction;
  to: PublishingStatus;
  requiredCapability: PublishingCapability;
  requiresComment?: boolean;
  requiresFutureScheduledAt?: boolean;
}

export const PUBLISHING_TRANSITIONS: readonly PublishingTransitionRule[] = [
  { from: 'draft', action: 'submitForReview', to: 'inReview', requiredCapability: 'submitForReview' },
  { from: 'draft', action: 'archive', to: 'archived', requiredCapability: 'approveRejectPublish' },
  { from: 'inReview', action: 'reject', to: 'draft', requiredCapability: 'approveRejectPublish', requiresComment: true },
  { from: 'inReview', action: 'approve', to: 'approved', requiredCapability: 'approveRejectPublish' },
  { from: 'inReview', action: 'archive', to: 'archived', requiredCapability: 'approveRejectPublish' },
  { from: 'approved', action: 'reject', to: 'draft', requiredCapability: 'approveRejectPublish', requiresComment: true },
  {
    from: 'approved',
    action: 'schedule',
    to: 'scheduled',
    requiredCapability: 'schedulePublishing',
    requiresFutureScheduledAt: true,
  },
  { from: 'approved', action: 'publish', to: 'published', requiredCapability: 'approveRejectPublish' },
  { from: 'approved', action: 'archive', to: 'archived', requiredCapability: 'approveRejectPublish' },
  { from: 'scheduled', action: 'unschedule', to: 'approved', requiredCapability: 'schedulePublishing' },
  { from: 'scheduled', action: 'publish', to: 'published', requiredCapability: 'approveRejectPublish' },
  { from: 'scheduled', action: 'archive', to: 'archived', requiredCapability: 'approveRejectPublish' },
  { from: 'published', action: 'unpublish', to: 'archived', requiredCapability: 'approveRejectPublish' },
  { from: 'archived', action: 'restore', to: 'draft', requiredCapability: 'approveRejectPublish' },
];

export function resolveTransition(from: PublishingStatus, action: PublishingAction): PublishingTransitionRule | undefined {
  return PUBLISHING_TRANSITIONS.find((rule) => rule.from === from && rule.action === action);
}

export function isPublishingStatus(value: unknown): value is PublishingStatus {
  return typeof value === 'string' && (PUBLISHING_STATUSES as readonly string[]).includes(value);
}

export function isPublishingAction(value: unknown): value is PublishingAction {
  return typeof value === 'string' && (PUBLISHING_ACTIONS as readonly string[]).includes(value);
}

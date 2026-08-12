/**
 * The slice of the SRS §3 role/permission matrix this module needs —
 * the TypeScript counterpart to core_contracts'
 * `RolePermissionMatrix`/`Capability` (Dart). Not code-shared; kept in
 * sync by hand. Only the three capabilities the publishing workflow
 * touches are modeled here, at `full` granularity only (this module
 * never needs to distinguish `limited` from `none` — a `limited` access
 * such as Editor's "suggest only" on `schedulePublishing` is never
 * sufficient to actually call `schedule`).
 */
import type { PublishingCapability } from './stateMachine';

export type UserRole = 'editor' | 'publisher' | 'superAdmin';

const FULL_ACCESS: Record<PublishingCapability, readonly UserRole[]> = {
  submitForReview: ['editor', 'publisher', 'superAdmin'],
  approveRejectPublish: ['publisher', 'superAdmin'],
  schedulePublishing: ['publisher', 'superAdmin'],
};

export function hasFullCapability(role: UserRole | undefined, capability: PublishingCapability): boolean {
  if (!role) return false;
  return FULL_ACCESS[capability].includes(role);
}

export function isUserRole(value: unknown): value is UserRole {
  return value === 'editor' || value === 'publisher' || value === 'superAdmin';
}

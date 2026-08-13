/**
 * SRS §3's "Edit all content" capability slice — Editor: "Assigned/
 * permitted" (interpreted as owner-only, the same reading
 * `feature_publishing`'s Dart use cases already established for this
 * exact SRS ambiguity — see `SubmitForReviewUseCase`'s doc comment
 * there); Publisher/Super Admin: full. Kept separate from
 * `../publishing/capabilities.ts`, which is deliberately scoped to only
 * the three publishing-*workflow* capabilities — this one is about
 * editing content *fields*, a different action entirely.
 */
import type { UserRole } from '../publishing/capabilities';

const EDIT_ALL_CONTENT_ROLES: readonly UserRole[] = ['publisher', 'superAdmin'];

export function canEditAllContent(role: UserRole): boolean {
  return EDIT_ALL_CONTENT_ROLES.includes(role);
}

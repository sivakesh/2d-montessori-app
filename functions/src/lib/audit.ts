/**
 * Shared append-only audit-event writer. Every privileged function
 * (publishing, auth, media, enquiries, ...) must route through this
 * instead of writing to `auditLogs/{eventId}` directly, so the event shape
 * stays consistent with PRD §9.1 (Audit event fields) and SRS CMS-15 /
 * NFR-07.
 *
 * Phase 0 scaffold — implemented once feature_audit's Firestore schema is
 * finalized in Phase 1.
 */

export type AuditEventType =
  | 'create'
  | 'update'
  | 'submitReview'
  | 'approve'
  | 'publish'
  | 'unpublish'
  | 'archive'
  | 'restore'
  | 'login'
  | 'roleChange'
  | 'mediaConsentChange';

export interface AuditEventInput {
  eventType: AuditEventType;
  entityType: string;
  entityId: string;
  actorId: string;
  actorRole: string;
  changeSummary?: string;
  changedFields?: string[];
  requestId: string;
  source: 'cms' | 'function' | 'migration';
}

/**
 * TODO(Phase 1): write to `auditLogs/{eventId}` via the Admin SDK once the
 * Firestore client/emulator wiring for functions lands. Kept as an async
 * no-op for now so callers can already depend on the final signature.
 */
export async function writeAuditEvent(_input: AuditEventInput): Promise<void> {
  return Promise.resolve();
}

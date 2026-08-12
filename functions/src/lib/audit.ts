/**
 * Shared append-only audit-event writer. Every privileged function
 * (publishing, auth, media, enquiries, ...) must route through this
 * instead of writing to `auditLogs/{eventId}` directly, so the event shape
 * stays consistent with PRD §9.1 (Audit event fields) and SRS CMS-15 /
 * NFR-07. `auditLogs` has no client read/write access at all (see
 * firebase/firestore.rules) — only the Admin SDK, which this module uses,
 * can write here.
 */
import * as admin from 'firebase-admin';

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
  | 'statusChange'
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

export async function writeAuditEvent(input: AuditEventInput): Promise<void> {
  await admin.firestore().collection('auditLogs').add({
    ...input,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });
}

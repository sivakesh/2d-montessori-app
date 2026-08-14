/**
 * Shared append-only audit-event writer. Every privileged function
 * (publishing, auth, media, enquiries, ...) must route through this
 * instead of writing to `auditLogs/{eventId}` directly, so the event shape
 * stays consistent with PRD §9.1 (Audit event fields) and SRS CMS-15 /
 * NFR-07. `auditLogs` has no client read/write access at all (see
 * firebase/firestore.rules) — only the Admin SDK, which this module uses,
 * can write here.
 *
 * Uses the modular `firebase-admin/firestore` API, not the legacy
 * `admin.firestore()` namespace (removed outright in firebase-admin
 * v14 — see docs/architecture/environments.md's "Cloud Functions
 * runtime & dependency versions"), so a future v14 upgrade needs no
 * source change here.
 */
import { FieldValue, getFirestore } from 'firebase-admin/firestore';

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
  await getFirestore()
    .collection('auditLogs')
    .add({
      ...input,
      timestamp: FieldValue.serverTimestamp(),
    });
}

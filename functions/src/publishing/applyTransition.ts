/**
 * The shared engine every publishing action funnels through — resolves
 * the transition, checks capability and comment/schedule requirements,
 * and atomically updates the content doc plus writes a transition-history
 * entry, all inside one Firestore transaction (so a concurrent request
 * can never apply two transitions from a state that only supports one).
 *
 * Deliberately returns only `{ contentId, status }`, not the full
 * updated document: fields written via `FieldValue.serverTimestamp()`
 * are placeholder sentinels until the transaction commits server-side,
 * not real values this function could hand back over the wire. Callers
 * needing the full record do a follow-up Firestore read (which returns
 * real `Timestamp`s) rather than this callable trying to serialize them —
 * see feature_publishing's `FirestorePublishingRepository` on the Dart
 * side for the same pattern.
 */
import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

import { writeAuditEvent, type AuditEventType } from '../lib/audit';
import { hasFullCapability } from './capabilities';
import type { ActiveCaller } from './guards';
import { isPublishingStatus, resolveTransition, type PublishingAction } from './stateMachine';

export interface ApplyTransitionParams {
  db: Firestore;
  contentId: string;
  action: PublishingAction;
  caller: ActiveCaller;
  comment: string | undefined;
  scheduledAt: Date | undefined;
  requestId: string;
}

export interface ApplyTransitionResult {
  contentId: string;
  status: string;
}

export async function applyTransition(params: ApplyTransitionParams): Promise<ApplyTransitionResult> {
  const { db, contentId, action, caller, comment, scheduledAt, requestId } = params;
  const contentRef = db.collection('content').doc(contentId);

  const toStatus = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(contentRef);
    const current = snapshot.data();
    if (!snapshot.exists || !current) {
      throw new HttpsError('not-found', 'Content not found.');
    }

    const fromStatus = current.status;
    if (!isPublishingStatus(fromStatus)) {
      throw new HttpsError('failed-precondition', 'Content has an invalid status.');
    }

    const rule = resolveTransition(fromStatus, action);
    if (!rule) {
      throw new HttpsError('failed-precondition', `${action} is not valid from ${fromStatus}.`, {
        reason: 'invalid-transition',
      });
    }
    if (!hasFullCapability(caller.role, rule.requiredCapability)) {
      throw new HttpsError('permission-denied', 'You do not have permission to perform this action.');
    }
    if (rule.requiresComment && (!comment || comment.trim().length === 0)) {
      throw new HttpsError('failed-precondition', 'A comment is required for this action.', {
        reason: 'comment-required',
      });
    }
    if (rule.requiresFutureScheduledAt && (!scheduledAt || scheduledAt.getTime() <= Date.now())) {
      throw new HttpsError('failed-precondition', 'Scheduled publish time must be in the future.', {
        reason: 'invalid-schedule',
      });
    }

    const now = FieldValue.serverTimestamp();
    const updates: Record<string, unknown> = {
      status: rule.to,
      updatedAt: now,
      updatedBy: caller.uid,
    };

    if (action === 'submitForReview') {
      updates.submittedAt = now;
      updates.submittedBy = caller.uid;
    } else if (action === 'approve' || action === 'reject') {
      updates.reviewedAt = now;
      updates.reviewedBy = caller.uid;
    } else if (action === 'schedule') {
      updates.scheduledAt = scheduledAt;
    } else if (action === 'unschedule') {
      updates.scheduledAt = FieldValue.delete();
    } else if (action === 'publish') {
      updates.publishedAt = now;
      updates.publishedBy = caller.uid;
      updates.scheduledAt = FieldValue.delete();
    } else if (action === 'unpublish' || action === 'archive') {
      updates.archivedAt = now;
      updates.archivedBy = caller.uid;
    }
    // 'restore' deliberately clears no timestamp fields beyond status/
    // updatedAt/updatedBy — archivedAt/archivedBy remain as a historical
    // record; the transitions subcollection is the real audit trail.

    transaction.update(contentRef, updates);
    transaction.set(contentRef.collection('transitions').doc(), {
      action,
      fromStatus,
      toStatus: rule.to,
      actorId: caller.uid,
      actorRole: caller.role,
      comment: comment ?? null,
      occurredAt: now,
    });

    return rule.to;
  });

  await writeAuditEvent({
    eventType: auditEventTypeFor(action),
    entityType: 'content',
    entityId: contentId,
    actorId: caller.uid,
    actorRole: caller.role,
    changeSummary: `${action} -> ${toStatus}`,
    requestId,
    source: 'function',
  });

  return { contentId, status: toStatus };
}

function auditEventTypeFor(action: PublishingAction): AuditEventType {
  switch (action) {
    case 'submitForReview':
      return 'submitReview';
    case 'approve':
      return 'approve';
    case 'publish':
      return 'publish';
    case 'unpublish':
      return 'unpublish';
    case 'archive':
      return 'archive';
    case 'restore':
      return 'restore';
    default:
      return 'update';
  }
}

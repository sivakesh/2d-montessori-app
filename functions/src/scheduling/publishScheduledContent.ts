/**
 * SRS CMS-05 "Scheduling" / Technical Architecture "Server-side scheduled
 * jobs using Asia/Kolkata-aware timestamps" / PRD §9 "Scheduled
 * publishing is executed by a trusted scheduled function with
 * idempotency and retry." This is that executor — the piece that was
 * explicitly missing after `feature_publishing`'s milestone: that engine
 * validates and *stores* a schedule; nothing previously made scheduled
 * content actually go live at `scheduledAt`. This file is what does.
 *
 * `runScheduledPublish` is exported separately from the `onSchedule`
 * trigger specifically so it can be invoked directly in tests (the same
 * way every callable in this codebase is tested via `.run(request)`
 * rather than by actually triggering it) — Cloud Scheduler itself cannot
 * be exercised outside a real deployment, but the executor's logic can
 * be, fully.
 *
 * Deployment note: the `onSchedule` trigger below only becomes an active
 * cron job once deployed to a real Firebase project (`firebase deploy
 * --only functions`) — this milestone does not deploy anywhere (see
 * decisions.md's Dev-deployment boundary). Until that deployment
 * happens, no process actually publishes content at `scheduledAt`; this
 * file is implemented, idempotent, audited and tested, but not yet
 * running anywhere.
 */
import { FieldValue, getFirestore, type Firestore } from 'firebase-admin/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { writeAuditEvent } from '../lib/audit';

const SYSTEM_ACTOR_ID = 'system';
const SYSTEM_ACTOR_ROLE = 'system';

export interface ScheduledPublishResult {
  publishedContentIds: string[];
  failedContentIds: string[];
}

/**
 * Publishes every `content` doc whose `status == 'scheduled'` and whose
 * `scheduledAt` has passed as of [now]. Idempotent: each candidate
 * document's status is re-read and re-checked *inside its own
 * transaction*, immediately before writing, so a document already
 * published by something else (a human via `transitionPage`, or an
 * overlapping/retried run of this same job) is silently skipped rather
 * than double-published or double-audited.
 *
 * One document's failure does not stop the run from processing the
 * rest, and does not change that document's status — it is left exactly
 * as `'scheduled'`, so the *next* scheduled run retries it automatically
 * with no separate retry bookkeeping needed (NFR-06: "Failed scheduled
 * publishing... remains visible and retryable without silent data
 * loss" — visible via the failure being logged and the content staying
 * in a plainly-not-yet-published state, retryable because nothing here
 * ever marks it permanently failed).
 */
export async function runScheduledPublish(db: Firestore, now: Date = new Date()): Promise<ScheduledPublishResult> {
  const dueSnapshot = await db.collection('content').where('status', '==', 'scheduled').where('scheduledAt', '<=', now).get();

  const publishedContentIds: string[] = [];
  const failedContentIds: string[] = [];

  for (const doc of dueSnapshot.docs) {
    try {
      const published = await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(doc.ref);
        const current = snapshot.data();
        if (!snapshot.exists || !current || current.status !== 'scheduled') {
          return false;
        }
        const scheduledAt = (current.scheduledAt as FirebaseFirestore.Timestamp | undefined)?.toDate();
        if (!scheduledAt || scheduledAt.getTime() > now.getTime()) {
          return false;
        }

        const serverNow = FieldValue.serverTimestamp();
        transaction.update(doc.ref, {
          status: 'published',
          publishedAt: serverNow,
          publishedBy: SYSTEM_ACTOR_ID,
          scheduledAt: FieldValue.delete(),
          updatedAt: serverNow,
          updatedBy: SYSTEM_ACTOR_ID,
        });
        transaction.set(doc.ref.collection('transitions').doc(), {
          action: 'publish',
          fromStatus: 'scheduled',
          toStatus: 'published',
          actorId: SYSTEM_ACTOR_ID,
          actorRole: SYSTEM_ACTOR_ROLE,
          comment: null,
          occurredAt: serverNow,
        });
        return true;
      });

      if (published) {
        publishedContentIds.push(doc.id);
        await writeAuditEvent({
          eventType: 'publish',
          entityType: 'content',
          entityId: doc.id,
          actorId: SYSTEM_ACTOR_ID,
          actorRole: SYSTEM_ACTOR_ROLE,
          changeSummary: 'Scheduled publish executed',
          requestId: `scheduled-publish-${doc.id}-${now.getTime()}`,
          source: 'function',
        });
      }
    } catch (error) {
      failedContentIds.push(doc.id);
      // Deliberately not rethrown: one document's failure must not stop
      // the rest of this run (NFR-06).
      console.error(`Scheduled publish failed for content/${doc.id}`, error);
    }
  }

  return { publishedContentIds, failedContentIds };
}

export const publishScheduledContent = onSchedule('every 5 minutes', async () => {
  await runScheduledPublish(getFirestore());
});

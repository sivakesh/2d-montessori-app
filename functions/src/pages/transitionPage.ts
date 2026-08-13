/**
 * Every Pages workflow action (submitForReview, approve, reject,
 * publish, unpublish, schedule, unschedule, archive, restore) goes
 * through this one callable rather than
 * `publishingFns-transitionContent` directly, so the SRS CMS-08
 * completeness gate below actually runs — but the transition itself is
 * delegated, unchanged, to the exact same
 * `functions/src/publishing/applyTransition.ts` engine every other
 * content type uses. This file adds a pre-flight check in front of that
 * engine; it does not re-implement, wrap, or duplicate any part of the
 * state machine, capability checks, or transaction logic themselves.
 */
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { resolveRequestId } from '../lib/requestId';
import { applyTransition, type ApplyTransitionResult } from '../publishing/applyTransition';
import { assertActiveCaller } from '../publishing/guards';
import { validateAction, validateContentId, validateOptionalComment, validateOptionalScheduledAt } from '../publishing/validators';
import { pageCompletenessViolations } from './completeness';

interface TransitionPageRequestData {
  contentId?: unknown;
  action?: unknown;
  comment?: unknown;
  scheduledAt?: unknown;
}

/**
 * SRS CMS-08's completeness checks apply at the moments content moves
 * toward or into public visibility — not on `reject`/`archive`/
 * `unschedule`/`restore`, which only need the transition engine's own
 * edge/capability checks.
 */
const COMPLETENESS_GATED_ACTIONS = new Set(['submitForReview', 'publish', 'schedule']);

export const transitionPage = onCall<TransitionPageRequestData, Promise<ApplyTransitionResult>>(async (request) => {
  const db = getFirestore();
  const caller = await assertActiveCaller(request, db);

  const contentId = validateContentId(request.data.contentId);
  const action = validateAction(request.data.action);
  const comment = validateOptionalComment(request.data.comment);
  const scheduledAt = validateOptionalScheduledAt(request.data.scheduledAt);

  if (COMPLETENESS_GATED_ACTIONS.has(action)) {
    const snapshot = await db.collection('content').doc(contentId).get();
    if (!snapshot.exists) {
      throw new HttpsError('not-found', 'Page not found.');
    }
    const violations = pageCompletenessViolations(snapshot.data() ?? {});
    if (violations.length > 0) {
      throw new HttpsError('failed-precondition', 'This page is not ready.', { reason: 'page-incomplete', violations });
    }
  }

  const result = await applyTransition({
    db,
    contentId,
    action,
    caller,
    comment,
    scheduledAt,
    requestId: resolveRequestId(request, contentId),
  });

  // Archive/restoration metadata specific to Pages — a small follow-up
  // write after the transition transaction commits, the same
  // non-atomic-with-the-audit-write pattern already used elsewhere in
  // this codebase (e.g. createDraft.ts's audit write). Low-stakes,
  // informational metadata only, never anything the workflow engine
  // itself depends on.
  if (action === 'restore') {
    await db.collection('content').doc(contentId).update({ restoredAt: FieldValue.serverTimestamp(), restoredBy: caller.uid });
  }

  return result;
});

/**
 * The single callable behind every named workflow action
 * (submitForReview, approve, reject, publish, unpublish, schedule,
 * unschedule, archive, restore). Unlike feature_identity's auth module —
 * which has five *distinct* callables because each does meaningfully
 * different work — every publishing action shares one implementation
 * (applyTransition.ts): they differ only in which edge of
 * `PUBLISHING_TRANSITIONS` applies, which is exactly what the `action`
 * parameter selects. See feature_publishing's `FirestorePublishingRepository`
 * (Dart) for the matching client-side design note.
 */
import { getFirestore } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';

import { resolveRequestId } from '../lib/requestId';
import { applyTransition, type ApplyTransitionResult } from './applyTransition';
import { assertActiveCaller } from './guards';
import { validateAction, validateContentId, validateOptionalComment, validateOptionalScheduledAt } from './validators';

interface TransitionContentRequestData {
  contentId?: unknown;
  action?: unknown;
  comment?: unknown;
  scheduledAt?: unknown;
}

export const transitionContent = onCall<TransitionContentRequestData, Promise<ApplyTransitionResult>>(async (request) => {
  const db = getFirestore();
  const caller = await assertActiveCaller(request, db);

  const contentId = validateContentId(request.data.contentId);
  const action = validateAction(request.data.action);
  const comment = validateOptionalComment(request.data.comment);
  const scheduledAt = validateOptionalScheduledAt(request.data.scheduledAt);

  return applyTransition({
    db,
    contentId,
    action,
    caller,
    comment,
    scheduledAt,
    requestId: resolveRequestId(request, contentId),
  });
});

/**
 * Creates a new Draft. Minimal by design — full content-field creation
 * (body, SEO, media, ...) is each content feature's own concern; this
 * exists only so the publishing workflow has something to exercise, per
 * this milestone's boundary ("do not begin the full page builder... until
 * the publishing workflow has been implemented and verified").
 *
 * `ownerId` is always the caller's own uid, set server-side — never
 * client-supplied, so nobody can create a draft "owned by" someone else.
 */
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';

import { writeAuditEvent } from '../lib/audit';
import { resolveRequestId } from '../lib/requestId';
import { assertActiveCaller } from './guards';
import { validateContentType, validateTitle } from './validators';

interface CreateDraftRequestData {
  contentType?: unknown;
  title?: unknown;
}

interface CreateDraftResponse {
  contentId: string;
}

export const createDraft = onCall<CreateDraftRequestData, Promise<CreateDraftResponse>>(async (request) => {
  const db = getFirestore();
  const caller = await assertActiveCaller(request, db);

  const contentType = validateContentType(request.data.contentType);
  const title = validateTitle(request.data.title);

  const now = FieldValue.serverTimestamp();
  const docRef = await db.collection('content').add({
    contentType,
    title,
    status: 'draft',
    ownerId: caller.uid,
    createdAt: now,
    createdBy: caller.uid,
    updatedAt: now,
    updatedBy: caller.uid,
  });

  await writeAuditEvent({
    eventType: 'create',
    entityType: 'content',
    entityId: docRef.id,
    actorId: caller.uid,
    actorRole: caller.role,
    changeSummary: `Created ${contentType} draft "${title}"`,
    requestId: resolveRequestId(request, docRef.id),
    source: 'function',
  });

  return { contentId: docRef.id };
});

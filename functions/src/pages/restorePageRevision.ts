/**
 * SRS CMS-06: "Authorised roles can compare and restore an earlier
 * version without erasing the audit trail." Copies a prior revision's
 * content fields onto the current draft; never deletes or rewrites the
 * revision it restores from — restoring itself appends a *new* revision
 * entry (the same as any other content edit), so the full history,
 * including this restore, remains intact afterward.
 */
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { writeAuditEvent } from '../lib/audit';
import { resolveRequestId } from '../lib/requestId';
import { assertActiveCaller } from '../publishing/guards';
import { canEditAllContent } from './permissions';
import { validatePageId } from './validators';

interface RestorePageRevisionRequestData {
  pageId?: unknown;
  revisionId?: unknown;
}

interface RestorePageRevisionResponse {
  pageId: string;
}

function validateRevisionId(value: unknown): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'A revision id is required.');
  }
  return value;
}

const CONTENT_FIELDS = ['title', 'slug', 'summary', 'pageType', 'sections', 'featuredImage', 'seo', 'navigationLabel', 'showInNavigation'] as const;

export const restorePageRevision = onCall<RestorePageRevisionRequestData, Promise<RestorePageRevisionResponse>>(async (request) => {
  const db = getFirestore();
  const caller = await assertActiveCaller(request, db);
  const pageId = validatePageId(request.data.pageId);
  const revisionId = validateRevisionId(request.data.revisionId);

  const contentRef = db.collection('content').doc(pageId);
  const revisionRef = contentRef.collection('revisions').doc(revisionId);

  await db.runTransaction(async (transaction) => {
    const [pageSnapshot, revisionSnapshot] = await Promise.all([transaction.get(contentRef), transaction.get(revisionRef)]);
    const page = pageSnapshot.data();
    if (!pageSnapshot.exists || !page) {
      throw new HttpsError('not-found', 'Page not found.');
    }
    const revision = revisionSnapshot.data();
    if (!revisionSnapshot.exists || !revision) {
      throw new HttpsError('not-found', 'That revision could not be found.');
    }
    if (page.status !== 'draft') {
      throw new HttpsError('failed-precondition', 'This page can only be edited while it is a draft.', { reason: 'page-not-editable' });
    }
    if (!canEditAllContent(caller.role) && page.ownerId !== caller.uid) {
      throw new HttpsError('permission-denied', 'You do not have permission to edit this page.');
    }

    const restoredFields = Object.fromEntries(CONTENT_FIELDS.map((field) => [field, revision[field]]));
    const now = FieldValue.serverTimestamp();

    transaction.update(contentRef, { ...restoredFields, updatedAt: now, updatedBy: caller.uid });
    transaction.set(contentRef.collection('revisions').doc(), { ...restoredFields, actorId: caller.uid, createdAt: now });
  });

  await writeAuditEvent({
    eventType: 'update',
    entityType: 'content',
    entityId: pageId,
    actorId: caller.uid,
    actorRole: caller.role,
    changeSummary: `Restored revision ${revisionId}`,
    requestId: resolveRequestId(request, pageId),
    source: 'function',
  });

  return { pageId };
});

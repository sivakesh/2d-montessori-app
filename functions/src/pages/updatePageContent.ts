/**
 * Replaces a page's editable content fields — only valid while the page
 * is a Draft (editing an already-published page goes through
 * `publishingFns-transitionContent`'s `unpublish` then `restore`, reusing
 * the existing workflow rather than adding a parallel "live draft copy"
 * mechanism; see decisions.md). Every successful call appends a
 * `content/{pageId}/revisions/` entry (SRS CMS-06), all inside the same
 * transaction as the content update itself so a revision can never be
 * recorded without the corresponding change actually landing (or vice
 * versa).
 */
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { writeAuditEvent } from '../lib/audit';
import { resolveRequestId } from '../lib/requestId';
import { assertActiveCaller } from '../publishing/guards';
import { canEditAllContent } from './permissions';
import { assertSlugAvailable } from './slug';
import { validatePageContent, validatePageId } from './validators';

interface UpdatePageContentResponse {
  pageId: string;
}

export const updatePageContent = onCall<Record<string, unknown>, Promise<UpdatePageContentResponse>>(async (request) => {
  const db = getFirestore();
  const caller = await assertActiveCaller(request, db);
  const pageId = validatePageId(request.data.pageId);
  const content = validatePageContent(request.data);

  const contentRef = db.collection('content').doc(pageId);

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(contentRef);
    const current = snapshot.data();
    if (!snapshot.exists || !current) {
      throw new HttpsError('not-found', 'Page not found.');
    }
    if (current.status !== 'draft') {
      throw new HttpsError('failed-precondition', 'This page can only be edited while it is a draft.', { reason: 'page-not-editable' });
    }
    if (!canEditAllContent(caller.role) && current.ownerId !== caller.uid) {
      throw new HttpsError('permission-denied', 'You do not have permission to edit this page.');
    }

    await assertSlugAvailable(transaction, content.slug, pageId);

    const now = FieldValue.serverTimestamp();
    transaction.update(contentRef, {
      title: content.title,
      slug: content.slug,
      summary: content.summary,
      pageType: content.pageType,
      sections: content.sections,
      featuredImage: content.featuredImage,
      seo: content.seo,
      navigationLabel: content.navigationLabel,
      showInNavigation: content.showInNavigation,
      updatedAt: now,
      updatedBy: caller.uid,
    });

    transaction.set(contentRef.collection('revisions').doc(), {
      title: content.title,
      slug: content.slug,
      summary: content.summary,
      pageType: content.pageType,
      sections: content.sections,
      featuredImage: content.featuredImage,
      seo: content.seo,
      navigationLabel: content.navigationLabel,
      showInNavigation: content.showInNavigation,
      actorId: caller.uid,
      createdAt: now,
    });
  });

  await writeAuditEvent({
    eventType: 'update',
    entityType: 'content',
    entityId: pageId,
    actorId: caller.uid,
    actorRole: caller.role,
    changeSummary: `Updated page content for "${content.title}"`,
    requestId: resolveRequestId(request, pageId),
    source: 'function',
  });

  return { pageId };
});

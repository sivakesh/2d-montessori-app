/**
 * Creates a new page Draft with a minimal, server-derived initial slug —
 * everything else (summary, sections, SEO, ...) is filled in afterwards
 * via `updatePageContent` as the editor works (SRS CMS-07 autosave).
 * Page-specific analogue of `functions/src/publishing/createDraft.ts`;
 * not a reuse of that callable because it needs to derive+reserve a slug
 * transactionally, which the generic envelope has no concept of.
 */
import { FieldValue, getFirestore, type Transaction } from 'firebase-admin/firestore';
import { onCall } from 'firebase-functions/v2/https';

import { writeAuditEvent } from '../lib/audit';
import { resolveRequestId } from '../lib/requestId';
import { assertActiveCaller } from '../publishing/guards';
import { validatePageTitle } from './validators';
import { slugify } from './slugify';

interface CreatePageRequestData {
  title?: unknown;
}

interface CreatePageResponse {
  pageId: string;
}

async function uniqueSlugFor(transaction: Transaction, baseSlug: string): Promise<string> {
  const db = getFirestore();
  let candidate = baseSlug;
  for (let suffix = 2; suffix < 100; suffix += 1) {
    const query = db.collection('content').where('contentType', '==', 'page').where('slug', '==', candidate).limit(1);
    const snapshot = await transaction.get(query);
    if (snapshot.empty) return candidate;
    candidate = `${baseSlug}-${suffix}`;
  }
  throw new Error('Could not generate a unique slug.');
}

export const createPage = onCall<CreatePageRequestData, Promise<CreatePageResponse>>(async (request) => {
  const db = getFirestore();
  const caller = await assertActiveCaller(request, db);
  const title = validatePageTitle(request.data.title);
  const baseSlug = slugify(title);

  const docRef = db.collection('content').doc();
  await db.runTransaction(async (transaction) => {
    const slug = await uniqueSlugFor(transaction, baseSlug);
    const now = FieldValue.serverTimestamp();
    transaction.set(docRef, {
      contentType: 'page',
      title,
      slug,
      summary: '',
      pageType: 'standard',
      sections: [],
      featuredImage: null,
      seo: { title: null, metaDescription: null, canonicalUrl: null, indexing: 'indexFollow', social: { title: null, description: null, image: null } },
      navigationLabel: null,
      showInNavigation: false,
      status: 'draft',
      ownerId: caller.uid,
      createdAt: now,
      createdBy: caller.uid,
      updatedAt: now,
      updatedBy: caller.uid,
    });
  });

  await writeAuditEvent({
    eventType: 'create',
    entityType: 'content',
    entityId: docRef.id,
    actorId: caller.uid,
    actorRole: caller.role,
    changeSummary: `Created page draft "${title}"`,
    requestId: resolveRequestId(request, docRef.id),
    source: 'function',
  });

  return { pageId: docRef.id };
});

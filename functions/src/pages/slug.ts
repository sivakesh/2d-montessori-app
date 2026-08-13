/**
 * SRS CMS-08 "unique slug" / PRD §5 "Slugs are ... unique within their
 * route namespace." Checked inside the same Firestore transaction that
 * writes the page, so a slug can never be claimed twice by two
 * concurrent saves — see `updatePageContent.ts`/`createPage.ts` for the
 * call sites, and `functions/test/emulator/pages.functions.test.ts`'s
 * concurrency test for the actual race proof (the equivalent of
 * `feature_publishing`'s last-active-Super-Admin race test, for slugs).
 */
import type { Transaction } from 'firebase-admin/firestore';
import { getFirestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

/**
 * Throws `failed-precondition` (`reason: 'slug-conflict'`) if any *other*
 * page document already uses [slug]. Uniqueness applies across every
 * status (a Draft may still reserve a slug it plans to publish under),
 * scoped to `contentType == 'page'` only — Pages and any future content
 * type sharing the `content` collection do not compete for the same
 * slug namespace.
 */
export async function assertSlugAvailable(transaction: Transaction, slug: string, excludingPageId: string | undefined): Promise<void> {
  const db = getFirestore();
  const query = db.collection('content').where('contentType', '==', 'page').where('slug', '==', slug).limit(2);
  const snapshot = await transaction.get(query);
  const conflict = snapshot.docs.some((doc) => doc.id !== excludingPageId);
  if (conflict) {
    throw new HttpsError('failed-precondition', 'That URL slug is already in use by another page.', { reason: 'slug-conflict' });
  }
}

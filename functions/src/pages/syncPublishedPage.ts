/**
 * Keeps the public `publishedPages/{slug}` collection (public read, no
 * admin fields, no unpublished revisions — see `firebase/firestore.rules`
 * and `PublicPageView`'s Dart doc comment) in sync with the admin-only
 * `content/{contentId}` collection whenever a page's status changes.
 *
 * Implemented as a Firestore trigger — reactive and decoupled from
 * `transitionPage.ts` — rather than folded into that callable directly,
 * because (a) it keeps `applyTransition.ts` itself untouched and generic
 * across every content type, and (b) Cloud Functions triggers get
 * automatic retry-on-failure semantics, which matters here: this is a
 * "materialized view" sync, not the workflow transition itself (that
 * already committed and was already audited by the time this runs).
 *
 * Editing a page's content is only ever allowed while it is a Draft (see
 * `updatePageContent.ts`), so a page's `slug` cannot change while it is
 * Published.
 *
 * The sync logic is exported as `syncPublishedPageForChange`, taking
 * plain `before`/`after` document data rather than a Firestore
 * `Event`/`Change` object — the same "extract a directly-testable pure
 * function, have the trigger wrapper just unwrap the event and call it"
 * pattern `scheduling/publishScheduledContent.ts` uses, since hand-
 * constructing a realistic 2nd-gen `FirestoreEvent` in a test is
 * impractical (unlike `onCall`'s `CallableRequest`, which this
 * codebase's other tests construct directly).
 *
 * Deliberately does NOT trust `after` (or `before`) for the actual
 * publish/unpublish decision or for the fields it writes — Cloud
 * Firestore 2nd-gen triggers are delivered *at least once* and are
 * explicitly **not** ordering-guaranteed (see Google's own Cloud
 * Functions/Eventarc docs). A page rapidly published then unpublished
 * or rescheduled (routine during authoring/UAT) can have its two
 * trigger invocations processed out of order: if the older "became
 * Published" event is (re)delivered *after* the newer "no longer
 * Published" event has already run, blindly trusting that stale
 * event's `after` payload would resurrect (or leave stale) a
 * `publishedPages/{slug}` document for a page that is not currently
 * Published — a real defect found in Dev UAT (a page scheduled minutes
 * in the future was publicly readable immediately; root-caused to
 * exactly this — a stale `publishedPages` document left over from
 * earlier publish/unpublish testing on the same page, not anything
 * about scheduling itself). Every invocation instead re-reads the
 * *live* `content/{contentId}` document and reconciles `publishedPages`
 * to match that live truth, making this convergent and idempotent
 * regardless of delivery order, delivery count, or which specific
 * event triggered this run. `before.slug` is still used, but only as a
 * hint for cleaning up a slug this specific write moved *away* from —
 * a live read alone can never recover a slug the document no longer
 * has.
 */
import { getFirestore, type DocumentData, type Firestore } from 'firebase-admin/firestore';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';

function isPage(data: DocumentData | undefined): boolean {
  return data?.contentType === 'page';
}

/**
 * Resolves every `RelatedContentSection.relatedPageIds` reference across
 * a page's sections to a display-ready summary — but only for related
 * pages that are *currently* published at the moment this page is
 * synced. See `PublicPageView.resolvedRelatedPages`'s doc comment for
 * the staleness this implies (a related page unpublished later does not
 * retroactively update pages that already reference it, until they are
 * next republished) — a documented, accepted limitation, not an oversight.
 */
export async function resolveRelatedPages(db: Firestore, sections: unknown): Promise<Record<string, unknown>> {
  const ids = new Set<string>();
  if (Array.isArray(sections)) {
    for (const section of sections as Record<string, unknown>[]) {
      if (section?.type === 'relatedContent' && Array.isArray(section.relatedPageIds)) {
        for (const id of section.relatedPageIds as unknown[]) {
          if (typeof id === 'string') ids.add(id);
        }
      }
    }
  }

  const result: Record<string, unknown> = {};
  await Promise.all(
    [...ids].map(async (id) => {
      const snapshot = await db.collection('content').doc(id).get();
      const data = snapshot.data();
      if (data && data.contentType === 'page' && data.status === 'published') {
        result[id] = { pageId: id, slug: data.slug, title: data.title, summary: data.summary, featuredImage: data.featuredImage ?? null };
      }
    }),
  );
  return result;
}

/**
 * The testable core. `before`/`after` are the triggering event's own
 * payload — used only as a cheap early-exit filter (is this write even
 * page-related?) and as a hint for which slug this write may have moved
 * away from. The actual publish/unpublish decision, and every field
 * written, always comes from a fresh read of `content/{contentId}` — see
 * this file's doc comment for why trusting the event payload directly
 * is not safe.
 */
export async function syncPublishedPageForChange(
  db: Firestore,
  contentId: string,
  before: DocumentData | undefined,
  after: DocumentData | undefined,
): Promise<void> {
  if (!isPage(before) && !isPage(after)) return;

  const liveSnapshot = await db.collection('content').doc(contentId).get();
  const live = liveSnapshot.exists ? liveSnapshot.data() : undefined;
  const shouldBePublished = isPage(live) && live?.status === 'published';
  const liveSlug = shouldBePublished ? (live?.slug as string) : undefined;

  // A slug this write moved away from (including "was published under
  // this slug, no longer is") can only be recovered from the event
  // itself — a live read has no memory of a slug the document no
  // longer has. Guarded by `!== liveSlug` so a stale/reordered event
  // can never delete a slug that a *later* write has since republished
  // under (the same content id or otherwise).
  const staleSlug = before?.slug as string | undefined;
  if (staleSlug && staleSlug !== liveSlug) {
    await db.collection('publishedPages').doc(staleSlug).delete();
  }

  if (shouldBePublished && live && liveSlug) {
    const resolvedRelatedPages = await resolveRelatedPages(db, live.sections);
    await db
      .collection('publishedPages')
      .doc(liveSlug)
      .set({
        pageId: contentId,
        slug: live.slug,
        title: live.title,
        summary: live.summary,
        pageType: live.pageType,
        sections: live.sections ?? [],
        featuredImage: live.featuredImage ?? null,
        seo: live.seo ?? null,
        navigationLabel: live.navigationLabel ?? null,
        showInNavigation: live.showInNavigation === true,
        publishedAt: live.publishedAt ?? null,
        resolvedRelatedPages,
      });
  }
}

/**
 * Region is pinned explicitly to `asia-south1` — not left to infer a
 * default the way every other Function in this codebase does — because
 * this is the one Firestore-triggered (`onDocumentWritten`) Function,
 * and Eventarc requires a Firestore trigger's region to match the
 * region of the Firestore database it watches. The real Dev Firestore
 * database (`twod-montessori-dev`) is confirmed to live in
 * `asia-south1`; every other Function in this codebase is `onCall`/
 * `onSchedule`, which has no such co-location constraint and is left on
 * the (equally explicit, just SDK-default rather than code-pinned)
 * `us-central1` — see `docs/architecture/environments.md`'s "Cloud
 * Functions region policy" for the full reasoning and the intentional
 * split this creates. Do not remove this option to "match the rest of
 * the codebase" — doing so would silently move this specific trigger
 * away from its database's region and reproduce the original deploy
 * failure this option was added to prevent.
 */
export const syncPublishedPage = onDocumentWritten({ document: 'content/{contentId}', region: 'asia-south1' }, async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  await syncPublishedPageForChange(getFirestore(), event.params.contentId, before, after);
});

/**
 * Integration tests for the Pages callables (`createPage`,
 * `updatePageContent`, `transitionPage`, `restorePageRevision`) and the
 * `syncPublishedPageForChange` sync logic, against the real Firebase
 * Emulator Suite (Auth + Firestore) — NOT run by `npm test`. Run via
 * `npm run test:emulator`, which needs JDK 21+ (see README
 * "Prerequisites"). Authored and statically checked (`tsc`, eslint) in
 * an environment where the emulator itself could not be started; see
 * docs/architecture/decisions.md "Phase 1 — CMS Core: feature_pages"
 * for exactly what has and hasn't been run.
 *
 * Conventions match functions/test/emulator/publishing.functions.test.ts
 * exactly: `.run(request)` on the exported `CallableFunction` directly,
 * `expectHttpsErrorCode` for asserting on `HttpsError.code` (not
 * `.message`), unique per-describe-block actor uids, and running the
 * whole `test/emulator/` directory `--runInBand` (see
 * functions/package.json) so files never race each other's global-
 * collection state (`auditLogs`, slug uniqueness) the way a fifth CI-
 * caught bug during Foundation Verification proved they can.
 */
import * as admin from 'firebase-admin';
import type { CallableRequest } from 'firebase-functions/v2/https';

import { createPage } from '../../src/pages/createPage';
import { restorePageRevision } from '../../src/pages/restorePageRevision';
import { syncPublishedPageForChange } from '../../src/pages/syncPublishedPage';
import { transitionPage } from '../../src/pages/transitionPage';
import { updatePageContent } from '../../src/pages/updatePageContent';

admin.initializeApp({ projectId: 'demo-montessori-2d' });
const db = admin.firestore();
const auth = admin.auth();

function requestAs(uid: string, role: string, data: unknown = {}): CallableRequest<never> {
  return { data, auth: { uid, token: { role } as never }, rawRequest: {} } as unknown as CallableRequest<never>;
}

function unauthenticatedRequest(data: unknown = {}): CallableRequest<never> {
  return { data, auth: undefined, rawRequest: {} } as unknown as CallableRequest<never>;
}

async function seedUser(uid: string, role: string, status: 'active' | 'suspended' = 'active'): Promise<void> {
  await auth.createUser({ uid, email: `${uid}@example.test`, password: 'seed-password-1' });
  await auth.setCustomUserClaims(uid, { role, status });
  await db.collection('users').doc(uid).set({
    email: `${uid}@example.test`,
    displayName: uid,
    photoUrl: null,
    role,
    status,
    mustChangePassword: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    createdBy: 'seed',
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedBy: 'seed',
  });
}

async function cleanupUser(uid: string): Promise<void> {
  await Promise.allSettled([auth.deleteUser(uid), db.collection('users').doc(uid).delete()]);
}

async function cleanupContent(contentId: string): Promise<void> {
  const [transitions, revisions] = await Promise.all([
    db.collection('content').doc(contentId).collection('transitions').get(),
    db.collection('content').doc(contentId).collection('revisions').get(),
  ]);
  await Promise.allSettled([
    ...transitions.docs.map((d) => d.ref.delete()),
    ...revisions.docs.map((d) => d.ref.delete()),
    db.collection('content').doc(contentId).delete(),
  ]);
}

async function cleanupPublishedPage(slug: string): Promise<void> {
  await db.collection('publishedPages').doc(slug).delete().catch(() => undefined);
}

async function auditLogCount(): Promise<number> {
  const snapshot = await db.collection('auditLogs').count().get();
  return snapshot.data().count;
}

async function auditEntriesFor(entityId: string): Promise<FirebaseFirestore.DocumentData[]> {
  const snapshot = await db.collection('auditLogs').where('entityId', '==', entityId).get();
  return snapshot.docs.map((doc) => doc.data());
}

async function expectHttpsErrorCode(promise: Promise<unknown>, code: string): Promise<void> {
  await expect(promise).rejects.toMatchObject({ code });
}

function fullPageContent(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    title: 'About us',
    slug: `about-us-${Date.now()}-${Math.floor(Math.random() * 1e6)}`,
    summary: 'A short summary.',
    pageType: 'standard',
    sections: [{ id: 's1', type: 'richText', body: 'Body text.' }],
    seo: { title: 'About us', metaDescription: 'A page about us.' },
    showInNavigation: false,
    ...overrides,
  };
}

describe('createPage', () => {
  const editorUid = 'pages-editor';
  const suspendedUid = 'pages-suspended-editor';

  beforeAll(() => Promise.all([seedUser(editorUid, 'editor'), seedUser(suspendedUid, 'editor', 'suspended')]));
  afterAll(() => Promise.all([cleanupUser(editorUid), cleanupUser(suspendedUid)]));

  it('rejects an unauthenticated caller and creates no audit entry', async () => {
    const before = await auditLogCount();
    await expectHttpsErrorCode(createPage.run(unauthenticatedRequest({ title: 'X' })), 'unauthenticated');
    expect(await auditLogCount()).toBe(before);
  });

  it('rejects a suspended caller even with a cached "active" claim', async () => {
    await expectHttpsErrorCode(createPage.run(requestAs(suspendedUid, 'editor', { title: 'X' })), 'permission-denied');
  });

  it('creates a Draft with a derived slug, ownerId set server-side, and writes one audit entry', async () => {
    const response = await createPage.run(requestAs(editorUid, 'editor', { title: 'Our Program Philosophy' }));

    const doc = await db.collection('content').doc(response.pageId).get();
    expect(doc.data()).toMatchObject({ contentType: 'page', title: 'Our Program Philosophy', slug: 'our-program-philosophy', status: 'draft', ownerId: editorUid });

    const auditEntries = await auditEntriesFor(response.pageId);
    expect(auditEntries).toHaveLength(1);
    expect(auditEntries[0]).toMatchObject({ eventType: 'create', entityType: 'content', actorId: editorUid, source: 'function' });

    await cleanupContent(response.pageId);
  });

  it('auto-suffixes the slug when the derived slug is already taken', async () => {
    const first = await createPage.run(requestAs(editorUid, 'editor', { title: 'Admissions' }));
    const second = await createPage.run(requestAs(editorUid, 'editor', { title: 'Admissions' }));

    const [firstDoc, secondDoc] = await Promise.all([
      db.collection('content').doc(first.pageId).get(),
      db.collection('content').doc(second.pageId).get(),
    ]);
    expect(firstDoc.data()?.slug).toBe('admissions');
    expect(secondDoc.data()?.slug).toBe('admissions-2');

    await Promise.all([cleanupContent(first.pageId), cleanupContent(second.pageId)]);
  });
});

describe('updatePageContent', () => {
  const ownerUid = 'pages-owner';
  const otherEditorUid = 'pages-other-editor';
  const publisherUid = 'pages-publisher';
  let pageId: string;

  beforeAll(() => Promise.all([seedUser(ownerUid, 'editor'), seedUser(otherEditorUid, 'editor'), seedUser(publisherUid, 'publisher')]));
  afterAll(() => Promise.all([cleanupUser(ownerUid), cleanupUser(otherEditorUid), cleanupUser(publisherUid)]));

  beforeEach(async () => {
    const response = await createPage.run(requestAs(ownerUid, 'editor', { title: 'Draft page' }));
    pageId = response.pageId;
  });

  afterEach(() => cleanupContent(pageId));

  it('rejects a non-owner Editor and creates no audit entry', async () => {
    const before = await auditLogCount();
    await expectHttpsErrorCode(
      updatePageContent.run(requestAs(otherEditorUid, 'editor', { pageId, ...fullPageContent() })),
      'permission-denied',
    );
    expect(await auditLogCount()).toBe(before);
  });

  it('allows the owner to update content and writes a revision plus an audit entry', async () => {
    const content = fullPageContent({ title: 'Updated title' });
    await updatePageContent.run(requestAs(ownerUid, 'editor', { pageId, ...content }));

    const doc = await db.collection('content').doc(pageId).get();
    expect(doc.data()?.title).toBe('Updated title');

    const revisions = await db.collection('content').doc(pageId).collection('revisions').get();
    expect(revisions.docs).toHaveLength(1);
    expect(revisions.docs[0]?.data()).toMatchObject({ title: 'Updated title', actorId: ownerUid });

    const auditEntries = await auditEntriesFor(pageId);
    expect(auditEntries.some((e) => e.eventType === 'update' && e.actorId === ownerUid)).toBe(true);
  });

  it('allows a Publisher to edit content they do not own', async () => {
    await expect(updatePageContent.run(requestAs(publisherUid, 'publisher', { pageId, ...fullPageContent() }))).resolves.toMatchObject({ pageId });
  });

  it('rejects an invalid slug format', async () => {
    await expectHttpsErrorCode(
      updatePageContent.run(requestAs(ownerUid, 'editor', { pageId, ...fullPageContent({ slug: 'Not Valid!' }) })),
      'invalid-argument',
    );
  });

  it('rejects a slug already used by another page', async () => {
    const otherSlug = `taken-slug-${Date.now()}`;
    const other = await createPage.run(requestAs(ownerUid, 'editor', { title: 'Other page' }));
    await updatePageContent.run(requestAs(ownerUid, 'editor', { pageId: other.pageId, ...fullPageContent({ slug: otherSlug }) }));

    await expectHttpsErrorCode(
      updatePageContent.run(requestAs(ownerUid, 'editor', { pageId, ...fullPageContent({ slug: otherSlug }) })),
      'failed-precondition',
    );

    await cleanupContent(other.pageId);
  });

  it('never lets two concurrent saves both claim the same new slug', async () => {
    const raceSlug = `race-slug-${Date.now()}`;
    const pageA = await createPage.run(requestAs(ownerUid, 'editor', { title: 'Race A' }));
    const pageB = await createPage.run(requestAs(ownerUid, 'editor', { title: 'Race B' }));

    const [resultA, resultB] = await Promise.allSettled([
      updatePageContent.run(requestAs(ownerUid, 'editor', { pageId: pageA.pageId, ...fullPageContent({ slug: raceSlug }) })),
      updatePageContent.run(requestAs(ownerUid, 'editor', { pageId: pageB.pageId, ...fullPageContent({ slug: raceSlug }) })),
    ]);

    const statuses = [resultA.status, resultB.status];
    expect(statuses.filter((s) => s === 'fulfilled')).toHaveLength(1);
    expect(statuses.filter((s) => s === 'rejected')).toHaveLength(1);

    await Promise.all([cleanupContent(pageA.pageId), cleanupContent(pageB.pageId)]);
  });

  it('rejects editing once the page has left Draft', async () => {
    await updatePageContent.run(requestAs(ownerUid, 'editor', { pageId, ...fullPageContent() }));
    await transitionPage.run(requestAs(ownerUid, 'editor', { contentId: pageId, action: 'submitForReview' }));

    await expectHttpsErrorCode(
      updatePageContent.run(requestAs(ownerUid, 'editor', { pageId, ...fullPageContent() })),
      'failed-precondition',
    );
  });
});

describe('transitionPage — completeness gate and full workflow', () => {
  const editorUid = 'pages-workflow-editor';
  const publisherUid = 'pages-workflow-publisher';
  const superAdminUid = 'pages-workflow-super-admin';
  let pageId: string;

  beforeAll(() =>
    Promise.all([seedUser(editorUid, 'editor'), seedUser(publisherUid, 'publisher'), seedUser(superAdminUid, 'superAdmin')]),
  );
  afterAll(() => Promise.all([cleanupUser(editorUid), cleanupUser(publisherUid), cleanupUser(superAdminUid)]));

  beforeEach(async () => {
    const response = await createPage.run(requestAs(editorUid, 'editor', { title: 'Workflow page' }));
    pageId = response.pageId;
  });

  afterEach(() => cleanupContent(pageId));

  it('blocks submitForReview on an incomplete page (no sections/SEO yet) and creates no audit entry', async () => {
    const before = await auditLogCount();
    await expectHttpsErrorCode(
      transitionPage.run(requestAs(editorUid, 'editor', { contentId: pageId, action: 'submitForReview' })),
      'failed-precondition',
    );
    expect(await auditLogCount()).toBe(before);

    const doc = await db.collection('content').doc(pageId).get();
    expect(doc.data()?.status).toBe('draft');
  });

  it('allows submitForReview once the page is complete', async () => {
    await updatePageContent.run(requestAs(editorUid, 'editor', { pageId, ...fullPageContent() }));
    const response = await transitionPage.run(requestAs(editorUid, 'editor', { contentId: pageId, action: 'submitForReview' }));
    expect(response.status).toBe('inReview');
  });

  it('does not gate reject/archive on completeness', async () => {
    await updatePageContent.run(requestAs(editorUid, 'editor', { pageId, ...fullPageContent() }));
    await transitionPage.run(requestAs(editorUid, 'editor', { contentId: pageId, action: 'submitForReview' }));

    await expect(
      transitionPage.run(requestAs(publisherUid, 'publisher', { contentId: pageId, action: 'reject', comment: 'Needs work.' })),
    ).resolves.toMatchObject({ status: 'draft' });
  });

  it('walks a complete page through submitForReview, approve, publish, unpublish, restore — syncing publishedPages along the way', async () => {
    await updatePageContent.run(requestAs(editorUid, 'editor', { pageId, ...fullPageContent() }));
    const pageDoc = await db.collection('content').doc(pageId).get();
    const slug = pageDoc.data()?.slug as string;

    await transitionPage.run(requestAs(editorUid, 'editor', { contentId: pageId, action: 'submitForReview' }));
    await transitionPage.run(requestAs(publisherUid, 'publisher', { contentId: pageId, action: 'approve' }));
    await transitionPage.run(requestAs(publisherUid, 'publisher', { contentId: pageId, action: 'publish' }));

    // The emulator suite for these tests runs Auth + Firestore only (no
    // Functions emulator — callables are invoked directly via `.run()`),
    // so the real `onDocumentWritten` trigger never fires here; the sync
    // logic itself (`syncPublishedPageForChange`) is exercised directly,
    // the same "extract the pure function, test it directly" approach
    // `runScheduledPublish` uses — see that file's doc comment.
    const afterPublish = (await db.collection('content').doc(pageId).get()).data();
    await syncPublishedPageForChange(db, pageId, pageDoc.data(), afterPublish);

    const publishedDoc = await db.collection('publishedPages').doc(slug).get();
    expect(publishedDoc.exists).toBe(true);
    expect(publishedDoc.data()).toMatchObject({ pageId, slug, title: 'About us' });
    expect(publishedDoc.data()).not.toHaveProperty('ownerId');
    expect(publishedDoc.data()).not.toHaveProperty('status');

    const beforeUnpublish = afterPublish;
    await transitionPage.run(requestAs(superAdminUid, 'superAdmin', { contentId: pageId, action: 'unpublish' }));
    const afterUnpublish = (await db.collection('content').doc(pageId).get()).data();
    await syncPublishedPageForChange(db, pageId, beforeUnpublish, afterUnpublish);

    expect((await db.collection('publishedPages').doc(slug).get()).exists).toBe(false);

    await transitionPage.run(requestAs(superAdminUid, 'superAdmin', { contentId: pageId, action: 'restore' }));
    const restoredDoc = await db.collection('content').doc(pageId).get();
    expect(restoredDoc.data()).toMatchObject({ status: 'draft', restoredBy: superAdminUid });
    expect(restoredDoc.data()?.restoredAt).toBeTruthy();

    await cleanupPublishedPage(slug);
  });
});

describe('restorePageRevision', () => {
  const ownerUid = 'pages-revision-owner';
  let pageId: string;

  beforeAll(() => seedUser(ownerUid, 'editor'));
  afterAll(() => cleanupUser(ownerUid));

  beforeEach(async () => {
    const response = await createPage.run(requestAs(ownerUid, 'editor', { title: 'Revisable page' }));
    pageId = response.pageId;
  });

  afterEach(() => cleanupContent(pageId));

  it('returns not-found for a revision id that does not exist', async () => {
    await expectHttpsErrorCode(restorePageRevision.run(requestAs(ownerUid, 'editor', { pageId, revisionId: 'does-not-exist' })), 'not-found');
  });

  it('restores an earlier revision onto the current draft and records a new revision without erasing history', async () => {
    await updatePageContent.run(requestAs(ownerUid, 'editor', { pageId, ...fullPageContent({ title: 'First version' }) }));
    const firstRevisions = await db.collection('content').doc(pageId).collection('revisions').get();
    const firstRevisionId = firstRevisions.docs[0]?.id as string;

    await updatePageContent.run(requestAs(ownerUid, 'editor', { pageId, ...fullPageContent({ title: 'Second version' }) }));

    await restorePageRevision.run(requestAs(ownerUid, 'editor', { pageId, revisionId: firstRevisionId }));

    const doc = await db.collection('content').doc(pageId).get();
    expect(doc.data()?.title).toBe('First version');

    const revisionsAfterRestore = await db.collection('content').doc(pageId).collection('revisions').get();
    expect(revisionsAfterRestore.docs).toHaveLength(3); // original + second version + the restore itself
  });
});

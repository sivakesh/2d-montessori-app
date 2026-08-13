/**
 * Integration tests for `runScheduledPublish` (the scheduled-publishing
 * executor, SRS CMS-05 / PRD §9) against the real Firebase Emulator
 * Suite (Auth + Firestore) — NOT run by `npm test`. Run via `npm run
 * test:emulator` (needs JDK 21+, see README "Prerequisites"). This
 * exercises the executor's *logic* directly by calling
 * `runScheduledPublish(db, now)`, the same way every callable in this
 * codebase is tested via `.run(request)` rather than actually triggering
 * it — Cloud Scheduler itself cannot be exercised without a real
 * deployment (see decisions.md's Dev-deployment boundary and
 * `publishScheduledContent.ts`'s doc comment on what "tested" means
 * here specifically: the executor is proven correct; nothing in this
 * repository proves Cloud Scheduler is actually invoking it on a
 * schedule, because nothing has been deployed yet).
 */
import * as admin from 'firebase-admin';
import type { CallableRequest } from 'firebase-functions/v2/https';

import { createPage } from '../../src/pages/createPage';
import { transitionPage } from '../../src/pages/transitionPage';
import { updatePageContent } from '../../src/pages/updatePageContent';
import { runScheduledPublish } from '../../src/scheduling/publishScheduledContent';

admin.initializeApp({ projectId: 'demo-montessori-2d' });
const db = admin.firestore();
const auth = admin.auth();

function requestAs(uid: string, role: string, data: unknown = {}): CallableRequest<never> {
  return { data, auth: { uid, token: { role } as never }, rawRequest: {} } as unknown as CallableRequest<never>;
}

async function seedUser(uid: string, role: string): Promise<void> {
  await auth.createUser({ uid, email: `${uid}@example.test`, password: 'seed-password-1' });
  await auth.setCustomUserClaims(uid, { role, status: 'active' });
  await db.collection('users').doc(uid).set({
    email: `${uid}@example.test`,
    displayName: uid,
    photoUrl: null,
    role,
    status: 'active',
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
  const [transitions] = await Promise.all([db.collection('content').doc(contentId).collection('transitions').get()]);
  await Promise.allSettled([...transitions.docs.map((d) => d.ref.delete()), db.collection('content').doc(contentId).delete()]);
}

async function auditEntriesFor(entityId: string): Promise<FirebaseFirestore.DocumentData[]> {
  const snapshot = await db.collection('auditLogs').where('entityId', '==', entityId).get();
  return snapshot.docs.map((doc) => doc.data());
}

function fullPageContent(): Record<string, unknown> {
  return {
    title: 'Scheduled page',
    slug: `scheduled-page-${Date.now()}-${Math.floor(Math.random() * 1e6)}`,
    summary: 'Summary.',
    pageType: 'standard',
    sections: [{ id: 's1', type: 'richText', body: 'Body.' }],
    seo: { title: 'Scheduled page', metaDescription: 'A scheduled page.' },
    showInNavigation: false,
  };
}

async function makeScheduledPage(ownerUid: string, publisherUid: string, scheduledAt: Date): Promise<string> {
  const created = await createPage.run(requestAs(ownerUid, 'editor', { title: 'Scheduled page' }));
  await updatePageContent.run(requestAs(ownerUid, 'editor', { pageId: created.pageId, ...fullPageContent() }));
  await transitionPage.run(requestAs(ownerUid, 'editor', { contentId: created.pageId, action: 'submitForReview' }));
  await transitionPage.run(requestAs(publisherUid, 'publisher', { contentId: created.pageId, action: 'approve' }));
  await transitionPage.run(
    requestAs(publisherUid, 'publisher', { contentId: created.pageId, action: 'schedule', scheduledAt: scheduledAt.toISOString() }),
  );
  return created.pageId;
}

describe('runScheduledPublish', () => {
  const ownerUid = 'scheduling-owner';
  const publisherUid = 'scheduling-publisher';

  beforeAll(() => Promise.all([seedUser(ownerUid, 'editor'), seedUser(publisherUid, 'publisher')]));
  afterAll(() => Promise.all([cleanupUser(ownerUid), cleanupUser(publisherUid)]));

  it('publishes a page whose scheduledAt has passed, and writes an audit entry', async () => {
    const pageId = await makeScheduledPage(ownerUid, publisherUid, new Date(Date.now() + 1000));
    const result = await runScheduledPublish(db, new Date(Date.now() + 5000));

    expect(result.publishedContentIds).toContain(pageId);
    const doc = await db.collection('content').doc(pageId).get();
    expect(doc.data()).toMatchObject({ status: 'published', publishedBy: 'system' });
    expect(doc.data()?.scheduledAt).toBeUndefined();

    const auditEntries = await auditEntriesFor(pageId);
    expect(auditEntries.some((e) => e.eventType === 'publish' && e.actorId === 'system')).toBe(true);

    await cleanupContent(pageId);
  });

  it('does not publish a page whose scheduledAt is still in the future', async () => {
    const pageId = await makeScheduledPage(ownerUid, publisherUid, new Date(Date.now() + 3600_000));
    const result = await runScheduledPublish(db, new Date());

    expect(result.publishedContentIds).not.toContain(pageId);
    const doc = await db.collection('content').doc(pageId).get();
    expect(doc.data()?.status).toBe('scheduled');

    await cleanupContent(pageId);
  });

  it('is idempotent: running twice for the same due page only publishes and audits it once', async () => {
    const pageId = await makeScheduledPage(ownerUid, publisherUid, new Date(Date.now() + 1000));
    const now = new Date(Date.now() + 5000);

    const first = await runScheduledPublish(db, now);
    const second = await runScheduledPublish(db, now);

    expect(first.publishedContentIds).toContain(pageId);
    expect(second.publishedContentIds).not.toContain(pageId);

    const auditEntries = await auditEntriesFor(pageId);
    expect(auditEntries.filter((e) => e.eventType === 'publish')).toHaveLength(1);

    await cleanupContent(pageId);
  });

  it('never double-publishes when two overlapping runs race for the same due page', async () => {
    const pageId = await makeScheduledPage(ownerUid, publisherUid, new Date(Date.now() + 1000));
    const now = new Date(Date.now() + 5000);

    const [a, b] = await Promise.all([runScheduledPublish(db, now), runScheduledPublish(db, now)]);
    const totalPublishedThisPage = [...a.publishedContentIds, ...b.publishedContentIds].filter((id) => id === pageId).length;
    expect(totalPublishedThisPage).toBe(1);

    const auditEntries = await auditEntriesFor(pageId);
    expect(auditEntries.filter((e) => e.eventType === 'publish')).toHaveLength(1);

    await cleanupContent(pageId);
  });
});

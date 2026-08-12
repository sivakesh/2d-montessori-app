/**
 * Integration tests for the publishing callables (`createDraft`,
 * `transitionContent`) against the real Firebase Emulator Suite (Auth +
 * Firestore) — NOT run by `npm test`. Run via `npm run test:emulator`,
 * which needs JDK 21+ (see README "Prerequisites"). Authored and
 * statically checked (`tsc`, eslint) in an environment where the
 * emulator itself could not be started; see
 * docs/architecture/decisions.md "Test execution status" for exactly
 * what has and hasn't been run.
 *
 * Mirrors functions/test/emulator/auth.functions.test.ts's conventions:
 * `.run(request)` called directly on the exported `CallableFunction`,
 * `expectHttpsErrorCode` for asserting on `HttpsError.code` (not
 * `.message`), and audit-entry-count assertions around every
 * success/failure boundary.
 */
import * as admin from 'firebase-admin';
import type { CallableRequest } from 'firebase-functions/v2/https';

import { createDraft } from '../../src/publishing/createDraft';
import { transitionContent } from '../../src/publishing/transitionContent';

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
  const transitions = await db.collection('content').doc(contentId).collection('transitions').get();
  await Promise.allSettled([
    ...transitions.docs.map((doc) => doc.ref.delete()),
    db.collection('content').doc(contentId).delete(),
  ]);
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

describe('createDraft', () => {
  const editorUid = 'publishing-editor';
  const suspendedUid = 'publishing-suspended-editor';

  beforeAll(async () => {
    await seedUser(editorUid, 'editor');
    await seedUser(suspendedUid, 'editor', 'suspended');
  });

  afterAll(() => Promise.all([cleanupUser(editorUid), cleanupUser(suspendedUid)]));

  it('rejects an unauthenticated caller and creates no audit entry', async () => {
    const before = await auditLogCount();
    await expectHttpsErrorCode(
      createDraft.run(unauthenticatedRequest({ contentType: 'page', title: 'Untitled' })),
      'unauthenticated',
    );
    expect(await auditLogCount()).toBe(before);
  });

  it('rejects a caller whose Firestore status is suspended, even though their cached claim says active', async () => {
    const before = await auditLogCount();
    await expectHttpsErrorCode(
      createDraft.run(requestAs(suspendedUid, 'editor', { contentType: 'page', title: 'Untitled' })),
      'permission-denied',
    );
    expect(await auditLogCount()).toBe(before);
  });

  it('creates a Draft owned by the caller and writes exactly one audit entry', async () => {
    const response = await createDraft.run(requestAs(editorUid, 'editor', { contentType: 'page', title: 'Our Program' }));

    const doc = await db.collection('content').doc(response.contentId).get();
    expect(doc.data()).toMatchObject({
      contentType: 'page',
      title: 'Our Program',
      status: 'draft',
      ownerId: editorUid,
    });

    const auditEntries = await auditEntriesFor(response.contentId);
    expect(auditEntries).toHaveLength(1);
    expect(auditEntries[0]).toMatchObject({ eventType: 'create', entityType: 'content', actorId: editorUid, source: 'function' });

    await cleanupContent(response.contentId);
  });

  it('ignores any client-supplied ownerId and always sets it to the caller', async () => {
    const response = await createDraft.run(
      requestAs(editorUid, 'editor', { contentType: 'page', title: 'Spoofed owner', ownerId: 'someone-else' } as never),
    );

    const doc = await db.collection('content').doc(response.contentId).get();
    expect(doc.data()?.ownerId).toBe(editorUid);

    await cleanupContent(response.contentId);
  });
});

describe('transitionContent — the full workflow', () => {
  const editorUid = 'workflow-editor';
  const publisherUid = 'workflow-publisher';
  const superAdminUid = 'workflow-super-admin';
  let contentId: string;

  beforeAll(async () => {
    await Promise.all([
      seedUser(editorUid, 'editor'),
      seedUser(publisherUid, 'publisher'),
      seedUser(superAdminUid, 'superAdmin'),
    ]);
  });

  afterAll(() => Promise.all([cleanupUser(editorUid), cleanupUser(publisherUid), cleanupUser(superAdminUid)]));

  beforeEach(async () => {
    const response = await createDraft.run(requestAs(editorUid, 'editor', { contentType: 'page', title: 'Workflow content' }));
    contentId = response.contentId;
  });

  afterEach(() => cleanupContent(contentId));

  it('rejects an unauthenticated caller and creates no audit entry', async () => {
    const before = await auditLogCount();
    await expectHttpsErrorCode(
      transitionContent.run(unauthenticatedRequest({ contentId, action: 'submitForReview' })),
      'unauthenticated',
    );
    expect(await auditLogCount()).toBe(before);
  });

  it('rejects an action with no edge from the current status and creates no audit entry', async () => {
    const before = await auditLogCount();
    await expectHttpsErrorCode(
      transitionContent.run(requestAs(superAdminUid, 'superAdmin', { contentId, action: 'publish' })),
      'failed-precondition',
    );
    expect(await auditLogCount()).toBe(before);

    const doc = await db.collection('content').doc(contentId).get();
    expect(doc.data()?.status).toBe('draft');
  });

  it('rejects an Editor trying to approve (capability check) and creates no audit entry', async () => {
    await transitionContent.run(requestAs(editorUid, 'editor', { contentId, action: 'submitForReview' }));
    const before = await auditLogCount();

    await expectHttpsErrorCode(
      transitionContent.run(requestAs(editorUid, 'editor', { contentId, action: 'approve' })),
      'permission-denied',
    );
    expect(await auditLogCount()).toBe(before);

    const doc = await db.collection('content').doc(contentId).get();
    expect(doc.data()?.status).toBe('inReview');
  });

  it('rejects reject without a comment and creates no audit entry', async () => {
    await transitionContent.run(requestAs(editorUid, 'editor', { contentId, action: 'submitForReview' }));
    const before = await auditLogCount();

    await expectHttpsErrorCode(
      transitionContent.run(requestAs(publisherUid, 'publisher', { contentId, action: 'reject' })),
      'failed-precondition',
    );
    expect(await auditLogCount()).toBe(before);
  });

  it('rejects schedule with a past scheduledAt and creates no audit entry', async () => {
    await transitionContent.run(requestAs(editorUid, 'editor', { contentId, action: 'submitForReview' }));
    await transitionContent.run(requestAs(publisherUid, 'publisher', { contentId, action: 'approve' }));
    const before = await auditLogCount();

    await expectHttpsErrorCode(
      transitionContent.run(
        requestAs(publisherUid, 'publisher', { contentId, action: 'schedule', scheduledAt: '2000-01-01T00:00:00.000Z' }),
      ),
      'failed-precondition',
    );
    expect(await auditLogCount()).toBe(before);
  });

  it('walks Draft through submitForReview, approve, schedule, unschedule, publish, unpublish — with a transition-history entry and an audit entry at every step', async () => {
    const steps: Array<{ caller: string; role: string; data: Record<string, unknown>; expectedStatus: string }> = [
      { caller: editorUid, role: 'editor', data: { action: 'submitForReview' }, expectedStatus: 'inReview' },
      { caller: publisherUid, role: 'publisher', data: { action: 'approve' }, expectedStatus: 'approved' },
      {
        caller: publisherUid,
        role: 'publisher',
        data: { action: 'schedule', scheduledAt: new Date(Date.now() + 86_400_000).toISOString() },
        expectedStatus: 'scheduled',
      },
      { caller: publisherUid, role: 'publisher', data: { action: 'unschedule' }, expectedStatus: 'approved' },
      { caller: superAdminUid, role: 'superAdmin', data: { action: 'publish' }, expectedStatus: 'published' },
      { caller: superAdminUid, role: 'superAdmin', data: { action: 'unpublish' }, expectedStatus: 'archived' },
    ];

    for (const step of steps) {
      const before = await auditLogCount();
      const response = await transitionContent.run(requestAs(step.caller, step.role, { contentId, ...step.data }));
      expect(response.status).toBe(step.expectedStatus);
      expect(await auditLogCount()).toBe(before + 1);
    }

    const doc = await db.collection('content').doc(contentId).get();
    expect(doc.data()).toMatchObject({
      status: 'archived',
      submittedBy: editorUid,
      reviewedBy: publisherUid,
      publishedBy: superAdminUid,
      archivedBy: superAdminUid,
    });

    const transitions = await db.collection('content').doc(contentId).collection('transitions').orderBy('occurredAt').get();
    expect(transitions.docs.map((d) => d.data().action)).toEqual([
      'submitForReview',
      'approve',
      'schedule',
      'unschedule',
      'publish',
      'unpublish',
    ]);

    const auditEntries = await auditEntriesFor(contentId);
    expect(auditEntries).toHaveLength(1 + steps.length); // +1 for createDraft in beforeEach
  });

  it('reject returns InReview content to Draft, records the comment, and writes an audit entry', async () => {
    await transitionContent.run(requestAs(editorUid, 'editor', { contentId, action: 'submitForReview' }));

    const response = await transitionContent.run(
      requestAs(publisherUid, 'publisher', { contentId, action: 'reject', comment: 'Please add more detail.' }),
    );
    expect(response.status).toBe('draft');

    const transitions = await db.collection('content').doc(contentId).collection('transitions').orderBy('occurredAt').get();
    const rejectTransition = transitions.docs.at(-1)?.data();
    expect(rejectTransition).toMatchObject({ action: 'reject', comment: 'Please add more detail.' });

    const auditEntries = await auditEntriesFor(contentId);
    expect(auditEntries.some((e) => e.eventType === 'update' && e.actorId === publisherUid)).toBe(true);
  });

  it('never applies two conflicting concurrent transitions from the same status to the same content', async () => {
    await transitionContent.run(requestAs(editorUid, 'editor', { contentId, action: 'submitForReview' }));

    const [approveResult, archiveResult] = await Promise.allSettled([
      transitionContent.run(requestAs(publisherUid, 'publisher', { contentId, action: 'approve' })),
      transitionContent.run(requestAs(superAdminUid, 'superAdmin', { contentId, action: 'archive' })),
    ]);

    // Both `approve` and `archive` are valid edges out of `inReview`, but
    // only one can win: the Firestore transaction in applyTransition.ts
    // reads the content doc's current status before writing, so whichever
    // commits first moves it out of `inReview`; the second re-reads on
    // retry, finds the edge no longer exists from the new status, and is
    // rejected with `failed-precondition` rather than silently applying.
    const statuses = [approveResult.status, archiveResult.status];
    expect(statuses.filter((s) => s === 'fulfilled')).toHaveLength(1);
    expect(statuses.filter((s) => s === 'rejected')).toHaveLength(1);

    const doc = await db.collection('content').doc(contentId).get();
    expect(['approved', 'archived']).toContain(doc.data()?.status);
  });
});

/**
 * Positive/negative tests for firestore.rules' content/{contentId} +
 * content/{contentId}/transitions/{transitionId} rules (SRS CMS-02,
 * CMS-03 — Phase 1 CMS Core / feature_publishing). Runs only against the
 * Firestore emulator: `npm run test:against-emulators` from this
 * directory (needs JDK 21+). Authored and statically checked here but
 * not executed — see docs/architecture/decisions.md "Phase 1 — CMS Core:
 * feature_publishing" / "Test execution status (feature_publishing)".
 *
 * Each context's `.firestore()` is called at most once and cached in a
 * local variable — see firestore.rules.test.ts's comment on the same
 * pattern for why (a real bug this checkpoint's CI run caught).
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, setDoc } from 'firebase/firestore';

let testEnv: RulesTestEnvironment;

const ACTIVE_EDITOR = { role: 'editor', status: 'active' };
const ACTIVE_PUBLISHER = { role: 'publisher', status: 'active' };
const ACTIVE_SUPER_ADMIN = { role: 'superAdmin', status: 'active' };

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-montessori-2d-content-rules',
    firestore: {
      rules: readFileSync(join(__dirname, '..', 'firestore.rules'), 'utf8'),
      host: 'localhost',
      port: 8080,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

async function seedContentDoc(contentId: string, data: Record<string, unknown>): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'content', contentId), data);
  });
}

async function seedUserDoc(uid: string, data: Record<string, unknown>): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', uid), data);
  });
}

describe('content/{contentId} read access', () => {
  it('allows the owner to read their own draft', async () => {
    await seedContentDoc('c1', { contentType: 'page', title: 'Home', status: 'draft', ownerId: 'editor1' });
    const owner = testEnv.authenticatedContext('editor1', ACTIVE_EDITOR);
    const db = owner.firestore();
    await assertSucceeds(getDoc(doc(db, 'content', 'c1')));
  });

  it('denies an Editor reading content they do not own', async () => {
    await seedContentDoc('c1', { contentType: 'page', title: 'Home', status: 'draft', ownerId: 'editor1' });
    const other = testEnv.authenticatedContext('editor2', { role: 'editor', status: 'active' });
    const db = other.firestore();
    await assertFails(getDoc(doc(db, 'content', 'c1')));
  });

  it('allows an active Publisher to read content they do not own', async () => {
    await seedContentDoc('c1', { contentType: 'page', title: 'Home', status: 'inReview', ownerId: 'editor1' });
    await seedUserDoc('pub1', { email: 'pub1@example.test', role: 'publisher', status: 'active' });
    const publisher = testEnv.authenticatedContext('pub1', ACTIVE_PUBLISHER);
    const db = publisher.firestore();
    await assertSucceeds(getDoc(doc(db, 'content', 'c1')));
  });

  it('allows an active Super Admin to read content they do not own', async () => {
    await seedContentDoc('c1', { contentType: 'page', title: 'Home', status: 'draft', ownerId: 'editor1' });
    await seedUserDoc('admin1', { email: 'admin1@example.test', role: 'superAdmin', status: 'active' });
    const admin = testEnv.authenticatedContext('admin1', ACTIVE_SUPER_ADMIN);
    const db = admin.firestore();
    await assertSucceeds(getDoc(doc(db, 'content', 'c1')));
  });

  it('denies a Publisher whose cached token is stale (token says active, Firestore says suspended)', async () => {
    await seedContentDoc('c1', { contentType: 'page', title: 'Home', status: 'draft', ownerId: 'editor1' });
    await seedUserDoc('pub1', { email: 'pub1@example.test', role: 'publisher', status: 'suspended' });
    const stalePublisher = testEnv.authenticatedContext('pub1', ACTIVE_PUBLISHER);
    const db = stalePublisher.firestore();
    await assertFails(getDoc(doc(db, 'content', 'c1')));
  });

  it('denies an unauthenticated read', async () => {
    await seedContentDoc('c1', { contentType: 'page', title: 'Home', status: 'draft', ownerId: 'editor1' });
    const anon = testEnv.unauthenticatedContext();
    const db = anon.firestore();
    await assertFails(getDoc(doc(db, 'content', 'c1')));
  });
});

describe('content/{contentId} write access — everything goes through Cloud Functions', () => {
  it('denies the owner writing to their own draft directly', async () => {
    await seedContentDoc('c1', { contentType: 'page', title: 'Home', status: 'draft', ownerId: 'editor1' });
    const owner = testEnv.authenticatedContext('editor1', ACTIVE_EDITOR);
    const db = owner.firestore();
    await assertFails(setDoc(doc(db, 'content', 'c1'), { title: 'Renamed' }, { merge: true }));
  });

  it('denies a Super Admin transitioning content directly (must go through transitionContent)', async () => {
    await seedContentDoc('c1', { contentType: 'page', title: 'Home', status: 'draft', ownerId: 'editor1' });
    await seedUserDoc('admin1', { email: 'admin1@example.test', role: 'superAdmin', status: 'active' });
    const admin = testEnv.authenticatedContext('admin1', ACTIVE_SUPER_ADMIN);
    const db = admin.firestore();
    await assertFails(setDoc(doc(db, 'content', 'c1'), { status: 'published' }, { merge: true }));
  });
});

describe('content/{contentId}/transitions — immutable history', () => {
  it('allows the owner to read their content’s transition history', async () => {
    await seedContentDoc('c1', { contentType: 'page', title: 'Home', status: 'inReview', ownerId: 'editor1' });
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'content', 'c1', 'transitions', 't1'), {
        action: 'submitForReview',
        fromStatus: 'draft',
        toStatus: 'inReview',
        actorId: 'editor1',
        actorRole: 'editor',
      });
    });
    const owner = testEnv.authenticatedContext('editor1', ACTIVE_EDITOR);
    const db = owner.firestore();
    await assertSucceeds(getDocs(collection(db, 'content', 'c1', 'transitions')));
  });

  it('denies a non-owner Editor reading the transition history', async () => {
    await seedContentDoc('c1', { contentType: 'page', title: 'Home', status: 'inReview', ownerId: 'editor1' });
    const other = testEnv.authenticatedContext('editor2', { role: 'editor', status: 'active' });
    const db = other.firestore();
    await assertFails(getDocs(collection(db, 'content', 'c1', 'transitions')));
  });

  it('denies any client write to the transition history', async () => {
    await seedContentDoc('c1', { contentType: 'page', title: 'Home', status: 'inReview', ownerId: 'editor1' });
    await seedUserDoc('admin1', { email: 'admin1@example.test', role: 'superAdmin', status: 'active' });
    const admin = testEnv.authenticatedContext('admin1', ACTIVE_SUPER_ADMIN);
    const db = admin.firestore();
    await assertFails(
      setDoc(doc(db, 'content', 'c1', 'transitions', 'fake'), {
        action: 'publish',
        fromStatus: 'approved',
        toStatus: 'published',
        actorId: 'admin1',
        actorRole: 'superAdmin',
      }),
    );
  });
});

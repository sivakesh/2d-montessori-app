/**
 * Positive/negative tests for firestore.rules' media/{mediaId} and
 * mediaUsages/{usageId} rules (SRS MED-01..MED-06 — Phase 1 CMS Core /
 * feature_media). Run via `npm run test:against-emulators` from this
 * directory (needs JDK 21+) — not executed in this environment, see
 * README "Prerequisites".
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-montessori-2d-media-rules',
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

async function seedUserDoc(uid: string, data: Record<string, unknown>): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users', uid), data);
  });
}

async function seedMediaDoc(mediaId: string, data: Record<string, unknown>): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'media', mediaId), data);
  });
}

async function seedMediaUsageDoc(usageId: string, data: Record<string, unknown>): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'mediaUsages', usageId), data);
  });
}

describe('media/{mediaId}', () => {
  it('allows an active Editor to read the shared library (not owner-scoped)', async () => {
    await seedMediaDoc('m1', { title: 'Logo', status: 'ready', uploadedBy: 'someone-else' });
    await seedUserDoc('editor1', { email: 'editor1@example.test', role: 'editor', status: 'active' });
    const editor = testEnv.authenticatedContext('editor1', { role: 'editor', status: 'active' });
    await assertSucceeds(getDoc(doc(editor.firestore(), 'media', 'm1')));
  });

  it('allows an active Publisher and an active Super Admin to read', async () => {
    await seedMediaDoc('m1', { title: 'Logo', status: 'ready' });
    await seedUserDoc('pub1', { email: 'pub1@example.test', role: 'publisher', status: 'active' });
    await seedUserDoc('admin1', { email: 'admin1@example.test', role: 'superAdmin', status: 'active' });
    const publisher = testEnv.authenticatedContext('pub1', { role: 'publisher', status: 'active' });
    const admin = testEnv.authenticatedContext('admin1', { role: 'superAdmin', status: 'active' });
    await assertSucceeds(getDoc(doc(publisher.firestore(), 'media', 'm1')));
    await assertSucceeds(getDoc(doc(admin.firestore(), 'media', 'm1')));
  });

  it('denies an unauthenticated read', async () => {
    await seedMediaDoc('m1', { title: 'Logo', status: 'ready' });
    const anon = testEnv.unauthenticatedContext();
    await assertFails(getDoc(doc(anon.firestore(), 'media', 'm1')));
  });

  it('denies a suspended user even with a cached "active" claim', async () => {
    await seedMediaDoc('m1', { title: 'Logo', status: 'ready' });
    await seedUserDoc('editor1', { email: 'editor1@example.test', role: 'editor', status: 'suspended' });
    const editor = testEnv.authenticatedContext('editor1', { role: 'editor', status: 'active' });
    await assertFails(getDoc(doc(editor.firestore(), 'media', 'm1')));
  });

  it('denies any client write, even as Super Admin', async () => {
    await seedUserDoc('admin1', { email: 'admin1@example.test', role: 'superAdmin', status: 'active' });
    const admin = testEnv.authenticatedContext('admin1', { role: 'superAdmin', status: 'active' });
    await assertFails(setDoc(doc(admin.firestore(), 'media', 'm1'), { title: 'Hacked', status: 'ready' }));
  });
});

describe('mediaUsages/{usageId}', () => {
  it('allows an active CMS user to read', async () => {
    await seedMediaUsageDoc('m1__c1', { mediaId: 'm1', contentId: 'c1' });
    await seedUserDoc('editor1', { email: 'editor1@example.test', role: 'editor', status: 'active' });
    const editor = testEnv.authenticatedContext('editor1', { role: 'editor', status: 'active' });
    await assertSucceeds(getDoc(doc(editor.firestore(), 'mediaUsages', 'm1__c1')));
  });

  it('denies an unauthenticated read', async () => {
    await seedMediaUsageDoc('m1__c1', { mediaId: 'm1', contentId: 'c1' });
    const anon = testEnv.unauthenticatedContext();
    await assertFails(getDoc(doc(anon.firestore(), 'mediaUsages', 'm1__c1')));
  });

  it('denies any client write, even as Super Admin', async () => {
    await seedUserDoc('admin1', { email: 'admin1@example.test', role: 'superAdmin', status: 'active' });
    const admin = testEnv.authenticatedContext('admin1', { role: 'superAdmin', status: 'active' });
    await assertFails(setDoc(doc(admin.firestore(), 'mediaUsages', 'm1__c1'), { mediaId: 'm1', contentId: 'c1' }));
  });
});

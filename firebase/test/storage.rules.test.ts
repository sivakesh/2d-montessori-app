/**
 * Positive/negative tests for storage.rules. Unchanged at the Phase 1
 * Foundation milestone (see storage.rules' header comment) — this suite
 * exists so that fact is verified, not assumed, and so it already covers
 * the deny-by-default baseline before feature_media adds real upload
 * rules in Phase 2. Run via `npm run test:against-emulators` from this
 * directory — needs JDK 21+; not executed in this environment (see
 * README "Prerequisites").
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { getBytes, ref, uploadBytes } from 'firebase/storage';

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-montessori-2d',
    storage: {
      rules: readFileSync(join(__dirname, '..', 'storage.rules'), 'utf8'),
      host: 'localhost',
      port: 9199,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

describe('public/** — read-only for clients', () => {
  it('allows unauthenticated read once an object exists', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), 'public/logo.png'), new Uint8Array([1, 2, 3]));
    });
    const anon = testEnv.unauthenticatedContext();
    await assertSucceeds(getBytes(ref(anon.storage(), 'public/logo.png')));
  });

  it('denies a client write, even authenticated as Super Admin', async () => {
    const admin = testEnv.authenticatedContext('admin1', { role: 'superAdmin', status: 'active' });
    await assertFails(uploadBytes(ref(admin.storage(), 'public/logo.png'), new Uint8Array([1, 2, 3])));
  });
});

describe('private/** and everything else — default deny', () => {
  it('denies unauthenticated read', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(ref(ctx.storage(), 'private/originals/photo.png'), new Uint8Array([1, 2, 3]));
    });
    const anon = testEnv.unauthenticatedContext();
    await assertFails(getBytes(ref(anon.storage(), 'private/originals/photo.png')));
  });

  it('denies a client write, even authenticated as Super Admin', async () => {
    const admin = testEnv.authenticatedContext('admin1', { role: 'superAdmin', status: 'active' });
    await assertFails(uploadBytes(ref(admin.storage(), 'private/originals/photo.png'), new Uint8Array([1, 2, 3])));
  });
});

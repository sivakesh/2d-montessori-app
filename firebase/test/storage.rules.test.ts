/**
 * Positive/negative tests for storage.rules, including feature_media's
 * /private/media/{mediaId}/{fileName} upload rules (SRS MED-01..MED-06),
 * which cross-service-read Firestore (firestore.get()) to re-verify the
 * caller's live role/status — see storage.rules' own comment on that
 * rule for why. Run via `npm run test:against-emulators` from this
 * directory — needs JDK 21+; not executed in this environment (see
 * README "Prerequisites").
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';
import { deleteObject, getBytes, ref, uploadBytes } from 'firebase/storage';

let testEnv: RulesTestEnvironment;

const ONE_PIXEL_PNG_BYTES = new Uint8Array([1, 2, 3]);
const REQUIRED_METADATA = { title: 'Test asset', altText: 'A description of the test asset' };

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    // Distinct project ID per test file — see firestore.rules.test.ts's
    // comment on the same line for why (a real "already started" failure
    // caught by CI when two files shared one project ID).
    projectId: 'demo-montessori-2d-storage-rules',
    // The real ruleset, not a stub — firestore.get() calls from
    // storage.rules are admin-level cross-service reads that bypass
    // Firestore's own rules regardless, but loading the real file avoids
    // any doubt about that and matches every other rules-test file's
    // convention of testing against the actual deployed rules.
    firestore: {
      rules: readFileSync(join(__dirname, '..', 'firestore.rules'), 'utf8'),
      host: 'localhost',
      port: 8080,
    },
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

afterEach(async () => {
  await testEnv.clearFirestore();
});

async function seedUserDoc(uid: string, data: Record<string, unknown>): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users', uid), data);
  });
}

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

describe('private/media/{mediaId}/{fileName} — feature_media uploads (SRS MED-01..MED-06)', () => {
  it('allows an active Editor to upload an approved image with required accessibility metadata', async () => {
    await seedUserDoc('editor1', { email: 'editor1@example.test', role: 'editor', status: 'active' });
    const editor = testEnv.authenticatedContext('editor1', { role: 'editor', status: 'active' });
    await assertSucceeds(
      uploadBytes(ref(editor.storage(), 'private/media/m1/original.png'), ONE_PIXEL_PNG_BYTES, {
        contentType: 'image/png',
        customMetadata: { ...REQUIRED_METADATA, uploadedBy: 'editor1' },
      }),
    );
  });

  it('allows an approved video upload under the video size limit', async () => {
    await seedUserDoc('pub1', { email: 'pub1@example.test', role: 'publisher', status: 'active' });
    const publisher = testEnv.authenticatedContext('pub1', { role: 'publisher', status: 'active' });
    await assertSucceeds(
      uploadBytes(ref(publisher.storage(), 'private/media/m2/original.mp4'), ONE_PIXEL_PNG_BYTES, {
        contentType: 'video/mp4',
        customMetadata: { ...REQUIRED_METADATA, uploadedBy: 'pub1' },
      }),
    );
  });

  it('allows an approved PDF document upload under the document size limit', async () => {
    await seedUserDoc('pub1', { email: 'pub1@example.test', role: 'publisher', status: 'active' });
    const publisher = testEnv.authenticatedContext('pub1', { role: 'publisher', status: 'active' });
    await assertSucceeds(
      uploadBytes(ref(publisher.storage(), 'private/media/m3/original.pdf'), ONE_PIXEL_PNG_BYTES, {
        contentType: 'application/pdf',
        customMetadata: { ...REQUIRED_METADATA, uploadedBy: 'pub1' },
      }),
    );
  });

  it('denies an unauthenticated upload', async () => {
    const anon = testEnv.unauthenticatedContext();
    await assertFails(
      uploadBytes(ref(anon.storage(), 'private/media/m1/original.png'), ONE_PIXEL_PNG_BYTES, {
        contentType: 'image/png',
        customMetadata: { ...REQUIRED_METADATA, uploadedBy: 'anon' },
      }),
    );
  });

  it('denies a suspended user even with a cached "active" claim (live Firestore status wins)', async () => {
    await seedUserDoc('editor1', { email: 'editor1@example.test', role: 'editor', status: 'suspended' });
    const editor = testEnv.authenticatedContext('editor1', { role: 'editor', status: 'active' });
    await assertFails(
      uploadBytes(ref(editor.storage(), 'private/media/m1/original.png'), ONE_PIXEL_PNG_BYTES, {
        contentType: 'image/png',
        customMetadata: { ...REQUIRED_METADATA, uploadedBy: 'editor1' },
      }),
    );
  });

  it('denies uploading with someone else’s uid as uploadedBy', async () => {
    await seedUserDoc('editor1', { email: 'editor1@example.test', role: 'editor', status: 'active' });
    const editor = testEnv.authenticatedContext('editor1', { role: 'editor', status: 'active' });
    await assertFails(
      uploadBytes(ref(editor.storage(), 'private/media/m1/original.png'), ONE_PIXEL_PNG_BYTES, {
        contentType: 'image/png',
        customMetadata: { ...REQUIRED_METADATA, uploadedBy: 'someone-else' },
      }),
    );
  });

  it('denies an upload missing alt text', async () => {
    await seedUserDoc('editor1', { email: 'editor1@example.test', role: 'editor', status: 'active' });
    const editor = testEnv.authenticatedContext('editor1', { role: 'editor', status: 'active' });
    await assertFails(
      uploadBytes(ref(editor.storage(), 'private/media/m1/original.png'), ONE_PIXEL_PNG_BYTES, {
        contentType: 'image/png',
        customMetadata: { title: 'Test asset', altText: '', uploadedBy: 'editor1' },
      }),
    );
  });

  it('denies an upload missing a title', async () => {
    await seedUserDoc('editor1', { email: 'editor1@example.test', role: 'editor', status: 'active' });
    const editor = testEnv.authenticatedContext('editor1', { role: 'editor', status: 'active' });
    await assertFails(
      uploadBytes(ref(editor.storage(), 'private/media/m1/original.png'), ONE_PIXEL_PNG_BYTES, {
        contentType: 'image/png',
        customMetadata: { title: '', altText: 'A description', uploadedBy: 'editor1' },
      }),
    );
  });

  it('denies an unapproved MIME type', async () => {
    await seedUserDoc('editor1', { email: 'editor1@example.test', role: 'editor', status: 'active' });
    const editor = testEnv.authenticatedContext('editor1', { role: 'editor', status: 'active' });
    await assertFails(
      uploadBytes(ref(editor.storage(), 'private/media/m1/original.exe'), ONE_PIXEL_PNG_BYTES, {
        contentType: 'application/x-msdownload',
        customMetadata: { ...REQUIRED_METADATA, uploadedBy: 'editor1' },
      }),
    );
  });

  it('denies an image over the approved size limit', async () => {
    await seedUserDoc('editor1', { email: 'editor1@example.test', role: 'editor', status: 'active' });
    const editor = testEnv.authenticatedContext('editor1', { role: 'editor', status: 'active' });
    const oversized = new Uint8Array(11 * 1024 * 1024); // 11MB > the 10MB image limit
    await assertFails(
      uploadBytes(ref(editor.storage(), 'private/media/m1/original.png'), oversized, {
        contentType: 'image/png',
        customMetadata: { ...REQUIRED_METADATA, uploadedBy: 'editor1' },
      }),
    );
  });

  it('denies reading a private media original, even by its own uploader', async () => {
    await seedUserDoc('editor1', { email: 'editor1@example.test', role: 'editor', status: 'active' });
    const editor = testEnv.authenticatedContext('editor1', { role: 'editor', status: 'active' });
    await uploadBytes(ref(editor.storage(), 'private/media/m1/original.png'), ONE_PIXEL_PNG_BYTES, {
      contentType: 'image/png',
      customMetadata: { ...REQUIRED_METADATA, uploadedBy: 'editor1' },
    });
    await assertFails(getBytes(ref(editor.storage(), 'private/media/m1/original.png')));
  });

  it('denies deleting a private media original directly', async () => {
    await seedUserDoc('editor1', { email: 'editor1@example.test', role: 'editor', status: 'active' });
    const editor = testEnv.authenticatedContext('editor1', { role: 'editor', status: 'active' });
    await uploadBytes(ref(editor.storage(), 'private/media/m1/original.png'), ONE_PIXEL_PNG_BYTES, {
      contentType: 'image/png',
      customMetadata: { ...REQUIRED_METADATA, uploadedBy: 'editor1' },
    });
    await assertFails(deleteObject(ref(editor.storage(), 'private/media/m1/original.png')));
  });
});

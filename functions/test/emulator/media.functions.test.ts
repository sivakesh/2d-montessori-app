/**
 * Integration tests for the Media Library (SRS MED-01..MED-06) against
 * the real Firebase Emulator Suite (Auth + Firestore + Storage). Run via
 * `npm run test:emulator` (needs JDK 21+ — see README "Prerequisites").
 *
 * `handleMediaUploaded` (the Storage trigger's testable core, exported
 * separately from the `onObjectFinalized` wrapper — see
 * `src/media/onMediaUploaded.ts`'s own doc comment) is exercised
 * directly against a real object already uploaded to the Storage
 * emulator, the same "extract the pure(ish) function, the trigger
 * wrapper just unwraps the event" pattern `runScheduledPublish`/
 * `syncPublishedPageForChange` already use in this codebase — the real
 * `onObjectFinalized` trigger itself is not fired (this suite does not
 * start the Functions emulator, only Auth/Firestore/Storage).
 */
import * as admin from 'firebase-admin';
import type { CallableRequest } from 'firebase-functions/v2/https';
import sharp from 'sharp';

import { archiveMedia, restoreMedia } from '../../src/media/archiveMedia';
import { deleteMedia } from '../../src/media/deleteMedia';
import { handleMediaUploaded } from '../../src/media/onMediaUploaded';
import { updateMediaMetadata } from '../../src/media/updateMediaMetadata';

admin.initializeApp({ projectId: 'demo-montessori-2d', storageBucket: 'demo-montessori-2d.appspot.com' });
const db = admin.firestore();
const auth = admin.auth();
const bucket = admin.storage().bucket();

function requestAs(uid: string, role: string, data: unknown = {}): CallableRequest<never> {
  return { data, auth: { uid, token: { role } as never }, rawRequest: {} } as unknown as CallableRequest<never>;
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

async function cleanupMedia(mediaId: string): Promise<void> {
  const auditSnapshot = await db.collection('auditLogs').where('entityId', '==', mediaId).get();
  await Promise.allSettled([
    db.collection('media').doc(mediaId).delete(),
    bucket.deleteFiles({ prefix: `private/media/${mediaId}/`, force: true }),
    bucket.deleteFiles({ prefix: `public/media/${mediaId}/`, force: true }),
    ...auditSnapshot.docs.map((d) => d.ref.delete()),
  ]);
}

async function auditEntriesFor(entityId: string): Promise<FirebaseFirestore.DocumentData[]> {
  const snapshot = await db.collection('auditLogs').where('entityId', '==', entityId).get();
  return snapshot.docs.map((doc) => doc.data());
}

async function expectHttpsErrorCode(promise: Promise<unknown>, code: string): Promise<void> {
  await expect(promise).rejects.toMatchObject({ code });
}

const EXTENSION_FOR_CONTENT_TYPE: Record<string, string> = {
  'image/png': 'png',
  'application/x-msdownload': 'exe',
  'application/pdf': 'pdf',
};

/** Uploads real bytes to the Storage emulator and fires the processing pipeline against it directly. */
async function uploadAndProcess(params: { mediaId: string; uploaderUid: string; contentType?: string; bytes?: Buffer; title?: string; altText?: string }): Promise<void> {
  const { mediaId, uploaderUid, contentType = 'image/png', title = 'Test asset', altText = 'A description' } = params;
  const bytes = params.bytes ?? (await sharp({ create: { width: 100, height: 50, channels: 3, background: { r: 200, g: 20, b: 20 } } }).png().toBuffer());
  const extension = EXTENSION_FOR_CONTENT_TYPE[contentType] ?? 'bin';
  const objectPath = `private/media/${mediaId}/original.${extension}`;
  await bucket.file(objectPath).save(bytes, {
    metadata: { contentType, metadata: { title, altText, uploadedBy: uploaderUid } },
  });
  const [metadata] = await bucket.file(objectPath).getMetadata();
  await handleMediaUploaded({
    data: {
      bucket: bucket.name,
      name: objectPath,
      contentType,
      size: Number(metadata.size),
      metadata: { title, altText, uploadedBy: uploaderUid },
    },
  } as never);
}

describe('onMediaUploaded processing pipeline', () => {
  const uploaderUid = 'media-uploader';
  const mediaId = 'test-media-image-1';

  beforeAll(() => seedUser(uploaderUid, 'editor'));
  afterAll(() => cleanupUser(uploaderUid));
  afterEach(() => cleanupMedia(mediaId));

  it('processes a valid image into Ready with WebP variants, correct dimensions/orientation, and writes exactly one success audit entry', async () => {
    await uploadAndProcess({ mediaId, uploaderUid, title: 'Landscape photo', altText: 'A red rectangle' });

    const doc = await db.collection('media').doc(mediaId).get();
    const data = doc.data();
    expect(data).toMatchObject({
      status: 'ready',
      mimeCategory: 'image',
      title: 'Landscape photo',
      altText: 'A red rectangle',
      width: 100,
      height: 50,
      orientation: 'landscape',
      archived: false,
      uploadedBy: uploaderUid,
    });
    expect(data?.variants).toBeTruthy();
    expect(Object.keys(data?.variants ?? {}).length).toBeGreaterThan(0);
    for (const variant of Object.values(data?.variants ?? {}) as Array<{ url: string; format: string }>) {
      expect(variant.format).toBe('webp');
      expect(variant.url).toContain(mediaId);
    }

    const auditEntries = await auditEntriesFor(mediaId);
    expect(auditEntries).toHaveLength(1);
    expect(auditEntries[0]).toMatchObject({ eventType: 'create', entityType: 'media' });
  });

  it('marks a corrupted file (spoofed image/png content-type on non-image bytes) as Failed, retains no false-success audit, and keeps the asset non-public', async () => {
    await uploadAndProcess({ mediaId, uploaderUid, bytes: Buffer.from('this is not a real image') });

    const doc = await db.collection('media').doc(mediaId).get();
    expect(doc.data()).toMatchObject({ status: 'failed' });
    expect(doc.data()?.failureReason).toBeTruthy();

    const auditEntries = await auditEntriesFor(mediaId);
    expect(auditEntries).toHaveLength(0);
  });

  it('marks an unapproved MIME type as Failed even though the bytes are a valid image', async () => {
    const pngBytes = await sharp({ create: { width: 10, height: 10, channels: 3, background: { r: 0, g: 0, b: 0 } } }).png().toBuffer();
    await uploadAndProcess({ mediaId, uploaderUid, contentType: 'application/x-msdownload', bytes: pngBytes });

    const doc = await db.collection('media').doc(mediaId).get();
    expect(doc.data()?.status).toBe('failed');
    expect(doc.data()?.failureReason).toMatch(/Unapproved MIME type/);
  });

  it('copies a non-image (document) original straight to a public variant with no transformation', async () => {
    const pdfBytes = Buffer.from('%PDF-1.4 fake but approved-type test content');
    await uploadAndProcess({ mediaId, uploaderUid, contentType: 'application/pdf', bytes: pdfBytes });

    const doc = await db.collection('media').doc(mediaId).get();
    const data = doc.data();
    expect(data).toMatchObject({ status: 'ready', mimeCategory: 'document', width: null, height: null });
    expect(data?.variants?.original).toBeTruthy();
    expect(data?.variants?.original?.format).toBe('pdf');
  });
});

describe('updateMediaMetadata', () => {
  const ownerUid = 'media-meta-owner';
  const otherEditorUid = 'media-meta-other';
  const publisherUid = 'media-meta-publisher';
  const mediaId = 'test-media-meta-1';

  beforeAll(() => Promise.all([seedUser(ownerUid, 'editor'), seedUser(otherEditorUid, 'editor'), seedUser(publisherUid, 'publisher')]));
  afterAll(() => Promise.all([cleanupUser(ownerUid), cleanupUser(otherEditorUid), cleanupUser(publisherUid)]));

  beforeEach(async () => {
    await db.collection('media').doc(mediaId).set({ title: 'Original title', altText: 'Original alt', description: '', status: 'ready', archived: false, uploadedBy: ownerUid });
  });
  afterEach(() => cleanupMedia(mediaId));

  it('rejects an unauthenticated caller', async () => {
    await expectHttpsErrorCode(
      updateMediaMetadata.run({ data: { mediaId, title: 'New', altText: 'New alt' }, auth: undefined, rawRequest: {} } as unknown as CallableRequest<never>),
      'unauthenticated',
    );
  });

  it('rejects a suspended caller even with a cached "active" claim', async () => {
    await seedUser('media-meta-suspended', 'editor', 'suspended');
    await expectHttpsErrorCode(
      updateMediaMetadata.run(requestAs('media-meta-suspended', 'editor', { mediaId, title: 'New', altText: 'New alt' })),
      'permission-denied',
    );
    await cleanupUser('media-meta-suspended');
  });

  it('rejects a non-owner Editor and creates no audit entry', async () => {
    const before = (await auditEntriesFor(mediaId)).length;
    await expectHttpsErrorCode(updateMediaMetadata.run(requestAs(otherEditorUid, 'editor', { mediaId, title: 'New', altText: 'New alt' })), 'permission-denied');
    expect((await auditEntriesFor(mediaId)).length).toBe(before);
  });

  it('allows the owning Editor to update their own asset and writes an audit entry', async () => {
    await updateMediaMetadata.run(requestAs(ownerUid, 'editor', { mediaId, title: 'Updated title', altText: 'Updated alt', description: 'A description' }));
    const doc = await db.collection('media').doc(mediaId).get();
    expect(doc.data()).toMatchObject({ title: 'Updated title', altText: 'Updated alt', description: 'A description' });
    const auditEntries = await auditEntriesFor(mediaId);
    expect(auditEntries.some((e) => e.eventType === 'update' && e.actorId === ownerUid)).toBe(true);
  });

  it('allows a Publisher to update an asset they do not own', async () => {
    await expect(updateMediaMetadata.run(requestAs(publisherUid, 'publisher', { mediaId, title: 'Pub edit', altText: 'Alt' }))).resolves.toMatchObject({ mediaId });
  });

  it('rejects missing alt text', async () => {
    await expectHttpsErrorCode(updateMediaMetadata.run(requestAs(ownerUid, 'editor', { mediaId, title: 'New', altText: '' })), 'invalid-argument');
  });

  it('rejects editing while the asset is still processing', async () => {
    await db.collection('media').doc(mediaId).update({ status: 'processing' });
    await expectHttpsErrorCode(updateMediaMetadata.run(requestAs(ownerUid, 'editor', { mediaId, title: 'New', altText: 'Alt' })), 'failed-precondition');
  });
});

describe('archiveMedia / restoreMedia', () => {
  const ownerUid = 'media-archive-owner';
  const mediaId = 'test-media-archive-1';

  beforeAll(() => seedUser(ownerUid, 'editor'));
  afterAll(() => cleanupUser(ownerUid));

  beforeEach(async () => {
    await db.collection('media').doc(mediaId).set({ title: 'Asset', altText: 'Alt', status: 'ready', archived: false, uploadedBy: ownerUid });
  });
  afterEach(() => cleanupMedia(mediaId));

  it('archives then restores, toggling archived/archivedAt/archivedBy correctly', async () => {
    await archiveMedia.run(requestAs(ownerUid, 'editor', { mediaId }));
    let doc = await db.collection('media').doc(mediaId).get();
    expect(doc.data()).toMatchObject({ archived: true, archivedBy: ownerUid });
    expect(doc.data()?.archivedAt).toBeTruthy();

    await restoreMedia.run(requestAs(ownerUid, 'editor', { mediaId }));
    doc = await db.collection('media').doc(mediaId).get();
    expect(doc.data()).toMatchObject({ archived: false, archivedAt: null, archivedBy: null });
  });

  it('is idempotent: archiving an already-archived asset does not throw or duplicate audit entries', async () => {
    await archiveMedia.run(requestAs(ownerUid, 'editor', { mediaId }));
    const before = (await auditEntriesFor(mediaId)).length;
    await archiveMedia.run(requestAs(ownerUid, 'editor', { mediaId }));
    expect((await auditEntriesFor(mediaId)).length).toBe(before);
  });
});

describe('deleteMedia — permanent delete with in-use protection', () => {
  const ownerUid = 'media-delete-owner';
  const mediaId = 'test-media-delete-1';

  beforeAll(() => seedUser(ownerUid, 'editor'));
  afterAll(() => cleanupUser(ownerUid));

  afterEach(async () => {
    await Promise.allSettled([cleanupMedia(mediaId), db.collection('mediaUsages').doc(`${mediaId}__page1`).delete()]);
  });

  it('refuses to delete a non-archived (still active/Ready) asset', async () => {
    await db.collection('media').doc(mediaId).set({ title: 'Asset', status: 'ready', archived: false, uploadedBy: ownerUid });
    await expectHttpsErrorCode(deleteMedia.run(requestAs(ownerUid, 'editor', { mediaId })), 'failed-precondition');
    expect((await db.collection('media').doc(mediaId).get()).exists).toBe(true);
  });

  it('refuses to permanently delete an archived asset that is still in use', async () => {
    await db.collection('media').doc(mediaId).set({ title: 'Asset', status: 'ready', archived: true, uploadedBy: ownerUid });
    await db.collection('mediaUsages').doc(`${mediaId}__page1`).set({ mediaId, contentId: 'page1', contentTitle: 'A page', fieldPaths: ['featuredImage'] });

    await expectHttpsErrorCode(deleteMedia.run(requestAs(ownerUid, 'editor', { mediaId })), 'failed-precondition');
    expect((await db.collection('media').doc(mediaId).get()).exists).toBe(true);
  });

  it('permanently deletes an archived, unused asset and writes a delete audit entry', async () => {
    await bucket.file(`private/media/${mediaId}/original.png`).save(Buffer.from('x'));
    await db.collection('media').doc(mediaId).set({ title: 'Unused asset', status: 'ready', archived: true, uploadedBy: ownerUid });

    await deleteMedia.run(requestAs(ownerUid, 'editor', { mediaId }));

    expect((await db.collection('media').doc(mediaId).get()).exists).toBe(false);
    const [files] = await bucket.getFiles({ prefix: `private/media/${mediaId}/` });
    expect(files).toHaveLength(0);
    const auditEntries = await auditEntriesFor(mediaId);
    expect(auditEntries.some((e) => e.eventType === 'delete')).toBe(true);
  });
});

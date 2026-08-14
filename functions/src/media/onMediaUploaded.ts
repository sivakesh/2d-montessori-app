/**
 * The processing pipeline (SRS MED-01..MED-06's Uploading -> Processing
 * -> Ready/Failed lifecycle). Fires once an original finishes uploading
 * to `private/media/{mediaId}/original.<ext>` (gated by storage.rules —
 * see that file's comment for why no signed URL / upload-brokering
 * callable is used). This function is the ONLY writer of `media/{id}`
 * documents and the ONLY writer of `public/media/**` — clients never
 * write either directly, which is what makes "approved for public
 * access" a property of what this trusted function chose to generate,
 * not of anything a client controls.
 *
 * Region deliberately left unset — see
 * docs/architecture/environments.md's "Cloud Functions region policy"
 * for why a Storage trigger's region must match its *bucket's* location
 * (an Eventarc co-location constraint, the same class of constraint that
 * required pinning `pagesFns-syncPublishedPage`'s region explicitly) and
 * why that must be confirmed against the real project before being
 * pinned, not guessed — this is a required pre-deploy verification step,
 * not an oversight.
 */
import type { Bucket } from '@google-cloud/storage';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { onObjectFinalized, type StorageEvent } from 'firebase-functions/v2/storage';
import sharp from 'sharp';

import { writeAuditEvent } from '../lib/audit';
import { originalStoragePath, publicVariantStoragePath } from './mediaPath';
import { approvedMediaTypeFor } from './validators';

const ORIGINAL_PATH_PATTERN = /^private\/media\/([^/]+)\/original\.[^./]+$/;

/** Responsive widths generated for images, largest first — capped to the source image's actual width, never upscaled. */
const RESPONSIVE_WIDTHS = [1920, 1024, 640, 320];

interface MediaVariant {
  storagePath: string;
  url: string;
  width: number | null;
  height: number | null;
  format: string;
}

async function makePublicAndGetUrl(bucket: Bucket, path: string): Promise<string> {
  const file = bucket.file(path);
  await file.makePublic();
  return `https://storage.googleapis.com/${bucket.name}/${path}`;
}

async function processImage(params: { bucket: Bucket; mediaId: string; originalBuffer: Buffer }): Promise<{ width: number; height: number; variants: Record<string, MediaVariant> }> {
  const { bucket, mediaId, originalBuffer } = params;
  // sharp() itself validates the actual image signature/structure via
  // libvips — a corrupted or mislabeled file throws here, which is the
  // real, non-spoofable corruption check (a client-declared contentType
  // header proves nothing about the actual bytes).
  const image = sharp(originalBuffer, { failOn: 'error' });
  const metadata = await image.metadata();
  const width = metadata.width ?? 0;
  const height = metadata.height ?? 0;
  if (width <= 0 || height <= 0) {
    throw new Error('Image has no readable dimensions.');
  }

  const variants: Record<string, MediaVariant> = {};
  const widthsToGenerate = [...new Set(RESPONSIVE_WIDTHS.filter((w) => w <= width))];
  if (widthsToGenerate.length === 0) widthsToGenerate.push(width);

  for (const targetWidth of widthsToGenerate) {
    const resized = targetWidth === width ? image.clone() : image.clone().resize({ width: targetWidth });
    const webpBuffer = await resized.webp({ quality: 82 }).toBuffer();
    const variantPath = publicVariantStoragePath(mediaId, `w${targetWidth}.webp`);
    await bucket.file(variantPath).save(webpBuffer, { contentType: 'image/webp' });
    const url = await makePublicAndGetUrl(bucket, variantPath);
    const resizedMeta = await sharp(webpBuffer).metadata();
    variants[`w${targetWidth}`] = {
      storagePath: variantPath,
      url,
      width: resizedMeta.width ?? targetWidth,
      height: resizedMeta.height ?? null,
      format: 'webp',
    };
  }

  return { width, height, variants };
}

async function copyOriginalToPublic(params: { bucket: Bucket; originalPath: string; mediaId: string; fileExtension: string }): Promise<MediaVariant> {
  const { bucket, originalPath, mediaId, fileExtension } = params;
  const destinationPath = publicVariantStoragePath(mediaId, `original.${fileExtension}`);
  await bucket.file(originalPath).copy(bucket.file(destinationPath));
  const url = await makePublicAndGetUrl(bucket, destinationPath);
  return { storagePath: destinationPath, url, width: null, height: null, format: fileExtension };
}

function orientationFor(width: number, height: number): 'landscape' | 'portrait' | 'square' {
  if (width === height) return 'square';
  return width > height ? 'landscape' : 'portrait';
}

export async function handleMediaUploaded(event: StorageEvent): Promise<void> {
  const objectName = event.data.name;
  const match = ORIGINAL_PATH_PATTERN.exec(objectName);
  if (!match) return; // Not a media original (e.g. a public/** derivative this same function just wrote) — ignore.

  const mediaId = match[1] as string;
  const db = getFirestore();
  const mediaRef = db.collection('media').doc(mediaId);
  const storage = getStorage();
  const bucket = storage.bucket(event.data.bucket);

  const contentType = event.data.contentType ?? '';
  const fileSizeBytes = event.data.size;
  const customMetadata = event.data.metadata ?? {};
  const title = customMetadata.title ?? '';
  const altText = customMetadata.altText ?? '';
  const description = customMetadata.description ?? '';
  const uploadedBy = customMetadata.uploadedBy ?? '';
  const fileName = objectName.split('/').pop() ?? objectName;
  const fileExtension = fileName.includes('.') ? (fileName.split('.').pop() as string) : 'bin';

  const approvedType = approvedMediaTypeFor(contentType);

  await mediaRef.set(
    {
      mediaId,
      fileName,
      title,
      description,
      altText,
      mimeType: contentType,
      mimeCategory: approvedType?.category ?? null,
      fileSizeBytes,
      status: 'processing',
      failureReason: null,
      archived: false,
      storagePath: originalStoragePath(mediaId, fileExtension),
      uploadedBy,
      uploadedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: uploadedBy,
    },
    { merge: true },
  );

  try {
    if (!approvedType) {
      throw new Error(`Unapproved MIME type: ${contentType}`);
    }
    if (fileSizeBytes > approvedType.maxSizeBytes) {
      throw new Error(`File size ${fileSizeBytes} exceeds the ${approvedType.category} limit of ${approvedType.maxSizeBytes} bytes.`);
    }

    let width: number | null = null;
    let height: number | null = null;
    let orientation: 'landscape' | 'portrait' | 'square' | null = null;
    let variants: Record<string, MediaVariant>;

    if (approvedType.category === 'image') {
      const [originalBuffer] = await bucket.file(objectName).download();
      const result = await processImage({ bucket, mediaId, originalBuffer });
      width = result.width;
      height = result.height;
      orientation = orientationFor(result.width, result.height);
      variants = result.variants;
    } else {
      // Video/document: no transformation in Phase 1 (automatic video
      // processing/thumbnails are explicitly deferred) — the original
      // itself becomes the servable public asset, unmodified.
      const variant = await copyOriginalToPublic({ bucket, originalPath: objectName, mediaId, fileExtension });
      variants = { original: variant };
    }

    await mediaRef.update({
      status: 'ready',
      width,
      height,
      orientation,
      variants,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: uploadedBy,
    });

    // Audit only the real outcome — a "create" audit entry means
    // processing genuinely succeeded, never written speculatively before
    // that's known (SRS NFR-07 "no false-success audit").
    await writeAuditEvent({
      eventType: 'create',
      entityType: 'media',
      entityId: mediaId,
      actorId: uploadedBy || 'system',
      actorRole: 'system',
      changeSummary: `Media "${title || fileName}" processed and ready`,
      requestId: `media-upload-${mediaId}`,
      source: 'function',
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`Media processing failed for media/${mediaId}`, error);
    await mediaRef.update({
      status: 'failed',
      failureReason: message,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: uploadedBy,
    });
    // Deliberately no audit entry here — nothing succeeded, so nothing
    // should read as an audited event; the Firestore doc's own
    // status:'failed'/failureReason is the visible, retryable record
    // (mirrors runScheduledPublish.ts's own "no audit on failure,
    // document state itself is the record" reasoning).
  }
}

export const onMediaUploaded = onObjectFinalized(async (event) => {
  await handleMediaUploaded(event);
});

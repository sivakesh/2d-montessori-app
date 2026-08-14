/**
 * Cloud Storage path conventions for the Media Library. Centralized here
 * so every module (`onMediaUploaded.ts`, `deleteMedia.ts`,
 * `usageTracking.ts`, and `pages/updatePageContent.ts`'s usage
 * reconciliation) agrees on the exact shape rather than hand-building
 * path strings independently.
 *
 * `MediaReference.storagePath` (the preserved, unmodified contract in
 * `packages/feature_pages`) is the pointer this module derives a
 * `mediaId` back out of — it always holds the *original's* path, never a
 * derivative's, giving every `MediaReference` a stable, single way back
 * to its owning `media/{mediaId}` document regardless of which public
 * variant its `url` field happens to point at.
 */

const ORIGINAL_PATH_PREFIX = 'private/media/';

export function originalStoragePath(mediaId: string, fileExtension: string): string {
  return `${ORIGINAL_PATH_PREFIX}${mediaId}/original.${fileExtension}`;
}

export function publicVariantStoragePath(mediaId: string, variantFileName: string): string {
  return `public/media/${mediaId}/${variantFileName}`;
}

/** Extracts `mediaId` from a `private/media/{mediaId}/...` path; `undefined` for anything else (including plain external URLs with no `storagePath`). */
export function mediaIdFromStoragePath(storagePath: string | undefined | null): string | undefined {
  if (!storagePath || !storagePath.startsWith(ORIGINAL_PATH_PREFIX)) return undefined;
  const rest = storagePath.slice(ORIGINAL_PATH_PREFIX.length);
  const mediaId = rest.split('/')[0];
  return mediaId && mediaId.length > 0 ? mediaId : undefined;
}

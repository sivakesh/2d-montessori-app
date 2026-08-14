/**
 * Approved file types/sizes and field validation for the Media Library
 * (SRS MED-01..MED-06). `APPROVED_MEDIA_TYPES` is the authoritative,
 * server-side re-check of what `storage.rules`' `isApprovedMediaUpload()`
 * already gates at upload time — hand-synced, not code-shared (same
 * established pattern as `publishing/stateMachine.ts` mirroring
 * `PublishingStateMachine`), since Storage Rules and Cloud Functions are
 * different languages/runtimes. A Storage Rule can only see the
 * client-declared `contentType`/`size` at request time; this file's
 * checks run again in `onMediaUploaded.ts` against the real, now-landed
 * GCS object metadata, which cannot be spoofed by the client the way a
 * request header can.
 */
import { HttpsError } from 'firebase-functions/v2/https';

export type MediaMimeCategory = 'image' | 'video' | 'document';

export interface ApprovedMediaType {
  mimeType: string;
  category: MediaMimeCategory;
  maxSizeBytes: number;
}

const MB = 1024 * 1024;

/** Keep in sync with storage.rules' `isApprovedMediaUpload()`. */
export const APPROVED_MEDIA_TYPES: readonly ApprovedMediaType[] = [
  { mimeType: 'image/jpeg', category: 'image', maxSizeBytes: 10 * MB },
  { mimeType: 'image/png', category: 'image', maxSizeBytes: 10 * MB },
  { mimeType: 'image/webp', category: 'image', maxSizeBytes: 10 * MB },
  { mimeType: 'image/gif', category: 'image', maxSizeBytes: 10 * MB },
  { mimeType: 'video/mp4', category: 'video', maxSizeBytes: 200 * MB },
  { mimeType: 'video/webm', category: 'video', maxSizeBytes: 200 * MB },
  { mimeType: 'application/pdf', category: 'document', maxSizeBytes: 25 * MB },
];

export function approvedMediaTypeFor(mimeType: string): ApprovedMediaType | undefined {
  return APPROVED_MEDIA_TYPES.find((t) => t.mimeType === mimeType);
}

export function validateMediaId(value: unknown): string {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) {
    throw new HttpsError('invalid-argument', 'A valid mediaId is required.');
  }
  return value;
}

export function validateTitle(value: unknown): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'A non-empty title is required.');
  }
  if (value.length > 200) {
    throw new HttpsError('invalid-argument', 'Title must be 200 characters or fewer.');
  }
  return value.trim();
}

export function validateAltText(value: unknown): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new HttpsError('invalid-argument', 'Non-empty accessible alt text is required.');
  }
  if (value.length > 300) {
    throw new HttpsError('invalid-argument', 'Alt text must be 300 characters or fewer.');
  }
  return value.trim();
}

export function validateOptionalDescription(value: unknown): string {
  if (value === undefined || value === null) return '';
  if (typeof value !== 'string') {
    throw new HttpsError('invalid-argument', 'Description must be a string.');
  }
  if (value.length > 2000) {
    throw new HttpsError('invalid-argument', 'Description must be 2000 characters or fewer.');
  }
  return value.trim();
}

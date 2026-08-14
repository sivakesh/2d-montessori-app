/**
 * Keeps `mediaUsages/{mediaId}__{contentId}` (and each affected
 * `media/{mediaId}.usageCount`) in sync with which `MediaReference`s a
 * page's content actually contains — the data behind SRS "usage
 * references showing where an asset is used" and "protection against
 * deleting media currently in use" (`deleteMedia.ts` queries
 * `mediaUsages` directly before allowing a permanent delete).
 *
 * Called from `pages/updatePageContent.ts` inside the *same* transaction
 * as the content write, so a page's saved content and its usage index
 * can never drift apart. Deliberately walks the validated content
 * structurally (any nested object with a `storagePath` string field),
 * not via a hand-maintained list of "every place a `MediaReference` can
 * appear in a `PageSection`" — a future section type that embeds one
 * needs no change here to be picked up correctly.
 */
import type { Transaction, Firestore } from 'firebase-admin/firestore';
import { FieldValue } from 'firebase-admin/firestore';

import { mediaIdFromStoragePath } from './mediaPath';

interface MediaUsageOccurrence {
  mediaId: string;
  fieldPath: string;
}

function collectMediaReferences(value: unknown, path: string, out: MediaUsageOccurrence[]): void {
  if (Array.isArray(value)) {
    value.forEach((item, index) => collectMediaReferences(item, `${path}[${index}]`, out));
    return;
  }
  if (typeof value !== 'object' || value === null) return;

  const map = value as Record<string, unknown>;
  const storagePath = map.storagePath;
  if (typeof storagePath === 'string') {
    const mediaId = mediaIdFromStoragePath(storagePath);
    if (mediaId) out.push({ mediaId, fieldPath: path });
  }
  for (const [key, nested] of Object.entries(map)) {
    collectMediaReferences(nested, path ? `${path}.${key}` : key, out);
  }
}

/** Every `media/{mediaId}` this page's saved content currently references, grouped with the field path(s) it appears at. */
export function collectPageMediaUsage(content: { featuredImage?: unknown; seo?: unknown; sections?: unknown }): Map<string, string[]> {
  const occurrences: MediaUsageOccurrence[] = [];
  collectMediaReferences(content.featuredImage, 'featuredImage', occurrences);
  collectMediaReferences(content.seo, 'seo', occurrences);
  collectMediaReferences(content.sections, 'sections', occurrences);

  const byMediaId = new Map<string, string[]>();
  for (const { mediaId, fieldPath } of occurrences) {
    const existing = byMediaId.get(mediaId);
    if (existing) {
      existing.push(fieldPath);
    } else {
      byMediaId.set(mediaId, [fieldPath]);
    }
  }
  return byMediaId;
}

/**
 * Reconciles `mediaUsages` and `media/{mediaId}.usageCount` for one page
 * from its before/after media-usage sets, inside the given transaction.
 * `contentTitle` is denormalized onto each usage doc purely so a "where
 * is this used" UI can render a list without a fan-out read per result.
 */
export function reconcilePageMediaUsage(params: {
  db: Firestore;
  transaction: Transaction;
  contentId: string;
  contentTitle: string;
  before: Map<string, string[]>;
  after: Map<string, string[]>;
}): void {
  const { db, transaction, contentId, contentTitle, before, after } = params;
  const allMediaIds = new Set([...before.keys(), ...after.keys()]);

  for (const mediaId of allMediaIds) {
    const beforeFieldPaths = before.get(mediaId);
    const afterFieldPaths = after.get(mediaId);
    const usageRef = db.collection('mediaUsages').doc(`${mediaId}__${contentId}`);
    const mediaRef = db.collection('media').doc(mediaId);

    if (afterFieldPaths && afterFieldPaths.length > 0) {
      transaction.set(usageRef, {
        mediaId,
        contentId,
        contentTitle,
        fieldPaths: afterFieldPaths,
        updatedAt: FieldValue.serverTimestamp(),
      });
      if (!beforeFieldPaths || beforeFieldPaths.length === 0) {
        transaction.update(mediaRef, { usageCount: FieldValue.increment(1) });
      }
    } else if (beforeFieldPaths && beforeFieldPaths.length > 0) {
      transaction.delete(usageRef);
      transaction.update(mediaRef, { usageCount: FieldValue.increment(-1) });
    }
  }
}

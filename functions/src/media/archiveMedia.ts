/**
 * Soft-delete (SRS "Archive/recycle-bin behaviour"). Archiving never
 * removes the Firestore doc, the original, or any variant — only sets
 * `archived: true` so the asset drops out of the default library view
 * and picker while staying recoverable via `restoreMedia`. A
 * permanently-in-use asset can still be archived (archiving is
 * reversible and does not affect anything currently rendering it, since
 * `MediaReference.url` already points at the asset's own public variant
 * URLs — only `deleteMedia`, which is irreversible, is blocked while in
 * use).
 */
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { writeAuditEvent } from '../lib/audit';
import { resolveRequestId } from '../lib/requestId';
import { assertActiveCaller } from '../publishing/guards';
import { canManageMediaAsset } from './permissions';
import { validateMediaId } from './validators';

interface ArchiveMediaRequestData {
  mediaId?: unknown;
}

async function setArchived(request: import('firebase-functions/v2/https').CallableRequest<ArchiveMediaRequestData>, archived: boolean): Promise<{ mediaId: string }> {
  const db = getFirestore();
  const caller = await assertActiveCaller(request, db);
  const mediaId = validateMediaId(request.data.mediaId);
  const mediaRef = db.collection('media').doc(mediaId);

  // Only audit a real state change — calling this twice in a row (the
  // idempotent-no-op path below) must not produce a second, misleading
  // "archived"/"restored" audit entry for nothing actually changing.
  const didChange = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(mediaRef);
    const current = snapshot.data();
    if (!snapshot.exists || !current) {
      throw new HttpsError('not-found', 'Media asset not found.');
    }
    if (!canManageMediaAsset(caller.role, caller.uid, current.uploadedBy as string)) {
      throw new HttpsError('permission-denied', 'You do not have permission to modify this asset.');
    }
    if (current.archived === archived) {
      return false; // Idempotent no-op.
    }
    transaction.update(mediaRef, {
      archived,
      archivedAt: archived ? FieldValue.serverTimestamp() : null,
      archivedBy: archived ? caller.uid : null,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: caller.uid,
    });
    return true;
  });

  if (didChange) {
    await writeAuditEvent({
      eventType: archived ? 'archive' : 'restore',
      entityType: 'media',
      entityId: mediaId,
      actorId: caller.uid,
      actorRole: caller.role,
      changeSummary: archived ? 'Archived media asset' : 'Restored media asset',
      requestId: resolveRequestId(request, mediaId),
      source: 'function',
    });
  }

  return { mediaId };
}

export const archiveMedia = onCall<ArchiveMediaRequestData, ReturnType<typeof setArchived>>((request) => setArchived(request, true));

export const restoreMedia = onCall<ArchiveMediaRequestData, ReturnType<typeof setArchived>>((request) => setArchived(request, false));

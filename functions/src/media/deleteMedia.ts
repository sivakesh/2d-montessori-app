/**
 * Permanent delete — the recycle-bin's "empty" action (SRS "Archive/
 * recycle-bin behaviour" + "Protection against deleting media currently
 * in use"). Two hard gates, both required: the asset must already be
 * archived (ordinary "delete" from the library is `archiveMedia`, a
 * reversible soft-delete; this is the separate, irreversible action only
 * reachable from within the recycle-bin view), and it must have zero
 * live usage references — checked by *querying* `mediaUsages` directly,
 * not by trusting the denormalized `usageCount` display field on the
 * media doc, so a counter drift can never silently allow an in-use asset
 * to be deleted.
 */
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { writeAuditEvent } from '../lib/audit';
import { resolveRequestId } from '../lib/requestId';
import { assertActiveCaller } from '../publishing/guards';
import { canManageMediaAsset } from './permissions';
import { validateMediaId } from './validators';

interface DeleteMediaRequestData {
  mediaId?: unknown;
}

interface DeleteMediaResponse {
  mediaId: string;
}

export const deleteMedia = onCall<DeleteMediaRequestData, Promise<DeleteMediaResponse>>(async (request) => {
  const db = getFirestore();
  const caller = await assertActiveCaller(request, db);
  const mediaId = validateMediaId(request.data.mediaId);
  const mediaRef = db.collection('media').doc(mediaId);

  const snapshot = await mediaRef.get();
  const current = snapshot.data();
  if (!snapshot.exists || !current) {
    throw new HttpsError('not-found', 'Media asset not found.');
  }
  if (!canManageMediaAsset(caller.role, caller.uid, current.uploadedBy as string)) {
    throw new HttpsError('permission-denied', 'You do not have permission to delete this asset.');
  }
  if (current.archived !== true) {
    throw new HttpsError('failed-precondition', 'Only an archived asset can be permanently deleted — archive it first.', {
      reason: 'media-not-archived',
    });
  }

  const usageSnapshot = await db.collection('mediaUsages').where('mediaId', '==', mediaId).limit(1).get();
  if (!usageSnapshot.empty) {
    throw new HttpsError('failed-precondition', 'This asset is still in use and cannot be permanently deleted.', {
      reason: 'media-in-use',
    });
  }

  const bucket = getStorage().bucket();
  await Promise.all([
    bucket.deleteFiles({ prefix: `private/media/${mediaId}/`, force: true }),
    bucket.deleteFiles({ prefix: `public/media/${mediaId}/`, force: true }),
  ]);
  await mediaRef.delete();

  await writeAuditEvent({
    eventType: 'delete',
    entityType: 'media',
    entityId: mediaId,
    actorId: caller.uid,
    actorRole: caller.role,
    changeSummary: `Permanently deleted media asset "${(current.title as string) || mediaId}"`,
    requestId: resolveRequestId(request, mediaId),
    source: 'function',
  });

  return { mediaId };
});

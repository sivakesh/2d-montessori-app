/**
 * Edits a media asset's title/description/altText (SRS "File name,
 * title, description and accessible alt text"). Never touches the
 * file/variants themselves — that is `onMediaUploaded.ts`'s job alone.
 */
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';

import { writeAuditEvent } from '../lib/audit';
import { resolveRequestId } from '../lib/requestId';
import { assertActiveCaller } from '../publishing/guards';
import { validateMediaId, validateOptionalDescription, validateAltText, validateTitle } from './validators';
import { canManageMediaAsset } from './permissions';

interface UpdateMediaMetadataRequestData {
  mediaId?: unknown;
  title?: unknown;
  altText?: unknown;
  description?: unknown;
}

interface UpdateMediaMetadataResponse {
  mediaId: string;
}

export const updateMediaMetadata = onCall<UpdateMediaMetadataRequestData, Promise<UpdateMediaMetadataResponse>>(async (request) => {
  const db = getFirestore();
  const caller = await assertActiveCaller(request, db);
  const mediaId = validateMediaId(request.data.mediaId);
  const title = validateTitle(request.data.title);
  const altText = validateAltText(request.data.altText);
  const description = validateOptionalDescription(request.data.description);

  const mediaRef = db.collection('media').doc(mediaId);

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(mediaRef);
    const current = snapshot.data();
    if (!snapshot.exists || !current) {
      throw new HttpsError('not-found', 'Media asset not found.');
    }
    if (current.status !== 'ready' && current.status !== 'failed') {
      throw new HttpsError('failed-precondition', 'This asset cannot be edited while it is still processing.', { reason: 'media-not-editable' });
    }
    if (!canManageMediaAsset(caller.role, caller.uid, current.uploadedBy as string)) {
      throw new HttpsError('permission-denied', 'You do not have permission to edit this asset.');
    }

    transaction.update(mediaRef, {
      title,
      altText,
      description,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: caller.uid,
    });
  });

  await writeAuditEvent({
    eventType: 'update',
    entityType: 'media',
    entityId: mediaId,
    actorId: caller.uid,
    actorRole: caller.role,
    changeSummary: `Updated media metadata for "${title}"`,
    requestId: resolveRequestId(request, mediaId),
    source: 'function',
  });

  return { mediaId };
});

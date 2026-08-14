/**
 * Media Library — Cloud Functions.
 *
 * Traceability: SRS MED-01..MED-06; PRD Section 7 (Media Library)
 *
 * Uploads go directly from the client to Cloud Storage
 * (`private/media/{mediaId}/original.<ext>`), authorized by
 * `firebase/storage.rules` — no upload-brokering callable exists here.
 * `onMediaUploaded` (a Storage trigger, not a callable) is the pipeline
 * that turns a landed original into a processed, publicly-servable
 * `media/{mediaId}` document; every other export here is an ordinary
 * callable for library management once an asset exists.
 */
export const capability = 'media' as const;

export { onMediaUploaded } from './onMediaUploaded';
export { updateMediaMetadata } from './updateMediaMetadata';
export { archiveMedia, restoreMedia } from './archiveMedia';
export { deleteMedia } from './deleteMedia';

// Runs before any test module loads. `onObjectFinalized` (a Storage
// trigger — see src/media/onMediaUploaded.ts) resolves its target bucket
// name eagerly at module-evaluation time from `firebase-functions`'
// `firebaseConfig()`, which reads `process.env.FIREBASE_CONFIG` — set
// automatically inside a real deployed function, `firebase
// emulators:exec`, or `firebase functions:shell`, but not in a plain
// `npm test` Jest run, where merely importing `src/index.ts` (and
// therefore `src/media/onMediaUploaded.ts`) would otherwise throw before
// a single test body even runs. This mirrors exactly what firebase-tools
// itself provides in every other context that already works.
if (!process.env.FIREBASE_CONFIG) {
  process.env.FIREBASE_CONFIG = JSON.stringify({
    projectId: 'demo-montessori-2d',
    storageBucket: 'demo-montessori-2d.appspot.com',
  });
}
if (!process.env.GCLOUD_PROJECT) {
  process.env.GCLOUD_PROJECT = 'demo-montessori-2d';
}

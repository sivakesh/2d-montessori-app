# firebase/

Firestore/Storage rules, indexes and emulator fixtures. `firebase.json` and
`.firebaserc`(`.template`) live at the repository root because the Firebase
CLI requires `firebase.json` at the directory you run `firebase` commands
from; this folder holds the files it points at.

- `firestore.rules` — deny-by-default baseline; public reads only on
  `published*`/`public*` collections. Role-based write rules land in Phase
  1/2. See the top-of-file comments for what's deliberately not implemented
  yet.
- `storage.rules` — deny-by-default; only `/public/**` (written solely by
  trusted Cloud Functions) is client-readable.
- `firestore.indexes.json` — empty placeholder. Composite indexes get added
  as each collection's real query patterns are implemented (PRD §12.1).
- `emulator-fixtures/` — seed data for `firebase emulators:start --import`.
  Empty in Phase 0; populated once feature_identity/feature_pages exist so
  local dev has a default Super Admin + sample content.

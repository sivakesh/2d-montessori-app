# Website CMS: DEV validation plan

This is the plan for validating the public website CMS (Gallery, media
library, page editor, additional pages, consent withdrawal) on the DEV
Firebase project before any production use. See `docs/website_content.md`
for the design and the proposed rules.

> Nothing here has been run against a real Firebase project. Every step
> that changes a project (rules, claims, Auth settings, deploys) needs
> explicit approval from the project owner first.

## 1. Environments

| What | DEV | PROD |
|---|---|---|
| Firebase project | `montessori-app-95988` | `twod-montessori-prod` |
| `.firebaserc` aliases | `default`, `dev`, `montessori-app` | `prod` |
| App build flag | `--dart-define=DEPLOY_TARGET=dev` (also the default when omitted) | `--dart-define=DEPLOY_TARGET=prod` (explicit only) |
| Storage bucket | `montessori-app-95988.firebasestorage.app` | `twod-montessori-prod.firebasestorage.app` |

**Not this app's projects**
- `twod-montessori-dev` belongs to the separate CMS monorepo branch
  (`origin/montessori-cms-monorepo`).
- It is currently the **gcloud CLI's default project** on this machine. Any
  `gcloud` command run without `--project` would go there.
- Always pass `--project montessori-app-95988` explicitly.

**`APP_ENV` and `DEPLOY_TARGET` are independent**
- `DEPLOY_TARGET` picks the Firebase project.
- `APP_ENV` picks behaviour:
  - `dev` (the default in debug builds) uses the dev login: phone number
    only, **no Firebase Auth session**;
  - `prod` (the default in release builds) uses real phone OTP.

## 2. Inspecting the deployed rules safely

- The deployed rules aren't in the repository, and the Firebase CLI has no
  command to download them.
- **Safest:** the project owner opens the Firebase console → Firestore →
  Rules, and Storage → Rules, for `montessori-app-95988`. The Rules page
  shows the current release and its history without changing anything.
  Copy both into a review note.
- **Alternative (read-only API):** the Firebase Rules API
  (`GET https://firebaserules.googleapis.com/v1/projects/montessori-app-95988/releases`,
  then `GET …/rulesets/{id}`). Run it only with the owner's approval and
  always with the explicit project id.
- **Inference to confirm:** the dev login reads and writes Firestore with
  no Auth session, so DEV's current rules must allow unauthenticated
  access to at least `users`. If they are broadly open, the website
  collections are already publicly writable in DEV, and that should be
  fixed with the merged rules.

## 3. Administrator authorization (custom claim)

The proposed rules treat a request as an admin's only when its Firebase
Auth token carries the custom claim **`role: "admin"`**. The tested rules
read it with `request.auth.token.get('role', '')`. If you prefer a boolean
`admin: true`, change both rules files and the emulator tests together.

**Prerequisite: Firebase Auth sign-in**
- A claim can only exist on a Firebase Auth account. The dev login
  (`APP_ENV=dev`) has none, so under the proposed rules dev-login users can
  never edit the website.
- DEV validation of website editing must therefore use the real phone OTP
  login (`APP_ENV=prod`) on the DEV project.
- To avoid sending real SMS, add Firebase Auth test phone numbers with
  fixed codes (Authentication → Sign-in method → Phone). That is a project
  setting change and needs approval.

**Granting** (project owner only, from a trusted machine; never from the
app)
1. Find the admin's Auth uid:
   - `users/{phone}.firebaseAuthUid`, or `prod_users/{phone}.authUid`; or
   - Firebase console → Authentication → Users.
2. Confirm the person really is an administrator. The Firestore `role`
   field alone isn't proof: under DEV's open rules anyone could have
   written it.
3. Set the claim with the Identity Toolkit REST API, using the owner's
   gcloud credentials. No new dependency is needed:
   ```
   curl -X POST \
     -H "Authorization: Bearer $(gcloud auth print-access-token)" \
     -H "x-goog-user-project: montessori-app-95988" \
     -H "Content-Type: application/json" \
     "https://identitytoolkit.googleapis.com/v1/projects/montessori-app-95988/accounts:update" \
     -d '{"localId":"<UID>","customAttributes":"{\"role\":\"admin\"}"}'
   ```
   The Firebase Admin SDK's `setCustomUserClaims` does the same.
   `customAttributes` replaces all of the account's existing claims, so
   include any others the account needs.
4. Record who granted it, for whom, and when, in an admin log outside the
   app.

**Token refresh**
- Claims reach the app only in a new ID token.
- After a grant or revoke, the admin signs out and back in. Otherwise the
  change takes effect within about an hour, when the token refreshes.
- The app does not force a refresh today. A later change could call
  `getIdToken(true)` on opening Settings → Website.

**Revoking**
1. Set `customAttributes` to `{}`, or to the remaining claims.
2. Revoke the account's refresh tokens (`accounts:update` with
   `"validSince"` set to the current time in seconds, or the Admin SDK's
   `revokeRefreshTokens`). This ends existing sessions.
3. Rules don't check revocation themselves, so an issued ID token stays
   valid for up to an hour unless refresh tokens are revoked.

**Migrating existing administrators**
1. List admin accounts:
   - DEV: `users` where `role == 'admin'`;
   - PROD: `prod_users`.
2. Keep only those with an Auth uid. Admins who only ever used the dev login
   have none; they must sign in once with phone OTP.
3. Confirm the list with the school.
4. Grant claims one at a time (above).
5. Have each admin sign in again.
6. Only then deploy the merged rules.

The app's own role checks (`currentUserProvider.role`) stay as they are.
The claim adds server-side enforcement; it doesn't replace them.

## 4. Remaining server-side validation gaps

All of these use Firestore rules and existing app code only, with no
Cloud Functions and no dependencies.

| Gap | Today | Smallest safe implementation |
|---|---|---|
| Maximum 20 sections and allowed fields | Rules check `sections.size() <= 20` only; the app validates the rest. | Add a rules function `isValidSection(s)` checking `s.type` is one of the four types, `s.keys().hasOnly(...)` for that type, and string length limits. Call it for indexes 0–19 using the guard `sections.size() <= i \|\| isValidSection(sections[i])`, since rules can't loop. Extend the emulator tests. |
| Safe button links | Checked only in the app, when saving and before following a link. | Inside `isValidSection`, for `cta`: `s.target.matches('^(/\|/(admissions\|teacher-training\|programs\|gallery\|contact)\|/pages/[a-z0-9]+(-[a-z0-9]+)*\|https://[^/\\s]+(/[^\\s]*)?\|mailto:[^\\s]+\|tel:[+0-9 ()-]+)$')`. The public page keeps re-checking. |
| Unique slugs when two pages are created at once | A query-then-write check in the service, which has a race. | Add a slug registry `website_slugs/{slug}` = `{pageId}`. Write it in the **same batch** as the draft. Rules allow `create` only (a second creator fails because the document exists), deny `update`, and allow `delete` only by the owning page's admin flow. They also require the draft's slug to match: `getAfter(/databases/$(database)/documents/website_slugs/$(slug)).data.pageId == pageId`. A rename deletes the old registry document and creates the new one in one batch. This adds one small collection, which needs approval. |
| Published pages need published images | Checked in the service; the public site drops any image that isn't published. | **No rule needed for privacy.** A draft or hidden image's record isn't publicly readable, so visitors can't get its URL even if a live page refers to it. Enforcing it in rules would need one `get()` per image, over the 10-call limit for pages with many images. If wanted, enforce it only for built-in slots (one image, one `get()`). |
| Consent withdrawal and file deletion | Withdrawal hides the image everywhere at once, the rules refuse "published without consent" (tested), and the files are kept. | (a) **Shorten caching:** uploads currently send `Cache-Control: public, max-age=31536000, immutable`, which lets browsers and shared caches keep a withdrawn photo for up to a year. Use `private, max-age=86400` (or no `immutable`) for new uploads. (b) **Revoke the link:** offer an explicit "Withdraw and delete files" choice that runs the existing delete workflow, which removes the files and so invalidates the download URL. It must stay a deliberate second action, never automatic. |

## 5. Browser test plan (DEV)

**Setup**
- Use **non-identifying sample images only**: abstract shapes, plain
  objects, empty classrooms, no people.
- Prepare one each of:
  - a large JPEG (more than 3000 px wide, with EXIF location data);
  - a PNG with transparency;
  - a WebP;
  - a very tall image (portrait 1:3);
  - a file over 15 MB;
  - a renamed PDF (`.jpg` extension);
  - a GIF.
- Builds:
  - `flutter run -d chrome --dart-define=DEPLOY_TARGET=dev --dart-define=APP_ENV=prod` for real OTP (needed for claim and rules testing);
  - `APP_ENV=dev` for the current DEV behaviour.
- Browsers: Chrome, Safari and Firefox on desktop, plus iOS Safari and
  Android Chrome.

### 5.1 Upload and image handling
1. Upload each file. JPEG, PNG and WebP are accepted. Over 15 MB, PDF and
   GIF are refused with a message.
2. In Firebase console → Storage, open `website_media/<id>/`. Confirm:
   - `_display.jpg` has a long edge of at most 2000 px, and `_thumb.jpg`
     at most 640 px;
   - both are JPEG with the `Cache-Control` header set;
   - file names don't contain the original name.
3. Download the display file and check it has no EXIF data (for example
   `exiftool` or Preview → Show Inspector): no GPS, no camera fields.
4. The transparent PNG renders on a warm-white background, not black.
5. The tall image shows its crop previews correctly. Move the focal point
   and confirm the previews follow it.

### 5.2 Public display
1. With nothing published, check the homepage ornament, the section-page
   placeholders and "Photographs are on their way".
2. Publish two images (alt text plus consent) in different categories:
   - the gallery shows both, with filter chips;
   - captions show, and the lightbox opens, moves next/previous and
     closes (also with Esc and the arrow keys);
   - in DevTools → Network, grid tiles load `_thumb` and the lightbox
     loads `_display`.
3. Set the homepage hero and the Admissions, Teacher Training and Programs
   images and text. The pages show them after a refresh, with no rebuild.
4. Throttle the network to "Slow 3G": placeholders show, then images fade
   in. Block the Storage domain: the "image unavailable" mark shows and
   nothing breaks.
5. If CanvasKit can't draw an image because of CORS, the `<img>` fallback
   is used. Note this, and fix `cors.json` on the bucket (with approval).

### 5.3 Workflows
| Action | Expect |
|---|---|
| Upload | Draft, not public |
| Publish without alt text or consent | Refused with a message |
| Publish | Visible in the gallery and on pages using it |
| Hide, image not used by a live page | Gone from the public site |
| Hide, image used by a live page | Refused, with a message naming the page |
| Replace | Same id; back to draft; consent cleared; old files removed from Storage; pages show their placeholder until it is republished |
| Withdraw consent, image used on 3+ pages | Confirmation names the pages; after confirming, the image is gone from the gallery and every page at once; pages stay published; Pages list shows "Image not shown"; audit entry `consent-withdrawn` in Firestore; files still in Storage |
| Delete, image in use | Refused |
| Delete, image unused | Record, audit entries and both files removed; the old download URL now returns 404 |
| Page editor | Fields prefilled with built-in English and Tamil; "Save draft" leaves the live site unchanged; Publish updates it; Reset restores built-in text; Live/Editing preview and EN/Tamil toggles work |

### 5.4 Additional pages
1. Create "Open Day" (`open-day`). It is a draft: `/pages/open-day` shows
   "Page not found" to signed-out visitors.
2. Try a duplicate slug: refused. Try `Bad Slug`: refused.
3. Add one section of each type. Try a `javascript:` button link: refused.
4. Publish. Signed out, the page renders in English and Tamil.
5. Turn on "Show in navigation" and publish. The page appears before Contact
   in the header, mobile menu and footer. Reorder two pages and check the
   order.
6. Unpublish, then archive. Each time the page shows "Page not found" and
   leaves the navigation. Restore it: it is back as an unpublished draft.

### 5.5 Routing, refresh and back
The site uses clean path URLs (see `docs/website_clean_urls.md`). For
each of `/`, `/gallery`, `/admissions`, `/pages/open-day`,
`/pages/does-not-exist`, `/pages/a/b` and `/app`:
- **Open it directly in a new tab:** the right page shows, and a missing
  page shows "Page not found". The address has no `#`.
- **Refresh:** the same page shows (no hosting 404).
- **Browser back:** it returns to the previous page. A deep link has
  Home underneath. **Forward** returns to the page you came back from.
- **Old links:** `/#/gallery`, `/#/pages/open-day` and `/#/app` open the
  same page, and the address changes to the clean path.
- **Language:** switching EN/தமிழ் keeps the address.
- **Refresh on `/otp`** (during sign-in): known issue, pre-existing, and
  out of scope while authentication is frozen. The page goes blank
  because the phone number is lost; reopen `/login`. Don't count it as a
  regression.

Also check:
- **Login** from the public header opens `/app`, and back returns to the
  site.
- **After signing in**, back doesn't expose a stale dashboard after
  logout.

### 5.6 Site layout (header, navigation and footer)
Desktop (≥1280 px) and mobile (390 px), English and Tamil:
- With no layout published, the header, mobile menu and footer match
  the current site exactly.
- Settings → Website → Site layout opens on the current navigation.
  Edit the site name, tagline, footer text and copyright; the preview
  (Desktop/Mobile, EN/தமிழ்) follows each edit, and a second browser
  window on the public site does not change.
- Save draft: the public site is unchanged after a reload.
- Publish (confirm): after a reload the header, menu and footer show the
  new layout; footer-only links don't appear in the header or menu.
- Hide a link to a published additional page and publish: the link is
  gone, and the page still opens at `/pages/<slug>`.
- A visible link to an unpublished page blocks publishing with a
  message; hiding it allows publishing.
- An external `https://` link opens in a new tab. `http://` links and
  typed app routes (`/app`, `/dashboard`, …) are refused in the link
  dialog.
- Login, Dashboard and Logout behave exactly as before for signed-out,
  parent, staff and admin users, in the header, menu and footer.
- Unpublish (confirm): after a reload the built-in layout is back, the
  draft is still in the editor, and no page was unpublished.
- Refresh and back/forward on public pages, custom pages and `/app`
  still work.

### 5.7 Roles and access (after DEV rules and claims are approved and deployed)
| User | Settings → Website | Direct writes (DevTools console or REST) | Public site |
|---|---|---|---|
| Signed out | n/a | All website writes denied; draft and audit reads denied | Published content only |
| Parent (OTP) | Not reachable | Denied | Published content only |
| Staff (OTP) | Locked view | Denied | Published content only |
| Admin without claim | Opens (app role) but saves fail with permission errors | Denied | Published content only |
| Admin with claim | Full workflow | Allowed within the rule constraints | Published content only |
| Dev-login admin (`APP_ENV=dev`) | Opens, but saves fail (no Auth session) | Denied | Published content only |

Also confirm:
- Finance, Fees, attendance and leave screens still work for each role
  under the merged rules. Merging must not narrow their access by mistake.

## 6. Blockers before DEV rules can be deployed
1. The deployed DEV rules must be inspected (section 2) and the website
   rules merged into them, not deployed alone.
2. Admin claims must be granted (section 3), which needs owner approval.
3. Website editing in DEV needs real phone sign-in or approved test phone
   numbers.
4. Decide on the section 4 items, especially the slug registry and the
   cache header.
5. Storage CORS must be confirmed for the DEV hosting origin.

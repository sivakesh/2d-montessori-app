# Public website content and gallery

How the public website (`lib/modules/public_website`) gets its images and
managed text, and how administrators manage them (Settings → Website,
`lib/modules/admin/website`).

> **Status:** the app code is in place. The Firestore and Storage security
> rules (`test/firebase_rules/`) are a **proposal only**. They are tested
> against the Firebase emulators but have not been applied anywhere. This
> repository does not contain the deployed rules, so compare the proposal
> with the live rules for `montessori-app-95988` and `twod-montessori-prod`
> before deploying anything.

## Data model

Image files are stored separately from the content that describes and uses
them.

### Storage: `website_media/{mediaId}/`

| File | Use |
|---|---|
| `{timestamp}_display.jpg` | Pages and the lightbox. Long edge at most 2000 px. |
| `{timestamp}_thumb.jpg` | Gallery tiles and admin lists. Long edge at most 640 px. |

- In the browser, uploads are re-encoded as JPEG through a canvas. This also
  removes embedded metadata (EXIF), including any GPS location.
- File names are neutral, because an original file name can name a child.
- Files are uploaded with `Cache-Control: public, max-age=31536000, immutable`.
  A replacement is uploaded to a new path and the old files are then deleted.

### Firestore: `website_media/{mediaId}` (the media library)

| Field | Notes |
|---|---|
| `url`, `storagePath` | Download URL and path of the display image |
| `thumbUrl`, `thumbStoragePath` | Download URL and path of the thumbnail |
| `contentType`, `sizeBytes`, `width`, `height` | Of the display image |
| `focalX`, `focalY` | Point to keep in view when cropping, as 0–1 fractions (0.5, 0.5 is the centre) |
| `alt` `{en, ta}` | Alt text: the accessibility description. New uploads start with `en: "2D Montessori"` (Tamil empty), editable at once and later; never taken from the file name, and never written to an existing image. Not a publishing condition, and says nothing about approval or consent (see *Alt text, photo approval, consent and publishing*). |
| `decorative` | Optional, `true` when marked decorative: screen readers skip it; any alt text is kept but not read. Absent on earlier records (not decorative). |
| `caption` `{en, ta}` | Optional; shown in the gallery and lightbox |
| `category` | `general`, `classroom`, `materials`, `outdoors`, `events`, `teacher_training` or `campus` |
| `inGallery` | Whether the image is listed in the gallery. An image can be used only on pages. |
| `galleryOrder` | Integer sort order |
| `status` | `draft`, `published` or `hidden`. Only `published` is ever shown. |
| `consentConfirmed` | One combined attestation: the admin confirmed the photo is **school-approved** and that **consent** was obtained for every identifiable person. Required to publish. `false` on every upload unless the admin confirms it (see below). |
| `createdAt`, `updatedAt`, `publishedAt` | Timestamps |

- A published media document is meant to be publicly readable. For that
  reason it holds **no uploader or editor identity**. User ids in this app
  are phone numbers.
- Changes are recorded in **`website_media/{mediaId}/audit/{entryId}`**
  (`action`, `byId`, `byName`, `at`), which is admin only. Bulk actions
  record each image on its own (`consent-confirmed` from the bulk action has
  `bulk: true`; also `gallery-added`, `gallery-removed`).
- Album membership is **never** on the media record (see below), so
  albums aren't visible to visitors and editing an image can't lose them.

### Firestore: `website_albums/{albumId}` (media library albums, admin only)

| Field | Notes |
|---|---|
| `schoolId` | The school (`default_school`), as for templates. Listing filters on it. |
| `schemaVersion` | 1 |
| `name` | Required, 1–80 characters |
| `description` | Optional, at most 300; not stored while empty |
| `mediaIds` | The images' ids, in the order added (at most 2,000). An image may be in several albums, or none. Changed with `arrayUnion` / `arrayRemove`. |
| `createdAt`, `createdById`, `createdByName`, `updatedAt`, `updatedById`, `updatedByName` | Admin-only record, so editor identity is fine here |

- Albums only organise the library. Adding or removing an image never
  changes its publication, consent or gallery visibility. Deleting an
  album leaves its images as they are.
- A deleted image is taken out of its albums (best effort). An id that is
  still listed is left out of counts and filters (`WebsiteAlbum.availableIn`).
- Photo galleries and Asymmetric galleries can take images from albums
  (docs/website_visual_site_editor.md, "Albums as an image source"). Publishing
  copies the album images visitors may see into the page itself, so this
  record is never public and no public album collection exists.
- **The security rules don't allow this collection yet** (see "Pending rule
  changes"). Until they do, the library shows that albums couldn't be
  loaded, and everything else works.

### Firestore: page content

There is one document per place on the site, keyed by slot: `home` (the
homepage hero), `admissions`, `teacher_training`, `programs` and `gallery`.

| Collection | Visibility | Contents |
|---|---|---|
| `website_page_drafts/{slot}` | Admin only | The editable content, plus `updatedAt`, `updatedById` and `updatedByName` |
| `website_pages/{slot}` | Public | The published content only: `slot`, `imageMediaId`, `headline {en, ta}`, `intro {en, ta}`, `publishedAt` |

- Drafts are kept in a separate collection because security rules can't
  hide individual fields of a document.
- A page refers to its image by media id. That lets one upload be reused on
  several pages and in the gallery, and lets a metadata change reach every
  page that uses the image.

### Built-in text in the page editor

- When nothing is saved for a heading or introduction, the editor fills its
  fields with the site's exact built-in English and Tamil copy, taken from
  `WebsitePageSlot.builtInHeadline` and `builtInIntro`, which read
  `PublicStrings`.
- On save or publish, any heading or introduction pair still identical to the
  built-in copy is stored blank, meaning "use built-in", so the page keeps
  following the built-in copy if it is revised.
- Saved text, including a deliberately blank Tamil field, loads exactly as
  saved.
- The editor states whether it shows built-in content, a saved draft (with
  or without unpublished changes) or the published content.
- Its preview can show the version being edited or the live version, in
  English or Tamil.
- "Reset to built-in content" restores the built-in text and removes the
  image, in the editor only. Nothing reaches the website until the admin
  saves a draft or publishes.

### Additional pages (`/pages/<slug>`)

These reuse the same draft and live collections as the built-in pages. They
are told apart by `kind: 'custom'` and use an automatic document id, so no
new collection is needed and the public site still needs only one query for
all live page documents.

| Field | Draft (`website_page_drafts`) | Live (`website_pages`) |
|---|---|---|
| `kind` | `'custom'` | `'custom'` |
| `slug` | ✓ | ✓ |
| `title {en, ta}` | ✓ | ✓ |
| `intro {en, ta}` | ✓ | ✓ |
| `heroMediaId` | ✓ | ✓ |
| `sections` (see below) | ✓ | ✓ |
| `showInNavigation` | ✓ | ✓ |
| `navOrder` | ✓ | ✓ |
| `mediaIds` (every image used) | ✓ | ✓ |
| `archived` | ✓ | — |
| `createdAt`, `updatedAt`, `updatedById`, `updatedByName` | ✓ | — |
| `publishedAt` | — | ✓ |

**Sections.** There can be up to 20, each with an `id`, `type` and only the
fields that type uses:

| Type | Fields |
|---|---|
| `text` | `heading`, `body` |
| `image_text` | `heading`, `body`, `mediaId`, `imageOnRight` |
| `image_grid` | `heading`, `mediaIds` (up to 24); each image shows its own caption and alt text |
| `cta` | `heading`, `body`, `buttonLabel`, `target` |

All text is `{en, ta}`. A blank Tamil field shows the English text.

**Slugs**
- 2 to 60 characters: lowercase letters, digits and single hyphens.
- Must be unique among drafts and live pages. An archived page keeps its
  slug reserved, so an old link never starts showing a different page.
- Because the client SDK can't run a query inside a transaction, two admins
  creating the same new slug at the same moment isn't prevented.
- Pages live under the `/pages/` prefix, so a slug can never shadow a
  built-in or management route (`/app`, `/admin_dashboard`, …).

**Button links**
- Allowed:
  - this site's public pages: `/`, a built-in section, or `/pages/<slug>`;
  - `https://` links;
  - `mailto:` and `tel:` links.
- Anything else is refused, including `javascript:`, `http:` and management
  routes.
- The public page checks the link again before following it.

**Workflow**
- **Create:** the page starts as a draft with no live copy and is not in the
  navigation.
- **Save draft:** changes the draft only.
- **Publish:** copies the visitor-facing fields to the live copy. Every
  referenced image must be published, and the page must not be archived.
- **Unpublish:** deletes the live copy.
- **Archive:** deletes the live copy and moves the page to "Archived pages".
- **Restore:** brings the page back as an unpublished draft.
- **Navigation:**
  - `showInNavigation` is page content, so it takes effect on publish.
  - `navOrder` is a site setting, so reordering applies immediately to both
    the drafts and the live copies.
  - Listed pages appear after Gallery and before Contact.
- **Images:** an image used by a live additional page can't be hidden, and
  one used by any page can't be deleted. Both checks use `mediaIds`.

**Visitors**
- Only live, non-archived, well-formed pages are shown.
- An unknown, unpublished, archived or malformed slug shows "page not found".
- Drafts are never read by the public site.

### Site layout (`site_layout`): header, navigation and footer

Settings → Website → **Site layout** manages the public header and footer:

- **Site identity:** site name (header and footer) and tagline (footer), in
  English and Tamil. Blank means the built-in wording.
- **Main navigation:** the header links and the mobile menu.
- **Footer navigation:** the footer links, independent of the header (a
  link can be in the footer only).
- **Footer content:** optional footer text and copyright line.

Storage and reads:

- One document, `site_layout` (`kind: 'layout'`, `schemaVersion: 1`):
  the draft in `website_page_drafts/site_layout` (admin only, with editor
  bookkeeping) and the published copy in `website_pages/site_layout`
  (visitor-facing fields only). No new collection and **no extra read**:
  visitors get it with the live pages query below.
- Each link is `{id, label{en,ta}, target, visible}`; its order is its
  position in the list. A target is one of:
  - `{kind: 'builtin', id}` — a built-in page by its slot id (`home`,
    `admissions`, `teacher_training`, `programs`, `gallery`) or `contact`;
  - `{kind: 'page', pageId}` — an additional page by its stable id, so a
    changed address never breaks the link;
  - `{kind: 'external', url}` — a complete `https://` address (opens in a
    new tab).
- Site pages are never typed as paths, so a link can't lead to `/app`,
  `/login`, `/otp`, `/dashboard`, `/admin_*` or a raw `/pages/` address;
  typed addresses like these are refused (`PublicRoutes.isReserved`).
- A blank link label uses the page's own name (the built-in label, or
  the published page's title). External links need an English label.
- Limits: 10 main links, 16 footer links, labels 40 characters, site
  name 60, tagline 160, footer text 600, copyright 120.

Behaviour:

- **Nothing published** (or a published layout that can't be read: wrong
  kind or version, wrong shapes) → the built-in header and footer exactly
  as before: built-in pages, published additional pages marked "show in
  navigation" in their order, Contact last, in the header and footer.
  A single malformed link is left out.
- **Published layout** → its links, in its order. A link is hidden from
  visitors when it is switched off, malformed, or its additional page is
  missing, unpublished, archived or invalid; no draft title or address
  is ever shown. Hiding or removing a link never unpublishes its page,
  which stays reachable at its address. While a layout is published,
  "show in navigation" and the Pages tab's order have no effect (the
  Pages tab says so).
- The first draft reproduces the current navigation, so publishing it
  unchanged changes nothing visible.
- Save draft never changes the website. Publish (confirmed) refuses
  invalid links and any **visible** link to an unpublished page; hidden
  links may wait for their page. Unpublish (confirmed) deletes the live
  copy and keeps the draft.
- The editor's preview draws the real header, footer and mobile menu
  from the draft, at 1280 px (scaled) or 390 px, in English or Tamil,
  without publishing. It can't be clicked.
- Login, Dashboard and Logout are not part of the layout and never
  change.

### Languages

The language registry (`site_languages`) and how text is kept in every
language are described in `docs/website_multilingual.md`.

### How visitors read content

- The whole public site uses two queries per visit, cached for the session:
  - `website_media` where `status == 'published'`. This is a single-field
    filter, so no composite index is needed, and it matches the proposed rule.
  - all of `website_pages` (built-in page content, additional pages, the
    site layout and the language registry).
- Changes need no rebuild or redeploy. New visitors see them on their next
  page load. An admin's own session refreshes immediately.

### Fallbacks

- No page content published, or blank text → the site's built-in wording.
  - If Tamil text is blank, the managed English text is shown, so the
    English and Tamil pages never show unrelated content.
- No image, an image that isn't published (or was deleted), or a load
  failure → the built-in decorative placeholder.
- An image that fails to download → the placeholder with a small
  "image unavailable" mark.

## Admin workflow rules (enforced in `WebsiteContentAdminService`)

**Who can make changes**
- Every method that reads or changes content requires
  `requesterRole == 'admin'`. `pickImage` only opens the file picker and
  writes nothing.
- Staff and parents see the locked view.

**Uploading and publishing**
- An upload is a draft. Its approval and consent are confirmed only if the
  admin confirmed them for that image in the review (below); otherwise it
  stays unconfirmed.
- **Several at once:** *Upload images* opens the picker for several files.
  Each is checked on its own (JPEG, PNG or WebP, not empty, at most 15 MB);
  a file that can't be uploaded is listed with its reason, never dropped.
  The review step sets shared defaults (category, caption, gallery,
  decorative, albums) and lets each image have its own alt text, caption,
  category and decorative setting. Files then upload one at a time, each
  with its progress and result. Failed or cancelled files can be retried,
  alone or together; uploaded ones are never sent again. Every file has a
  media id reserved before uploading (`newMediaId`), and `uploadMedia`
  with that id returns the existing record instead of making another, so a
  retry or a second tap never creates a duplicate. *Stop* finishes the
  image in progress and marks the rest cancelled. The original file name
  is shown in the review only, never stored.
- **Review of each image:** thumbnail, file name, alt text (prefilled
  "2D Montessori") and one checkbox, *Photo approved by the school and
  consent obtained*, unticked to start. The shared settings show how many
  images are confirmed and how many are not; each unconfirmed image says
  so in red.
- **Confirm for all:** *Apply approval and consent confirmation to all
  selected images* first shows: "I confirm that all selected photographs
  are approved by the school and that the required consent has been
  obtained." Only *Confirm for N images* ticks them; *Cancel* changes
  nothing. It applies to this upload's images only (not those left out,
  already uploaded or elsewhere in the library). Any image can be unticked,
  or ticked again, afterwards.
- **Saved with each image:** after each file uploads, a ticked image is
  confirmed through `confirmConsent`, the same method (and the same
  `consent-confirmed` audit entry) as the library's own confirmation;
  confirmed with the "all" action, the entry has `bulk: true`. An
  unticked image keeps `consentConfirmed: false`. Each file's result says
  which it is; if the confirmation can't be saved, the result says so and
  the image stays unconfirmed. No security rule changes are needed: the
  upload creates the record exactly as before, then updates it.
- **One image** (the image section of events and announcements) uploads
  with the default alt text and unconfirmed, then opens in the library
  for its alt text and confirmation.
- Publishing requires the file and consent confirmation (see below).

**Bulk actions** (Media library: select images one by one, or all shown
with the current album filter; *Clear selection*; the count is shown).
Each action goes image by image through the single-image method, with all
its checks, and reports every image: done, unchanged (already so, and
why) or failed (and why). One failure never stops the others.

| Action | Uses | Checks kept |
|---|---|---|
| Confirm consent… | `confirmConsent` | Asks first, naming the responsibility for every image; recorded in each image's audit with `bulk: true`. Publishes nothing. |
| Publish | `publishMedia` | Consent confirmed and a file, per image |
| Unpublish | `hideMedia` | Refused while a published page, event, announcement or active form shows the image |
| Add to / Remove from gallery | `setInGallery` | Changes `inGallery` only |
| Delete… | `deleteMedia` | Asks first; refused for an image used on a page (draft or live), form, event, announcement or template, or when templates can't be checked |
| Add to / Remove from album… | `WebsiteAlbumsService` | Images unchanged |

The menu says beforehand how many images each action applies to and why
the others can't be changed.

**Taking an image off the website.** There are three ways, deliberately
different:

| Action | Purpose | When allowed | Effect |
|---|---|---|---|
| **Withdraw consent** (untick and save, after a confirmation naming the affected pages) | Privacy | Always, at once, even while live pages use the image | The image becomes `hidden` and the record gets `consentWithdrawnAt`. It leaves the gallery and every page immediately. Those pages stay published with their other content and show their placeholder; the Pages list marks them "Image not shown". Storage files are kept. An audit entry (`consent-withdrawn`) records who, when, whether it was published, and which pages were affected. It can only return through fresh consent and publishing. |
| **Hide** | Editorial | Refused while a live page shows the image | The image becomes `hidden`. No published page loses its image by accident. |
| **Replace** | New photo, same id | Always | The file is swapped, consent is cleared, and a published image goes back to `draft` at once (pages show their placeholder). The old files are deleted as part of the swap. The new photo needs its own consent before it is published again. |

**Deleting**
- Deleting removes the record, its audit trail and its Storage files.
- An image used by any page, draft or live, can't be deleted.
- Delete is the only action that removes the photo's Storage files.

**Pages**
- A page can only be published with published images, so a withdrawn or
  hidden image can't be republished on a page.
- Unpublishing a page returns it to its built-in content and keeps the draft.

**Public safeguard.** The public site resolves every image (gallery, page
banners, sections) from one list: media with `status == 'published'` *and*
`consentConfirmed == true`. A record in any other state is shown nowhere.

**Limits**
- Files: JPEG, PNG or WebP, up to 15 MB.
- Alt text: 250 characters. Caption: 300. Heading: 120. Introduction: 600.

## Alt text, photo approval, consent and publishing

These are separate things; none implies another.

1. **Alt text (accessibility).** Describes the image for screen readers
   and when the image can't be shown. New uploads default to
   "2D Montessori"; replace it with a meaningful description (who or what
   is shown) wherever you can. Images marked decorative are skipped by
   screen readers. Alt text never establishes approval or consent, and an
   image without it can still be published by the app.
2. **Photo approval.** The school approves the photograph for use on the
   website.
3. **Consent.** The required consent has been obtained for every
   identifiable person in the photograph, where applicable.

   The data model records 2 and 3 as **one** confirmation
   (`consentConfirmed`), so the library has one control for both. An
   authorised administrator must tick it: uploading, writing alt text,
   choosing a category or adding to an album never sets it.
4. **Publishing eligibility.** An image can be published only when it has
   its file **and** `consentConfirmed` is true. Otherwise publishing is
   refused, one by one or in bulk, with the real reason: "The image file is
   missing." or "Photo approval and consent not confirmed: …". Bulk results
   name each image by its alt text (or caption), and the reason is shown
   under it. Visitors see an image only while it is published *and*
   confirmed.

The confirmation, single or for all, is the administrator's **attestation**
and is recorded in the image's audit trail. The app does not, and cannot,
verify that consent exists. Withdrawing it (untick and save) removes the
image from the website at once.

**Workflows.**
- *One image:* upload, open it in the library, check the alt text, tick
  approval and consent, then *Publish*.
- *Several images:* *Upload images*, choose the files, review each image
  (alt text, and approval and consent, ticked one by one or with *Apply
  approval and consent confirmation to all selected images* and then
  unticked where needed), then *Upload*. Publish in the library, one by
  one or with the bulk *Publish*, which publishes only the confirmed ones
  and lists why the others weren't.
- *Existing images* keep their alt text and confirmation exactly as stored;
  change them in the image's details.

## Proposed security rules (not applied, emulator-tested)

The service checks above can be bypassed by anyone calling Firestore or
Storage directly, so the rules must enforce the same limits.

**Files**
- `test/firebase_rules/website_content.firestore.rules`
- `test/firebase_rules/website_content.storage.rules`

**Status**
- These are proposals. They cover **only the website collections** and must
  be merged into the project's real rules after review.
- **Never deploy either file on its own:** a deploy replaces all of a
  service's rules.
- The deployed rules for `montessori-app-95988` and `twod-montessori-prod`
  are not in this repository and have not been inspected.

### Identifying an admin

User documents here are keyed by phone number, with the Auth uid stored as
a field (`firebaseAuthUid` or `authUid`), so rules can't look a role up by
uid. The proposal expects a **custom claim** `role: 'admin'` on each admin's
Auth account, set with the Admin SDK. Nothing in the app sets it yet.

- The rules read it as `request.auth.token.get('role', '') == 'admin'`.
  `get` with a default means a token without the claim is simply denied,
  rather than raising an evaluation error.
- An alternative is an allowlist document `website_admins/{uid}`, which the
  rules would check with `exists(...)`.

### Pending rule changes (media library upgrade; not made, need approval)

The media library upgrade's app code needs two rule changes that haven't
been made to the proposal or the deployed rules:

1. **Optional alt text.** `isValidMedia` still requires English alt text on
   a published record. Against rules like that, publishing an image
   without alt text is refused by Firestore (the app shows the error).
   Change: drop the `alt.en` condition, keeping `consentConfirmed == true`.
   Until then, new uploads meet it through their default alt text
   ("2D Montessori"); images stored without alt text, or whose alt text an
   admin cleared, are still refused on publish by such rules.
2. **Albums.** There is no rule for `website_albums`, so its reads and
   writes are denied. Proposed: like `website_templates`, admin with the
   matching `schoolId` claim only (never public): `get, list` when
   `isSchoolAdmin(resource.data.schoolId)`; `create` and `update` when
   `isSchoolAdmin(...)`, `schoolId` unchanged, `name` a string of 1–80,
   `description` (if present) at most 300, `mediaIds` a list of at most
   2,000; `delete` when `isSchoolAdmin(resource.data.schoolId)`.

### What the Firestore rules enforce

- **`website_media`**
  - Visitors may get or list only `status == 'published'` records, and
    their queries must filter on that, as the public site's does.
  - Admins may create or update a record only when it:
    - has a known status;
    - holds none of the private fields (`fileName`, `updatedBy`,
      `updatedByName`, `updatedById`, `uploadedBy`, `createdBy`);
    - if `published`, has `consentConfirmed == true` and English alt text
      (the app no longer requires alt text: see "Pending rule changes").
  - Admins may delete.
- **`website_media/{id}/audit`**
  - Admins may read, create and delete entries. Nobody may edit one.
- **`website_pages`** (live)
  - Anyone may read.
  - Admins may create or update:
    - a **built-in slot** (`home`, `admissions`, `teacher_training`,
      `programs`, `gallery`), only with no `kind` field and no private
      fields;
    - **any other id**, only as a valid `kind: 'custom'` page: valid slug,
      English title, at most 20 sections, no `archived` field, no private
      fields.
  - **Deletes (unpublishing) have their own explicit rule:**
    `allow delete: if isWebsiteAdmin()`. This replaces the earlier
    `request.resource == null` condition inside the write rule.
  - **`site_layout`**, only as `kind: 'layout'`, `schemaVersion: 1`, with
    at most 10 main and 16 footer links, text fields within their length
    limits, and only the visitor-facing fields (`kind`, `schemaVersion`,
    `siteName`, `tagline`, `mainNav`, `footerNav`, `footerText`,
    `copyright`, `publishedAt`). Individual links aren't checked by the
    rules (they can't loop over a list); the app validates them before
    saving and again before showing them.
- **`website_page_drafts`**
  - Admins only, for reading and writing.
  - `site_layout` must have the layout shape above (editor fields allowed).
  - Any other non-slot id must be a `kind: 'custom'` page with a valid slug.

### What the Storage rules enforce

- `website_media/{mediaId}/{file}`: admins only, for read, upload and delete.
- Uploads must be under 15 MB and `image/jpeg`, `image/png` or `image/webp`.
- Visitors load images through the download URL stored in a published
  record. That URL's token is honoured without consulting the rules.

### Running the emulator tests

```
JAVA_HOME=/path/to/jdk21 firebase emulators:exec \
  --config test/firebase_rules/firebase.json \
  --project demo-montessori-website --only firestore,storage \
  "python3 -I test/firebase_rules/website_rules_test.py"
```

- Firebase CLI 15 needs Java 21 or later.
- The `demo-` project id keeps everything local, and the script refuses any
  other project.
- The script makes 147 checks, using only the Python standard library.
  It covers:
  - public, signed-in-without-role, staff, parent and admin access;
  - public versus draft reads;
  - publication validity;
  - consent rules;
  - audit immutability;
  - authorised and unauthorised deletes and updates;
  - Storage upload types and sizes;
  - downloads with and without the URL token.
- Run against the earlier documented `website_pages` rule, the same script
  fails 8 checks. Its deletes worked, but it allowed malformed or
  private-field live documents.

### Limitations

- **Content rules are shallow.** They check the record's shape (status,
  slug, title, section count, private fields). They don't validate every
  section's fields or button links; the app validates those before saving
  and again before following a link.
- **Site layout links aren't checked by the rules.** They check the
  layout's shape, sizes and fields; each link's target (and that a linked
  page is published) is checked by the app when saving and publishing, and
  again when the site shows the link.
- **Slug uniqueness and image references** can't be enforced by rules.
  Uniqueness is checked by the service, and two admins creating the same new
  slug at the same moment isn't prevented. The rules also don't check that a
  live page's images exist or are published; the public site simply doesn't
  show images that aren't.
- **No rule-level per-field allowlist** exists for media records beyond the
  private-field denylist.

### Hosting

The web app uses clean path URLs (`https://<site>/pages/<slug>`), and old
`/#/...` links still open their page. The existing `firebase.json` rewrite
(`**` → `/index.html`) already serves every route, so no hosting change is
required. A narrower rewrite is proposed. See `docs/website_clean_urls.md`.


### Notes

- **Existing rules:** the new collections are only readable if the deployed
  rules don't already deny unauthenticated reads broadly. If they do, the
  public site keeps showing its built-in content and placeholders, which is
  the designed fallback, until rules like these are deployed. The admin
  screens need admin read and write access.
- **Download URLs outlive hiding:** a download URL stays valid after an
  image is hidden or its consent is withdrawn. Anyone who copied it earlier,
  or whose browser cached it, could still open it. Only deleting the image
  (or replacing its file) removes the Storage objects and invalidates the
  URL. For a consent withdrawal that must reach already-shared links, also
  delete the image.
- **CORS:** the Storage bucket's CORS setting (see `cors.json`) must allow the
  website's origin for canvas rendering. The image widget falls back to an
  `<img>` element if it doesn't.

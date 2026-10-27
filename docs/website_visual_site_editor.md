# Visual site editor: sections, built-in pages, design, header and footer

Builds on the page builder (`docs/website_page_builder.md`) and the site
layout (`docs/website_content.md`). Nothing here deploys, migrates or
writes anything by itself: every change is made by an admin, saved as a
draft, previewed, then published through the existing CMS service.

## Phase 0: why the five capabilities were missing

| Request | What existed | Why it was missing |
|---|---|---|
| Visual site layout | `SiteLayout`: text and links only | `PublicHeader`/`PublicFooter` drew fixed `PublicColors`; there was nothing visual to store or edit. |
| Built-in pages in the visual editor | Slot documents (`home`, `admissions`, `teacher_training`, `programs`, `gallery`): headline, intro, image | The rest of each page is bundled code (`PublicStrings` and private widgets in `public_home_page.dart`, `public_section_page.dart`, `public_gallery_page.dart`). Contact had no document. |
| Full page sections | Blocks, including `columns` | No container with its own background, padding and width; blocks were always drawn inside a fixed 960 px width. |
| Colours | `style.background` ∈ {white, sage, gold}, `style.spacing` | No design tokens; the renderer used constant colours. |
| Header and footer | As for the site layout | No stored style fields. The proposed live rules allowed only the existing layout keys. |

## Content model: one model, no competing system

- **Sections are a block type** (`section`, v1). A section has a name for
  the editor, a layout (`1`, `1:1`, `1:2`, `2:1`, `1:1:1`) and columns of
  blocks, using the same `ColumnsFieldSpec` as `columns`. Everything
  generic comes for free: parsing, unknown fields, ids, duplication,
  validation, translation paths, image usage and the structure tree.
  Sections and columns can't contain each other (nesting depth stays 1).
- **Section presets** (`section_presets.dart`): Blank, Hero, About,
  Programs, Features, Testimonials, Gallery, FAQ, Call to action and
  Contact. Each is a section of ordinary blocks with starter English text,
  valid as created, with new ids every time.
- **New block types** (v1): `hero`, `cards`, `features`, `page_header`,
  `notice` and `gallery_feed` (the school's whole published gallery with
  its filters). Buttons gain the `link` and `back` styles. They exist so the
  built-in pages can be rebuilt faithfully, and are available everywhere.
- **Style keys** (`BlockStyle`): `background`, `textColor`, `headingColor`,
  `buttonColor`, `buttonTextColor`, `borderColor` and `lineColor` (a
  palette reference `token:<id>` or `#RRGGBB`; `background` keeps `white`,
  `sage` and `gold`), plus `spacing` (now also `none`), `padding`,
  `paddingTop`, `paddingBottom`, `align`, `fontSize`, `width` and
  `borderWidth`. Each block type declares the keys it offers
  (`BlockDefinition.styleKeys`), and the renderer honours them. Unknown
  keys are kept.
- **Inheritance:** a block's own style, else its section's (text, heading
  and button colours, alignment), else the site design.

## Design system (`website_design.dart`)

- `SiteDesign`: a palette of named colours plus body and heading size and
  line height.
  - The site's own colours (`forest`, `forestDark`, `sage`, `sageLight`,
    `gold`, `goldLight`, `ink`, `muted`, `background`, `surface`, `line`)
    can be renamed and changed, but not removed.
  - Added colours can be removed; anything using a removed colour falls
    back to its default.
- Styles store `token:<id>`, which follows the palette, or `#RRGGBB`, a
  local override that stays fixed.
- The renderer's own defaults (headings, text, buttons, header and footer)
  are palette colours too, so changing a palette colour changes the whole
  site.
- Stored on the site layout as `design`, only when it differs from the
  defaults. `WebsiteDesignScope` provides it to everything drawn: the
  published design on the public site, the draft in the editors.

## Header and footer (`website_site_style.dart`)

- **`SiteHeaderStyle`:**
  - colours for the background, top bar, site name, links and the
    current-page underline;
  - show or hide the logo;
  - link position (after the name, or centred);
  - height;
  - an optional button with an English/Tamil label and a link. The link
    follows the same rules as page buttons: a site page, https, mailto or
    tel.
- **`SiteFooterStyle`:**
  - colours for the background, site name, text and links;
  - alignment;
  - contact details: an English/Tamil address, plus a phone number and
    email, both tappable.
- Both are stored on the site layout as `header` and `footer`, only when
  they differ from the site's own look. They are edited in **Site layout &
  design**, previewed with the real `PublicHeader`/`PublicFooter`, and
  published with the layout, which applies them to every page at once.
- In the page editors, the canvas shows the real header and footer with
  the draft layout. Clicking either one explains that it is shared by
  every page and opens Site layout & design. Returning reloads only the
  layout, so the page's unsaved edits are kept.

## Built-in pages (`built_in_pages.dart`)

- **`BuiltInPage`:** Home, Admissions, Teacher Training, Programs,
  Gallery, Contact.
- **`BuiltInPageAdapter.blocksFor`** rebuilds a page from the site's own
  wording (English and Tamil) and its managed headline, introduction and
  image. Every language of the managed text is kept, and ids are derived
  from the page, so conversion is repeatable.
- **Storage:** `schemaVersion: 2`, `blocks` and `mediaIds` in the page's
  existing document (Contact gets a `contact` document).
  - Only these fields are written (an update of the existing document).
    The managed headline, introduction and image stay untouched, which is
    what older versions of the app show.
  - The old built-in form editor writes only its own fields, so it keeps
    the blocks. It shows a notice on a converted page. While the blocks
    are published, its Publish and Unpublish are unavailable (the service
    refuses them too: visitors wouldn't see the form's content, and
    unpublishing would take the blocks down), and it links to the visual
    editor.
  - A draft holding only blocks (saved before any form edit) has no
    managed content of its own: the form, and a conversion, start from
    the published heading, introduction and image.
- **Activation is explicit and reversible:**
  1. Settings → Website → Pages → "Edit a built-in page visually" shows
     the page twice through the real public page widget: as it is today,
     and as converted. Nothing is written.
  2. "Use the visual editor for this page" converts it in the editor
     only.
  3. Save draft writes the blocks; visitors still see the built-in page.
  4. Publish shows the blocks to visitors. Images must be published.
  5. Unpublish takes the blocks off the website. "Return to the built-in
     page" removes them from the draft and the website (confirmed). If it
     fails part-way, the editor keeps the blocks being edited and shows
     what is actually saved; it can be tried again.
  - If publishing saves the draft but the live write fails, the message
    says so and the editor shows the saved state ("Draft not published"
    when an earlier version is still live).
- **Publishing safeguards** (built-in pages, additional pages, the old
  form editor):
  - Publishing over a page visitors already see asks first ("Replace the
    published page?"); Cancel writes nothing. A first publication isn't
    asked about.
  - A page built with blocks can't be published when nothing on it would
    be shown (no blocks, or only hidden or unsupported ones). Its draft can
    still be saved; pages made of sections are unchanged.
  - "Draft saved, but publication failed." whenever the draft was written
    but the live page wasn't, in every editor, which then shows the saved
    state.
  - Site layout: if the layout is published (or its draft saved) but
    removing the default design, header or footer from the draft fails
    afterwards, the message says it was published and to save the draft
    again; the status shows it published.
- **Parity check:** for every page, in English and Tamil, the converted
  page shows exactly the same text as today, through the same public page
  widget (`test/website_site_editor_test.dart`). On Home, the managed
  image and the pathway links are the same. Spacing is close but not
  pixel-identical: for example, Back to Home sits 32 px below the notice
  instead of 28 px.

## Persistence, security, compatibility

- **Service and permissions:** every write goes through
  `WebsiteContentAdminService`, with its admin check, block validation and
  published-image checks: `saveBuiltInPageDraft`, `publishBuiltInPage`,
  `unpublishBuiltInPage`, `revertBuiltInPage`, and the existing layout
  save/publish. Non-admin roles are refused (tested).
- **Isolation:** the app serves one school per Firebase project, and there
  is no `schoolId` in the website collections. The new data lives in the
  same admin-only drafts and visitor-facing live collections, so isolation
  is unchanged (it is per project).
- **Proposed rules** (`test/firebase_rules/`, never deployed): `contact`
  joins the built-in page ids, and the live layout may hold `design`,
  `header` and `footer` maps. **The deployed rules must be updated the
  same way before these features are used in production.** Under rules
  without these changes (checked against the previous proposal), saving
  the Contact draft and publishing Contact are refused, and so is
  publishing a layout whose design, header or footer differs from the
  site's own (the whole batch, so the draft isn't changed either).
  Everything else (built-in blocks on the other five pages, unpublish,
  revert, deletes) is allowed by both.
- **Emulator checks** (demo project, JDK 21 or later):
  `website_rules_test.py` (rules) and `website_persistence_test.py` (what
  real Firestore stores for each of the service's writes: `mergeFields`
  keeps `lastPublished*` and unknown fields, a text map loses a removed
  language, a default design is removed from the draft, Contact revert
  leaves no documents). Run each with
  `firebase emulators:exec --config test/firebase_rules/firebase.json
  --project demo-montessori-website --only firestore,storage "python3 -I
  test/firebase_rules/<script>"`; `RULES_UNDER_TEST=previous` checks the
  persistence script against older rules.
- **Older versions of the app:**
  - New block types and sections are unsupported there: kept, not shown.
  - A block page's legacy `sections` copy leaves out sections and the new
    block types.
  - Built-in pages keep their managed fields, so older versions show the
    built-in pages.
  - Older versions ignore the layout's `design`, `header` and `footer`.
- **Hidden blocks are never published:** a live page (built-in or
  additional) leaves out hidden blocks and sections at every depth, and
  their images (`BlockRegistry.withoutHidden`). The draft keeps them, and
  draft-versus-live status ignores them.
- **Unknown fields:** kept in blocks, columns, styles, the design, the
  header and footer styles, and the layout draft's top-level keys. The
  live layout holds visitor-facing fields only.
- **Not touched:** authentication, routing, `main.dart`, the URL strategy,
  Firebase configuration and hosting.

## Known gaps

- **Built-in pages:**
  - Gallery's filters and lightbox come from the `gallery_feed` block. In
    the editor's canvas it is a static preview of the published photos;
    the live block, and the comparison and Preview views, use the real
    gallery.
  - Converted spacing differs by a few pixels in places (see above).
- **Typography:** fixed sizes chosen from lists (body, heading, line
  height). There is no font family choice.
- **Header and footer:** edited as forms with a live preview in Site layout
  & design. On the page canvas they are selectable but not edited in
  place.
- **Editor:**
  - No drag and drop, undo/redo, inline text editing or leave-page guard
    (out of scope).
  - The built-in page editor's toolbar wraps onto several rows on mid-size
    screens.
- **Rules:** the proposed rules changes still need to be merged into the
  deployed rules (see above). The deployed rules aren't in this
  repository and haven't been compared.

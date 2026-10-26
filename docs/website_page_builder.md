# Page builder blocks (P2a) and translation core (L2a)

> **Status:** the foundations (P2a, L2a) and the block editor (P2b) are
> tested locally and not deployed.
> - No translation collections or screens exist yet (L2b and L2c).
> - Built-in pages are not converted.
> - No data is migrated, and no Firestore rules or settings changed.

## Blocks

Code lives in `lib/modules/public_website/content/blocks/`, and the public
renderer in `widgets/blocks/website_blocks_view.dart`.

- **Every block** is stored as
  `{id, type, v, hidden?, style?: {background, spacing}, ...fields}`.
- **Ids** (`block_ids.dart`):
  - Generated ids are `b_`, `i_`, `c_` or `r_` followed by 10 random
    base-36 characters, from a secure random source.
  - Legacy ids (base-36 timestamps) and derived ids (`<id>__img`) stay
    valid. Any id is `[A-Za-z0-9_-]{1,64}`.
  - An id never changes when content is reordered.
- **Block types** (`block_registry.dart`): `text`, `image`, `columns`
  (layouts 1:1, 1:2, 2:1, 1:1:1; one level of nesting), `cta`, `buttons`,
  `gallery` and `divider`.
  - Each type declares its fields once (`field_spec.dart`: text, image,
    link, choice, toggle, items with ids, columns).
  - Parsing, saving, validation, the images a page uses and the
    translatable texts all come from those declarations.
  - A new type needs a definition and a render function, nothing else.
- **Nothing stored is lost:**
  - Unknown types, newer versions, blocks with no id or type, and
    non-block entries become `UnsupportedBlock`s. They are saved back
    exactly as stored and never shown publicly.
  - Unknown keys, and values of the wrong shape inside known blocks and
    items, are kept and written back unchanged; validation reports them.
  - Every language key of every text is kept.
- **Validation** checks:
  - each field: length in every language, English needed before another
    language, required images and buttons, allowed options;
  - links, with the same `SafeLinkTarget` checks as page buttons,
    including same-site protected routes;
  - ids: valid, and unique across the page's blocks, items and columns;
  - nesting depth, and at most 6 blocks per column;
  - at most 40 blocks, and an encoded size of at most 500 KB
    (`BlockLimits`, configurable).
- **Duplicating** a block gives it, its items, its columns and the blocks
  inside them fresh ids.

### Pages

- **Existing pages are unchanged.** They are still made of `sections`,
  stored with exactly the same fields, edited by the existing editor and
  shown by the existing renderer.
- **A page saved with blocks** has `schemaVersion: 2` and a `blocks` list
  (no page has them yet).
  - `CustomPage.blocks` reads them, and every save writes them back
    unchanged, including unsupported blocks.
  - Their images count in `mediaIds` (usage checks), and publishing
    requires them to be published.
  - Their problems join the page's validation.
- **The public page:** a page with blocks shows its blocks. Each block is
  checked again before it is drawn:
  - hidden, unsupported and invalid blocks, and images that aren't
    published, are left out one at a time;
  - unsafe links aren't shown;
  - columns stack on mobile.
- **The editor** edits a block page's blocks (see "Block editor" below).
  A page made of sections keeps the existing section editor.

### Legacy sections → blocks (`legacy_sections.dart`)

The conversion is in memory only: nothing is converted or written in this
phase. It is deterministic, so the same section always gives the same ids
and translation paths:

| Section | Block |
|---|---|
| `text` | `text` (same id) |
| `image_text` | `columns` 1:1 (same id): columns `<id>__c1`/`<id>__c2`, holding `image` `<id>__img` (4:3) and `text` `<id>__txt`, ordered by "image on the right" |
| `image_grid` | `gallery` (same id): items `<id>__m_<mediaId>`, repeats `_2`, `_3` … |
| `cta` | `cta` (same id): button item `<id>__btn` |

`LegacySections.toSection` converts back exactly (it is tested both ways).
It will be used for the legacy `sections` copy once the block editor
writes block pages.

**Only one editable copy, ever.** A page has either sections (edited by
the section editor) or blocks (edited by the block editor), never both:

- When a block page is saved, its `sections` are regenerated from its
  blocks (`LegacySections.mirror`). They are a read-only copy for older
  versions of the app and are never read back.
- The copy holds every top-level block that has an exact section form, up
  to 20. Hidden blocks and blocks without a section form (buttons,
  dividers, other columns layouts …) are left out, and the editor says how
  many.
  - A columns block with a hidden block inside is left out too: a section
    can't hide half of itself, and older versions must never show what was
    hidden. The blocks themselves are saved unchanged.
  - A style that only spells out the defaults (`background: white`,
    `spacing: normal`, as choosing them in the editor stores) looks the same
    as no style, so it doesn't stop a block's copy. Any other value, or an
    unknown style key, does. Stored styles are never rewritten.
- A block page is validated by its blocks only.

## Visual block editor (P2b, V1 visual editor)

> Sections, built-in pages, the design system and the header and footer
> editor are described in `docs/website_visual_site_editor.md`.

Settings → Website → Pages → an additional page built with blocks. New
pages are created built with blocks (no blocks yet); pages made of
sections keep the form editor until converted (below).

**Layout** (`ui/page_builder/website_visual_editor.dart`):

| Width | Panels |
|---|---|
| ≥ 1200 px | Structure, canvas and properties side by side |
| 840–1199 px | Canvas; Structure and Properties shown or hidden with buttons above it |
| < 840 px | One at a time: Page, Structure, Edit tabs |

- **Toolbar:** status (draft / published / archived, in navigation,
  unsaved edits, problems to fix), Editing / Live version, language,
  Desktop / Mobile width, Preview, and the existing Save draft, Publish,
  Unpublish, Discard changes and Archive (or Restore) — the same service
  calls and checks as before; nothing else saves or publishes. On a phone
  (< 840 px) it keeps the status, language, Save draft and Publish (or
  Restore); the version, Preview, width, Unpublish, Discard changes and
  Archive are in its **More** menu, with the same confirmations.
- **Structure** (left): Add block (all seven types; a new block goes
  after the selected one), every block with the blocks inside each column
  (Add to a column there; columns can't nest), and per block: select,
  edit, move up/down, duplicate (fresh ids for the block, its items, its
  columns and the blocks inside), hide/show and delete (confirmed). Hidden,
  locked and "to fix" blocks are marked. Below: "Show the first block to
  fix", the page's full list of problems and the warnings.
- **Canvas** (centre): the page as visitors see it — its title,
  introduction and banner from the public page body, then each block drawn
  by the public renderer (`WebsiteBlocksView`, one block at a time, with
  `spaced: false`; the canvas keeps each block's space above), with
  published images only, in the chosen language.
  - **Desktop** lays the page out at least 1200 px wide (above the public
    pages' 1100 px desktop breakpoint, so columns, grids and gutters are
    the desktop ones) and scales it down to fit the canvas; clicks still
    reach the scaled page. **Mobile** lays it out at 390 px.
  - Click (or focus and press Enter) to select a block: an outline and a
    toolbar (move, duplicate, hide/show, delete). Delete or Backspace on a
    focused block deletes it after confirming; Alt+↑/↓ moves it. Links and
    the gallery lightbox don't react.
  - With a block inside columns selected, its columns block keeps an
    outline ("Editing a block in these columns") but not its whole-block
    toolbar or keys, so the columns block can't be deleted or duplicated by
    mistake.
  - `+` points between blocks (and at the end) add a block there.
  - Blocks visitors wouldn't see are placeholders saying why: hidden,
    with problems, unsupported, an unpublished image, nothing to show yet.
    Inside columns, a note under the columns block lists each such block
    (column, position, type, why); when none is shown, the columns
    placeholder says so. Nothing stored changes.
  - An empty page shows what to do first and buttons for common blocks.
  - **Preview** shows the page exactly as visitors see it (the public page
    body) with no editing aids; **Live** shows the published version.
- **Properties** (right): the selected block's form, generated from its
  type's field declarations, plus background and space above. English and
  Tamil are edited; text in other languages and unknown fields are kept
  unchanged. A columns block lists the blocks in each column to select; a
  block inside a column links back to it. Unsupported blocks are locked:
  they can only be moved or deleted (with a warning). With nothing
  selected: the page settings (title, address, introduction, banner image,
  navigation, translation readiness).
- Edits go through `BlockListOps` (`ui/page_builder/block_list_ops.dart`):
  pure functions on the block list, addressed by position (an unsupported
  block may have no id), that keep every untouched block as it is.
- **Validation:** saving is refused while there are problems (unsafe or
  protected links, missing images, limits, ids …). Warnings don't block
  saving: images that aren't published (publishing the page is refused),
  hidden blocks, unsupported blocks, and blocks with no sections copy.
- **Translation readiness:** for each enabled language other than English,
  how many texts (and required texts) have inline text in that language.
  Nothing is created; translation records are a later step.
- **Discard changes** (confirmed) returns to the last saved draft.
  Leaving without saving keeps nothing either.
- **Converting a page made of sections** is explicit: "Convert to
  blocks…" shows the converted page (rendered for visitors) and its
  blocks; Cancel changes nothing.
  - Convert switches to the visual editor without saving; Save draft keeps
    it, and Discard changes undoes it.
  - Converted blocks keep the sections' ids and every language. The
    sections copy written on save is exactly the original sections, so
    older versions of the app see the same page.
  - Opening a page never converts it.

**Not yet:** selecting blocks inside columns on the canvas (select them
in the structure or from the columns block), drag and drop, undo/redo,
editing text directly on the canvas, and a warning when leaving with
unsaved changes.

## Translation core (`content/translation/`)

Pure Dart; nothing is stored.

- **Paths** (`field_path.dart`) use ids and field names, never positions,
  separated by `/`:
  - `page/title`, `page/seo/description`
  - `b/<blockId>/<field>`, also for blocks inside columns (block ids are
    unique on a page)
  - `b/<blockId>/i/<itemId>/<field>`
  - `b/<blockId>/col/<colId>/header` and `b/<blockId>/row/<rowId>/<colId>`
    (tables)
  - `layout/<field>`, `nav/<entryId>/label`, `media/<mediaId>/<field>`
- **Source hash** (`source_hash.dart`): SHA-256 (`package:crypto`, now
  declared directly) of the English text, after converting `\r\n` and
  `\r` to `\n` and trimming.
- **Records** (`translation_record.dart`):
  - Each field entry holds `text`, `status`, `sourceHash`, `origin`
    (`human`, `legacy`, `ai`) and `previousText`.
  - A record covers one language and one document (id
    `<lang>__<scope>__<docId>`).
  - **Stored statuses:** draft, needs review, approved, published.
  - **Derived statuses:** missing (no text) and outdated (the English
    hash changed). An outdated translation's text is kept.
  - **Allowed moves:** draft → needs review or approved; needs review →
    draft or approved; approved → published or draft; published → draft
    (by editing).
  - Editing approved or published text keeps it in `previousText` until
    the next publish. Approving is refused while the translation is
    outdated.
  - When a block is deleted, its paths become orphans. They are never
    matched to new content, which always has new ids.
- **Coverage** (`translation_coverage.dart`):
  - `TranslatableSources` lists the English texts of blocks, custom pages
    (blocks or legacy sections), the site layout and images, marking which
    are required (titles, headings, labels, alt text).
  - `TranslationCoverage` counts every text and the required ones by
    derived status, plus ready (approved or published and up to date),
    orphans and whether every required text is ready.

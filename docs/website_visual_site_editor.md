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

## Styling: page background, top bar, typography and block font sizes

Every setting is optional: nothing set keeps a page, the header and a block exactly as before, and no new key is written. Each goes through the existing draft, publish and revert flows.

- **Page background** (`website_page_style.dart`, `PageStyle`):
  - **Stored as** `pageStyle: {background}` on the page's own draft and live documents: additional pages (`CustomPage.pageStyle`, in its content map only when set) and built-in pages built with blocks.
  - **Edited** in the visual editor's page settings: palette swatches, an editable `#RRGGBB` and "Reset to default" (`WebsitePageBackgroundField`). It shows at once on the canvas and in "Preview as visitors see it", and marks the page unsaved.
  - **Where it applies:** behind the page's content only (`PageBackground`), never the header, top bar, footer or a section with its own background. "Return to the built-in page", unpublish and revert remove it with the blocks.
  - **Not offered** on pages still made of sections (the older format).
- **Top bar** (the language switch and login, `SiteHeaderStyle`):
  - **Settings:** background, text and icon colour (login and logout; the language switch keeps its own pill colours, so it stays readable on any bar colour), alignment (left, centre — the default, as the bar has always looked — or right), vertical alignment, and four sizes in px:
    - text size 11–18 (default 13);
    - padding at the top and bottom 0–24 (default 6);
    - padding at the sides 0–48 (default 0; at most 16 on phones);
    - space between controls 0–40 (default 12).
  - **Layout:** the controls wrap onto a second line when they don't fit. On phones, login and logout stay in the menu, as before.
  - **Stored** in the existing `header` map of the site layout; edited and published in Site layout & design.
- **Typography** (`SiteDesign`, Site layout & design → Design):
  - **Sizes,** each a slider and number box with a reset and an "Inherits … / Custom" line:

    | Text | Range | Default |
    |---|---|---|
    | Page titles and hero headings | 24–72 | 44 |
    | Page titles on phones | 20–48 | 32 |
    | Section headings | 18–48 | 26 |
    | Body text and descriptions | 12–24 | 16 |
    | Header navigation | 12–22 | 15 |
    | Buttons | 12–22 | site's own |

  - **Values:** whole pixels only. Line height keeps its list.
  - **Phones:** only titles have a separate phone size, as in the existing renderer.
  - **Stored** in `design`. The previous fixed size lists are all within the new ranges, so saved designs stay valid.
  - **Navigation:** the header still measures its links at the chosen size and uses the menu when they don't fit. The header row is at most 1160 px wide, so six links fit at 15 px; larger navigation text, or more links, uses the menu.
- **A block's own font sizes** (block `style`: `headingFontSize` 14–72, `bodyFontSize` 12–24):
  - **Offered on** `text`, `hero`, `cards`, `features`, `page_header`, `notice`, `events_feed`, `announcements_feed`, `cta` and `map` (both), and `gallery` (heading).
  - **Not offered on** containers (`section`, `columns`), `form`, `image`, `buttons`, `divider` or `gallery_feed`: their text belongs to the blocks inside, or there is none.
  - **Precedence:** an override takes the place of the site typography and of the block's "Text size" option. A hero's or page header's heading override is its title, scaled on phones in the same ratio as the site's titles.
  - **Editing:** each panel field shows whether it inherits ("Inherits the site typography: 26 px") or is custom; Reset removes the key, and the block keeps its id.
- **Preview and website:** the canvas uses the same renderer and `WebsiteDesignScope` as the public site, so published pages match the preview.

## Block spacing: padding and margin (every block type)

Every block type, present and future, has the same two groups at the end of its *Design* settings: **Padding (inside the block)** and **Margin (outside the block)**. They aren't fields of any block definition: they are style keys (`blockPadding`, `blockMargin`; `content/blocks/block_spacing.dart`), offered by the shared style editor and drawn by the shared renderer (`_BlockWidget` in `website_blocks_view.dart`), so a new block type gets them with no code.

- **Values**: top, right, bottom and left, each Automatic (blank) or 0–200 px (zero is a value); unit px. *Same on all sides* links the four; unlinked, each is set alone. Desktop, Tablet and Phone each have their own: a side not set on tablets is desktop's, on phones the tablet's, else desktop's; each field says whether it is *Set*, *From desktop: 24* or *Automatic*. *Reset* on a side, or *Reset … to Automatic* for the screen size shown, removes the override. Stored only as set: `{'desktop': {'top': 24}, 'mobile': {'top': 8}}`; nothing stored means the block looks exactly as before.
- **Padding** is inside the block's surface: for a block with a background or border (and the call to action, notice, section and asymmetric gallery, which draw their own), the sides set replace that surface's own inner padding (e.g. 32 px), the others are kept; without a surface it surrounds the content. **Margin** is outside the surface. A top margin set for a screen size *is* the space above the block there: it takes the place of *Space above* on the page and of the section's gap between blocks (never added to them; 0 means touching). Unset, those gaps are as before. A bottom margin adds below the block.
- **Width**: a block with its own left or right spacing spans the width it is given (on a full-width page, its content width), so the sides are measured from those edges. Without side spacing a top-level block is placed as before: one narrower than its content width (a short Text block, a Buttons block) is centred there, as it always was.
- **Canvas**: the editor's outline around a block is drawn over it and takes no space, so the canvas lays blocks out exactly as the website does and selecting a block moves nothing (it used to add 4–5 px around every block).
- **Sections**: a section's padding sides replace its own (its *Padding* top/bottom style and its side padding) only where set; the existing section spacing settings are unchanged. Each block applies only its own spacing, so blocks inside sections and columns never get it twice.
- **Narrow screens**: the left and right sides of each (margin, then padding) shrink in proportion when together they would take more than a third of the width available (`FitPadding`), so nothing overflows sideways. Images keep their shape; buttons keep their size.
- **Section padding**: a section's Design starts with *Section padding (top and bottom)*, open: Top and Bottom for Desktop, Tablet and Phone (0–200 px, zero a value; linked or not; a reset per side, per screen size and for every screen size). It edits the same `blockPadding` top and bottom as the shared Padding group (one setting, two views; left and right stay in the shared group). The earlier section dropdowns (`padding`, `paddingTop`, `paddingBottom`) are no longer offered; values saved with them are still drawn and are what Automatic means (shown as "Automatic: 96"), so existing sections look the same. Each side set replaces the earlier value (never added to it); a value set for desktop or tablets is inherited by phones as it is (the old 48 px cap on phones applies to Automatic only).
- **Known**: the Hero's side-by-side layout (desktop, tablets) needs about 530 px; with or without spacing it overflows in a narrower space (spacing can make it that narrow). On phones it stacks.

## Layouts, items per row, Photo gallery and Map

- **Compatibility rule:** settings added to an existing block type are optional fields marked `omitDefault` (not stored while they hold their default), or `style` keys (stored only when set). A block saved before they existed reads, saves back and renders exactly as before; one built without them (the older section format's conversion) reads their defaults (`StructuredBlock.option` / `toggle`). No migration, no new collection, no rules change: the rules don't inspect blocks.
- **Sections and columns:**
  - Layouts `1`, `1:1`, `1:2`, `2:1`, `1:1:1` and now `1:1:1:1` (four columns), named in the editor ("Four columns"). Changing the layout keeps the existing columns' ids. A layout with fewer columns, when the removed columns hold blocks, asks first and moves those blocks to the end of the last column kept (cancelled, nothing changes; refused when they wouldn't fit in one column).
  - `style.columnGap` and `style.rowGap` (0, 8, 16, 24, 32, 40, 48 or 64 px). Unset: 40 px between columns; 24 px (columns block) or 24/32 px (section, phone/wider) between stacked columns, as before. Padding, content width and space above are the existing options.
  - **Responsive:** phones (< 700 px) stack the columns; tablets (700–1100 px) show up to three side by side, as before, and four as two rows of two; desktops show them all in one row.
- **Items per row** (`cards`, `features`): `desktopColumns` (auto, 1–4), `tabletColumns` (auto = as on desktop, 1–3), `mobileColumns` (auto = one per row, 1–2). `auto` everywhere is the earlier layout (all in one row; stacked on phones). A row's cards share its height. Cards now allow up to eight, points up to eight. Events and announcements keep their own layout and column settings.
- **Card image and icon** (`cards`): each card may have an image (`imageMediaId`, from the media library: Choose, Change, Remove; stored only when chosen) and an icon, with *None (no icon)*. Every part is optional, the title included: a card needs an image, an icon, a title or some text (in English, every language's fallback); a card with none of these is reported ("Card N: add an image, an icon, a title or some text"), and a link alone doesn't count. A Tamil title still needs its English, as elsewhere. New cards start with *None*; saved cards are unchanged (an explicitly saved icon stays, and an absent icon is still the star). The image is drawn as a **banner across the top of the card**: edge to edge (outside the card's padding, its top corners rounded by the card's), always half as tall as the card is wide (2:1, from the card's actual width, e.g. 360 px wide → 180 px tall), covering that frame around its focal point (centre by default), cropped but never stretched. The icon, title, text and link follow, padded as before; an image-only card is just the banner. Its library alt text is read by screen readers; an image without one is decorative, so the card's title isn't read twice. Earlier image-size settings (`imageSize`, `imageHeight`) are gone; values already saved are kept as stored and ignored (no migration). On the page: the banner, then the icon, then the title, text and link, with nothing drawn and no space kept for what isn't there (an empty title leaves no gap); an unpublished image isn't shown. The Features block keeps its icons (no *None*).
- **Photo gallery** (`gallery`, previously "Image grid"): images chosen from the existing media library, in the order set (add several at once with **Add images**, in the order ticked; move up/down; remove). Each image has an optional caption (replacing the library's) and link (else it opens the lightbox). Settings: images per row on desktop (1–6), tablets (auto = desktop), phones (1–3; default 2); shape (landscape 4:3, square, portrait 3:4, wide 16:9); images shown (all, or a limit); captions on or off. Removed or unpublished images are left out for visitors. **School gallery** (`gallery_feed`) still shows every published gallery photograph with its filters; to curate, use a Photo gallery instead.
- **Map** (`map`): heading; address or place name (required, English only, not translated; no `<` or `>`); map type (map or satellite); zoom (10–18); height (240, 320, 400 or 480 px); "Get directions" link (on by default); optional address and contact text (beside the map on wide screens, above it on phones). The map is Google's keyless embed (`https://maps.google.com/maps?q=…&t=m|k&z=…&hl=…&output=embed`, no API key) in an iframe titled "Map showing <place>"; the directions link is a documented Google Maps URL (`/maps/dir/?api=1&destination=…`) and is the way there if the map doesn't load. In the editor's canvas the map doesn't take clicks and the link doesn't open. Off the web (tests) a placeholder stands in for the iframe.
- **Preview:** Desktop, Tablet (820 px) and Mobile (390 px) in the visual editor's canvas.
- **Section text and columns (the Blank section):** every section (the "Blank section" preset is a plain section) has three optional fields above its columns: `eyebrow` (small heading, 60), `heading` (160) and `description` (1000, paragraphs), all `omitDefault`, English-first like other text (stored Tamil kept). Each is drawn only when it has text, in the section's alignment and colours, 12 px apart and 32 px (24 on phones) above the columns; none adds no space. A section with heading text but no visible blocks is shown; one with neither is left out, as before. In the properties form each column can be moved left or right (widths follow: "wider right" becomes "wider left") or removed, and **Add column** adds one (equal widths, up to four). Removing a column that holds blocks asks: move them to the end of the neighbouring column (if they fit), remove them with the column, or cancel. A section keeps at least one column, a columns block two. The operations are `ColumnOps` (`block_list_ops.dart`). Blocks still move only within their column otherwise.
- **Subtitles:** a section's subtitle or introduction is its own heading and description (above); inside a column, a Text block. Other block types don't grow their own subtitle fields.

## Asymmetric gallery (`asymmetric_gallery`)

A separate block type (Add block → **Asymmetric gallery**) for editorial photographic compositions; the **Photo gallery** (`gallery`) is unchanged, and no existing page (Home included) uses the new block until an editor adds it. Fields, checks, Automatic resolution and the layout engine are in `content/blocks/asymmetric_gallery.dart`; the renderer is `widgets/blocks/public_asymmetric_gallery.dart`. The editor's canvas and the website draw it with the same code from the same settings, so the preview at each size (Desktop, Tablet 820 px, Mobile 390 px) is what visitors see.

- **Images** (`images`, 1–12, each with a stable id): chosen from the media library, several at once with **Add images** (images already in the block can't be ticked again; **Change** on one image can deliberately pick any image, the same one included); replace, move up/down, remove. Per image: alt text (replaces the library's; Tamil kept), *Decorative only*, caption (replaces the library's), caption placement (block's, below, over, none), link, click action (Automatic = its link, else the larger view; or link, larger view, nothing), *Open other websites in a new tab* (on by default), and *Show this image*. **Feature image**: one image at a time (turning it on elsewhere turns it off here); the item list marks it, or the first image when none is chosen.
- **Composition, per screen size** (groups *Layout on desktop / tablets / phones*; desktop keys plain, others prefixed `tablet…`, `mobile…`): arrangement (Asymmetric editorial, Large feature with supporting images, Mosaic, Staggered grid, Custom arrangement), feature position (left, right, top, bottom), feature width (40–65% or a custom 25–80%), feature height (120–1000 px), feature and supporting image shapes (Automatic, square, landscape 5:4, portrait 4:5, 4:3, 3:2, 16:9, or a custom W:H from 4:1 to 1:4), how supporting images sit (Automatic, one above another, two by two, side by side), columns (2–6, for mosaic, staggered and custom) and the gaps across and down (0–96 px). Every option starts **Automatic**: desktop is an editorial composition (feature on the left, 60%); tablets follow desktop's settings (3 mosaic / 2 staggered / 4 custom columns, 16 px gaps); phones put the feature on top with the rest two by two (12 px gaps), or keep a mosaic, staggered or custom grid in two columns. Each screen size can be set on its own; nothing is copied between them.
- **Per image, per screen size** (group *Screen sizes and order*): hide on desktop / tablets / phones, and a position on each (1 = first; Automatic = the list order, or desktop's). *Size in a custom arrangement*: columns wide and rows tall on each size (Automatic: from the next larger size, else the layout's), clamped to the columns. Relative size (normal, larger, largest) sets a supporting image's share of the space, and its cells in a mosaic.
- **How the layout works**: from the width actually available, the engine places each image as a rectangle within it (relative proportions and grid cells, not fixed pixel positions), so nothing is wider than the page at any width, and the block's height is known before images load (no layout shift). Mosaic and custom are grids of square cells (the supporting shape sets the cell shape), each image spanning cells, packed in order; staggered places each image in the shortest column in its own shape, alternate columns starting lower. The feature height applies to the editorial and feature arrangements.
- **Appearance** (block defaults in *Image appearance*, overridable per image): fit (cover or contain), focus across / down (0–100%; Automatic = the image's Media library focal point), corner radius (0–48, Automatic 16 px), border (0–4 px) and its colour, overlay colour and strength (0–90%), hover (none, zoom, lift, darken) and shadow (none, soft, strong). Hover also shows on keyboard focus; with reduced motion (the system setting) zoom and lift are off and nothing animates.
- **Captions**: on or off; below or over the image; alignment; size (11–24 px); weight; upright or italic; colour; background when over. A caption below shares its image's rectangle (two lines at most; over the image if the space is too small), except in a staggered grid, where it is added under the image. Heading and description are optional: a block of photographs alone is fine.
- **Size and spacing**: maximum width (320–1600 px, Automatic the 1160 px content width), image gap (0–96), alignment (left, centre, right), space at the top and bottom (0–160), and the padding inside a background colour (block *Design → Background*; 0–96, Automatic 32 px, 20 on phones).
- **Larger view**: on by default for the block (*Clicking an image opens a larger view*), using the Photo gallery's lightbox over the images that open it. A click does one thing (its link or the larger view, never both). The canvas never opens anything.
- **Checks** (they stop saving): 1–12 images, each with an image; numbers in range; colours valid; a custom width or shape filled in and valid; one feature image at most; "follow the link" with a link. Publishing also refuses unpublished or missing images, as for every block. The editor lists images with no alt text (here or in the library) that aren't marked decorative, and unpublished or missing ones.
- **Accessibility**: each image is one screen-reader node with its alt text (its own, else the library's) and its action (link or button); a decorative image is skipped unless it does something, when it is named by its caption or "Image N". Focusable images show a focus ring. Only the images shown on the current screen size are built, so hidden ones aren't loaded.
- **Stored**: only settings that are changed (Automatic is never written); settings this version doesn't know are kept as stored.

## Testimonials (`testimonials`)

A block type (Add block → **Testimonials**) for quotes from families, students and educators as cards. Before it, "testimonials" were only the *Testimonials* section preset (three Text blocks); that preset, and every page built with it, is unchanged. Fields and the rules for initials and ratings are in `content/blocks/testimonials.dart`; the renderer is `widgets/blocks/public_testimonials.dart` (the canvas and the website use it alike).

- **Each testimonial** (`testimonials`, 1–12, stable ids): name, role or relationship, testimonial text (required), profile photo from the media library (choose, change, remove) and its description, rating, *Hide this testimonial's rating*, and in *More details*: date (free text, as it should appear), location and a verification label. Only the text is required; nothing else is shown, or invented, until entered.
- **Avatar**: the profile photo (published) as a circle; else initials from the name, the first letter of its first two words ("Tanveer Razi" → TR, "Yasmeen" → Y; leading punctuation skipped; a Tamil letter keeps its vowel sign); else no avatar at all. An unpublished or missing photo falls back to the initials. *Avatars* group: show avatars, size (24–120 px; Automatic 56, 40 compact), initials background and colour, alignment, border (0–4 px) and its colour.
- **Rating**: none by default (saved testimonials stay unrated); 0 to 5 in half stars. Shown only when the block's *Show ratings* is on, the testimonial's own isn't hidden, and it has one; otherwise nothing is drawn or reserved. *Ratings* group: star and empty-star colours (Automatic amber and grey), star size (12–40 px), alignment, and an optional number ("4.5") or "4.5 / 5". Full, half and empty stars differ in shape, not only colour.
- **Cards**: layout vertical (avatar, name, rating, text), horizontal (avatar beside) or compact (rating and text, the person below); background, border (0–4 px, Automatic 1 px in the site's line colour) and its colour, corner radius (0–48, Automatic 16), padding (8–64, Automatic 28; 20 compact or on phones), shadow (none, soft, strong; Automatic soft), content alignment (Automatic: centred when vertical, else left) and the space between parts (0–40, Automatic 12).
- **Section**: optional small label, heading and description; cards per row on desktop (Automatic 3), tablets (2) and phones (1), never more than there are testimonials when Automatic, and fewer whenever a card would be narrower than 220 px; gap between cards (Automatic 24, 16 on phones); maximum width (320–1600, Automatic 1160); heading alignment; space at the top and bottom; background through *Design → Background*. Cards in a row share its height; long text wraps.
- **Editor**: settings in collapsible groups, closed at first; a feature's settings are offered only when it is on (avatar settings with avatars on, star settings with ratings on, a border colour with a border, *Hide this rating* with a rating, the photo description with a photo; values are kept meanwhile). Each testimonial's header previews its avatar (photo or initials) and rating as they are edited. Numbers have *Reset to Automatic*.
- **Accessibility**: a rating is read as "4.5 out of 5 stars" (Tamil too); initials as "Initials of {name}"; a photo by its own description, else the library's alt text, else "Photo of {name}". Each card is one group for screen readers. Nothing in a card is interactive.
- **Stored**: only what is set (Automatic, no rating, no photo are never written); unknown settings are kept as stored. `FieldSpec.shownWhen` (editor only) is the one shared addition.

## Accreditations & Recognition and Custom HTML

Two more block types, added like every other (`block_registry.dart`): stored in the page's `blocks`, drafted, published and unpublished with the page, no new collection, no migration, no rules change.

- **Accreditations & Recognition** (`accreditations`): heading, introduction, *Show as* (certificate cards or logo strip), cards per row on desktop/tablet/phone (`auto` = 3/2/1, stored only when set), and 1–12 items. Each item: organisation or accrediting body (optional), credential or recognition, logo and certificate image (media library, optional), short description, verification or certificate link (the site's usual safe links), issue and expiry dates (optional; `2024`, `2024-03` or `2024-03-05`; an expiry before the issue date is a problem). The list order is the display order (move up/down).
  - **Cards show the image only** (the certificate, else the logo, else a plain badge), placed by the layout settings; *Text alignment* and *Space between image and text* now apply to the logo strip, where names still show under the logos.
  - **Details popup:** on the website each card (and each logo-strip slot) is one button: a click anywhere on it, or Enter/Space when focused, opens the accreditation's details in a dialog (centred, at most 640 px wide; full screen below 600 px), on a white surface whatever the card or section colours. It shows only what was entered: the credential as the title (else the organisation, else "Accreditation"), the organisation under it, the logo (large when it is the only image; small beside the title when there is a certificate), the certificate whole and uncropped, the description, "Issued …" and "Expires …" (as entered), and **Verify**. Escape, Close or a click outside closes it, and focus returns to the card. In the editor the cards are inert: a click selects and edits the block, and the details never open.
  - **Verify** opens exactly the address entered (an https address in a new tab; a page of this site in place). It is offered only for a real web address: an https address whose host is a domain name (not `localhost`, not an IP address, not a bare word or number; `https://2`, which browsers open as `0.0.0.2`, is not), `mailto:`/`tel:`, or a page of this site. Such a link still passes the site's usual link check (so published blocks stay visible), but no Verify is shown and the editor lists it under *Verify links visitors won't see*.
  - **Card background** (each accreditation's own, in its panel): Automatic (the white card, as before; not stored), Transparent (the section's background shows; nothing opaque is drawn), White, the suggestions (Soft ivory, Warm beige and Soft sage green from the site palette, so they follow the design; Pale green `#EEF5EA` and Light grey `#F2F2F0`), any palette colour or a custom `#RRGGBB`. Border, radius, padding and alignment are kept; on a dark colour the text turns light. In the logo strip, Automatic and Transparent show no fill (as before) and a colour fills the 160 px slot.
  - An item needs at least an organisation, a credential or an image. Without an organisation, nothing blank is drawn; screen readers name it by its credential, else "Accreditation" ("<name> logo", "More information about <name>").
  - **Layout of each accreditation** (block settings, in the block's panel under that heading, between *Cards per row on phones* and the list of accreditations; stored only when changed, so existing blocks look and save as before): *Image position* and *Text alignment* (Automatic, left, centre, right; Automatic is left on cards and centred in the logo strip), *Content position* (top, or centre: the cards in a row become the same height with their content in the middle; in the logo strip the items in a row are centred on each other), *Image size* (Automatic, small, medium, large: logos 48/72/104 px tall, certificate images half, three quarters or the full card width; Automatic is a 64 px logo on cards and 72 px in the strip, and a full-width certificate), *Space between image and text* (Automatic: 16 px on cards, 8 px in the strip; or 8–32 px) and *Card padding* (certificate cards only; Automatic 20 px, or 12–32 px). A logo is never wider than its 160 px slot in the strip, or than the card; a wide logo is then less tall. Text applies to the credential, name, description, dates and the link. The editor's canvas and the website use the same renderer (`AccreditationLayout`).
  - Visitors see only what was entered: dates are shown as written ("Issued March 2024 · Expires March 2027", in Tamil too), never turned into "valid", "expired" or "verified". An item without a published logo or certificate shows a plain badge. Image descriptions are the library's alt text, else "<name> logo" / "<name> certificate"; the link reads "More information" (screen readers: "More information about <name>").
- **Custom HTML** (`html`): one field, `html` (up to 20,000 characters, the same for every language), saved exactly as typed (surrounding whitespace trimmed). The editor shows that JavaScript is not supported, what of the markup visitors won't see, and a preview; the canvas shows it as on the site.
  - **Security** (`custom_html.dart`): the markup is never put into the page as HTML. It goes through Google's `sanitize_html` (the HTML5 parser, then GitHub's sanitization rules: no scripts, styles, forms, iframes, objects, embeds, SVG/MathML, event handlers or unsafe URLs), then only an explicit allowlist is drawn as Flutter text and images: headings, paragraphs, lists, quotes, `pre`/`code`, rules, inline formatting and `<img>`. The only attributes used are a link's `href` and `title` and an image's `src`, `alt`, `width` and `height`. A link is followed only to `https://`, `mailto:` or a page of this site (`SafeLinkTarget`); `http:`, protocol-relative, `javascript:`, `data:` and `tel:` links show as plain text. Tables are left out (use the Columns block). Nesting deeper than 32 levels is not drawn. A block with nothing left to show is a problem and isn't saved.
  - **Images** (`CustomHtml.imageAllowed`, checked separately from links): only absolute `https://` addresses with a host and no user name, password or non-default port are loaded; `http:`, relative, protocol-relative, `data:`, `blob:`, `javascript:` and other addresses are never fetched (the editor lists them). An image is drawn at its `width`/`height` (whole pixels, keeping their shape), else at its own size, and always scaled down to the block's width (and at most 960 px tall), so it never overflows on phones. `alt` is its screen-reader description; inside a safe link the image opens the link and the link is announced with the image's `alt` (else the link's `title`); blank text around it in the link is not drawn. An image with a blocked address reads as its description inside a safe link, as before. If an image can't be loaded, its description shows instead. On the web, an image from a site that doesn't allow cross-origin reading is drawn by the browser as a plain `<img>` (Flutter's `WebHtmlElementStrategy.fallback`); nothing else from the markup reaches it. The editor's preview, its canvas and the website use the same renderer; links open only on the website. Visitors' browsers fetch these images from the other site (it sees their IP address, as for any third-party image).
  - **Media library images:** paste the image's `https://` address (its Storage download address). There is no `media:` reference yet, so a Custom HTML image isn't checked at publishing and stops showing if that media item is deleted; for images the school manages, the Image block and Accreditations & Recognition's logo picker remain the better choice.
  - **Limits:** this is formatted text and images, not a web page: no layout, colours, fonts, tables or embeds from the markup; the site's typography applies. `<u>` and `<font>` are removed with their text by the sanitizer. Anything richer would need a sandboxed iframe on a separate origin, which this block deliberately doesn't do.

## Video, form or calendar embed (`embed`)

- **Providers** (`embed_providers.dart`): YouTube, Vimeo, Google Forms and Google Calendar. The block's `source` is the pasted link or the provider's `<iframe>` code, kept as pasted for editing. Every time the block is checked or shown, only the iframe's `src` (or the link) is read, against exact hosts and paths, and the frame's address is **rebuilt** from the ids found (YouTube → `www.youtube-nocookie.com/embed/<id>?rel=0[&start=]`; Vimeo → `player.vimeo.com/video/<id>?dnt=1[&h=]`; Forms → `docs.google.com/forms/d/e/<id>/viewform?embedded=true`; Calendar → `calendar.google.com/calendar/embed` with only `src`, `ctz`, `mode`). Nothing else pasted is used or run; the editor lists what was ignored. Rejected, with the reason: other or lookalike hosts, `http:`, ports and credentials, `javascript:`/`data:`, playlists and channels, form editing and `forms.gle` links, script-based embeds (social posts), badges such as an image in a link.
- **The frame:** per-provider `sandbox` (videos: scripts, same-origin *of the provider*, presentation, popups; Forms adds forms) and `allow` (videos: encrypted-media, picture-in-picture; fullscreen only when the block allows it), never top navigation, downloads, modals, camera, microphone, location, payment or autoplay; `loading="lazy"`, `referrerpolicy="strict-origin-when-cross-origin"`; the block's required title is the frame's `title`.
- **Click to load** (on by default): visitors see a placeholder ("Load YouTube", "Loads content from www.youtube-nocookie.com.") and nothing is fetched from the provider until they press it. The editor's canvas never creates a frame. A link opens the provider's own page.
- **Sizes:** shape Automatic (videos 16:9; forms 800 px, calendars 600 px), 16:9, 4:3, square, or a fixed height (320–1200 px).

## Custom Code: not available yet

Author HTML, CSS and JavaScript must never run in the app's own origin (the public site, admin and parent portals share it, with their sessions). The design (sandboxed frame on a separate origin served with its own CSP and `frame-ancestors` headers) needs a second Hosting site, which is not set up. Until it is reviewed and browser-tested, no Custom Code block type exists in the editor; a block of that type stored by a later version would be kept unchanged and not shown (as any unknown block).

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

## Upcoming events block (`events_feed`)

- **What it shows:** calendar events an admin has put on the website
  (Calendar → Show on website), read only from their sanitized copies in
  `website_public_items`. The public site never reads
  `school_calendar_events` or `school_notifications`.
- **Settings** (stored on the block, never on events):
  - a heading (translatable);
  - at most 3, 4, 6, 9 or 12 events (default 6);
  - a layout: List (one per row), Grid of cards (the default) or Compact
    cards;
  - columns for the card layouts: desktop 1–4 (default 3), tablet 1–3
    (default 2), phone 1–2 (default 1);
  - whether to show event images (default on).

  Phone, tablet and desktop are the site's breakpoints (under 700 px, under
  1,100 px, wider). A card is never narrower than 150 px: in a narrow space,
  such as a section column, fewer columns are used.

  A block saved before these settings existed shows the defaults (a grid).
  Its old `display` value is kept as stored but no longer used.

  It can go on any page, on its own or in a section. The **Events** section
  preset adds it with the heading "Upcoming events".
- **Which events are shown** (`upcomingPublicEvents`): only well-formed
  event items for this school, soonest first (ties by English title).
  - An event with an end time is shown until it ends.
  - An event without one (all-day, or a start time only) is shown until
    the end of its day at school.
  - An item whose expiry has passed is never shown.
  - Announcements aren't shown by this block.
- **Time zone:** the app has no time zone setting, so school time is fixed
  at India Standard Time (UTC+05:30, no daylight saving; `SchoolTimeZone`).
  Every visitor sees the same date and time, labelled IST, whatever their
  device's time zone. Times are entered in the admin's browser, so they are
  correct when admins work in IST. When a time zone setting is added, it
  replaces this constant.
- **Dates and times:** "Sun 14 February 2027", with "9:30 AM – 12:00 PM IST"
  in English or "09:30 – 12:00 IST" in Tamil. An all-day event shows its
  date and "All day", never midnight.
- **Languages:** event text uses each item's own translation, then the
  language's fallback, then English (`LocalizedText.resolve`, as everywhere
  else). Labels, months and weekdays are in English and Tamil
  (`PublicStrings`), and in English for other languages. The Tamil wording
  should be reviewed by a native speaker, as for the rest of the site.
- **Images:** an event's image is shown only when it is a published
  website image with confirmed consent. A missing image is left out; the
  event is still shown. A source's attachments are never copied
  (see `WebsitePublicItem`).
- **Choosing an event's image** (Calendar → Edit → Public website → Event
  image, while "Show on website" is on):
  - **Choose image** picks from the media library. **Upload image** adds a
    photograph to the library (as a draft, outside the gallery) and opens
    it in the library's editor to add alt text, confirm consent and
    publish. **Edit image** reopens it there. **Remove image** takes it off
    the event.
  - The event's copy stores only the image's id, never a URL or storage
    path.
  - Statuses:
    - Uploaded: needs alt text and consent.
    - Approved: consent confirmed, not published yet.
    - Published: visitors see it.
    - Unavailable: deleted, hidden, or its consent withdrawn.
  - Saving with an image that isn't published says the website wasn't
    changed.
  - Republishing without touching the image keeps it, and never uploads
    anything. Replacing or removing changes only the image; translations
    and the registration link are kept.
  - An image used by an event can't be deleted, or hidden, until it is
    removed from the event. Withdrawing its consent still takes it off the
    website at once, and the event's text can still be updated.
- **States:** loading, "No upcoming events.", and an error message with
  Try again. Malformed documents are skipped one by one.
- **Previews:** each event in the block shows its title, date, time,
  location and image (when images are on), never its description. The
  whole description is stored, and shown only on the event's details page.
- **Event details (`/events/<id>`):**
  - On the website, each event in the block is one button (hover and
    focus highlight, Enter or Space, one screen-reader label). It opens
    the event's details at `/events/<calendar event id>`. The address is
    stable, so it can be shared. The id keeps its case.
  - The route is added in `main.dart` beside `/pages/<slug>`. Back returns
    to the page the visitor came from, or Home for a shared link.
  - The page reads that one document from `website_public_items` and
    nothing else. It shows the title, full description, date, time (IST or
    "All day"), location, and the image when it is a published website
    image.
  - An event that was withdrawn, is over, has expired or is malformed
    (and any other address under `/events/`) shows "This event is not
    available", with Back and Back to Home. The same rule as the list
    decides this.
  - In the editor's canvas, events aren't clickable.
- **Registration link** (optional, `registrationUrl` on the website item):
  - It can be a page of this website, or an https, mailto or tel link
    (`SafeLinkTarget`). It is refused when written and ignored when read
    otherwise, and checked again before it is followed.
  - It is shown as "Register" only when present and allowed.
  - It is set through `WebsitePublicItemExtras`; there is no admin control
    for it yet.
- **Freshness:** visitors see the website copy as published, never
  unpublished calendar edits. The list and an event's details are read
  again each time their page is opened, so a republished event appears
  without reloading the site. A page left open keeps what it loaded.
  Publishing in the website editor, or a change in the admin's calendar,
  also reloads them in that session.
- **Description limit:** 2,000 characters, the same in the calendar
  (`CalendarEventModel.maxDescriptionLength`) and on the website copy
  (`WebsitePublicItem.maxBodyLength`). Both count characters the same way:
  after trimming, in UTF-16 code units, so an emoji counts as two.
  - The editor shows a live count, and says by how much a description is
    over.
  - The calendar service and the website service refuse anything longer.
  - Nothing is ever shortened.
- **Calendar status:** "On website" only while visitors actually see the
  event, by the same rule as the list and event pages. Otherwise the
  calendar shows "Not visible on website" with the reason:
  - the event has ended (the copy can be removed);
  - the copy has expired;
  - the copy isn't valid (Update website replaces it).

  An event that has already ended isn't offered "Show on website". A
  failed show or update is reported as a failure, never as shown or
  updated.
- **Out-of-date copies:** a calendar edit reaches the website only through
  the edit dialog's "Show on website" switch, or "Update website". An edit
  made elsewhere leaves the old copy:
  - while the website status couldn't be loaded (saving now says the
    website wasn't changed);
  - from a version of the app without website publishing;
  - from the Firebase console.

  The calendar marks such an event "Website out of date" and says what
  differs (title, date or time, location, description, type).

## Announcements (`announcements_feed`, `/announcements/<id>`)

Built on the same pieces as Upcoming events:
- the sanitized copies in `website_public_items`;
- `WebsitePublicItemsService`;
- the media library;
- the shared layouts and columns (`public_item_cards.dart`);
- the shared admin statuses (`website_copy_status.dart`);
- the shared image picker (`website_item_image_section.dart`).

### Publishing (Notifications → the globe button → Public website)
- **Saving an announcement never touches the website.** Its Public website
  dialog shows where its copy stands. "Show on website", then Save, shows,
  updates or removes it explicitly (`AnnouncementWebsitePublisher`).
- **Who:** only administrators. For anyone else the screen shows no
  website status or actions, and archiving works as before.
- **Which announcements** (`announcementIneligibility`):
  - status **Published**;
  - audience **Public** (the app's "everyone");
  - **not sent to particular classes, students or staff**. A "Public"
    notice can still carry such lists, which make it personal.

  Scheduled, Draft, Archived, Parents, Staff and Admin Only notices are
  refused with the reason. So is an expired one (it isn't newly shown).
- **The copy** (`itemForAnnouncement`):
  - the title and the full message;
  - the publication date: the publish date, else when it was sent, else
    when it was created;
  - the expiry date;
  - the category (the school's English label);
  - the pin;
  - an admin-chosen image (media id);
  - the school.

  The creator, recipients and targeting, attachment, academic year,
  priority, acknowledgement and every other field stay in the app.
- **One copy per announcement** (`announcement_<id>`). Showing again replaces
  it, keeping its first publication time and any translations.
- **Status chips on the list:**
  - On website;
  - Website out of date (an edit since; it names what differs);
  - Remove from website (it can't be shown any more);
  - Not visible on website (with the reason: expired, not yet due, or an
    invalid copy).
- **Failures:** a failed show, update or removal says the website wasn't
  changed, and the dialog stays open. Nothing is reported as shown when
  visitors won't see it.
- **Archiving** removes the copy first. If that fails while it is on the
  website, nothing is archived.

### Visitors
- They see an announcement from its publication date until its expiry
  (`isPublicAnnouncementAvailable`). This is the same rule for the list,
  the page and the admin's status.
- The **Announcements** block: heading, at most 3/4/6/9/12 (default 6),
  List / Grid of cards (default) / Compact cards, and the same columns
  (desktop 1–4, tablet 1–3, phone 1–2) and minimum card width as Upcoming
  events. Its switches:
  - **Show images;**
  - **Show the category;**
  - **Pinned first, marked "Pinned".**

  Previews show the image, labels, title and "Published <date>", never the
  message. Newest first, pinned first when chosen. States: loading, "No
  announcements right now.", and an error with Try again. The
  **Announcements** section preset adds it.
- **`/announcements/<id>`** (registered in `main.dart` beside events):
  - It shows the category, title, publication date, approved image and full
    message.
  - It reads that one document only.
  - Withdrawn, expired, not yet due, other-school, malformed or unknown
    announcements show "This announcement is not available", with Back and
    Back to Home.
  - Back returns to the page the visitor came from, or Home.
- **English and Tamil:** an announcement's own Tamil when present, else
  English. Labels are in both; other languages get English labels.
  Category labels are English.

### Images
- The same as events, in the Public website dialog: Choose, Upload, Edit
  image (alt text, consent, publish in the library's editor) and Remove.
- Statuses: No image, Uploaded, Approved, Published, Unavailable.
- Only a published, consented image can be attached. Changing the image
  keeps translations, and republishing keeps it with no new upload.
- An image used by an announcement can't be deleted or hidden ("… in the
  Notifications first"). Withdrawing consent hides it at once.

### Known limitations
- The website controls are in a dialog beside the announcement's form,
  not inside it: the form reads the signed-in Firebase user and the
  school's class, student and staff lists directly. Edit and save the
  announcement, then update its copy from Public website.
- There are no translation fields for announcements yet (language
  management is separate). Copies keep any translations they are given.
- Announcement messages over 2,000 characters, or titles over 120, can't be
  shown; publishing says so. The notification form doesn't count them.

### Browser UAT
1. Create a Public, Published announcement for everyone. Check that nothing
   appears on the website.
2. Open Public website, switch "Show on website" on, choose or upload an
   image (add alt text, confirm consent, publish), and Save. Check the
   card on a page with an Announcements block, then click it, or Tab and
   press Enter, and check `/announcements/<id>`.
3. Refresh `/announcements/<id>` directly. Back should go Home.
4. Edit the title, and check "Website out of date". Update from Public
   website.
5. Set its audience to Parents, or pick a class, and check "Remove from
   website". Remove it, and check the page is unavailable.
6. Set an expiry date in the past and republish. Check it disappears and
   the list says "Not visible on website".
7. Withdraw the image's consent, and check it disappears at once. Try
   deleting an image an announcement uses.
8. Try each layout and column setting at desktop, tablet and 360 px widths.
9. Archive an announcement that is on the website, and check the copy
   goes.

## Website Publishing Manager (Settings → Website → Publishing manager)
Everything that can go on the website, in one place.
- The data layer is `website_publishing_manager.dart`.
- The screen is `website_publishing_manager_screen.dart`.

It is a view over the existing publishing services, not a second system:
- **Pages** are published with `publishCustomPage` and `publishBuiltInPage`, with their own checks: validation, an empty page, and unpublished images.
- **Events and announcements** go through `WebsitePublicItemsService`. Each has one copy at a fixed id, so nothing can be duplicated. They are judged by the Calendar and Notifications publishers' own rules.

Only admins can use it. Every call checks the role, as the services do.

### Tabs
- **Unpublished items** lists pages, events and announcements that have no website copy.
  - Each row shows its title, type, source status, school, date and whether it can be published.
  - When it can't be published, the row says why.
- **Published items & website status** lists events and announcements that have a copy.
  - Each row shows:
    - its status: On website, Website out of date (with what changed), Not visible (with the reason: ended, expired, not yet due, or an invalid copy) or Remove from website;
    - its image status.
  - **Status filters:**
    - "Unpublished" lists items without a copy, so they can be shown from this tab too.
    - "Failed" lists items whose last action failed.
  - **Pages:** pages aren't listed here, because they are updated and unpublished from their own editors.

### Eligibility
Eligibility is checked by the existing rules, never by the status field alone.
- **Events**
  - The event must be Published and its audience must be Public.
  - The copy must pass its own validation.
  - An event that has ended isn't published.
- **Announcements**
  - The announcement must be Published, with audience Public.
  - It must not be targeted at classes, students or staff.
  - It needs a publication date, and its copy must pass validation.
  - It must not be expired.
  - **Scheduled announcements:** an announcement that won't start until a later date isn't published from here. This is stricter than the Notifications dialog.
  - **Approval:** confirming the bulk dialog is the admin's explicit approval.
- **Additional pages**
  - The draft must not be archived, must pass validation, and must show visitors something.
  - Every image on it must be published.
- **Built-in pages built with the visual editor**
  - They follow the same rules as additional pages.
  - **Already published:** if visitors already see a published version (blocks, or a heading, introduction or image), the page is not published from here. Its editor asks before replacing it, so the admin must use that.
  - The same check as the editor (`builtInHasPublishedVersion`) is used.
- **Not covered:** the older heading, introduction and image forms for built-in pages aren't listed. Publish them from their form.

### Selection and actions
- **Selection is kept by key, not by row,** so it spans every page of results (20 rows per page).
  - "Select all eligible" adds every match of the current filters that an action can apply to, on every page.
  - "Clear selection" empties the selection.
  - Ineligible rows can't be selected.
- **Before acting,** a dialog shows how many are selected, how many will be done and how many will be skipped, with each skipped item's reason.
  - Removing and updating are confirmed the same way.
  - Cancel changes nothing.
- **Runs are sequential.**
  - Before anything is done, everything is re-read. An item that no longer exists, has become ineligible, or is already on the website is skipped. Nothing is published twice, and a page published in the meantime is never replaced.
  - One item failing doesn't stop the others.
  - Afterwards, everything is re-read again. An item reported as done but not confirmed by that re-read is reported as failed, so the run never claims complete success when something failed.
- **The result** lists succeeded, failed and skipped items separately, with reasons.
  - Failed items stay selected and are marked Failed until they succeed, so they can be retried.
  - Each row also has individual actions.

### School scoping
- Website copies carry `schoolId`. The manager lists and changes only the copies of its school (`default_school`).
- Another school's copy is never listed. If an item here has a copy belonging to another school, that copy can't be changed.
- The app's own records (pages, events, announcements) have no school field: there is one school per Firebase project.

### Browser UAT
1. Sign in as an admin and open Settings → Website → Publishing manager. As a teacher, check that the screen is locked.
2. In Unpublished items, check the reasons shown for:
   - a draft event;
   - a Staff event;
   - an event that has ended;
   - a targeted announcement;
   - an expired announcement;
   - a scheduled announcement;
   - an empty page;
   - an archived page.
3. With more than 20 rows, click Select all eligible. Check that the count includes rows on page 2, and that ineligible rows can't be ticked.
4. Click Publish selected and check the confirmation counts. Click Cancel, then publish again. Check the result, the refreshed list and the public website.
5. Run the same items again. Check that they are skipped as "already on the website".
6. Edit an event's title. In Published items, check "Website out of date" and the change listed, then click Update website.
7. Check that "Not visible" is shown, with a reason, for an event that has ended and an announcement that has expired.
8. Remove two items. Check the confirmation, that they disappear from the website, and that the events and announcements are unchanged.
9. Go offline mid-run, or block writes. Check that the failed items are listed with their reasons, stay selected and marked Failed, and that a retry succeeds.
10. Check the layout at desktop, tablet and 360 px widths.

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

## Page block limit

`BlockLimits.pageMaxBlocks` (`content/blocks/block_limits.dart`) is the one page-wide limit: **150 blocks**, counting every block once (top-level blocks, sections and columns blocks, each block in their columns, hidden blocks). It was 40, an early cautious value with no technical reason behind it, which a Home page built from sections reaches quickly; the real constraint is the page document's size (`maxDocumentBytes`, 500 KiB, under Firestore's 1 MiB), still checked on save. Saving (`BlockRegistry.validate`) and the editor's Add controls use the same count. A section or columns block is added only with room for itself, its blocks and one more block (`BlockListOps.canInsert`), so it is never left empty and unusable; options that don't fit are shown disabled with the reason, and the structure panel explains the limit when the page is nearly or completely full. A page stored with more blocks still loads and renders; saving it explains the limit until blocks are removed.

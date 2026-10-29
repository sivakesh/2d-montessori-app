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

## Layouts, items per row, Photo gallery and Map

- **Compatibility rule:** settings added to an existing block type are optional fields marked `omitDefault` (not stored while they hold their default), or `style` keys (stored only when set). A block saved before they existed reads, saves back and renders exactly as before; one built without them (the older section format's conversion) reads their defaults (`StructuredBlock.option` / `toggle`). No migration, no new collection, no rules change: the rules don't inspect blocks.
- **Sections and columns:**
  - Layouts `1`, `1:1`, `1:2`, `2:1`, `1:1:1` and now `1:1:1:1` (four columns), named in the editor ("Four columns"). Changing the layout keeps the existing columns' ids. A layout with fewer columns, when the removed columns hold blocks, asks first and moves those blocks to the end of the last column kept (cancelled, nothing changes; refused when they wouldn't fit in one column).
  - `style.columnGap` and `style.rowGap` (0, 8, 16, 24, 32, 40, 48 or 64 px). Unset: 40 px between columns; 24 px (columns block) or 24/32 px (section, phone/wider) between stacked columns, as before. Padding, content width and space above are the existing options.
  - **Responsive:** phones (< 700 px) stack the columns; tablets (700–1100 px) show up to three side by side, as before, and four as two rows of two; desktops show them all in one row.
- **Items per row** (`cards`, `features`): `desktopColumns` (auto, 1–4), `tabletColumns` (auto = as on desktop, 1–3), `mobileColumns` (auto = one per row, 1–2). `auto` everywhere is the earlier layout (all in one row; stacked on phones). A row's cards share its height. Cards now allow up to eight, points up to eight. Events and announcements keep their own layout and column settings.
- **Photo gallery** (`gallery`, previously "Image grid"): images chosen from the existing media library, in the order set (add several at once with **Add images**, in the order ticked; move up/down; remove). Each image has an optional caption (replacing the library's) and link (else it opens the lightbox). Settings: images per row on desktop (1–6), tablets (auto = desktop), phones (1–3; default 2); shape (landscape 4:3, square, portrait 3:4, wide 16:9); images shown (all, or a limit); captions on or off. Removed or unpublished images are left out for visitors. **School gallery** (`gallery_feed`) still shows every published gallery photograph with its filters; to curate, use a Photo gallery instead.
- **Map** (`map`): heading; address or place name (required, English only, not translated; no `<` or `>`); map type (map or satellite); zoom (10–18); height (240, 320, 400 or 480 px); "Get directions" link (on by default); optional address and contact text (beside the map on wide screens, above it on phones). The map is Google's keyless embed (`https://maps.google.com/maps?q=…&t=m|k&z=…&hl=…&output=embed`, no API key) in an iframe titled "Map showing <place>"; the directions link is a documented Google Maps URL (`/maps/dir/?api=1&destination=…`) and is the way there if the map doesn't load. In the editor's canvas the map doesn't take clicks and the link doesn't open. Off the web (tests) a placeholder stands in for the iframe.
- **Preview:** Desktop, Tablet (820 px) and Mobile (390 px) in the visual editor's canvas.
- **Section text and columns (the Blank section):** every section (the "Blank section" preset is a plain section) has three optional fields above its columns: `eyebrow` (small heading, 60), `heading` (160) and `description` (1000, paragraphs), all `omitDefault`, English-first like other text (stored Tamil kept). Each is drawn only when it has text, in the section's alignment and colours, 12 px apart and 32 px (24 on phones) above the columns; none adds no space. A section with heading text but no visible blocks is shown; one with neither is left out, as before. In the properties form each column can be moved left or right (widths follow: "wider right" becomes "wider left") or removed, and **Add column** adds one (equal widths, up to four). Removing a column that holds blocks asks: move them to the end of the neighbouring column (if they fit), remove them with the column, or cancel. A section keeps at least one column, a columns block two. The operations are `ColumnOps` (`block_list_ops.dart`). Blocks still move only within their column otherwise.
- **Subtitles:** a section's subtitle or introduction is its own heading and description (above); inside a column, a Text block. Other block types don't grow their own subtitle fields.

## Accreditations & Recognition and Custom HTML

Two more block types, added like every other (`block_registry.dart`): stored in the page's `blocks`, drafted, published and unpublished with the page, no new collection, no migration, no rules change.

- **Accreditations & Recognition** (`accreditations`): heading, introduction, *Show as* (certificate cards or logo strip), cards per row on desktop/tablet/phone (`auto` = 3/2/1, stored only when set), and 1–12 items. Each item: organisation or accrediting body (required), credential or recognition, logo and certificate image (media library, optional), short description, verification or certificate link (the site's usual safe links), issue and expiry dates (optional; `2024`, `2024-03` or `2024-03-05`; an expiry before the issue date is a problem). The list order is the display order (move up/down).
  - Visitors see only what was entered: dates are shown as written ("Issued March 2024 · Expires March 2027", in Tamil too), never turned into "valid", "expired" or "verified". An item without a published logo or certificate shows a plain badge. Image descriptions are the library's alt text, else "<name> logo" / "<name> certificate"; the link reads "More information" (screen readers: "More information about <name>").
- **Custom HTML** (`html`): one field, `html` (up to 20,000 characters, the same for every language), saved exactly as typed (surrounding whitespace trimmed). The editor shows that JavaScript is not supported, what of the markup visitors won't see, and a preview; the canvas shows it as on the site.
  - **Security** (`custom_html.dart`): the markup is never put into the page as HTML. It goes through Google's `sanitize_html` (the HTML5 parser, then GitHub's sanitization rules: no scripts, styles, forms, iframes, objects, embeds, SVG/MathML, event handlers or unsafe URLs), then only an explicit allowlist is drawn as Flutter text: headings, paragraphs, lists, quotes, `pre`/`code`, rules and inline formatting. No attribute other than a link's `href` is used, and a link is followed only to `https://`, `mailto:` or a page of this site (`SafeLinkTarget`); `http:`, protocol-relative, `javascript:`, `data:` and `tel:` links show as plain text. Images and tables are left out (use the Image and Columns blocks). Nesting deeper than 32 levels is not drawn. A block with nothing left to show is a problem and isn't saved.
  - **Limits:** this is formatted text, not a web page: no layout, colours, fonts, images, tables or embeds from the markup; the site's typography applies. `<u>` and `<font>` are removed with their text by the sanitizer. Anything richer would need a sandboxed iframe on a separate origin, which this block deliberately doesn't do.

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

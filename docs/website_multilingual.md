# Website languages (multilingual foundation)

> **Current status: editing is English only.** `multilingualEditing = false` (in `website_content_editors.dart`) hides every Tamil and other-language field, the preview-language switches and the translation-readiness panel. The Languages tab (Settings → Website → Languages) stays available, so admins still choose which languages visitors are offered; it notes that, while editing is English only, a page without text in a visitor's language shows the fallback language's text. Stored translations are kept and still shown on the public website. The design below returns with the language module, which adds AI translation and review.


> **Status:** phases L0 and L1 are done in the app. They are tested
> locally (unit, widget and Firestore-emulator tests) and not deployed.
> Translation workflow, AI translation and language URL prefixes are later
> phases (see the end of this document).

## L0: no language is ever dropped

- **`LocalizedText`** (`content/website_content_models.dart`) still stores
  `{en, ta}` exactly as before.
  - It now also keeps every other language key it reads (`hi`, `ml`,
    `te`, `kn`, `fr`, or a code added later) in `others`, and writes them
    back unchanged.
  - Values that aren't text aren't language text and are ignored.
- **Editors and service writes start from the loaded value** and replace
  only English and Tamil, so other languages survive the save. This covers:
  - the built-in page editor, the additional-page editor (title,
    introduction and section text), the site layout editor (identity
    text and link labels) and the media editor (alt text and caption);
  - the service's whole-document writes (built-in page draft and publish,
    additional page draft and publish, media details, site layout).
- **Two deliberate resets:**
  - *Reset to built-in content* (built-in page) restores the built-in
    English and Tamil and keeps other languages.
  - *Start again from current navigation* (site layout) returns the reset
    text to the built-in wording in every language, and its confirmation
    says so. Blank English means "use the built-in wording", and text in
    another language without English isn't allowed.
- **The layout and language drafts** are written with exact top-level
  fields (`mergeFields`), not a deep `merge: true`, so a cleared language
  really is cleared. The additional-page draft keeps its deep merge, which
  only ever adds or updates language keys.
- **Validation** applies length limits to every language. Text in any
  language needs the English (source) text: "…enter the English text as
  well as the Hindi text." Tamil messages are unchanged.
- **Display:** a language's own text, else its fallback language's, else
  English. English and Tamil display exactly as before.
- **Languages are values, not a fixed list.** `PublicLanguage` is a value
  type (code, native name, English name, fallback); `english` and `tamil`
  are the built-in ones.
  - The public switch and the editors' preview pickers are built from a
    list: segments for up to three languages, a menu beyond that.
  - Widget keys are unchanged (`public-language-english`,
    `website-preview-ta`, …).
- **Unchanged:** the interface strings (`PublicStrings`) and the gallery
  category names. Every language other than Tamil uses the English
  interface strings for now.

## L1: language registry

- **One document, `site_languages`,** follows the `site_layout` pattern:
  - the draft in `website_page_drafts/site_languages` (admin only);
  - the published copy in `website_pages/site_languages`
    (visitor-facing fields only).
- **No new collection and no extra read:** visitors get it with the live
  pages query.
- **Shape:**
  ```json
  { "kind": "languages", "schemaVersion": 1, "source": "en", "fallback": "en",
    "languages": [ {"code": "en", "nativeName": "English", "englishName": "English", "enabled": true, "public": true}, … ] }
  ```
- **Initial languages:** English and Tamil enabled and public. Hindi,
  Malayalam, Telugu, Kannada and French are listed but off.
- **Enabled** means offered in the editors' previews. **Public** means
  offered in the visitors' language switch, and only counts when the
  language is also enabled. The list order is the switch order.
- **Rules:**
  - English is the source and must stay enabled and public.
  - The fallback must be enabled and public. Text missing in a language
    shows in the fallback language, then in English.
  - Codes are 2–3 lowercase letters with an optional region (`pt-BR`).
    Codes that are words the website's routes use (`app`, `otp`,
    `pages`, …) are refused.
  - At most 20 languages, and names of at most 40 characters.
- **Adding a language** (Settings → Website → Languages → Add language)
  needs no code change. A new language starts off.
- **Turning a language off,** hiding it, unpublishing the registry or
  starting again never deletes text in any language.
- **Fallback:** with no registry published, or one that can't be used
  (wrong shape, version or invalid), visitors get English and Tamil
  exactly as before. If the language a visitor chose stops being offered,
  the site returns to English.
- **Admin screen:** Settings → Website → Languages offers enable, public,
  reorder, fallback, add, a preview of the real visitors' switch, Save
  draft, Publish and Unpublish (both confirmed), and start again. It is
  admin only, and every service method checks the role.
- **Rules proposal** (`test/firebase_rules/`, not deployed):
  - Live: `kind`, version 1, `source == 'en'`, the fallback a short
    string, and 1–20 languages, with only the visitor-facing fields.
  - Draft: the same shape.
  - Each entry's code and names are checked by the app, because rules
    can't loop over a list.

## Known limits of L0/L1

- **Writing text in Hindi and the other new languages isn't possible
  yet.** It is entered in L2 (manual translation mode). Until then,
  enabling a language adds it to the editors' preview pickers and, if
  public, to the visitors' switch. Its pages show the fallback language's
  text, and the interface stays in English.
- **Older app versions still in browsers** (cached builds) don't know
  `others`. An admin saving on such a build drops non-English/Tamil keys
  from that record. Nothing has those keys yet; the planned separate
  translation documents (L2) remove this risk.
- **Publishing the language registry** checks the code and names in the
  app only (see the rules note above).

## Later phases (need separate approval)

- **L2:** translation records and lifecycle (missing, draft, needs review,
  approved, published, outdated), using per-field source hashes. They are
  kept in separate translation documents, which are new collections.
- **L3:** a public bundle for each language, per-page language
  availability and a coverage report.
- **L4:** AI translation through a protected backend. This needs Cloud
  Functions, Secret Manager and the Blaze plan.
  - **OpenAI is the intended default provider**, through the official API
    with structured output, behind a provider-neutral interface, so the
    provider and model are configuration.
  - API keys are never in Flutter, Firestore or page content.
- **L5:** glossary, context, placeholders and output validation.
- **L6:** language URL prefixes (`/ta/admissions`). These touch route
  generation and need an exception to the authentication freeze.
- **L7:** interface strings and gallery categories in every language.

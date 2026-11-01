# Clean public URLs (no `#`)

The web app uses path URLs: `https://<site>/pages/about` instead of
`https://<site>/#/pages/about`.

> **Status:** the app change is done and tested locally (unit and widget
> tests, plus a local Firebase Hosting emulator). It has **not** been
> deployed or checked in a real browser. No hosting change is required.
> A narrower rewrite is proposed below.

## What changed in the app

- **Before:** the app had no URL strategy set, so Flutter's default hash
  URLs were used. Routing is Navigator 1: `MaterialApp` with `home`, named
  `routes` and `onGenerateRoute` for `/otp` and `/pages/<slug>`
  (`lib/main.dart`).
- **Now:** `main()` calls `configurePublicUrlStrategy()`
  (`lib/modules/public_website/url_strategy/`) before `runApp`.
  - On the web this is Flutter's `PathUrlStrategy`, from the SDK package
    `flutter_web_plugins`. That package was already resolved in
    `pubspec.lock` through the Firebase web plugins; `pubspec.yaml` now
    declares it, and nothing new is downloaded.
  - Old hash links still work. When the path is `/` and the fragment is a
    route (`#/...`), that route is opened (`PublicRoutes.legacyHashRoute`).
    Flutter then replaces the address with the clean path. An ordinary
    `#anchor` is not treated as a route.
  - On Android, and anything else that isn't the web, it does nothing.
- Route names are unchanged:
  - `/`, `/admissions`, `/teacher-training`, `/programs`, `/gallery`,
    `/contact`
  - `/pages/<slug>`
  - `/app`, `/login`, `/otp`, `/dashboard`, `/admin_*`
- Every link already navigates by route name, so navigation links, page
  buttons and Login now produce clean addresses with no other change.
- The language is app state, not part of the address, so switching
  language keeps the address. A refresh starts in English, as before.
- Protected routes keep their own guards, independent of the URL style:
  - `/app` and `/dashboard` show login to signed-out visitors
    (`AuthGate` and `DashboardRoute`).
  - The admin screens check the role.

## Authentication compatibility

Clean URLs were added without changing authentication:
- No authentication file changed. `lib/modules/auth/**`, `AuthGate`,
  `DashboardRoute`, `RoleBasedHome`, `PublicAccountControls` and their
  tests are untouched.
- In `lib/main.dart` the only change is the `configurePublicUrlStrategy()`
  call and its import. The route table, `onGenerateRoute` (including
  `/otp`) and every guard are unchanged.
- The authentication code doesn't read the browser address:
  - Phone sign-in uses a reCAPTCHA element found by its id.
  - The reCAPTCHA domain check and Firebase Auth's session persistence
    (per origin) don't depend on the path.
- One effect to be aware of: Flutter's URL strategy applies to the whole
  app, so the management routes also show as clean paths (`/app`,
  `/login`, `/otp`, `/dashboard`, `/admin_*` instead of `/#/app`, …).
  - They open the same route with the same guards, now and on a refresh.
    The current hosting rewrite serves them, and the proposed rewrite
    lists them explicitly.
  - Old `/#/app`-style links still open the same route.
  - If the management routes must keep `#` addresses, clean URLs can't be
    limited to the public pages with a single Flutter URL strategy.
    Removing the one call in `main()` restores hash URLs everywhere.

## Hosting

`firebase.json` (unchanged):

```json
"hosting": {
  "public": "build/web",
  "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
  "rewrites": [{ "source": "**", "destination": "/index.html" }]
}
```

Firebase Hosting serves a matching static file before applying rewrites.
So this config **already supports clean URLs**: every route returns the
app's `index.html` on refresh or in a new tab, and real assets are served
as themselves. The build's `<base href="/">` (the default
`--base-href`) makes the app's scripts and assets load from deep paths.

Its drawback is that the rewrite matches everything. A missing asset or a
mistyped address returns `index.html` with status 200 instead of 404.

### Proposed narrower rewrite (not applied)

Replace `"rewrites"` with:

```json
"rewrites": [
  { "source": "/", "destination": "/index.html" },
  { "regex": "^/(admissions|teacher-training|programs|gallery|contact|app|login|otp|dashboard)/?$", "destination": "/index.html" },
  { "regex": "^/pages/[A-Za-z0-9-]+/?$", "destination": "/index.html" },
  { "regex": "^/admin_[a-z_]+/?$", "destination": "/index.html" }
]
```

Effect:
- Only the app's own routes get `index.html`.
- Unknown addresses and missing assets get Hosting's 404, which is
  Hosting's default page unless a `404.html` is added.
- Old `/#/...` links request `/`, so they are covered.
- Headers, redirects and `ignore` are unaffected (there are none besides
  `ignore`).

Before adopting it:
- **Keep the list in step with routes.** A new top-level public route
  must be added to the regex, or refreshing it gives a 404.
- The regexes are case-sensitive, except for slugs.
- Decide whether to add a branded `404.html`.

The same config is used for DEV and production (`.firebaserc`: `dev`,
`prod`). Apply it to DEV first.

### Local check (Firebase Hosting emulator, demo project, nothing deployed)

| Request | Current config | Proposed config |
|---|---|---|
| `/`, `/admissions`, `/programs/`, `/pages/open-day` | 200 `index.html` | 200 `index.html` |
| `/app`, `/login`, `/otp`, `/dashboard`, `/admin_dashboard` | 200 `index.html` | 200 `index.html` |
| `/pages/a/b`, `/no-such-page` | 200 `index.html` | 404 |
| `/main.dart.js`, `/flutter_bootstrap.js`, `/favicon.png`, `/manifest.json`, `/assets/AssetManifest.bin.json` | 200, the file | 200, the file |
| `/assets/missing.png` | 200 `index.html` (masks the missing file) | 404 |

## Compatibility

- **Old `/#/` links and bookmarks** keep working through the mapping
  above. This needs confirming in a browser.
- **Mixed paths and fragments:** a URL that has both a path and a route
  fragment (`/programs#/gallery`) opens the path.
- **Cached clients:** visitors with an old cached `main.dart.js` (Flutter
  service worker or browser cache) keep hash URLs until they get the new
  build. Both URL styles keep working throughout.
- **`/otp` refresh: known issue, pre-existing, out of scope.** A refresh on
  `/otp` loses the phone number and shows a blank page. This happened with
  hash URLs too (`/#/otp`); clean URLs only make `/otp` easier to see in
  the address bar. Authentication is frozen, so this is documented and not
  fixed here. Any fix needs separate approval.
- **Unknown start route:** an unknown start address (for example
  `/no-such-page`) opens Home, as it did with hash URLs. In debug builds
  Flutter logs "Could not navigate to initial route".
- **Search engines:** each public page now has its own address. The
  content is still rendered by Flutter, so indexing remains limited (see
  the SEO notes in the architecture review).

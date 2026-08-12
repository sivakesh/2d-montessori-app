# Environment configuration

Non-secret, app-level configuration (site timezone, feature flags, which
`AppEnvironment` a build targets) is supplied via
[`--dart-define-from-file`](https://dartcode.org) rather than committed into
source. Firebase *project* configuration (API keys, project IDs) is handled
separately — see [`docs/architecture/environments.md`](../../docs/architecture/environments.md).

## Files

| File | Tracked in git? | Purpose |
|---|---|---|
| `dev.example.json` / `staging.example.json` / `prod.example.json` | Yes | Documented shape of each environment's config. Copy, don't edit in place. |
| `dev.json` / `staging.json` / `prod.json` | **No** (gitignored) | Your actual local values, copied from the matching `*.example.json`. |

None of the values in these files are secrets — Firebase web config and
feature flags are inherently client-visible. They're kept out of git purely
so environment drift doesn't get committed by accident and so real project
identifiers (once they exist) aren't checked in ahead of the projects being
provisioned, per the Phase 0 scope decision.

## Usage

```bash
cp config/env/dev.example.json config/env/dev.json
flutter run -d chrome --dart-define-from-file=config/env/dev.json
```

## Phase 0 status

`apps/*/lib/main.dart` does not yet read these files — it always boots
against the local Emulator Suite via the safe `demo-` project (see
`packages/firebase_adapters/lib/src/demo_firebase_options.dart`), which is
enough to develop against emulators today. Wiring `--dart-define-from-file`
into environment-selected entrypoints (`main_staging.dart`, `main_prod.dart`)
is a Phase 1 Foundation task, done once the real dev/staging/prod Firebase
projects exist and `flutterfire configure` has generated their
`firebase_options_<env>.dart` files.

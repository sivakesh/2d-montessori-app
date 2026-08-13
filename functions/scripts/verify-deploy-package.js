#!/usr/bin/env node
/**
 * Reproduces, offline and without any Firebase/GCP network call, the
 * exact class of failure a real deployment hit:
 *
 *   "Build failed with status: FAILURE and message: lib/index.js does
 *   not exist."
 *
 * Root cause (found by inspecting the actual deploy pipeline, not
 * guessed): `firebase deploy --only functions` runs the `predeploy` hook
 * (`npm run build`, which compiles `src/**` to `lib/**` via `tsc`) and
 * *then* packages the `functions/` source directory for upload,
 * excluding anything matched by `firebase.json`'s `functions[].ignore`
 * array (gitignore-style glob semantics). That array contained a bare
 * `"lib"` entry — which matches the *entire* `lib/` directory the build
 * step had just produced, at any depth, the same way a bare directory
 * name in a `.gitignore` file does. The predeploy build succeeded
 * locally every time; the compiled output was then silently stripped
 * back out of the bundle actually uploaded to Cloud Build, which is why
 * `npm test`/`npm run build` in CI never caught this — neither one
 * touches the packaging step at all, only `firebase deploy` does.
 *
 * This script simulates that same packaging step using the same
 * gitignore-semantics library (`ignore`) firebase-tools uses internally
 * for this exact array, and fails loudly if the entry point
 * `package.json`'s `main` field declares would not survive it — turning
 * a failure mode that was previously only observable via a real,
 * authenticated deployment into something CI catches on every push.
 *
 * Usage: node scripts/verify-deploy-package.js
 * (wired into `npm run verify:deploy-package`, which runs `npm run
 * build` first — see package.json.)
 */
const fs = require('fs');
const path = require('path');
const ignoreLib = require('ignore');

const functionsDir = path.resolve(__dirname, '..');
const repoRoot = path.resolve(functionsDir, '..');
const firebaseJsonPath = path.join(repoRoot, 'firebase.json');
const packageJsonPath = path.join(functionsDir, 'package.json');

function loadFunctionsDeployConfig() {
  const firebaseJson = JSON.parse(fs.readFileSync(firebaseJsonPath, 'utf8'));
  const configs = Array.isArray(firebaseJson.functions) ? firebaseJson.functions : [firebaseJson.functions];
  const config = configs.find((c) => c && c.source === 'functions');
  if (!config) {
    throw new Error(`Could not find a functions config with "source": "functions" in ${firebaseJsonPath}.`);
  }
  return config;
}

function listAllFiles(dir, base) {
  const results = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...listAllFiles(fullPath, base));
    } else {
      results.push(path.relative(base, fullPath).split(path.sep).join('/'));
    }
  }
  return results;
}

function main() {
  const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
  const mainRel = packageJson.main;
  if (!mainRel) {
    console.error('FAIL: functions/package.json has no "main" field — cannot verify a deploy bundle with no declared entry point.');
    process.exitCode = 1;
    return;
  }

  const entryAbs = path.join(functionsDir, mainRel);
  if (!fs.existsSync(entryAbs)) {
    console.error(`FAIL: declared entry point "${mainRel}" does not exist on disk. Run \`npm run build\` first.`);
    process.exitCode = 1;
    return;
  }

  const config = loadFunctionsDeployConfig();
  const ig = ignoreLib().add(config.ignore || []);
  const allFiles = listAllFiles(functionsDir, functionsDir);
  const included = allFiles.filter((f) => !ig.ignores(f));

  if (!included.includes(mainRel)) {
    console.error('');
    console.error('FAIL: the declared entry point would NOT survive Firebase\'s functions deploy packaging.');
    console.error(`  functions/package.json "main":        ${mainRel}`);
    console.error(`  firebase.json functions[].ignore:     ${JSON.stringify(config.ignore)}`);
    console.error('');
    console.error('This exact condition is what produces, on a real deployment:');
    console.error('  "Build failed with status: FAILURE and message: lib/index.js does not exist."');
    console.error('');
    console.error(`Fix: remove whichever ignore pattern matches "${mainRel}" from firebase.json's functions[].ignore array.`);
    process.exitCode = 1;
    return;
  }

  console.log(
    `OK: "${mainRel}" exists after \`npm run build\` and survives the deploy-package ignore rules ` +
      `(${included.length}/${allFiles.length} files would be uploaded).`,
  );
}

main();

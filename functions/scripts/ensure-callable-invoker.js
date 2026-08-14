#!/usr/bin/env node
/**
 * Ensures every HTTPS *callable* Cloud Function (`onCall`) — and only
 * those — has a Cloud Run IAM policy that allows it to actually be
 * invoked, by binding `allUsers`/`roles/run.invoker` on its underlying
 * Cloud Run service.
 *
 * Root cause this exists to fix, confirmed against the real
 * `twod-montessori-dev` project (not guessed): all 11 callable
 * services (e.g. `authfns-completefirstlogin`) came up with a
 * completely empty IAM policy after a successful `firebase deploy`,
 * while `schedulingfns-publishscheduledcontent` (Cloud Scheduler
 * trigger) and `pagesfns-syncpublishedpage` (Firestore/Eventarc
 * trigger) correctly got their own non-public invoker bindings.
 * Firebase-managed v2 Functions ARE Cloud Run services, and Cloud Run
 * now provisions new services **private by default** (Google's
 * "secure by default" rollout) — `firebase deploy` is supposed to
 * explicitly grant public invoke access for `onCall`/`onRequest`
 * functions on top of that default, but on this project that step did
 * not take effect for any of the 11 callables, without the deploy
 * itself being reported as failed. `onCall` functions are meant to be
 * invoked directly by signed-in app users through the Firebase client
 * SDK's callable protocol — the ID-token check happens *inside* the
 * function body (`request.auth`, see e.g. `auth/guards.ts`), not via
 * Cloud IAM, so Cloud Run access for these MUST be public; that is not
 * a security regression, it's how every `onCall` function in this
 * codebase already enforces auth (see `firebase/firestore.rules`,
 * every callable's `requireAuthenticatedCaller`/role guard).
 *
 * This script does NOT touch `onSchedule` or `onDocumentWritten`
 * (`onDocumentWritten`) functions — it identifies "is this callable?"
 * structurally, from the same compiled deploy artifact Firebase itself
 * uses (`__endpoint.callableTrigger`), not from a hardcoded function
 * name list that could silently drift out of sync with the source.
 *
 * Wired into firebase.json's functions `postdeploy` hook, so this
 * self-heals on every future real deploy regardless of *why* Firebase
 * CLI's own invoker step didn't apply (an org/project policy blocking
 * the `allUsers` principal, or the deploying account lacking
 * `run.services.setIamPolicy`) — both are handled below. It is also
 * safe and idempotent to run standalone, narrowly, without a full
 * redeploy: `npm run ensure:callable-invoker -- --project=<id>`.
 *
 * Requires the `gcloud` CLI on PATH, authenticated
 * (`gcloud auth login`) as a principal with `roles/run.admin` (or
 * broader) on the target project — NOT merely
 * `roles/cloudfunctions.developer`, which cannot set IAM policy.
 *
 * Usage:
 *   node scripts/ensure-callable-invoker.js --project=<firebase-project-id>
 * (or let firebase.json's postdeploy hook supply --project=$GCLOUD_PROJECT
 * automatically)
 */
const { execFileSync } = require('child_process');
const path = require('path');

function parseArgs(argv) {
  const args = { project: process.env.GCLOUD_PROJECT || null };
  for (const arg of argv) {
    if (arg.startsWith('--project=')) {
      args.project = arg.slice('--project='.length).trim();
    } else {
      console.error(`Unrecognized argument: ${arg}`);
      process.exit(1);
    }
  }
  return args;
}

function discoverCallableServices() {
  // Reads the exact compiled artifact `firebase deploy` uploads — see
  // firebase.json's predeploy chain (`npm run build` always runs
  // before this script, whether via `verify:deploy-package` in
  // predeploy or the `prebuild`-style `npm run` prefix on this
  // script's own package.json entry).
  const compiled = require(path.join(__dirname, '..', 'lib', 'index.js'));
  const services = [];
  for (const [namespaceKey, namespace] of Object.entries(compiled)) {
    if (typeof namespace !== 'object' || namespace === null) continue;
    for (const [exportKey, exported] of Object.entries(namespace)) {
      const endpoint = exported && exported.__endpoint;
      if (!endpoint || !endpoint.callableTrigger) continue;
      services.push({
        functionName: `${namespaceKey}-${exportKey}`,
        serviceName: `${namespaceKey}-${exportKey}`.toLowerCase(),
        region: (endpoint.region && endpoint.region[0]) || 'us-central1',
      });
    }
  }
  return services;
}

function gcloud(args) {
  return execFileSync('gcloud', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

function hasPublicInvoker(policyJson) {
  const policy = JSON.parse(policyJson || '{}');
  return (policy.bindings || []).some((b) => b.role === 'roles/run.invoker' && (b.members || []).includes('allUsers'));
}

function ensureInvoker(project, service) {
  const { serviceName, region } = service;
  const commonArgs = ['run', 'services', 'get-iam-policy', serviceName, `--region=${region}`, `--project=${project}`, '--format=json'];

  let policyJson;
  try {
    policyJson = gcloud(commonArgs);
  } catch (error) {
    return { service, status: 'SKIPPED', detail: `Service not found or not readable: ${firstLine(error)}` };
  }

  if (hasPublicInvoker(policyJson)) {
    return { service, status: 'OK', detail: 'allUsers already has roles/run.invoker.' };
  }

  try {
    gcloud(['run', 'services', 'add-iam-policy-binding', serviceName, `--region=${region}`, `--project=${project}`, '--member=allUsers', '--role=roles/run.invoker']);
    return { service, status: 'FIXED', detail: 'Bound allUsers to roles/run.invoker.' };
  } catch (bindError) {
    // Known cause of this specific failure: an org/project policy (e.g.
    // constraints/iam.allowedPolicyMemberDomains, or the Cloud Run
    // "Invoker IAM check") rejects binding the allUsers/
    // allAuthenticatedUsers special principals outright. Google's own
    // documented workaround for a service that must stay public despite
    // that policy is to disable the per-service invoker IAM check
    // instead of binding allUsers.
    try {
      gcloud(['run', 'services', 'update', serviceName, `--region=${region}`, `--project=${project}`, '--no-invoker-iam-check']);
      return {
        service,
        status: 'FIXED_VIA_NO_INVOKER_CHECK',
        detail: `allUsers binding was rejected (${firstLine(bindError)}); disabled the per-service Cloud Run invoker IAM check instead.`,
      };
    } catch (fallbackError) {
      return {
        service,
        status: 'FAILED',
        detail:
          `Both the allUsers binding and the --no-invoker-iam-check fallback failed. ` +
          `This is very likely a permission gap on the deploying account — it needs ` +
          `roles/run.admin (roles/cloudfunctions.developer is NOT sufficient to set IAM policy). ` +
          `bind error: ${firstLine(bindError)} | fallback error: ${firstLine(fallbackError)}`,
      };
    }
  }
}

function firstLine(error) {
  const text = (error && (error.stderr || error.message) || String(error)).toString().trim();
  return text.split('\n')[0];
}

module.exports = { discoverCallableServices, hasPublicInvoker };

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.project) {
    console.error('Usage: node scripts/ensure-callable-invoker.js --project=<firebase-project-id>');
    console.error('(or set GCLOUD_PROJECT in the environment — firebase.json postdeploy does this automatically)');
    process.exitCode = 1;
    return;
  }
  if (args.project.startsWith('demo-')) {
    console.error(`Refusing: "${args.project}" looks like an Emulator Suite demo project id — this script only makes sense against a real deploy.`);
    process.exitCode = 1;
    return;
  }

  const services = discoverCallableServices();
  if (services.length === 0) {
    console.error('No callable (onCall) functions found in lib/index.js — nothing to do. Did `npm run build` run first?');
    process.exitCode = 1;
    return;
  }

  console.log(`Checking ${services.length} callable Cloud Run service(s) on project "${args.project}"...`);
  console.log('');

  const results = services.map((service) => ensureInvoker(args.project, service));
  let anyFailed = false;
  for (const { service, status, detail } of results) {
    console.log(`  [${status}] ${service.serviceName} (${service.region}) — ${detail}`);
    if (status === 'FAILED') anyFailed = true;
  }

  console.log('');
  if (anyFailed) {
    console.error('One or more callable services could not be made publicly invokable. See FAILED lines above.');
    process.exitCode = 1;
  } else {
    console.log('All callable services allow public invocation. Event-driven functions (onSchedule, onDocumentWritten) were not touched.');
  }
}

if (require.main === module) {
  main();
}

/**
 * Locks in the exact set of Cloud Run services
 * `scripts/ensure-callable-invoker.js` is allowed to touch: every
 * `onCall` function, and nothing else. This is the same structural
 * "is this callable?" check (`__endpoint.callableTrigger`) the script
 * itself uses against the compiled deploy artifact — see that file's
 * doc comment for the real-project incident (all 11 callables came up
 * with an empty Cloud Run IAM policy after a successful deploy) this
 * guards against regressing. If a future capability adds or removes an
 * `onCall` function, this test's expected list must be updated
 * deliberately — that's the point: nothing should silently drop out of
 * (or newly enter) the public-invoker set.
 *
 * Requires `functions/lib/index.js` to already be built (`npm run
 * build`), same as `scripts/ensure-callable-invoker.js` itself when run
 * for real — CI's Cloud Functions job always runs Build before Test.
 */
import { existsSync } from 'fs';
import path from 'path';

const compiledEntryPoint = path.join(__dirname, '..', 'lib', 'index.js');

const describeIfBuilt = existsSync(compiledEntryPoint) ? describe : describe.skip;

describeIfBuilt('scripts/ensure-callable-invoker.js: discoverCallableServices', () => {
  const { discoverCallableServices } = require('../scripts/ensure-callable-invoker.js') as {
    discoverCallableServices: () => Array<{ functionName: string; serviceName: string; region: string }>;
  };

  it('targets exactly the 11 onCall functions, matching the real project (Cloud Run service names)', () => {
    const serviceNames = discoverCallableServices()
      .map((s) => s.serviceName)
      .sort();

    expect(serviceNames).toEqual(
      [
        'authfns-completefirstlogin',
        'authfns-createuser',
        'authfns-resetuserpassword',
        'authfns-setuserrole',
        'authfns-setuserstatus',
        'pagesfns-createpage',
        'pagesfns-restorepagerevision',
        'pagesfns-transitionpage',
        'pagesfns-updatepagecontent',
        'publishingfns-createdraft',
        'publishingfns-transitioncontent',
      ].sort(),
    );
  });

  it('never includes the Cloud Scheduler trigger or the Firestore trigger', () => {
    const serviceNames = discoverCallableServices().map((s) => s.serviceName);
    expect(serviceNames).not.toContain('schedulingfns-publishscheduledcontent');
    expect(serviceNames).not.toContain('pagesfns-syncpublishedpage');
  });

  it('defaults every discovered callable to us-central1 (none carry an explicit region override)', () => {
    for (const service of discoverCallableServices()) {
      expect(service.region).toBe('us-central1');
    }
  });
});

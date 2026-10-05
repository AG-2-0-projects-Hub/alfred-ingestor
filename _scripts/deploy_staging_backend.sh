#!/usr/bin/env bash
# Deploy the backend to STAGING safely (written 2026-10-05, see lessons.md "Cloud Run service template can carry a broken test env var").
# usage: bash _scripts/deploy_staging_backend.sh deploy | tag | shift
#   deploy: reads the real SENDGRID_API_KEY in-process from the LIVE revision (never printed), aborts unless it is the only env var that differs
#           from the service template, then `gcloud run deploy --source=backend --update-env-vars=...` (creates a revision with 0% traffic if traffic is pinned)
#   tag:    tags the newest revision (tag "wlcheck") so it can be tested on its own URL before taking traffic
#   shift:  sends 100% of traffic to the newest revision explicitly (not LATEST), removes the tag, prints checks
# Run via `wsl bash -l <abs path>`; gcloud is called by absolute path (see memory reference_gcloud_wsl_invocation). Needs the founder's go: it deploys.
set -euo pipefail
G=~/google-cloud-sdk/bin/gcloud
P="--region=europe-west3 --project=alfred-prod-502215"
SVC=alfred-backend-staging
newest() { $G run revisions list --service=$SVC $P --limit=1 --format="value(metadata.name)"; }
case "${1:-}" in
  deploy)
    LIVE=$($G run services describe $SVC $P --format="value(status.traffic[0].revisionName)")
    $G run revisions describe "$LIVE" $P --format=json > /tmp/live_rev.json
    $G run services describe $SVC $P --format=json > /tmp/svc.json
    python3 - "$LIVE" <<'PY'
import json, os, sys
r = json.load(open('/tmp/live_rev.json')); s = json.load(open('/tmp/svc.json'))
def env(c): return {e['name']: (('secret:' + e['valueFrom']['secretKeyRef']['name']) if 'valueFrom' in e else 'v:' + e.get('value', '')) for e in c}
re_ = env(r['spec']['containers'][0]['env']); se = env(s['spec']['template']['spec']['containers'][0]['env'])
diff = sorted(k for k in set(re_) | set(se) if re_.get(k) != se.get(k))
k = re_.get('SENDGRID_API_KEY', '')[2:]
print('live revision:', sys.argv[1], '| env names that differ from the template:', diff, '| live key length', len(k), 'starts with SG.:', k.startswith('SG.'))
if not k.startswith('SG.') or len(k) < 50 or any(d != 'SENDGRID_API_KEY' for d in diff):
    print('ABORT: unexpected difference or invalid live key, not deploying'); sys.exit(3)
open('/tmp/live_sg_key', 'w').write(k); os.chmod('/tmp/live_sg_key', 0o600)
PY
    cd "$(dirname "$0")/.."
    KEY=$(cat /tmp/live_sg_key)
    $G run deploy $SVC --source=backend $P --update-env-vars="SENDGRID_API_KEY=$KEY" --quiet 2>&1 | tail -12
    rm -f /tmp/live_sg_key /tmp/live_rev.json /tmp/svc.json; unset KEY
    echo "newest revision: $(newest)  (check its traffic: it is 0% if traffic is pinned)";;
  tag)
    NEW=$(newest); $G run services update-traffic $SVC $P --update-tags=wlcheck=$NEW | tail -3
    echo "test it at https://wlcheck---alfred-backend-staging-iz7l3uxudq-ey.a.run.app (health, /api/waitlist/confirm?token=garbage -> 400)";;
  shift)
    NEW=$(newest); $G run services update-traffic $SVC $P --to-revisions=$NEW=100 | tail -3
    $G run services update-traffic $SVC $P --remove-tags=wlcheck | tail -2
    $G run services describe $SVC $P --format=json | python3 -c "
import json,sys
d=json.load(sys.stdin); env={e['name']:e for e in d['spec']['template']['spec']['containers'][0]['env']}
k=env['SENDGRID_API_KEY'].get('value','')
print('traffic:', d['status']['traffic'], '| key length', len(k), 'SG.:', k.startswith('SG.'), '| latest ready:', d['status']['latestReadyRevisionName'])";;
  *) echo "usage: $0 deploy|tag|shift"; exit 2;;
esac

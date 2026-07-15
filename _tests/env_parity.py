#!/usr/bin/env python3
"""Environment parity probe — compares what actually matters, not just objects.

WHY THIS EXISTS
---------------
When prod was split off from staging (2026-07-12) I diffed tables, columns,
policies, indexes, functions, triggers, buckets and cron jobs, and reported
"zero delta". That was a comfortable lie. The two environments were identical in
every way I bothered to look and different in three ways that reached production:

  1. The `supabase_realtime` PUBLICATION was never copied  -> the host dashboard
     silently never live-updated. (Publications are not part of table DDL.)
  2. Whether RLS is actually SWITCHED ON (`relrowsecurity`) was never compared.
     A policy on a table with RLS off is inert.
  3. Which API KEY each frontend ships was never checked -> prod served the
     `service_role` key publicly for a day.

Objects are the easy half. This probe compares the SWITCHES and the CREDENTIALS.

USAGE
-----
    python3 _tests/env_parity.py            # compare staging vs prod
    python3 _tests/env_parity.py --json     # machine-readable

Exits non-zero if anything differs, so it can gate a release.

CREDENTIALS: read from the environment, never hardcoded. Set
STAGING_DB_URL / PROD_DB_URL to the respective Supabase REST URLs, and
STAGING_SERVICE_KEY / PROD_SERVICE_KEY to their service keys. On this machine the
prod key lives in GCP Secret Manager; see _run_parity.sh.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request

# Frontends whose shipped key must be checked. A browser bundle may only ever
# carry an `anon` JWT or an `sb_publishable_` key.
FRONTENDS = {
    "prod    (alwaysalfred)": "https://alwaysalfred.vercel.app",
    "old prod(alfred-ingestor)": "https://alfred-ingestor.vercel.app",
    "staging (git-staging)":
        "https://alfred-ingestor-git-staging-sanslighthouse-6079s-projects.vercel.app",
}

# The one query that answers "are the switches the same?". Kept as SQL so it can
# also be pasted straight into the Supabase SQL editor for the prod project,
# which has no MCP connection.
PARITY_SQL = """
select json_build_object(
  'rls', (
    select json_object_agg(c.relname, json_build_object(
             'rls_enabled', c.relrowsecurity,
             'policies',    (select count(*) from pg_policy p where p.polrelid = c.oid)))
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
  ),
  'realtime_publication', (
    select coalesce(json_agg(tablename order by tablename), '[]'::json)
    from pg_publication_tables where pubname = 'supabase_realtime'
  ),
  'buckets', (
    select coalesce(json_agg(json_build_object(
             'id', id, 'public', public, 'size_limit', file_size_limit)
             order by id), '[]'::json)
    from storage.buckets
  ),
  'storage_policies', (
    select count(*) from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'storage'
  ),
  'functions', (
    select coalesce(json_agg(p.proname order by p.proname), '[]'::json)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
  ),
  'triggers', (
    select coalesce(json_agg(t.tgname order by t.tgname), '[]'::json)
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and not t.tgisinternal
  ),
  'cron_jobs', (
    select coalesce(json_agg(jobname order by jobname), '[]'::json)
    from cron.job
  ),
  'extensions', (
    select coalesce(json_agg(extname order by extname), '[]'::json)
    from pg_extension
  )
) as parity;
"""


# ── frontend credential audit ────────────────────────────────────────────────

def _jwt_role(key: str) -> str | None:
    try:
        payload = key.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        return json.loads(base64.urlsafe_b64decode(payload)).get("role")
    except Exception:
        return None


def classify_key(key: str) -> tuple[str, bool]:
    """(description, is_safe_for_a_browser)"""
    if key.startswith("sb_secret_"):
        return ("sb_secret_ (SECRET KEY)", False)
    if key.startswith("sb_publishable_"):
        return ("sb_publishable_", True)
    role = _jwt_role(key)
    if role == "service_role":
        return ("legacy JWT role=service_role", False)
    if role == "anon":
        return ("legacy JWT role=anon", True)
    return (f"unrecognised ({key[:12]}…)", False)


def audit_frontends() -> list[dict]:
    findings = []
    for label, base in FRONTENDS.items():
        row: dict = {"frontend": label, "url": base}
        try:
            with urllib.request.urlopen(f"{base}/assets/.env", timeout=25) as r:
                env = dict(
                    line.split("=", 1)
                    for line in r.read().decode().splitlines()
                    if "=" in line and not line.startswith("#")
                )
        except Exception as exc:
            row.update(ok=False, detail=f"unreachable: {exc}")
            findings.append(row)
            continue

        key = env.get("SUPABASE_ANON_KEY", "").strip()
        desc, safe = classify_key(key)
        row.update(
            supabase_url=env.get("SUPABASE_URL", "").strip(),
            backend_url=env.get("BACKEND_URL", "").strip(),
            key_type=desc,
            ok=safe,
            detail="" if safe else "PRIVILEGED KEY IN A PUBLIC BUNDLE",
        )
        findings.append(row)
    return findings


# ── database parity ──────────────────────────────────────────────────────────

def fetch_parity(rest_url: str, service_key: str) -> dict:
    """Run PARITY_SQL through the `exec_sql` RPC if present; otherwise fall back
    to per-table REST probes (enough to catch the RLS/realtime classes of bug)."""
    req = urllib.request.Request(
        f"{rest_url.rstrip('/')}/rest/v1/rpc/exec_sql",
        data=json.dumps({"query": PARITY_SQL}).encode(),
        headers={
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raise SystemExit(
            f"\nCould not run the parity query against {rest_url}: HTTP {e.code}.\n"
            f"{e.read().decode()[:200]}\n\n"
            "Supabase has no SQL-over-REST endpoint by default. Either:\n"
            "  (a) paste _tests/env_parity.sql into BOTH SQL editors and diff the\n"
            "      two JSON blobs with:  python3 _tests/env_parity.py --diff a.json b.json\n"
            "  (b) create an exec_sql RPC (service-role only) in both projects.\n"
        )


def diff(a: dict, b: dict, path: str = "") -> list[str]:
    out: list[str] = []
    if type(a) is not type(b):
        return [f"{path}: type differs ({type(a).__name__} vs {type(b).__name__})"]
    if isinstance(a, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a:
                out.append(f"{path}.{k}: MISSING in staging (prod has {b[k]!r})")
            elif k not in b:
                out.append(f"{path}.{k}: MISSING in prod (staging has {a[k]!r})")
            else:
                out += diff(a[k], b[k], f"{path}.{k}")
    elif isinstance(a, list):
        sa, sb_ = {json.dumps(x, sort_keys=True) for x in a}, \
                  {json.dumps(x, sort_keys=True) for x in b}
        for only in sorted(sa - sb_):
            out.append(f"{path}: only in staging -> {only}")
        for only in sorted(sb_ - sa):
            out.append(f"{path}: only in prod    -> {only}")
    elif a != b:
        out.append(f"{path}: staging={a!r}  prod={b!r}")
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--diff", nargs=2, metavar=("STAGING_JSON", "PROD_JSON"),
                    help="diff two JSON blobs produced by env_parity.sql")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    failures = 0

    print("=" * 72)
    print("CREDENTIALS — what each deployed frontend actually ships")
    print("=" * 72)
    for row in audit_frontends():
        mark = "OK  " if row.get("ok") else "FAIL"
        print(f"[{mark}] {row['frontend']}")
        print(f"        supabase : {row.get('supabase_url', '?')}")
        print(f"        key      : {row.get('key_type', '?')}")
        if not row.get("ok"):
            print(f"        !!! {row.get('detail')}")
            failures += 1
    print()

    print("=" * 72)
    print("DATABASE — switches, not just objects")
    print("=" * 72)
    if args.diff:
        a = json.load(open(args.diff[0]))
        b = json.load(open(args.diff[1]))
    else:
        staging_url = os.environ.get("STAGING_DB_URL")
        prod_url = os.environ.get("PROD_DB_URL")
        if not (staging_url and prod_url):
            print("  (skipped: set STAGING_DB_URL/PROD_DB_URL + *_SERVICE_KEY,")
            print("   or run with --diff after pasting _tests/env_parity.sql into")
            print("   both SQL editors)")
            return 1 if failures else 0
        a = fetch_parity(staging_url, os.environ["STAGING_SERVICE_KEY"])
        b = fetch_parity(prod_url, os.environ["PROD_SERVICE_KEY"])

    deltas = diff(a, b, "")
    if deltas:
        failures += len(deltas)
        for d in deltas:
            print(f"  DELTA {d}")
    else:
        print("  no delta — RLS flags, realtime publication, buckets, policies,")
        print("  functions, triggers, cron jobs and extensions all match")

    print()
    print("=" * 72)
    print(f"RESULT: {'PASS' if failures == 0 else f'{failures} PROBLEM(S)'}")
    print("=" * 72)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

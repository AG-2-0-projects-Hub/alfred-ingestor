#!/usr/bin/env python3
"""Health Check Protocol runner — see ../HEALTH_CHECK_PROTOCOL.md for the full
design/rationale. Each check_* function targets one specific real incident
this project already hit; the table in the protocol doc maps checks to rows.

Usage:
    backend/venv/bin/python _tests/health/run_health_check.py [--env staging|prod]

Reads credentials from _tests/fixtures/.env.test (same file the Playwright
runner uses). Exits 0 if every non-skipped check passes, 1 otherwise.

NOTE (2026-09-10): --env prod is accepted but NOT yet properly wired — prod
checks currently fall back to empty PROD_* lookups in this same file and
will mostly SKIP. This needs a real separate-file design (see the session
handoff for exact next steps) before prod checks are meaningful.

NOTE (2026-09-10, revised): the 4 check_gemini_* functions run over Vertex
AI (GCP service-account ADC on this machine), not the Developer API. Staging
has never had its own GEMINI_API_KEY since Batch 6 (2026-07-16) moved it
onto Vertex — confirmed live via `gcloud run services describe
alfred-backend-staging` (GOOGLE_GENAI_USE_VERTEXAI=true, no key env var).
The Developer-API key this used to hit (GEMINI_API_TEST_KEY, free tier) and
prod's own fallback GEMINI_API_KEY (AI Studio prepay, separate billing) were
both tried and both dead — free tier throttled under repeated runs, prod's
key came back "prepayment credits are depleted". Vertex has no such cap and
matches what staging/prod actually run, so these checks now require local
ADC (`gcloud auth application-default login`) instead of any key in
.env.test; they SKIP cleanly if ADC isn't set up.
"""
from __future__ import annotations

import argparse
import base64
import json
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import httpx
from dotenv import dotenv_values

ROOT = Path(__file__).resolve().parents[2]
BACKEND_DIR = ROOT / "backend"
sys.path.insert(0, str(BACKEND_DIR))

ENV = dotenv_values(ROOT / "_tests" / "fixtures" / ".env.test")

GCLOUD = str(Path.home() / "google-cloud-sdk" / "bin" / "gcloud")
GCP_PROJECT = "alfred-prod-502215"
GCP_REGION = "europe-west3"

EXPECTED_MODEL = "gemini-3.8-flash"
MODEL_CONSTANT_FILES = [
    "backend/services/gemini_client.py",
    "backend/services/gemini_messenger.py",
    "backend/services/gemini_merge_resolve.py",
    "scraper/main.py",
]

PROJECT_REFS = {
    "staging": "gcxxilzfhwlsjcvtpsvj",
    "prod": "ylaooctefesedrecshic",
}

CLOUD_RUN_SERVICES = {
    "staging": {"backend": "alfred-backend-staging", "scraper": "alfred-scraper-staging", "min_instances": 0},
    "prod": {"backend": "alfred-backend", "scraper": "alfred-scraper", "min_instances": 1},
}

VERCEL_PROJECT_IDS = {
    "staging": "prj_qywP9BKQKsGuODS1NnprMOB8eBC3",  # alfred-staging
}


@dataclass
class CheckResult:
    name: str
    status: str  # "PASS" | "FAIL" | "SKIP"
    detail: str
    seconds: float = 0.0


def _vercel_headers() -> dict:
    token = ENV.get("VERCEL_BYPASS_TOKEN")
    return {"x-vercel-protection-bypass": token} if token else {}


def _timed(fn):
    def wrapper(*a, **kw) -> CheckResult:
        start = time.monotonic()
        try:
            result = fn(*a, **kw)
        except Exception as exc:  # noqa: BLE001 — a check crashing IS a FAIL, report it
            result = CheckResult(fn.__name__, "FAIL", f"raised {type(exc).__name__}: {exc}")
        result.seconds = time.monotonic() - start
        return result

    return wrapper


# ─── Layer 0: static, no network ───────────────────────────────────────────

@_timed
def check_model_consistency() -> CheckResult:
    """Row 1 — the actual root cause of the 2026-09-10 incident: one file left
    on a deprecated model while every other call site had been migrated."""
    pattern = re.compile(r'gemini-[0-9][\w.\-]*')
    bad: list[str] = []
    for rel in MODEL_CONSTANT_FILES:
        path = ROOT / rel
        if not path.exists():
            bad.append(f"{rel}: file not found")
            continue
        found = set(pattern.findall(path.read_text(encoding="utf-8")))
        stale = found - {EXPECTED_MODEL}
        if stale:
            bad.append(f"{rel}: {sorted(stale)}")
    if bad:
        return CheckResult("model_consistency", "FAIL", "; ".join(bad))
    return CheckResult("model_consistency", "PASS", f"all pinned to {EXPECTED_MODEL}")


# ─── Layer 1: infra health ──────────────────────────────────────────────────

@_timed
def check_backend_health(env: str) -> CheckResult:
    url = ENV["STAGING_BACKEND_URL"] if env == "staging" else ENV.get("PROD_BACKEND_URL", "")
    if not url:
        return CheckResult("backend_health", "SKIP", f"no backend URL configured for {env}")
    resp = httpx.get(f"{url}/health", timeout=15)
    if resp.status_code == 200:
        return CheckResult("backend_health", "PASS", f"{url}/health -> 200")
    return CheckResult("backend_health", "FAIL", f"{url}/health -> {resp.status_code}")


@_timed
def check_scraper_health(env: str) -> CheckResult:
    url = ENV["STAGING_SCRAPER_URL"] if env == "staging" else ENV.get("PROD_SCRAPER_URL", "")
    if not url:
        return CheckResult("scraper_health", "SKIP", f"no scraper URL configured for {env}")
    resp = httpx.get(f"{url}/health", timeout=15)
    if resp.status_code == 200:
        return CheckResult("scraper_health", "PASS", f"{url}/health -> 200")
    return CheckResult("scraper_health", "FAIL", f"{url}/health -> {resp.status_code}")


def _gcloud_json(*args: str) -> dict:
    out = subprocess.run(
        [GCLOUD, *args, "--project", GCP_PROJECT, "--region", GCP_REGION, "--format", "json"],
        capture_output=True, text=True, timeout=30, check=True,
    )
    return json.loads(out.stdout)


@_timed
def check_cloud_run_traffic(env: str) -> CheckResult:
    """Row 4 — a stuck rollout serving a bad revision at partial traffic."""
    service = CLOUD_RUN_SERVICES[env]["backend"]
    data = _gcloud_json("run", "services", "describe", service)
    splits = data.get("status", {}).get("traffic", [])
    latest = data.get("status", {}).get("latestReadyRevisionName")
    if len(splits) == 1 and splits[0].get("percent") == 100 and splits[0].get("revisionName") == latest:
        return CheckResult("cloud_run_traffic", "PASS", f"{service}: 100% -> {latest}")
    return CheckResult("cloud_run_traffic", "FAIL", f"{service}: traffic split is {splits}, expected 100% -> {latest}")


@_timed
def check_cloud_run_min_instances(env: str) -> CheckResult:
    """Row 5 — prod's min-instances=1 is load-bearing (BackgroundTasks CPU-freeze
    otherwise, see lessons.md 2026-07-13); a reverted value is a real incident."""
    cfg = CLOUD_RUN_SERVICES[env]
    service = cfg["backend"]
    data = _gcloud_json("run", "services", "describe", service)
    annotations = data.get("spec", {}).get("template", {}).get("metadata", {}).get("annotations", {})
    raw = annotations.get("autoscaling.knative.dev/minScale", "0")
    actual = int(raw)
    expected = cfg["min_instances"]
    if actual == expected:
        return CheckResult("cloud_run_min_instances", "PASS", f"{service}: min-instances={actual}")
    return CheckResult(
        "cloud_run_min_instances", "FAIL",
        f"{service}: min-instances={actual}, expected {expected}",
    )


# ─── Layer 2: live Gemini smoke tests — real API calls, real app code ──────
# Each imports the ACTUAL backend module and calls the ACTUAL function the
# live app uses, so this exercises real prompts/retry logic, not a reimplemented
# stand-in. This is what would have caught the 2026-09-10 incident directly.
# Runs over Vertex AI (ADC) — see the module docstring for why the Developer
# API path (a key in .env.test) was dropped.

def _vertex_env():
    import os
    os.environ.setdefault("GOOGLE_GENAI_USE_VERTEXAI", "true")
    os.environ.setdefault("GOOGLE_CLOUD_PROJECT", GCP_PROJECT)
    os.environ.setdefault("GOOGLE_CLOUD_LOCATION", "global")


def _vertex_adc_available() -> bool:
    try:
        import google.auth
        google.auth.default()
        return True
    except Exception:
        return False


@_timed
def check_gemini_ingest_text() -> CheckResult:
    """Row 2/3 — the exact call path that was 100% broken on 2026-09-10."""
    if not _vertex_adc_available():
        return CheckResult("gemini_ingest_text", "SKIP", "no local ADC (run: gcloud auth application-default login)")
    _vertex_env()
    import asyncio
    from services import gemini_client
    text = asyncio.run(gemini_client.process_with_prompt_a_text(
        "Wifi password: Sunshine123. Check-in: 3pm. Check-out: 11am."
    ))
    if text and len(text) > 10:
        return CheckResult("gemini_ingest_text", "PASS", f"{len(text)} chars returned")
    return CheckResult("gemini_ingest_text", "FAIL", f"empty/short response: {text!r}")


@_timed
def check_gemini_merge() -> CheckResult:
    if not _vertex_adc_available():
        return CheckResult("gemini_merge", "SKIP", "no local ADC (run: gcloud auth application-default login)")
    _vertex_env()
    import asyncio
    from services import gemini_merge_resolve
    result = asyncio.run(gemini_merge_resolve.run_merger(
        scraped_markdown="# Test Villa\nCheck-in: 3pm. Wifi: TestNet / pass123.",
        ingested_markdown="Host note: extra towels in the hall closet.",
        nickname="Health Check Test Property",
    ))
    if isinstance(result, dict) and result:
        return CheckResult("gemini_merge", "PASS", f"{len(result)} top-level keys returned")
    return CheckResult("gemini_merge", "FAIL", f"unexpected result: {result!r}")


@_timed
def check_gemini_chat() -> CheckResult:
    if not _vertex_adc_available():
        return CheckResult("gemini_chat", "SKIP", "no local ADC (run: gcloud auth application-default login)")
    _vertex_env()
    import asyncio
    from services import gemini_messenger
    result = asyncio.run(gemini_messenger.first_pass(
        master_json={"property_identity": {"property_name": "Health Check Test Property"}},
        conversation_history=[],
        preferred_language="en",
        guest_message="What time is check-in?",
    ))
    if isinstance(result, dict) and result:
        return CheckResult("gemini_chat", "PASS", "first_pass returned a parsed response")
    return CheckResult("gemini_chat", "FAIL", f"unexpected result: {result!r}")


@_timed
def check_gemini_summarizer() -> CheckResult:
    if not _vertex_adc_available():
        return CheckResult("gemini_summarizer", "SKIP", "no local ADC (run: gcloud auth application-default login)")
    _vertex_env()
    import asyncio
    from services import gemini_messenger
    result = asyncio.run(gemini_messenger.summarize_escalation([
        {"sender_type": "guest", "content": "The wifi is not working."},
        {"sender_type": "host", "content": "Try restarting the router under the TV."},
    ]))
    if isinstance(result, dict) and result:
        return CheckResult("gemini_summarizer", "PASS", "summarize_escalation returned a parsed response")
    return CheckResult("gemini_summarizer", "FAIL", f"unexpected result: {result!r}")


# ─── Layer 3: data / security probes ───────────────────────────────────────

@_timed
def check_rls_anon_blocked(env: str) -> CheckResult:
    """Row 7 — regression guard for the real 2026-07-13 cross-tenant leak: a
    host once saw another host's properties because an anon-role query wasn't
    blocked. Confirms the anon key still sees zero rows on tenant tables."""
    anon_key = ENV.get("SUPABASE_ANON_KEY")
    supabase_url = ENV.get("SUPABASE_URL") if env == "staging" else ENV.get("PROD_SUPABASE_URL", "")
    if not anon_key or not supabase_url:
        return CheckResult("rls_anon_blocked", "SKIP", "SUPABASE_ANON_KEY/SUPABASE_URL not set")
    leaks = []
    for table in ("properties", "guests", "conversations", "messages"):
        resp = httpx.get(
            f"{supabase_url}/rest/v1/{table}",
            params={"select": "id", "limit": "1"},
            headers={"apikey": anon_key, "Authorization": f"Bearer {anon_key}"},
            timeout=15,
        )
        if resp.status_code == 200 and resp.json():
            leaks.append(table)
    if leaks:
        return CheckResult("rls_anon_blocked", "FAIL", f"anon key can read rows from: {leaks}")
    return CheckResult("rls_anon_blocked", "PASS", "anon key returns zero rows on all tenant tables")


def _decode_jwt_role(token: str) -> tuple[str | None, str | None]:
    try:
        payload_b64 = token.split(".")[1]
        payload_b64 += "=" * (-len(payload_b64) % 4)
        payload = json.loads(base64.urlsafe_b64decode(payload_b64))
        return payload.get("role"), payload.get("ref")
    except Exception:
        return None, None


@_timed
def check_deployed_supabase_key(env: str) -> CheckResult:
    """Rows 12/19/20 — the real 2026-07-13 incident: prod's Vercel shipped the
    service_role key instead of anon for ~1 day (BUG-029). Flutter compiles its
    .env into the bundle and serves it verbatim at /assets/.env (confirmed live
    2026-09-10 — this is far more reliable than regex-scanning main.dart.js,
    which is minified/chunked and not guaranteed to contain the literal string).
    Since BUG-029's fix, keys are the new sb_publishable_/sb_secret_ format, not
    legacy JWTs — this checks both formats."""
    frontend_url = ENV["STAGING_FRONTEND_URL"] if env == "staging" else ENV.get("PROD_FRONTEND_URL", "")
    if not frontend_url:
        return CheckResult("deployed_supabase_key", "SKIP", f"no frontend URL configured for {env}")
    headers = _vercel_headers()
    resp = httpx.get(frontend_url.rstrip("/") + "/assets/.env", headers=headers, timeout=20, follow_redirects=True)
    if resp.status_code != 200 or resp.text.strip().startswith("<!DOCTYPE") or resp.text.strip().startswith("<html"):
        return CheckResult("deployed_supabase_key", "SKIP", f"/assets/.env not fetchable (status {resp.status_code}, or SPA fallback returned — bundle layout may have changed)")

    values = dict(re.findall(r'^([A-Z_]+)=(.*)$', resp.text, flags=re.MULTILINE))
    key = values.get("SUPABASE_ANON_KEY", "")
    deployed_url = values.get("SUPABASE_URL", "")
    expected_ref = PROJECT_REFS[env]

    if key.startswith("sb_secret_"):
        return CheckResult("deployed_supabase_key", "FAIL", "a sb_secret_ key is shipped in the public bundle — this is the exact BUG-029 failure mode")
    if expected_ref not in deployed_url:
        return CheckResult("deployed_supabase_key", "FAIL", f"deployed SUPABASE_URL is '{deployed_url}', expected project ref '{expected_ref}' — cross-wired environments")
    if key.startswith("sb_publishable_"):
        return CheckResult("deployed_supabase_key", "PASS", f"sb_publishable_ key shipped, URL matches ref '{expected_ref}'")
    if key.startswith("eyJ"):
        role, ref = _decode_jwt_role(key)
        if role == "service_role":
            return CheckResult("deployed_supabase_key", "FAIL", "service_role JWT is shipped in the public bundle — this is the exact BUG-029 failure mode")
        if role == "anon" and ref == expected_ref:
            return CheckResult("deployed_supabase_key", "PASS", f"legacy anon JWT shipped, ref matches '{expected_ref}' (consider migrating to sb_publishable_)")
        return CheckResult("deployed_supabase_key", "FAIL", f"unexpected JWT role/ref: role={role}, ref={ref}")
    prefix = key.split("_")[0] if "_" in key else key[:3]
    return CheckResult("deployed_supabase_key", "FAIL", f"SUPABASE_ANON_KEY has an unrecognized format (prefix: {prefix!r}, length: {len(key)}) — never print the full value, inspect the live /assets/.env directly if needed")


@_timed
def check_frontend_reachable(env: str) -> CheckResult:
    frontend_url = ENV["STAGING_FRONTEND_URL"] if env == "staging" else ENV.get("PROD_FRONTEND_URL", "")
    if not frontend_url:
        return CheckResult("frontend_reachable", "SKIP", f"no frontend URL configured for {env}")
    resp = httpx.get(frontend_url, headers=_vercel_headers(), timeout=20, follow_redirects=True)
    if resp.status_code == 200:
        return CheckResult("frontend_reachable", "PASS", f"{frontend_url} -> 200")
    return CheckResult("frontend_reachable", "FAIL", f"{frontend_url} -> {resp.status_code}")


@_timed
def check_vercel_build(env: str) -> CheckResult:
    """Row 11 — Vercel serving a stale/failed build silently. Checks the most
    recent deployment's state; an ERRORED latest deployment means Vercel is
    quietly still serving whatever built successfully before it."""
    token = ENV.get("VERCEL_API_TOKEN")
    project_id = VERCEL_PROJECT_IDS.get(env)
    if not token or not project_id:
        return CheckResult("vercel_build", "SKIP", "VERCEL_API_TOKEN or project id not set for this env")
    resp = httpx.get(
        "https://api.vercel.com/v6/deployments",
        params={"projectId": project_id, "limit": "1", "target": "production" if env == "staging" else "production"},
        headers={"Authorization": f"Bearer {token}"},
        timeout=20,
    )
    if resp.status_code != 200:
        return CheckResult("vercel_build", "FAIL", f"Vercel API returned {resp.status_code}")
    deployments = resp.json().get("deployments", [])
    if not deployments:
        return CheckResult("vercel_build", "SKIP", "no deployments found for this project")
    latest = deployments[0]
    state = latest.get("state") or latest.get("readyState")
    if state == "READY":
        return CheckResult("vercel_build", "PASS", f"latest deployment state=READY")
    return CheckResult("vercel_build", "FAIL", f"latest deployment state={state} — Vercel may be silently serving an older build")


@_timed
def check_telegram_webhook(env: str) -> CheckResult:
    """Row 15 — a stale webhook URL after a redeploy goes silent with no error
    anywhere except Telegram's own getWebhookInfo. Staging only for now (prod
    bot token not wired — same pattern as GEMINI_API_TEST_KEY, deliberately
    kept separate from prod credentials)."""
    if env != "staging":
        return CheckResult("telegram_webhook", "SKIP", "only wired for staging (see docstring)")
    token = ENV.get("TELEGRAM_BOT_TOKEN_TEST")
    if not token:
        return CheckResult("telegram_webhook", "SKIP", "TELEGRAM_BOT_TOKEN_TEST not set")
    resp = httpx.get(f"https://api.telegram.org/bot{token}/getWebhookInfo", timeout=15)
    data = resp.json()
    if not data.get("ok"):
        return CheckResult("telegram_webhook", "FAIL", f"getWebhookInfo not ok: {data}")
    info = data["result"]
    if not info.get("url"):
        return CheckResult("telegram_webhook", "FAIL", "no webhook URL registered")
    if info.get("last_error_message"):
        return CheckResult("telegram_webhook", "FAIL", f"last_error_message: {info['last_error_message']}")
    return CheckResult("telegram_webhook", "PASS", f"webhook set, pending={info.get('pending_update_count', 0)}, no errors")


@_timed
def check_whatsapp_token(env: str) -> CheckResult:
    """Row 14 — a silently expired/revoked token or unsubscribed app (BUG-040's
    exact failure mode: webhook verified fine, zero real messages ever arrived).
    Staging only for now, using its own separate test WABA — see
    HEALTH_CHECK_PROTOCOL.md for why staging and prod deliberately stay on
    different numbers."""
    if env != "staging":
        return CheckResult("whatsapp_token", "SKIP", "only wired for staging (see docstring)")
    token = ENV.get("WHATSAPP_ACCESS_TOKEN_TEST")
    phone_id = ENV.get("WHATSAPP_PHONE_NUMBER_ID_TEST")
    if not token or not phone_id:
        return CheckResult("whatsapp_token", "SKIP", "WHATSAPP_ACCESS_TOKEN_TEST/PHONE_NUMBER_ID_TEST not set")
    resp = httpx.get(
        f"https://graph.facebook.com/v25.0/{phone_id}",
        params={"fields": "verified_name,code_verification_status,quality_rating"},
        headers={"Authorization": f"Bearer {token}"},
        timeout=15,
    )
    if resp.status_code != 200:
        return CheckResult("whatsapp_token", "FAIL", f"Graph API returned {resp.status_code} — token likely expired/revoked")
    data = resp.json()
    return CheckResult("whatsapp_token", "PASS", f"token valid, quality_rating={data.get('quality_rating')}")


@_timed
def check_firecrawl(env: str) -> CheckResult:
    """Row 16 — Firecrawl key/quota exhausted blocks all new property scraping.
    One cheap live smoke scrape against a stable, tiny page."""
    key = ENV.get("FIRECRAWL_API_KEY_TEST")
    if not key:
        return CheckResult("firecrawl", "SKIP", "FIRECRAWL_API_KEY_TEST not set")
    resp = httpx.post(
        "https://api.firecrawl.dev/v1/scrape",
        json={"url": "https://example.com"},
        headers={"Authorization": f"Bearer {key}"},
        timeout=30,
    )
    if resp.status_code != 200:
        return CheckResult("firecrawl", "FAIL", f"Firecrawl API returned {resp.status_code}")
    if not resp.json().get("success"):
        return CheckResult("firecrawl", "FAIL", f"success=false: {resp.json()}")
    return CheckResult("firecrawl", "PASS", "scrape succeeded")


@_timed
def check_orphaned_test_data(env: str) -> CheckResult:
    """Row 18 — optional: needs a service-role key, deliberately NOT stored in
    the shared .env.test (too privileged for a file with that access pattern).
    Set SUPABASE_SERVICE_ROLE_KEY_TEST locally to enable; skipped otherwise."""
    service_key = ENV.get("SUPABASE_SERVICE_ROLE_KEY_TEST")
    supabase_url = ENV.get("SUPABASE_URL") if env == "staging" else ENV.get("PROD_SUPABASE_URL", "")
    if not service_key or not supabase_url:
        return CheckResult("orphaned_test_data", "SKIP", "SUPABASE_SERVICE_ROLE_KEY_TEST not set (see docstring)")
    resp = httpx.get(
        f"{supabase_url}/rest/v1/properties",
        params={"select": "id,name,updated_at", "master_json": "is.null", "deleted_at": "is.null", "limit": "50"},
        headers={"apikey": service_key, "Authorization": f"Bearer {service_key}"},
        timeout=15,
    )
    if resp.status_code != 200:
        return CheckResult("orphaned_test_data", "FAIL", f"query failed: {resp.status_code}")
    rows = resp.json()
    if not rows:
        return CheckResult("orphaned_test_data", "PASS", "no un-merged properties found")
    return CheckResult("orphaned_test_data", "PASS", f"{len(rows)} un-merged properties exist (informational, not a failure — review manually)")


CHECKS_LAYER0 = [check_model_consistency]
CHECKS_LAYER1 = [check_backend_health, check_scraper_health, check_cloud_run_traffic, check_cloud_run_min_instances]
CHECKS_LAYER2 = [check_gemini_ingest_text, check_gemini_merge, check_gemini_chat, check_gemini_summarizer]
CHECKS_LAYER3 = [check_rls_anon_blocked, check_deployed_supabase_key, check_frontend_reachable, check_vercel_build, check_telegram_webhook, check_whatsapp_token, check_firecrawl, check_orphaned_test_data]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env", choices=["staging", "prod"], default="staging")
    args = parser.parse_args()

    print(f"Health Check Protocol — env={args.env}\n")
    results: list[CheckResult] = []

    print("── Layer 0: static ──")
    for check in CHECKS_LAYER0:
        results.append(check())

    print("── Layer 1: infra health ──")
    for check in CHECKS_LAYER1:
        results.append(check(args.env))

    print("── Layer 2: live Gemini smoke (real API calls) ──")
    for check in CHECKS_LAYER2:
        results.append(check())

    print("── Layer 3: data / security probes ──")
    for check in CHECKS_LAYER3:
        results.append(check(args.env))

    icon = {"PASS": "✅", "FAIL": "\U0001F534", "SKIP": "⚪"}
    for r in results:
        print(f"{icon[r.status]} {r.status:4} {r.name:28} ({r.seconds:.1f}s)  {r.detail}")

    failed = [r for r in results if r.status == "FAIL"]
    skipped = [r for r in results if r.status == "SKIP"]
    passed = [r for r in results if r.status == "PASS"]
    print(f"\n{len(passed)} passed, {len(failed)} failed, {len(skipped)} skipped")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())

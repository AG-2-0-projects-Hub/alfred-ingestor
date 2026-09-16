#!/usr/bin/env python3
"""Optional code review via an OpenRouter model — for critical changes only
(pre-`main` merge, auth/security touches), never automatic, never Claude
subagents (those cost Claude Code session credits; this costs OpenRouter API
credits instead, which is the whole point).

Usage:
    python3 _scripts/or_code_review.py [--base REF] [--model MODEL]

    --base REF   Compare REF..HEAD plus any uncommitted changes. Default:
                 origin/staging (everything not yet on staging's remote).
    --model      Override the model. Default: qwen/qwen3.7-flash (picked
                 2026-09-16 after a 2-model validation pass against a real
                 known regression from this project's own history — the
                 much pricier mistral-small-3.2-24b-instruct said "NO ISSUES
                 FOUND" on the exact same diff and was rejected; qwen3.7-flash
                 correctly flagged it, and a negative-control clean diff
                 confirmed it doesn't just flag everything by default).

Reads OPENROUTER_API_KEY from the shared ~/AG_master_files/_scripts/.env
(same key the QA runner's vision judge and graphify's pipeline use).
"""
import argparse
import json
import subprocess
import sys
import urllib.request
from pathlib import Path

DEFAULT_MODEL = "qwen/qwen3.7-flash"
MAX_DIFF_CHARS = 60_000  # keep well under the model's context; truncate rather than fail silently

REVIEW_PROMPT = """\
You are a senior engineer doing a focused code review of the diff below. Look specifically for:
1. Correctness bugs — logic errors, edge cases, off-by-one, wrong conditionals.
2. Blast radius — does this change affect callers/behavior beyond what the diff's own \
comments/commit message claim? (e.g. a shared helper's default changed for every caller, \
not just the one being fixed).
3. Regressions — something that worked before this diff and doesn't after.
4. Security — injection, secrets, auth bypass, unsafe deserialization.

Do NOT comment on style, formatting, or naming. Only report things you are reasonably \
confident are real bugs, not stylistic preferences.

For each finding, respond as one line in this exact format:
FILE: <path> | LINE: <approx line or range> | SEVERITY: <high|medium|low> | ISSUE: <one sentence>

If you find nothing real, respond with exactly: NO ISSUES FOUND

Diff:
{diff}
"""


def load_openrouter_key() -> str:
    env_path = Path.home() / "AG_master_files/_scripts/.env"
    if not env_path.exists():
        sys.exit(f"Missing {env_path} — OPENROUTER_API_KEY must live there (shared root key).")
    for line in env_path.read_text().splitlines():
        if line.startswith("OPENROUTER_API_KEY="):
            return line.split("=", 1)[1].strip()
    sys.exit(f"OPENROUTER_API_KEY not found in {env_path}")


def get_diff(base: str) -> str:
    committed = subprocess.run(
        ["git", "diff", f"{base}...HEAD"], capture_output=True, text=True, check=False
    ).stdout
    uncommitted = subprocess.run(
        ["git", "diff", "HEAD"], capture_output=True, text=True, check=False
    ).stdout
    diff = (committed + "\n" + uncommitted).strip()
    if not diff:
        sys.exit(f"No diff between {base} and the working tree — nothing to review.")
    return diff


def review(diff: str, model: str, api_key: str) -> str:
    if len(diff) > MAX_DIFF_CHARS:
        diff = diff[:MAX_DIFF_CHARS] + "\n\n[... truncated, diff too large for one pass ...]"
    body = json.dumps(
        {
            "model": model,
            "messages": [{"role": "user", "content": REVIEW_PROMPT.format(diff=diff)}],
        }
    ).encode()
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions",
        data=body,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        payload = json.load(resp)
    return payload["choices"][0]["message"]["content"]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base", default="origin/staging")
    parser.add_argument("--model", default=DEFAULT_MODEL)
    args = parser.parse_args()

    api_key = load_openrouter_key()
    diff = get_diff(args.base)
    print(f"Reviewing {len(diff)} chars of diff (base={args.base}) via {args.model}...\n")
    print(review(diff, args.model, api_key))


if __name__ == "__main__":
    main()

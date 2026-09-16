#!/usr/bin/env bash
# Deterministic structural check for the-ingestor's Session End / Wrap-up (see CLAUDE.md).
# Checks structure only, never content quality — PASS/FAIL, no judgment calls.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0
check() {
  local ok=$1 msg=$2
  if [ "$ok" -eq 0 ]; then
    echo "PASS: $msg"
  else
    echo "FAIL: $msg"
    fail=1
  fi
}

grep -q '^## Pending' CONTEXT.md
check $? "'## Pending' heading present in CONTEXT.md"

grep -q '^## Unresolved Decisions' CONTEXT.md
check $? "'## Unresolved Decisions' heading present in CONTEXT.md"

pending_lines=$(awk '/^## Pending$/{flag=1; next} /^## /{flag=0} flag' CONTEXT.md | wc -l)
[ "$pending_lines" -le 15 ]
check $? "'## Pending' section is <=15 lines (currently $pending_lines)"

digest_entries=$(grep -c '^## Session ' _Context/session-digest.md 2>/dev/null || echo 0)
[ "$digest_entries" -le 5 ]
check $? "session-digest.md has <=5 entries (currently $digest_entries)"

if grep -q 'Define after BLAST Blueprint phase' CLAUDE.md; then
  check 1 "CLAUDE.md Stack/Data Schema filled in (still placeholder text)"
else
  check 0 "CLAUDE.md Stack/Data Schema filled in"
fi

# QA gate (added 2026-09-16, see CLAUDE.md '## QA Workflow'): backend/frontend source
# changed without a matching _tests/scenarios.md diff in the same range. Structural only —
# it can't judge whether the right scenario was logged, only whether scenarios.md moved at all.
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
committed_changed=""
if [ -n "$upstream" ]; then
  committed_changed=$(git diff --name-only "$upstream...HEAD" 2>/dev/null || true)
fi
uncommitted_changed=$(git status --porcelain 2>/dev/null | sed -E 's/^...//; s/.* -> //')
changed_files=$(printf '%s\n%s\n' "$committed_changed" "$uncommitted_changed" | sort -u)

source_changed=$(printf '%s\n' "$changed_files" | grep -E '^(backend/|frontend/lib/)' || true)
scenarios_changed=$(printf '%s\n' "$changed_files" | grep -Fx '_tests/scenarios.md' || true)

if [ -n "$source_changed" ] && [ -z "$scenarios_changed" ]; then
  n=$(printf '%s\n' "$source_changed" | grep -c .)
  first=$(printf '%s\n' "$source_changed" | head -1)
  check 1 "QA gate: $n backend/frontend file(s) changed (e.g. $first) with no _tests/scenarios.md diff — run the same-session targeted replay and log a pending-intake row"
else
  check 0 "QA gate: backend/frontend changes have a matching scenarios.md diff (or none)"
fi

exit $fail

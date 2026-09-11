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

exit $fail

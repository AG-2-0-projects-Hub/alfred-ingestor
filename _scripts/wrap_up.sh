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

# Self-check (added 2026-09-16, see lessons.md): the Edit tool used to write this
# very file has reset its executable bit 3/3 times this session. `-x` tests the
# actual on-disk permission, independent of how this run was invoked (bash vs
# direct), so it catches the regression even when invoked via `bash wrap_up.sh`.
[ -x _scripts/wrap_up.sh ]
check $? "_scripts/wrap_up.sh has its executable bit set (chmod +x if not)"

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

# Lessons-index sync gate (added 2026-09-16, see CLAUDE.md '## Session End / Wrap-up' step 4):
# doesn't judge whether a lesson was worth logging (that's a judgment call) — only that
# lessons_index.md never silently drifts out of sync with whatever IS in lessons.md, since a
# built-but-unmaintained index is worse than no index (this project already lived that once
# with the QA-scenario check itself).
lessons_entries=$(grep -c '^## ' lessons.md 2>/dev/null || echo 0)
index_rows=$(grep -c '^| [0-9]' lessons_index.md 2>/dev/null || echo 0)
[ "$lessons_entries" -eq "$index_rows" ]
check $? "lessons_index.md row count ($index_rows) matches lessons.md entry count ($lessons_entries)"

# FIX-VERIFY protocol gate (added 2026-09-17, see FIX_VERIFY_PROTOCOL.md): opt-in, not applied
# to every commit -- only commits that carry a "Protocol: FIX_VERIFY" trailer are checked. Each
# one must state how it was verified, and if it touched frontend/lib/ it must also add/change a
# _tests/runner/scenarios/ file AND wire it into run.ts in the SAME commit -- reusing an existing
# scenario doesn't count (the whole point is building coverage that didn't exist before), and an
# unwired scenario file never actually runs again, so it doesn't count either.
fv_commits=""
if [ -n "$upstream" ]; then
  fv_commits=$(git log --format='%H' "$upstream..HEAD" 2>/dev/null | while read -r sha; do
    git log -1 --format='%B' "$sha" | grep -qi '^Protocol: FIX_VERIFY$' && echo "$sha"
  done)
fi

fv_fail=0
fv_detail=""
for sha in $fv_commits; do
  msg=$(git log -1 --format='%B' "$sha")
  if ! printf '%s\n' "$msg" | grep -qi '^Verified:'; then
    fv_fail=1
    fv_detail="$fv_detail; ${sha:0:7} missing a 'Verified:' line"
    continue
  fi
  files=$(git diff-tree --no-commit-id --name-only -r "$sha")
  if printf '%s\n' "$files" | grep -q '^frontend/lib/'; then
    if ! printf '%s\n' "$files" | grep -q '^_tests/runner/scenarios/'; then
      fv_fail=1
      fv_detail="$fv_detail; ${sha:0:7} touches frontend/lib/ with no new/changed _tests/runner/scenarios/ file"
    elif ! printf '%s\n' "$files" | grep -Fxq '_tests/runner/run.ts'; then
      fv_fail=1
      fv_detail="$fv_detail; ${sha:0:7} added/changed a scenario file but didn't wire it into run.ts"
    fi
  fi
done

if [ -n "$fv_commits" ]; then
  check $fv_fail "FIX-VERIFY protocol commits have Verified: + a real scenario for any frontend change${fv_detail}"
else
  check 0 "FIX-VERIFY protocol gate (no commits opted in this session)"
fi

exit $fail

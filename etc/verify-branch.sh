#!/bin/bash
#
# verify-branch.sh — run the pre-push gate against ONE worktree, named explicitly.
#
# WHY THIS EXISTS
#   The gate in CLAUDE.md §3 is half a dozen commands with two environment
#   requirements, and it was being reassembled by hand every time. On 2026-09-08
#   a single session hand-assembled it four times and omitted the `cd` in two of
#   them, so the build ran in whichever worktree the shell happened to be in.
#   Both runs went green, and both were green about the wrong tree. One was
#   caught only because the example count of the wrong tree happened to differ.
#
#   The cwd of a Bash tool call is not stable between calls in agent harnesses,
#   so "remember to cd first" is not a control. Here the worktree is a REQUIRED
#   ARGUMENT: there is nothing to forget, and the tree that was actually tested
#   is printed at the top and the bottom of every run, so a truncated log still
#   says which one it was.
#
# USAGE
#   etc/verify-branch.sh [--quick] [--base <ref>] <absolute-worktree-path>
#
#     --quick        skip jl4-test (~12 min). Everything else still runs.
#     --base <ref>   what to diff against for changed-file checks and commit
#                    trailers. Default origin/unstable.
#
#   Exits 0 only if every check that ran passed. Any failure is fatal and named
#   in the summary table.
#
# WHAT IT DOES NOT CHECK — stated because a green run must not be mistaken for
# CI. See the memory note "local gate is not CI".
#   DMN engine harnesses, the `go` selftest, jl4-mlir, the WASM build, Nix, and
#   TypeScript. A PR that passes this can still go red in CI on any of those.
#
set -uo pipefail

QUICK=0
BASE=origin/unstable
WT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --quick) QUICK=1; shift ;;
    --base)  BASE="${2:-}"; [ -n "$BASE" ] || { echo "--base needs a ref" >&2; exit 2; }; shift 2 ;;
    -h|--help) sed -n '3,32p' "$0"; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *)  [ -z "$WT" ] || { echo "give exactly one worktree path" >&2; exit 2; }; WT="$1"; shift ;;
  esac
done

[ -n "$WT" ] || { echo "usage: $0 [--quick] [--base <ref>] <absolute-worktree-path>" >&2; exit 2; }

# An absolute path is the whole point: a relative one would be resolved against
# whatever directory the caller happens to be in, which is the bug this script
# exists to remove.
case "$WT" in
  /*) ;;
  *) echo "FATAL: worktree path must be absolute, got '$WT'" >&2; exit 2 ;;
esac
[ -d "$WT" ] || { echo "FATAL: no such directory: $WT" >&2; exit 2; }
git -C "$WT" rev-parse --git-dir >/dev/null 2>&1 || { echo "FATAL: not a git worktree: $WT" >&2; exit 2; }

HEAD_SHA=$(git -C "$WT" rev-parse --short HEAD)
BRANCH=$(git -C "$WT" branch --show-current)
LIBS="$WT/jl4-core/libraries"
export JL4_LIBRARY_PATH="$LIBS"

banner() {
  echo "────────────────────────────────────────────────────────────────────"
  echo "  worktree : $WT"
  echo "  branch   : ${BRANCH:-<detached>}   HEAD $HEAD_SHA"
  echo "  base     : $BASE ($(git -C "$WT" rev-parse --short "$BASE" 2>/dev/null || echo '?'))"
  echo "  libs     : $JL4_LIBRARY_PATH"
  echo "────────────────────────────────────────────────────────────────────"
}
banner

RESULTS=()
FAILED=0
step() { # step <label> <command...>
  local label="$1"; shift
  printf '\n=== %s ===\n' "$label"
  if "$@"; then
    RESULTS+=("PASS  $label"); return 0
  else
    RESULTS+=("FAIL  $label"); FAILED=1; return 1
  fi
}
note() { RESULTS+=("      $*"); }

# ---------------------------------------------------------------- pre-flight
# Concurrent cabal invocations inside ONE worktree corrupt each other and
# produce a phantom `renameFile:renamePath ... .o.tmp does not exist` that reads
# as a code error and is not (CLAUDE.md §2.1). Refuse rather than produce one.
if pgrep -f "$WT.*cabal|cabal.*$WT" >/dev/null 2>&1; then
  echo "FATAL: a cabal process is already running in this worktree." >&2
  echo "       One at a time, or you get phantom .o.tmp errors." >&2
  exit 3
fi

# A stale ~/.local/bin/l4 shadows the worktree build and fails doc examples that
# are perfectly valid. Warn rather than fail: it only matters for test-docs.
if command -v l4 >/dev/null 2>&1; then
  WHICH_L4=$(command -v l4)
  case "$WHICH_L4" in
    "$WT"/*) ;;
    *) echo "WARNING: 'l4' on PATH is $WHICH_L4, not this worktree's build."
       echo "         doc/test-docs.sh may fail on valid examples. Symlink the"
       echo "         cabal binary first on PATH if you need the L4 half." ;;
  esac
fi

# `*.evaldiff.l4` sit inside the corpus globs and would be goldened if committed.
STRAY=$(find "$WT/jl4" "$WT/jl4-core" -name '*.evaldiff.l4' 2>/dev/null | head -5)
if [ -n "$STRAY" ]; then
  echo "FATAL: stray .evaldiff.l4 files present — they are inside corpus globs:" >&2
  echo "$STRAY" | sed 's/^/       /' >&2
  exit 3
fi

# ---------------------------------------------------------------- the gate
step "cabal build all" bash -c "cd '$WT' && cabal build all 2>&1 | grep -viE '^ *ld: warning' | grep -iE 'error' && exit 1 || exit 0"

if [ "$QUICK" = 1 ]; then
  note "jl4-test SKIPPED (--quick)"
else
  step "jl4-test (corpus goldens + round-trip)" \
    bash -c "cd '$WT' && cabal test jl4-test 2>&1 | tee /tmp/vb-jl4-test.\$\$ | grep -E 'examples,|PASS|FAIL' | tail -3; grep -q 'jl4-test: PASS' /tmp/vb-jl4-test.\$\$"
fi

step "l4-cli-test"    bash -c "cd '$WT' && cabal test l4-cli-test 2>&1 | tee /tmp/vb-cli.\$\$ | grep -E 'examples,|PASS|FAIL' | tail -2; grep -q 'l4-cli-test: PASS' /tmp/vb-cli.\$\$"
step "jl4-core-test"  bash -c "cd '$WT' && cabal test jl4-core-test 2>&1 | tee /tmp/vb-core.\$\$ | grep -E 'examples,|PASS|FAIL' | tail -2; grep -q 'jl4-core-test: PASS' /tmp/vb-core.\$\$"

step "check-corpus-goldens" bash -c "cd '$WT' && node etc/check-corpus-goldens.mjs"

step "doc/test-docs.sh --no-l4" bash -c "cd '$WT' && ./doc/test-docs.sh --no-l4 2>&1 | tail -6"

# Prettier over the WHOLE repo trips on a missing workspace package in a fresh
# worktree (`@repo/prettier-config` under ts-apps), which is an install gap and
# not a formatting defect. Check the files this branch actually changed.
CHANGED=$(git -C "$WT" diff --name-only "$BASE"...HEAD 2>/dev/null | grep -E '\.(md|mjs|yml|yaml|json|ts|js|svelte)$' || true)
if [ -n "$CHANGED" ]; then
  # shellcheck disable=SC2086
  step "prettier 3.4.2 (changed files)" bash -c "cd '$WT' && npx -y prettier@3.4.2 --check $(echo $CHANGED | tr '\n' ' ')"
else
  note "prettier SKIPPED (no changed files it handles)"
fi

# ---------------------------------------------------------------- hygiene
printf '\n=== commit trailers ===\n'
MISSING=0
while IFS= read -r c; do
  [ -n "$c" ] || continue
  if ! git -C "$WT" log -1 --format='%B' "$c" | grep -q '^Claude-Session:'; then
    echo "  MISSING Claude-Session: $(git -C "$WT" log -1 --format='%h %s' "$c")"
    MISSING=1
  fi
done < <(git -C "$WT" rev-list --no-merges "$BASE".."$HEAD_SHA" 2>/dev/null)
if [ "$MISSING" = 1 ]; then RESULTS+=("FAIL  commit trailers"); FAILED=1
else echo "  all commits carry Claude-Session"; RESULTS+=("PASS  commit trailers"); fi

# `L4.Print` has TWO printers with different guards, and the round-trip property
# is weaker than it looks: a printer that drops a bracket emits source that
# parses, type-checks, and evaluates to a DIFFERENT answer. CLAUDE.md §3.2.1.
if git -C "$WT" diff --name-only "$BASE"...HEAD 2>/dev/null | grep -q 'L4/Print.hs'; then
  RESULTS+=("      L4/Print.hs CHANGED — run the §3.2.1 evaluation differential BY HAND;")
  RESULTS+=("      the round-trip property alone will not catch a re-association bug.")
fi

# ---------------------------------------------------------------- summary
echo
banner
echo "  RESULTS"
for r in "${RESULTS[@]}"; do echo "    $r"; done
echo
echo "  NOT CHECKED: DMN engine harnesses, go selftest, jl4-mlir, WASM, Nix,"
echo "               TypeScript. A green run here is not a green CI."
echo "────────────────────────────────────────────────────────────────────"
rm -f /tmp/vb-jl4-test.$$ /tmp/vb-cli.$$ /tmp/vb-core.$$
exit "$FAILED"

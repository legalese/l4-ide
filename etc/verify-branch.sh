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
#   etc/verify-branch.sh [--quick] [--serial] [--fast] [--base <ref>] <absolute-worktree-path>
#
#     --quick        skip jl4-test (~12 min). Everything else still runs.
#     --fast         PARTIAL GATE, never the default. If EVERY path changed since --base (committed, staged,
#                    unstaged or untracked) is a markdown file or a corpus .l4 / golden under
#                    jl4/examples/{ok,legal,canon,not-ok,lsp}/ that no test source names, run a reduced gate:
#                      docs only   the file checks, no build and no suite;
#                      corpus      the file checks, `cabal build jl4-test`, and jl4-test restricted to the
#                                  changed files and every file that imports them (etc/gate-fast-select.mjs).
#                    Anything else runs the full gate, and the run says why. Either way it says which, at the
#                    top and the bottom. A reduced run is NOT a substitute for the full gate or for CI.
#                    With L4_GATE_BIN_CACHE=<dir>, a corpus run reuses a jl4-test binary built from identical
#                    build inputs (etc/gate-bin-cache.mjs) instead of building one. Cannot be combined with --quick.
#     --serial       run the test suites one after another. The default runs them at
#                    the same time, after one serial build of all of them, because
#                    two cabal processes that BUILD in one worktree corrupt each
#                    other (CLAUDE.md §2.1) while processes that only run built
#                    test binaries do not. Use --serial to tell a failure caused by
#                    the suites running together from one that is not.
#     --base <ref>   what to diff against for changed-file checks and commit
#                    trailers. Default origin/unstable.
#
#   Exits 0 only if every check that ran passed. Any failure is fatal and named
#   in the summary table. A test suite that fails keeps its full log, and the
#   run prints the log's path and the failing examples; passing suites' logs go.
#
# CONDITIONAL PROBES — each runs only when the diff against --base touches what
# it guards, and each came from a review the test suites had passed
# (specs/todo/MAIN-PRE-REVIEW.md):
#   (a) jl4-core/src/L4/Parser*: `l4 check` CPU time at 1,000 and 4,000 lines
#       (etc/probe-parse-scaling.mjs). FAIL above a ratio of 8.
#   (b) jl4-service/: the same calls before and after a restart
#       (etc/probe-service-restart.mjs). FAIL on any difference.
#   (c) jl4/tests-cli/: new assertions comparing output without dropping '\r'
#       (etc/probe-cli-crlf.mjs). WARN only: it reads text, not behaviour.
#
# WHAT IT DOES NOT CHECK — stated because a green run must not be mistaken for
# CI. See the memory note "local gate is not CI".
#   Test suites NOT run here, although CI runs `cabal test all`: jl4-lsp-test,
#   jl4-mlir-test, jl4-websessions-test, jl4-proleg-burden, jl4-proleg-roundtrip.
#   Named as suites on purpose — this list used to say only `jl4-mlir`, between
#   the WASM build and Nix, where it read as the MLIR backend among build targets
#   rather than as a suite among suites, so five missing suites looked like one.
#   Also not run: DMN engine harnesses, the `go` selftest, the WASM build, Nix,
#   and TypeScript. A PR that passes this can still go red in CI on any of those.
#
set -uo pipefail

QUICK=0
SERIAL=0
FAST=0
BASE=origin/unstable
WT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --quick) QUICK=1; shift ;;
    --serial) SERIAL=1; shift ;;
    --fast) FAST=1; shift ;;
    --base)  BASE="${2:-}"; [ -n "$BASE" ] || { echo "--base needs a ref" >&2; exit 2; }; shift 2 ;;
    -h|--help) sed -n '3,/^set -uo pipefail/p' "$0" | sed '$d'; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *)  [ -z "$WT" ] || { echo "give exactly one worktree path" >&2; exit 2; }; WT="$1"; shift ;;
  esac
done

[ -n "$WT" ] || { echo "usage: $0 [--quick] [--serial] [--fast] [--base <ref>] <absolute-worktree-path>" >&2; exit 2; }
[ "$FAST" = 1 ] && [ "$QUICK" = 1 ] && { echo "--fast and --quick contradict each other: --fast chooses what jl4-test runs" >&2; exit 2; }

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

# ---------------------------------------------------------------- --fast: may this diff take the reduced gate?
# Decided before the banner so that the first thing printed says which gate this is. The selector is the
# one in the tree under test; a branch that predates it cannot take the reduced gate. Any doubt is `full`.
FAST_MODE=""
FAST_WHY=""
FAST_FILES=()
FAST_MATCH_OPTS=()
FAST_NOTES=()
PARTIAL_LINE="PARTIAL GATE (--fast): CI and the full gate run more"
if [ "$FAST" = 1 ]; then
  if [ ! -f "$WT/etc/gate-fast-select.mjs" ]; then FAST_WHY="this tree has no etc/gate-fast-select.mjs"
  elif ! command -v node >/dev/null 2>&1; then FAST_WHY="node is not installed"
  elif ! FAST_SEL=$(cd "$WT" && node etc/gate-fast-select.mjs --base "$BASE" "$WT" 2>&1); then FAST_WHY="the selector failed: $(echo "$FAST_SEL" | grep -m1 -E 'Error|fatal' | head -c 300)"
  else
    FAST_VERDICT=""
    while IFS=$'\t' read -r k v; do
      case "$k" in
        VERDICT) FAST_VERDICT=$v ;;
        REASON)  FAST_WHY="${FAST_WHY:+$FAST_WHY; }$v" ;;
        NOTE)    FAST_NOTES+=("$v") ;;
        FILE)    FAST_FILES+=("$v") ;;
        MATCH)   FAST_MATCH_OPTS+=(--match "$v") ;;
      esac
    done <<< "$FAST_SEL"
    case "$FAST_VERDICT" in
      docs|corpus) FAST_MODE=$FAST_VERDICT ;;
      full) ;;
      *) FAST_WHY="the selector gave no verdict" ;;
    esac
  fi
fi
partial_banner() {
  if [ -n "$FAST_MODE" ]; then
    echo "################################################################"
    echo "  $PARTIAL_LINE"
    echo "  reduced gate: $FAST_MODE"
    echo "################################################################"
  elif [ "$FAST" = 1 ]; then
    echo "  FULL GATE: --fast was asked for and fell through, because: $FAST_WHY"
  fi
}
partial_banner

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

# ---------------------------------------------------------------- logs
# Each test suite's output goes to a log in a directory made for this run. A
# suite that passes deletes its log. A suite that fails keeps it, prints its
# path and the failing examples, and the summary names it again.
#
# The log's path is chosen HERE and handed to the step. Until 2026-10-08 each
# step's `bash -c "..."` named its own file, /tmp/vb-<suite>.$$, where $$ was
# the inner bash's pid, while the cleanup at the end removed /tmp/vb-<suite>.$$
# with this script's pid. The two never matched, so every run left its logs
# behind (about 300 files and 30 MB in /tmp when it was noticed), and nothing
# pointed at a failing suite's log, the one file worth reading.
LOGDIR=$(mktemp -d "${TMPDIR:-/tmp}/verify-branch.XXXXXX") \
  || { echo "FATAL: cannot create a log directory" >&2; exit 2; }
KEPT=()
# The probes below run copies of the built binaries, kept here and always removed.
PROBEDIR=$(mktemp -d "${TMPDIR:-/tmp}/verify-branch-probe.XXXXXX") \
  || { echo "FATAL: cannot create a probe directory" >&2; exit 2; }
# On any exit, Ctrl-C included, the log directory goes unless a failed suite's log is in it.
cleanup() { rm -rf "$PROBEDIR"; [ "${#KEPT[@]}" -gt 0 ] || rm -rf "$LOGDIR"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# A suite is started (its `cabal test` writes the log), then reported (the
# summary lines, the verdict, the failing examples). Splitting the two lets the
# suites run at the same time and still be reported in a fixed order.
suite_start() { # suite_start <cabal test target | jl4-test:<slice>>
  local target="$1" log="$LOGDIR/$1.log"
  case "$target" in
    jl4-test:*)
      # One slice of the jl4-test examples, run from the built binary, because four `cabal test`
      # processes would write one test log. This is what `cabal test jl4-test` sets up for it:
      # the package directory as cwd, and the two data directories.
      shard_opts "${target#jl4-test:}"
      ( cd "$WT/jl4" && env jl4_datadir="$WT/jl4" jl4_core_datadir="$WT/jl4-core" \
          "$JL4_TEST_BIN" "${SHARD_OPTS[@]}" > "$log" 2>&1 \
        && echo "Test suite $target: PASS" >> "$log" ) & ;;
    *) ( cd "$WT" && cabal test "$target" > "$log" 2>&1 ) & ;;
  esac
  LAST_SUITE_PID=$!
  SUITE_PIDS="$SUITE_PIDS $!"
}
# jl4-test as four processes, chosen by hspec example path. Whatever the three named slices do not select
# lands in "rest", so no example is missed; the example counts are checked against hspec's own count below.
# Measured on nye (10 cores): 299 s against 663-679 s for one process; the slowest slice is prettyLayout.
shard_opts() { # shard_opts <slice> sets SHARD_OPTS
  case "$1" in
    canon)        SHARD_OPTS=(--match "ok files/canon/") ;;
    oknotcanon)   SHARD_OPTS=(--match "ok files/" --skip "ok files/canon/") ;;
    prettylayout) SHARD_OPTS=(--match "prettyLayout round-trip") ;;
    rest)         SHARD_OPTS=(--skip "ok files/" --skip "prettyLayout round-trip") ;;
    fast)         SHARD_OPTS=(${FAST_MATCH_OPTS[@]+"${FAST_MATCH_OPTS[@]}"}) ;;   # --fast: see fast_corpus
  esac
}
suite_report() { # suite_report <label> <cabal test target> <summary lines to show>
  local label="$1" target="$2" lines="$3" log="$LOGDIR/$2.log"
  printf '\n=== %s ===\n' "$label"
  grep -E 'examples,|PASS|FAIL' "$log" | tail -"$lines"
  if grep -q "$target: PASS" "$log"; then
    RESULTS+=("PASS  $label"); rm -f "$log"
    return 0
  fi
  RESULTS+=("FAIL  $label"); FAILED=1
  KEPT+=("$log")
  echo "  full log: $log"
  # hspec numbers each failure "  1) <the example's path>". A suite that did not
  # build, or crashed, has none, so show the end of its log instead.
  if grep -qE '^  [0-9]+\) ' "$log"; then
    grep -E '^  [0-9]+\) ' "$log" | head -20 | sed 's/^ */  failed: /'
  else
    tail -15 "$log" | sed 's/^/  | /'
  fi
  return 1
}
LAST_SUITE_PID=
SUITE_PIDS=""
# The suites, in report order: <label>|<cabal test target>|<summary lines to show>.
# jl4-service-test renders a state graph over the HTTP surface and asserts its captions
# (jl4-service/test/IntegrationSpec.hs). Added 2026-09-22: a caption change on
# lts/draw-what-it-means turned it red while this script stayed green, because it was not here.
SUITES=()
if [ "$QUICK" != 1 ]; then
  if [ "$SERIAL" = 1 ]; then SUITES+=("jl4-test (corpus goldens + round-trip)|jl4-test|3")
  else
    SUITES+=("jl4-test, slice canon|jl4-test:canon|3" "jl4-test, slice ok files outside canon|jl4-test:oknotcanon|3")
    SUITES+=("jl4-test, slice prettyLayout round-trip|jl4-test:prettylayout|3" "jl4-test, slice everything else|jl4-test:rest|3")
  fi
fi
SUITES+=("l4-cli-test|l4-cli-test|2" "jl4-core-test|jl4-core-test|2" "jl4-service-test|jl4-service-test|2")

# The checks below read files and run node or git; none of them touches cabal or the
# built binaries, so they can run while the test suites do (see the gate section).
static_checks() {
  step "check-corpus-goldens" bash -c "cd '$WT' && node etc/check-corpus-goldens.mjs"

  # Citations INTO legalese/canon. Selftest first -- a checker's green means
  # nothing until something has shown it can go red. The sweep itself needs no
  # canon checkout for the file:line and assertion-count classes, which resolve
  # against the vendored mirror; NOTES.md section citations print as explicitly
  # unchecked when canon is absent, and CANON_DIR=... makes them checkable. This
  # gate does not pass --require, because a laptop without canon beside l4-ide is
  # a normal state and not a branch defect.
  step "check-canon-citations --selftest" bash -c "cd '$WT' && node etc/check-canon-citations.mjs --selftest"
  step "check-canon-citations" bash -c "cd '$WT' && node etc/check-canon-citations.mjs"

  # The vendored mirror under jl4/examples/canon/ must equal legalese/canon at the
  # pin (CLAUDE.md §3.1). Nothing above looks at that: jl4-test compares the
  # mirror's files with the mirror's own goldens, so a mirror file edited together
  # with its golden stays green here and goes red only in CI's Canon Mirror job.
  # A merge makes exactly that edit, with no conflict, when one side moves a file
  # into the mirror and the other side edits it at its old path (measured
  # 2026-09-24 on #489). --check fetches canon at the pin; its exit 3 means canon
  # was unreachable, which offline is a normal state and not a branch defect, so
  # it is noted rather than failed.
  step "sync-canon --selftest" bash -c "cd '$WT' && node etc/sync-canon.mjs --selftest | tail -1; exit \${PIPESTATUS[0]}"
  printf '\n=== sync-canon --check (mirror = canon at the pin) ===\n'
  (cd "$WT" && node etc/sync-canon.mjs --check)
  case $? in
    0) RESULTS+=("PASS  sync-canon --check (mirror = canon at the pin)") ;;
    3) note "sync-canon --check SKIPPED: canon unreachable at the pin; CI's Canon Mirror job still runs it" ;;
    *) RESULTS+=("FAIL  sync-canon --check (mirror = canon at the pin)"); FAILED=1 ;;
  esac

  step "doc/test-docs.sh --no-l4" bash -c "cd '$WT' && ./doc/test-docs.sh --no-l4 2>&1 | tail -6; exit \${PIPESTATUS[0]}"

  # Prettier over the WHOLE repo trips on a missing workspace package in a fresh
  # worktree (`@repo/prettier-config` under ts-apps), which is an install gap and
  # not a formatting defect. Check the files this branch actually changed, and
  # only those that still exist: `--diff-filter=d` leaves out deletions, which
  # prettier would otherwise report as "No files matching the pattern".
  # --fast classifies the working tree, uncommitted and untracked files included, so it checks those too:
  # for a docs-only diff, prettier is the one check that reads the edited text.
  CHANGED=$( { git -C "$WT" diff --name-only --diff-filter=d "$BASE"...HEAD 2>/dev/null
               if [ -n "$FAST_MODE" ]; then git -C "$WT" diff --name-only --diff-filter=d HEAD 2>/dev/null; git -C "$WT" ls-files -o --exclude-standard 2>/dev/null; fi
             } | sort -u | grep -E '\.(md|mjs|yml|yaml|json|ts|js|svelte)$' || true)
  if [ -n "$CHANGED" ]; then
    # shellcheck disable=SC2086
    step "prettier 3.4.2 (changed files)" bash -c "cd '$WT' && npx -y prettier@3.4.2 --check $(echo $CHANGED | tr '\n' ' ')"
  else
    note "prettier SKIPPED (no changed files it handles)"
  fi
}

# ---------------------------------------------------------------- the gate
start_static() {
  # Their results come back through files: a background subshell cannot append to RESULTS.
  ( RESULTS=(); FAILED=0; static_checks
    printf '%s\n' "${RESULTS[@]}" > "$LOGDIR/static.results"; echo "$FAILED" > "$LOGDIR/static.failed" ) > "$LOGDIR/static.out" 2>&1 &
  STATIC_PID=$!
}

# --fast, corpus: jl4-test restricted to the examples that read the changed files. See etc/gate-fast-select.mjs
# for what it selects, and why a selection can be trusted only if it is checked: a `--match` that matches
# nothing runs nothing and passes, so the selection is counted by hspec's own --dry-run first, every affected
# file must select an example of its own, and the run must execute exactly the examples that were counted.
fast_corpus() {
  local key="" n="" executed="" rel f out missing=0
  JL4_TEST_BIN=""
  if [ -n "${L4_GATE_BIN_CACHE:-}" ]; then
    key=$(node "$WT/etc/gate-bin-cache.mjs" key "$WT" 2>/dev/null) || key=""
    # Into PROBEDIR, which every exit removes: LOGDIR is kept when a suite fails, and when the cache is on another volume than
    # TMPDIR the restore is a 230 MB copy, so restoring there left one on the internal disk after every red corpus run.
    if [ -n "$key" ] && node "$WT/etc/gate-bin-cache.mjs" restore "$WT" jl4-test "$PROBEDIR/jl4-test" >/dev/null 2>&1; then
      JL4_TEST_BIN="$PROBEDIR/jl4-test"
      RESULTS+=("PASS  jl4-test binary restored from the cache, key $key (no cabal build ran)")
    fi
  fi
  if [ -z "$JL4_TEST_BIN" ]; then
    step "cabal build jl4-test" bash -c "cd '$WT' && cabal build jl4-test 2>&1 | grep -viE '^ *ld: warning' | grep -iE 'error' && exit 1 || exit 0" ||
      { note "jl4-test NOT run: it did not build"; return 0; }
    JL4_TEST_BIN=$(cd "$WT" && cabal list-bin jl4-test 2>/dev/null)
    if [ -n "$key" ] && [ -x "$JL4_TEST_BIN" ]; then
      node "$WT/etc/gate-bin-cache.mjs" store "$WT" "$key" "jl4-test=$JL4_TEST_BIN" >/dev/null 2>&1 &&
        note "jl4-test stored in the binary cache, key $key" ||
        note "jl4-test NOT stored in the binary cache (the build inputs changed while it built, or the cache is unwritable)"
    fi
  fi
  if [ ! -x "$JL4_TEST_BIN" ]; then RESULTS+=("FAIL  jl4-test: no built binary ($JL4_TEST_BIN)"); FAILED=1; return 0; fi
  out=$(cd "$WT/jl4" && env jl4_datadir="$WT/jl4" jl4_core_datadir="$WT/jl4-core" "$JL4_TEST_BIN" --dry-run -f specdoc "${FAST_MATCH_OPTS[@]}" 2>&1)
  n=$(echo "$out" | grep -E '^[0-9]+ examples' | tail -1 | cut -d' ' -f1)
  if [ -z "$n" ] || [ "$n" -eq 0 ]; then
    RESULTS+=("FAIL  --fast selected NO jl4-test example (hspec --dry-run counts ${n:-none}); a run of nothing is not a pass")
    FAILED=1; return 0
  fi
  for f in "${FAST_FILES[@]}"; do
    rel=${f#jl4/examples/}
    if ! echo "$out" | grep -qxF "  $rel"; then echo "  no jl4-test example for $rel"; missing=$((missing + 1)); fi
  done
  if [ "$missing" -gt 0 ]; then
    RESULTS+=("FAIL  --fast: $missing of ${#FAST_FILES[@]} affected corpus file(s) select no jl4-test example (above)")
    FAILED=1; return 0
  fi
  echo "  --fast selected $n jl4-test examples for ${#FAST_FILES[@]} corpus file(s)"
  suite_start "jl4-test:fast"; wait "$LAST_SUITE_PID"
  executed=$(grep -E '^[0-9]+ examples' "$LOGDIR/jl4-test:fast.log" 2>/dev/null | tail -1 | cut -d' ' -f1)
  if [ "$executed" = "$n" ]; then RESULTS+=("PASS  jl4-test ran the $n examples that --dry-run counted")
  else RESULTS+=("FAIL  jl4-test ran ${executed:-no} examples; --dry-run counted $n"); FAILED=1; fi
  suite_report "jl4-test, the examples that read the changed files (--fast)" "jl4-test:fast" 3
}

fast_gate() {
  start_static   # the file checks overlap whatever else runs; --serial does not apply to them here
  local x
  for x in ${FAST_NOTES[@]+"${FAST_NOTES[@]}"}; do note "$x"; done
  case "$FAST_MODE" in
    docs) note "cabal build, jl4-test, l4-cli-test, jl4-core-test and jl4-service-test NOT RUN (--fast, docs only)" ;;
    corpus)
      fast_corpus
      note "NOT RUN (--fast, corpus): the rest of jl4-test, l4-cli-test, jl4-core-test, jl4-service-test" ;;
  esac
}

# The full gate below is deliberately not indented under this `else`: indenting it would turn every line into diff noise.
if [ -n "$FAST_MODE" ]; then
fast_gate
else
step "cabal build all" bash -c "cd '$WT' && cabal build all 2>&1 | grep -viE '^ *ld: warning' | grep -iE 'error' && exit 1 || exit 0"

if [ "$QUICK" = 1 ]; then
  note "jl4-test SKIPPED (--quick)"
fi

[ "$SERIAL" != 1 ] && start_static

if [ "$SERIAL" = 1 ]; then
  note "test suites ran one after another (--serial)"
  for spec in "${SUITES[@]}"; do
    IFS='|' read -r label target lines <<< "$spec"
    suite_start "$target"; wait "$LAST_SUITE_PID"
    suite_report "$label" "$target" "$lines"
  done
else
  # Build every suite once, here, so that no `cabal test` below has anything to compile.
  targets=(); for spec in "${SUITES[@]}"; do IFS='|' read -r _ target _ <<< "$spec"; t="${target%%:*}"
    case " ${targets[*]-} " in *" $t "*) ;; *) targets+=("$t") ;; esac; done
  if step "cabal build the test suites" bash -c "cd '$WT' && cabal build ${targets[*]} 2>&1 | grep -viE '^ *ld: warning' | grep -iE 'error' && exit 1 || exit 0"; then
    note "test suites ran at the same time (use --serial to run them one at a time)"
    JL4_TEST_BIN=""; JL4_TEST_COUNT=""
    case " ${targets[*]-} " in *" jl4-test "*)
      JL4_TEST_BIN=$(cd "$WT" && cabal list-bin jl4-test 2>/dev/null)
      # hspec's own count of the examples, to hold the four slices against.
      JL4_TEST_COUNT=$( [ -x "$JL4_TEST_BIN" ] && cd "$WT/jl4" && env jl4_datadir="$WT/jl4" jl4_core_datadir="$WT/jl4-core" "$JL4_TEST_BIN" --dry-run 2>&1 | grep -E '^[0-9]+ examples' | tail -1 | cut -d' ' -f1)
      ;; esac
    if case " ${targets[*]-} " in *" jl4-test "*) [ -z "$JL4_TEST_COUNT" ] ;; *) false ;; esac; then
      RESULTS+=("FAIL  jl4-test: no built binary or no example count from --dry-run ($JL4_TEST_BIN)"); FAILED=1
    else
      # On a host with fewer than 8 cores the jl4-test slices run AFTER the other suites, not beside them:
      # on lhs (4 cores, Intel N150) four slices beside jl4-service-test starved its batch examples, which
      # run 40 half-second cases through one capability against a 30-second HTTP timeout, and three of them
      # failed in all four full-gate runs. nice -n 10 on the slices did not help (the load average stayed
      # near 3.5 of 4), so the cause is not CPU share alone. On 8 or more cores everything starts together.
      CORES=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
      for phase in 1 2; do
        SUITE_PIDS=""
        for spec in "${SUITES[@]}"; do IFS='|' read -r _ target _ <<< "$spec"
          late=0; case "$target" in jl4-test:*) [ "$CORES" -lt 8 ] && late=1 ;; esac
          [ "$late" = $((phase - 1)) ] && suite_start "$target"
        done
        # shellcheck disable=SC2086
        [ -z "$SUITE_PIDS" ] || wait $SUITE_PIDS
      done
      [ "$CORES" -lt 8 ] && note "jl4-test slices ran after the other suites ($CORES cores; they run beside them from 8)"
      if [ -n "$JL4_TEST_COUNT" ]; then
        SLICED=0
        for sl in canon oknotcanon prettylayout rest; do
          n=$(grep -E '^[0-9]+ examples' "$LOGDIR/jl4-test:$sl.log" 2>/dev/null | tail -1 | cut -d' ' -f1); SLICED=$((SLICED + ${n:-0}))
        done
        if [ "$SLICED" = "$JL4_TEST_COUNT" ]; then RESULTS+=("PASS  jl4-test slices cover all $JL4_TEST_COUNT examples (hspec --dry-run)")
        else RESULTS+=("FAIL  jl4-test slices ran $SLICED examples; hspec counts $JL4_TEST_COUNT"); FAILED=1; fi
      fi
      for spec in "${SUITES[@]}"; do IFS='|' read -r label target lines <<< "$spec"; suite_report "$label" "$target" "$lines"; done
    fi
  else
    note "test suites NOT run: they did not build"
  fi
fi

fi   # end of the full gate

# ---------------------------------------------------------------- probes
# Each probe guards a defect that a review of a main-bound PR found after every
# suite above had passed, and runs only when the diff touches what it guards
# (header; specs/todo/MAIN-PRE-REVIEW.md). They run copies of the binaries: a
# build in this worktree relinks the originals, and a half-written binary fails
# both sides of a before/after comparison alike (CLAUDE.md §3.2.1).
DIFF_FILES=$(git -C "$WT" diff --name-only "$BASE"...HEAD 2>/dev/null)
NOT_PROBED=()
snapshot() { # snapshot <exe> prints the path of a copy of the built exe
  local bin
  bin=$(cd "$WT" && cabal list-bin "exe:$1" 2>/dev/null) && [ -x "$bin" ] && cp "$bin" "$PROBEDIR/$1" && echo "$PROBEDIR/$1"
}

if echo "$DIFF_FILES" | grep -q '^jl4-core/src/L4/Parser'; then
  if L4_COPY=$(snapshot l4); then
    step "probe (a): l4 check time is linear in file length" \
      bash -c "cd '$WT' && node etc/probe-parse-scaling.mjs --selftest && node etc/probe-parse-scaling.mjs '$L4_COPY'"
  else RESULTS+=("FAIL  probe (a): no built l4 to time"); FAILED=1; fi
else NOT_PROBED+=("(a) parse time"); fi

if echo "$DIFF_FILES" | grep -q '^jl4-service/'; then
  if SVC_COPY=$(snapshot jl4-service); then
    step "probe (b): jl4-service answers the same after a restart" \
      bash -c "cd '$WT' && node etc/probe-service-restart.mjs '$SVC_COPY'"
  else RESULTS+=("FAIL  probe (b): no built jl4-service to start"); FAILED=1; fi
else NOT_PROBED+=("(b) service restart"); fi

if echo "$DIFF_FILES" | grep -q '^jl4/tests-cli/'; then
  printf '\n=== probe (c): CLI tests that compare output without dropping \\r ===\n'
  if CRLF=$(cd "$WT" && node etc/probe-cli-crlf.mjs --selftest >/dev/null && node etc/probe-cli-crlf.mjs --base "$BASE" "$WT"); then
    echo "$CRLF"
    case "$CRLF" in
      *WARN:*) RESULTS+=("WARN  probe (c): $(echo "$CRLF" | grep -c '^  ') CLI-test line(s) may need '\\r' dropped; read them above") ;;
      *) RESULTS+=("PASS  probe (c): no new CLI-test comparison of raw output") ;;
    esac
  else echo "$CRLF"; RESULTS+=("FAIL  probe (c) could not run"); FAILED=1; fi
else NOT_PROBED+=("(c) CLI \\r"); fi
[ "${#NOT_PROBED[@]}" -eq 0 ] ||
  note "probes not run, the diff does not touch what they guard: $(printf '%s, ' "${NOT_PROBED[@]}" | sed 's/, $//')"

if [ "$SERIAL" = 1 ] && [ -z "$FAST_MODE" ]; then
  static_checks
else
  wait "$STATIC_PID"
  cat "$LOGDIR/static.out"
  while IFS= read -r r; do RESULTS+=("$r"); done < "$LOGDIR/static.results"
  [ "$(cat "$LOGDIR/static.failed")" = 1 ] && FAILED=1
fi

# ---------------------------------------------------------------- hygiene
printf '\n=== commit trailers ===\n'
# `Claude-Session:` names the Claude Code session behind a commit Claude co-authored, so only
# those commits are held to it. A commit with no Claude `Co-Authored-By:` line was written by
# hand and passes without either trailer.
MISSING=0
BYHAND=0
while IFS= read -r c; do
  [ -n "$c" ] || continue
  body=$(git -C "$WT" log -1 --format='%B' "$c")
  if ! printf '%s\n' "$body" | grep -qi '^Co-Authored-By: Claude'; then
    BYHAND=$((BYHAND + 1))
  elif ! printf '%s\n' "$body" | grep -q '^Claude-Session:'; then
    echo "  MISSING Claude-Session: $(git -C "$WT" log -1 --format='%h %s' "$c")"
    MISSING=1
  fi
done < <(git -C "$WT" rev-list --no-merges "$BASE".."$HEAD_SHA" 2>/dev/null)
[ "$BYHAND" -gt 0 ] && note "$BYHAND commit(s) without a Claude co-author: not held to Claude-Session"
if [ "$MISSING" = 1 ]; then RESULTS+=("FAIL  commit trailers"); FAILED=1
else echo "  every Claude-co-authored commit carries Claude-Session"; RESULTS+=("PASS  commit trailers"); fi

# `L4.Print` has TWO printers with different guards, and the round-trip property
# is weaker than it looks: a printer that drops a bracket emits source that
# parses, type-checks, and evaluates to a DIFFERENT answer. CLAUDE.md §3.2.1.
if git -C "$WT" diff --name-only "$BASE"...HEAD 2>/dev/null | grep -q 'L4/Print.hs'; then
  RESULTS+=("      L4/Print.hs CHANGED — run the §3.2.1 evaluation differential BY HAND;")
  RESULTS+=("      the round-trip property alone will not catch a re-association bug.")
fi

# ---------------------------------------------------------------- summary
echo
partial_banner
banner
echo "  RESULTS"
for r in "${RESULTS[@]}"; do echo "    $r"; done
if [ "${#KEPT[@]}" -gt 0 ]; then
  echo
  echo "  LOGS of the failed suites, kept:"
  for k in "${KEPT[@]}"; do echo "    $k"; done
fi
echo
echo "  NOT CHECKED — suites CI runs and this does not: jl4-lsp-test,"
echo "               jl4-mlir-test, jl4-websessions-test, jl4-proleg-burden,"
echo "               jl4-proleg-roundtrip."
echo "  NOT CHECKED — also: DMN engine harnesses, go selftest, WASM, Nix,"
echo "               TypeScript. A green run here is not a green CI."
if [ -n "$FAST_MODE" ]; then
  echo
  echo "  $PARTIAL_LINE"
  echo "  This was the reduced gate for a '$FAST_MODE' diff. It did not run the full gate's other suites, and nothing"
  echo "  here shows that the unchanged parts of the tree are still green."
fi
echo "────────────────────────────────────────────────────────────────────"
exit "$FAILED"

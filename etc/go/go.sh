#!/usr/bin/env bash
# go.sh — the only entry point of the "SEC Regulation Crowdfunding: go" pipeline.
#
# Phase dispatch, gate enforcement, resumability. Everything with an exit code
# lives under etc/go/; everything that is a judgement lives in the skill at
# .claude/skills/running-the-l4-pipeline/. This script never calls a model, and
# the skill never writes a status.
#
# Scope today: MILESTONE G1 — the replay run. It drives the EXISTING corpus
# through every currently-reachable projection and emits conversion report v0.
# No de novo encoding.
#
# MILESTONE G2 — the de novo run — runs its DEPOSIT-VALIDATING half. P1, P2, P3
# and P4 do not fetch, search, encode or find forks: those need the network or a
# model and this driver takes neither. They validate what an agent deposited,
# and report SKIPPED with a named reason when the deposit is not there yet. So
# `g2 COMPLETE` means every g2 stage is accounted for — NOT that a de novo run
# happened. SPEC.md §6's G2 acceptance is the §8 diff oracle
# (etc/go/lib/denovo-diff.mjs), which no stage calls. See
# `go.sh plan --milestone g2`.
#
# This script NEVER runs cabal, never commits, and never pushes.
#
#   Usage:  etc/go/go.sh <command> [options]
#
#     run     --milestone g1|g2 --subject ID [--run-id ID] [--through STAGE]
#             [--only STAGE] [--waive HG1=REASON] [--fixed-now ISO8601]
#
#             HG1 is the only waivable gate. HG2 guards anything outward-facing
#             and opens on a signature or not at all; --waive HG2 exits 2.
#     plan    [--milestone g1|g2]
#     status  [--run-id ID]
#     verify  [--run-id ID] [--gates]
#     gc      [--keep N]
#     help
#
#   Exit codes (extending etc/check-bpmn-kie.sh's 0/1/2/3/4):
#     0 clean   1 finding   2 usage   3 gate   4 broken   5 skipped-while-required
#
#   Environment:
#     L4                   path to a prebuilt `l4`. REQUIRED — this script does
#                          not build. Same escape hatch as JL4_LSP_CMD=/DMNMD=.
#     JL4_LSP_CMD          prebuilt jl4-lsp, for the ladder leg
#     JL4_GO_SERVICE_URL   a LOOPBACK jl4-service for the MCP leg; non-loopback
#                          is refused (an outward-facing write is HG2's)
#     L4_GO_RUNDIR         where runs live (default $TMPDIR/l4-go)
#     L4_GO_REQUIRED       1 ⇒ any SKIPPED stage is fatal (exit 5), as CI wants
#     L4_GO_FIXED_NOW      pin the clock (default 2025-01-31T00:00:00Z)

set -euo pipefail

GO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PHASES="$GO_ROOT/etc/go/phases"
LIB="$GO_ROOT/etc/go/lib"

# --- the stage table --------------------------------------------------------
# G1's declared stages, in order. p0-preflight, p3-check, p6-tests and
# p9-report are always declared; each p7 leg is declared iff the subject's
# sidecar (etc/go/subjects/<id>/subject.json) has an entry for it in `legs`.
# That is what keeps COMPLETE honest for a subject that has, say, no wizard
# and no regulative rules: its sidecar omits those legs, so their absence
# cannot make the milestone INCOMPLETE and their presence is never faked.
# `p9-report` is last: the report reads the journal, so it must run after
# everything that writes to it. G1_STAGES is assembled after subject
# resolution below.
P7_LEG_ORDER=(
  p7-dmn
  p7-dmn-md
  p7-bpmn
  p7-ladder
  p7-lts
  p7-mcp
  p7-tnr
  p7-wizard
  p7-akn
)

# Stages that exist as entry points and cannot run. Each refuses with exit 3 and
# names its blocker. They are NOT declared members of any milestone, so they
# cannot make a milestone INCOMPLETE by their absence.
#
# p1-ingest, p2-sweep, p3-encode, p4-forks and p5-gate left this list: they are
# now real stages that validate a deposit, and they are g2's declared members.
UNIMPLEMENTED_STAGES=(p8-verify p10-publish)

# G2's declared stages, in order. The five de novo stages plus the report.
#
# WHAT IS DELIBERATELY NOT HERE, and why the omission is the honest choice:
# p3-check, p6-tests and every p7 leg read the subject's COMMITTED corpus and
# its committed goldens (GO_S_CORPUS, legs[*].golden). Running them inside a g2
# run would measure the replay artifacts and file the result under a de novo
# label — "the encoding typechecks", "its assertions hold" — about a module the
# de novo run never wrote. Re-pointing them at a `denovo.modules` deposit is
# unbuilt; until it is, they are named in `plan --milestone g2` as NOT WIRED
# rather than run. p9-report is included because it reads journal.ndjson and
# nothing else, so it is correct for any milestone.
G2_STAGES=(p1-ingest p2-sweep p3-encode p4-forks p5-gate p9-report)

# SPEC.md §7.3: exactly two human gates. HG1 blocks P6 onward; HG2 blocks
# anything outward-facing, which at G1 means the MCP deployment leg and P10.
# gated_by_HG1 is assembled after subject resolution: P6 onward means p6-tests,
# every declared p7 leg, and p9-report.
gated_by_HG1=""
gated_by_HG2="p10-publish"

usage() {
  sed -n '2,48p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die_usage() {
  echo "go.sh: $1" >&2
  echo "run 'etc/go/go.sh help' for usage" >&2
  exit 2
}

# --- argument parsing -------------------------------------------------------
CMD="${1:-help}"
shift || true

MILESTONE="g1"
SUBJECT=""
RUN_ID=""
THROUGH=""
ONLY=""
KEEP=5
WANT_GATES=0
declare -a WAIVERS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --milestone)
      MILESTONE="$2"
      shift 2
      ;;
    --subject)
      SUBJECT="$2"
      shift 2
      ;;
    --run-id)
      RUN_ID="$2"
      shift 2
      ;;
    --through)
      THROUGH="$2"
      shift 2
      ;;
    --only)
      ONLY="$2"
      shift 2
      ;;
    --waive)
      WAIVERS+=("$2")
      shift 2
      ;;
    --fixed-now)
      L4_GO_FIXED_NOW="$2"
      shift 2
      ;;
    --keep)
      KEEP="$2"
      shift 2
      ;;
    --gates)
      WANT_GATES=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die_usage "unknown option $1" ;;
  esac
done

RUNDIR_BASE="${L4_GO_RUNDIR:-${TMPDIR:-/tmp}/l4-go}"
FIXED_NOW="${L4_GO_FIXED_NOW:-2025-01-31T00:00:00Z}"

# --- subject resolution -----------------------------------------------------
# With no --subject, the sole sidecar under etc/go/subjects/ is the default;
# once a second subject exists, naming one becomes mandatory — a silent
# default among several would make a run about an unnamed body of law.
if [[ -z "$SUBJECT" ]]; then
  mapfile -t _SUBJECTS < <(node "$LIB/subject.mjs" --list)
  if [[ ${#_SUBJECTS[@]} -eq 1 && -n "${_SUBJECTS[0]}" ]]; then
    SUBJECT="${_SUBJECTS[0]}"
  else
    die_usage "--subject is required (available: ${_SUBJECTS[*]:-none}; see etc/go/subjects/)"
  fi
fi

# Everything the pipeline knows about ONE body of law lives in its sidecar,
# etc/go/subjects/<id>/. The resolver validates the descriptor (unknown keys
# refused, referenced goldens must exist) and prints shell-safe GO_S_* lines;
# an unknown subject exits 2 listing the available sidecars and the recipe for
# adding one. The eval is safe because subject.mjs single-quotes every value.
SUBJECT_ENV="$(node "$LIB/subject.mjs" "$SUBJECT")" || exit 2
eval "$SUBJECT_ENV"
export "${!GO_S_@}"

# The subject's corpus file set: main module, plus the wizard module when the
# sidecar declares one. Used for the corpus digest that gates bind to.
declare -a GO_CORPUS_FILES=("$GO_S_CORPUS")
[[ -n "${GO_S_WIZARD:-}" ]] && GO_CORPUS_FILES+=("$GO_S_WIZARD")

# At g2 the gate binds to the DE NOVO deposits instead, because that is what HG1
# is being asked about. A waiver granted over the committed corpus says nothing
# about an encoding that did not exist when it was granted — and since digestSet
# records a missing file as ABSENT rather than skipping it, DEPOSITING a bundle
# or a module changes the digest and re-opens the gate, which is the behaviour
# §6.3 claims for a post-gate edit.
if [[ "$MILESTONE" == "g2" ]]; then
  GO_CORPUS_FILES=()
  for _p in "${GO_S_DENOVO_BUNDLE:-}" "${GO_S_DENOVO_REGISTER:-}" "${GO_S_DENOVO_FORKS:-}"; do
    [[ -n "$_p" ]] && GO_CORPUS_FILES+=("$_p")
  done
  if [[ -n "${GO_S_DENOVO_MODULES:-}" ]]; then
    read -ra _mods <<<"$GO_S_DENOVO_MODULES"
    GO_CORPUS_FILES+=("${_mods[@]}")
  fi
  # A subject with no `denovo` section at all still needs a digest to bind a
  # gate to; `text:` entries are literal digest contributors (digestSet).
  [[ ${#GO_CORPUS_FILES[@]} -eq 0 ]] && GO_CORPUS_FILES=("text:g2-no-denovo-declared=$GO_S_ID")
fi

# Assemble the declared stage list and the HG1 set from the sidecar's legs.
G1_STAGES=(p0-preflight p3-check p6-tests)
gated_by_HG1="p6-tests"
for s in "${P7_LEG_ORDER[@]}"; do
  if [[ " $GO_S_LEGS " == *" $s "* ]]; then
    G1_STAGES+=("$s")
    gated_by_HG1="$gated_by_HG1 $s"
  fi
done
G1_STAGES+=(p9-report)
gated_by_HG1="$gated_by_HG1 p9-report"

# SPEC.md §7.3: HG1 blocks P6 onward. In g2's declared set the only stage after
# P5 is the report, so that is what HG1 gates — and, as at g1, a g2 run stops
# there with exit 3 until the gate is signed or waived on the record.
if [[ "$MILESTONE" == "g2" ]]; then gated_by_HG1="p9-report"; fi

# deposit_state PATH -> undeclared | absent | present. `plan` only.
deposit_state() {
  if [[ -z "${1:-}" ]]; then
    echo undeclared
  elif [[ -f "$1" ]]; then
    echo present
  else
    echo absent
  fi
}

stages_for() {
  case "$1" in
    g1) printf '%s\n' "${G1_STAGES[@]}" ;;
    g2) printf '%s\n' "${G2_STAGES[@]}" ;;
    *)
      echo "go.sh: unknown milestone '$1'; SPEC.md §6 defines G0-G4 and this driver implements G1." >&2
      return 2
      ;;
  esac
}

# --- commands ---------------------------------------------------------------

# The G2 plan. It prints SPEC.md §4's full de novo stage order — including the
# stages this driver does NOT declare at g2 — because a plan that lists only
# what runs cannot tell you what is missing. Every row says which of the two it
# is, and the deposit rows say whether the deposit is there.
cmd_plan_g2() {
  local b r f m
  b="${GO_S_DENOVO_BUNDLE:-}"
  r="${GO_S_DENOVO_REGISTER:-}"
  f="${GO_S_DENOVO_FORKS:-}"
  m="${GO_S_DENOVO_MODULES:-}"

  echo "milestone g2, subject $SUBJECT — SPEC.md §4's de novo stage order, in order:"
  echo
  printf '  %-14s %-9s %-11s %s\n' STAGE GATE DEPOSIT "WHAT IT CHECKS / WHY NOT"
  printf '  %-14s %-9s %-11s %s\n' "p1-ingest" "-" "$(deposit_state "$b")" "${b:-(no denovo.bundle in subject.json)}"
  printf '  %-14s %-9s %-11s %s\n' "p2-sweep" "-" "$(deposit_state "$r")" "${r:-(no denovo.register in subject.json)}"

  local mstate="undeclared" mn=0
  if [[ -n "$m" ]]; then
    local mm
    read -ra mm <<<"$m"
    mn=${#mm[@]}
    mstate=present
    local x
    for x in "${mm[@]}"; do [[ -f "$x" ]] || mstate=absent; done
  fi
  printf '  %-14s %-9s %-11s %s\n' "p3-encode" "-" "$mstate" "$([[ $mn -gt 0 ]] && echo "$mn declared module(s); l4 check each" || echo "(no denovo.modules in subject.json)")"
  printf '  %-14s %-9s %-11s %s\n' "p3-check" "NOT WIRED" "-" "reads the committed corpus ($GO_S_CORPUS); re-pointing it at a de novo deposit is unbuilt"
  printf '  %-14s %-9s %-11s %s\n' "p4-forks" "-" "$(deposit_state "$f")" "${f:-(no denovo.fork_register in subject.json)}"

  local n=0 s
  for s in "$b" "$r" "$f"; do [[ -n "$s" && -f "$s" ]] && n=$((n + 1)); done
  printf '  %-14s %-9s %-11s %s\n' "p5-gate" "-" "$n of 3" "the cross-file joins; needs all three deposits, else SKIPPED"
  echo "  ---- HG1 ------- Meng's go on the encoding; blocks P6 onward (SPEC.md §7.3)"
  printf '  %-14s %-9s %-11s %s\n' "p6-tests" "NOT WIRED" "-" "reads the committed corpus; a de novo run's tests discriminate between FORKS, which is unbuilt"
  local leg
  for leg in "${P7_LEG_ORDER[@]}"; do
    [[ " $GO_S_LEGS " == *" $leg "* ]] || continue
    printf '  %-14s %-9s %-11s %s\n' "$leg" "NOT WIRED" "-" "compares against this subject's committed goldens, which are the replay artifacts"
  done
  printf '  %-14s %-9s %-11s %s\n' "p9-report" "HG1" "-" "reads journal.ndjson and nothing else"
  echo
  echo "declared by this driver at g2, and therefore run: ${G2_STAGES[*]}"
  echo "entry points that still exist and refuse, each with a named blocker:"
  for s in "${UNIMPLEMENTED_STAGES[@]}"; do printf '  %-14s %s\n' "$s" "$PHASES/$s.sh"; done
  echo
  echo "READ THIS BEFORE READING A g2 VERDICT. P1, P2, P3 and P4 do not fetch, search,"
  echo "encode or find forks: those need the network or a model, and this driver takes"
  echo "neither (ORCHESTRATOR.md §2.1, §6.4). They VALIDATE what an agent deposited, and"
  echo "report SKIPPED with a named reason when the deposit is not there. So 'g2 COMPLETE'"
  echo "means every g2 stage is accounted for — it does NOT mean a de novo run happened."
  echo "SPEC.md §6's G2 acceptance is the §8 diff oracle, etc/go/lib/denovo-diff.mjs,"
  echo "which no stage calls. Run with L4_GO_REQUIRED=1 to make an absent deposit fatal."
}

cmd_plan() {
  local rc=0
  local stages
  stages=$(stages_for "$MILESTONE") || rc=$?
  [[ $rc -eq 0 ]] || exit $rc
  if [[ "$MILESTONE" == "g2" ]]; then
    cmd_plan_g2
    return 0
  fi
  echo "milestone $MILESTONE, subject $SUBJECT — declared stages, in order:"
  local s
  while read -r s; do
    local gate="-"
    [[ " $gated_by_HG1 " == *" $s "* ]] && gate="HG1"
    [[ " $gated_by_HG2 " == *" $s "* ]] && gate="HG2"
    printf '  %-14s gate=%-4s %s\n' "$s" "$gate" "$PHASES/$s.sh"
  done <<<"$stages"
  echo
  echo "entry points that exist and refuse, each with a named blocker:"
  for s in "${UNIMPLEMENTED_STAGES[@]}"; do printf '  %-14s %s\n' "$s" "$PHASES/$s.sh"; done
  echo
  echo "the milestone rule: $MILESTONE is COMPLETE when every declared stage has a"
  echo "receipt, no receipt is BROKEN, every non-PASS receipt carries a reason that"
  echo "appears in the report, and every gate is satisfied or explicitly waived."
  echo "That is completeness of accounting, not greenness — SPEC.md §6 permits a"
  echo "non-executable DMN at G1 provided the report says so in Blocking terms."
}

latest_run() {
  ls -1d "$RUNDIR_BASE"/*/ 2>/dev/null | sort | tail -1 | sed 's:/$::'
}

# gate_grant_state JOURNAL GATE CORPUS_DIGEST -> open | stale | closed
#
# A gate is open only while a granting row (satisfied or waived) records the
# corpus digest this run is actually using. `stale` means the gate WAS granted
# and the corpus has moved since, which is the case the design's "a post-gate
# edit re-opens the gate" claim is about.
#
# This replaces a grep for any granting row anywhere in the journal. That grep
# memoised the gate for the life of the run directory, so one waiver covered
# every later encoding change — and, because it also matched `satisfied`, a
# resumed run never re-ran gate-verify.sh either, which is where the signed
# route's own content binding lives. Both routes are re-checked here.
gate_grant_state() {
  node -e '
    import("'"$LIB"'/ledger.mjs").then((m) => {
      const [journal, gate, digest] = process.argv.slice(1);
      const rows = m
        .read(journal)
        .filter((r) => r.kind === "gate" && r.gate === gate);
      const granting = rows.filter(
        (r) => r.state === "satisfied" || r.state === "waived",
      );
      const open = granting.some((r) => r.corpus_digest === digest);
      process.stdout.write(open ? "open" : granting.length ? "stale" : "closed");
    });
  ' "$1" "$2" "$3"
}

resolve_run() {
  if [[ -n "$RUN_ID" ]]; then
    echo "$RUNDIR_BASE/$RUN_ID"
  else
    local l
    l=$(latest_run || true)
    [[ -n "$l" ]] || {
      echo "go.sh: no runs under $RUNDIR_BASE" >&2
      exit 2
    }
    echo "$l"
  fi
}

cmd_status() {
  node "$LIB/verify-run.mjs" "$(resolve_run)"
}

cmd_verify() {
  local extra=()
  [[ $WANT_GATES -eq 1 ]] && extra+=(--gates)
  node "$LIB/verify-run.mjs" "$(resolve_run)" "${extra[@]}"
}

cmd_gc() {
  # Retention: keep the latest run per subject, AND any run holding a granted
  # gate verdict — a signature is expensive to obtain and must not be collected.
  local keep_ids=()
  local d
  for d in $(ls -1d "$RUNDIR_BASE"/*/ 2>/dev/null | sed 's:/$::'); do
    if grep -q '"kind":"gate"' "$d/journal.ndjson" 2>/dev/null && grep -q '"state":"satisfied"' "$d/journal.ndjson" 2>/dev/null; then
      keep_ids+=("$d")
    fi
  done
  for d in $(ls -1d "$RUNDIR_BASE"/*/ 2>/dev/null | sed 's:/$::' | sort | tail -"$KEEP"); do keep_ids+=("$d"); done
  local removed=0
  for d in $(ls -1d "$RUNDIR_BASE"/*/ 2>/dev/null | sed 's:/$::'); do
    local k
    local keep=0
    for k in "${keep_ids[@]}"; do [[ "$k" == "$d" ]] && keep=1; done
    if [[ $keep -eq 0 ]]; then
      rm -rf "$d"
      removed=$((removed + 1))
      echo "gc: removed $d"
    fi
  done
  echo "gc: kept ${#keep_ids[@]} run dir(s) (latest $KEEP, plus every run holding a granted gate); removed $removed"
}

cmd_run() {
  local stages rc=0
  stages=$(stages_for "$MILESTONE") || rc=$?
  [[ $rc -eq 0 ]] || exit $rc

  # --- the one hard prerequisite: a prebuilt l4 ------------------------------
  if [[ -z "${L4:-}" ]]; then
    cat >&2 <<EOF
go.sh: L4 is unset.

This orchestrator never runs cabal — the build lock is a shared resource and
concurrent invocations in one worktree corrupt each other (CLAUDE.md §2.1).
Point L4 at a prebuilt binary, the same escape hatch as JL4_LSP_CMD= and DMNMD=:

  export L4=/path/to/dist-newstyle/build/<arch>/ghc-9.10.3/jl4-0.1/x/l4/build/l4/l4
EOF
    exit 2
  fi
  if [[ ! -x "$L4" ]] && ! command -v "$L4" >/dev/null 2>&1; then
    echo "go.sh: L4=$L4 is not executable and not on PATH" >&2
    exit 2
  fi

  export JL4_LIBRARY_PATH="${JL4_LIBRARY_PATH:-$GO_ROOT/jl4-core/libraries}"

  # --- run id + run dir ------------------------------------------------------
  # The corpus this run is about, as one digest. It names the run, and the gate
  # rows bind to it so a waiver granted over one corpus does not silently cover
  # a later edit.
  local corpus_digest corpus_sha8
  corpus_digest=$(node "$LIB/digest.mjs" "${GO_CORPUS_FILES[@]}")
  corpus_sha8=$(printf '%s' "$corpus_digest" | sed 's/^sha256://' | cut -c1-8)
  local RUN
  if [[ -n "$RUN_ID" ]]; then
    RUN="$RUNDIR_BASE/$RUN_ID"
    [[ -d "$RUN" ]] || {
      echo "go.sh: --run-id $RUN_ID has no directory at $RUN" >&2
      exit 2
    }
  else
    local day seq
    day=$(date -u +%Y-%m-%d)
    seq=1
    while [[ -d "$RUNDIR_BASE/$day-$corpus_sha8-$(printf '%03d' $seq)" ]]; do seq=$((seq + 1)); done
    RUN_ID="$day-$corpus_sha8-$(printf '%03d' $seq)"
    RUN="$RUNDIR_BASE/$RUN_ID"
    mkdir -p "$RUN/artifacts"
  fi

  local head tree_state
  head=$(git -C "$GO_ROOT" rev-parse HEAD 2>/dev/null || echo "(not a git tree)")
  if [[ -n "$(git -C "$GO_ROOT" status --porcelain 2>/dev/null)" ]]; then tree_state="dirty"; else tree_state="clean"; fi

  # The `l4` binary is an input to every stage and is declared by none: no phase
  # script can see the path the driver was handed. Hash it ONCE here and fold
  # the digest into every stage's inputs digest below.
  #
  # Without this fold, a run resumed after `l4` was rebuilt or repointed
  # replayed EVERY leg without invoking the binary once — measured with a stub
  # that exits 1 on every call: thirteen `replayed` lines, `VERDICT: g1
  # COMPLETE`, exit 0, and a report still naming the ORIGINAL binary. p0's
  # CLI-surface pin and its failing-#ASSERT tripwire, which exist precisely to
  # catch a moved binary, were both skipped. Resuming an interrupted run is the
  # documented workflow, and rebuilding `l4` in between is the obvious thing to
  # have done.
  local l4_path l4_sha
  l4_path="$(command -v "$L4" || echo "$L4")"
  l4_sha="$(node "$LIB/digest.mjs" "$l4_path")"
  export GO_L4_PATH="$l4_path" GO_L4_SHA="$l4_sha"

  export GO_ROOT
  export GO_RUN="$RUN" GO_RUNID="$RUN_ID" GO_SUBJECT="$SUBJECT" GO_MILESTONE="$MILESTONE"
  export GO_FIXED_NOW="$FIXED_NOW"

  # run_begin is written once per run dir, not once per invocation: a resumed
  # run is the same run.
  if [[ ! -f "$RUN/journal.ndjson" ]]; then
    node "$LIB/receipt.mjs" run-begin --run "$RUN" \
      --run-id "$RUN_ID" --milestone "$MILESTONE" --subject "$SUBJECT" \
      --repo-head "$head" --tree-state "$tree_state" --fixed-now "$FIXED_NOW" \
      --l4-binary "$L4" --declared "$(echo "$stages" | tr '\n' ',')" \
      --gated-stages "{\"HG1\":[$(for x in $gated_by_HG1; do printf '"%s",' "$x"; done | sed 's/,$//')],\"HG2\":[$(for x in $gated_by_HG2; do printf '"%s",' "$x"; done | sed 's/,$//')]}"
  fi

  echo "go: run $RUN_ID  (milestone $MILESTONE, subject $SUBJECT)"
  echo "go: tree $head [$tree_state]   fixed-now $FIXED_NOW"
  echo "go: run dir $RUN"
  [[ "$tree_state" == "dirty" ]] && echo "go: NOTE — the working tree is dirty. That is a fact, not a failure; it is stamped on the report."

  # --- waivers, recorded as verdicts, never as absences ----------------------
  # A waiver is bound to the corpus it was granted over (`--corpus-digest`), and
  # the gate check below re-derives that digest before every gated stage. Before
  # this binding existed, one `--waive HG1` at the top of a run covered every
  # later edit to the encoding: the corpus could be changed mid-run and every
  # HG1-gated stage re-ran against unreviewed content with no diff, no chain
  # break and no verify finding — the circumvention was not merely unfakeable
  # but deniable, which is the opposite of what §6.3 claims.
  #
  # HG2 cannot be waived here at all. Its subject is anything outward-facing,
  # and the skill's rule is that no agent decides that on its own; a rule that
  # lives only in prose while the driver accepts the flag is not a rule.
  # Two passes: every waiver is validated before ANY is recorded, so a refused
  # one does not leave the journal carrying its accepted siblings.
  local w gname greason
  for w in "${WAIVERS[@]:-}"; do
    [[ -n "$w" ]] || continue
    gname="${w%%=*}"
    greason="${w#*=}"
    if [[ "$gname" == "HG2" ]]; then
      cat >&2 <<EOF
go.sh: --waive HG2 is REFUSED.

HG2 is Meng's go on anything outward-facing — creating the corpus repo,
publishing the report, any lexipedia contact. An agent may not decide on its own
that an outward-facing act is warranted, so there is no self-service route past
it: HG2 opens on a signature or not at all.

  etc/go/gate-request.sh HG2 --run <rundir>     # prints the payload to sign
  ssh-keygen -Y sign -f <key> -n l4-go-gate-hg2 <rundir>/HG2.payload.txt

HG1 may be waived (--waive HG1="reason"), because its subject is a review this
run can proceed without having had, provided the report says so.
EOF
      exit 2
    fi
    [[ "$gname" == "HG1" ]] || die_usage "--waive: unknown gate '$gname'; SPEC.md §7.3 defines HG1 and HG2, and only HG1 is waivable"
    [[ -n "$greason" && "$greason" != "$gname" ]] || die_usage "--waive $gname= needs a reason; a waiver with no reason cannot be printed in the report"
  done
  for w in "${WAIVERS[@]:-}"; do
    [[ -n "$w" ]] || continue
    gname="${w%%=*}"
    greason="${w#*=}"
    node "$LIB/receipt.mjs" gate --run "$RUN" --gate "$gname" --state waived \
      --corpus-digest "$corpus_digest" --reason "$greason"
    echo "go: gate $gname WAIVED — $greason"
    if [[ "$MILESTONE" == "g2" ]]; then
      echo "go:   the waiver covers the de novo deposit set $corpus_digest and nothing else; deposit or edit one and $gname re-opens."
    else
      echo "go:   the waiver covers corpus $corpus_digest and nothing else; edit a corpus file and $gname re-opens."
    fi
  done

  # --- dispatch --------------------------------------------------------------
  local overall=0
  local s
  while read -r s; do
    [[ -n "$s" ]] || continue
    if [[ -n "$ONLY" && "$s" != "$ONLY" ]]; then continue; fi

    # gate check, default-deny
    local gate=""
    [[ " $gated_by_HG1 " == *" $s "* ]] && gate="HG1"
    [[ " $gated_by_HG2 " == *" $s "* ]] && gate="HG2"
    if [[ -n "$gate" ]]; then
      local gstate
      gstate=$(gate_grant_state "$RUN/journal.ndjson" "$gate" "$corpus_digest")
      if [[ "$gstate" != "open" ]]; then
        if [[ "$gstate" == "stale" ]]; then
          echo "go: $gate was granted over a different corpus than this run is now using." >&2
          echo "go:   corpus now: $corpus_digest" >&2
          echo "go:   The grant does not cover it, so the gate is closed again." >&2
        fi
        if bash "$GO_ROOT/etc/go/gate-verify.sh" "$gate" --run "$RUN"; then
          node "$LIB/receipt.mjs" gate --run "$RUN" --gate "$gate" --state satisfied \
            --namespace "$([[ $gate == HG1 ]] && echo l4-go-gate || echo l4-go-gate-hg2)" \
            --corpus-digest "$corpus_digest" \
            --signature-file "$RUN/$gate.payload.txt.sig"
        else
          node "$LIB/receipt.mjs" gate --run "$RUN" --gate "$gate" --state refused \
            --corpus-digest "$corpus_digest" \
            --reason "no verifying signature over the current corpus; see etc/go/gate-request.sh $gate --run $RUN"
          echo "go: $gate is not satisfied — refusing $s and every stage after it." >&2
          echo "go: VERDICT: GATE" >&2
          node "$LIB/receipt.mjs" run-end --run "$RUN" --verdict GATE --exit 3
          exit 3
        fi
      fi
    fi

    local script="$PHASES/$s.sh"
    [[ -f "$script" ]] || {
      echo "go.sh: BROKEN — declared stage $s has no script at $script" >&2
      exit 4
    }

    export GO_STAGE="$s"

    # inputs digest: the stage declares its own inputs, the driver digests them,
    # and the driver folds in the one input no stage can declare — the `l4`
    # binary it was handed. `text:` entries are literal digest contributors; see
    # digestSet in lib/ledger.mjs.
    local inputs digest
    inputs=$(GO_STAGE="$s" bash "$script" --inputs 2>/dev/null || true)
    if [[ -n "$inputs" ]]; then
      digest=$(printf '%s\ntext:l4-binary=%s\n' "$inputs" "$l4_sha" | node "$LIB/digest.mjs" --stdin)
    else
      digest=""
    fi
    export GO_INPUTS_DIGEST="$digest"

    # resumability: a completed stage with an unchanged inputs digest is replayed.
    local prior=""
    if [[ -n "$digest" ]]; then
      prior=$(node -e '
        import("'"$LIB"'/ledger.mjs").then(m => {
          const r = m.findReplayable(process.argv[1], process.argv[2], process.argv[3]);
          if (r) process.stdout.write(JSON.stringify({hash: r.hash, status: r.status, reason: r.reason ?? "", blocker: r.blocker ?? "", label: r.label ?? "", metrics: r.metrics ?? {}, notes: r.notes ?? []}));
        });
      ' "$RUN/journal.ndjson" "$s" "$digest")
    fi

    if [[ -n "$prior" ]]; then
      local phash pstatus preason pblocker plabel pmetrics pnotes pauthors
      local field
      for field in hash status reason blocker label; do
        printf -v "p$field" '%s' "$(printf '%s' "$prior" | node -e '
          let s = "";
          process.stdin.on("data", (d) => (s += d)).on("end", () => process.stdout.write(String(JSON.parse(s)[process.argv[1]] ?? "")));
        ' "$field")"
      done
      pmetrics=$(printf '%s' "$prior" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const m=JSON.parse(s).metrics||{};process.stdout.write(Object.entries(m).map(([k,v])=>`${k}=${String(v).replace(/\n/g," ")}`).join("\n"))})')
      pnotes=$(printf '%s' "$prior" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const n=JSON.parse(s).notes||[];process.stdout.write(n.map(x=>String(x.text).replace(/\n/g," ")).join("\n"))})')
      pauthors=$(printf '%s' "$prior" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const a=[...new Set((JSON.parse(s).notes||[]).map(x=>x.author))];process.stdout.write(a.length===1?a[0]:"")})')
      # A replayed receipt KEEPS its verdict and names the receipt that earned
      # it. It carries no oracle of its own, and it should not: the oracle ran,
      # on inputs whose digest is byte-identical, and its row is in the same
      # hash-chained journal. Demoting a replayed PASS would make the milestone
      # verdict change when the same milestone is run twice, which is exactly
      # the property resumability needs to preserve.
      #
      # Everything else on the receipt DOES carry forward, because
      # render-report.mjs reads the LATEST row per stage and a replay is that
      # row. Dropping them silently rewrote the report on the first resume:
      #   * metrics — every measured number vanished (fidelity counts, assertion
      #     count) and the corpus sha256 table rendered "(none recorded)" for
      #     files the run demonstrably read one journal row earlier;
      #   * label — `PASS (INTERIM)` became a bare `PASS` and
      #     `UNVERIFIED (EXTRA)` a bare `UNVERIFIED`. The label rides IN the
      #     status by design, so losing it upgrades what the report claims;
      #   * notes — the "claimed, not verified" caveats disappeared, which is
      #     the wrong direction for a caveat to drift.
      local extra=()
      [[ -n "$preason" ]] && extra+=(--reason "$preason")
      [[ -n "$pblocker" ]] && extra+=(--blocker "$pblocker")
      [[ -n "$plabel" ]] && extra+=(--label "$plabel")
      [[ -n "$pauthors" ]] && extra+=(--author "$pauthors")
      if [[ -n "$pmetrics" ]]; then
        local kv
        while IFS= read -r kv; do
          [[ -n "$kv" ]] && extra+=(--metric "$kv")
        done <<<"$pmetrics"
      fi
      if [[ -n "$pnotes" ]]; then
        local nt
        while IFS= read -r nt; do
          [[ -n "$nt" ]] && extra+=(--note "$nt")
        done <<<"$pnotes"
      fi
      node "$LIB/receipt.mjs" stage-end --run "$RUN" --stage "$s" --status "$pstatus" \
        --inputs-digest "$digest" --replayed-from "$phash" --artifacts-from "$phash" "${extra[@]}"
      echo "go: $s replayed (inputs unchanged)"
      [[ -n "$THROUGH" && "$s" == "$THROUGH" ]] && break
      continue
    fi

    node "$LIB/receipt.mjs" stage-begin --run "$RUN" --stage "$s" --inputs-digest "$digest"

    set +e
    bash "$script"
    local prc=$?
    set -e
    case $prc in
      0) ;;
      1) overall=1 ;;
      3)
        echo "go: $s refused (gate). VERDICT: GATE" >&2
        node "$LIB/receipt.mjs" run-end --run "$RUN" --verdict GATE --exit 3
        exit 3
        ;;
      4)
        echo "go: $s BROKEN. VERDICT: BROKEN" >&2
        node "$LIB/receipt.mjs" run-end --run "$RUN" --verdict BROKEN --exit 4
        exit 4
        ;;
      5)
        echo "go: $s SKIPPED while L4_GO_REQUIRED=1." >&2
        node "$LIB/receipt.mjs" run-end --run "$RUN" --verdict INCOMPLETE --exit 5
        exit 5
        ;;
      *) overall=1 ;;
    esac

    [[ -n "$THROUGH" && "$s" == "$THROUGH" ]] && break
  done <<<"$stages"

  # --- milestone verdict, recomputed from the journal ------------------------
  # verify-run.mjs answers three questions — does the chain verify, do the
  # artifacts every receipt names still hash as recorded, and what is the
  # milestone verdict — and encodes the first two in `chain_ok`/`findings` and
  # in its EXIT CODE. This used to read `.verdict` and discard the rest behind
  # `|| true`, so a run whose recorded artifacts had vanished, or whose journal
  # had been hand-edited, still printed `COMPLETE` and exited 0 while
  # `go.sh verify` over the same directory listed the findings and exited 1.
  # The second-party check is still the authority; the driver simply no longer
  # contradicts it.
  local vjson vsummary vhead verdict vexit chain_state findings_n
  vjson=$(node "$LIB/verify-run.mjs" "$RUN" --json || true)
  vsummary=$(printf '%s' "$vjson" | node -e '
    let s = "";
    process.stdin.on("data", (d) => (s += d)).on("end", () => {
      const j = JSON.parse(s);
      process.stdout.write(`${j.verdict}\t${j.chain_ok ? "ok" : "broken"}\t${j.findings.length}\n`);
      for (const f of j.findings) process.stdout.write(`  finding [${f.kind}] ${f.detail}\n`);
    });
  ')
  vhead=$(printf '%s\n' "$vsummary" | head -1)
  verdict=$(printf '%s' "$vhead" | cut -f1)
  chain_state=$(printf '%s' "$vhead" | cut -f2)
  findings_n=$(printf '%s' "$vhead" | cut -f3)

  # A journal that does not verify was written by something other than
  # receipt.mjs, so nothing computed from it is a statement about the corpus.
  if [[ "$chain_state" != "ok" ]]; then verdict="BROKEN"; fi

  case "$verdict" in
    COMPLETE) vexit=0 ;;
    GATE) vexit=3 ;;
    BROKEN) vexit=4 ;;
    *) vexit=1 ;;
  esac
  [[ $overall -eq 1 && $vexit -eq 0 ]] && vexit=0 # a leg finding is accounted for, not a milestone failure

  if [[ "${findings_n:-0}" -gt 0 ]]; then
    echo >&2
    echo "go: verify-run reported $findings_n finding(s) about this run's own journal and artifacts:" >&2
    printf '%s\n' "$vsummary" | tail -n +2 >&2
    echo "go:   re-derive with: etc/go/go.sh verify --run-id $RUN_ID --gates" >&2
    [[ $vexit -eq 0 ]] && vexit=1
  fi

  node "$LIB/receipt.mjs" run-end --run "$RUN" --verdict "$verdict" --exit "$vexit"

  # The FINAL report, rendered after run_end so it carries the run's own
  # verdict. It is derived, not attested: no receipt hashes it, because anyone
  # can re-run render-report.mjs over the journal and get the same bytes. The
  # hashed, preliminary render p9-report produced lives in artifacts/.
  if [[ -f "$RUN/journal.ndjson" ]]; then
    node "$GO_ROOT/etc/go/report/render-report.mjs" "$RUN" --format md,html >/dev/null 2>&1 || true
  fi

  echo
  echo "go: VERDICT: $MILESTONE $verdict"
  if [[ "$MILESTONE" == "g2" ]]; then
    echo "go:   g2's verdict is over its DEPOSIT-VALIDATING stages. It says the deposits"
    echo "go:   present are well formed and names the ones that are not there. It does not"
    echo "go:   say a de novo run happened: SPEC.md §6's G2 acceptance is the §8 diff oracle"
    echo "go:   (node etc/go/lib/denovo-diff.mjs), which no stage calls."
  fi
  echo "go: journal  $RUN/journal.ndjson"
  [[ -f "$RUN/report.md" ]] && echo "go: report   $RUN/report.md"
  exit "$vexit"
}

case "$CMD" in
  run) cmd_run ;;
  plan) cmd_plan ;;
  status) cmd_status ;;
  verify) cmd_verify ;;
  gc) cmd_gc ;;
  help | -h | --help) usage ;;
  *) die_usage "unknown command '$CMD'" ;;
esac

#!/usr/bin/env bash
# go.sh — the only entry point of the "SEC Regulation Crowdfunding: go" pipeline.
#
# Phase dispatch, gate enforcement, resumability. Everything with an exit code
# lives under etc/go/; everything that is a judgement lives in the skill at
# .claude/skills/running-the-l4-pipeline/. This script never calls a model, and
# the skill never writes a status.
#
# A RUN IS ABOUT ONE SUBJECT AND ONE ENCODING OF IT, and `--encoding` is what
# selects it. There is no capability label: G0-G4 describe what this tooling can
# do in the order it was built, which is a fact about this repository and not
# about any body of law (PIPELINE-ARTIFACT-MODEL-SPEC.md §3.9).
#
# --encoding primary (the default) — the run drives the COMMITTED encoding
# through every currently-reachable projection and emits conversion report v0.
# Nothing is encoded from source.
#
# --encoding <id> — the run is about an ADDITIONAL encoding, and VALIDATES what
# an agent deposited rather than producing it. P1-P4 do not fetch, search,
# encode or find forks (those need the network or a model; this driver takes
# neither); p3-check, p6-tests, p8-verify and p7-dmn (emit-only) measure the
# deposited module set, and p8-diff runs SPEC.md §8's diff oracle over the
# declared surface map. Every stage reports SKIPPED, on the record, when its
# deposit is not there — so COMPLETE means every stage is accounted for, NOT
# that a de novo run happened. See `go.sh plan --subject ID --encoding <id>`.
#
# --encoding undeclared — the same stage set over a subject that declares no
# additional encoding at all: a forecast of what would have to be deposited.
#
# This script NEVER runs cabal, never commits, and never pushes.
#
#   Usage:  etc/go/go.sh <command> [options]
#
#     run     --subject ID [--encoding primary|ID|undeclared] [--run-id ID]
#             [--through STAGE] [--only STAGE] [--waive HG1=REASON]
#             [--fixed-now ISO8601]
#
#             HG1 is the only waivable gate. HG2 guards anything outward-facing
#             and opens on a signature or not at all; --waive HG2 exits 2.
#     doctor  [--subject ID] [--encoding primary|ID|undeclared]
#             the front-door forecast: which declared stages will run whole,
#             which will SKIP and why, each with its remedy. Runs no stage.
#             Exit: 0 wants met · 1 will not run whole · 2 no usable l4.
#     plan    [--subject ID] [--encoding primary|ID|undeclared]
#     status  [--run-id ID] [--subject ID]
#     verify  [--run-id ID] [--subject ID] [--gates]
#     readset [--run-id ID] [--subject ID] [--stage S] [--json]
#             R4: what a run READ, itemised, with each member's role and
#             whether a newer version of it exists. Freshness is Make's — a
#             newer prerequisite — and is derived, never stored.
#             Exit: 0 all current · 1 something is stale.
#     subject-report --subject ID [--json]
#             R13: the account of a SUBJECT across every run whose evidence
#             survives, not of one run. Each phase resolves to CURRENT, STALE
#             or NEVER RUN. Exit: 0 none stale · 1 something is stale.
#     gc      [--keep N]
#     new-subject ID --citation TEXT --source-url URL [--display-name TEXT]
#             [--encoding-main PATH] [--force]
#             Scaffold etc/go/subjects/ID/ so `plan --subject ID` works at
#             once. The sidecar declares encoding.state "unwritten": the
#             encoding does not exist yet, every stage that reads a module
#             will SKIP naming the file to deposit, and the gate digest is
#             already over that absent path, so depositing it re-opens HG1.
#             pins.json and known-defects.json are emitted EMPTY and marked
#             unmeasured — both are measurement records, and a scaffolder
#             that invented plausible contents would be manufacturing the
#             evidence the pipeline exists to demand.
#     help
#
#   Exit codes (extending etc/check-bpmn-kie.sh's 0/1/2/3/4):
#     0 clean   1 finding   2 usage   3 gate   4 broken   5 skipped-while-required
#
#   Environment:
#     L4                   path to a prebuilt `l4`. When unset, `run` and
#                          `doctor` DISCOVER one under dist-newstyle — own
#                          worktree first, then newest sibling (lib/
#                          toolchain.sh). Explicit always wins; with none
#                          found the run refuses. This script NEVER builds.
#     JL4_LSP_CMD          prebuilt jl4-lsp for the ladder leg; discovered the
#                          same way when unset
#     JL4_GO_SERVICE_URL   a LOOPBACK jl4-service for the MCP leg; non-loopback
#                          is refused (an outward-facing write is HG2's). Never
#                          auto-discovered: a deployment target must be named
#                          by a human, not found by a probe.
#     L4_GO_RUNDIR         where runs live (default $TMPDIR/l4-go)
#     L4_GO_REQUIRED       1 ⇒ any SKIPPED stage is fatal (exit 5), as CI
#                          wants; `run` refuses at the door when the doctor
#                          forecasts one, rather than minutes in
#     L4_GO_FIXED_NOW      pin the clock (default 2025-01-31T00:00:00Z)

set -euo pipefail

GO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PHASES="$GO_ROOT/etc/go/phases"
LIB="$GO_ROOT/etc/go/lib"

# Toolchain discovery (go_provision_toolchain): fills L4/JL4_LSP_CMD from
# dist-newstyle when unset. Sourced here, invoked only by `run` and `doctor` —
# `plan` and `help` must keep working with no binary anywhere (CI asserts it).
source "$LIB/toolchain.sh"

# --- the stage table --------------------------------------------------------
# G1's declared stages, in order. p0-preflight, p3-check, p6-tests and
# p9-report are always declared; each p7 leg is declared iff the subject's
# sidecar (etc/go/subjects/<id>/subject.json) has an entry for it in `legs`.
# That is what keeps COMPLETE honest for a subject that has, say, no wizard
# and no regulative rules: its sidecar omits those legs, so their absence
# cannot make a run INCOMPLETE and their presence is never faked.
# `p9-report` is last: the report reads the journal, so it must run after
# everything that writes to it. PRIMARY_STAGES is assembled after subject
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
# names its blocker. They are NOT declared members of any stage set, so they
# cannot make a run INCOMPLETE by their absence.
#
# p1-ingest, p2-sweep, p3-encode, p4-forks and p5-gate left this list: they are
# now real stages that validate a deposit, and they are g2's declared members.
# p8-verify left it 2026-08-09 (D3): declared in both stage sets below.
UNIMPLEMENTED_STAGES=(p10-publish)

# G2's declared stages, in order (2026-08-09, D5). The five deposit-validating
# stages, the measurement stages over the deposit, the §8 comparator, and the
# report.
#
# LAYERING, stated where the list is declared because both P3 stages run:
# p3-encode is deposit ACCEPTANCE — the module exists and `l4 check` accepts
# it, nothing else — while p3-check holds the P3 HOUSE RULES (BRANCH over
# ELSE IF, @ref per dated arm, the per-origin floors) against the same
# deposit. They are one phase's two halves and their receipts say so.
# p6-tests runs the deposit's own #ASSERT directives; p7-dmn runs EMIT-ONLY
# (no goldens exist for a deposit — see the leg's golden-absent branch); p8-verify runs
# `l4 verify`; p8-diff is the ONE stage licensed to read both the committed
# corpus and the deposit, because SPEC.md §8's acceptance is precisely the
# comparison of the two over the declared surface map.
#
# STILL NOT HERE: p0-preflight — so a deposit run carries no CLI-surface pin and no
# failing-#ASSERT tripwire, while p6-tests' oracle rests on the workaround
# that tripwire defends (§5.3); a p0 for the deposit path is future work. The p7 legs other
# than p7-dmn read committed goldens/entries the deposit does not have; the
# plan names each one's missing piece. p9-report reads journal.ndjson and
# nothing else, so it is correct for either stage set.
DEPOSIT_STAGES=(p1-ingest p2-sweep p3-encode p3-check p4-forks p5-gate p6-tests p7-dmn p8-verify p8-diff p9-report)

# SPEC.md §7.3: exactly two human gates. HG1 blocks P6 onward; HG2 blocks
# anything outward-facing, which on the primary path means the MCP deployment
# leg and P10. gated_by_HG1 is DERIVED after subject resolution: P6 onward means p6-tests,
# every declared p7 leg, and p9-report.
gated_by_HG1=""
gated_by_HG2="p10-publish"

usage() {
  # DERIVED, not a hardcoded last line. `sed -n '2,60p'` truncated the block the
  # moment the header grew past 60 lines — R9's rewrite pushed it to 89, so
  # `help` stopped printing its last five commands INCLUDING `help` itself, and
  # ended mid-sentence. Nothing caught it: check-skill-drift skips `help` by
  # construction, and a truncated usage still exits 0.
  #
  # The header is every comment line from line 2 up to the first line that is
  # not a comment, so the block defines its own end and the next edit cannot
  # re-break this.
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

die_usage() {
  echo "go.sh: $1" >&2
  echo "run 'etc/go/go.sh help' for usage" >&2
  exit 2
}

# A VALUE-TAKING FLAG MUST BE FOLLOWED BY A VALUE, and saying so is this
# driver's job rather than the shell's.
#
# Every such arm reads `$2` and shifts twice. With a flag last on the line there
# is no `$2`, and under `set -euo pipefail` bash aborts with
# `go.sh: line 246: $2: unbound variable` and exit 1 — an interpreter stack
# trace where a usage message belongs, naming a line number instead of the flag
# the caller typed. The exit code is wrong too: 2 is this driver's usage exit
# and 1 means a real finding about the corpus, so a script that distinguishes
# them reads a typo as a result.
#
# Called as `need_val "$@"` from inside the arm, where `$1` is still the flag
# and `$2` its value.
need_val() {
  [[ $# -ge 2 ]] || die_usage "$1 needs a value"
}

# --- argument parsing -------------------------------------------------------
CMD="${1:-help}"
shift || true

SUBJECT=""
RUN_ID=""
THROUGH=""
ONLY=""
KEEP=5
WANT_GATES=0
declare -a WAIVERS=()
NEW_ID=""
NEW_DISPLAY_NAME=""
NEW_CITATION=""
NEW_SOURCE_URL=""
NEW_ENCODING=""
NEW_FORCE=0
declare -a STORE_ARGS=()
STAGE_ONLY=""
WANT_JSON=0
ENCODING_ID=""
# Whether --encoding was PASSED, which "" cannot tell you: the initializer above
# and an explicitly empty value are the same string. Only the flag distinguishes
# "no selection given, use the default" from "a selection was attempted and named
# nothing", and R9 made that difference matter — --encoding is now the sole
# selector of what a run is about.
ENCODING_SEEN=0

# `store` owns its own flag vocabulary (--keep-days, --dry-run, --allow-waived,
# --subject, --stage), so the driver hands it every argument verbatim rather
# than parsing them here. A driver that parsed them would have to be edited
# every time the store grows a verb.
if [[ "$CMD" == "store" ]]; then
  STORE_ARGS=("$@")
  set --
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subject)
      need_val "$@"
      SUBJECT="$2"
      shift 2
      ;;
    --run-id)
      need_val "$@"
      RUN_ID="$2"
      shift 2
      ;;
    --through)
      need_val "$@"
      THROUGH="$2"
      shift 2
      ;;
    --only)
      need_val "$@"
      ONLY="$2"
      shift 2
      ;;
    --waive)
      need_val "$@"
      WAIVERS+=("$2")
      shift 2
      ;;
    --fixed-now)
      need_val "$@"
      L4_GO_FIXED_NOW="$2"
      shift 2
      ;;
    --encoding)
      need_val "$@"
      ENCODING_ID="$2"
      ENCODING_SEEN=1
      shift 2
      ;;
    --stage)
      need_val "$@"
      STAGE_ONLY="$2"
      shift 2
      ;;
    --json)
      WANT_JSON=1
      shift
      ;;
    --keep)
      need_val "$@"
      KEEP="$2"
      shift 2
      ;;
    --gates)
      WANT_GATES=1
      shift
      ;;
    --display-name)
      need_val "$@"
      NEW_DISPLAY_NAME="$2"
      shift 2
      ;;
    --citation)
      need_val "$@"
      NEW_CITATION="$2"
      shift 2
      ;;
    --source-url)
      need_val "$@"
      NEW_SOURCE_URL="$2"
      shift 2
      ;;
    # RENAMED FROM `--encoding`, which R2/R3 gave a second, unrelated meaning.
    #
    # This names where a NEW subject's entry module will live — it becomes
    # `encoding.main` in the scaffolded sidecar. `--encoding` now selects which
    # encoding a RUN is about, and its arm sits earlier in this same `case`, so
    # this one had become unreachable: `new-subject … --encoding path/x.l4`
    # exited 0, said nothing, and wrote the default path. A documented input
    # silently discarded, which `bash -n` cannot see because a duplicate `case`
    # label is legal shell. selftest.mjs now checks for one directly.
    --encoding-main)
      need_val "$@"
      NEW_ENCODING="$2"
      shift 2
      ;;
    --force)
      NEW_FORCE=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    # One bare positional, and only for `new-subject`: the id of the subject
    # being created. Every other command names its subject with --subject,
    # which resolves an EXISTING sidecar — the thing this command's argument
    # by definition is not.
    *)
      # `--milestone` was RETIRED, and it refuses rather than being quietly
      # unknown: a reader who types it has a mental model to correct, and the
      # message is the only place left in the system that can correct it.
      #
      # DELIBERATELY NOT A `case` ARM. check-skill-drift.mjs decides a flag
      # exists by testing whether go.sh contains the literal `--milestone)`, so
      # a real arm would make the drift guard green over any stale `--milestone`
      # command line left in SKILL.md — which is exactly the sweep this ruling
      # depends on. Matching it here keeps `flagExists("--milestone")` false, so
      # a surviving mention fails CI.
      if [[ "$1" == --milestone || "$1" == --milestone=* ]]; then
        echo "go.sh: --milestone was retired by PIPELINE-ARTIFACT-MODEL-SPEC.md §3.9 — G0-G4 are" >&2
        echo "       CAPABILITY milestones (what this tooling can do, in the order it was built)," >&2
        echo "       not phases a body of law passes through. A run is about one subject and one" >&2
        echo "       ENCODING of it, and that is what selects it now:" >&2
        echo "         --milestone g1  ->  --encoding primary      (the default; drop the flag)" >&2
        echo "         --milestone g2  ->  --encoding <id>, or --encoding undeclared when the" >&2
        echo "                             subject declares none. List the ids with:" >&2
        echo "                               node etc/go/lib/subject.mjs <subject> --encodings" >&2
        exit 2
      fi
      if [[ "$CMD" == "new-subject" && -z "$NEW_ID" && "$1" != -* ]]; then
        NEW_ID="$1"
        shift
      elif [[ "$CMD" == "store" ]]; then
        STORE_ARGS+=("$1")
        shift
      else
        die_usage "unknown option $1"
      fi
      ;;
  esac
done

# `new-subject` takes no run selection, so `--encoding` there is either the old
# spelling of `--encoding-main` or a misunderstanding of what the command does.
# Accepting it silently is how the rename would keep the very defect it repairs:
# the flag would parse, set a variable `new-subject` never reads, and exit 0
# having written the default path — which is exactly what the collision did.
if [[ "$CMD" == "new-subject" && $ENCODING_SEEN -eq 1 ]]; then
  die_usage "new-subject takes no --encoding: it registers a subject rather than selecting a run over one. To say where the entry module will live, use --encoding-main PATH"
fi

RUNDIR_BASE="${L4_GO_RUNDIR:-${TMPDIR:-/tmp}/l4-go}"
FIXED_NOW="${L4_GO_FIXED_NOW:-2025-01-31T00:00:00Z}"

# --- subject resolution -----------------------------------------------------
# Only three commands are ABOUT a body of law: `run` executes stages against
# one, `plan` prints that subject's stage list, and `doctor` checks the
# environment those stages want. `help`, `status`, `verify` and `gc` are about
# the DRIVER and the run store; none of them reads a GO_S_* variable, and
# demanding a subject from them is a requirement with nothing behind it.
#
# That distinction was free while one sidecar existed, because the sole subject
# was the silent default. Adding a second made the requirement bite, and it bit
# `help` first: `etc/go/go.sh help` — the command the refusal message itself
# tells you to run — exited 2 without printing usage, which is how the CI step
# that calls it went red on a PR that never touched the driver.
# A membership test and not a `case`, deliberately: check-skill-drift.mjs finds
# the dispatch table by matching the FIRST `case "$CMD" in` at column 0, so a
# second one here would shadow it and the checker would report every real
# command as undispatched. One dispatch table per driver is also just true.
_NEEDS_SUBJECT=0
# `subject-report` is here because it needs PRIMARY_STAGES and DEPOSIT_STAGES — the
# DECLARABLE universe — and those are assembled inside the subject-dependent
# region below. Without it the universe held only the deposit list, so every
# g1-only phase reached the report solely via a surviving journal's
# declared_stages, and would vanish entirely once those journals expired:
# exactly the silence R13 exists to break.
[[ " run plan doctor subject-report " == *" $CMD "* ]] && _NEEDS_SUBJECT=1

# With no --subject, the sole sidecar under etc/go/subjects/ is the default;
# once a second subject exists, naming one becomes mandatory — a silent
# default among several would make a run about an unnamed body of law.
if [[ $_NEEDS_SUBJECT -eq 1 && -z "$SUBJECT" ]]; then
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
if [[ -n "$SUBJECT" ]]; then
  # WHICH ENCODING THIS RUN IS ABOUT — the only thing a run is selected by.
  #
  # `--encoding` takes exactly the three values GO_S_ENCODING_ID can hold, so
  # the input vocabulary and the output vocabulary are the same words:
  #
  #   primary      the committed encoding. The default; the flag may be omitted.
  #   <id>         that additional encoding, NAMED. subject.mjs refuses an id
  #                the subject does not declare, and lists the ones it does.
  #   undeclared   the deposit path over a subject that declares NO additional
  #                encoding — a forecast of what would have to be deposited.
  #
  # NOTHING RESOLVES AN ORDINAL. `--milestone g2` used to mean "the additional
  # encoding", picked by counting, and that is a POSITION rather than a name: it
  # changes meaning silently as a subject's declarations grow and breaks loudly
  # the day a second one is declared. `regcf` is one edit from that. §3.2 is the
  # ruling; R9 is where the driver stops disagreeing with it.
  # AN UNPASSED FLAG MEANS "the default"; a PASSED-BUT-EMPTY one means the caller
  # tried to name something and named nothing. R9 made `--encoding` the sole
  # selector of what a run is about, so silently coercing an empty selector to
  # `primary` would quietly run a different thing than the caller asked for.
  # `${ENCODING_ID:-primary}` alone cannot tell the two apart, because the
  # initializer is itself the empty string — hence ENCODING_SEEN.
  if [[ $ENCODING_SEEN -eq 1 && -z "$ENCODING_ID" ]]; then
    die_usage "--encoding needs a value: primary, a declared encoding id, or undeclared"
  fi
  _ENC="${ENCODING_ID:-primary}"
  _NO_ADDITIONAL_ENCODING=0
  _ENC_UNDECLARED=0
  if [[ "$_ENC" == "undeclared" ]]; then
    mapfile -t _DECLARED < <(node "$LIB/subject.mjs" "$SUBJECT" --encodings 2>/dev/null || true)
    if [[ ${#_DECLARED[@]} -gt 0 && -n "${_DECLARED[0]}" ]]; then
      # `undeclared` is a CLAIM ABOUT THE SUBJECT, and here it is false. Running
      # anyway would measure nothing and report it green.
      echo "go.sh: --encoding undeclared says '$SUBJECT' declares no additional encoding," >&2
      echo "       but it declares ${#_DECLARED[@]}. Name one:" >&2
      printf '         %s\n' "${_DECLARED[@]}" >&2
      echo "       ...or --encoding primary for the committed encoding." >&2
      exit 2
    fi
    # NOT an error. A subject that has not yet declared an additional encoding is
    # exactly the subject a deposit PLAN is most useful for: it forecasts what
    # would have to be deposited. The module set is empty — there is no
    # additional encoding to iterate — and the deposit stages report SKIPPED
    # naming what is missing, which is what R12's "unwritten" case depends on.
    _ENC=""
    _NO_ADDITIONAL_ENCODING=1
    # The run is about an additional encoding that DOES NOT EXIST YET, and the
    # stages must say so. Leaving GO_S_ENCODING_ID at "primary" made every skip
    # reason tell the reader to add modules to the COMMITTED encoding — advice
    # that is wrong in the only case that ever fires.
    _ENC_UNDECLARED=1
  fi
  _ENC_ARGS=()
  [[ -n "$_ENC" && "$_ENC" != "primary" ]] && _ENC_ARGS=(--encoding "$_ENC")
  SUBJECT_ENV="$(node "$LIB/subject.mjs" "$SUBJECT" "${_ENC_ARGS[@]}")" || exit 2
  eval "$SUBJECT_ENV"
  export "${!GO_S_@}"
fi

# Everything from here to the end of the stage assembly is ABOUT a subject: it
# resolves the module set, the gate digest set and the declared stage list from
# the sidecar. `help`, `status`, `verify` and `gc` reach none of it, and under
# `set -u` it would abort them on GO_S_ENCODING being unbound — which is how
# `gc` came to exit 1 rather than collect anything the first time the subject
# requirement was made conditional. Guarding the region, rather than the
# requirement alone, is what makes those four commands genuinely
# subject-independent.
if [[ $_NEEDS_SUBJECT -eq 1 ]]; then
  # --- 1. the module set this run's stages iterate ----------------------------
  #
  # THE SELECTED ENCODING IS THE MODULE SET. There is no "origin" sentinel and
  # no capability label: subject.mjs resolves the SELECTED encoding into the
  # ordinary GO_S_ENCODING_MODULES and GO_S_MIN_* names, so a stage reads the
  # encoding it was handed and no stage branches on which one it is. That is
  # what let p3-check, p6-tests and p7-dmn DELETE their per-origin arms (R2/R3)
  # rather than rename them.
  #
  # Floors travel with their encoding structurally: `encodings.<id>.checks` sits
  # inside the encoding it measures, so a committed floor cannot be applied to a
  # deposit and a deposit floor cannot be applied to the committed one.
  #
  # Exported EXPLICITLY: the `export "${!GO_S_@}"` glob above covers only the
  # sidecar-derived names, and the `--inputs` answers are produced by subshells
  # the dispatch loop spawns, which inherit only exported env.
  GO_MODULES="${GO_S_ENCODING_MODULES:-$GO_S_ENCODING${GO_S_WIZARD:+ $GO_S_WIZARD}}"
  # An asked-for additional encoding the subject has not declared leaves the
  # module set EMPTY rather than falling back to the committed one. Falling back
  # would silently run the deposit stages over the COMMITTED encoding and report
  # them green — a run that measured the wrong thing and said so confidently,
  # which is worse than the SKIP the stages give when they find nothing.
  [[ "${_NO_ADDITIONAL_ENCODING:-0}" == "1" ]] && GO_MODULES=""
  # `undeclared` is a THIRD value beside `primary` and a real id, because there
  # are genuinely three cases and collapsing any two makes a stage give advice
  # about the wrong key.
  [[ "${_ENC_UNDECLARED:-0}" == "1" ]] && GO_S_ENCODING_ID="undeclared"
  export GO_S_ENCODING_ID
  export GO_MODULES

  # --- 2. the declared stage list --------------------------------------------
  #
  # WHICH STAGES RUN IS A PROPERTY OF THE ENCODING, NOT OF A CAPABILITY LABEL
  # (R9, §3.9). A run about the COMMITTED encoding measures and projects it; a
  # run about an ADDITIONAL encoding validates what was deposited and compares
  # it against the committed one. Neither is "G1" or "G2": those name what the
  # tooling could do in the order it was built, which is a fact about this
  # repository's history and not about any body of law.
  #
  # p0-preflight, p3-check, p6-tests and p9-report are always declared; each p7
  # leg is declared iff the subject's sidecar has an entry for it in `legs`.
  # That is what keeps COMPLETE honest for a subject with, say, no wizard and no
  # regulative rules: its sidecar omits those legs, so their absence cannot make
  # a run INCOMPLETE and their presence is never faked. `p9-report` is last: the
  # report reads the journal, so it must run after everything that writes to it.
  PRIMARY_STAGES=(p0-preflight p3-check p6-tests p8-verify)
  for s in "${P7_LEG_ORDER[@]}"; do
    [[ " $GO_S_LEGS " == *" $s "* ]] && PRIMARY_STAGES+=("$s")
  done
  # p9-explain follows p9-report: both read the journal, and the explainer also
  # reads the report's own presence. Declared, so that a run which produced no
  # explainer says so in its verdict rather than staying silent.
  PRIMARY_STAGES+=(p9-report p9-explain)

  declare -a DECLARED_STAGES=()
  if [[ "$GO_S_ENCODING_ID" == "primary" ]]; then
    DECLARED_STAGES=("${PRIMARY_STAGES[@]}")
  else
    DECLARED_STAGES=("${DEPOSIT_STAGES[@]}")
  fi

  # --- 3. which stages HG1 gates — DERIVED, not listed ------------------------
  #
  # SPEC.md §7.3: HG1 blocks P6 onward. That sentence is the rule, so it is
  # written once and applied, rather than being transcribed into one hand-kept
  # list per stage set. The two lists it replaces were byte-equal to this
  # derivation on every selection the tree can express (measured, R9) — the
  # point is not that they were wrong but that nothing stopped them drifting:
  # an ungated stage here would publish HG1-unreviewed work and every downstream
  # honesty check would agree with the omission, because verify-run.mjs reads
  # the gated set out of run_begin.
  #
  # MINUS gated_by_HG2, not "and phase < 10": a stage carries one gate, and
  # `< 10` would merely be a coincidence of p10-publish's number. verify-run.mjs
  # reports a finding for any gate that gates a declared stage and has no
  # record, so a p10-publish that ever became declared would otherwise demand an
  # HG1 record it must never have.
  gated_by_HG1=""
  for s in "${DECLARED_STAGES[@]}"; do
    [[ " $gated_by_HG2 " == *" $s "* ]] && continue
    _n="${s#p}"
    _n="${_n%%-*}"
    [[ "$_n" =~ ^[0-9]+$ ]] || continue
    [[ "$_n" -ge 6 ]] && gated_by_HG1="${gated_by_HG1:+$gated_by_HG1 }$s"
  done
  unset _n

  # --- 4. what a gate on this run would bind to -------------------------------
  #
  # THE DIGEST BINDS TO WHAT THE RUN IS ABOUT: the module set its stages
  # actually iterate, plus every DEPOSIT a declared stage of this run reads.
  #
  # It used to branch on `--milestone`, which is R3's complaint exactly — same
  # subject, same tree, different flag, a different thing signed. Deriving it
  # from the selection makes the digest a function of what is under review, so
  # the same encoding yields the same digest whatever else the run does.
  #
  # It is GO_MODULES and not GO_S_ENCODING_MODULES. The difference bites in one
  # measured case: a deposit-path run over a subject that declares no additional
  # encoding empties GO_MODULES above, while GO_S_ENCODING_MODULES still holds
  # the committed encoding's modules — so the gate bound HG1 to an encoding the
  # run is not about, and the `text:` sentinel written for exactly that case was
  # unreachable because the array was never empty.
  #
  # GO_MODULES IS THE ONE ANSWER, AND EVERY STAGE MUST ASK IT. p3-encode read
  # the sidecar name directly and so typechecked those committed modules and
  # wrote PASS for a deposit that does not exist — the same divergence, one
  # layer down, found by the review of this change. Its four sibling
  # measurement stages already had the fallback; it now does too.
  #
  # ITERATE THE DEPOSITS, NOT THE STAGES. manifestText sorts but does NOT
  # dedupe, so a path contributed twice renders twice and changes the hash;
  # p1-ingest, p2-sweep, p4-forks and p5-gate all read all three natlang and
  # comparison deposits, so a stage-major union would double-count them.
  declare -a GO_ENCODING_FILES=()
  declare -a _MODS=()
  read -ra _MODS <<<"$GO_MODULES" || true
  [[ ${#_MODS[@]} -gt 0 ]] && GO_ENCODING_FILES+=("${_MODS[@]}")

  _declares() {
    local want="$1" s
    for s in "${DECLARED_STAGES[@]}"; do [[ "$s" == "$want" ]] && return 0; done
    return 1
  }
  # Each deposit, once, iff a declared stage reads it. HG1 covers the pairing
  # declarations too: a surface map edited after a waiver would otherwise ride
  # the old grant into p8-diff, and the narrative deposit taught the same lesson
  # at a different scale — editing explainer/orientation.md, re-running
  # `--only p9-explain` with no new grant, and watching the gate stay open while
  # the replaced prose went straight into the rendered document. A gate that
  # does not re-open over the thing it gates is not a gate over that thing.
  if [[ -n "${GO_S_NATLANG_BUNDLE:-}" ]] && { _declares p1-ingest || _declares p5-gate; }; then
    GO_ENCODING_FILES+=("$GO_S_NATLANG_BUNDLE")
  fi
  if [[ -n "${GO_S_NATLANG_REGISTER:-}" ]] && { _declares p2-sweep || _declares p5-gate; }; then
    GO_ENCODING_FILES+=("$GO_S_NATLANG_REGISTER")
  fi
  if [[ -n "${GO_S_COMPARISON_FORKS:-}" ]] && { _declares p4-forks || _declares p5-gate; }; then
    GO_ENCODING_FILES+=("$GO_S_COMPARISON_FORKS")
  fi
  if [[ -n "${GO_S_COMPARISON_SURFACE_MAP:-}" ]] && _declares p8-diff; then
    GO_ENCODING_FILES+=("$GO_S_COMPARISON_SURFACE_MAP")
  fi
  # Folding the narrative deposit in also closes the `--bless` hole for free:
  # blessing rewrites provenance.json, which is in this set, so the digest moves
  # and HG1 shuts.
  if [[ -n "${GO_S_EXPLAINER_DIR:-}" && -d "$GO_S_EXPLAINER_DIR" ]] && _declares p9-explain; then
    for _f in "$GO_S_EXPLAINER_DIR"/*.md "$GO_S_EXPLAINER_DIR"/manifest.json "$GO_S_EXPLAINER_DIR"/provenance.json; do
      [[ -e "$_f" ]] && GO_ENCODING_FILES+=("$_f")
    done
    unset _f
  fi
  # A run with nothing to bind still needs a digest to bind a gate to; `text:`
  # entries are literal digest contributors (digestSet). Reachable at last: it
  # fires for a subject that declares no additional encoding AND no deposits.
  [[ ${#GO_ENCODING_FILES[@]} -eq 0 ]] && GO_ENCODING_FILES=("text:no-additional-encoding-declared=$GO_S_ID")
fi

# gate_for STAGE -> HG1 | HG2 | -. ONE lookup, read by both plans, so a plan
# cannot print a gate the driver does not enforce. The deposit plan used to
# print the literal string "HG1" in each of its rows — a third copy of a claim
# the driver derives, and one that could not witness the derivation at all.
gate_for() {
  [[ " $gated_by_HG2 " == *" $1 "* ]] && {
    echo HG2
    return
  }
  [[ " $gated_by_HG1 " == *" $1 "* ]] && {
    echo HG1
    return
  }
  echo -
}

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

# The stage list this run declares. Resolved above, from the SELECTED ENCODING
# and nothing else — so there is no label that can be unknown, and no error arm.
# An encoding id that does not resolve was refused by subject.mjs before any of
# this ran, and it was refused BY NAME, listing the ids the subject declares.
stages_for() {
  printf '%s\n' "${DECLARED_STAGES[@]}"
}

# --- commands ---------------------------------------------------------------

# The DEPOSIT plan. It prints SPEC.md §4's full de novo stage order — including
# the stages this driver does NOT declare — because a plan that lists only
# what runs cannot tell you what is missing. Every row says which of the two it
# is, and the deposit rows say whether the deposit is there.
cmd_plan_deposit() {
  local b r f m enc key
  b="${GO_S_NATLANG_BUNDLE:-}"
  r="${GO_S_NATLANG_REGISTER:-}"
  f="${GO_S_COMPARISON_FORKS:-}"
  enc="${GO_S_ENCODING_ID:-primary}"
  # THE DEPOSIT MODULE SET IS THE SELECTED ADDITIONAL ENCODING'S, and there is
  # none when nothing was selected. Reading GO_S_ENCODING_MODULES unconditionally
  # showed the COMMITTED encoding here — `sg-succession`, which declares no
  # additional encoding, reported "7 declared module(s)" for a deposit it does
  # not have. A plan that confidently describes the wrong artifact is worse than
  # one that says `undeclared`, which is what the deposit contract asks for.
  case "$enc" in
    primary | undeclared)
      m=""
      key="encodings.<id>"
      ;;
    *)
      m="${GO_S_ENCODING_MODULES:-}"
      key="encodings.$enc"
      ;;
  esac

  if [[ "$enc" == "primary" || "$enc" == "undeclared" ]]; then
    echo "subject $SUBJECT, encoding undeclared — the deposit stage order, in order."
    echo "This subject declares NO additional encoding, so every deposit below reads"
    echo "'undeclared': the plan is a forecast of what would have to be declared under"
    echo "'encodings' and deposited, not an account of anything that exists."
  else
    echo "subject $SUBJECT, encoding '$enc' — the deposit stage order, in order:"
  fi
  echo
  printf '  %-14s %-9s %-11s %s\n' STAGE GATE DEPOSIT "WHAT IT CHECKS / WHY NOT"
  printf '  %-14s %-9s %-11s %s\n' "p1-ingest" "$(gate_for p1-ingest)" "$(deposit_state "$b")" "${b:-(no natlang_sources.bundle in subject.json)}"
  printf '  %-14s %-9s %-11s %s\n' "p2-sweep" "$(gate_for p2-sweep)" "$(deposit_state "$r")" "${r:-(no natlang_sources.register in subject.json)}"

  local mstate="undeclared" mn=0
  if [[ -n "$m" ]]; then
    local mm
    read -ra mm <<<"$m"
    mn=${#mm[@]}
    mstate=present
    local x
    for x in "${mm[@]}"; do [[ -f "$x" ]] || mstate=absent; done
  fi
  printf '  %-14s %-9s %-11s %s\n' "p3-encode" "$(gate_for p3-encode)" "$mstate" "$([[ $mn -gt 0 ]] && echo "$mn declared module(s); l4 check each" || echo "(no $key.modules in subject.json)")"
  printf '  %-14s %-9s %-11s %s\n' "p3-check" "$(gate_for p3-check)" "$mstate" "the P3 house rules over the SAME deposit: BRANCH over ELSE IF, @ref per dated arm, and the floors that travel with this encoding ($key.checks)"
  printf '  %-14s %-9s %-11s %s\n' "p4-forks" "$(gate_for p4-forks)" "$(deposit_state "$f")" "${f:-(no comparison.fork_register in subject.json)}"

  local n=0 s
  for s in "$b" "$r" "$f"; do [[ -n "$s" && -f "$s" ]] && n=$((n + 1)); done
  printf '  %-14s %-9s %-11s %s\n' "p5-gate" "$(gate_for p5-gate)" "$n of 3" "the cross-file joins; needs all three deposits, else SKIPPED"
  echo "  ---- HG1 ------- Meng's go on the encoding; blocks P6 onward (SPEC.md §7.3)"
  printf '  %-14s %-9s %-11s %s\n' "p6-tests" "$(gate_for p6-tests)" "$mstate" "the deposit's own #ASSERT directives, via l4 run --json results[]; floor = $key.checks.min_assertions"
  # Every p7 leg the sidecar declares, with a PRECISE reason per leg: a plan
  # that lists only what runs cannot tell a reader what is missing, and a
  # generic reason ("compares against committed goldens") was true of some
  # legs and false of others. p7-dmn is wired (emit-only, D6); the rest are
  # not, each for its own named lack.
  local leg legwhy
  for leg in "${P7_LEG_ORDER[@]}"; do
    [[ " $GO_S_LEGS " == *" $leg "* ]] || continue
    if [[ "$leg" == "p7-dmn" ]]; then
      printf '  %-14s %-9s %-11s %s\n' "p7-dmn" "$(gate_for p7-dmn)" "$mstate" "emit-only over the deposit: l4 export + dmn-moddle gate + engine-load probes; no golden exists, so no diff. Cases via encodings.<id>.legs['p7-dmn'].cases when declared"
      continue
    fi
    case "$leg" in
      p7-dmn-md) legwhy="golden-differential only, and this encoding declares no dmn-md golden; re-pointing it emit-only is unbuilt" ;;
      p7-bpmn) legwhy="needs an expected_dir + rules map for the deposit; the sidecar declares neither, and the leg's soundness gate reads committed goldens" ;;
      p7-ladder) legwhy="needs its own demo entry + figures dir, and none is declared for this encoding; the committed ones render the committed encoding" ;;
      p7-lts) legwhy="its oracle cross-checks digraph count against the BPMN discovery call over the committed corpus; re-pointing both halves is unbuilt" ;;
      p7-mcp) legwhy="needs a loopback JL4_GO_SERVICE_URL deployment of the DEPOSIT (it carries @exports); the leg today zips the committed corpus pair" ;;
      p7-tnr) legwhy="the sidecar declares no legs['p7-tnr'].golden for this encoding — a .nlg.golden is on disk but undeclared, and an undeclared golden gates nothing" ;;
      p7-wizard) legwhy="its well-formedness checks read the committed wizard module; the deposit declares no wizard split" ;;
      p7-akn) legwhy="re-pointing its shallow well-formedness pass at the deposit is unbuilt" ;;
      *) legwhy="re-pointing this leg at the deposit is unbuilt" ;;
    esac
    printf '  %-14s %-9s %-11s %s\n' "$leg" "NOT WIRED" "-" "$legwhy"
  done
  printf '  %-14s %-9s %-11s %s\n' "p8-verify" "$(gate_for p8-verify)" "$mstate" "l4 verify over the de novo module set; five control fixtures license the oracle"
  local sm="${GO_S_COMPARISON_SURFACE_MAP:-}" smwhat
  if [[ -n "$sm" ]]; then
    smwhat="SPEC.md §8's diff oracle over $sm"
  else
    smwhat="(no comparison.surface_map in subject.json)"
  fi
  printf '  %-14s %-9s %-11s %s\n' "p8-diff" "$(gate_for p8-diff)" "$(deposit_state "$sm")" "$smwhat"
  printf '  %-14s %-9s %-11s %s\n' "p9-report" "$(gate_for p9-report)" "-" "reads journal.ndjson and nothing else"
  echo
  # WHAT A GATE WOULD BIND TO, printed here for the same reason `cmd_plan`
  # prints it: a gate grant covers one digest and nothing else, so "which files
  # are in it" is the question a reader of a waiver actually has. The deposit
  # plan printed no digest at all until R9, which is how a deposit run over a
  # subject with nothing deposited came to bind HG1 to the COMMITTED encoding
  # without anyone being able to see it from `plan`.
  echo "the digest a gate on this run would bind to, over ${#GO_ENCODING_FILES[@]} file(s):"
  echo "  $(node "$LIB/digest.mjs" "${GO_ENCODING_FILES[@]}")"
  for s in "${GO_ENCODING_FILES[@]}"; do printf '  %s\n' "${s#"$GO_ROOT"/}"; done
  echo
  echo "declared for a deposit run, and therefore run: ${DEPOSIT_STAGES[*]}"
  echo "entry points that still exist and refuse, each with a named blocker:"
  for s in "${UNIMPLEMENTED_STAGES[@]}"; do printf '  %-14s %s\n' "$s" "$PHASES/$s.sh"; done
  echo
  echo "READ THIS BEFORE READING A DEPOSIT VERDICT. P1, P2, P3 and P4 do not fetch, search,"
  echo "encode or find forks: those need the network or a model, and this driver takes"
  echo "neither (ORCHESTRATOR.md §2.1, §6.4). They VALIDATE what an agent deposited, and"
  echo "report SKIPPED with a named reason when the deposit is not there. So COMPLETE here"
  echo "means every declared stage is accounted for — it does NOT mean a de novo run happened:"
  echo "a run with every deposit absent is COMPLETE over SKIPPED receipts. SPEC.md §6's"
  echo "G2 acceptance is the §8 diff oracle, etc/go/lib/denovo-diff.mjs, which p8-diff"
  echo "runs over the declared surface map — its receipt above says whether it did."
  echo "Run with L4_GO_REQUIRED=1 to make an absent deposit fatal."
}

cmd_plan() {
  local rc=0
  local stages
  stages=$(stages_for) || rc=$?
  [[ $rc -eq 0 ]] || exit $rc
  if [[ "$GO_S_ENCODING_ID" != "primary" ]]; then
    cmd_plan_deposit
    return 0
  fi
  echo "subject $SUBJECT, encoding primary — declared stages, in order:"
  local s
  while read -r s; do
    printf '  %-14s gate=%-4s %s\n' "$s" "$(gate_for "$s")" "$PHASES/$s.sh"
  done <<<"$stages"
  echo
  # WHAT A GATE WOULD BIND TO, printed rather than left to be inferred. A gate
  # grant covers one digest and nothing else, so "which files are in it" is the
  # question a reader of a waiver actually has — and it is the question that was
  # answered wrongly for the explainer's narrative deposit, which the gate was
  # supposed to cover and did not.
  echo "the digest a gate on this run would bind to, over ${#GO_ENCODING_FILES[@]} file(s):"
  echo "  $(node "$LIB/digest.mjs" "${GO_ENCODING_FILES[@]}")"
  for s in "${GO_ENCODING_FILES[@]}"; do printf '  %s\n' "${s#"$GO_ROOT"/}"; done
  # Say it, rather than leaving the reader to infer it from a run in which every
  # stage skipped. The digest above is real either way — digestSet records an
  # absent path as ABSENT — so depositing the first module MOVES it and re-opens
  # HG1, which is the property that makes registering a subject before encoding
  # it safe rather than merely possible.
  if [[ "${GO_S_ENCODING_STATE:-written}" == "unwritten" ]]; then
    echo
    echo "  NOTE: this sidecar declares encoding.state \"unwritten\" — the paths above"
    echo "  are where the encoding WILL live, and none of them is a file yet. Every"
    echo "  stage that reads a module will report SKIPPED naming the file to deposit."
    echo "  Writing the encoding is agent work; flip the state to \"written\" when it"
    echo "  lands (subject.mjs refuses the stale declaration, so you cannot forget)."
  fi
  echo
  echo "entry points that exist and refuse, each with a named blocker:"
  for s in "${UNIMPLEMENTED_STAGES[@]}"; do printf '  %-14s %s\n' "$s" "$PHASES/$s.sh"; done
  echo
  echo "the run rule: this run is COMPLETE when every declared stage has a"
  echo "receipt, no receipt is BROKEN, every non-PASS receipt carries a reason that"
  echo "appears in the report, and every gate is satisfied or explicitly waived."
  echo "That is completeness of accounting, not greenness — SPEC.md §6 permits a"
  echo "non-executable DMN at G1 provided the report says so in Blocking terms."
}

# latest_run [SUBJECT] -> the newest run dir, optionally of one subject only.
#
# `status` and `verify` are subject-independent — they read a journal and check
# it — so with no --subject the newest run of ANY subject is the right answer.
# But once a second subject exists, `go.sh status --subject regcf` is a
# question with an obvious meaning, and answering it with sg-succession's
# newest run because the flag went unread is a silent wrong answer: the report
# would be about a different body of law and would look entirely normal.
latest_run() {
  if [[ -n "${1:-}" ]]; then
    node "$LIB/gc-subjects.mjs" "$RUNDIR_BASE" "$1" | sort | tail -1
  else
    ls -1d "$RUNDIR_BASE"/*/ 2>/dev/null | sort | tail -1 | sed 's:/$::'
  fi
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
    l=$(latest_run "$SUBJECT" || true)
    [[ -n "$l" ]] || {
      if [[ -n "$SUBJECT" ]]; then
        echo "go.sh: no runs of subject '$SUBJECT' under $RUNDIR_BASE" >&2
      else
        echo "go.sh: no runs under $RUNDIR_BASE" >&2
      fi
      exit 2
    }
    echo "$l"
  fi
}

# `run="$(resolve_run)" || exit` and not `node ... "$(resolve_run)"`:
# resolve_run refuses by calling `exit 2`, and inside a command substitution
# that exits the SUBSHELL. Inlined, the refusal printed and then the driver
# carried on and handed verify-run.mjs an empty argument, so the user saw the
# right diagnosis followed by a `usage:` line about a different script, under
# verify-run.mjs's exit code rather than 2. Assigning first makes the
# substitution's status visible, which is the only place the refusal survives.
cmd_status() {
  local run
  run="$(resolve_run)" || exit $?
  node "$LIB/verify-run.mjs" "$run"
}

# R13's fold: the account of a SUBJECT, across every run whose evidence survives.
# Not a union — a receipt binds to the digest it ran over, so each phase resolves
# to one state. STALE here is R4's (a newer prerequisite exists, named), never
# "the digest moved": a digest cannot say WHICH member, and can miss a
# prerequisite that moved without moving it.
cmd_subject_report() {
  local l4_path l4_sha stdlib_dir stdlib_sha
  [[ -n "$SUBJECT" ]] || die_usage "subject-report needs --subject <id>"
  go_provision_toolchain "$GO_ROOT"
  l4_path="$(command -v "${L4:-l4}" || echo "${L4:-l4}")"
  if [[ -x "$l4_path" ]]; then
    l4_sha="$(node "$LIB/digest.mjs" "$l4_path")"
  else
    l4_sha="unset"
  fi
  stdlib_dir="${JL4_LIBRARY_PATH:-$GO_ROOT/jl4-core/libraries}"
  stdlib_sha="$(node "$LIB/stdlib-digest.mjs" "$stdlib_dir")"
  local extra=()
  [[ "$WANT_JSON" == "1" ]] && extra+=(--json)
  # THE DECLARABLE UNIVERSE, not merely the declared one. A phase that has never
  # been declared for this subject is exactly the phase R13 must still name: the
  # union of surviving `declared_stages` omits it, and omission reads as
  # "accounted for elsewhere" when nothing had accounted for it anywhere. That
  # misreading is R12's failure. The driver owns the stage sets, so the driver
  # passes them; the library never guesses at a universe it cannot see.
  local declarable
  declarable="$(printf '%s\n' "${PRIMARY_STAGES[@]}" "${DEPOSIT_STAGES[@]}" | sort -u | tr '\n' ' ')"
  node "$LIB/subject-report.mjs" "$RUNDIR_BASE" --subject "$SUBJECT" \
    --declarable "$declarable" \
    --param "l4-binary=$l4_sha" \
    --param "l4-stdlib=$stdlib_sha" \
    --param "fixed_now=$FIXED_NOW" \
    "${extra[@]}"
}

# R4's query: what did this run READ, and does a newer version of any of it
# exist? A QUERY and not a phase (§4.2) — it consumes no declared input set,
# earns no receipt and nothing depends on its answer.
#
# The toolchain params are passed IN rather than recomputed inside the library,
# because the driver is what owns those facts: a param nobody supplies is
# reported UNEVALUATED, never assumed unchanged. Assuming it unchanged is
# exactly the §3.7a bug — the binary and the stdlib moved and no digest noticed.
cmd_readset() {
  local run l4_path l4_sha stdlib_dir stdlib_sha
  run="$(resolve_run)" || exit $?
  # THE QUERY MUST RESOLVE A PREREQUISITE EXACTLY AS A RUN WOULD, or "stale"
  # degrades into "I asked a different question". Measured: a `command -v l4`
  # fallback reported every stage of a green run STALE on `l4-binary`, because
  # the driver had discovered a binary under a SIBLING WORKTREE's dist-newstyle
  # while the PATH held an unrelated `~/.local/bin/l4`. Nothing had moved; two
  # resolutions had merely disagreed, and a freshness tool that cries wolf on a
  # clean tree is a tool nobody reads twice. So: the same discovery the run uses.
  go_provision_toolchain "$GO_ROOT"
  l4_path="$(command -v "${L4:-l4}" || echo "${L4:-l4}")"
  if [[ -x "$l4_path" ]]; then
    l4_sha="$(node "$LIB/digest.mjs" "$l4_path")"
  else
    l4_sha="unset"
  fi
  stdlib_dir="${JL4_LIBRARY_PATH:-$GO_ROOT/jl4-core/libraries}"
  stdlib_sha="$(node "$LIB/stdlib-digest.mjs" "$stdlib_dir")"
  local extra=()
  [[ -n "$STAGE_ONLY" ]] && extra+=(--stage "$STAGE_ONLY")
  [[ "$WANT_JSON" == "1" ]] && extra+=(--json)
  node "$LIB/readset-cli.mjs" "$run" \
    --param "l4-binary=$l4_sha" \
    --param "l4-stdlib=$stdlib_sha" \
    --param "fixed_now=$FIXED_NOW" \
    "${extra[@]}"
}

cmd_verify() {
  local extra=() run
  [[ $WANT_GATES -eq 1 ]] && extra+=(--gates)
  run="$(resolve_run)" || exit $?
  node "$LIB/verify-run.mjs" "$run" "${extra[@]}"
}

# --- new-subject ------------------------------------------------------------
#
# Registering a body of law used to require having already encoded it: `main`
# was mandatory AND had to exist, so there was no way to say "this subject is
# real, its encoding is not written yet". That is R12 in
# specs/todo/PIPELINE-ARTIFACT-MODEL-SPEC.md — the first encoding has no home —
# and it is why this command could not exist before encoding.state did.
#
# WHAT IS AND IS NOT SCAFFOLDED. subject.json is configuration: every value in
# it is a decision the caller makes, so it is written from the arguments and
# the caller is required to supply the ones that cannot be guessed. pins.json
# and known-defects.json are MEASUREMENT RECORDS — pins.json records a CLI
# surface probed against a real binary, known-defects.json records defects
# observed on a stated date. A scaffolder that emitted plausible contents for
# either would be manufacturing exactly the evidence this pipeline exists to
# demand, so both are emitted empty and marked unmeasured, and the stages that
# need them refuse loudly and name the recipe. An empty measurement file claims
# nothing, which is the only honest thing it can say.
cmd_new_subject() {
  [[ -n "$NEW_ID" ]] || die_usage "new-subject: an id is required — etc/go/go.sh new-subject <id> --citation ... --source-url ..."
  [[ "$NEW_ID" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die_usage "new-subject: id '$NEW_ID' must match ^[a-z0-9][a-z0-9-]*$ (subject.mjs refuses anything else, and the id is a directory name)"
  [[ -n "$NEW_CITATION" ]] || die_usage "new-subject: --citation is required; it is what the report cites this subject AS, and there is no defensible default"
  [[ -n "$NEW_SOURCE_URL" ]] || die_usage "new-subject: --source-url is required; it is the provenance of every later claim about this body of law"

  local dir="$GO_ROOT/etc/go/subjects/$NEW_ID"
  if [[ -d "$dir" && $NEW_FORCE -eq 0 ]]; then
    echo "go.sh: etc/go/subjects/$NEW_ID already exists. Refusing to overwrite a sidecar:" >&2
    echo "  pins.json and known-defects.json are measurement records, and re-scaffolding" >&2
    echo "  would replace measured content with empty stubs. Pass --force if that is what" >&2
    echo "  you want, or edit the files in place." >&2
    exit 2
  fi

  # Where the encoding WILL live. Defaults to the house layout; the file is not
  # created, because creating it would make encoding.state "unwritten" false on
  # the very next line.
  local enc="${NEW_ENCODING:-jl4/examples/legal/$NEW_ID/$NEW_ID.l4}"
  if [[ -e "$GO_ROOT/$enc" ]]; then
    echo "go.sh: $enc already exists, so this subject's encoding is not unwritten." >&2
    echo "  new-subject scaffolds the UNWRITTEN case. Write the sidecar by hand with" >&2
    echo "  encoding.state \"written\" (the default), using etc/go/subjects/regcf as the" >&2
    echo "  worked example." >&2
    exit 2
  fi

  local name="${NEW_DISPLAY_NAME:-$NEW_ID}"
  mkdir -p "$dir"

  NEW_ID="$NEW_ID" NEW_NAME="$name" NEW_CITATION="$NEW_CITATION" \
    NEW_SOURCE_URL="$NEW_SOURCE_URL" NEW_ENC="$enc" NEW_DIR="$dir" \
    node "$LIB/new-subject.mjs" || exit $?

  echo
  echo "created etc/go/subjects/$NEW_ID/ — subject.json, pins.json, known-defects.json, NOTES.md"
  echo
  echo "it is already a subject:"
  echo "  etc/go/go.sh plan --subject $NEW_ID"
  echo
  echo "what is NOT done, in the order it has to happen:"
  echo "  1. write the encoding at $enc (agent work — the L4 encoding skill)"
  echo "  2. flip encoding.state to \"written\" in etc/go/subjects/$NEW_ID/subject.json"
  echo "     (subject.mjs refuses the stale declaration once the file exists, so this"
  echo "      cannot be forgotten silently)"
  echo "  3. measure pins.json against a real l4 — see etc/go/subjects/regcf/pins.json"
  echo "     for the shape and etc/go/lib/discover.mjs for how the values are probed"
  echo "  4. declare the projection legs this subject supports, in subject.json's"
  echo "     'legs' — the driver declares a stage IFF the leg is there, so an omitted"
  echo "     leg is an honest silence rather than a failing stage"
}

# --- store ------------------------------------------------------------------
# The artifact store and the blessing ledger, which outlive run directories.
# `gc` above sweeps RUN DIRECTORIES; this sweeps the store, and the two are
# deliberately separate verbs because they collect different things under
# different rules — the run store is a cache, the object store is evidence.
cmd_store() {
  node "$LIB/store-cli.mjs" "${STORE_ARGS[@]}"
}

cmd_gc() {
  # Retention: keep the latest --keep runs OF EACH SUBJECT, AND any run holding
  # a granted gate verdict — a signature is expensive to obtain and must not be
  # collected.
  #
  # "of each subject" is load-bearing and was, until 2026-08-20, only a comment:
  # the code took `sort | tail -$KEEP` over the whole store. That is harmless
  # while one subject exists and wrong the moment a second does — a burst of
  # runs on the newer subject buries every run of the older one inside the
  # window that gets deleted, and cross-run replay (SPEC §R7) reuses receipts
  # from exactly those older runs. Retention would silently delete the thing
  # that makes a toolchain tweak cheap to re-measure.
  #
  # MEASURED 2026-08-20, and stated carefully because the first draft of this
  # comment was not: the store holds 92 run directories, of which 16 still hold
  # a journal, ALL of them sg-succession — every regcf journal is already gone,
  # reaped by $TMPDIR's own cleaner rather than by gc (files here survive about
  # two to five days). So the concrete claim this comment first made, that one
  # `gc` "would have deleted every regcf run in the store", is FALSE: there are
  # no regcf runs in the store to delete. What is true is the general rule and
  # what the fixture in selftest.mjs demonstrates directly — a subject buried
  # under a burst of runs on another loses its entire replay corpus — plus the
  # measured consequence here, that `gc --keep 5` under the old rule would have
  # kept 5 directories and removed 87, including all 76 whose journals predate
  # the subject field.
  #
  # A run whose journal names no subject (the pre-subject runs of 2026-08-09,
  # whose run_begin predates the field) is retained under the sentinel key
  # "(unattributed)" rather than pooled with a real subject: it cannot be shown
  # to be redundant with any subject's latest, so it is not collected as if it
  # were.
  # KEEP-LIST MEMBERSHIP IS BY RUN ID, NOT BY PATH STRING.
  #
  # It was by path string, and that DELETED EVERY RUN DIRECTORY, gate-holding
  # ones included, while printing "kept N". macOS sets TMPDIR with a trailing
  # slash, so `${TMPDIR:-/tmp}/l4-go` is `/var/.../T//l4-go` — a double slash.
  # `ls -1d … | sed` preserves it; `gc-subjects.mjs` runs the path through
  # node's resolver, which collapses it. The two spellings name the same
  # directory and compare unequal, so nothing ever matched the keep-list. It
  # fired by DEFAULT on macOS, and it is what destroyed three runs during the
  # review that found it.
  #
  # A run id is the directory's basename, is unique within the base, and is
  # immune to every path-form difference there is. Comparing those cannot
  # reproduce this class of bug even if a third spelling appears tomorrow.
  local keep_ids=()
  local d
  for d in $(ls -1d "$RUNDIR_BASE"/*/ 2>/dev/null | sed 's:/$::'); do
    if grep -q '"kind":"gate"' "$d/journal.ndjson" 2>/dev/null && grep -q '"state":"satisfied"' "$d/journal.ndjson" 2>/dev/null; then
      keep_ids+=("$(basename "$d")")
    fi
  done
  local subj
  for subj in $(node "$LIB/gc-subjects.mjs" "$RUNDIR_BASE"); do
    for d in $(node "$LIB/gc-subjects.mjs" "$RUNDIR_BASE" "$subj" | sort | tail -"$KEEP"); do keep_ids+=("$(basename "$d")"); done
  done
  local removed=0
  for d in $(ls -1d "$RUNDIR_BASE"/*/ 2>/dev/null | sed 's:/$::'); do
    local k
    local keep=0
    local id
    id="$(basename "$d")"
    for k in "${keep_ids[@]}"; do [[ "$k" == "$id" ]] && keep=1; done
    if [[ $keep -eq 0 ]]; then
      rm -rf "$d"
      removed=$((removed + 1))
      echo "gc: removed $d"
    fi
  done
  echo "gc: kept ${#keep_ids[@]} run dir(s) (latest $KEEP per subject, plus every run holding a granted gate); removed $removed"
}

# The front-door forecast, runnable on its own. Discovery first (so the
# forecast is about the environment a run would actually get), then the
# doctor's per-stage verdict. Runs no stage, writes no run dir.
cmd_doctor() {
  local stages rc=0
  stages=$(stages_for) || rc=$?
  [[ $rc -eq 0 ]] || exit $rc
  go_provision_toolchain "$GO_ROOT"
  export GO_ROOT
  export JL4_LIBRARY_PATH="${JL4_LIBRARY_PATH:-$GO_ROOT/jl4-core/libraries}"
  node "$LIB/doctor.mjs" --encoding "$GO_S_ENCODING_ID" --stages "$(echo "$stages" | tr '\n' ' ')"
}

cmd_run() {
  local stages rc=0
  stages=$(stages_for) || rc=$?
  [[ $rc -eq 0 ]] || exit $rc

  # --- provision, then the one hard prerequisite: a prebuilt l4 --------------
  # Discovery fills L4/JL4_LSP_CMD from dist-newstyle when unset; explicit env
  # always wins, and each line below says which happened, because "discovered"
  # and "explicit" are different claims and the report may need to cite one.
  go_provision_toolchain "$GO_ROOT"
  if [[ -z "${L4:-}" ]]; then
    cat >&2 <<EOF
go.sh: L4 is unset, and no built l4 was discovered under dist-newstyle in this
worktree or its siblings.

This orchestrator never runs cabal — the build lock is a shared resource and
concurrent invocations in one worktree corrupt each other (CLAUDE.md §2.1).
Build one in a DIFFERENT worktree, or point L4 at a prebuilt binary, the same
escape hatch as JL4_LSP_CMD= and DMNMD=:

  export L4=/path/to/dist-newstyle/build/<arch>/ghc-9.10.3/jl4-0.1/x/l4/build/l4/l4
EOF
    exit 2
  fi
  if [[ ! -x "$L4" ]] && ! command -v "$L4" >/dev/null 2>&1; then
    echo "go.sh: L4=$L4 is not executable and not on PATH" >&2
    exit 2
  fi
  echo "go: l4      $L4  [${GO_L4_PROVENANCE:-explicit}]"
  [[ -n "${JL4_LSP_CMD:-}" ]] && echo "go: jl4-lsp $JL4_LSP_CMD  [${GO_LSP_PROVENANCE:-explicit}]"

  export JL4_LIBRARY_PATH="${JL4_LIBRARY_PATH:-$GO_ROOT/jl4-core/libraries}"
  export GO_ROOT

  # --- the door forecast -----------------------------------------------------
  # The same doctor `go.sh doctor` runs, in brief form: name every declared
  # stage that will not run whole BEFORE ten minutes are spent learning it one
  # receipt at a time. Under L4_GO_REQUIRED=1 a forecast skip refuses HERE —
  # the same stages would exit 5 mid-run, after the earlier stages' work.
  #
  # The forecast covers the stages THIS invocation will dispatch: an --only or
  # --through run must not be refused over a doomed stage it was never going
  # to reach.
  local door_stages="$stages"
  if [[ -n "$ONLY" ]]; then
    # Intersected with the declared set: --only over an undeclared stage
    # dispatches nothing, and a forecast must not refuse a run that was
    # going to run nothing.
    door_stages="$(printf '%s\n' "$stages" | awk -v o="$ONLY" '$0 == o')"
  elif [[ -n "$THROUGH" ]]; then
    # awk, not sed's '1,/re/p': that range cannot close on line 1, so
    # --through <first-stage> would have forecast every stage.
    door_stages="$(printf '%s\n' "$stages" | awk -v t="$THROUGH" '{ print } $0 == t { exit }')"
  fi
  local doctor_rc=0
  set +e
  node "$LIB/doctor.mjs" --encoding "$GO_S_ENCODING_ID" --stages "$(echo "$door_stages" | tr '\n' ' ')" --brief
  doctor_rc=$?
  set -e
  if [[ "${L4_GO_REQUIRED:-0}" == "1" && $doctor_rc -ge 1 ]]; then
    echo "go: L4_GO_REQUIRED=1 and the forecast above names stages that cannot run whole; refusing at the door." >&2
    exit 5
  fi

  # --- run id + run dir ------------------------------------------------------
  # The corpus this run is about, as one digest. It names the run, and the gate
  # rows bind to it so a waiver granted over one corpus does not silently cover
  # a later edit.
  local corpus_digest corpus_sha8
  corpus_digest=$(node "$LIB/digest.mjs" "${GO_ENCODING_FILES[@]}")
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

  # THE STANDARD LIBRARY IS THE SECOND UNDECLARED INPUT TO EVERY STAGE.
  #
  # The paragraph above folds `l4_sha` into every digest because "the `l4`
  # binary is an input to every stage and is declared by none: no phase script
  # can see the path the driver was handed." JL4_LIBRARY_PATH is an input to
  # every stage on identical terms -- every module of every subject opens with
  # IMPORT prelude and IMPORT daydate -- declared by none, invisible to every
  # phase script, and, unlike the binary, settable by the caller.
  #
  # MEASURED before this was folded: copy jl4-core/libraries, change `__GEQ__`
  # on DATE from `AT LEAST` to `GREATER THAN` (one word), point the env var at
  # the copy. sg-paa.l4 still reports 79 assertions and 0 failures, byte for
  # byte identical to the baseline, while a date-boundary EVAL goes TRUE ->
  # FALSE. Every oracle in the pipeline stayed green and the answer moved.
  #
  # Content and not path, so relocating an identical library does not
  # invalidate a replay; the path is exported separately for the report.
  local stdlib_dir stdlib_sha
  stdlib_dir="${JL4_LIBRARY_PATH:-$GO_ROOT/jl4-core/libraries}"
  stdlib_sha="$(node "$LIB/stdlib-digest.mjs" "$stdlib_dir")"
  export GO_STDLIB_DIR="$stdlib_dir" GO_STDLIB_SHA="$stdlib_sha"

  export GO_ROOT
  export GO_RUN="$RUN" GO_RUNID="$RUN_ID" GO_SUBJECT="$SUBJECT"
  export GO_FIXED_NOW="$FIXED_NOW"

  # run_begin is written once per run dir, not once per invocation: a resumed
  # run is the same run.
  if [[ ! -f "$RUN/journal.ndjson" ]]; then
    node "$LIB/receipt.mjs" run-begin --run "$RUN" \
      --run-id "$RUN_ID" --encoding "$GO_S_ENCODING_ID" --subject "$SUBJECT" \
      --repo-head "$head" --tree-state "$tree_state" --fixed-now "$FIXED_NOW" \
      --l4-binary "$L4" --declared "$(echo "$stages" | tr '\n' ',')" \
      --gated-stages "{\"HG1\":[$(for x in $gated_by_HG1; do printf '"%s",' "$x"; done | sed 's/,$//')],\"HG2\":[$(for x in $gated_by_HG2; do printf '"%s",' "$x"; done | sed 's/,$//')]}"
  fi

  # THE CORPUS, ITEMISED — once per invocation, fresh runs and resumes alike.
  #
  # `corpus_digest` is a SET hash: it can say "this changed" and never "which of
  # these did the expert review?". That second question is R11's, and answering
  # it from a digest means re-resolving the subject and re-reading the tree,
  # both of which need the run being asked about to still exist. Written to a
  # file rather than a journal row because it is the input to `covers[]`, and a
  # blessing has to carry its members so it can outlive the run that granted it.
  #
  # Once per invocation is exactly right: corpus_digest is already a
  # per-invocation constant that every gate check in the loop reuses.
  node -e '
    import("'"$LIB"'/ledger.mjs").then((m) => {
      process.stdout.write(JSON.stringify(m.digestMembers(process.argv.slice(1)), null, 2));
    });
  ' "${GO_ENCODING_FILES[@]}" > "$RUN/.corpus-members.json"

  echo "go: run $RUN_ID  (subject $SUBJECT, encoding $GO_S_ENCODING_ID)"
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
      --subject "$SUBJECT" --run-id "$RUN_ID" --covers-from "$RUN/.corpus-members.json" \
      --corpus-digest "$corpus_digest" --reason "$greason"
    echo "go: gate $gname WAIVED — $greason"
    if [[ "$GO_S_ENCODING_ID" != "primary" ]]; then
      echo "go:   the waiver covers the deposit set $corpus_digest and nothing else; deposit or edit one and $gname re-opens."
    else
      echo "go:   the waiver covers corpus $corpus_digest and nothing else; edit a corpus file, or any file of the subject's explainer narrative deposit, and $gname re-opens."
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
            --subject "$SUBJECT" --run-id "$RUN_ID" --covers-from "$RUN/.corpus-members.json" \
            --namespace "$([[ $gate == HG1 ]] && echo l4-go-gate || echo l4-go-gate-hg2)" \
            --corpus-digest "$corpus_digest" \
            --signer "$(cat "$RUN/$gate.signer" 2>/dev/null || echo "")" \
            --payload-digest "$(node "$LIB/digest.mjs" "$RUN/$gate.payload.txt" 2>/dev/null || echo "")" \
            --signature-file "$RUN/$gate.payload.txt.sig"
        else
          node "$LIB/receipt.mjs" gate --run "$RUN" --gate "$gate" --state refused \
            --subject "$SUBJECT" --run-id "$RUN_ID" --covers-from "$RUN/.corpus-members.json" \
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
    #
    # R4: the SAME pass also itemises the set into a read-set, written beside
    # the run. One `--members-out` flag rather than a second invocation, because
    # the members must prove the digest and two passes over a tree that is being
    # edited would produce a read-set that does not — a race indistinguishable,
    # later, from a doctored row.
    local inputs digest members
    inputs=$(GO_STAGE="$s" bash "$script" --inputs 2>/dev/null || true)
    members="$RUN/.read-set-$s.json"
    if [[ -n "$inputs" ]]; then
      digest=$(printf '%s\ntext:l4-binary=%s\ntext:l4-stdlib=%s\n' "$inputs" "$l4_sha" "$stdlib_sha" | node "$LIB/digest.mjs" --stdin --members-out "$members")
    else
      digest=""
      rm -f "$members"
    fi
    export GO_INPUTS_DIGEST="$digest"
    # R4: the itemised members, for go_receipt to record on the stage_end row.
    # `rs_arg` is the same fact as an argv fragment, for the two REPLAY exits
    # below — a replayed stage runs no phase script, so nothing would call
    # go_receipt for it, yet its receipt must still say what it read. R8: a run
    # directory is answerable by someone holding only that directory.
    export GO_READ_SET=""
    local rs_arg=()
    if [[ -n "$digest" && -f "$members" ]]; then
      export GO_READ_SET="$members"
      rs_arg=(--read-set "$members")
    fi

    # Resumability, in two widths.
    #
    # WITHIN this run, a completed stage with an unchanged inputs digest is
    # replayed — that is what makes a killed terminal or a usage limit cost
    # nothing, and it is unchanged.
    #
    # ACROSS runs of the SAME SUBJECT, the same rule applies to a stage whose
    # result is determined by its declared inputs. Those inputs already name the
    # stage's own script, the checkers it calls, and (folded in above) the sha256
    # of the `l4` binary — so editing any part of the toolchain moves the digest
    # and the stage re-executes, while everything the edit did not touch is
    # borrowed. That is the whole point: change one exporter, re-run, and only
    # that leg runs again.
    #
    # `lib/ledger.mjs` owns which stages may NOT cross a run boundary
    # (CROSS_RUN_INELIGIBLE) and why. The within-run lookup is tried FIRST and
    # separately, because a receipt from this run needs no artifact copy.
    local prior="" prior_run=""
    if [[ -n "$digest" ]]; then
      prior=$(node -e '
        import("'"$LIB"'/ledger.mjs").then(m => {
          const r = m.findReplayable(process.argv[1], process.argv[2], process.argv[3]);
          if (r) process.stdout.write(JSON.stringify({hash: r.hash, status: r.status, reason: r.reason ?? "", blocker: r.blocker ?? "", label: r.label ?? "", metrics: r.metrics ?? {}, notes: r.notes ?? []}));
        });
      ' "$RUN/journal.ndjson" "$s" "$digest")
      if [[ -z "$prior" ]]; then
        prior=$(node -e '
          import("'"$LIB"'/ledger.mjs").then(m => {
            const f = m.findReplayableAcrossRuns(process.argv[1], process.argv[2], process.argv[3], process.argv[4], process.argv[5]);
            if (!f) return;
            const r = f.record;
            process.stdout.write(JSON.stringify({hash: r.hash, status: r.status, reason: r.reason ?? "", blocker: r.blocker ?? "", label: r.label ?? "", metrics: r.metrics ?? {}, notes: r.notes ?? [], artifacts: r.artifacts ?? [], from_run: f.runId, from_dir: f.runDir}));
          });
        ' "$RUNDIR_BASE" "$RUN" "$SUBJECT" "$s" "$digest")
        if [[ -n "$prior" ]]; then
          # THE DONOR'S ARTIFACTS ARE CHECKED BEFORE ANY OF THEM IS COPIED.
          #
          # Within-run replay copies artifact records VERBATIM, and receipt.mjs
          # says why: "Re-hashing would launder a file that changed after the
          # original receipt was written." The cross-run path cannot copy the
          # records -- `--artifacts-from` resolves inside THIS journal, and a
          # borrowed path would dangle once gc pruned the donor -- so it copies
          # the FILES and records them with `--artifact`, which re-hashes. That
          # is the laundering the comment forbids: a donor artifact tampered
          # with after its receipt was written would report CHANGED under
          # `verify` in its own run and `matches` here.
          #
          # A mismatch REFUSES the borrow rather than repairing it. If a donor
          # artifact no longer matches its own receipt, that receipt is not
          # evidence of anything, and the honest response is to execute the
          # stage -- which is what clearing $prior makes happen.
          if ! printf '%s' "$prior" | node "$LIB/donor-check.mjs"; then
            echo "go: $s will NOT borrow from an earlier run (see above); executing instead" >&2
            prior=""
          else
            prior_run=$(printf '%s' "$prior" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(String(JSON.parse(s).from_run||"")))')
          fi
        fi
      fi
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
      # hash-chained journal. Demoting a replayed PASS would make the run
      # verdict change when the same run is repeated, which is exactly
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
      if [[ -n "$prior_run" ]]; then
        # CROSS-RUN replay. `--artifacts-from` resolves its hash inside THIS
        # journal (lib/receipt.mjs), so it cannot name a receipt from another
        # run — and pointing at another run's files would be worse anyway: `gc`
        # prunes run directories, and `go.sh verify` re-hashes every artifact a
        # receipt names, so a borrowed path would dangle and verification of a
        # perfectly good run would fail.
        #
        # So the artifacts are COPIED in, and the receipt records them normally.
        # The invariant that buys is the one that makes `verify` worth anything:
        # a run directory is self-contained and checkable on its own, by someone
        # who has only that directory.
        # THE DONOR'S ARTIFACT RECORDS, AS DATA. receipt.mjs fetches the bytes
        # from the store by `cas` and records the donor's hash VERBATIM.
        #
        # What this replaces: a `cp` loop that flattened every artifact to its
        # basename (so two artifacts from different subdirectories overwrote
        # each other), fell back to recording ANOTHER RUN'S absolute path as
        # this run's artifact, and then passed `--artifact`, which re-hashes the
        # copy — precisely the laundering receipt.mjs's own comment forbids.
        # Four defects, all of them gone with the loop.
        local from_dir
        from_dir=$(printf '%s' "$prior" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(String(JSON.parse(s).from_dir||"")))')
        printf '%s' "$prior" \
          | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.stringify(JSON.parse(s).artifacts||[])))' \
          > "$RUN/.replay-artifacts.json"
        node "$LIB/receipt.mjs" stage-end --run "$RUN" --stage "$s" --status "$pstatus" \
          --inputs-digest "$digest" --replayed-from "$phash" --replayed-from-run "$prior_run" \
          --subject "$SUBJECT" --run-id "$RUN_ID" --donor-dir "$from_dir" \
          --artifacts-json "$RUN/.replay-artifacts.json" "${rs_arg[@]}" "${extra[@]}"
        echo "go: $s replayed from run $prior_run (inputs unchanged)"
      else
        node "$LIB/receipt.mjs" stage-end --run "$RUN" --stage "$s" --status "$pstatus" \
          --inputs-digest "$digest" --replayed-from "$phash" --artifacts-from "$phash" "${rs_arg[@]}" "${extra[@]}"
        echo "go: $s replayed (inputs unchanged)"
      fi
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

  # --- the run verdict, recomputed from the journal --------------------------
  # verify-run.mjs answers three questions — does the chain verify, do the
  # artifacts every receipt names still hash as recorded, and what is the
  # run verdict — and encodes the first two in `chain_ok`/`findings` and
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
  [[ $overall -eq 1 && $vexit -eq 0 ]] && vexit=0 # a leg finding is accounted for, not a run failure

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
    # The explainer's final render, for the same reason and with the same
    # status — but DECLARED-STAGES-ONLY. p9-explain renders narrative prose
    # about a body of law, and a run that does not declare the stage
    # gets no explainer file. The guard is load-bearing, measured 2026-08-09
    # before it existed: a deposit run wrote the primary narrative — 127 KB about the
    # COMMITTED corpus, drift banners included — into the run dir with no
    # receipt, no journal row, and no gate covering it (a deposit run's HG1 digest
    # deliberately excludes the narrative deposit), then announced its path.
    # That is the relabelling ORCHESTRATOR.md §5.2 exists to prevent. (An
    # earlier comment here PREDICTED this guard's behaviour while the render
    # ran unconditionally; the sidecar's declared explainer dir made the
    # prediction false.) In a declaring run the render may still
    # legitimately leave no file — a subject with no declared narrative — so
    # a failure stays silent rather than inventing one.
    if [[ $'\n'"$stages"$'\n' == *$'\n'"p9-explain"$'\n'* ]]; then
      node "$GO_ROOT/etc/go/report/render-explainer.mjs" "$RUN" --format md,html >/dev/null 2>&1 || true
    fi
  fi

  echo
  echo "go: VERDICT: $verdict  (subject $SUBJECT, encoding $GO_S_ENCODING_ID)"
  if [[ "$GO_S_ENCODING_ID" != "primary" ]]; then
    echo "go:   this verdict is over the DECLARED stages. It says the deposits present are"
    echo "go:   well formed and names the ones that are not there. It does not, by itself,"
    echo "go:   say a de novo run happened: a run with every deposit absent is COMPLETE over"
    echo "go:   SKIPPED receipts. SPEC.md §6's G2 acceptance is the §8 diff oracle"
    echo "go:   (node etc/go/lib/denovo-diff.mjs), which the p8-diff stage runs when a"
    echo "go:   surface map is deposited — read its receipt, not the verdict, for that."
  fi
  echo "go: journal  $RUN/journal.ndjson"
  [[ -f "$RUN/report.md" ]] && echo "go: report   $RUN/report.md"
  # The explainer is announced here and NOWHERE ELSE. report.md deliberately
  # does not link to it: the explainer can legitimately not exist for a run, and
  # a report linking to a document that was never produced would be making a
  # claim about the run that the journal does not support.
  [[ -f "$RUN/explainer.html" ]] && echo "go: explainer $RUN/explainer.html  (and explainer.md)"
  exit "$vexit"
}

case "$CMD" in
  run) cmd_run ;;
  doctor) cmd_doctor ;;
  plan) cmd_plan ;;
  status) cmd_status ;;
  verify) cmd_verify ;;
  gc) cmd_gc ;;
  new-subject) cmd_new_subject ;;
  readset) cmd_readset ;;
  subject-report) cmd_subject_report ;;
  store) cmd_store ;;
  help | -h | --help) usage ;;
  *) die_usage "unknown command '$CMD'" ;;
esac

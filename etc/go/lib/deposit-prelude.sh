#!/usr/bin/env bash
# Sourced by the de novo (G2) stages AFTER lib/phase-prelude.sh. Never executed.
#
# THE DEPOSIT CONTRACT, in one file so the four stages cannot drift apart.
#
# A G2 stage does not produce its own deliverable. Fetching a statute (P1),
# searching for what has happened to it (P2), encoding it (P3) and finding its
# ambiguities (P4) are agent acts: they need the network, or a model, or both,
# and this orchestrator takes neither (ORCHESTRATOR.md §2.1, §6.4). What the
# stage owns is the other half of the same interface — given a DEPOSIT, say
# whether it is well formed, and say it with an exit code.
#
# So each stage has exactly three outcomes, and they are decided here:
#
#   no path declared   the subject's sidecar has no denovo.<key>. SKIPPED,
#                      naming the key and the file to add it to.
#   declared, absent   the agent has not produced it yet. SKIPPED — a missing
#                      PREREQUISITE, not a defect. `L4_GO_REQUIRED=1` makes it
#                      fatal (exit 5), which is what CI wants: a G2 run that
#                      skipped every deposit is not a G2 run.
#   present            validated. PASS with oracle class `structural`, or
#                      DEGRADED naming every rule that fired.
#
# The distinction between the middle row and the last is the whole point of this
# change: before it, all three collapsed into one exit-3 refusal, so a subject
# that HAD deposited a bundle could not find that out from the pipeline.

if [[ -z "${GO_LIB:-}" ]]; then
  echo "deposit-prelude.sh: source lib/phase-prelude.sh first" >&2
  exit 2
fi

GO_REGISTER_VALIDATE="$GO_ROOT/etc/go/lib/register-validate.mjs"

# go_deposit_path SCHEMA -> the declared absolute path, or empty.
# SCHEMA is the register-validate schema name, which is also the deposit's own
# `kind`, so one string names the format, the validator and the file.
go_deposit_path() {
  case "$1" in
    source-bundle) printf '%s' "${GO_S_DENOVO_BUNDLE:-}" ;;
    external-modifications) printf '%s' "${GO_S_DENOVO_REGISTER:-}" ;;
    fork-register) printf '%s' "${GO_S_DENOVO_FORKS:-}" ;;
    *)
      echo "go_deposit_path: unknown schema '$1'" >&2
      return 2
      ;;
  esac
}

# go_deposit_key SCHEMA -> the subject.json key that declares it.
go_deposit_key() {
  case "$1" in
    source-bundle) printf 'denovo.bundle' ;;
    external-modifications) printf 'denovo.register' ;;
    fork-register) printf 'denovo.fork_register' ;;
  esac
}

# go_deposit_require SCHEMA — SKIP the stage unless the deposit is on disk.
# Returns 0 with the path in GO_DEPOSIT; never returns otherwise (go_skip exits).
go_deposit_require() {
  local schema="$1" path key
  path="$(go_deposit_path "$schema")"
  key="$(go_deposit_key "$schema")"
  if [[ -z "$path" ]]; then
    go_skip "the '$GO_S_ID' sidecar declares no $key, so this subject has nowhere to deposit a $schema. Add it to $GO_S_DIR/subject.json; the path's existence is optional, because producing the file is agent work owned by the skill's G2 section."
  fi
  if [[ ! -f "$path" ]]; then
    go_skip "the declared $key deposit has not been produced yet: $path is not a file. Producing it is agent work (fetch/search/encode with provenance), owned by the G2 section of .claude/skills/running-the-l4-pipeline/SKILL.md. Deposit it and re-run this stage; the receipt is the fact."
  fi
  GO_DEPOSIT="$path"
  return 0
}

# go_deposit_peers SCHEMA — echo the DECLARED-AND-PRESENT paths of the other two
# deposits, one per line. Cross-file rules run over exactly these; the validator
# reports every join whose peer is missing as `skip`, never as a pass, and the
# caller surfaces that count.
go_deposit_peers() {
  local self="$1" s p
  for s in source-bundle external-modifications fork-register; do
    [[ "$s" == "$self" ]] && continue
    p="$(go_deposit_path "$s")"
    [[ -n "$p" && -f "$p" ]] && printf '%s\n' "$p"
  done
  return 0
}

# go_deposit_shape FILE SCHEMA -> 0 ok, 1 with a one-line reason on stdout.
#
# Parses the file and checks its self-declared `kind` and `subject` BEFORE the
# validator sees it, for two reasons. register-validate exits 2 both for a
# deposit it cannot read and for a schema it cannot enforce — the first is a
# defect in the deposit and the second is a defect in the repo, and a stage that
# cannot tell them apart reports a DEGRADED corpus for a BROKEN harness. And the
# validator has no idea which subject it is looking at: nothing in the three
# schemas ties a register to a body of law, so a bna register deposited under
# the regcf sidecar validates perfectly and is about the wrong statute.
go_deposit_shape() {
  node -e '
    const fs = require("node:fs");
    const [file, schema, subject] = process.argv.slice(1);
    let doc;
    try {
      doc = JSON.parse(fs.readFileSync(file, "utf8"));
    } catch (e) {
      process.stdout.write(`is not valid JSON: ${e.message}`);
      process.exit(1);
    }
    if (doc === null || typeof doc !== "object" || Array.isArray(doc)) {
      process.stdout.write("is not a JSON object");
      process.exit(1);
    }
    if (doc.kind !== schema) {
      process.stdout.write(
        `declares kind ${JSON.stringify(doc.kind)}, but the stage deposits a ${JSON.stringify(schema)}`,
      );
      process.exit(1);
    }
    if (doc.subject !== subject) {
      process.stdout.write(
        `is about subject ${JSON.stringify(doc.subject)}, but this run is about ${JSON.stringify(subject)}`,
      );
      process.exit(1);
    }
    process.exit(0);
  ' "$1" "$2" "$GO_S_ID"
}

# go_deposit_rules_fired LOG -> the distinct rule names in `[rule]` position,
# comma-joined. A DEGRADED reason that says "3 findings, see the log" sends the
# reader to a file the journal names only by sha256; naming the rules puts the
# fact in the row.
go_deposit_rules_fired() {
  grep -oE '\[[a-z0-9][a-z0-9-]*\]$' "$1" 2>/dev/null | tr -d '[]' | sort -u | paste -sd, - || true
}

# go_deposit_findings_split LOG PRIMARY_PATH -> two lines:
#   1. the rules that fired against PRIMARY_PATH, comma-joined
#   2. the rules that fired against the PEERS, as "kind path: rule,rule; …"
#
# The validator validates every file on its command line in its own right and
# prints one section per file, so its EXIT CODE is a total: a perfectly good
# source bundle sitting next to a broken fork register makes it exit 1. Reading
# the total as a fact about the primary produced a measured falsehood —
# p1-ingest reporting "the source bundle does not satisfy its own format; rules
# that fired: at-least-one-live-reading, demoted-requires-a-demoted-reading, …",
# every one of which is a fork-register rule about a different file. The stage
# still goes DEGRADED (it cannot claim PASS over a validator run that exited 1),
# but its reason now names the file each rule was about.
go_deposit_findings_split() {
  node -e '
    const fs = require("node:fs");
    const [log, primary] = process.argv.slice(1);
    const lines = fs.readFileSync(log, "utf8").split("\n");
    let cur = null;
    const sections = new Map();
    for (const l of lines) {
      const head = /^register-validate: ([a-z-]+) (.*)$/.exec(l);
      if (head) {
        cur = `${head[1]}\t${head[2]}`;
        if (!sections.has(cur)) sections.set(cur, new Set());
        continue;
      }
      const fail = /\[([a-z0-9][a-z0-9-]*)\]\s*$/.exec(l);
      if (fail && /^\s+FAIL /.test(l) && cur) sections.get(cur).add(fail[1]);
    }
    const mine = [];
    const theirs = [];
    for (const [k, v] of sections) {
      if (v.size === 0) continue;
      const [kind, path] = k.split("\t");
      if (path === primary) mine.push(...v);
      else theirs.push(`${kind} ${path}: ${[...v].sort().join(",")}`);
    }
    process.stdout.write(`${[...new Set(mine)].sort().join(",")}\n${theirs.join("; ")}\n`);
  ' "$1" "$2"
}

# go_deposit_check SCHEMA — the whole mechanical half, in one call.
#
# SKIPs (and exits) when the deposit is undeclared or absent. Otherwise runs the
# validator over it with every declared-and-present peer and leaves the result
# in these variables for the caller to turn into a receipt:
#
#   GO_DEPOSIT         the deposit's path
#   GO_DEPOSIT_LOG     the validator transcript, to name as an artifact
#   GO_DEPOSIT_RC      0 clean · 1 a finding · 2 the harness (see below)
#   GO_DEPOSIT_SHAPE   empty, or a one-line reason the file is not this deposit
#   GO_DEPOSIT_PEERS   how many peers the joins could see (0, 1 or 2)
#   GO_DEPOSIT_RULES   how many x-rules ran
#   GO_DEPOSIT_SKIPS   how many joins could not run for want of a peer
#   GO_DEPOSIT_FIRED   every rule name that fired anywhere, comma-joined
#   GO_DEPOSIT_OWN     the rules that fired against THIS deposit, comma-joined
#   GO_DEPOSIT_PEER_FIRED  the rules that fired against the peers, per file
#
# Return value mirrors GO_DEPOSIT_RC. A shape error returns 1 with
# GO_DEPOSIT_SHAPE set and the validator never invoked.
#
# NOTE ON ERREXIT, because this cost a debugging round. Nothing in here may
# `set +e` / `set -e`: those are shell-global, not function-local, so a helper
# that restores errexit on its way out re-enables it in the CALLER — and the
# caller's next act is to read this function's non-zero return, which under
# errexit terminates the stage before it can write its receipt. Measured: a
# DEGRADED p4-forks exited 1 with an empty journal and no row at all. So every
# failure here is captured with `|| rc=$?`, and the stages call this function as
# `go_deposit_check X || RC=$?`, which is errexit-safe on both sides.
go_deposit_check() {
  local schema="$1" shape shape_rc=0 peers=()
  go_deposit_require "$schema"

  GO_DEPOSIT_LOG="$GO_OUT/$GO_STAGE-validate.txt"
  GO_DEPOSIT_SHAPE=""
  GO_DEPOSIT_PEERS=0
  GO_DEPOSIT_RULES=0
  GO_DEPOSIT_SKIPS=0
  GO_DEPOSIT_FIRED=""
  GO_DEPOSIT_OWN=""
  GO_DEPOSIT_PEER_FIRED=""

  shape="$(go_deposit_shape "$GO_DEPOSIT" "$schema")" || shape_rc=$?
  if [[ $shape_rc -ne 0 ]]; then
    GO_DEPOSIT_SHAPE="$shape"
    printf '%s\n' "$GO_DEPOSIT $shape" >"$GO_DEPOSIT_LOG"
    GO_DEPOSIT_RC=1
    return 1
  fi

  mapfile -t peers < <(go_deposit_peers "$schema")
  GO_DEPOSIT_PEERS=${#peers[@]}

  GO_DEPOSIT_RC=0
  node "$GO_REGISTER_VALIDATE" "$schema" "$GO_DEPOSIT" "${peers[@]}" >"$GO_DEPOSIT_LOG" 2>&1 ||
    GO_DEPOSIT_RC=$?

  # Exit 2 from the validator is never a statement about the deposit: the shape
  # check above has already ruled out the unreadable-file and wrong-kind cases,
  # so what is left is a schema this validator cannot fully enforce — a repo
  # defect, which is BROKEN and not DEGRADED.
  if [[ $GO_DEPOSIT_RC -eq 2 ]]; then
    go_broken "register-validate.mjs exited 2 on a deposit whose JSON, kind and subject this stage had already checked, so the remaining exit-2 causes are all about the SCHEMAS, not the file: a keyword the validator does not implement, or an x-rules/implementation mismatch. See $GO_DEPOSIT_LOG."
  fi

  # Every file on the command line is validated in its own right, so these are
  # totals across the deposit and its peers — which is what the receipt should
  # say, because a join finding may be reported against either side.
  GO_DEPOSIT_RULES=$(grep -oE '[0-9]+ rule\(s\) checked' "$GO_DEPOSIT_LOG" | awk '{s += $1} END {print s + 0}')
  GO_DEPOSIT_SKIPS=$(grep -c '^  skip ' "$GO_DEPOSIT_LOG" || true)
  GO_DEPOSIT_SKIPS=${GO_DEPOSIT_SKIPS:-0}
  GO_DEPOSIT_FIRED="$(go_deposit_rules_fired "$GO_DEPOSIT_LOG")"
  { read -r GO_DEPOSIT_OWN; read -r GO_DEPOSIT_PEER_FIRED; } < <(go_deposit_findings_split "$GO_DEPOSIT_LOG" "$GO_DEPOSIT")
  return "$GO_DEPOSIT_RC"
}

export GO_REGISTER_VALIDATE

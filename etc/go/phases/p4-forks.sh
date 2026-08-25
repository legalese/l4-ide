#!/usr/bin/env bash
# P4 — ambiguity forks and TYPICALLY defaults (de novo path). THE STAGE
# VALIDATES THE REGISTER; THE AGENT FINDS THE FORKS.
#
# R4 is ruled (R4-FORK-REPRESENTATION.md §7, 2026-08-02): one Interpretation
# record threaded as an ordinary GIVEN, public interface delegating to private
# per-reading implementations, extended to regulative rules. The register format
# enforces that ruling's 1:1 map — a materialised fork IS an Interpretation
# field, and two entries may not claim the same one — along with the fields the
# BNA smoke's twelve ambiguities showed every fork naturally has: both readings,
# the reading taken, and why.
#
# What this stage cannot do is find a fork. Opening one requires reading the
# source text against an encoding and noticing that two readings survive, which
# is the judgement SPEC.md §7.1 delegates to a frontier model and §7.3 carries at
# HG1. And fork-register COMPLETENESS is unfalsifiable in principle: no
# procedure establishes that every ambiguity was found, so the register is
# checked for internal and cross-file consistency and never for exhaustiveness.
#
# Requirements source: jl4/examples/legal/bna/SMOKE-REPORT.md §2 (p4-forks) —
# "the real stage therefore needs: R4 to specify a machine-checkable fork syntax
# (the prose-convention marker is an interface, and it already broke once — one
# of the 12 drifted from the exact marker syntax so a convention scan found 11),
# plus the both-readings/reading-taken/why fields this register shows every fork
# naturally has." Both landed: the register is JSON rather than a comment
# convention, and `readings[]` / `taken` / `rationale` are required fields whose
# absence is an exit code rather than a scan that quietly returns 11.
#
# The charities cleanroom (PR #201) is the second measured inventory and agrees:
# twelve interpretive choices, each with reading (i), reading (ii), the one
# taken, why, and — its own addition — the scenario that exercises the choice,
# which is `witnesses` here.

if [[ "${1:-}" == "--inputs" ]]; then
  printf '%s\n' "${GO_S_DENOVO_FORKS:-}" "${GO_S_DENOVO_REGISTER:-}" "${GO_S_DENOVO_BUNDLE:-}" \
    "${BASH_SOURCE[0]}" "$GO_ROOT/etc/go/lib/deposit-prelude.sh" \
    "$GO_ROOT/etc/go/lib/register-validate.mjs" \
    "$GO_ROOT/specs/todo/single-instruction-demo/schemas/fork-register.schema.json"
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"
source "$GO_ROOT/etc/go/lib/deposit-prelude.sh"

RC=0
go_deposit_check fork-register || RC=$?

# Materialisation is a discriminator, not an assumption: the BNA smoke's twelve
# ambiguities were ALL resolved at encode time or delegated to a fact-supplier,
# and none required runtime forking. So the counts are recorded per
# materialisation class — a register of twelve entries none of which is
# materialised is a true and interesting result, and one the report must be able
# to state without opening the artifact.
read -r ENTRIES MATERIALISED SETTLED WITNESSED < <(node -e '
  const j = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
  const e = Array.isArray(j.entries) ? j.entries : [];
  const c = (f) => e.filter(f).length;
  process.stdout.write(
    `${e.length} ${c((x) => x.materialisation === "interpretation-field")} ` +
      `${c((x) => x.status === "settled" || x.status === "demoted")} ` +
      `${c((x) => (x.witnesses ?? []).length > 0)}\n`,
  );
' "$GO_DEPOSIT" 2>/dev/null || echo "0 0 0 0")

METRICS=(--metric "deposit=$GO_DEPOSIT" --metric "peers_present=$GO_DEPOSIT_PEERS"
  --metric "rules_checked=$GO_DEPOSIT_RULES" --metric "joins_skipped=$GO_DEPOSIT_SKIPS"
  --metric "forks=$ENTRIES" --metric "materialised=$MATERIALISED"
  --metric "settled_by_authority=$SETTLED" --metric "with_witnesses=$WITNESSED")

declare -a SKIPNOTE=()
[[ "$GO_DEPOSIT_SKIPS" -gt 0 ]] && SKIPNOTE=(--note "$GO_DEPOSIT_SKIPS cross-file join(s) could not run because a peer deposit is absent — including 'cross-refs-resolve', which is how a fork an authority has already settled proves it cites a real P2 entry rather than presenting as open. The artifact reports each as 'skip', never as a pass")

if [[ -n "$GO_DEPOSIT_SHAPE" ]]; then
  go_receipt --status DEGRADED \
    --reason "the deposit at $GO_DEPOSIT $GO_DEPOSIT_SHAPE" \
    --artifact "$GO_DEPOSIT_LOG" "${METRICS[@]}"
  exit "$GO_EXIT_FINDING"
fi

if [[ $RC -ne 0 ]]; then
  # Own findings and peer findings are stated separately. The validator's exit
  # code is a total over every file on its command line, so a clean fork register
  # sitting next to a broken peer exits 1 — and calling that "the fork register
  # does not satisfy its own format" names the wrong file.
  if [[ -n "$GO_DEPOSIT_OWN" ]]; then
    REASON="the fork register at $GO_DEPOSIT does not satisfy its own format; rule(s) that fired against it: $GO_DEPOSIT_OWN."
    [[ -n "$GO_DEPOSIT_PEER_FIRED" ]] && REASON="$REASON Further finding(s) against peer deposit(s), which their own stages report: $GO_DEPOSIT_PEER_FIRED."
  else
    REASON="the fork register at $GO_DEPOSIT is internally well formed — no rule fired against it — but it was validated alongside its peer deposit(s) and the run reports: $GO_DEPOSIT_PEER_FIRED. Those belong to the peers' own stages; this stage cannot report PASS over a validator run that exited $RC."
  fi
  go_receipt --status DEGRADED \
    --reason "$REASON See $GO_DEPOSIT_LOG." \
    --artifact "$GO_DEPOSIT_LOG" "${METRICS[@]}"
  exit "$GO_EXIT_FINDING"
fi

go_receipt --status PASS \
  --oracle-cmd "node etc/go/lib/register-validate.mjs fork-register $GO_DEPOSIT (+$GO_DEPOSIT_PEERS peer deposit(s))" \
  --oracle-exit 0 \
  --oracle-class structural \
  --oracle-because "$GO_DEPOSIT_RULES declared rules ran, and they model R4's ruled representation rather than the file's syntax: the 1:1 map between a materialised fork and an Interpretation field is enforced in both directions, the reading taken must be one of the register's own live readings, a non-live reading must explain itself, a live reading must cite the text that licenses it, and an observable divergence must name a witness. It does NOT establish COMPLETENESS — $ENTRIES fork(s) are recorded and nothing here says that is all of them." \
  --artifact "$GO_DEPOSIT_LOG" "${METRICS[@]}" "${SKIPNOTE[@]}" \
  --note "fork-register completeness — that every ambiguity in the source was found — is unfalsifiable by construction and is carried by HG1 (SPEC.md §7.3). This stage's PASS means the $ENTRIES recorded forks are internally coherent and cross-reference resolvably, and nothing about the ones nobody noticed"

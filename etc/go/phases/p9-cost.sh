#!/usr/bin/env bash
# P9 — what this run cost, in wall clock and in tokens.
#
# Two halves, kept apart because they are evidence of different kinds and
# averaging their standing down to the weaker one would be the whole failure:
#
#   ATTESTED    what the driver measured. Every stage's `elapsed_ms` and
#               `dispatch_ms` were taken by the process that did the waiting,
#               and `ledger.verify` refuses a figure more than a second longer
#               than the bracket between the row's own stage_begin and
#               stage_end — a second of slack, for the whole-second clock
#               fallback in lib/clock.sh, and not a rounding convenience.
#   ATTRIBUTED  what the agent sessions spent, read out of the harness's own
#               JSONL transcripts. Nobody typed these numbers — but the
#               transcript is an ordinary file, so every one read is recorded
#               with its sha256 and byte count and the derivation can be
#               repeated by a second party.
#
# WHICH SESSIONS BELONG TO THIS RUN is the one question neither source answers
# alone. A transcript says what a session did and never which run it did it for;
# the journal says which sessions invoked the driver and nothing about what they
# spent. So the driver writes a `session` row per invocation, observed from
# CLAUDE_CODE_SESSION_ID, and this stage joins the two.
#
# It runs BEFORE p9-report so the report can read its metrics, which means it
# cannot see itself, p9-report or p9-explain. `measured_through` says where the
# figures stop, because a total that silently stops short reads as a total.

if [[ "${1:-}" == "--inputs" ]]; then
  # DELIBERATELY EMPTY, for p9-report's reason and one of its own.
  #
  # p9-report's: this reads the journal, and the journal grows as this stage
  # runs, so no honest digest of it exists — declaring one that omitted the
  # journal would let a stale cost report replay as current.
  #
  # Its own: the transcripts are outside the tree entirely and change with every
  # token the measuring session spends. There is no set of files whose digest
  # this stage's answer is a function of, so there is no digest to declare.
  # lib/ledger.mjs also names it in CROSS_RUN_INELIGIBLE, against the edit that
  # gives it inputs later.
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/../lib/phase-prelude.sh"

LEDGER="$GO_OUT/cost-ledger.json"

set +e
node "$GO_LIB/cost-ledger.mjs" build \
  --journal "$GO_RUN/journal.ndjson" \
  --out "$LEDGER" \
  --label "run $GO_RUNID" >"$GO_OUT/p9-cost.txt" 2>&1
RC=$?
set -e
cat "$GO_OUT/p9-cost.txt"

case $RC in
  0) ;;
  # Exit 3 is cost-ledger.mjs's "nothing to measure": no session row, no
  # --session, no CLAUDE_CODE_SESSION_ID. That is the pipeline driven by a
  # human at a terminal, which is a legitimate way to drive it and not a
  # defect. SKIPPED names it; a zero would read as "this run cost nothing".
  3)
    # DELIBERATELY NOT go_skip, which is fatal under L4_GO_REQUIRED=1.
    #
    # That variable means "a named PREREQUISITE is missing from this machine",
    # and it is right for a toolchain: a run that skipped its DMN engine is not
    # a run. An agent session is not a prerequisite of measuring a run — CI has
    # none by construction, and a pipeline driven by a human at a terminal has
    # none either. Making it fatal would kill every CI run at the second-to-last
    # stage, before p9-report, so the run would produce no report at all in
    # exactly the setting that most needs one.
    #
    # The receipt is still SKIPPED with its reason, and the attested stage
    # timings are unaffected: the driver writes those on every stage_end.
    go_receipt --status SKIPPED \
      --reason "no agent session is attributable to this run: the driver recorded no session row and CLAUDE_CODE_SESSION_ID is unset, which is what a run driven by hand or by CI looks like. The attested stage timings are still on every stage_end row." \
      --note "Not fatal under L4_GO_REQUIRED=1, unlike an ordinary SKIPPED: that flag is about a missing prerequisite, and an agent session is not one. A run with nobody to attribute has no token cost to report, which is a fact about the run rather than a gap in the machine."
    exit "$GO_EXIT_CLEAN"
    ;;
  *) go_broken "cost-ledger.mjs exited $RC building $LEDGER; see $GO_OUT/p9-cost.txt" ;;
esac

[[ -f "$LEDGER" ]] || go_broken "cost-ledger.mjs exited 0 but wrote no $LEDGER"

# --- the oracle: the ledger must add up ---------------------------------------
#
# `structural` and not `presence`, and here is exactly what earns it — stated
# precisely, because "the parts are folded independently" would overclaim.
#
# The two accumulations being compared come from ONE pass over the transcripts,
# so this is a REGRESSION guard rather than an independent derivation: it cannot
# catch a transcript that lies, and it will catch the day an edit makes two
# accumulations of the same population disagree. That is worth having and it is
# not the same thing, so the receipt says which it is.
#
# The one check that is NOT of that kind, and the strongest here: the
# per-segment figures are attributed by TIMESTAMP against the journal's stage
# brackets, by different code from the totals, and must re-sum to them exactly.
# A request placed in no segment, or in two, breaks it.
set +e
METRICS="$(node -e '
  const j = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
  const bad = [];
  const KEYS = ["requests","input_tokens","output_tokens","thinking_tokens","cache_creation_input_tokens","cache_read_input_tokens"];

  // 1. the per-session figures must re-sum to the stated totals.
  for (const k of KEYS) {
    const s = j.sessions.reduce((a, x) => a + x.total[k], 0);
    if (s !== j.totals.session_total[k]) bad.push(`totals.session_total.${k} is ${j.totals.session_total[k]}, sessions sum to ${s}`);
  }
  // 2. so must the by-role split, which is folded independently.
  for (const k of KEYS) {
    const s = Object.values(j.by_role).reduce((a, x) => a + x[k], 0);
    if (s !== j.totals.session_total[k]) bad.push(`by_role.${k} sums to ${s}, not ${j.totals.session_total[k]}`);
  }
  // 3. the in-window figures can never exceed the unclipped ones.
  for (const k of KEYS)
    if (j.totals.in_window[k] > j.totals.session_total[k]) bad.push(`in_window.${k} exceeds session_total.${k}`);
  // 4. a union is never larger than the sum of its parts, nor smaller than any one.
  const o = j.occupancy;
  if (o.busy_ms_lower_bound < o.pipeline_busy_ms) bad.push("busy_ms_lower_bound is below pipeline_busy_ms, which it contains");
  if (o.busy_ms_lower_bound < o.agent_tool_ms) bad.push("busy_ms_lower_bound is below agent_tool_ms, which it contains");
  if (o.busy_ms_lower_bound > o.pipeline_busy_ms + o.agent_tool_ms) bad.push("busy_ms_lower_bound exceeds the sum of its two components");
  // 5. a clipped figure can never exceed its unclipped self — the defect this
  //    check was written for, found by reading the first run of this pipeline.
  for (const t of j.tools) {
    if (t.calls_in_window > t.calls) bad.push(`tool ${t.name}: calls_in_window exceeds calls`);
    if (t.ms_in_window > t.ms) bad.push(`tool ${t.name}: ms_in_window exceeds ms`);
  }
  for (const k of Object.keys(j.network.calls)) {
    if (j.network.calls_in_window[k] > j.network.calls[k]) bad.push(`network.${k}: in-window calls exceed the total`);
    if (j.network.ms_in_window[k] > j.network.ms[k]) bad.push(`network.${k}: in-window ms exceed the total`);
  }
  // 6. the transcript count must agree with the per-session counts. (Whether a
  //    transcript could be READ is handled below, as a DEGRADED condition
  //    rather than here: an unreadable file makes the totals short, which is a
  //    caveat about coverage, not an artifact whose arithmetic disagrees.)
  const nt = j.transcripts.length;
  if (nt !== j.sessions.reduce((a, x) => a + x.transcripts, 0)) bad.push("transcript count disagrees with the per-session counts");
  // 7. THE INDEPENDENT ONE. Every in-window event is attributed to exactly one
  //    segment, by timestamp against the journal brackets, by code that does
  //    not share an accumulator with the totals. The sums must match exactly.
  for (const k of KEYS) {
    const s = j.by_segment.reduce((a, x) => a + x[k], 0);
    if (s !== j.totals.in_window[k]) bad.push(`by_segment.${k} sums to ${s}, not the in-window total ${j.totals.in_window[k]} — an event was placed in no segment or in two`);
  }

  if (bad.length) { console.error("cost-ledger does not add up:\n  " + bad.join("\n  ")); process.exit(1); }

  const p = j.pipeline ?? {};
  const t = p.totals ?? {};
  const w = j.totals.in_window, all = j.totals.session_total;
  // IN-WINDOW, to match the token figures beside it. A backgrounded tool
  // contributes calls but no time: its duration is dispatch, and the work it
  // launched is counted through the subagent transcripts instead.
  const tool = j.tools.reduce((a, x) => ({
    calls: a.calls + x.calls_in_window,
    ms: a.ms + (x.duration_is_dispatch ? 0 : x.ms_in_window),
    calls_all: a.calls_all + x.calls,
  }), { calls: 0, ms: 0, calls_all: 0 });
  const out = {
    cost_span_ms: o.span_ms, cost_pipeline_busy_ms: o.pipeline_busy_ms,
    cost_agent_tool_ms: o.agent_tool_ms, cost_busy_lower_bound_ms: o.busy_ms_lower_bound,
    cost_stage_elapsed_ms: t.elapsed_ms, cost_dispatch_ms: t.dispatch_ms,
    cost_stages: t.stages, cost_stages_replayed: t.replayed, cost_stages_untimed: t.untimed,
    cost_measured_through: p.measured_through,
    cost_sessions: (p.sessions ?? []).length, cost_invocations: p.invocations,
    cost_unattributed_invocations: p.unattributed_invocations,
    cost_transcripts: nt,
    cost_requests: w.requests, cost_input_tokens: w.input_tokens,
    cost_output_tokens: w.output_tokens, cost_thinking_tokens: w.thinking_tokens,
    cost_cache_creation_tokens: w.cache_creation_input_tokens,
    cost_cache_read_tokens: w.cache_read_input_tokens,
    cost_requests_session_total: all.requests,
    cost_output_tokens_session_total: all.output_tokens,
    // SESSION TOTALS, and they carry the suffix this stage uses for session
    // totals. Without it they sat unlabelled among window-clipped siblings —
    // the same conflation this change had to repair twice elsewhere.
    cost_subagent_requests_session_total: j.by_role.subagent?.requests ?? 0,
    cost_subagent_output_tokens_session_total: j.by_role.subagent?.output_tokens ?? 0,
    cost_workflows_session_total: j.workflows.length,
    cost_segments: j.by_segment.length,
    cost_transcripts_measuring_self: j.transcripts.filter((t) => t.measuring_self).length,
    cost_transcripts_unreadable: j.transcripts.filter((t) => t.unreadable).length,
    cost_tool_calls: tool.calls, cost_tool_ms: tool.ms,
    cost_tool_calls_session_total: tool.calls_all,
    cost_web_search: j.network.calls_in_window.web_search,
    cost_web_fetch: j.network.calls_in_window.web_fetch,
    cost_mcp_calls: j.network.calls_in_window.mcp,
    cost_network_ms: j.network.ms_in_window.web_search + j.network.ms_in_window.web_fetch + j.network.ms_in_window.mcp,
    cost_web_search_session_total: j.network.calls.web_search,
    cost_models: Object.keys(j.by_model).join(" "),
  };
  for (const [k, v] of Object.entries(out)) if (v !== null && v !== undefined) console.log(`${k}=${v}`);
' "$LEDGER")"
ORACLE_RC=$?
set -e
[[ $ORACLE_RC -eq 0 ]] || go_broken "the cost ledger this stage just wrote does not add up; see the lines above. That is a defect in etc/go/lib/cost-ledger.mjs, not a finding about the run."

METRIC_ARGS=()
while IFS= read -r kv; do [[ -n "$kv" ]] && METRIC_ARGS+=(--metric "$kv"); done <<<"$METRICS"

# --- what the figures do NOT cover, said out loud -----------------------------
NOTES=()
UNATTR="$(node -e 'const j=require(process.argv[1]);console.log(j.pipeline?.unattributed_invocations??0)' "$LEDGER")"
UNTIMED="$(node -e 'const j=require(process.argv[1]);console.log(j.pipeline?.totals?.untimed??0)' "$LEDGER")"
NOSCRIPT="$(node -e 'const j=require(process.argv[1]);console.log(j.sessions.filter(s=>s.transcripts===0).map(s=>s.session).join(" "))' "$LEDGER")"
UNREADABLE="$(node -e 'const j=require(process.argv[1]);console.log(j.transcripts.filter(t=>t.unreadable).length)' "$LEDGER")"

STATUS=PASS
if [[ "$UNATTR" != "0" ]]; then
  STATUS=DEGRADED
  NOTES+=("$UNATTR driver invocation(s) recorded no agent session — those legs were driven by something that set no CLAUDE_CODE_SESSION_ID. Their token cost is real and is not in these figures.")
fi
if [[ "$UNTIMED" != "0" ]]; then
  STATUS=DEGRADED
  NOTES+=("$UNTIMED stage(s) carry no elapsed_ms, so the stage-time total is short by an unmeasured amount. The reachable cause is a phase script run DIRECTLY rather than through go.sh — which SKILL.md and 'go.sh plan' both tell readers to do: the driver is what starts the clock, so a directly-invoked stage has no start to measure from.")
fi
if [[ -n "$NOSCRIPT" ]]; then
  STATUS=DEGRADED
  NOTES+=("no transcript was found on this machine for session(s): $NOSCRIPT. The session drove this run and its spend cannot be measured here.")
fi
if [[ "$UNREADABLE" != "0" ]]; then
  STATUS=DEGRADED
  NOTES+=("$UNREADABLE transcript(s) could not be read; the ledger names each with the error. Their requests are missing from every figure, so the totals are short by an unknown amount.")
fi

NOTE_ARGS=()
for n in "${NOTES[@]:-}"; do [[ -n "$n" ]] && NOTE_ARGS+=(--note "$n"); done

go_receipt --status "$STATUS" \
  --oracle-cmd "node etc/go/lib/cost-ledger.mjs build --journal \$RUN/journal.ndjson && the ledger's own parts re-sum to its stated totals" \
  --oracle-exit 0 \
  --oracle-class structural \
  --oracle-because "the per-session figures, the by-role split and the in-window clip are each folded independently and checked against the totals the artifact states, and the interval unions are checked against the bounds a union must satisfy; an artifact whose arithmetic disagrees with itself is refused as BROKEN rather than recorded" \
  --artifact "$LEDGER" --artifact "$GO_OUT/p9-cost.txt" \
  --note "The stage timings are ATTESTED — measured by the driver, and ledger.verify refuses any elapsed_ms more than a second longer than the bracket its own row sits in (the second of slack is for the whole-second clock fallback in lib/clock.sh). The token and tool figures are ATTRIBUTED: read from the harness's transcripts, which are named with their sha256 so the derivation can be repeated, but which are ordinary files. Figures stop at this stage; p9-report and p9-explain run after it. What each figure covers, and what it cannot, is stated in the report section that renders them, so it is written once." \
  "${METRIC_ARGS[@]}" "${NOTE_ARGS[@]}"

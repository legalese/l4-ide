#!/usr/bin/env node
// What a run COST, measured rather than asserted.
//
// Usage:
//   node etc/go/lib/cost-ledger.mjs build --out FILE
//        [--journal PATH]   a run's journal.ndjson: supplies the sessions to
//                           attribute, the run window, and the ATTESTED half
//        [--session UUID]…  a session to attribute on top of those; repeatable
//        [--from ISO --to ISO]  override the window
//        [--label TEXT]     what the window is, for the report
//   node etc/go/lib/cost-ledger.mjs scan [--project SLUG] [--limit N]
//        list sessions on this machine, newest first, with span and spend
//
// Exit: 0 written · 2 usage · 3 nothing to measure (no session resolved)
//
// --- where the numbers come from ---------------------------------------------
//
// Claude Code writes one JSONL transcript per session under
// <config>/projects/<slug>/<uuid>.jsonl, and one per subagent under
// <config>/projects/<slug>/<uuid>/subagents/**/*.jsonl. Every assistant record
// carries `message.usage` — the API's own accounting — and every record carries
// a `timestamp`. Tool calls appear as `tool_use` blocks and their results as
// `tool_result` blocks naming the same id, so a call's wall clock is the gap
// between the two.
//
// That makes this file a MEASUREMENT, not a deposit. The distinction matters
// because it is the one the rest of this pipeline is built on: a stage validates
// what an agent produced, and never accepts a number the agent typed. Here
// there is no number to accept — the transcript is written by the harness, and
// this reads it. An agent cannot make a request cheaper by saying so.
//
// It is still WEAKER than a driver attestation, and the ledger says so in its
// own `standing` field: the transcript is an ordinary file, and an agent with a
// shell can edit it. So every transcript read is recorded with its sha256 and
// byte count, which is what lets a second party re-derive these totals or show
// that the file moved underneath them.
//
// --- three traps, all of them measured on this repository's own transcripts ---
//
// 1. ONE REQUEST APPEARS ON SEVERAL ROWS. A single API response is split into
//    one record per content block — thinking, text, tool_use, tool_use — and
//    EVERY row repeats the same `message.usage`. Summing rows over this
//    session's transcript gave 2,918,840 output tokens; deduplicating by
//    `requestId` gave 1,337,281. A naive sum over-reports by roughly 2.2x.
//
// 2. SUBAGENTS ARE NOT IN THE SESSION TRANSCRIPT. Workflow and Agent subagents
//    write their own files under `<uuid>/subagents/`. On this session that was
//    146 files and 3,773 further requests — about a quarter of the output
//    tokens and four fifths of the Bash calls. A ledger that reads only the
//    session file reports a fraction and looks complete.
//
// 3. A SESSION MEASURING ITSELF IS MEASURING A FILE THAT IS STILL GROWING.
//    Two reads of this transcript eleven minutes apart differed by 11 Bash
//    calls — the calls that did the reading. That is not an error to be
//    corrected; it is a boundary to be named, so `measuring_self` is recorded
//    per transcript and the report states which figures stop at their own
//    measurement.
//
// --- what is deliberately NOT here -------------------------------------------
//
// No money. Token counts are facts about a run; prices are facts about a
// contract, they change without notice, and a stale rate table would put a
// confident wrong dollar figure in a report whose whole premise is that every
// number has a row behind it. A reader with a rate card can multiply.

import { createHash } from "node:crypto";
import {
  existsSync,
  readdirSync,
  readFileSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { basename, join, resolve } from "node:path";
import { read as readJournal } from "./ledger.mjs";

const EXIT = { OK: 0, USAGE: 2, NOTHING: 3 };

const nowIso = () => new Date().toISOString();

/** Where Claude Code keeps transcripts. CLAUDE_CONFIG_DIR wins, as it does for
 *  the harness itself; otherwise ~/.claude. */
export function configRoot() {
  return process.env.CLAUDE_CONFIG_DIR
    ? resolve(process.env.CLAUDE_CONFIG_DIR)
    : join(homedir(), ".claude");
}

/**
 * Find a session's transcripts, ANYWHERE under projects/.
 *
 * The project slug is the session's ORIGINAL working directory with the
 * separators replaced — not the current one. Every run of this pipeline happens
 * in a worktree under `l4wt/`, while the session that launched it was started
 * in the reference checkout, so deriving the slug from `process.cwd()` finds
 * nothing. Scanning is cheap (one readdir per project) and cannot be wrong.
 */
export function transcriptsFor(session, root = configRoot()) {
  const projects = join(root, "projects");
  if (!existsSync(projects)) return [];
  const out = [];
  for (const slug of readdirSync(projects)) {
    const main = join(projects, slug, `${session}.jsonl`);
    if (existsSync(main)) out.push({ path: main, role: "main", session });
    const subs = join(projects, slug, session, "subagents");
    if (existsSync(subs)) {
      const walk = (d) => {
        for (const e of readdirSync(d, { withFileTypes: true })) {
          const p = join(d, e.name);
          if (e.isDirectory()) walk(p);
          else if (e.name.endsWith(".jsonl"))
            out.push({
              path: p,
              role: "subagent",
              session,
              // The workflow run this subagent belonged to, when the layout
              // says so: subagents/workflows/<runId>/agent-<id>.jsonl.
              group: /\/subagents\/workflows\/([^/]+)\//.exec(p)?.[1] ?? null,
            });
        }
      };
      walk(subs);
    }
  }
  return out.sort((a, b) => (a.path < b.path ? -1 : 1));
}

const ZERO = () => ({
  requests: 0,
  input_tokens: 0,
  output_tokens: 0,
  thinking_tokens: 0,
  cache_creation_input_tokens: 0,
  cache_read_input_tokens: 0,
});

function addUsage(acc, u) {
  acc.requests += 1;
  acc.input_tokens += u.input_tokens || 0;
  acc.output_tokens += u.output_tokens || 0;
  acc.thinking_tokens += u.output_tokens_details?.thinking_tokens || 0;
  acc.cache_creation_input_tokens += u.cache_creation_input_tokens || 0;
  acc.cache_read_input_tokens += u.cache_read_input_tokens || 0;
  return acc;
}

/**
 * Which tool calls reached OUT of this machine, and under what name.
 *
 * A closed list, because there is no general way to tell: `Bash` reaches the
 * network whenever the command it ran was `curl`, and this cannot see inside
 * it. So the class is assigned from the tool NAME, every `mcp__*` tool counts
 * as an external service by construction, and the report states the boundary
 * rather than implying the count is every packet the run sent. The pipeline's
 * OWN fetches are counted separately, by the stage that makes them.
 */
export function networkClass(name) {
  if (name === "WebSearch") return "web_search";
  if (name === "WebFetch") return "web_fetch";
  if (name.startsWith("mcp__")) return "mcp";
  return null;
}

/**
 * Tools whose call duration is DISPATCH, not work.
 *
 * `Workflow` returns a task id immediately and the agents run in the
 * background; ten calls measured 17 seconds of tool time against hours of
 * subagent work. Recording that as the cost of the workflow would understate it
 * by two orders of magnitude, so these are flagged and the report reads their
 * real cost off the subagent transcripts instead.
 */
const BACKGROUNDED = new Set(["Workflow", "Agent", "Task", "Monitor"]);

function inWindow(ts, from, to) {
  if (!ts) return false;
  if (from && ts < from) return false;
  if (to && ts > to) return false;
  return true;
}

/**
 * Read one transcript. Returns the per-file measurement; the caller merges.
 *
 * `seen` is shared ACROSS files so a request is counted once even if two
 * transcripts record it. Request ids are globally unique, so a collision would
 * be a duplicate rather than two distinct requests — and double-counting is the
 * failure mode this whole file exists to avoid.
 */
function readTranscript(file, { from, to, seen }) {
  const st = statSync(file.path);
  let text;
  try {
    text = readFileSync(file.path, "utf8");
  } catch (e) {
    // AN UNREADABLE TRANSCRIPT IS REPORTED, NOT SKIPPED SILENTLY. A permission
    // error or a file past the runtime's string limit would otherwise take a
    // session's whole spend out of the totals with nothing to show for it, and
    // a total that is quietly short is exactly the failure this file exists to
    // avoid. The stage turns `unreadable` into DEGRADED.
    return {
      file: {
        path: file.path,
        role: file.role,
        group: file.group ?? null,
        session: file.session,
        sha256: null,
        bytes: st.size,
        mtime: st.mtime.toISOString(),
        records: 0,
        measuring_self: false,
        unreadable: e.message,
      },
      span: { first: null, last: null },
      total: ZERO(),
      in_window: ZERO(),
      by_model: {},
      tools: [],
      server: { web_search: 0, web_fetch: 0 },
      intervals: [],
      sidechain_requests: 0,
    };
  }
  const sha = "sha256:" + createHash("sha256").update(text).digest("hex");
  const total = ZERO();
  const win = ZERO();
  const byModel = {};
  const tools = new Map();
  const pending = new Map();
  const server = { web_search: 0, web_fetch: 0 };
  // Every paired tool call, as a real interval. The union of these is the only
  // LOWER BOUND on agent activity this file can measure without guessing: a
  // model thinking for four minutes between two Bash calls leaves no interval,
  // so the figure understates and is labelled as understating.
  const intervals = [];
  let records = 0;
  let first = null;
  let last = null;
  let sidechain = 0;

  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    let rec;
    try {
      rec = JSON.parse(line);
    } catch {
      // A HALF-WRITTEN LAST LINE IS NORMAL, not corruption: a live session is
      // appending while this reads. Skip it and keep going; the alternative is
      // a ledger that cannot be produced whenever the pipeline is driven by an
      // agent, which is every time.
      continue;
    }
    records += 1;
    const ts = rec.timestamp || null;
    if (ts) {
      if (!first || ts < first) first = ts;
      if (!last || ts > last) last = ts;
    }
    const within = inWindow(ts, from, to);

    if (Array.isArray(rec.message?.content)) {
      for (const c of rec.message.content) {
        if (c.type === "tool_use")
          pending.set(c.id, { name: c.name, ts, within });
        else if (c.type === "tool_result") {
          const u = pending.get(c.tool_use_id);
          if (!u) continue;
          pending.delete(c.tool_use_id);
          const ms = ts && u.ts ? Date.parse(ts) - Date.parse(u.ts) : null;
          const t = tools.get(u.name) ?? {
            name: u.name,
            calls: 0,
            calls_in_window: 0,
            ms: 0,
            ms_in_window: 0,
            max_ms: 0,
            unpaired: 0,
          };
          t.calls += 1;
          if (u.within) t.calls_in_window += 1;
          // A NEGATIVE OR ABSENT GAP IS DISCARDED, NOT CLAMPED. Clamping to
          // zero would fold a clock anomaly into the total silently; leaving it
          // out and counting it as unpaired keeps the arithmetic checkable.
          if (ms != null && ms >= 0) {
            t.ms += ms;
            // CLIPPED THE SAME WAY THE TOKEN FIGURES ARE. A tool total that
            // covers the whole session sitting beside a token total that covers
            // the run window is two different questions answered under sibling
            // names — measured on this pipeline's own first run, where a
            // 4.2-hour tool total sat next to a 7-second window.
            if (u.within) t.ms_in_window += ms;
            if (ms > t.max_ms) t.max_ms = ms;
            // A backgrounded tool returns at once and its work happens
            // elsewhere; its 300 ms of dispatch is not 300 ms of activity, and
            // the subagent transcripts contribute the real intervals.
            if (!BACKGROUNDED.has(u.name))
              intervals.push([Date.parse(u.ts), Date.parse(ts)]);
          } else t.unpaired += 1;
          tools.set(u.name, t);
        }
      }
    }

    const u = rec.message?.usage;
    if (!u) continue;
    // Trap 1: one request, several rows, the same usage repeated on each.
    if (rec.requestId) {
      if (seen.has(rec.requestId)) continue;
      seen.add(rec.requestId);
    }
    if (rec.isSidechain) sidechain += 1;
    addUsage(total, u);
    if (within) addUsage(win, u);
    const model = rec.message?.model || "unknown";
    addUsage((byModel[model] ??= ZERO()), u);
    server.web_search += u.server_tool_use?.web_search_requests || 0;
    server.web_fetch += u.server_tool_use?.web_fetch_requests || 0;
  }

  // A tool_use with no tool_result: the call was still running when the
  // transcript was read, or the session ended mid-call. Counted, not timed.
  for (const [, u] of pending) {
    const t = tools.get(u.name) ?? {
      name: u.name,
      calls: 0,
      calls_in_window: 0,
      ms: 0,
      ms_in_window: 0,
      max_ms: 0,
      unpaired: 0,
    };
    t.calls += 1;
    if (u.within) t.calls_in_window += 1;
    t.unpaired += 1;
    tools.set(u.name, t);
  }

  return {
    file: {
      path: file.path,
      role: file.role,
      group: file.group ?? null,
      session: file.session,
      sha256: sha,
      bytes: st.size,
      mtime: st.mtime.toISOString(),
      records,
      // Trap 3, named per file rather than guessed at from mtime.
      measuring_self:
        file.role === "main" &&
        file.session === (process.env.CLAUDE_CODE_SESSION_ID || null),
    },
    span: { first, last },
    total,
    in_window: win,
    by_model: byModel,
    tools: [...tools.values()],
    server,
    intervals,
    sidechain_requests: sidechain,
  };
}

function mergeUsage(a, b) {
  for (const k of Object.keys(a)) a[k] += b[k] || 0;
  return a;
}

function mergeTools(into, list) {
  for (const t of list) {
    const cur = into.get(t.name) ?? {
      name: t.name,
      calls: 0,
      calls_in_window: 0,
      ms: 0,
      ms_in_window: 0,
      max_ms: 0,
      unpaired: 0,
    };
    cur.calls += t.calls;
    cur.calls_in_window += t.calls_in_window;
    cur.ms += t.ms;
    cur.ms_in_window += t.ms_in_window;
    cur.unpaired += t.unpaired;
    if (t.max_ms > cur.max_ms) cur.max_ms = t.max_ms;
    into.set(t.name, cur);
  }
}

export function buildLedger({ sessions, from, to, label, root, pipeline }) {
  const seen = new Set();
  const files = [];
  const perSession = [];
  const totalAll = ZERO();
  const totalWin = ZERO();
  const byModel = {};
  const tools = new Map();
  const server = { web_search: 0, web_fetch: 0 };
  const groups = new Map();
  const byRole = { main: ZERO(), subagent: ZERO() };
  const activity = [];
  let sidechain = 0;

  for (const s of sessions) {
    const found = transcriptsFor(s.session, root);
    const acc = {
      session: s.session,
      attributed_by: s.attributed_by,
      transcripts: found.length,
      span: { first: null, last: null, ms: null },
      total: ZERO(),
      in_window: ZERO(),
    };
    for (const f of found) {
      const m = readTranscript(f, { from, to, seen });
      files.push(m.file);
      mergeUsage(acc.total, m.total);
      mergeUsage(acc.in_window, m.in_window);
      mergeUsage(byRole[f.role] ?? (byRole[f.role] = ZERO()), m.total);
      mergeTools(tools, m.tools);
      for (const iv of m.intervals) activity.push(iv);
      server.web_search += m.server.web_search;
      server.web_fetch += m.server.web_fetch;
      sidechain += m.sidechain_requests;
      for (const [k, v] of Object.entries(m.by_model))
        mergeUsage((byModel[k] ??= ZERO()), v);
      if (m.span.first && (!acc.span.first || m.span.first < acc.span.first))
        acc.span.first = m.span.first;
      if (m.span.last && (!acc.span.last || m.span.last > acc.span.last))
        acc.span.last = m.span.last;
      // Per-workflow rollup: what one fan-out cost, separable from the rest.
      if (m.file.group) {
        const g = groups.get(m.file.group) ?? {
          group: m.file.group,
          agents: 0,
          first: null,
          last: null,
          total: ZERO(),
        };
        g.agents += 1;
        mergeUsage(g.total, m.total);
        if (m.span.first && (!g.first || m.span.first < g.first))
          g.first = m.span.first;
        if (m.span.last && (!g.last || m.span.last > g.last))
          g.last = m.span.last;
        groups.set(m.file.group, g);
      }
    }
    if (acc.span.first && acc.span.last)
      acc.span.ms = Date.parse(acc.span.last) - Date.parse(acc.span.first);
    mergeUsage(totalAll, acc.total);
    mergeUsage(totalWin, acc.in_window);
    perSession.push(acc);
  }

  const toolList = [...tools.values()].map((t) => ({
    ...t,
    network: networkClass(t.name),
    // See BACKGROUNDED: for these the duration is the dispatch, and reading it
    // as the cost of the work would understate it by orders of magnitude.
    duration_is_dispatch: BACKGROUNDED.has(t.name),
  }));
  toolList.sort((a, b) => b.ms - a.ms || b.calls - a.calls);

  const net = { web_search: 0, web_fetch: 0, mcp: 0 };
  const netMs = { web_search: 0, web_fetch: 0, mcp: 0 };
  const netIn = { web_search: 0, web_fetch: 0, mcp: 0 };
  const netInMs = { web_search: 0, web_fetch: 0, mcp: 0 };
  for (const t of toolList)
    if (t.network) {
      net[t.network] += t.calls;
      netMs[t.network] += t.ms;
      netIn[t.network] += t.calls_in_window;
      netInMs[t.network] += t.ms_in_window;
    }

  // --- how long the machine was DEMONSTRABLY working ------------------------
  //
  // Four numbers, never one, because they answer four questions and the
  // difference between them IS the finding: a human-gated pipeline spends most
  // of its wall clock waiting for a human.
  const from_ms = from ? Date.parse(from) : -Infinity;
  const to_ms = to ? Date.parse(to) : Infinity;
  const clip = (iv) => [Math.max(iv[0], from_ms), Math.min(iv[1], to_ms)];
  const agentIv = activity.map(clip);
  const stageIv = (pipeline?.busy_intervals ?? []).map(clip);
  const occupancy = {
    // The elapsed time the run occupied, end to end. Includes every hour
    // nobody was working — overnight, and the human gates especially.
    span_ms: pipeline?.span?.ms ?? null,
    // The driver's own attested stage brackets, unioned.
    pipeline_busy_ms: unionMs(stageIv),
    // Tool calls only. A LOWER BOUND: time the model spent thinking or
    // generating between two tool calls is real work and leaves no interval
    // here, so this understates, and by an unknown amount.
    agent_tool_ms: unionMs(agentIv),
    // The two unioned rather than added — they overlap by construction, since
    // the agent is waiting while the stage it launched runs.
    busy_ms_lower_bound: unionMs([...stageIv, ...agentIv]),
    note:
      "span_ms includes idle time, which for a human-gated pipeline is most of it. " +
      "busy_ms_lower_bound is a floor, not an estimate: it counts attested stage brackets " +
      "and measured tool-call intervals, and counts nothing for model generation between calls.",
  };

  return {
    kind: "cost-ledger",
    schema: 1,
    // WHAT THIS IS EVIDENCE OF, stated in the artifact rather than inferred by
    // whoever reads it. `attributed` is the middle rung between the driver's
    // own attestations and an agent's claim: the numbers come from a harness-
    // written file, and the file is named with its hash so the derivation can
    // be repeated.
    standing: "attributed",
    measured_at: nowIso(),
    window: { from: from ?? null, to: to ?? null, label: label ?? null },
    // The two halves, kept apart on purpose: see `pipelineFromJournal`.
    pipeline: pipeline ?? null,
    occupancy,
    sessions: perSession,
    transcripts: files,
    totals: { session_total: totalAll, in_window: totalWin },
    by_model: byModel,
    // WHERE THE SPEND WENT: the session's own turns, or the subagents it
    // launched. Rolled up from the transcript each request was read from, not
    // from a flag on the record, so it holds for a harness that files subagent
    // turns differently. `sidechain_requests` is the harness's own marking of
    // the same split, kept as an independent cross-check.
    by_role: byRole,
    sidechain_requests: sidechain,
    workflows: [...groups.values()]
      .map((g) => ({
        ...g,
        ms: g.first && g.last ? Date.parse(g.last) - Date.parse(g.first) : null,
      }))
      .sort((a, b) => (a.group < b.group ? -1 : 1)),
    tools: toolList,
    network: {
      calls: net,
      ms: netMs,
      calls_in_window: netIn,
      ms_in_window: netInMs,
      // The API's own count of searches it ran server-side, which is a
      // different population from the client `WebSearch` tool and must not be
      // added to it.
      server_side: server,
      note:
        "Model-initiated only. A Bash call running curl reaches the network and is not counted here; " +
        "the pipeline's own fetches are counted by the stage that makes them.",
    },
  };
}

/**
 * INTERVAL UNION, in milliseconds.
 *
 * The one piece of arithmetic in this file that is easy to get wrong in the
 * direction that flatters. Stage time and agent time OVERLAP by construction —
 * the agent is sitting there while the stage runs — so adding them reports a
 * machine that worked twice as long as it did. Union, never sum.
 */
export function unionMs(intervals) {
  const iv = intervals
    .filter(
      (x) => Number.isFinite(x[0]) && Number.isFinite(x[1]) && x[1] > x[0],
    )
    .sort((a, b) => a[0] - b[0]);
  let total = 0;
  let curStart = null;
  let curEnd = null;
  for (const [a, b] of iv) {
    if (curEnd === null || a > curEnd) {
      if (curEnd !== null) total += curEnd - curStart;
      curStart = a;
      curEnd = b;
    } else if (b > curEnd) curEnd = b;
  }
  if (curEnd !== null) total += curEnd - curStart;
  return total;
}

/**
 * The ATTESTED half: what the driver itself measured, read back off the journal.
 *
 * Separate from everything above and labelled `attested` in the artifact,
 * because it is evidence of a different KIND. These figures were taken by the
 * process that did the waiting and are checked by `ledger.verify` against the
 * bracket each row sits in; the transcript figures are read from a file an
 * agent could edit. Merging them into one "total time" would quietly average
 * the two standings down to the weaker one.
 */
export function pipelineFromJournal(journalPath) {
  const rows = readJournal(journalPath);
  if (!rows.length) return null;
  const begin = rows.find((r) => r.kind === "run_begin") ?? null;
  const ends = rows.filter((r) => r.kind === "stage_end");
  // LAST ROW PER STAGE WINS, matching render-report.mjs. A stage re-run after a
  // repair has two rows, and counting both would bill the run for work it did
  // once and then did again — which is arguably true but is not what "how long
  // did stage X take" asks, and the report already reads the run stage-by-stage
  // off the latest row.
  const latest = [...new Map(ends.map((r) => [r.stage, r])).values()];
  const stages = latest.map((r) => ({
    stage: r.stage,
    status: r.status,
    elapsed_ms: typeof r.elapsed_ms === "number" ? r.elapsed_ms : null,
    dispatch_ms: typeof r.dispatch_ms === "number" ? r.dispatch_ms : null,
    replayed: Boolean(r.replayed_from),
    replayed_from_run: r.replayed_from_run ?? null,
    ts: r.ts ?? null,
  }));
  const sum = (f) => stages.reduce((a, x) => a + (x[f] ?? 0), 0);
  const ts = rows
    .map((r) => r.ts)
    .filter(Boolean)
    .sort();
  const intervals = [];
  // A stage's OCCUPIED interval is its bracket, not its elapsed: dispatch
  // happens inside it too, and the union below needs real endpoints.
  for (let i = 0; i < rows.length; i++) {
    if (rows[i].kind !== "stage_end" || !rows[i].ts) continue;
    for (let j = i - 1; j >= 0; j--) {
      if (rows[j].kind === "stage_end" && rows[j].stage === rows[i].stage)
        break;
      if (rows[j].kind === "stage_begin" && rows[j].stage === rows[i].stage) {
        if (rows[j].ts)
          intervals.push([Date.parse(rows[j].ts), Date.parse(rows[i].ts)]);
        break;
      }
    }
  }
  return {
    standing: "attested",
    run_id: begin?.run_id ?? null,
    subject: begin?.subject ?? null,
    encoding: begin?.encoding ?? begin?.milestone ?? null,
    // The sessions the DRIVER observed, one row per invocation. Deduplicated,
    // because a run driven in five sittings from one session yields five rows
    // and one session's spend.
    sessions: [
      ...new Set(
        rows
          .filter((r) => r.kind === "session" && r.session)
          .map((r) => r.session),
      ),
    ],
    invocations: rows.filter((r) => r.kind === "session").length,
    // Whether any leg was driven by something that is not an agent session. If
    // so, its cost is real and unattributable, and the report must say so
    // rather than let the reader read a missing figure as a zero.
    unattributed_invocations: rows.filter(
      (r) => r.kind === "session" && !r.session,
    ).length,
    span: {
      first: ts[0] ?? null,
      last: ts[ts.length - 1] ?? null,
      ms: ts.length ? Date.parse(ts[ts.length - 1]) - Date.parse(ts[0]) : null,
    },
    // The last `run_end`, or null while the run is still going. It is what the
    // window's upper edge should be for a ledger rebuilt AFTER the fact — see
    // cmdBuild. A resumed run writes several; the last one is the boundary.
    ended_at: rows.filter((r) => r.kind === "run_end").at(-1)?.ts ?? null,
    stages,
    totals: {
      stages: stages.length,
      elapsed_ms: sum("elapsed_ms"),
      dispatch_ms: sum("dispatch_ms"),
      replayed: stages.filter((x) => x.replayed).length,
      // A stage with no figure is NAMED, not averaged over. Every one of these
      // is a row written before this schema, or a stage that ended without
      // going through go_receipt.
      untimed: stages.filter((x) => x.elapsed_ms === null).length,
    },
    // The stage this ledger could see. It cannot see itself, and it cannot see
    // p9-report or p9-explain, which run after it. Stated rather than implied,
    // because a total that silently stops short reads as a total.
    measured_through: stages.length ? stages[stages.length - 1].stage : null,
    busy_intervals: intervals,
  };
}

// --- CLI ---------------------------------------------------------------------

function parse(argv) {
  const out = { session: [], _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith("--")) {
      out._.push(a);
      continue;
    }
    const key = a.slice(2);
    if (key === "session") {
      const v = argv[++i];
      if (v === undefined) usageDie(`--${key} needs a value`);
      out.session.push(v);
      continue;
    }
    const v = argv[++i];
    if (v === undefined) usageDie(`--${key} needs a value`);
    out[key.replace(/-/g, "_")] = v;
  }
  return out;
}

function usageDie(msg) {
  process.stderr.write(`cost-ledger.mjs: ${msg}\n`);
  process.stderr.write(
    "usage: cost-ledger.mjs build --out FILE [--session UUID]… [--from ISO --to ISO] [--label TEXT]\n" +
      "       cost-ledger.mjs scan [--project SLUG] [--limit N]\n",
  );
  process.exit(EXIT.USAGE);
}

function cmdScan(args) {
  const root = configRoot();
  const projects = join(root, "projects");
  if (!existsSync(projects)) {
    process.stderr.write(`cost-ledger.mjs: no transcripts under ${projects}\n`);
    process.exit(EXIT.NOTHING);
  }
  const rows = [];
  for (const slug of readdirSync(projects)) {
    if (args.project && slug !== args.project) continue;
    const dir = join(projects, slug);
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const e of entries) {
      if (!e.isFile() || !e.name.endsWith(".jsonl")) continue;
      const p = join(dir, e.name);
      const st = statSync(p);
      rows.push({
        session: basename(e.name, ".jsonl"),
        project: slug,
        mtime: st.mtime.toISOString(),
        bytes: st.size,
      });
    }
  }
  rows.sort((a, b) => (a.mtime < b.mtime ? 1 : -1));
  const limit = Number(args.limit || 20);
  for (const r of rows.slice(0, limit))
    process.stdout.write(
      `${r.mtime}\t${r.session}\t${String(r.bytes).padStart(10)}\t${r.project}\n`,
    );
  return EXIT.OK;
}

function cmdBuild(args) {
  if (!args.out) usageDie("build needs --out FILE");

  let pipeline = null;
  if (args.journal) {
    if (!existsSync(args.journal))
      usageDie(`--journal ${args.journal} is not a file`);
    pipeline = pipelineFromJournal(args.journal);
  }

  // WHERE THE SESSION LIST COMES FROM, in order of how much it is worth.
  //
  //   journal   the `session` rows the DRIVER wrote, one per invocation. This
  //             is the good source: it is the only one that knows which
  //             sessions actually drove THIS run, and it was observed rather
  //             than typed.
  //   env       the session running right now. Present because a ledger built
  //             outside a run (`--out` with no journal) should still measure
  //             something, and because it catches the first invocation of a
  //             run whose journal row this very stage precedes.
  //   --session anybody saying so. Kept, and marked `declared`, because a run
  //             whose encoding was written in a session that never invoked the
  //             driver has real cost the first two sources cannot see.
  //
  // All three are merged and every session carries how it was come by, because
  // that is what `standing` is for.
  const order = new Map();
  for (const sid of pipeline?.sessions ?? [])
    order.set(sid, { session: sid, attributed_by: "journal" });
  for (const sid of args.session)
    if (!order.has(sid))
      order.set(sid, { session: sid, attributed_by: "declared" });
  const env = process.env.CLAUDE_CODE_SESSION_ID;
  if (env && !order.has(env))
    order.set(env, { session: env, attributed_by: "observed" });
  const sessions = [...order.values()];
  if (!sessions.length) {
    process.stderr.write(
      "cost-ledger.mjs: no session to measure. Pass --journal PATH (whose driver\n" +
        "  invocations recorded one), --session UUID, or run under an agent harness\n" +
        "  that sets CLAUDE_CODE_SESSION_ID.\n",
    );
    process.exit(EXIT.NOTHING);
  }
  // THE WINDOW DEFAULTS TO THE RUN, not to all of time. Without it a session
  // that has been open all week reports the week's spend as this run's, which
  // is the over-attribution this whole file is trying not to commit.
  const ledger = buildLedger({
    sessions,
    from: args.from ?? pipeline?.span?.first ?? null,
    // THE UPPER EDGE, and it is not "no edge".
    //
    // p9-cost runs INSIDE the run, so there is no run_end yet and the boundary
    // is this moment. Rebuilt later — which is the ordinary way anyone checks
    // this artifact — the boundary is the run's own end, and leaving it open
    // would sweep in every hour the session worked on something else
    // afterwards. Measured: rebuilding this run's ledger with an open upper
    // edge reported more agent activity than the run's entire span.
    to: args.to ?? pipeline?.ended_at ?? (pipeline ? nowIso() : null),
    label: args.label ?? (pipeline ? `run ${pipeline.run_id}` : null),
    pipeline,
  });
  writeFileSync(args.out, JSON.stringify(ledger, null, 2) + "\n");
  return EXIT.OK;
}

// Importable as a module (selftest) without running the CLI.
if (
  process.argv[1] &&
  resolve(process.argv[1]) === resolve(new URL(import.meta.url).pathname)
) {
  const [cmd, ...rest] = process.argv.slice(2);
  const args = parse(rest);
  if (cmd === "scan") process.exit(cmdScan(args));
  else if (cmd === "build") process.exit(cmdBuild(args));
  else usageDie(`unknown command '${cmd ?? ""}'`);
}

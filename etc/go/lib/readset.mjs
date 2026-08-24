// R4 — the read-set: what a stage actually read, itemised.
//
// A stage already declares its inputs (`<stage>.sh --inputs`) and the driver
// already folds them into one `inputs_digest`. The fold answers "did anything
// change?" and cannot answer "which of these changed?", "was a prior encoding
// among them?", or "did these two runs read the same law?" — which are the
// three questions R4 exists to make askable.
//
// THE MEMBERS ARE A PROOF OF THE FOLD, NOT AN ANNOTATION BESIDE IT.
// `ledger.manifestText` renders exactly the fields `ledger.digestMembers`
// returns, so `refold(members) === inputs_digest` by construction — checkable
// offline, with no filesystem and no surviving run. A `stage_begin` row whose
// read-set does not re-fold to its own digest is a row nothing wrote
// legitimately. That identity is why the read-set is recorded as members
// rather than as a second, independently-derived list.
//
// NOTHING DERIVED IS STORED. A member's ROLE, an artifact's FRESHNESS and two
// encodings' COMPARABILITY are all computed here, at query time, from the
// graph. Storing any of them would store a fact about history inside a fact
// about a job, which is the category error this whole spec exists to stop
// (§2). Freshness in particular keeps its exact Make meaning — a newer
// prerequisite exists — and is derived, never recorded.

import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { refold, sha256File } from "./ledger.mjs";

// `refold` is defined in ledger.mjs, beside the frozen `manifestText` format it
// inverts, and re-exported here so a caller reasoning about read-sets can reach
// it from the read-set module. ONE implementation, two doors — never a second
// copy, because a drifting copy of a frozen format is how every digest in every
// journal quietly stops meaning what it says.
export { refold };

/**
 * What a stage DOES, which is intrinsic and therefore nameable (§3.3). The
 * three classes R5's table turns on are `natlang_sources`, `research` and
 * `encode`; the rest exist so role derivation is total, because a member whose
 * role is `unknown` silently weakens every predicate built on top of it.
 */
export const PHASE_CLASS = {
  "p0-preflight": "check",
  "p1-ingest": "natlang_sources",
  "p2-sweep": "research",
  "p3-check": "check",
  "p3-encode": "encode",
  "p4-forks": "register",
  "p5-gate": "gate",
  "p6-tests": "test",
  "p7-akn": "projection",
  "p7-bpmn": "projection",
  "p7-dmn": "projection",
  "p7-dmn-md": "projection",
  "p7-ladder": "projection",
  "p7-lts": "projection",
  "p7-mcp": "projection",
  "p7-tnr": "projection",
  "p7-wizard": "projection",
  "p8-diff": "compare",
  "p8-verify": "verify",
  "p9-explain": "report",
  "p9-report": "report",
  "p10-publish": "publish",
};

export function classOf(stage) {
  return PHASE_CLASS[stage] ?? "unknown";
}

/**
 * Resolve each member to a role. Self-contained sources are consulted FIRST,
 * because R8 makes a run directory answerable on its own and a derivation that
 * needs the store to be present is a derivation that stops working after
 * `store gc`.
 *
 *   1. a `text:` entry                          -> `param`
 *   2. produced by an earlier stage of THIS run -> that stage's class
 *   3. present in the store index               -> that record's stage's class
 *   4. inside the repo checkout                 -> `tree`
 *   5. otherwise                                -> `unknown`
 *
 * `rows` is this run's journal, `index` the store's index records (may be
 * empty — every caller must work with no store at all).
 */
export function rolesFor(members, rows = [], index = [], repoRoot = null) {
  // The run's OWN subject, read from its run_begin. Without it a run-origin
  // member carries no subject, and `freshness` keys produced members on an
  // empty one while every store record carries a real one — a guaranteed miss,
  // reported as `unknown`. Taken from the journal rather than passed in,
  // because the journal is the thing that knows, and an argument the caller
  // could get wrong is an argument that will be got wrong.
  const runSubject = rows.find((r) => r.kind === "run_begin")?.subject ?? null;
  const byRunSha = new Map();
  for (const r of rows) {
    if (r.kind !== "stage_end") continue;
    for (const a of r.artifacts ?? [])
      if (a.sha256 && !byRunSha.has(a.sha256))
        byRunSha.set(a.sha256, { stage: r.stage, rel: a.rel ?? null });
  }
  const byStoreSha = new Map();
  for (const r of index)
    if (r.sha256 && !byStoreSha.has(r.sha256))
      byStoreSha.set(r.sha256, {
        stage: r.stage,
        rel: r.rel ?? null,
        subject: r.subject ?? null,
      });

  const root = repoRoot ? resolve(repoRoot) : null;
  return members.map((m) => {
    if (m.path.startsWith("text:"))
      return { ...m, role: "param", origin: "declared" };
    const inRun = m.sha256 ? byRunSha.get(m.sha256) : null;
    if (inRun)
      return {
        ...m,
        role: classOf(inRun.stage),
        origin: "run",
        producer: inRun.stage,
        rel: inRun.rel,
        subject: runSubject,
      };
    // A store hit only wins if it actually YIELDS a class. It often does not:
    // the blessing path re-admits every `covers[]` member under the pseudo-
    // stage `covers`, with `rel` of the form `tree:<abs path>` — those records
    // say "a signature covered these bytes", which is a fact about review and
    // not about production. Letting such a record outrank the tree check
    // classified every corpus module of a blessed run as `unknown`, which is a
    // worse answer than the one the filesystem was about to give for free.
    const inStore = m.sha256 ? byStoreSha.get(m.sha256) : null;
    const storeClass = inStore ? classOf(inStore.stage) : "unknown";
    if (inStore && storeClass !== "unknown")
      return {
        ...m,
        role: storeClass,
        origin: "store",
        producer: inStore.stage,
        rel: inStore.rel,
        subject: inStore.subject,
      };
    // `tree:` in a store rel is the repo-file marker the store already uses;
    // honour it even when the path itself is outside this checkout, because a
    // borrowed run's tree file is still a tree file.
    if (inStore && String(inStore.rel ?? "").startsWith("tree:"))
      return { ...m, role: "tree", origin: "tree", coveredBy: inStore.stage };
    if (root && resolve(m.path).startsWith(root + "/"))
      return { ...m, role: "tree", origin: "tree" };
    return { ...m, role: "unknown", origin: "unresolved" };
  });
}

/**
 * The key a produced artifact is known by: (subject, stage, rel).
 *
 * ONE FUNCTION, USED BY BOTH ENDS, for the same reason `refold` sits beside
 * `manifestText`: a composite key built in one place and read in another is a
 * key that can silently disagree with itself. It did. The map was built with
 * NUL separators and read with spaces, so EVERY produced member missed and
 * reported `unknown` — produced-artifact freshness never worked, and the defect
 * was invisible because tree members take the by-content path instead.
 *
 * The separator is written as the ESCAPE `\u0000`, never as a literal byte:
 * a raw NUL in source is invisible in every diff and most editors, which is how
 * the mismatch survived review in the first place. selftest asserts this file
 * contains no raw NUL.
 */
export function witnessKey(subject, stage, rel) {
  const SEP = "\u0000";
  return `${subject ?? ""}${SEP}${stage ?? ""}${SEP}${rel ?? ""}`;
}

/**
 * FRESHNESS — Make's, exactly: does a newer version of any prerequisite exist?
 *
 * Answered per member, against the value that member WOULD have now, computed
 * the same way it was computed then:
 *
 *   - a `tree` member   -> hash the file on disk now
 *   - a produced member -> the newest admission under (subject, stage, rel)
 *   - a `param`         -> whatever `nowParams` says the driver would pass
 *
 * "Newest admission" is APPEND ORDER in `objects.ndjson`, never a timestamp. A
 * clock-derived answer would make the verdict depend on when it was asked,
 * which is the defect §3.7a found in the pipeline's own declared inputs.
 *
 * APPEND ORDER IS NOT PRODUCTION ORDER, and that is a deliberate choice rather
 * than an oversight. A cross-run REPLAY re-admits the donor's bytes, appending
 * a later index record that holds OLDER content — so the last record for a slot
 * can carry bytes produced before ones admitted earlier. It is kept because the
 * question freshness asks is Make's: "what IS this prerequisite now?", and the
 * pipeline's most recent word about that slot is the answer, exactly as "the
 * file on disk" is for a tree member. Ordering by production time instead would
 * need a clock, and would report a replayed artifact as stale against itself.
 *
 * Returns { state: "current" | "stale" | "unknown", moved, unknown }. `moved`
 * NAMES the members that moved, which is the whole reason a read-set beats a
 * digest: a digest can only ever say THAT something changed.
 */
export function freshness(roled, index = [], nowParams = {}) {
  const newest = new Map();
  for (const r of index) {
    if (!r.rel || !r.stage) continue;
    newest.set(witnessKey(r.subject, r.stage, r.rel), r.sha256);
  }
  const moved = [];
  let unknown = 0;
  for (const m of roled) {
    if (m.role === "param") {
      const key = m.path.slice(5).split("=")[0];
      if (!(key in nowParams)) {
        unknown++;
        continue;
      }
      const now = `text:${key}=${nowParams[key]}`;
      if (now !== m.path) moved.push({ ...m, now });
      continue;
    }
    // A PRODUCED artifact is asked about by IDENTITY, not by path: its path
    // names a run directory that may be long gone, so "is the file at that path
    // different" is the wrong question. "Is there a newer admission under the
    // same (subject, stage, rel)" is the right one, and it outlives the run.
    if (m.origin === "run" || m.origin === "store") {
      const now = newest.get(witnessKey(m.subject, m.producer, m.rel));
      if (now === undefined) {
        unknown++;
        continue;
      }
      if (now !== m.sha256) moved.push({ ...m, now });
      continue;
    }
    // EVERY OTHER MEMBER IS ASKED ABOUT BY CONTENT, and deliberately NOT gated
    // on repo membership. Whether a path lies inside the checkout decides its
    // ROLE; it has nothing to do with whether the file moved. Gating freshness
    // on it reported `unknown` for every member outside the tree — an
    // unevaluated prerequisite wearing the same word as an evaluated one.
    const abs = resolve(m.path);
    if (existsSync(abs)) {
      const now = sha256File(abs);
      if (now !== m.sha256) moved.push({ ...m, now });
      continue;
    }
    // The file is gone. A member already recorded ABSENT has not changed; one
    // recorded with a hash has been deleted, which is a move like any other.
    if (m.absent || m.sha256 == null) continue;
    moved.push({ ...m, now: null });
  }
  if (moved.length) return { state: "stale", moved, unknown };
  return { state: unknown ? "unknown" : "current", moved, unknown };
}

/**
 * INDEPENDENCE — did this producer read a prior encoding of the same subject?
 *
 * This is the only sense in which "blind" was ever meaningful (§3.4): an
 * encoding agent ALWAYS reads some corpus, namely the fetched legal text, so
 * the boolean that used to be called `blind` could only ever have meant this
 * one of the three edges it was conflating.
 */
export function independence(roled, subject = null) {
  const priors = roled.filter(
    (m) =>
      m.role === "encode" &&
      (subject == null || (m.subject ?? subject) === subject),
  );
  return { independent: priors.length === 0, priors };
}

/**
 * COMPARABILITY — do two read-sets rest on the same law?
 *
 * R5's load-bearing constraint: two encodings differ INTERPRETIVELY only if
 * their upstream `natlang_sources` were identical. Otherwise they are two
 * encodings of two different texts, and calling their difference a fork is
 * spurious. This is the predicate a `blind: true` flag cannot express at all,
 * which is what settles R4.
 */
export function comparability(roledA, roledB) {
  const src = (rs) =>
    new Set(
      rs
        .filter((m) => m.role === "natlang_sources" && m.sha256)
        .map((m) => m.sha256),
    );
  const a = src(roledA);
  const b = src(roledB);
  const onlyA = [...a].filter((s) => !b.has(s));
  const onlyB = [...b].filter((s) => !a.has(s));
  // NEITHER SIDE HAVING ANY is not comparability, it is absence of evidence.
  // Returning `true` there would license exactly the spurious fork claim this
  // predicate exists to prevent, and it is the case that holds TODAY for every
  // subject in the tree, because no subject has run p1-ingest for real.
  if (a.size === 0 && b.size === 0)
    return {
      comparable: false,
      reason: "no natlang_sources in either read-set",
      onlyA,
      onlyB,
    };
  if (onlyA.length || onlyB.length)
    return {
      comparable: false,
      reason: "upstream sources differ",
      onlyA,
      onlyB,
    };
  return {
    comparable: true,
    reason: "identical natlang_sources",
    onlyA,
    onlyB,
  };
}

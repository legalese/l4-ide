// The append-only, hash-chained run journal.
//
// One file per run: <rundir>/journal.ndjson. Every line is one record. Each
// record carries `prev` (the hash of the line before it) and `hash` (the
// sha256 of its own canonical JSON with `hash` removed), so a record cannot be
// altered or removed without breaking every hash after it.
//
// The chain is not a security control — an agent that can write the journal can
// rewrite the whole chain. It is an *undeniability* control: every route to a
// laundered status leaves a diff. render-report.mjs refuses a journal whose
// chain does not verify, so hand-editing the journal produces a report that
// says the journal was hand-edited.
//
// receipt.mjs is the only module that calls append(). Nothing else may.

import { createHash } from "node:crypto";
import {
  appendFileSync,
  existsSync,
  readdirSync,
  readFileSync,
  statSync,
} from "node:fs";
import { join } from "node:path";

/**
 * Bumped when the record shape changes. An unknown schema is BROKEN, not
 * guessed at.
 *
 * 2 (2026-08-02): the `gate` record gained `corpus_digest`, the sha256 over the
 * corpus files the gate was granted over. go.sh re-checks it before letting a
 * gated stage run, so a waiver no longer covers arbitrary later edits. A
 * schema-1 gate row carries no such binding, and cannot be distinguished from a
 * schema-2 row that failed to record one — which is exactly the ambiguity this
 * number exists to refuse.
 *
 * 4 (2026-08-24): the `stage_end` record gained `read_set` — R4's itemised
 * members of the set `inputs_digest` folds. It is a schema bump and not a free
 * addition because it makes a NEW CHECK possible: from schema 4 on, a
 * `stage_end` carrying a read-set must re-fold to its own digest, and `verify`
 * enforces it. A schema-3 row carries no read-set and cannot be distinguished
 * from a schema-4 row that failed to record one — the same ambiguity the
 * number existed to refuse at 2.
 *
 * 5 — `run_begin` says which ENCODING the run is about (`primary`, a declared
 * id, or `undeclared`) instead of which CAPABILITY MILESTONE it was labelled
 * with (R9, §3.9). This is a rename in shape only for `g1`, which always meant
 * the committed encoding; for `g2` it is a genuine gain in information, because
 * `g2` named an ordinal — "the additional one" — and an ordinal stops
 * identifying anything the moment a subject declares two. A schema-4 row
 * carries `milestone` and no `encoding`, and there is no way to recover from
 * `g2` WHICH additional encoding a run was about; readers report it as
 * `legacy:g2` rather than guessing an id.
 *
 * 6 (2026-08-25) — `stage_end` says how long the stage TOOK (`elapsed_ms`) and
 * how long the driver spent getting it there (`dispatch_ms`), and a `session`
 * record says which agent session each driver invocation ran under. It is a
 * schema bump on the same terms as 4: it makes a NEW CHECK possible, enforced
 * in `verify` below — a stage cannot have taken longer than the wall clock
 * between its own `stage_begin` and `stage_end`, and a row claiming otherwise
 * was not written by a driver that ran it. A schema-5 row carries no elapsed
 * and cannot be distinguished from a schema-6 row that failed to record one.
 *
 * The cost of a bump, paid once and by design: a run BEGUN under schema 5
 * cannot be resumed by this binary (see `append` below). Start a new run.
 */
export const JOURNAL_SCHEMA = 6;

/**
 * Schemas this binary can READ. A journal declares its schema in record 0 and
 * must be internally consistent; it does not have to match the current binary.
 *
 * The check this replaces was `rec.journal_schema !== JOURNAL_SCHEMA` on every
 * record, which made every journal ever written unverifiable the moment the
 * constant moved — including the ones committed to `legalese/canon`, silently,
 * because nobody re-verifies an old run until they need it. Adding fields is
 * safe for old records by construction: hashRecord canonicalises a record as
 * PARSED, with no schema template, so a schema-2 stage_end carrying no `rel`,
 * no `cas` and no `produced_under` hashes today to exactly what it hashed on
 * the day it was written.
 *
 * Internal consistency is still enforced, and that is the real check: a journal
 * whose record 0 says 2 and whose record 3 says 3 was written by two different
 * binaries into one chain, which is a genuine problem.
 */
export const KNOWN_SCHEMAS = new Set([2, 3, 4, 5, 6]);

export const GENESIS =
  "sha256:0000000000000000000000000000000000000000000000000000000000000000";

/** Deterministic JSON: keys sorted at every level, so the hash is stable. */
export function canonical(value) {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return "[" + value.map(canonical).join(",") + "]";
  const keys = Object.keys(value).sort();
  return (
    "{" +
    keys.map((k) => JSON.stringify(k) + ":" + canonical(value[k])).join(",") +
    "}"
  );
}

export function hashRecord(rec) {
  const { hash: _drop, ...rest } = rec;
  return "sha256:" + createHash("sha256").update(canonical(rest)).digest("hex");
}

export function sha256File(path) {
  return (
    "sha256:" + createHash("sha256").update(readFileSync(path)).digest("hex")
  );
}

export function sha256Text(text) {
  return "sha256:" + createHash("sha256").update(text).digest("hex");
}

/**
 * Digest a set of files as one value. Order-independent; missing files are
 * named, not skipped.
 *
 * An entry of the form `text:<value>` is a LITERAL contributor: a fact about
 * the run that is not a file, hashed as written. It exists so the driver can
 * fold in the sha256 of the `l4` binary — a 200 MB file that every stage
 * depends on and that would otherwise be re-read once per stage — without
 * pretending it is one of the stage's declared source paths.
 */
/**
 * The SERIALISATION digestSet hashes. Exported, because it is a document.
 *
 * `digestSet(paths) === sha256Text(manifestText(paths))`, by construction: this
 * IS digestSet's body, lifted out. That identity is what makes every digest
 * already recorded in every journal — and in the gate rows committed to
 * `legalese/canon` — resolvable to a readable manifest rather than staying an
 * opaque number. Two runs that disagree about whether a stage may replay can be
 * handed both manifests and diffed; nothing else in this system offers that.
 *
 * THE FORMAT IS FROZEN. It names run directories (the `corpus_sha8` in every
 * run id) and sits inside gate rows already committed. A tab moved here
 * silently stops every existing run id and gate binding from corresponding to
 * anything. selftest.mjs pins the identity above precisely so the lift cannot
 * drift from the thing it was lifted out of.
 */
export function manifestText(paths) {
  return [...paths]
    .sort()
    .map((p) => {
      if (p.startsWith("text:")) return p;
      if (!existsSync(p)) return `${p}\tABSENT`;
      return `${p}\t${statSync(p).size}\t${sha256File(p)}`;
    })
    .join("\n");
}

export function digestSet(paths) {
  return sha256Text(manifestText(paths));
}

/**
 * The same set, ITEMISED — one record per member, in manifestText's order.
 *
 * A digest is a set hash: it can say "this changed" and never "which of these
 * did the expert review?". That question is R11's, and answering it from a
 * digest means re-resolving the subject and re-reading the tree — both of which
 * need the run that is being asked about to still exist. This returns the
 * members as data, so a blessing can carry them and outlive its run.
 */
export function digestMembers(paths) {
  return [...paths].sort().map((p) => {
    if (p.startsWith("text:")) return { path: p, sha256: null, bytes: null };
    if (!existsSync(p))
      return { path: p, sha256: null, bytes: null, absent: true };
    return { path: p, sha256: sha256File(p), bytes: statSync(p).size };
  });
}

/**
 * manifestText's INVERSE, and it lives here rather than beside its callers so
 * that anyone editing the frozen format above cannot miss the other half of the
 * identity:
 *
 *     refold(digestMembers(paths)) === digestSet(paths)
 *
 * That identity is what makes an itemised read-set a PROOF of the digest it was
 * folded into, checkable offline with no filesystem and no surviving run
 * directory (R4, §3.4). A `stage_end` row whose recorded read-set does not
 * re-fold to its own `inputs_digest` is a row nothing wrote legitimately.
 *
 * The sort is deliberate: `manifestText` sorts before rendering, so sorting
 * here reproduces the identity faithfully and makes the check independent of
 * the order a journal happened to serialise the members in. A REORDERED record
 * still re-folds; a DOCTORED one does not — which is the asymmetry wanted.
 */
export function refold(members) {
  // A MALFORMED MEMBER MUST NOT CRASH THE VERIFIER. `verify` exists to REPORT
  // that a journal is wrong; if a hand-edited `read_set` containing a bare
  // string threw here, the verifier would die with a TypeError instead of
  // saying what it found — turning "this journal is broken" into "the tool is
  // broken", which is the report nobody can act on. A member that is not a
  // member object cannot re-fold to anything, so it renders as a value that
  // will not match any real digest, and `verify` says so in its own words.
  return sha256Text(
    [...members]
      .map((m) =>
        m && typeof m === "object" && typeof m.path === "string"
          ? m
          : { path: `\u0000malformed:${JSON.stringify(m ?? null)}` },
      )
      .sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0))
      .map((m) =>
        m.path.startsWith("text:")
          ? m.path
          : m.absent
            ? `${m.path}\tABSENT`
            : `${m.path}\t${m.bytes}\t${m.sha256}`,
      )
      .join("\n"),
  );
}

export function read(journalPath) {
  if (!existsSync(journalPath)) return [];
  const text = readFileSync(journalPath, "utf8");
  const out = [];
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    out.push(JSON.parse(line));
  }
  return out;
}

/**
 * Verify the chain. Returns { ok, records, problems }. A journal that does not
 * verify is not a finding about the corpus — it means the journal was edited by
 * something other than receipt.mjs.
 */
export function verify(journalPath) {
  const records = read(journalPath);
  const problems = [];
  let prev = GENESIS;
  records.forEach((rec, i) => {
    if (i === 0) {
      if (!KNOWN_SCHEMAS.has(rec.journal_schema))
        problems.push(
          `record 0 (${rec.stage ?? rec.kind}): journal_schema ${rec.journal_schema} is not one this binary reads (${[...KNOWN_SCHEMAS].join(", ")})`,
        );
    } else if (rec.journal_schema !== records[0].journal_schema) {
      problems.push(
        `record ${i} (${rec.stage ?? rec.kind}): journal_schema ${rec.journal_schema} != ${records[0].journal_schema} declared by record 0 — one chain, two binaries`,
      );
    }
    if (rec.prev !== prev)
      problems.push(
        `record ${i} (${rec.stage ?? rec.kind}): prev ${rec.prev} != ${prev}`,
      );
    const recomputed = hashRecord(rec);
    if (rec.hash !== recomputed)
      problems.push(
        `record ${i} (${rec.stage ?? rec.kind}): hash mismatch — the record was edited after it was written`,
      );
    if (rec.seq !== i)
      problems.push(`record ${i}: seq ${rec.seq} out of order`);
    // R4's integrity check, and the reason the read-set is worth recording as
    // members rather than as prose: a recorded read-set is a PROOF of the
    // digest beside it, and the proof is checkable here with no filesystem, no
    // store and no surviving run directory. Guarded on the read-set being
    // present so that schema-2 and schema-3 journals — including the ones
    // already committed to `legalese/canon` — verify exactly as they did.
    if (rec.kind === "stage_end" && Array.isArray(rec.read_set)) {
      const proof = refold(rec.read_set);
      if (rec.inputs_digest && proof !== rec.inputs_digest)
        problems.push(
          `record ${i} (${rec.stage}): read_set re-folds to ${proof}, not the recorded ` +
            `inputs_digest ${rec.inputs_digest} — the row claims inputs it did not read`,
        );
    }
    // SCHEMA 6: a stage cannot have taken longer than it was running.
    //
    // `elapsed_ms` is measured INSIDE the window the two records bracket — the
    // driver appends `stage_begin`, runs the script, and the script computes
    // the figure just before the call that appends `stage_end`. So the true
    // relation is strict, and a row claiming more time than its own bracket
    // allows was not written by a driver that ran the stage. Same standing as
    // the read-set check above: not a finding about the corpus, a statement
    // that the journal is not what it says it is.
    //
    // The tolerance exists for one measured reason. `go_now_ms` prefers bash's
    // EPOCHREALTIME and falls back to second-resolution `date` where that is
    // absent (bash 4), and a difference of two second-truncated readings can
    // exceed the true interval by just under 1000 ms. A tighter bound would
    // fire on the clock rather than on a defect.
    //
    // A REPLAYED row is exempt by construction, not by exception: a replay
    // writes no `stage_begin`, so there is no bracket, and `begin` is null.
    if (rec.kind === "stage_end" && typeof rec.elapsed_ms === "number") {
      let begin = null;
      for (let j = i - 1; j >= 0; j--) {
        const r = records[j];
        if (r.kind === "stage_end" && r.stage === rec.stage) break;
        if (r.kind === "stage_begin" && r.stage === rec.stage) {
          begin = r;
          break;
        }
      }
      if (begin?.ts && rec.ts) {
        const bracket = Date.parse(rec.ts) - Date.parse(begin.ts);
        if (Number.isFinite(bracket) && rec.elapsed_ms > bracket + 1000)
          problems.push(
            `record ${i} (${rec.stage}): elapsed_ms ${rec.elapsed_ms} exceeds the ` +
              `${bracket} ms between its own stage_begin and stage_end — the row ` +
              `claims time the stage did not have`,
          );
      }
    }
    prev = rec.hash;
  });
  return { ok: problems.length === 0, records, problems };
}

/** Append one record. The ONLY writer of journal.ndjson. Called only by receipt.mjs. */
export function append(journalPath, record) {
  const records = read(journalPath);
  // A JOURNAL'S SCHEMA IS FIXED WHEN IT IS CREATED. Resuming a run that began
  // under an older binary would otherwise stamp today's constant onto later
  // rows, and `verify` would then report "one chain, two binaries" FOREVER —
  // the run would be permanently unverifiable, which destroys the one property
  // the chain exists to provide. Refusing is the house rule applied to itself:
  // an unknown schema is BROKEN, not guessed at. The fix for the operator is to
  // start a new run, which costs a replay and keeps the evidence intact.
  if (records.length && records[0].journal_schema !== JOURNAL_SCHEMA)
    throw new Error(
      `ledger: ${journalPath} was created at journal_schema ${records[0].journal_schema}, ` +
        `and this binary writes ${JOURNAL_SCHEMA}. Appending would put two schemas in one ` +
        `chain and make the run permanently unverifiable. Start a new run instead.`,
    );
  const prev = records.length ? records[records.length - 1].hash : GENESIS;
  const rec = {
    journal_schema: JOURNAL_SCHEMA,
    seq: records.length,
    ts: new Date().toISOString(),
    ...record,
    prev,
  };
  rec.hash = hashRecord(rec);
  appendFileSync(journalPath, JSON.stringify(rec) + "\n");
  return rec;
}

/**
 * Resumability. Find a completed stage_end for `stage` whose recorded
 * inputs_digest matches the one computed now.
 *
 * The honesty hazard here is under-declaring the input set: a stage that omits
 * one of its real inputs from `inputs_digest` will report `replayed` after that
 * input changes. Each phase script therefore declares its own inputs — the
 * corpus files it reads, its own script source, and whatever pin it depends on
 * — behind `--inputs`, and go.sh (see `cmd_run`'s dispatch loop) digests that
 * list AFTER folding in the sha256 of the `l4` binary, which every stage
 * depends on and no stage can see. That fold is not decoration: without it a
 * run resumed against a REBUILT or SUBSTITUTED binary replayed every leg
 * without invoking it once, so p0-preflight's CLI-surface pin and its
 * failing-#ASSERT tripwire were skipped and the report still named the old
 * binary.
 */
export function findReplayable(journalPath, stage, inputsDigest) {
  const records = read(journalPath);
  for (let i = records.length - 1; i >= 0; i--) {
    const r = records[i];
    if (r.kind !== "stage_end" || r.stage !== stage) continue;
    if (r.status === "BROKEN") return null; // never replay a broken harness
    if (r.inputs_digest !== inputsDigest) return null; // inputs moved; re-run
    return r;
  }
  return null;
}

/**
 * Stages whose result is NOT determined by their declared inputs, and which
 * therefore may never borrow a receipt from a DIFFERENT run.
 *
 * The inputs digest covers files. It does not cover the world. Three stages
 * here are about the world:
 *
 *   * `p7-mcp` posts to a live jl4-service and reads the tool list back. Same
 *     inputs, different service — or no service at all — and the cached PASS
 *     would assert a deployment that is not there. Its oracle class is
 *     `execution`, and execution is precisely what a cross-run replay does not
 *     redo.
 *   * `p2-sweep` exists BECAUSE time has passed: its subject is whether a court
 *     or a regulator has moved since the text was printed. Caching it across
 *     runs is close to a category error — a sweep from six months ago has
 *     unchanged inputs and a stale answer, and SPEC.md §4 P2 requires the report
 *     to state what was SEARCHED, which a borrowed row cannot honestly restate.
 *   * `p9-cost` measures what THIS run cost, from transcripts written outside
 *     the tree by a harness the digest cannot see. Borrowing its receipt would
 *     report another run's hours and tokens as this one's — the single most
 *     misleading number the pipeline could produce, because it would be
 *     precise, sourced and about the wrong run. It declares NO inputs today,
 *     which already makes both kinds of replay unreachable — the driver skips
 *     the lookup entirely on an empty digest. Naming it here is defence
 *     against the edit that gives it a digest later: that edit would otherwise
 *     make it cross-run replayable silently, and the failure would look like a
 *     correct report of the wrong run's cost.
 *
 * These stages still replay WITHIN a run: resuming an interrupted run must not
 * redo work the same run already did, and inside one run the world has not been
 * given a chance to move. The rule is about crossing a run boundary only.
 *
 * This is a closed list, not a heuristic: a stage is cacheable across runs
 * unless it is named here, and adding a name is a deliberate act.
 */
export const CROSS_RUN_INELIGIBLE = new Set(["p7-mcp", "p2-sweep", "p9-cost"]);

/**
 * The subject a run is for, read from its `run_begin` record. Returns null for
 * a directory that is not a run, or whose journal is unreadable — a malformed
 * neighbour must never make the current run fail.
 */
export function runSubject(journalPath) {
  try {
    const first = read(journalPath)[0];
    return first && first.kind === "run_begin" ? (first.subject ?? null) : null;
  } catch {
    return null;
  }
}

/**
 * Find a replayable receipt in ANOTHER run of the SAME subject.
 *
 * Scoping rules, each of which exists to stop a specific wrong reuse:
 *
 *   * same subject — a `p6-tests` PASS earned by regcf must never satisfy
 *     sg-succession, however the digests happen to fall;
 *   * same inputs digest — this is the actual authority, and it already folds
 *     in the `l4` binary's own sha256, so a rebuilt toolchain invalidates
 *     everything downstream;
 *   * never BROKEN — a harness defect is not evidence, in any run;
 *   * never a stage in CROSS_RUN_INELIGIBLE;
 *   * never the current run — that is `findReplayable`'s job, and it is
 *     checked first because a receipt from THIS run needs no artifact copy.
 *
 * The ENCODING is deliberately NOT filtered on. A stage that ran over the
 * committed encoding and over a deposit has different inputs and so a different
 * digest; the digest discriminates, and filtering on the encoding as well would
 * only mask a digest collision rather than prevent one.
 *
 * Newest run first, so the most recent qualifying evidence wins.
 */
export function findReplayableAcrossRuns(
  runRoot,
  currentRunDir,
  subject,
  stage,
  inputsDigest,
) {
  if (!inputsDigest || CROSS_RUN_INELIGIBLE.has(stage)) return null;
  if (!runRoot || !existsSync(runRoot)) return null;
  let entries;
  try {
    entries = readdirSync(runRoot);
  } catch {
    return null;
  }
  const current = currentRunDir ? currentRunDir.replace(/\/+$/, "") : "";

  // ORDERED BY WHEN THE RUN BEGAN, not by the run id's spelling.
  //
  // A run id is `YYYY-MM-DD-<corpus_sha8>-NNN`, so a lexicographic sort orders
  // by date, then by the CORPUS HASH, then by sequence. Within a single day the
  // greater sha8 therefore outranks the temporally later run — and the sha8 is
  // a content hash, so its order carries no meaning at all. Reachable whenever
  // one day holds runs over different corpora and a stage declares inputs
  // narrow enough to match across them (`p7-wizard` names only the wizard
  // module), and the consequence is borrowing an older receipt while a newer
  // execution over the same inputs sits right there.
  //
  // THE SELECTION RULE IS "the most recent execution over these inputs", and it
  // stays that. It is deliberately NOT "the best status over these inputs": a
  // lookup that preferred a PASS to a more recent DEGRADED would be status
  // shopping — picking the answer you want out of a set of equally valid ones —
  // which is the erosion this file refuses everywhere else. The ordering is the
  // bug; the rule is not, and the obvious "improvement" to a freshly-touched
  // ordering function is exactly the corruption.
  const candidates = [];
  for (const name of entries) {
    const dir = join(runRoot, name);
    if (dir === current) continue;
    const journal = join(dir, "journal.ndjson");
    if (!existsSync(journal)) continue;
    if (runSubject(journal) !== subject) continue;
    let ts = "";
    try {
      const first = read(journal)[0];
      ts = first?.kind === "run_begin" ? (first.ts ?? "") : "";
    } catch {
      ts = "";
    }
    candidates.push({ name, dir, journal, ts });
  }
  // ts descending; a run with no readable ts sorts last rather than first, so a
  // malformed journal can never outrank a well-formed one. Run id descending
  // breaks a tie, which is the old behaviour restored where it was harmless.
  candidates.sort((a, b) =>
    a.ts === b.ts ? (a.name < b.name ? 1 : -1) : a.ts < b.ts ? 1 : -1,
  );

  for (const { name, dir, journal } of candidates) {
    let record;
    try {
      record = findReplayable(journal, stage, inputsDigest);
    } catch {
      continue;
    }
    if (record) return { record, runId: name, runDir: dir, journal };
  }
  return null;
}

export function attemptsFor(journalPath, stage) {
  return read(journalPath).filter(
    (r) => r.kind === "stage_end" && r.stage === stage,
  ).length;
}

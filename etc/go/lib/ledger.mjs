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
import { appendFileSync, existsSync, readFileSync, statSync } from "node:fs";

/** Bumped when the record shape changes. An unknown schema is BROKEN, not guessed at. */
export const JOURNAL_SCHEMA = 1;

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

/** Digest a set of files as one value. Order-independent; missing files are named, not skipped. */
export function digestSet(paths) {
  const parts = [...paths].sort().map((p) => {
    if (!existsSync(p)) return `${p}\tABSENT`;
    return `${p}\t${statSync(p).size}\t${sha256File(p)}`;
  });
  return sha256Text(parts.join("\n"));
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
    if (rec.journal_schema !== JOURNAL_SCHEMA)
      problems.push(
        `record ${i} (${rec.stage ?? rec.kind}): journal_schema ${rec.journal_schema} != ${JOURNAL_SCHEMA}`,
      );
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
    prev = rec.hash;
  });
  return { ok: problems.length === 0, records, problems };
}

/** Append one record. The ONLY writer of journal.ndjson. Called only by receipt.mjs. */
export function append(journalPath, record) {
  const records = read(journalPath);
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
 * input changes. Phase scripts therefore digest the corpus files AND their own
 * script source AND the pinned CLI surface; see PHASE_INPUTS in go.sh.
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

export function attemptsFor(journalPath, stage) {
  return read(journalPath).filter(
    (r) => r.kind === "stage_end" && r.stage === stage,
  ).length;
}

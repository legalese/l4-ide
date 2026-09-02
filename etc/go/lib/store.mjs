#!/usr/bin/env node
// The artifact store and the blessing ledger — R6 and R11, one structure.
//
// THE INVERSION, in one sentence: before this module the run directory held the
// original and no store existed; after it the store holds the original and the
// run directory holds a cache. Nothing had to move for that to become true —
// only the direction of the arrow.
//
// Both rulings need the same thing: "a fact about a content hash that outlives
// the run that produced it". R6 needs it so two runs of one phase can be
// compared rather than clobbered; R11 needs it so a human's blessing does not
// expire with $TMPDIR. Measured 2026-08-20: of 92 run directories, 16 still
// hold a journal and files last two to five days. A blessing recorded only in a
// run journal has that half-life, which is not an architectural preference —
// it is a signature expiring in under a week for reasons nobody chose.
//
//   $L4_GO_STORE   default ${XDG_STATE_HOME:-$HOME/.local/state}/l4-go/store
//   ├── objects/<aa>/<hex64>        the bytes, mode 0444
//   ├── objects.ndjson              INDEX — unchained, lock-free, REBUILDABLE
//   ├── blessings/<seq6>-<hex8>.json  LEDGER — one file per record, chained
//   └── tmp/                        staging for atomic rename into objects/
//
// TWO INTEGRITY MODELS, DELIBERATELY DIFFERENT.
//
// objects.ndjson is an INDEX. Each record is one short line, so an O_APPEND
// write is atomic on POSIX and needs no lock even with concurrent runs. It is
// unchained because it is rebuildable: every fact in it also exists in some run
// journal. Losing it costs provenance metadata, not evidence.
//
// blessings/ is a LEDGER, and it is NOT rebuildable — a signature is the one
// thing in this system nobody can re-derive. So it is one file per record under
// `wx` (atomic create-or-fail, lock-free, crash-safe) rather than a shared
// ndjson: a `kill -9` mid-append to a shared file would corrupt the only thing
// that cannot be reconstructed, and losing one file here breaks the `prev`
// chain VISIBLY at one point instead of silently truncating.
//
// FAIL-OPEN AT PRODUCTION, FAIL-CLOSED AT CONSUMPTION. put() returns null and
// never throws: a broken home directory must not turn a good legal encoding run
// red. The refusal lives on the serving side, where a null `cas` means the
// bytes are not fetchable and therefore not servable.
import {
  chmodSync,
  copyFileSync,
  existsSync,
  mkdirSync,
  openSync,
  closeSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
  appendFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { hashRecord, sha256File, sha256Text } from "./ledger.mjs";

export const STORE_SCHEMA = 2;
const GENESIS = "sha256:" + "0".repeat(64);

/** $L4_GO_STORE, else the XDG state dir. Never $TMPDIR — that is the point. */
export function storeRoot() {
  if (process.env.L4_GO_STORE) return resolve(process.env.L4_GO_STORE);
  const xdg = process.env.XDG_STATE_HOME || join(homedir(), ".local", "state");
  return join(xdg, "l4-go", "store");
}

export function objectPath(root, sha) {
  const hex = sha.replace(/^sha256:/, "");
  return join(root, "objects", hex.slice(0, 2), hex);
}

function ensure(root) {
  for (const d of ["objects", "blessings", "tmp"])
    mkdirSync(join(root, d), { recursive: true });
}

export function has(root, sha) {
  try {
    return existsSync(objectPath(root, sha));
  } catch {
    return false;
  }
}

/**
 * Admit bytes. Returns the sha on success, null on ANY failure.
 *
 * Idempotent: an object already present is not rewritten, but a new index
 * record IS appended, because the index is per-admission provenance — the same
 * bytes produced by two runs is exactly the fact R6 wants to keep.
 */
export function put(root, absPath, sha, meta = {}) {
  try {
    ensure(root);
    const dest = objectPath(root, sha);
    if (!existsSync(dest)) {
      mkdirSync(dirname(dest), { recursive: true });
      // Stage then rename: a reader never sees a partial object, because
      // rename(2) within one filesystem is atomic.
      const tmp = join(root, "tmp", `${process.pid}-${sha.slice(7, 23)}`);
      copyFileSync(absPath, tmp);
      chmodSync(tmp, 0o444);
      renameSync(tmp, dest);
    }
    const rec = {
      store_schema: STORE_SCHEMA,
      ts: new Date().toISOString(),
      sha256: sha,
      bytes: meta.bytes ?? statSync(absPath).size,
      subject: meta.subject ?? null,
      stage: meta.stage ?? null,
      rel: meta.rel ?? null,
      inputs_digest: meta.inputs_digest ?? null,
      run_id: meta.run_id ?? null,
      produced_under: meta.produced_under ?? null,
      // R5's precondition, carried on the admission so it outlives the journal.
      // null means "this witness recorded no natlang_sources", which is NOT the
      // same claim as "its sources hashed to X" — conflating them would let two
      // source-less encodings look comparable, which is the spurious fork R5
      // exists to prevent.
      sources_digest: meta.sources_digest ?? null,
    };
    appendFileSync(join(root, "objects.ndjson"), JSON.stringify(rec) + "\n");
    return sha;
  } catch {
    return null;
  }
}

/** Copy an object out to destAbs. Returns true iff destAbs now has those bytes. */
export function materialise(root, sha, destAbs) {
  try {
    const src = objectPath(root, sha);
    if (!existsSync(src)) return false;
    mkdirSync(dirname(destAbs), { recursive: true });
    copyFileSync(src, destAbs);
    chmodSync(destAbs, 0o644);
    return true;
  } catch {
    return false;
  }
}

export function indexRecords(root, filter = {}) {
  const p = join(root, "objects.ndjson");
  if (!existsSync(p)) return [];
  const out = [];
  for (const line of readFileSync(p, "utf8").split("\n")) {
    if (!line.trim()) continue;
    let rec;
    try {
      rec = JSON.parse(line);
    } catch {
      continue; // a torn line is a lost index entry, not a corrupt store
    }
    if (
      Object.entries(filter).every(([k, v]) => v === undefined || rec[k] === v)
    )
      out.push(rec);
  }
  return out;
}

// ---------------------------------------------------------------- blessings

const blessingFiles = (root) => {
  const d = join(root, "blessings");
  if (!existsSync(d)) return [];
  return readdirSync(d)
    .filter((f) => f.endsWith(".json"))
    .sort();
};

export function readBlessings(root) {
  return blessingFiles(root)
    .map((f) => {
      try {
        return JSON.parse(readFileSync(join(root, "blessings", f), "utf8"));
      } catch {
        return null;
      }
    })
    .filter(Boolean)
    .sort((a, b) => a.seq - b.seq);
}

/**
 * Append a blessing. EXPORTED BUT GIVEN NO CLI VERB, deliberately.
 *
 * receipt.mjs is the only writer of a status precisely so that no caller can
 * assert one it did not earn; a blessing is the same kind of claim and gets the
 * same treatment. A phase script, a debug flag or a future agent has no route
 * to manufacture one, because there is no command to run.
 */
export function writeBlessing(root, rec) {
  ensure(root);
  const existing = readBlessings(root);
  let seq = existing.length;
  const prev = existing.length ? existing[existing.length - 1].hash : GENESIS;
  for (let attempt = 0; attempt < 20; attempt++) {
    const full = { ...rec, store_schema: STORE_SCHEMA, seq, prev };
    full.hash = hashRecord(full);
    const name = `${String(seq).padStart(6, "0")}-${full.hash.slice(7, 15)}.json`;
    const path = join(root, "blessings", name);
    try {
      // `wx` — create-or-fail. A collision means a concurrent writer took this
      // seq; retry at seq+1 rather than overwrite the one file that cannot be
      // rebuilt.
      const fd = openSync(path, "wx");
      try {
        writeFileSync(fd, JSON.stringify(full, null, 2) + "\n");
      } finally {
        closeSync(fd);
      }
      return full;
    } catch (e) {
      if (e?.code !== "EEXIST") throw e;
      seq += 1;
    }
  }
  throw new Error("store: 20 consecutive blessing seq collisions");
}

export function verifyBlessings(root) {
  const recs = readBlessings(root);
  const problems = [];
  let prev = GENESIS;
  recs.forEach((r, i) => {
    if (r.seq !== i) problems.push(`blessing ${i}: seq ${r.seq} out of order`);
    if (r.prev !== prev)
      problems.push(`blessing ${i}: prev ${r.prev} != ${prev}`);
    const { hash, ...rest } = r;
    if (hash !== hashRecord(rest))
      problems.push(
        `blessing ${i}: hash mismatch — the record was edited after it was written`,
      );
    prev = r.hash;
  });
  return { ok: problems.length === 0, problems, count: recs.length };
}

/**
 * THE SERVING PREDICATE. Written ONCE, here, and called by everything.
 *
 * Three erosion attacks on this design turned out to be the same defect: "an
 * object is servable iff…" written once in gc's retention roots, once in the
 * blessing lookup and once in the refusal, with the copies disagreeing about
 * `waived`. This is the only version in which that sentence is a fact about the
 * code rather than a claim about three of them.
 *
 * `waived` is an EDGE, not an absence — a verdict with a reason attached, in
 * gate-verify.sh's own words — so it resolves, and the caller decides whether a
 * waiver is good enough for what it is about to do.
 */
export function servability(root, sha) {
  const admissions = indexRecords(root, { sha256: sha });
  if (admissions.length === 0)
    return { servable: false, state: "unknown", reason: "no admission record" };
  const byId = new Map(readBlessings(root).map((b) => [b.hash, b]));
  // "some record", not "the record": content addressing means the blessing
  // attaches to the BYTES. If any admission of these bytes was under a
  // satisfied grant, they are what was blessed, whichever run produced them.
  let best = null;
  for (const a of admissions) {
    const b = a.produced_under?.blessing
      ? byId.get(a.produced_under.blessing)
      : null;
    if (!b) continue;
    if (b.state === "satisfied")
      return { servable: true, state: "satisfied", blessing: b };
    if (b.state === "waived" && !best) best = b;
  }
  if (best)
    return {
      servable: false,
      state: "waived",
      blessing: best,
      reason: best.reason ?? "no reason recorded",
    };
  return {
    servable: false,
    state: "unblessed",
    reason: "admitted, but under no gate — the producing stage was ungated",
  };
}

/** The blessing that covers these bytes, or null. */
export function blessingFor(root, sha) {
  const s = servability(root, sha);
  return s.blessing ?? null;
}

/**
 * Refuse a blessing record that claims more than it carries.
 *
 * Gate rows bypass checkReceipt today — receipt.mjs applies it only under
 * `case stage_end` — so a row claiming `satisfied` with a null signature is
 * written without complaint. In a run directory that is disposable; in a ledger
 * nothing ever sweeps it is permanent, and a waived-HG2 claim in particular
 * could never be taken back.
 */
export function checkClaim(rec) {
  const problems = [];
  const need = (c, m) => c || problems.push(m);
  need(
    rec.gate === "HG1" || rec.gate === "HG2",
    `unknown gate '${rec.gate}' (SPEC.md §7.3 defines HG1 and HG2)`,
  );
  need(
    ["satisfied", "waived", "refused"].includes(rec.state),
    `unknown state '${rec.state}'`,
  );
  if (rec.state === "satisfied") {
    need(rec.signature, "state 'satisfied' with no signature");
    need(rec.signer, "state 'satisfied' with no signer");
    need(rec.namespace, "state 'satisfied' with no signing namespace");
    need(rec.payload_digest, "state 'satisfied' with no payload_digest");
  }
  if (rec.state === "waived" || rec.state === "refused")
    need(rec.reason, `state '${rec.state}' with no reason`);
  // HG2's unwaivability moves OUT of go.sh's prose and INTO the writer. A
  // waived-HG2 record in a ledger nothing sweeps is a permanent claim that the
  // one ungateable gate was gated away.
  need(
    !(rec.gate === "HG2" && rec.state === "waived"),
    "HG2 may never be waived (SPEC.md §7.3); a waived-HG2 record in a durable ledger could never be withdrawn",
  );
  need(Array.isArray(rec.covers), "no covers[] array");
  return { ok: problems.length === 0, problems };
}

#!/usr/bin/env node
// The ONLY writer of journal.ndjson.
//
// Phase scripts call this; nothing else does. A model agent has no API for
// writing a status: it can run a phase script, and the phase script writes the
// row. That asymmetry is the whole honesty stance in one file.
//
// Usage (all phase scripts go through this):
//
//   node etc/go/lib/receipt.mjs stage-begin --run DIR --stage ID --inputs-digest D
//   node etc/go/lib/receipt.mjs stage-end   --run DIR --stage ID --status S \
//        [--reason TEXT] [--blocker TEXT] [--note TEXT] \
//        [--oracle-cmd CMD --oracle-exit N --oracle-class CLASS] \
//        [--oracle-because TEXT] [--artifact PATH]... [--inputs-digest D] \
//        [--replayed-from HASH] [--replayed-from-run RUNID]
//        [--metric key=value]...
//   node etc/go/lib/receipt.mjs run-begin  --run DIR --run-id ID --milestone M --subject S ...
//   node etc/go/lib/receipt.mjs run-end    --run DIR --verdict V
//   node etc/go/lib/receipt.mjs gate       --run DIR --gate HG1 --state satisfied|waived|refused \
//        [--namespace NS] [--payload-digest D] [--corpus-digest D] \
//        [--signature-file PATH] [--reason TEXT]
//
// Exit codes: 0 written · 2 usage · 4 the receipt violates the lattice rules
// (a defect in the calling phase script, never a finding about the corpus).

import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  statSync,
} from "node:fs";
import { dirname, relative, resolve } from "node:path";
import { append, read, refold, sha256File } from "./ledger.mjs";
import { rolesFor } from "./readset.mjs";
import {
  checkClaim,
  indexRecords,
  materialise,
  put,
  storeRoot,
  writeBlessing,
} from "./store.mjs";
import { checkReceipt, EXIT } from "./verdict.mjs";

function parseArgs(argv) {
  const out = { _: [], artifact: [], note: [], metric: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith("--")) {
      out._.push(a);
      continue;
    }
    const key = a.slice(2);
    const val = argv[++i];
    if (val === undefined) {
      process.stderr.write(`receipt.mjs: --${key} needs a value\n`);
      process.exit(EXIT.USAGE);
    }
    if (key === "artifact") out.artifact.push(val);
    else if (key === "note") out.note.push(val);
    else if (key === "metric") out.metric.push(val);
    else out[key.replace(/-/g, "_")] = val;
  }
  return out;
}

/**
 * `rel` — the artifact's identity WITHIN a run, subdirectories included.
 *
 * The cross-run copy path used to flatten every artifact to its basename, so
 * two artifacts from different subdirectories overwrote each other and the
 * receipt named one file twice. Latent only because `p7-lts` has never got past
 * NOT-BUILT and `p8-diff` has never run — both write into subdirectories, so
 * the first successful `p7-lts` makes it live.
 *
 * An artifact that is NOT under the run directory is an in-tree file the stage
 * points at rather than produced (p7-ladder's committed figures). Those get
 * `tree:<repo-relative>`, so nothing tries to copy them into a run and nothing
 * records another run's absolute path as this run's artifact.
 */
function relFor(p, runDir, repoRoot) {
  const abs = resolve(p);
  if (runDir) {
    const out = resolve(runDir, "artifacts");
    const r = relative(out, abs);
    if (r && !r.startsWith("..")) return r;
  }
  if (repoRoot) {
    const r = relative(repoRoot, abs);
    if (r && !r.startsWith("..")) return `tree:${r}`;
  }
  return abs.slice(abs.lastIndexOf("/") + 1);
}

function artifactRecord(p, ctx = {}) {
  const abs = resolve(p);
  if (!existsSync(abs)) return { path: p, absent: true };
  const sha = sha256File(abs);
  const bytes = statSync(abs).size;
  const rel = relFor(p, ctx.runDir, ctx.repoRoot);
  // `cas` is a PLACE the original bytes can still be fetched; `sha256` is the
  // CLAIM this receipt made about them. Two fields because they answer
  // different questions, and because that is what upgrades `verify`'s CHANGED
  // from an accusation into a diff. null when the store was unavailable —
  // put() never throws, so a broken home directory cannot fail a good run.
  const cas = ctx.store
    ? put(ctx.store, abs, sha, { ...ctx.meta, rel, bytes })
    : null;
  return { path: p, bytes, sha256: sha, rel, cas };
}

function metricsFrom(list) {
  const m = {};
  for (const kv of list) {
    const i = kv.indexOf("=");
    if (i < 0) continue;
    m[kv.slice(0, i)] = kv.slice(i + 1);
  }
  return m;
}

const [, , kindRaw, ...rest] = process.argv;
const args = parseArgs(rest);
const kind = (kindRaw || "").replace(/-/g, "_");

if (!args.run) {
  process.stderr.write("receipt.mjs: --run DIR is required\n");
  process.exit(EXIT.USAGE);
}
const journal = resolve(args.run, "journal.ndjson");

switch (kind) {
  case "run_begin": {
    append(journal, {
      kind: "run_begin",
      run_id: args.run_id,
      milestone: args.milestone,
      subject: args.subject,
      repo_head: args.repo_head ?? null,
      tree_state: args.tree_state ?? null,
      fixed_now: args.fixed_now ?? null,
      l4_binary: args.l4_binary ?? null,
      declared_stages: (args.declared ?? "").split(",").filter(Boolean),
      // Which stages each gate gates, recorded at run_begin so a later
      // `verify --gates` can check the ORDERING — that a granted gate was
      // recorded before the first stage it gates began — without trusting the
      // driver that wrote the journal.
      gated_stages: args.gated_stages ?? null,
    });
    break;
  }

  case "stage_begin": {
    append(journal, {
      kind: "stage_begin",
      stage: args.stage,
      inputs_digest: args.inputs_digest || null,
      attempt: Number(args.attempt ?? 1),
    });
    break;
  }

  case "stage_end": {
    // On a replay, the artifact records are copied VERBATIM from the receipt
    // being replayed, not re-hashed from disk. Re-hashing would launder a file
    // that changed after the original receipt was written; copying keeps the
    // original sha256 so `go.sh verify` still compares it against what is on
    // disk now and reports CHANGED.
    const runDir = args.run ? resolve(args.run) : null;
    const repoRoot = resolve(new URL("../../..", import.meta.url).pathname);
    let store = null;
    try {
      store = storeRoot();
    } catch {
      store = null;
    }
    // R4's read-set. It arrives as a FILE rather than on argv because a corpus
    // read-set is routinely larger than ARG_MAX.
    let readSet = null;
    if (args.read_set) {
      if (!existsSync(args.read_set)) {
        process.stderr.write(
          `receipt.mjs: --read-set ${args.read_set} does not exist\n`,
        );
        process.exit(EXIT.BROKEN);
      }
      try {
        readSet = JSON.parse(readFileSync(args.read_set, "utf8"));
      } catch (e) {
        process.stderr.write(
          `receipt.mjs: --read-set is not JSON: ${e.message}\n`,
        );
        process.exit(EXIT.BROKEN);
      }
      if (!Array.isArray(readSet)) {
        process.stderr.write(
          "receipt.mjs: --read-set must be an array of members\n",
        );
        process.exit(EXIT.BROKEN);
      }
      // REFUSE A READ-SET THAT DOES NOT PROVE ITS OWN DIGEST. Same discipline
      // as refusing a receipt whose status exceeds its evidence: a read-set
      // that does not re-fold is not weak evidence about the inputs, it is a
      // claim about them already known to be false — and writing it would seal
      // that falsehood inside a hash chain, where it reads as attested.
      const proof = refold(readSet);
      if (args.inputs_digest && proof !== args.inputs_digest) {
        process.stderr.write(
          "receipt.mjs: the read-set does not re-fold to the stage's inputs digest —\n" +
            `  digest ${args.inputs_digest}\n  refold ${proof}\n`,
        );
        process.exit(EXIT.BROKEN);
      }
    }

    // R5's precondition, carried INTO THE STORE rather than left in the
    // journal. Two encodings differ interpretively only if their upstream
    // `natlang_sources` were identical; a journal answers that for about two
    // to five days, which is exactly the half-life R11 exists to escape. So the
    // fold over the natlang_sources members rides on every admission, and
    // `store diff` can still refuse to call a difference a fork long after the
    // run that produced it is gone.
    //
    // Derived, but a fact about THIS ADMISSION and fixed forever — the same
    // standing as `inputs_digest` beside it. What must never be stored is a
    // fact about HISTORY (role, freshness), because that is recomputed.
    let sourcesDigest = null;
    if (Array.isArray(readSet)) {
      // THE REAL STORE INDEX, not []. A natlang_sources member is classified
      // by the record of the stage that PRODUCED it, and for a member produced
      // by an EARLIER RUN that record lives only in the store — passing an
      // empty index made the store branch unreachable, so `sources_digest` was
      // structurally null for every cross-run case, which is the only case it
      // exists to serve. Read defensively: put() is fail-open, and admission
      // must never be blocked by an unreadable index.
      let storeIndex = [];
      try {
        if (store) storeIndex = indexRecords(store);
      } catch {
        storeIndex = [];
      }
      const roled = rolesFor(readSet, read(journal), storeIndex, repoRoot);
      const srcs = roled.filter((m) => m.role === "natlang_sources");
      // null, not the empty fold: "this witness recorded no sources" and "this
      // witness recorded sources that happened to hash to X" are different
      // claims, and conflating them would let two source-less encodings look
      // comparable — the spurious fork R5 exists to prevent.
      sourcesDigest = srcs.length ? refold(srcs) : null;
    }

    const meta = {
      subject: args.subject ?? process.env.GO_SUBJECT ?? null,
      stage: args.stage ?? null,
      run_id: args.run_id ?? process.env.GO_RUNID ?? null,
      inputs_digest: args.inputs_digest ?? null,
      produced_under: null,
      sources_digest: sourcesDigest,
    };
    const ctx = { runDir, repoRoot, store, meta };

    let artifacts;
    if (args.artifacts_from) {
      const prior = read(journal).find((r) => r.hash === args.artifacts_from);
      if (!prior) {
        process.stderr.write(
          `receipt.mjs: --artifacts-from ${args.artifacts_from} names no record in this journal\n`,
        );
        process.exit(EXIT.BROKEN);
      }
      artifacts = prior.artifacts ?? [];
    } else if (args.artifacts_json) {
      // THE CROSS-RUN PATH. The donor's records arrive as data; the bytes are
      // fetched from the store by `cas` and only fall back to whatever the
      // donor left on disk. The recorded sha256 is the DONOR'S, verbatim, never
      // re-derived from the copy — which is the rule stated a few lines above
      // and the one the old `cp` + `--artifact` route broke, because
      // `--artifact` re-hashes.
      const donors = JSON.parse(readFileSync(args.artifacts_json, "utf8"));
      artifacts = [];
      for (let d of donors) {
        if (d.absent) {
          artifacts.push({ ...d });
          continue;
        }
        const isTree = typeof d.rel === "string" && d.rel.startsWith("tree:");
        const dest = isTree
          ? resolve(repoRoot, d.rel.slice(5))
          : resolve(
              runDir,
              "artifacts",
              d.rel ?? String(d.path).split("/").pop(),
            );
        if (!isTree) {
          // Three sources, in order of how much they can be trusted:
          //
          //   1. the store, by `cas` — the original bytes, immutable (0444);
          //   2. a copy already at `dest` — a resumed run in its own directory;
          //   3. the DONOR'S directory — the pre-store path.
          //
          // (3) is not legacy cruft to be removed later. The store starts empty,
          // and every journal written before it existed carries neither `rel`
          // nor `cas`, so for as long as those runs are the ones worth borrowing
          // from — which is the first weeks after this lands — (3) is the only
          // source there is. Dropping it would turn every cross-run replay into
          // exit 4 on the day the store shipped, which would read as the store
          // having broken replay rather than having been introduced.
          let got = d.cas && store ? materialise(store, d.cas, dest) : false;
          if (!got && !existsSync(dest) && args.donor_dir) {
            const donorCopy = resolve(
              args.donor_dir,
              "artifacts",
              d.rel && !d.rel.startsWith("tree:")
                ? d.rel
                : String(d.path).split("/").pop(),
            );
            if (existsSync(donorCopy)) {
              mkdirSync(dirname(dest), { recursive: true });
              copyFileSync(donorCopy, dest);
              got = true;
            }
          }
          if (!got && !existsSync(dest)) {
            process.stderr.write(
              `receipt.mjs: cannot materialise '${d.rel ?? d.path}' for this replay.\n` +
                `  store cas: ${d.cas ?? "(none recorded — a pre-store donor)"}\n` +
                `  donor dir: ${args.donor_dir ?? "(not given)"}\n` +
                `  A borrowed receipt whose artifacts cannot be produced is not evidence; run the stage.\n`,
            );
            process.exit(EXIT.BROKEN);
          }
          // Bytes that arrived from a pre-store donor are admitted NOW, so the
          // next borrow can come from the store rather than from a directory
          // $TMPDIR reaps in two to five days.
          if (!d.cas && store && existsSync(dest)) {
            const admitted = put(store, dest, sha256File(dest), {
              ...meta,
              rel: d.rel ?? null,
              bytes: d.bytes ?? null,
            });
            if (admitted) d = { ...d, cas: admitted };
          }
        }
        // The post-materialisation assertion. If what landed is not what the
        // donor recorded, the borrow is refused rather than repaired: recording
        // the new hash as though it were the measured one is exactly the
        // laundering the comment above forbids.
        if (existsSync(dest)) {
          const actual = sha256File(dest);
          if (d.sha256 && actual !== d.sha256) {
            process.stderr.write(
              `receipt.mjs: '${d.rel}' does not match the donor receipt after materialising.\n` +
                `  receipt: ${d.sha256}\n  on disk: ${actual}\n`,
            );
            process.exit(EXIT.BROKEN);
          }
        }
        artifacts.push({
          path: dest,
          bytes: d.bytes ?? null,
          sha256: d.sha256 ?? null,
          rel: d.rel ?? null,
          cas: d.cas ?? null,
        });
      }
    } else {
      artifacts = args.artifact.map((p) => artifactRecord(p, ctx));
    }

    const receipt = {
      kind: "stage_end",
      stage: args.stage,
      status: args.status,
      reason: args.reason ?? null,
      blocker: args.blocker ?? null,
      artifacts,
      oracle: args.oracle_cmd
        ? {
            cmd: args.oracle_cmd,
            exit: Number(args.oracle_exit),
            class: args.oracle_class,
            because: args.oracle_because ?? null,
          }
        : null,
      metrics: metricsFrom(args.metric),
      notes: args.note.map((text) => ({
        text,
        author: args.author ?? "phase-script",
        verified: false,
      })),
      inputs_digest: args.inputs_digest || null,
      // R4. The read-set lives HERE, on the receipt, beside the fold it proves
      // — not on `stage_begin`, which also carries the digest. One home, and
      // this is the row that always exists: a REPLAYED stage writes no
      // `stage_begin` at all (it never began; claiming otherwise would be a
      // receipt exceeding its evidence), yet its inputs are exactly as worth
      // recording, because R8 says a run directory must be answerable on its
      // own by someone holding only that directory.
      read_set: readSet,
      attempt: Number(args.attempt ?? 1),
      replayed_from: args.replayed_from ?? null,
      // The RUN the borrowed receipt came from. null means the same run — the
      // ordinary resume case, where the evidence is a few lines up in this very
      // journal. A value means the evidence was earned in ANOTHER run over a
      // byte-identical inputs digest, and the report must say so rather than
      // claim it is "on this journal": a reader who wants to check it has to be
      // told where to look.
      replayed_from_run: args.replayed_from_run ?? null,
      label: args.label ?? null,
    };

    // WHICH GATE GATES THIS STAGE, and what blessing is open for it — both
    // DERIVED, neither accepted from the caller.
    //
    // receipt.mjs is the only writer of a status precisely so that no caller can
    // assert one it did not earn. A `--blessing` flag would re-open exactly that
    // asymmetry for any phase script, debug flag or future agent. run_begin's
    // `gated_stages` is already the field verify-run.mjs trusts instead of the
    // driver, and the granting gate row is in the same hash-chained journal, so
    // the derivation needs no new channel and a second party can recompute it.
    const rows = read(journal);
    const begin = rows.find((x) => x.kind === "run_begin");
    let gatedBy = null;
    try {
      const gs =
        typeof begin?.gated_stages === "string"
          ? JSON.parse(begin.gated_stages)
          : (begin?.gated_stages ?? {});
      for (const [g, list] of Object.entries(gs))
        if (Array.isArray(list) && list.includes(args.stage)) gatedBy = g;
    } catch {
      gatedBy = null;
    }
    if (gatedBy) {
      const granting = rows
        .filter(
          (x) =>
            x.kind === "gate" &&
            x.gate === gatedBy &&
            (x.state === "satisfied" || x.state === "waived"),
        )
        .at(-1);
      receipt.produced_under = granting
        ? {
            blessing: granting.blessing ?? null,
            gate: gatedBy,
            state: granting.state,
            corpus_digest: granting.corpus_digest ?? null,
            reason: granting.reason ?? null,
          }
        : null;
    } else {
      receipt.produced_under = null;
    }
    // The artifacts were admitted before `produced_under` was known, so the
    // index records carry a null. Re-admit them under the blessing: put() is
    // idempotent on the bytes and appends a fresh index record, which is
    // exactly the per-admission provenance the store is for.
    if (receipt.produced_under && ctx.store)
      for (const a of receipt.artifacts ?? [])
        if (a.sha256 && a.path && existsSync(a.path))
          put(ctx.store, a.path, a.sha256, {
            ...meta,
            rel: a.rel ?? null,
            bytes: a.bytes ?? null,
            produced_under: receipt.produced_under,
          });

    const violations = checkReceipt(receipt, { gated: gatedBy });
    if (violations.length) {
      process.stderr.write(
        `receipt.mjs: REFUSED the receipt for stage '${args.stage}' —\n`,
      );
      for (const v of violations) process.stderr.write(`  - ${v}\n`);
      process.stderr.write(
        "This is a defect in the phase script that called receipt.mjs, not a finding about the corpus. Exit 4 (BROKEN).\n",
      );
      process.exit(EXIT.BROKEN);
    }
    // A phase script may not name an artifact it did not produce.
    const absent = receipt.artifacts.filter((a) => a.absent);
    if (absent.length && receipt.status === "PASS") {
      process.stderr.write(
        `receipt.mjs: REFUSED — PASS naming artifacts that are not on disk: ${absent.map((a) => a.path).join(", ")}\n`,
      );
      process.exit(EXIT.BROKEN);
    }
    const rec = append(journal, receipt);
    process.stdout.write(
      `${rec.stage}: ${rec.status}${rec.replayed_from ? " (replayed)" : ""}\n`,
    );
    break;
  }

  case "gate": {
    // THE BLESSING GOES TO THE LEDGER FIRST, THEN THE JOURNAL.
    //
    // Ordering is fail-closed on purpose. A crash between the two leaves an
    // orphan record in the ledger and NO gate row in the journal, so the gate
    // stays shut and the run refuses. The reverse order would leave a gate row
    // citing a blessing that does not exist — a run that believes it is blessed
    // by nothing.
    //
    // Why the ledger at all, when the journal already has a gate row: the
    // journal lives in $TMPDIR. Measured 2026-08-20 — 76 of 92 run directories
    // are already empty shells and files last two to five days. A signature
    // recorded only there expires in under a week, silently. The ledger is the
    // one thing in this system that is never swept.
    let blessingId = null;
    if (
      args.state === "satisfied" ||
      args.state === "waived" ||
      args.state === "refused"
    ) {
      let store = null;
      try {
        store = storeRoot();
      } catch {
        store = null;
      }
      const covers = args.covers_from
        ? JSON.parse(readFileSync(args.covers_from, "utf8"))
        : [];
      const sigPath = args.signature_file;
      const signature =
        sigPath && existsSync(sigPath)
          ? readFileSync(sigPath).toString("base64")
          : null;
      const rec = {
        kind: "blessing",
        subject: args.subject ?? process.env.GO_SUBJECT ?? null,
        gate: args.gate,
        state: args.state,
        corpus_digest: args.corpus_digest ?? null,
        covers,
        namespace: args.namespace ?? null,
        payload_digest: args.payload_digest ?? null,
        signer: args.signer ?? null,
        // EMBEDDED, not a path. signature_file points into $RUN, which gc
        // deletes; a signature that does not survive its run directory is not
        // a first-class edge.
        signature,
        reason: args.reason ?? null,
        granted_in_run: args.run_id ?? process.env.GO_RUNID ?? null,
        ts: new Date().toISOString(),
      };
      const claim = checkClaim(rec);
      if (!claim.ok) {
        process.stderr.write(
          `receipt.mjs: REFUSED the ${args.gate} blessing —\n` +
            claim.problems.map((p) => `  - ${p}\n`).join("") +
            `A blessing record is permanent: nothing sweeps the ledger. Exit 4 (BROKEN).\n`,
        );
        process.exit(EXIT.BROKEN);
      }
      if (store) {
        // The reviewed BYTES are admitted, so "show me what was blessed" is a
        // fetch and not a name — independent of git history and of the file
        // still being at that path.
        for (const m of covers)
          if (m.sha256 && m.path && existsSync(m.path))
            put(store, m.path, m.sha256, {
              subject: rec.subject,
              stage: "covers",
              rel: `tree:${m.path}`,
              bytes: m.bytes ?? null,
            });
        try {
          blessingId = writeBlessing(store, rec).hash;
        } catch (e) {
          process.stderr.write(
            `receipt.mjs: could not write the blessing: ${e.message}\n`,
          );
          process.exit(EXIT.BROKEN);
        }
      }
    }
    append(journal, {
      kind: "gate",
      // The ledger record this row corresponds to. null when the store was
      // unavailable — the gate still works, it just is not durable.
      blessing: blessingId,
      gate: args.gate,
      state: args.state, // satisfied | waived | refused
      namespace: args.namespace ?? null,
      payload_digest: args.payload_digest ?? null,
      // The sha256 over the corpus files this gate was granted over. A
      // SIGNATURE binds to content by construction (gate-payload.mjs hashes
      // every corpus file and gate-verify.sh rebuilds the payload each time); a
      // WAIVER bound to nothing, so one waiver covered every later encoding
      // change in the run — and since `gate-allowed-signers` ships with no key,
      // the waiver is the only route anyone can take. go.sh records this at the
      // moment of the waiver and re-checks it before every gated stage, which
      // is what makes "a post-gate edit re-opens the gate" true of the shipped
      // configuration rather than only of the signed one.
      corpus_digest: args.corpus_digest ?? null,
      signer: args.signer ?? null,
      signature_file: args.signature_file ?? null,
      reason: args.reason ?? null,
    });
    break;
  }

  case "run_end": {
    append(journal, {
      kind: "run_end",
      verdict: args.verdict,
      exit: Number(args.exit ?? 0),
    });
    break;
  }

  default:
    process.stderr.write(`receipt.mjs: unknown record kind '${kindRaw}'\n`);
    process.exit(EXIT.USAGE);
}

#!/usr/bin/env node
// The store's command surface. Dispatched by `etc/go/go.sh store <verb>`.
//
//   ls      [--subject S] [--stage S]   what the store holds
//   cat     <sha256> [--allow-waived]   write an object's bytes to stdout
//   diff    [--subject S] [--stage S]   WITNESSES THAT DISAGREE — see below
//   gc      [--keep-days N] [--dry-run] sweep unreachable objects
//   verify                              the ledger chain, and every claim in it
//
// `diff` is R6's actual deliverable. The ruling says artifacts are witnesses
// whose disagreement is the product: a non-deterministic producer means two
// runs over identical inputs yield DIFFERENT artifacts, and that difference is
// the finding rather than the waste. The witness key is
// (stage, inputs_digest, rel) — same phase, same declared inputs, same slot —
// so any group holding more than one distinct sha256 is a producer that did not
// converge over inputs the pipeline considers identical.
import {
  existsSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
} from "node:fs";
import { join } from "node:path";
import { classOf } from "./readset.mjs";
import {
  checkClaim,
  indexRecords,
  objectPath,
  readBlessings,
  servability,
  storeRoot,
  verifyBlessings,
} from "./store.mjs";

const EXIT = { CLEAN: 0, FINDING: 1, USAGE: 2, REFUSED: 3 };
const [verb, ...rest] = process.argv.slice(2);
const flag = (name) => {
  const i = rest.indexOf(`--${name}`);
  return i === -1 ? undefined : rest[i + 1];
};
const bool = (name) => rest.includes(`--${name}`);
const root = storeRoot();

function die(msg, code = EXIT.USAGE) {
  process.stderr.write(`store: ${msg}\n`);
  process.exit(code);
}

if (!existsSync(root) && verb !== "verify")
  die(
    `no store at ${root}.\n` +
      `  It is created by the first run that produces an artifact. Nothing is wrong;\n` +
      `  there is simply nothing recorded yet.`,
    EXIT.CLEAN,
  );

switch (verb) {
  case "ls": {
    const recs = indexRecords(root, {
      subject: flag("subject"),
      stage: flag("stage"),
    });
    for (const r of recs)
      process.stdout.write(
        `${r.sha256.slice(7, 19)}  ${String(r.bytes).padStart(9)}  ` +
          `${r.subject ?? "-"}/${r.stage ?? "-"}  ${r.rel ?? "-"}\n`,
      );
    process.stdout.write(`${recs.length} admission(s)\n`);
    break;
  }

  case "cat": {
    if (!rest[0]) die("cat needs a sha256");
    const sha = rest[0].startsWith("sha256:") ? rest[0] : `sha256:${rest[0]}`;
    const s = servability(root, sha);
    // DEFAULT DENY. An artifact from an ungated stage, a refused run, or any
    // run older than the store has no blessing, and serving it would be exactly
    // R11's failure: a confident answer traced to an encoding nobody reviewed.
    if (!s.servable && !(s.state === "waived" && bool("allow-waived"))) {
      process.stderr.write(
        `store: refusing to serve ${sha.slice(0, 19)} — ${s.state}: ${s.reason ?? ""}\n` +
          (s.state === "waived"
            ? "  It was produced under a WAIVER, not a signature. Pass --allow-waived to serve it\n" +
              "  anyway; the waiver's reason is above and belongs in whatever you say about the result.\n"
            : ""),
      );
      process.exit(EXIT.REFUSED);
    }
    if (s.state === "waived")
      process.stderr.write(
        `store: serving under a WAIVED gate — ${s.reason}\n`,
      );
    const p = objectPath(root, sha);
    if (!existsSync(p))
      die(`object ${sha.slice(0, 19)} is indexed but absent`, EXIT.FINDING);
    process.stdout.write(readFileSync(p));
    break;
  }

  case "diff": {
    const recs = indexRecords(root, {
      subject: flag("subject"),
      stage: flag("stage"),
    });
    const groups = new Map();
    for (const r of recs) {
      if (!r.stage || !r.inputs_digest) continue;
      const key = `${r.stage} ${r.inputs_digest} ${r.rel ?? ""}`;
      if (!groups.has(key)) groups.set(key, new Map());
      const bySha = groups.get(key);
      if (!bySha.has(r.sha256)) bySha.set(r.sha256, []);
      bySha.get(r.sha256).push(r);
    }
    let divergent = 0;
    for (const [key, bySha] of [...groups.entries()].sort()) {
      if (bySha.size < 2) continue;
      divergent++;
      const [stage, dig, rel] = key.split(" ");
      process.stdout.write(
        `\nDIVERGENT  ${stage}  ${rel || "(no rel)"}  inputs ${dig.slice(7, 19)}\n`,
      );
      for (const [sha, admissions] of bySha) {
        const runs = [...new Set(admissions.map((a) => a.run_id))].join(", ");
        process.stdout.write(
          `  ${sha.slice(7, 19)}  ${String(admissions[0].bytes).padStart(9)}  runs: ${runs}\n`,
        );
      }
      // SELF-REFERENTIAL, labelled and never filtered.
      //
      // Some artifacts embed the absolute path of the run that produced them
      // (p0-preflight's tripwire.json does), so they are a function of the run
      // id and never of the inputs: they can never dedupe and always appear
      // here. Labelling keeps the true findings readable; filtering would hide
      // a real one the day the heuristic is wrong. The substring that triggered
      // the label is named, so a reader can overrule it in a glance.
      const marks = [];
      for (const [sha, admissions] of bySha) {
        const p = objectPath(root, sha);
        if (!existsSync(p)) continue;
        let text = "";
        try {
          text = readFileSync(p, "utf8").slice(0, 200000);
        } catch {
          continue;
        }
        const rid = admissions[0].run_id;
        if (rid && text.includes(rid))
          marks.push(`${sha.slice(7, 19)} contains "${rid}"`);
      }
      if (marks.length === bySha.size && marks.length > 0)
        process.stdout.write(
          "  SELF-REFERENTIAL: every witness embeds its own run id, so this pair is a\n" +
            `  function of the run and not of the inputs — ${marks.join("; ")}\n`,
        );

      // R5. A UNIFORM "diff the artifacts" LAYER WOULD MISLABEL THREE DIFFERENT
      // EVENTS, so each divergence is read through the class of the phase that
      // produced it. The phase class is intrinsic — what the stage does — which
      // is why it can be named at all (§3.3).
      const cls = classOf(stage);
      if (cls === "natlang_sources")
        process.stdout.write(
          "  CURRENCY EVENT: the fetched text moved — the law changed, or the publisher\n" +
            "  revised it. This is NOT a fork, and nothing about the encoding is implicated.\n",
        );
      else if (cls === "research")
        process.stdout.write(
          "  SWEEP FINDING: new authority surfaced. Routes to the external-modification\n" +
            "  register, not to the fork register.\n",
        );
      else if (cls === "encode") {
        // THE LOAD-BEARING CONSTRAINT ON THE WHOLE COMPARISON LAYER: an encoding
        // diff is an interpretive fork ONLY IF the upstream read-sets matched.
        // Otherwise it is two encodings of two different texts, and calling
        // their difference a fork is spurious.
        // EVERY admission of each sha, not just the first. The same bytes can
        // be admitted by two runs that read DIFFERENT sources — a later run
        // re-deriving an identical encoding from revised text — and reading
        // only `a[0]` would report whichever admission happened to be
        // earliest, hiding a genuine disagreement about what the encoding
        // rests on.
        //
        // A sha whose admissions disagree about their sources contributes no
        // single answer, so it folds in as `null`: unknown, which forces NOT
        // ESTABLISHED rather than a guess in either direction.
        const digs = [...bySha.values()].map((admissions) => {
          const seen = new Set(admissions.map((a) => a.sources_digest ?? null));
          return seen.size === 1 ? [...seen][0] : null;
        });
        const known = digs.filter(Boolean);
        if (known.length !== digs.length)
          process.stdout.write(
            "  NOT ESTABLISHED as a fork: at least one witness recorded no natlang_sources\n" +
              "  read-set, so there is no evidence the two encodings rest on the same text.\n" +
              "  Absence of evidence is not comparability — see R5.\n",
          );
        else if (new Set(known).size === 1)
          process.stdout.write(
            "  INTERPRETIVE FORK: identical upstream sources, different L4. This is the\n" +
              "  fork register's actual subject.\n",
          );
        else
          process.stdout.write(
            "  NOT A FORK: the witnesses encode DIFFERENT source text (their natlang_sources\n" +
              "  differ), so their difference is a currency event one level up.\n",
          );
      }
    }
    process.stdout.write(
      `\n${groups.size} witness key(s), ${divergent} divergent\n` +
        (divergent === 0
          ? "Every phase that ran twice over identical declared inputs produced identical bytes.\n"
          : "A divergent key is a producer that did not converge over inputs the pipeline calls identical.\n"),
    );
    process.exit(divergent > 0 ? EXIT.FINDING : EXIT.CLEAN);
  }

  case "gc": {
    const keepDays = Number(flag("keep-days") ?? 90);
    const dry = bool("dry-run");
    // REACHABILITY, not age alone. Two roots, and the first must never shrink:
    // blessed bytes and every covers[] member are what R11 exists to keep
    // fetchable, so no age policy may reach them.
    const roots = new Set();
    for (const b of readBlessings(root))
      for (const m of b.covers ?? []) if (m.sha256) roots.add(m.sha256);
    for (const r of indexRecords(root)) {
      const s = servability(root, r.sha256);
      if (s.state === "satisfied" || s.state === "waived") roots.add(r.sha256);
    }
    const cutoff = Date.now() - keepDays * 86400000;
    let swept = 0;
    let kept = 0;
    const objDir = join(root, "objects");
    if (existsSync(objDir))
      for (const aa of readdirSync(objDir)) {
        const d = join(objDir, aa);
        if (!statSync(d).isDirectory()) continue;
        for (const hex of readdirSync(d)) {
          const sha = `sha256:${hex}`;
          const p = join(d, hex);
          if (roots.has(sha) || statSync(p).mtimeMs >= cutoff) {
            kept++;
            continue;
          }
          if (!dry) rmSync(p, { force: true });
          swept++;
          process.stdout.write(
            `${dry ? "would sweep" : "swept"} ${sha.slice(7, 19)}\n`,
          );
        }
      }
    process.stdout.write(
      `store gc: kept ${kept} object(s) (blessed or newer than ${keepDays}d), ` +
        `${dry ? "would sweep" : "swept"} ${swept}\n` +
        "Blessed bytes and every covers[] member are unreachable by any age policy.\n",
    );
    break;
  }

  case "verify": {
    if (!existsSync(root)) {
      process.stdout.write(
        `store verify: no store at ${root}; nothing to check\n`,
      );
      break;
    }
    const chain = verifyBlessings(root);
    const problems = [...chain.problems];
    // Every claim re-checked, not just the chain. A chain proves nobody edited
    // a record; checkClaim proves the record was worth writing.
    for (const b of readBlessings(root))
      for (const p of checkClaim(b).problems)
        problems.push(`blessing ${b.seq}: ${p}`);
    // EVERYTHING SERVABLE MUST BE FETCHABLE. That is the invariant, and it is
    // narrower than "every index record has bytes" on purpose: `store gc`
    // deliberately sweeps unblessed objects and leaves their index records
    // behind, because the index is per-admission provenance and is rebuildable
    // while the bytes are not worth keeping. Flagging those would make the
    // normal outcome of gc look like corruption — and a check that cries wolf
    // after a routine sweep is a check somebody deletes.
    //
    // A BLESSED object whose bytes are gone is a real finding: something reached
    // past the reachability roots, which is the one thing R11 needs to hold.
    let missing = 0;
    for (const r of indexRecords(root)) {
      if (existsSync(objectPath(root, r.sha256))) continue;
      const st = servability(root, r.sha256);
      if (st.state === "satisfied" || st.state === "waived") missing++;
    }
    if (missing)
      problems.push(
        `${missing} BLESSED object(s) are absent from objects/ — something swept past the ` +
          "reachability roots. Blessed bytes and covers[] members are what the store exists to keep fetchable.",
      );
    if (problems.length) {
      process.stderr.write(
        `store verify: ${problems.length} problem(s) —\n` +
          problems.map((p) => `  - ${p}\n`).join(""),
      );
      process.exit(EXIT.FINDING);
    }
    process.stdout.write(
      `store verify: ${chain.count} blessing(s), chain intact, every claim ` +
        "well-formed; every indexed object present\n",
    );
    break;
  }

  default:
    die(`unknown verb '${verb ?? ""}'; expected ls | cat | diff | gc | verify`);
}

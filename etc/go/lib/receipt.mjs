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
//        [--replayed-from HASH] [--metric key=value]...
//   node etc/go/lib/receipt.mjs run-begin  --run DIR --run-id ID --milestone M --subject S ...
//   node etc/go/lib/receipt.mjs run-end    --run DIR --verdict V
//   node etc/go/lib/receipt.mjs gate       --run DIR --gate HG1 --state satisfied|waived|refused ...
//
// Exit codes: 0 written · 2 usage · 4 the receipt violates the lattice rules
// (a defect in the calling phase script, never a finding about the corpus).

import { existsSync, statSync } from "node:fs";
import { resolve } from "node:path";
import { append, sha256File } from "./ledger.mjs";
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

function artifactRecord(p) {
  const abs = resolve(p);
  if (!existsSync(abs)) return { path: p, absent: true };
  return { path: p, bytes: statSync(abs).size, sha256: sha256File(abs) };
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
    });
    break;
  }

  case "stage_begin": {
    append(journal, {
      kind: "stage_begin",
      stage: args.stage,
      inputs_digest: args.inputs_digest ?? null,
      attempt: Number(args.attempt ?? 1),
    });
    break;
  }

  case "stage_end": {
    const receipt = {
      kind: "stage_end",
      stage: args.stage,
      status: args.status,
      reason: args.reason ?? null,
      blocker: args.blocker ?? null,
      artifacts: args.artifact.map(artifactRecord),
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
      inputs_digest: args.inputs_digest ?? null,
      attempt: Number(args.attempt ?? 1),
      replayed_from: args.replayed_from ?? null,
      label: args.label ?? null,
    };

    const violations = checkReceipt(receipt);
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
    append(journal, {
      kind: "gate",
      gate: args.gate,
      state: args.state, // satisfied | waived | refused
      namespace: args.namespace ?? null,
      payload_digest: args.payload_digest ?? null,
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

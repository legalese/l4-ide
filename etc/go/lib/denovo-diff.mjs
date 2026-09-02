#!/usr/bin/env node
// The §8 diff oracle: the acceptance comparator for milestone G2.
//
// SPEC.md §8 asks for a diff between a de novo encoding and the committed
// corpus, in which agreements validate both encodings and disagreements are
// triaged three ways. This is the machine half of that: it measures agreement
// and produces minimised divergence witnesses. It NEVER triages — encoding
// error vs genuine ambiguity vs improvement-over-corpus is a judgement, and
// judgement lives in the skill (ORCHESTRATOR.md §2.1). Every divergence row
// leaves this script with disposition UNTRIAGED.
//
// BEHAVIOURAL FIRST, TEXTUAL SECOND. Two L4 encodings of one statute share
// almost no names and no structure, so a textual diff answers a question
// nobody asked. The spine here is: declared pairing (surface-map.schema.json)
// -> shared fact battery -> pairwise evaluation -> answer comparison.
//
// HOW IT EVALUATES. Not `l4 batch`: batch re-emits the module through
// `prettyLayout` of the *directive-filtered* AST (jl4/app/L4/Cli/Batch.hs:206-207)
// and that re-emission does not re-parse for the Reg CF façade — measured
// 2026-08-02, `l4 batch jl4/examples/legal/regcf/regcf-wizard.l4 -e 'raise check'`
// dies on `incorrect indentation (got 75, should be greater than 180)` at a line
// of the module it was handed. (`l4 format` on the same file DOES round-trip, so
// the defect is batch's pretty-layout path, not the formatter.) Batch also
// requires @export, and `jl4/examples/legal/regcf/regcf.l4` declares none.
//
// So the oracle borrows batch's *wrapper* idea and drops its re-emission: it
// writes a probe module that IMPORTs the module under test, declares one
// `GoArgs` record per pair signature, decodes each battery row with JSONDECODE,
// and emits one `#EVAL` per (pair, row). `l4 run --json` then answers all of
// them in one process. The module under test is never rewritten, never
// formatted, and never even opened by this script except to be copied.
//
// Usage:
//   node etc/go/lib/denovo-diff.mjs validate --map MAP.json [--root DIR]
//   node etc/go/lib/denovo-diff.mjs battery  --map MAP.json [--root DIR] [--out DIR]
//   node etc/go/lib/denovo-diff.mjs run      --map MAP.json [--root DIR] [--out DIR]
//                                            [--fixed-now ISO8601] [--chunk N]
//                                            [--max-rows N] [--keep-probes]
//
// Exit: 0 ran, zero divergences (agreement is total)
//       1 ran, at least one divergence — a FINDING, not a failure
//       2 usage / an invalid map
//       4 BROKEN — a harness or CLI-shape defect, never a finding about either
//         encoding (a probe that will not typecheck, a cases key that will not
//         un-sanitise, an `l4 run` that answered nothing)

import { spawnSync } from "node:child_process";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_DEFAULT = resolve(HERE, "../../..");
const SCHEMA_PATH =
  "specs/todo/single-instruction-demo/schemas/surface-map.schema.json";

const EXIT_CLEAN = 0;
const EXIT_FINDING = 1;
const EXIT_USAGE = 2;
const EXIT_BROKEN = 4;

class Broken extends Error {}
class Usage extends Error {}

// ---------------------------------------------------------------------------
// A JSON Schema subset evaluator.
//
// No dependencies are available here (node + the prebuilt l4, nothing else), and
// hand-writing a validator that mirrors the schema would give two sources of
// truth that drift apart in opposite directions. So the schema file stays
// authoritative and this reads it. It supports exactly the keywords
// surface-map.schema.json uses; an unknown keyword is IGNORED, which is the
// dangerous direction, so `assertSupported` below refuses a schema that uses
// one. That check is what keeps "the schema tightened but nothing got stricter"
// from happening silently.
// ---------------------------------------------------------------------------

const SUPPORTED = new Set([
  "$schema",
  "$id",
  "$defs",
  "$ref",
  "title",
  "description",
  "default",
  "type",
  "const",
  "enum",
  "pattern",
  "required",
  "properties",
  "additionalProperties",
  "propertyNames",
  "minProperties",
  "items",
  "minItems",
  "minimum",
  "oneOf",
]);

export function assertSupported(schema, path = "#") {
  if (!schema || typeof schema !== "object") return;
  for (const k of Object.keys(schema)) {
    if (!SUPPORTED.has(k))
      throw new Broken(
        `${SCHEMA_PATH}${path}: keyword '${k}' is not implemented by the validator in etc/go/lib/denovo-diff.mjs. ` +
          `Ignoring it would let a tightened schema stop tightening anything. Implement it or remove it.`,
      );
  }
  for (const [k, v] of Object.entries(schema.properties || {}))
    assertSupported(v, `${path}/properties/${k}`);
  for (const [k, v] of Object.entries(schema.$defs || {}))
    assertSupported(v, `${path}/$defs/${k}`);
  if (schema.items) assertSupported(schema.items, `${path}/items`);
  if (typeof schema.additionalProperties === "object")
    assertSupported(
      schema.additionalProperties,
      `${path}/additionalProperties`,
    );
  for (const [i, v] of (schema.oneOf || []).entries())
    assertSupported(v, `${path}/oneOf/${i}`);
}

const typeOf = (v) =>
  v === null
    ? "null"
    : Array.isArray(v)
      ? "array"
      : Number.isInteger(v)
        ? "integer"
        : typeof v === "number"
          ? "number"
          : typeof v;

const typeMatches = (want, v) => {
  const t = typeOf(v);
  if (want === "number") return t === "number" || t === "integer";
  return want === t;
};

export function validateAgainstSchema(schema, doc, root = schema) {
  const errs = [];
  const walk = (s, v, path) => {
    if (s.$ref) {
      const key = s.$ref.replace(/^#\/\$defs\//, "");
      const target = (root.$defs || {})[key];
      if (!target) {
        errs.push(`${path}: unresolvable $ref ${s.$ref}`);
        return;
      }
      walk(target, v, path);
      return;
    }
    if (s.oneOf) {
      const ok = s.oneOf.filter((sub) => {
        const before = errs.length;
        walk(sub, v, path);
        const clean = errs.length === before;
        errs.length = before;
        return clean;
      });
      if (ok.length === 0)
        errs.push(`${path}: matches none of the oneOf forms`);
      return;
    }
    if (s.const !== undefined && v !== s.const)
      errs.push(
        `${path}: must be ${JSON.stringify(s.const)}, got ${JSON.stringify(v)}`,
      );
    if (s.enum && !s.enum.includes(v))
      errs.push(
        `${path}: must be one of ${s.enum.join(" | ")}, got ${JSON.stringify(v)}`,
      );
    if (s.type !== undefined) {
      const want = Array.isArray(s.type) ? s.type : [s.type];
      if (!want.some((w) => typeMatches(w, v))) {
        errs.push(`${path}: must be ${want.join(" or ")}, got ${typeOf(v)}`);
        return;
      }
    }
    if (typeof v === "string" && s.pattern && !new RegExp(s.pattern).test(v))
      errs.push(`${path}: must match /${s.pattern}/, got ${JSON.stringify(v)}`);
    if (typeof v === "number" && s.minimum !== undefined && v < s.minimum)
      errs.push(`${path}: must be >= ${s.minimum}`);
    if (Array.isArray(v)) {
      if (s.minItems !== undefined && v.length < s.minItems)
        errs.push(`${path}: needs at least ${s.minItems} item(s)`);
      if (s.items) v.forEach((item, i) => walk(s.items, item, `${path}[${i}]`));
      return;
    }
    if (v && typeof v === "object" && !Array.isArray(v)) {
      for (const r of s.required || [])
        if (!(r in v)) errs.push(`${path}: missing required key '${r}'`);
      if (
        s.minProperties !== undefined &&
        Object.keys(v).length < s.minProperties
      )
        errs.push(`${path}: needs at least ${s.minProperties} propert(ies)`);
      for (const [k, val] of Object.entries(v)) {
        const sub = (s.properties || {})[k];
        if (sub) {
          walk(sub, val, `${path}/${k}`);
        } else if (s.additionalProperties === false) {
          errs.push(
            `${path}: unknown key '${k}' (refuse-by-default; add it to the schema or delete it)`,
          );
        } else if (typeof s.additionalProperties === "object") {
          walk(s.additionalProperties, val, `${path}/${k}`);
        }
      }
    }
  };
  walk(schema, doc, "");
  return errs;
}

// ---------------------------------------------------------------------------
// CLI adapters. Every fact about a module is read back out of the l4 binary,
// never out of its source text (the one exception is `staging`, which copies
// bytes and reads nothing).
// ---------------------------------------------------------------------------

const L4 = () => process.env.L4 || "l4";

function l4(args, opts = {}) {
  const r = spawnSync(L4(), args, {
    encoding: "utf8",
    maxBuffer: 1 << 28,
    ...opts,
  });
  if (r.error)
    throw new Broken(
      `could not run ${L4()} ${args.join(" ")}: ${r.error.message}. ` +
        `Set $L4 to a prebuilt binary; this orchestrator never builds one.`,
    );
  return { status: r.status, out: r.stdout || "", err: r.stderr || "" };
}

/**
 * The module's own surface, as the CLI reports it: every non-imported rule
 * heading (the decision surface a pair may name) and every non-imported record
 * type with its field labels (the dictionary used to un-sanitise DMN case keys).
 */
export function readSurface(modulePath, fixedNow) {
  const { status, out, err } = l4([
    "render",
    modulePath,
    "--format",
    "json",
    "--include-unused",
    "--fixed-now",
    fixedNow,
  ]);
  if (status !== 0)
    throw new Broken(
      `l4 render --format json failed on ${modulePath} (exit ${status}):\n${(out + err).slice(0, 2000)}`,
    );
  let doc;
  try {
    doc = JSON.parse(out);
  } catch (e) {
    throw new Broken(
      `l4 render --format json did not emit JSON for ${modulePath}. ` +
        `The CLI's render shape changed; re-verify etc/go/lib/denovo-diff.mjs. Saw:\n${out.slice(0, 400)}`,
    );
  }
  const rules = [];
  const types = {};
  (function walk(o) {
    if (!o || typeof o !== "object") return;
    if (
      o.kind === "rule" &&
      typeof o.heading === "string" &&
      o.imported === false
    )
      rules.push(o.heading);
    if (
      o.kind === "type" &&
      typeof o.heading === "string" &&
      o.imported === false
    ) {
      if (o.body && o.body.$type === "fields" && Array.isArray(o.body.fields))
        types[o.heading] = o.body.fields.map((f) => f.label);
      else types[o.heading] = null; // an enum / non-record type
    }
    for (const k of Object.keys(o)) walk(o[k]);
  })(doc);
  if (rules.length === 0)
    throw new Broken(
      `l4 render --format json enumerated no rules for ${modulePath}. ` +
        `Either the module declares none, or the render shape moved.`,
    );
  return { rules: [...new Set(rules)], types };
}

/**
 * Is `name` an @export entrypoint of this module? Advisory only — it colours
 * the coverage note, and never licenses or withholds an agreement.
 *
 * The probe is `l4 batch … --validate-only` against an empty row: entrypoint
 * resolution happens strictly before row validation
 * (jl4/app/L4/Cli/Batch.hs:201 vs :213), so a name that is not exported answers
 * `no @export function named '…' found` and any other answer means it is.
 */
export function isExported(modulePath, name, scratchDir) {
  const empty = join(scratchDir, "empty-row.json");
  if (!existsSync(empty)) writeFileSync(empty, "[{}]\n");
  const { out, err } = l4([
    "batch",
    modulePath,
    "-i",
    empty,
    "--input-format",
    "json",
    "-e",
    name,
    "--validate-only",
  ]);
  return !/no @export function named/.test(out + err);
}

// ---------------------------------------------------------------------------
// Staging. Each side gets its own scratch directory holding a copy of the
// module and its sibling .l4 files, so importer-relative resolution works and
// the two sides cannot collide on a basename (a de novo encoding of Reg CF is
// very likely also called regcf.l4). JL4_LIBRARY_PATH is a single directory,
// not a list — measured — so it stays pointed at the stdlib.
// ---------------------------------------------------------------------------

const PROBE_STEM = "go-denovo-probe";

function stageSide(root, side, dir) {
  mkdirSync(dir, { recursive: true });
  const modAbs = resolve(root, side.module);
  if (!existsSync(modAbs))
    throw new Usage(
      `sides.${side._which}.module does not exist: ${side.module}`,
    );
  const srcDir = dirname(modAbs);
  const staged = [];
  for (const f of readdirSync(srcDir)) {
    if (extname(f) !== ".l4") continue;
    const p = join(srcDir, f);
    if (!statSync(p).isFile()) continue;
    copyFileSync(p, join(dir, f));
    staged.push(f);
  }
  for (const extra of side.stage || []) {
    const p = resolve(root, extra);
    if (!existsSync(p))
      throw new Usage(
        `sides.${side._which}.stage names a missing file: ${extra}`,
      );
    copyFileSync(p, join(dir, basename(p)));
    staged.push(basename(p));
  }
  const moduleName = basename(modAbs, ".l4");
  // An L4 file cannot IMPORT a library sharing its own basename — the failure
  // is a silent GraphException, not a "not found". The probe stem is fixed and
  // deliberately not a plausible corpus name, but check anyway.
  if (staged.includes(`${PROBE_STEM}.l4`))
    throw new Usage(
      `${side.module}'s directory already contains ${PROBE_STEM}.l4; the probe would collide with it.`,
    );
  return { dir, moduleName, staged, modulePath: join(dir, basename(modAbs)) };
}

// ---------------------------------------------------------------------------
// The battery.
// ---------------------------------------------------------------------------

/**
 * The DMN exporter's name sanitiser, as observed in
 * jl4/examples/dmn/regcf-corpus.cases.json against the type dictionary
 * `l4 render` reports: every run of non-alphanumerics becomes one underscore,
 * and leading/trailing underscores are trimmed. Verified 2026-08-02 to map all
 * 9 record-shaped context entries of that file onto declared types with zero
 * unmatched keys.
 *
 * It is not invertible, so the oracle never inverts it: it sanitises the
 * DECLARED field labels and matches forward. A case key with no match, or two
 * labels sanitising to one key, is a hard error.
 */
export const sanitiseFieldName = (s) =>
  String(s)
    .replace(/[^A-Za-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");

function unsanitiseRecord(caseValue, labels, where) {
  const fwd = new Map();
  for (const label of labels) {
    const k = sanitiseFieldName(label);
    if (fwd.has(k))
      throw new Broken(
        `${where}: two declared fields sanitise to the same key '${k}' — ` +
          `'${fwd.get(k)}' and '${label}'. The cases file cannot be un-sanitised unambiguously.`,
      );
    fwd.set(k, label);
  }
  const out = {};
  for (const [k, v] of Object.entries(caseValue)) {
    const label = fwd.get(k);
    if (!label)
      throw new Broken(
        `${where}: case key '${k}' does not un-sanitise onto any declared field. ` +
          `Declared: ${labels.map(sanitiseFieldName).slice(0, 8).join(", ")}${labels.length > 8 ? ", …" : ""}. ` +
          `Either the sanitiser changed or the slot names the wrong type.`,
      );
    out[label] = v;
  }
  return out;
}

const isDateBox = (v) =>
  v && typeof v === "object" && typeof v.$date === "string";

function seedRowsFromCases(root, map, leftTypes) {
  const rel = map.battery?.cases;
  if (!rel) return [];
  const abs = resolve(root, rel);
  if (!existsSync(abs)) throw new Usage(`battery.cases does not exist: ${rel}`);
  const doc = JSON.parse(readFileSync(abs, "utf8"));
  const cases = doc.cases;
  if (!Array.isArray(cases))
    throw new Usage(`battery.cases: ${rel} has no top-level 'cases' array`);
  const rows = [];
  for (const [i, c] of cases.entries()) {
    const ctx = c.context || {};
    const slots = {};
    let missing = 0;
    for (const [slotName, slot] of Object.entries(map.slots)) {
      const key = slot.from_case;
      if (!key) continue;
      if (!(key in ctx)) {
        missing++;
        continue;
      }
      const raw = ctx[key];
      if (slot.kind === "record") {
        const tname = slot.left.type;
        const labels = leftTypes[tname];
        if (!labels)
          throw new Usage(
            `slots.${slotName}.left.type '${tname}' is not a record type of the left module. ` +
              `It declares: ${Object.keys(leftTypes).join(", ")}`,
          );
        slots[slotName] = unsanitiseRecord(
          raw,
          labels,
          `${rel} case ${i} ('${c.name || i}') context.${key}`,
        );
      } else if (slot.kind === "date") {
        slots[slotName] = isDateBox(raw) ? raw.$date : raw;
      } else {
        slots[slotName] = raw;
      }
    }
    if (Object.keys(slots).length === 0) continue;
    const rd = ctx.RULES_EFFECTIVE_DATE;
    rows.push({
      name: c.name || `case ${i}`,
      origin: `${rel}#${i}`,
      slots,
      rule_date: isDateBox(rd) ? rd.$date : typeof rd === "string" ? rd : null,
      _missing_slots: missing,
    });
  }
  return rows;
}

const clone = (v) => JSON.parse(JSON.stringify(v));

function leavesOf(value, prefix = []) {
  if (value === null) return [{ path: prefix, value }];
  if (Array.isArray(value)) return []; // list-valued facts are not perturbed in v1
  if (typeof value === "object")
    return Object.entries(value).flatMap(([k, v]) =>
      leavesOf(v, [...prefix, k]),
    );
  return [{ path: prefix, value }];
}

const setAt = (o, path, v) => {
  let cur = o;
  for (const k of path.slice(0, -1)) cur = cur[k];
  cur[path.at(-1)] = v;
};

const DEFAULT_PERTURBATION = {
  enabled: true,
  max_per_seed: 0,
  numeric_deltas: [-1, 1],
  numeric_multipliers: [0, 0.5, 2],
  cross_pollinate: true,
};

const shiftDate = (iso, days) => {
  const d = new Date(`${iso}T00:00:00Z`);
  if (Number.isNaN(d.getTime())) return null;
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
};

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Candidate values for one leaf, boundary-biased.
 *
 * "Boundary-biased" means two things and neither is a guess: the numeric
 * offsets are ±1 (a statutory threshold is crossed by one dollar, not by an
 * order of magnitude), and cross-pollination reuses every value that same leaf
 * takes in some OTHER seed case. The seed cases are where a human already wrote
 * the regime boundaries down; this tries each of them everywhere instead of only
 * where it was written. `slots.<n>.thresholds` is the manual escape hatch for a
 * boundary that appears in no case at all.
 */
export function candidatesFor(leaf, pooled, cfg, thresholds) {
  const v = leaf.value;
  const out = new Set();
  const add = (x) => {
    if (x === undefined || x === null) return;
    if (typeof x === "number" && !Number.isFinite(x)) return;
    out.add(JSON.stringify(x));
  };
  if (typeof v === "boolean") add(!v);
  else if (typeof v === "number") {
    for (const d of cfg.numeric_deltas) add(v + d);
    for (const m of cfg.numeric_multipliers) add(Math.round(v * m * 100) / 100);
    add(-1);
    if (cfg.cross_pollinate)
      for (const p of pooled)
        if (typeof p === "number") {
          add(p);
          for (const d of cfg.numeric_deltas) add(p + d);
        }
  } else if (typeof v === "string" && ISO_DATE.test(v)) {
    for (const d of [-1, 1]) add(shiftDate(v, d));
    if (cfg.cross_pollinate)
      for (const p of pooled)
        if (typeof p === "string" && ISO_DATE.test(p)) {
          add(p);
          add(shiftDate(p, -1));
          add(shiftDate(p, 1));
        }
  } else if (typeof v === "string") {
    if (cfg.cross_pollinate)
      for (const p of pooled) if (typeof p === "string") add(p);
  }
  for (const t of thresholds || []) {
    add(t);
    if (typeof t === "number" && typeof v === "number")
      for (const d of cfg.numeric_deltas) add(t + d);
  }
  out.delete(JSON.stringify(v));
  return [...out].map((s) => JSON.parse(s));
}

export function expandBattery(map, seeds) {
  const cfg = { ...DEFAULT_PERTURBATION, ...(map.battery?.perturbation || {}) };
  const rows = seeds.map((s, i) => ({
    id: `s${i}`,
    kind: "seed",
    name: s.name,
    origin: s.origin,
    slots: s.slots,
    rule_date: s.rule_date ?? null,
    derived_from: null,
    mutation: null,
  }));
  if (!cfg.enabled) return { rows, cfg };

  // Pool every value each leaf path takes across all seeds, for cross-pollination.
  const pool = new Map();
  for (const s of seeds)
    for (const [slotName, val] of Object.entries(s.slots))
      for (const lf of leavesOf(val)) {
        const key = `${slotName}.${lf.path.join(".")}`;
        if (!pool.has(key)) pool.set(key, new Set());
        pool.get(key).add(JSON.stringify(lf.value));
      }

  let n = 0;
  for (const [si, s] of seeds.entries()) {
    let made = 0;
    for (const [slotName, val] of Object.entries(s.slots)) {
      const slot = map.slots[slotName];
      if (slot && slot.perturb === false) continue;
      for (const lf of leavesOf(val)) {
        const key = `${slotName}.${lf.path.join(".")}`;
        const pooled = [...(pool.get(key) || [])].map((x) => JSON.parse(x));
        const thresholds =
          (slot?.thresholds || {})[lf.path.at(-1)] ??
          (slot?.thresholds || {})[lf.path.join(".")];
        for (const cand of candidatesFor(lf, pooled, cfg, thresholds)) {
          if (cfg.max_per_seed && made >= cfg.max_per_seed) break;
          const slots = clone(s.slots);
          if (lf.path.length === 0) slots[slotName] = cand;
          else setAt(slots[slotName], lf.path, cand);
          rows.push({
            id: `s${si}m${made}`,
            kind: "perturbation",
            name: `${s.name} · ${key} = ${JSON.stringify(cand)}`,
            origin: s.origin,
            slots,
            rule_date: s.rule_date ?? null,
            derived_from: `s${si}`,
            mutation: { path: key, from: lf.value, to: cand },
          });
          made++;
          n++;
        }
      }
    }
  }
  return { rows, cfg, generated: n };
}

// ---------------------------------------------------------------------------
// Probe generation.
// ---------------------------------------------------------------------------

const bq = (s) => (/^[A-Za-z][A-Za-z0-9_]*$/.test(s) ? s : "`" + s + "`");
const article = (t) => (/^[AEIOU]/.test(t) ? "AN" : "A");

/** Haskell/L4 string-literal escaping, matching the lexer's showStringLit. */
function l4String(s) {
  let out = '"';
  for (const ch of s) {
    const c = ch.codePointAt(0);
    if (ch === '"') out += '\\"';
    else if (ch === "\\") out += "\\\\";
    else if (c < 0x20 || c === 0x7f) out += `\\${c}`;
    else out += ch;
  }
  return out + '"';
}

function applyRename(value, rename) {
  if (!rename || !value || typeof value !== "object" || Array.isArray(value))
    return value;
  const out = {};
  for (const [k, v] of Object.entries(value)) out[rename[k] ?? k] = v;
  return out;
}

/**
 * One probe module for one side over one chunk of (pair, row) jobs.
 *
 * Shape, per pair signature:
 *   DECLARE `GoArgs <sig>` HAS  a0 IS A <T0>  …
 *   GIVEN jsn IS A STRING
 *   GIVETH AN EITHER STRING `GoArgs <sig>`
 *   `go decode <sig>` jsn MEANS JSONDECODE jsn
 * and per job:
 *   #EVAL [`EVAL UNDER RULES EFFECTIVE AT` (Date d m y)]
 *       CONSIDER `go decode <sig>` "<row json>"
 *           WHEN RIGHT args THEN JUST (<call> (args's a0) …)
 *           WHEN LEFT  e    THEN NOTHING
 *
 * The explicit GIVETH is load-bearing and not decoration: JSONDECODE is driven
 * by the declared result type (jl4-core/src/L4/EvaluateLazy/Machine.hs:2519).
 * Written without it — decoding straight into the application site and letting
 * inference pick the type — the decode returns NOTHING at runtime and every
 * answer silently becomes "no answer". Measured 2026-08-02.
 */
export function generateProbe(side, which, jobs, map, moduleName) {
  const lines = [];
  const emit = (s = "") => lines.push(s);
  emit("IMPORT prelude");
  emit("IMPORT daydate");
  emit(`IMPORT ${bq(moduleName)}`);
  emit();
  emit(`TIMEZONE IS ${l4String(side.timezone)}`);
  emit();
  emit(
    "-- GENERATED by etc/go/lib/denovo-diff.mjs. Never committed; never edited.",
  );
  emit(`-- side: ${which} (${side.label})   module: ${side.module}`);
  emit();

  const sigs = new Map();
  for (const job of jobs) {
    const call = map.pairs.find((p) => p.id === job.pair)[which];
    const key = call.args.map((a) => map.slots[a][which].type).join("|");
    if (!sigs.has(key))
      sigs.set(key, { types: call.args.map((a) => map.slots[a][which].type) });
  }
  const sigIndex = new Map([...sigs.keys()].map((k, i) => [k, i]));
  for (const [key, sig] of sigs) {
    const i = sigIndex.get(key);
    emit(`DECLARE ${bq(`GoArgs ${i}`)} HAS`);
    sig.types.forEach((t, j) => emit(`    a${j} IS ${article(t)} ${t}`));
    emit();
    emit("GIVEN jsn IS A STRING");
    emit(`GIVETH AN EITHER STRING ${bq(`GoArgs ${i}`)}`);
    emit(`${bq(`go decode ${i}`)} jsn MEANS JSONDECODE jsn`);
    emit();
  }

  const index = [];
  for (const job of jobs) {
    const pair = map.pairs.find((p) => p.id === job.pair);
    const call = pair[which];
    const key = call.args.map((a) => map.slots[a][which].type).join("|");
    const i = sigIndex.get(key);
    const payload = {};
    call.args.forEach((slotName, j) => {
      const slot = map.slots[slotName];
      payload[`a${j}`] = applyRename(
        job.row.slots[slotName],
        slot[which].rename,
      );
    });
    const args = call.args.map((_, j) => `(args's a${j})`).join(" ");
    const applied = `${bq(call.call)}${args ? " " + args : ""}`;
    let projected = call.field
      ? `(${applied})'s ${bq(call.field)}`
      : `(${applied})`;
    const ruleDate =
      pair.rule_date === "case" ? job.row.rule_date : (pair.rule_date ?? null);

    // WHERE THE RULE DATE GOES, AND WHY IT MATTERS.
    //
    // `EVAL UNDER RULES EFFECTIVE AT` is dynamically scoped over evaluation, and
    // a lazily-constructed value carries its payload OUT of that scope: written
    // as
    //     `EVAL UNDER RULES EFFECTIVE AT` (Date 1 9 2016)
    //         (CONSIDER … WHEN RIGHT args THEN JUST (f (args's a0)) …)
    // the `JUST` is built inside the scope but `f (args's a0)` is a thunk that
    // is forced after the scope has closed, so the rule date is silently
    // ignored and the answer is the one for the unpinned clock. Measured
    // 2026-08-02 on `offering is within the offering limit` over a $3,000,000
    // offering: TRUE (the 2021 $5,000,000 limit) where the 2016 regime's
    // $1,000,000 limit makes it FALSE. Nothing warns; the wrong answer is
    // well-typed and confident.
    //
    // So the wrapper goes INSIDE the CONSIDER arm, around the application only
    // — the shape regcf.l4's own fixtures use at lines 1137-1144 — where the
    // scope is re-established each time the thunk is forced.
    if (ruleDate) {
      const [y, mo, d] = ruleDate.split("-").map(Number);
      projected = `(${bq("EVAL UNDER RULES EFFECTIVE AT")} (Date ${d} ${mo} ${y}) ${projected})`;
    }

    // The row is bound as a named MEANS and the `#EVAL` names it, rather than
    // being inlined into the directive: it keeps every `#EVAL` on one short
    // line, so a result's `range` maps back to exactly one job.
    const n = index.length;
    emit(`${bq(`go row ${n}`)} MEANS`);
    emit(
      `    CONSIDER ${bq(`go decode ${i}`)} ${l4String(JSON.stringify(payload))}`,
    );
    emit(`        WHEN RIGHT args THEN JUST ${projected}`);
    emit(`        WHEN LEFT  e    THEN NOTHING`);
    emit();
    const startLine = lines.length + 1; // 1-based line of the `#EVAL`
    emit(`#EVAL ${bq(`go row ${n}`)}`);
    emit();
    index.push({ ...job, line: startLine, rule_date: ruleDate });
  }
  return { source: lines.join("\n") + "\n", index };
}

/**
 * Relevance pruning. A perturbation moves exactly one slot; a pair that does
 * not take that slot as an argument cannot see it. This is not a heuristic —
 * an L4 decision is a function of its arguments, so the pruned evaluations are
 * provably equal to their seed's and would contribute agreement rows that mean
 * nothing. Seed rows are always evaluated against every pair, so the baseline
 * is never pruned.
 */
export function jobsFor(map, rows) {
  const jobs = [];
  for (const row of rows) {
    const touched = row.mutation ? row.mutation.path.split(".")[0] : null;
    for (const pair of map.pairs) {
      if (
        touched &&
        !pair.left.args.includes(touched) &&
        !pair.right.args.includes(touched)
      )
        continue;
      jobs.push({ pair: pair.id, row });
    }
  }
  return jobs;
}

// ---------------------------------------------------------------------------
// Evaluation.
// ---------------------------------------------------------------------------

/**
 * Canonical answer for one `#EVAL` result.
 *
 * `l4 run --json` renders values as text, so equality is string equality over a
 * rendering the compiler produced — which is exactly the property we want when
 * the two sides may return structurally different records: the comparison is on
 * what the decision ANSWERS, not on how either module spells it. `JUST OF ` is
 * the probe's own wrapper and is stripped; a bare `NOTHING` means the row failed
 * to decode, which is a harness fact and never an answer.
 */
export function canonAnswer(result) {
  if (!result) return { kind: "missing", value: null, text: "«no result»" };
  if (result.kind === "error")
    return {
      kind: "error",
      value: String(result.value).split("\n").slice(0, 2).join(" ").trim(),
      text: `ERROR: ${String(result.value).split("\n").slice(0, 2).join(" ").trim()}`,
    };
  const raw =
    typeof result.value === "string"
      ? result.value
      : JSON.stringify(result.value);
  const t = raw.trim();
  if (t === "NOTHING")
    return { kind: "decode-failed", value: null, text: "«row did not decode»" };
  const m = t.match(/^JUST OF\s+([\s\S]*)$/);
  let v = m ? m[1].trim() : t;
  if (v.startsWith("(") && v.endsWith(")")) v = v.slice(1, -1).trim();
  return { kind: "value", value: v, text: v };
}

function evaluateChunk(sideDir, source, index, fixedNow, keep, tag) {
  const probePath = join(sideDir, `${PROBE_STEM}.l4`);
  writeFileSync(probePath, source);
  const { status, out, err } = l4([
    "run",
    probePath,
    "--json",
    "--trace",
    "none",
    "--fixed-now",
    fixedNow,
  ]);
  let doc;
  try {
    doc = JSON.parse(out);
  } catch (e) {
    throw new Broken(
      `l4 run --json did not emit JSON for the generated probe (${tag}, exit ${status}). ` +
        `The probe is at ${probePath}. Saw:\n${(out + err).slice(0, 2000)}`,
    );
  }
  const results = doc.results || [];
  if (results.length === 0 && index.length > 0)
    throw new Broken(
      `the generated probe (${tag}) produced no results at all — it did not typecheck. ` +
        `Probe kept at ${probePath}. Diagnostics:\n${(doc.diagnostics || []).join("\n").slice(0, 3000)}`,
    );
  const byLine = new Map();
  for (const r of results) {
    const m = String(r.range || "").match(/:(\d+):/);
    if (m) byLine.set(Number(m[1]), r);
  }
  const answers = index.map((job) => ({
    job,
    answer: canonAnswer(byLine.get(job.line)),
  }));
  if (keep) {
    writeFileSync(join(sideDir, `${PROBE_STEM}.${tag}.l4`), source);
    writeFileSync(join(sideDir, `${PROBE_STEM}.${tag}.json`), out);
  } else {
    rmSync(probePath, { force: true });
  }
  return { answers, diagnostics: doc.diagnostics || [] };
}

function evaluateSide(staged, side, which, jobs, map, fixedNow, chunk, keep) {
  const all = [];
  const diags = [];
  for (let i = 0; i < jobs.length; i += chunk) {
    const slice = jobs.slice(i, i + chunk);
    const { source, index } = generateProbe(
      side,
      which,
      slice,
      map,
      staged.moduleName,
    );
    const tag = `${which}-${String(i / chunk).padStart(4, "0")}`;
    const r = evaluateChunk(staged.dir, source, index, fixedNow, keep, tag);
    all.push(...r.answers);
    diags.push(...r.diagnostics);
  }
  return { answers: all, diagnostics: diags };
}

// ---------------------------------------------------------------------------
// The comparison, and the SPEC §8 table.
// ---------------------------------------------------------------------------

export function compare(leftAnswers, rightAnswers) {
  const rows = [];
  for (let i = 0; i < leftAnswers.length; i++) {
    const L = leftAnswers[i];
    const R = rightAnswers[i];
    const agree = L.answer.text === R.answer.text;
    rows.push({
      pair: L.job.pair,
      row_id: L.job.row.id,
      row_kind: L.job.row.kind,
      row_name: L.job.row.name,
      derived_from: L.job.row.derived_from,
      mutation: L.job.row.mutation,
      rule_date: L.job.rule_date,
      left: L.answer,
      right: R.answer,
      agree,
    });
  }
  return rows;
}

/**
 * Sensitivity: which (pair, fact leaf) surfaces the battery actually exercised.
 *
 * This exists because of a measured false green. `total assets threshold` in
 * `regcf.l4:213` was moved 10,000,000 → 20,000,000 in a scratch copy — a real
 * change to a live decision path, read by `reporting-may-terminate` at line 671
 * — and the comparator answered `6800 agreed · 0 diverged`, exit 0, with the
 * report printing "the de novo run reproduced the corpus over this battery".
 * Every word of that was true and the impression it left was false. The cause
 * is visible in the rows: `status.total assets` was perturbed 128 times against
 * that pair and **not one perturbation moved either side's answer**, because
 * every value the generator reaches (0, 2·5M, 5M±1, 10M, −5M) sits below both
 * the old threshold and the new one. Agreement over an input the decision never
 * responded to is not evidence of agreement; it is an absence of measurement,
 * and a report that does not separate the two reads as a clean bill of health.
 *
 * So, per (pair, leaf): how many perturbations were evaluated, and how many
 * moved an answer away from the seed's. A leaf with `moved === 0` is **inert**
 * for that pair over this battery. `moved` counts a move on EITHER side, which
 * is the conservative direction: if either encoding responded, the surface was
 * exercised and the agreement means something.
 *
 * This is a measurement, not a judgement, and deliberately does NOT touch the
 * exit code — §8's semantics are agreement/divergence, and an inert leaf is
 * neither. It is reported so a reader cannot mistake silence for evidence. The
 * remedy when it fires is a battery that reaches the boundary: a seed case, or
 * a `slots.<n>.thresholds` entry, which exists for exactly this.
 */
export function sensitivity(rows) {
  const seedAnswers = new Map();
  for (const r of rows)
    if (r.row_kind === "seed")
      seedAnswers.set(`${r.pair} ${r.row_id}`, [r.left.text, r.right.text]);
  const acc = new Map();
  for (const r of rows) {
    if (r.row_kind !== "perturbation" || !r.mutation) continue;
    const base = seedAnswers.get(`${r.pair} ${r.derived_from}`);
    if (base === undefined) continue; // no seed baseline: cannot say
    const key = `${r.pair} ${r.mutation.path}`;
    let e = acc.get(key);
    if (!e) {
      e = { pair: r.pair, leaf: r.mutation.path, perturbed: 0, moved: 0 };
      acc.set(key, e);
    }
    e.perturbed++;
    if (r.left.text !== base[0] || r.right.text !== base[1]) e.moved++;
  }
  return [...acc.values()].sort(
    (a, b) => a.pair.localeCompare(b.pair) || a.leaf.localeCompare(b.leaf),
  );
}

/**
 * Minimise. A perturbation row is one field away from its seed, so when the
 * seed agreed the witness is already minimal by construction — there is no
 * smaller change that reaches it. What is left to do is to stop reporting the
 * same defect a hundred times: divergences are grouped by (pair, mutated leaf,
 * both answers), and each group elects one representative — the one whose
 * mutation moves the value least, so a threshold defect reports the row that
 * sits closest to the threshold.
 */
export function minimise(rows) {
  const diverged = rows.filter((r) => !r.agree);
  const groups = new Map();
  for (const r of diverged) {
    const key = [
      r.pair,
      r.mutation ? r.mutation.path : "«seed»",
      r.left.text,
      r.right.text,
    ].join(" ");
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(r);
  }
  const dist = (r) => {
    if (!r.mutation) return Number.POSITIVE_INFINITY;
    const { from, to } = r.mutation;
    if (typeof from === "number" && typeof to === "number")
      return Math.abs(to - from);
    return 1;
  };
  const witnesses = [];
  for (const [, group] of groups) {
    const seedFirst = group.filter((r) => r.row_kind === "seed");
    const pool = seedFirst.length ? seedFirst : group;
    const rep = pool.reduce((a, b) => (dist(b) < dist(a) ? b : a));
    witnesses.push({
      ...rep,
      minimal:
        rep.row_kind === "perturbation"
          ? "one-field-from-agreeing-seed"
          : "whole-seed-row",
      also_seen_on: group.length - 1,
      disposition: "UNTRIAGED",
    });
  }
  witnesses.sort(
    (a, b) => a.pair.localeCompare(b.pair) || b.also_seen_on - a.also_seen_on,
  );
  return witnesses;
}

const mdEsc = (s) => String(s).replace(/\|/g, "\\|").replace(/\n/g, " ");
const trunc = (s, n) =>
  String(s).length > n ? String(s).slice(0, n - 1) + "…" : String(s);

function renderMarkdown(report) {
  const L = report.sides.left.label;
  const R = report.sides.right.label;
  const out = [];
  out.push(`# De novo diff — ${report.subject}`);
  out.push("");
  out.push(
    `Produced by \`etc/go/lib/denovo-diff.mjs\` from \`${report.map_path}\`. ` +
      `Every disposition below is **UNTRIAGED**: this script measures, it does not triage. ` +
      `SPEC.md §8's three dispositions — \`ENCODING-ERROR\`, \`GENUINE-AMBIGUITY\`, \`IMPROVEMENT-OVER-CORPUS\` — ` +
      `are judgements and belong to the reviewer or the skill.`,
  );
  out.push("");
  out.push("## Surfaces");
  out.push("");
  out.push(`| | ${mdEsc(L)} (left) | ${mdEsc(R)} (right) |`);
  out.push("| --- | --- | --- |");
  out.push(
    `| module | \`${report.sides.left.module}\` | \`${report.sides.right.module}\` |`,
  );
  out.push(
    `| rules declared | ${report.surface.left.rules} | ${report.surface.right.rules} |`,
  );
  out.push(
    `| rules paired | ${report.surface.left.paired} | ${report.surface.right.paired} |`,
  );
  out.push(
    `| paired and \`@export\` | ${report.surface.left.exported} | ${report.surface.right.exported} |`,
  );
  out.push("");
  out.push("## Battery");
  out.push("");
  out.push(
    `${report.battery.seeds} seed row(s)${report.battery.cases ? ` from \`${report.battery.cases}\`` : ""}, ` +
      `${report.battery.perturbations} single-field perturbation(s), ` +
      `${report.battery.rows} row(s) in all. ` +
      `Every seed is evaluated against all ${report.pairs} pair(s); a perturbation is evaluated only against the pairs that take the ` +
      `mutated slot as an argument, because a decision is a function of its arguments and the rest are provably unchanged. ` +
      `That leaves **${report.evaluations}** evaluation(s) per side.`,
  );
  out.push("");
  out.push("## Agreement");
  out.push("");
  out.push(
    "| pair | citation | evaluated | agreed | diverged | leaves perturbed | of those, inert |",
  );
  out.push("| --- | --- | ---: | ---: | ---: | ---: | ---: |");
  for (const p of report.per_pair)
    out.push(
      `| \`${p.pair}\` | ${mdEsc(p.citation || "—")} | ${p.evaluated} | ${p.agreed} | ${p.diverged} | ` +
        `${p.leaves_perturbed ?? 0} | ${p.leaves_inert ?? 0} |`,
    );
  out.push(
    `| **total** | | **${report.totals.evaluated}** | **${report.totals.agreed}** | **${report.totals.diverged}** | ` +
      `**${report.totals.leaves_perturbed ?? 0}** | **${report.totals.leaves_inert ?? 0}** |`,
  );
  out.push("");
  out.push("### Sensitivity — where an agreement is not evidence");
  out.push("");
  const inertRows = (report.sensitivity ?? []).filter((s) => s.moved === 0);
  out.push(
    "An **inert** (pair, fact) leaf is one the battery perturbed without ever moving either " +
      "side's answer away from its seed's. Agreement there is not agreement about anything: the " +
      "decision never responded to that input over these values, so a real difference between the " +
      "two encodings on that leaf would be invisible. This is measured, it does not affect the " +
      "exit code, and it is not a defect in either encoding — it is a limit of the battery. The " +
      "remedy is a seed case or a `slots.<n>.thresholds` entry that reaches the boundary.",
  );
  out.push("");
  if (inertRows.length === 0) {
    out.push(
      "Every perturbed leaf moved an answer at least once. No blind spot of this kind.",
    );
  } else {
    out.push("| pair | fact leaf | perturbations | moved an answer |");
    out.push("| --- | --- | ---: | ---: |");
    for (const s of inertRows)
      out.push(
        `| \`${s.pair}\` | \`${mdEsc(trunc(s.leaf, 90))}\` | ${s.perturbed} | 0 |`,
      );
  }
  out.push("");
  out.push("## Triage table (SPEC.md §8)");
  out.push("");
  if (report.witnesses.length === 0) {
    out.push(
      `No divergence. Under SPEC.md §8 that is a **pass** — the de novo run reproduced the corpus ` +
        `over this battery. It is not the better pass, which is a run that finds a defect in the corpus. ` +
        (inertRows.length
          ? `**Read that with the Sensitivity table above**: ${inertRows.length} of ` +
            `${(report.sensitivity ?? []).length} (pair, fact) leaves were perturbed without ever moving an ` +
            `answer, so on those the battery measured nothing and the agreement is silence rather than evidence. `
          : "") +
        `What the battery did not reach is in "Limits" below.`,
    );
  } else {
    out.push(
      "| # | pair | witness | " +
        `${mdEsc(L)} says | ${mdEsc(R)} says | also seen on | fork | disposition |`,
    );
    out.push("| ---: | --- | --- | --- | --- | ---: | --- | --- |");
    report.witnesses.forEach((w, i) => {
      const witness = w.mutation
        ? `\`${mdEsc(w.mutation.path)}\`: ${mdEsc(JSON.stringify(w.mutation.from))} → ${mdEsc(JSON.stringify(w.mutation.to))}<br>on seed _${mdEsc(trunc(w.seed_name || w.row_name, 60))}_`
        : `whole seed row _${mdEsc(trunc(w.row_name, 80))}_`;
      out.push(
        `| ${i + 1} | \`${w.pair}\` | ${witness} | \`${mdEsc(trunc(w.left.text, 120))}\` | \`${mdEsc(trunc(w.right.text, 120))}\` | ${w.also_seen_on} | ${w.fork ? `\`${w.fork}\`` : "—"} | **UNTRIAGED** |`,
      );
    });
    out.push("");
    out.push(
      "Minimality: a witness marked `one-field-from-agreeing-seed` is minimal by construction — " +
        "its seed agreed and exactly one field moved. A witness marked `whole-seed-row` is not " +
        "minimised: the seed itself diverged, and there is no agreeing neighbour to shrink towards.",
    );
  }
  out.push("");
  out.push("## Limits — what this comparison cannot see");
  out.push("");
  for (const l of report.limits) out.push(`- ${l}`);
  out.push("");
  return out.join("\n");
}

const LIMITS = [
  "**Only the pairs the map declares.** Coverage is `rules paired / rules declared` above. A decision present in one encoding and absent from the other is invisible here unless somebody wrote the pair down — the map is a declaration, and the oracle can only disagree with what was declared.",
  "**Decisions only — the deontic layer is not exercised.** The battery evaluates `DECIDE`/`MEANS` functions. Regulative rules (obligations, deadlines, reparations) have no answer this comparator reads, so two encodings could differ on who owes what, by when, and with what consequence on breach, and every row here would still agree. The BPMN/LTS legs are where that divergence would show; wiring them into the diff is not built.",
  "**Answer equality is equality of the compiler's rendering.** Two answers that mean the same thing but render differently (a record with reordered fields, `4/2` against `2.0`) read as a divergence, and are triaged away by a human. The `field` projection in the map exists to narrow the comparison when that noise dominates.",
  "**Both sides erroring identically counts as agreement.** If a fact pattern makes both encodings refuse, that is recorded as an agreement on the refusal — which is the right answer for a curated refusal (Reg CF pre-commencement dates) and the wrong one if both encodings are broken in the same way.",
  "**Perturbation is single-field.** Interaction defects that need two fields to move together are out of reach. The generator is a search over a neighbourhood of the seed cases, not over the input space.",
  "**A leaf the battery never made a decision respond to is not compared, only visited.** The generator reaches the values it can derive from the seed cases (±1, ×0/×½/×2, ×−1, cross-pollination, declared thresholds); a statutory boundary outside every one of them is never crossed, and both encodings answer identically on the near side of it whatever they say on the far side. Measured case: moving `total assets threshold` from 10,000,000 to 20,000,000 in a scratch copy of `regcf.l4` changes a live path of `reporting-may-terminate` and produces **zero** divergence, because every value the battery reaches for `status.total assets` is below both. The Sensitivity table above is that blind spot enumerated rather than described; the remedy is a seed case or a `slots.<n>.thresholds` entry at the boundary.",
  "**List-valued and optional-shaped facts are not perturbed.** `leavesOf` descends objects and stops at arrays.",
  "**An enum-typed input field cannot be fed.** `JSONDECODE` delivers a constructor name as a string, so any `CONSIDER` over an enum-valued field of a decoded record raises `NonExhaustivePatterns` — on both sides identically, which reads as agreement on an error and measures nothing. Keep such slots out of the map (the Reg CF identity fixture drops `FormCFiling` for exactly this) until the decoder learns constructors. `l4 batch` decodes rows the same way and has the same limit.",
  "**A `#ASSERT` in either module is not consulted.** This is a differential oracle between two encodings; it says nothing about whether either agrees with the statute. That is HG1's question and P5's.",
];

// ---------------------------------------------------------------------------
// Driver.
// ---------------------------------------------------------------------------

function loadMap(root, mapPath) {
  const abs = resolve(mapPath);
  if (!existsSync(abs)) throw new Usage(`--map does not exist: ${mapPath}`);
  let doc;
  try {
    doc = JSON.parse(readFileSync(abs, "utf8"));
  } catch (e) {
    throw new Usage(`--map is not valid JSON: ${mapPath}: ${e.message}`);
  }
  const schemaPath = resolve(root, SCHEMA_PATH);
  if (!existsSync(schemaPath))
    throw new Broken(`the surface-map schema is missing: ${SCHEMA_PATH}`);
  const schema = JSON.parse(readFileSync(schemaPath, "utf8"));
  assertSupported(schema);
  const errs = validateAgainstSchema(schema, doc);
  if (errs.length) {
    const msg = [`${mapPath} does not satisfy ${SCHEMA_PATH}:`]
      .concat(errs.map((e) => `  - ${e}`))
      .join("\n");
    throw new Usage(msg);
  }
  // Referential integrity the schema cannot express.
  const ids = new Set();
  for (const p of doc.pairs) {
    if (ids.has(p.id)) throw new Usage(`duplicate pair id '${p.id}'`);
    ids.add(p.id);
    for (const which of ["left", "right"])
      for (const a of p[which].args)
        if (!(a in doc.slots))
          throw new Usage(
            `pair '${p.id}'.${which}.args names an undeclared slot '${a}'`,
          );
  }
  doc.sides.left._which = "left";
  doc.sides.right._which = "right";
  return { map: doc, abs };
}

function nearest(name, pool) {
  const lc = name.toLowerCase();
  return pool
    .map((r) => {
      const a = r.toLowerCase();
      let score = 0;
      for (const w of lc.split(/\s+/)) if (a.includes(w)) score++;
      return { r, score };
    })
    .filter((x) => x.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, 5)
    .map((x) => x.r);
}

function main(argv) {
  const cmd = argv[0];
  const opt = (name, dflt) => {
    const i = argv.indexOf(`--${name}`);
    return i >= 0 && argv[i + 1] !== undefined ? argv[i + 1] : dflt;
  };
  const flag = (name) => argv.includes(`--${name}`);
  if (!cmd || !["validate", "battery", "run"].includes(cmd) || !opt("map"))
    throw new Usage(
      "usage: denovo-diff.mjs validate|battery|run --map MAP.json [--root DIR] [--out DIR]\n" +
        "                     [--fixed-now ISO8601] [--chunk N] [--max-rows N] [--keep-probes]",
    );

  const root = resolve(opt("root", REPO_DEFAULT));
  const fixedNow = opt(
    "fixed-now",
    process.env.GO_FIXED_NOW ||
      process.env.L4_GO_FIXED_NOW ||
      "2025-01-31T00:00:00Z",
  );
  const chunk = Number(opt("chunk", "400"));
  const maxRows = Number(opt("max-rows", "0"));
  const { map, abs: mapAbs } = loadMap(root, opt("map"));

  const outDir = resolve(
    opt("out", join(process.env.TMPDIR || "/tmp", "l4-go-denovo-diff")),
  );
  mkdirSync(outDir, { recursive: true });

  // --- surfaces -------------------------------------------------------------
  const staged = {
    left: stageSide(root, map.sides.left, join(outDir, "side-left")),
    right: stageSide(root, map.sides.right, join(outDir, "side-right")),
  };
  const surface = {};
  for (const which of ["left", "right"]) {
    const s = readSurface(staged[which].modulePath, fixedNow);
    const named = map.pairs.map((p) => p[which].call);
    for (const n of named)
      if (!s.rules.includes(n)) {
        const near = nearest(n, s.rules);
        throw new Usage(
          `sides.${which} (${map.sides[which].module}) declares no rule named '${n}'.` +
            (near.length
              ? `\n  nearest: ${near.map((x) => `'${x}'`).join(", ")}`
              : "") +
            `\n  (${s.rules.length} rules enumerated by \`l4 render --format json --include-unused\`)`,
        );
      }
    const exported = [...new Set(named)].filter((n) =>
      isExported(staged[which].modulePath, n, outDir),
    ).length;
    surface[which] = {
      rules: s.rules.length,
      paired: new Set(named).size,
      exported,
      types: s.types,
    };
  }

  // EVERY DECLARED FIELD IS SUPPLIED, ON BOTH SIDES, BY EVERY ROW.
  //
  // A row states one canonical payload per slot and each side's `rename` maps
  // it onto that side's field names, so a record can be renamed or decomposed
  // in its own module and leave the map silently stale. That is not a
  // hypothetical: the corpus grew `date the securities were issued` in
  // 4fec076e and decomposed Rule 501(a)(4) into six booleans in 3f06cdc6, and
  // on 2026-08-09 both `transfer`-slot pairs were erroring on the left for all
  // twenty rows.
  //
  // It is invisible without this check for two compounding reasons. A missing
  // field raises `UserError "Missing required field"` at evaluation
  // (jl4-core/src/L4/EvaluateLazy/Machine.hs), and the probe's
  // `WHEN LEFT e THEN NOTHING` arm catches only *parse* failures — so the
  // answer becomes an ERROR string that `compare` reports as a divergence.
  // Twenty rows of broken harness therefore read as total corpus divergence:
  // the louder the breakage, the more it looks like a finding.
  //
  // Extra keys are legitimate and deliberately not flagged — a row states the
  // union of both sides' names ("one key, two names"), and JSONDECODE ignores
  // what the record does not declare. Only ABSENCE is an error.
  {
    const missing = [];
    for (const [slotName, slot] of Object.entries(map.slots)) {
      for (const which of ["left", "right"]) {
        const declared = surface[which].types[slot[which].type];
        if (!Array.isArray(declared)) continue; // enum, or a type we cannot see
        for (const [i, row] of (map.battery?.rows || []).entries()) {
          const payload = row.slots?.[slotName];
          if (!payload) continue;
          const supplied = new Set(
            Object.keys(applyRename(payload, slot[which].rename)),
          );
          const absent = declared.filter((f) => !supplied.has(f));
          if (absent.length)
            missing.push(
              `  battery.rows[${i}] (${row.name ?? "unnamed"}) -> slots.${slotName}.${which} ` +
                `(${slot[which].type}): ${absent.map((f) => `'${f}'`).join(", ")}`,
            );
        }
      }
    }
    if (missing.length) {
      const shown = missing.slice(0, 12);
      throw new Usage(
        `${missing.length} (row, slot, side) combination(s) do not supply every field the record declares. ` +
          `Each one evaluates to \`Missing required field\`, which the probe reports as a DIVERGENCE, ` +
          `not as a broken harness — so this reads as the two encodings disagreeing.\n` +
          shown.join("\n") +
          (missing.length > shown.length
            ? `\n  … and ${missing.length - shown.length} more`
            : "") +
          `\nFix by adding the field to the rows, or by mapping an existing row key onto it ` +
          `with slots.<name>.<side>.rename.`,
      );
    }
  }

  if (cmd === "validate") {
    process.stdout.write(
      `denovo-diff: ${opt("map")} is valid — ${map.pairs.length} pair(s), ` +
        `${Object.keys(map.slots).length} slot(s); every call resolves in its own module ` +
        `(left ${surface.left.paired}/${surface.left.rules} rules paired, ` +
        `right ${surface.right.paired}/${surface.right.rules}).\n`,
    );
    return EXIT_CLEAN;
  }

  // --- battery --------------------------------------------------------------
  const seeds = [
    ...seedRowsFromCases(root, map, surface.left.types),
    ...(map.battery?.rows || []).map((r, i) => ({
      name: r.name,
      origin: `${basename(mapAbs)}#battery.rows[${i}]`,
      slots: r.slots,
      rule_date: r.rule_date ?? null,
    })),
  ];
  if (seeds.length === 0)
    throw new Usage(
      "the battery is empty: battery.cases produced no row carrying a declared slot, and battery.rows is absent. " +
        "Check that every slot you want fed from the cases file carries a `from_case` key.",
    );
  let { rows, generated } = expandBattery(map, seeds);
  const truncated = maxRows > 0 && rows.length > maxRows;
  if (truncated) rows = rows.slice(0, maxRows);

  if (cmd === "battery") {
    const p = join(outDir, "battery.json");
    writeFileSync(
      p,
      JSON.stringify({ seeds: seeds.length, generated, rows }, null, 2),
    );
    process.stdout.write(
      `denovo-diff: ${seeds.length} seed(s) + ${generated} perturbation(s) = ${rows.length} row(s) -> ${p}\n`,
    );
    return EXIT_CLEAN;
  }

  // --- evaluate -------------------------------------------------------------
  const jobs = jobsFor(map, rows);

  const evaluated = {};
  for (const which of ["left", "right"])
    evaluated[which] = evaluateSide(
      staged[which],
      map.sides[which],
      which,
      jobs,
      map,
      fixedNow,
      chunk,
      flag("keep-probes"),
    );

  const cmpRows = compare(evaluated.left.answers, evaluated.right.answers);
  const seedName = new Map(rows.map((r) => [r.id, r.name]));
  const witnesses = minimise(cmpRows).map((w) => ({
    ...w,
    seed_name: w.derived_from ? seedName.get(w.derived_from) : null,
    fork: map.pairs.find((p) => p.id === w.pair)?.fork ?? null,
  }));

  const sens = sensitivity(cmpRows);
  const perPair = map.pairs.map((p) => {
    const mine = cmpRows.filter((r) => r.pair === p.id);
    const leaves = sens.filter((s) => s.pair === p.id);
    return {
      pair: p.id,
      citation: p.citation ?? null,
      fork: p.fork ?? null,
      evaluated: mine.length,
      agreed: mine.filter((r) => r.agree).length,
      diverged: mine.filter((r) => !r.agree).length,
      leaves_perturbed: leaves.length,
      leaves_inert: leaves.filter((s) => s.moved === 0).length,
    };
  });
  const inert = sens.filter((s) => s.moved === 0);

  const report = {
    schema: "l4-go/denovo-diff-report@1",
    subject: map.subject,
    map_path: opt("map"),
    fixed_now: fixedNow,
    l4: L4(),
    sides: {
      left: { label: map.sides.left.label, module: map.sides.left.module },
      right: { label: map.sides.right.label, module: map.sides.right.module },
    },
    surface: {
      left: { ...surface.left, types: undefined },
      right: { ...surface.right, types: undefined },
    },
    battery: {
      cases: map.battery?.cases ?? null,
      seeds: seeds.length,
      perturbations: generated || 0,
      rows: rows.length,
      truncated,
    },
    pairs: map.pairs.length,
    evaluations: cmpRows.length,
    per_pair: perPair,
    totals: {
      evaluated: cmpRows.length,
      agreed: cmpRows.filter((r) => r.agree).length,
      diverged: cmpRows.filter((r) => !r.agree).length,
      witnesses: witnesses.length,
      leaves_perturbed: sens.length,
      leaves_inert: inert.length,
    },
    witnesses,
    sensitivity: sens,
    limits: LIMITS,
  };

  const jsonPath = join(outDir, "denovo-diff.json");
  const mdPath = join(outDir, "denovo-diff.md");
  writeFileSync(jsonPath, JSON.stringify(report, null, 2));
  writeFileSync(mdPath, renderMarkdown(report));
  writeFileSync(
    join(outDir, "denovo-diff.rows.json"),
    JSON.stringify(cmpRows, null, 2),
  );

  process.stdout.write(
    `denovo-diff: ${report.totals.evaluated} evaluation(s) over ${rows.length} row(s) × ${map.pairs.length} pair(s)\n` +
      `             ${report.totals.agreed} agreed · ${report.totals.diverged} diverged · ` +
      `${witnesses.length} minimised witness(es)\n` +
      `             ${inert.length} of ${sens.length} (pair, fact) leaves inert — perturbed, never moved an answer\n` +
      `             ${jsonPath}\n             ${mdPath}\n`,
  );
  if (truncated)
    process.stdout.write(
      `             NOTE: --max-rows ${maxRows} truncated the battery; this is a partial comparison.\n`,
    );
  for (const w of witnesses.slice(0, 12))
    process.stdout.write(
      `  DIVERGE ${w.pair}  ${w.mutation ? `${w.mutation.path} ${JSON.stringify(w.mutation.from)}→${JSON.stringify(w.mutation.to)}` : `seed «${trunc(w.row_name, 50)}»`}\n` +
        `          ${map.sides.left.label}: ${trunc(w.left.text, 90)}\n` +
        `          ${map.sides.right.label}: ${trunc(w.right.text, 90)}\n`,
    );
  if (witnesses.length > 12)
    process.stdout.write(
      `  … and ${witnesses.length - 12} more; see ${mdPath}\n`,
    );

  return report.totals.diverged === 0 ? EXIT_CLEAN : EXIT_FINDING;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    process.exit(main(process.argv.slice(2)));
  } catch (e) {
    if (e instanceof Usage) {
      process.stderr.write(`denovo-diff: ${e.message}\n`);
      process.exit(EXIT_USAGE);
    }
    if (e instanceof Broken) {
      process.stderr.write(`denovo-diff: BROKEN — ${e.message}\n`);
      process.exit(EXIT_BROKEN);
    }
    throw e;
  }
}

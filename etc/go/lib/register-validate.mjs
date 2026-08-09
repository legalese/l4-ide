#!/usr/bin/env node
// One validator for the three de novo deposit contracts:
//
//   specs/todo/single-instruction-demo/schemas/source-bundle.schema.json          (P1)
//   specs/todo/single-instruction-demo/schemas/external-modifications.schema.json (P2)
//   specs/todo/single-instruction-demo/schemas/fork-register.schema.json          (P4)
//
// Usage:
//   register-validate.mjs <schema> <file> [peer-file ...]
//   register-validate.mjs --rules <schema>
//   register-validate.mjs --help
//
// <schema> is one of: fork-register · external-modifications · source-bundle.
// Peer files are identified by their own `kind` field, validated in their own
// right, and then used by the cross-file rules. A cross-file rule whose peer
// was not given is reported `skip`, never silently passed.
//
// Exit: 0 clean · 1 a finding · 2 usage, an unreadable file, or a schema this
// validator cannot fully enforce.
//
// Style follows etc/go/lib/subject.mjs: refuse-by-default, unknown keys are
// errors, and every message names the exact path and the rule that fired.
//
// THE ENFORCEMENT CONTRACT, which is the point of the file.
//
// The schemas are JSON Schema 2020-12 restricted to the closed keyword subset
// in KEYWORDS below. Before using a schema this validator AUDITS it and exits 2
// naming any keyword it does not implement, so a schema can never assert a
// constraint that quietly goes unchecked. Cross-field rules that JSON Schema
// cannot express cheaply are declared in the schema's `x-rules` with an id, and
// RULES below implements them by that id; the two sets are compared in BOTH
// directions, so a rule can be neither declared-but-unenforced nor
// enforced-but-undocumented.

import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, "../../..");
// L4_GO_SCHEMA_DIR overrides the schema root, matching subject.mjs's
// L4_GO_SUBJECTS_DIR: the selftest uses it to aim the loader at deliberately
// broken schemas and prove the enforcement contract above can still say no.
const SCHEMA_DIR = process.env.L4_GO_SCHEMA_DIR
  ? resolve(process.env.L4_GO_SCHEMA_DIR)
  : resolve(REPO, "specs/todo/single-instruction-demo/schemas");

export const SCHEMA_NAMES = [
  "fork-register",
  "external-modifications",
  "source-bundle",
];

function die(msg) {
  process.stderr.write(`register-validate: ${msg}\n`);
  process.exit(2);
}

// ------------------------------------------------------------------ 1. schema

// The closed subset. A schema keyword outside this set is a hard error: see the
// enforcement contract above.
const KEYWORDS = new Set([
  "$schema",
  "$id",
  "$ref",
  "$defs",
  "title",
  "description",
  "type",
  "enum",
  "const",
  "pattern",
  "format",
  "properties",
  "required",
  "additionalProperties",
  "items",
  "minItems",
  "maxItems",
  "uniqueItems",
  "minLength",
  "minimum",
  "x-rules",
]);
const FORMATS = new Set(["date", "date-time"]);

function auditSchema(node, where, seen) {
  if (Array.isArray(node) || node === null || typeof node !== "object") return;
  for (const [k, v] of Object.entries(node)) {
    if (!KEYWORDS.has(k))
      die(
        `${where}: schema uses keyword '${k}', which this validator does not implement. ` +
          `Implement it in KEYWORDS/validateNode or restate the constraint as an x-rules entry — ` +
          `a keyword that is parsed but not enforced is a constraint that silently does not exist.`,
      );
    if (k === "additionalProperties" && v !== false)
      die(
        `${where}.additionalProperties: only 'false' is implemented (got ${JSON.stringify(v)})`,
      );
    if (k === "format" && !FORMATS.has(v))
      die(
        `${where}.format: '${v}' is not implemented (have: ${[...FORMATS].join(", ")})`,
      );
    if (k === "$ref") {
      if (!/^#\/\$defs\/[A-Za-z0-9_]+$/.test(v))
        die(`${where}.$ref: only local '#/$defs/<name>' refs are implemented`);
      if (!seen.has(v.slice("#/$defs/".length)))
        die(`${where}.$ref: '${v}' does not resolve`);
    }
    if (k === "x-rules") {
      if (where !== "#")
        die(`${where}.x-rules: x-rules is a root-level keyword only`);
      continue;
    }
    if (k === "$defs") {
      for (const [n, d] of Object.entries(v))
        auditSchema(d, `#/$defs/${n}`, seen);
      continue;
    }
    if (k === "properties") {
      for (const [n, d] of Object.entries(v))
        auditSchema(d, `${where}.properties.${n}`, seen);
      continue;
    }
    if (k === "items") auditSchema(v, `${where}.items`, seen);
  }
}

function loadSchema(name) {
  const path = resolve(SCHEMA_DIR, `${name}.schema.json`);
  if (!existsSync(path)) die(`schema file not found: ${path}`);
  let schema;
  try {
    schema = JSON.parse(readFileSync(path, "utf8"));
  } catch (e) {
    die(`${path} is not valid JSON: ${e.message}`);
  }
  auditSchema(schema, "#", new Set(Object.keys(schema.$defs ?? {})));

  const declared = (schema["x-rules"] ?? []).map((r) => r.id);
  for (const r of schema["x-rules"] ?? []) {
    if (typeof r.id !== "string" || !r.id)
      die(`${name}: an x-rules entry has no id`);
    if (typeof r.description !== "string" || r.description.length < 20)
      die(`${name}: x-rules '${r.id}' has no usable description`);
    if (
      r.peer !== undefined &&
      r.peer !== "any" &&
      !SCHEMA_NAMES.includes(r.peer)
    )
      die(`${name}: x-rules '${r.id}' names an unknown peer '${r.peer}'`);
    for (const k of Object.keys(r))
      if (!["id", "description", "peer"].includes(k))
        die(`${name}: x-rules '${r.id}' has unknown key '${k}'`);
  }
  const impl = Object.keys(RULES[name] ?? {});
  const missing = declared.filter((id) => !impl.includes(id));
  const extra = impl.filter((id) => !declared.includes(id));
  if (missing.length)
    die(
      `${name}: x-rules declares ${missing.map((r) => `'${r}'`).join(", ")} with no implementation — ` +
        `a declared rule that does not run is worse than an undeclared one, because it reads as coverage`,
    );
  if (extra.length)
    die(
      `${name}: RULES implements ${extra.map((r) => `'${r}'`).join(", ")}, which x-rules does not declare — ` +
        `an undocumented rule cannot be reviewed`,
    );
  if (new Set(declared).size !== declared.length)
    die(`${name}: x-rules has duplicate ids`);
  return schema;
}

// ------------------------------------------------------- 2. structural checks

const isDate = (s) => {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) return false;
  const d = new Date(`${s}T00:00:00Z`);
  return (
    !Number.isNaN(d.getTime()) &&
    d.getUTCFullYear() === +m[1] &&
    d.getUTCMonth() + 1 === +m[2] &&
    d.getUTCDate() === +m[3]
  );
};

function typeOf(v) {
  if (v === null) return "null";
  if (Array.isArray(v)) return "array";
  if (Number.isInteger(v)) return "integer";
  return typeof v; // string · number · boolean · object
}

function validateNode(value, schema, path, root, out) {
  const add = (msg) => out.push({ path, message: msg, rule: "schema" });

  if (schema.$ref) {
    validateNode(
      value,
      root.$defs[schema.$ref.slice("#/$defs/".length)],
      path,
      root,
      out,
    );
    return;
  }
  if (schema.type !== undefined) {
    const want = Array.isArray(schema.type) ? schema.type : [schema.type];
    const got = typeOf(value);
    const ok = want.some(
      (t) => t === got || (t === "number" && got === "integer"),
    );
    if (!ok) {
      add(`expected ${want.join(" or ")}, got ${got}`);
      return;
    }
  }
  if (schema.const !== undefined && value !== schema.const)
    add(
      `must be ${JSON.stringify(schema.const)}, got ${JSON.stringify(value)}`,
    );
  if (schema.enum !== undefined && !schema.enum.includes(value))
    add(
      `${JSON.stringify(value)} is not one of: ${schema.enum.map((e) => JSON.stringify(e)).join(", ")}`,
    );
  if (typeof value === "string") {
    if (schema.minLength !== undefined && value.length < schema.minLength)
      add(`must be at least ${schema.minLength} character(s)`);
    if (schema.pattern !== undefined && !new RegExp(schema.pattern).test(value))
      add(`${JSON.stringify(value)} does not match ${schema.pattern}`);
    if (schema.format === "date" && !isDate(value))
      add(`${JSON.stringify(value)} is not a calendar date (YYYY-MM-DD)`);
    if (
      schema.format === "date-time" &&
      Number.isNaN(new Date(value).getTime())
    )
      add(`${JSON.stringify(value)} is not a date-time`);
  }
  if (
    typeof value === "number" &&
    schema.minimum !== undefined &&
    value < schema.minimum
  )
    add(`must be >= ${schema.minimum}`);

  if (typeOf(value) === "array") {
    if (schema.minItems !== undefined && value.length < schema.minItems)
      add(`must have at least ${schema.minItems} item(s), has ${value.length}`);
    if (schema.maxItems !== undefined && value.length > schema.maxItems)
      add(`must have at most ${schema.maxItems} item(s), has ${value.length}`);
    if (schema.uniqueItems) {
      const seen = new Set();
      value.forEach((v, i) => {
        const k = JSON.stringify(v);
        if (seen.has(k))
          out.push({
            path: `${path}[${i}]`,
            message: "duplicate item",
            rule: "schema",
          });
        seen.add(k);
      });
    }
    if (schema.items)
      value.forEach((v, i) =>
        validateNode(v, schema.items, `${path}[${i}]`, root, out),
      );
  }

  if (typeOf(value) === "object") {
    for (const k of schema.required ?? [])
      if (!(k in value))
        out.push({
          path: `${path}.${k}`,
          message: "is required",
          rule: "schema",
        });
    if (schema.additionalProperties === false && schema.properties)
      for (const k of Object.keys(value))
        if (!(k in schema.properties))
          out.push({
            path: `${path}.${k}`,
            message: `unknown key (allowed: ${Object.keys(schema.properties).join(", ")})`,
            rule: "schema",
          });
    for (const [k, sub] of Object.entries(schema.properties ?? {}))
      if (k in value) validateNode(value[k], sub, `${path}.${k}`, root, out);
  }
}

// ------------------------------------------------------------- 3. the x-rules
//
// Each takes a context and pushes findings. `ctx.doc` is the instance,
// `ctx.peers` maps a schema name to {path, doc} for every other file given,
// `ctx.f(path, msg)` records a finding, `ctx.skip(why)` records a check that
// could not run. Rules with a `peer` in x-rules are only called when the peer
// is present; the driver records the skip otherwise.

const dup = (xs) => {
  const seen = new Set(),
    out = new Set();
  for (const x of xs) (seen.has(x) ? out : seen).add(x);
  return [...out];
};
const has = (o, k) => o !== null && typeof o === "object" && k in o;
const digest = (abs) =>
  createHash("sha256").update(readFileSync(abs)).digest("hex");

// Exactly-one-of: the idiom every "absence carries a reason" pair uses.
function xor1(ctx, obj, path, a, b, rule) {
  const A = has(obj, a),
    B = has(obj, b);
  if (A && B) ctx.f(`${path}`, `${a} and ${b} are mutually exclusive`, rule);
  if (!A && !B)
    ctx.f(`${path}`, `exactly one of ${a} and ${b} is required`, rule);
}

const RULES = {
  "fork-register": {
    "entry-ids-unique": (ctx) => {
      for (const id of dup(ctx.doc.entries.map((e) => e.id)))
        ctx.f("entries", `duplicate entry id '${id}'`, "entry-ids-unique");
    },
    "reading-ids-unique-within-entry": (ctx) =>
      ctx.entries((e, p) => {
        for (const id of dup((e.readings ?? []).map((r) => r.id)))
          ctx.f(
            `${p}.readings`,
            `duplicate reading id '${id}'`,
            "reading-ids-unique-within-entry",
          );
      }),
    "taken-names-a-live-reading": (ctx) =>
      ctx.entries((e, p) => {
        const r = (e.readings ?? []).find((x) => x.id === e.taken?.reading);
        if (!r)
          ctx.f(
            `${p}.taken.reading`,
            `'${e.taken?.reading}' is not a reading id of entry '${e.id}'`,
            "taken-names-a-live-reading",
          );
        else if (r.status !== "live")
          ctx.f(
            `${p}.taken.reading`,
            `reading '${r.id}' has status '${r.status}'; the reading taken must be live`,
            "taken-names-a-live-reading",
          );
      }),
    "at-least-one-live-reading": (ctx) =>
      ctx.entries((e, p) => {
        if (!(e.readings ?? []).some((r) => r.status === "live"))
          ctx.f(
            `${p}.readings`,
            "no reading is live",
            "at-least-one-live-reading",
          );
      }),
    "materialisation-implies-field": (ctx) =>
      ctx.entries((e, p) => {
        const want = {
          "interpretation-field": ["interpretation_field", "delegated_field"],
          "delegated-to-fact": ["delegated_field", "interpretation_field"],
          "resolved-at-encode": [null, null],
        }[e.materialisation];
        if (!want) return;
        const [need, forbid] = want;
        for (const k of ["interpretation_field", "delegated_field"]) {
          if (k === need && !has(e, k))
            ctx.f(
              `${p}.${k}`,
              `materialisation '${e.materialisation}' requires it`,
              "materialisation-implies-field",
            );
          if ((k === forbid || need === null) && has(e, k))
            ctx.f(
              `${p}.${k}`,
              `materialisation '${e.materialisation}' forbids it`,
              "materialisation-implies-field",
            );
        }
      }),
    "materialisation-implies-mechanism": (ctx) =>
      ctx.entries((e, p) => {
        const want = {
          "interpretation-field": "TYPICALLY",
          "resolved-at-encode": "encoded",
          "delegated-to-fact": "fact-supplied",
        }[e.materialisation];
        if (want && e.taken?.mechanism !== want)
          ctx.f(
            `${p}.taken.mechanism`,
            `materialisation '${e.materialisation}' requires mechanism '${want}', got '${e.taken?.mechanism}'`,
            "materialisation-implies-mechanism",
          );
      }),
    "interpretation-fields-unique": (ctx) => {
      for (const f of dup(
        ctx.doc.entries.map((e) => e.interpretation_field).filter(Boolean),
      ))
        ctx.f(
          "entries",
          `two entries claim Interpretation field '${f}'; R4 maps them 1:1`,
          "interpretation-fields-unique",
        );
    },
    "non-live-readings-explain": (ctx) =>
      ctx.entries((e, p) =>
        (e.readings ?? []).forEach((r, i) => {
          // 'arguable' is deliberately exempt: nothing rejected it, so it owes
          // `foreclosure` instead — enforced by the next rule.
          if (
            r.status !== "live" &&
            r.status !== "arguable" &&
            !has(r, "rejection_rationale")
          )
            ctx.f(
              `${p}.readings[${i}].rejection_rationale`,
              `status '${r.status}' requires it`,
              "non-live-readings-explain",
            );
        }),
      ),
    "arguable-readings-cite-and-foreclose": (ctx) =>
      ctx.entries((e, p) =>
        (e.readings ?? []).forEach((r, i) => {
          const at = `${p}.readings[${i}]`;
          if (r.status === "arguable") {
            if ((r.citations ?? []).length === 0)
              ctx.f(
                `${at}.citations`,
                "an arguable reading must cite the text that makes it arguable",
                "arguable-readings-cite-and-foreclose",
              );
            if (!has(r, "foreclosure"))
              ctx.f(
                `${at}.foreclosure`,
                "an arguable reading must say what makes it non-operative",
                "arguable-readings-cite-and-foreclose",
              );
            if (has(r, "rejection_rationale"))
              ctx.f(
                `${at}.rejection_rationale`,
                "an arguable reading was not rejected; use foreclosure",
                "arguable-readings-cite-and-foreclose",
              );
          } else if (has(r, "foreclosure")) {
            ctx.f(
              `${at}.foreclosure`,
              `foreclosure is for status 'arguable', not '${r.status}'`,
              "arguable-readings-cite-and-foreclose",
            );
          }
        }),
      ),
    "live-readings-cite-their-licence": (ctx) =>
      ctx.entries((e, p) =>
        (e.readings ?? []).forEach((r, i) => {
          if (r.status === "live" && (r.citations ?? []).length === 0)
            ctx.f(
              `${p}.readings[${i}].citations`,
              "a live reading must cite the text that licenses it",
              "live-readings-cite-their-licence",
            );
        }),
      ),
    "settled-or-demoted-requires-authority": (ctx) =>
      ctx.entries((e, p) => {
        const needs = e.status === "settled" || e.status === "demoted";
        if (needs && !has(e, "settled_by"))
          ctx.f(
            `${p}.settled_by`,
            `status '${e.status}' requires it`,
            "settled-or-demoted-requires-authority",
          );
        if (!needs && has(e, "settled_by"))
          ctx.f(
            `${p}.settled_by`,
            `status '${e.status}' forbids it`,
            "settled-or-demoted-requires-authority",
          );
      }),
    "demoted-requires-a-demoted-reading": (ctx) =>
      ctx.entries((e, p) => {
        if (
          e.status === "demoted" &&
          !(e.readings ?? []).some((r) => r.status === "demoted")
        )
          ctx.f(
            `${p}.readings`,
            "status 'demoted' but no reading is demoted",
            "demoted-requires-a-demoted-reading",
          );
      }),
    "quote-or-absent-reason": (ctx) =>
      ctx.entries((e, p) =>
        xor1(
          ctx,
          e.source ?? {},
          `${p}.source`,
          "quote",
          "quote_absent_reason",
          "quote-or-absent-reason",
        ),
      ),
    "materialised-forks-declare-divergence": (ctx) =>
      ctx.entries((e, p) => {
        if (
          e.materialisation === "interpretation-field" &&
          !has(e, "divergence")
        )
          ctx.f(
            `${p}.divergence`,
            "a materialised fork must declare divergence (possibly 'unassessed')",
            "materialised-forks-declare-divergence",
          );
      }),
    "observable-divergence-requires-witnesses": (ctx) =>
      ctx.entries((e, p) => {
        if (e.divergence === "observable" && (e.witnesses ?? []).length === 0)
          ctx.f(
            `${p}.witnesses`,
            "divergence 'observable' requires at least one witness",
            "observable-divergence-requires-witnesses",
          );
      }),
    "witnesses-only-when-observable": (ctx) =>
      ctx.entries((e, p) => {
        if ((e.witnesses ?? []).length > 0 && e.divergence !== "observable")
          ctx.f(
            `${p}.witnesses`,
            `witnesses given but divergence is '${e.divergence ?? "(absent)"}'`,
            "witnesses-only-when-observable",
          );
      }),
    "empty-register-explains": (ctx) => {
      if (ctx.doc.entries.length === 0 && !has(ctx.doc, "note"))
        ctx.f(
          "note",
          "a register with no entries must say why",
          "empty-register-explains",
        );
    },
    "cross-refs-resolve": (ctx) => {
      const ids = new Set(
        ctx.peers["external-modifications"].doc.entries.map((e) => e.id),
      );
      ctx.entries((e, p) => {
        (e.cross_refs ?? []).forEach((r, i) => {
          if (!ids.has(r))
            ctx.f(
              `${p}.cross_refs[${i}]`,
              `'${r}' is not an external-modifications entry id`,
              "cross-refs-resolve",
            );
        });
        const x = e.settled_by?.external_modification;
        if (x !== undefined && !ids.has(x))
          ctx.f(
            `${p}.settled_by.external_modification`,
            `'${x}' is not an external-modifications entry id`,
            "cross-refs-resolve",
          );
      });
    },
    "peer-subjects-agree": (ctx) => ctx.subjectsAgree(),
  },

  "external-modifications": {
    "entry-ids-unique": (ctx) => {
      for (const id of dup(ctx.doc.entries.map((e) => e.id)))
        ctx.f("entries", `duplicate entry id '${id}'`, "entry-ids-unique");
    },
    "search-ids-unique": (ctx) => {
      for (const id of dup(ctx.doc.searches.map((s) => s.id)))
        ctx.f("searches", `duplicate search id '${id}'`, "search-ids-unique");
    },
    "search-outcome-matches-findings": (ctx) =>
      ctx.doc.searches.forEach((s, i) => {
        const n = (s.findings ?? []).length;
        if (s.outcome === "no-findings" && n > 0)
          ctx.f(
            `searches[${i}].findings`,
            `outcome 'no-findings' but ${n} finding(s) listed`,
            "search-outcome-matches-findings",
          );
        if (s.outcome === "findings" && n === 0)
          ctx.f(
            `searches[${i}].findings`,
            "outcome 'findings' but none listed",
            "search-outcome-matches-findings",
          );
      }),
    "search-findings-resolve": (ctx) => {
      const ids = new Set(ctx.doc.entries.map((e) => e.id));
      ctx.doc.searches.forEach((s, i) =>
        (s.findings ?? []).forEach((f, j) => {
          if (!ids.has(f))
            ctx.f(
              `searches[${i}].findings[${j}]`,
              `'${f}' is not an entry id`,
              "search-findings-resolve",
            );
        }),
      );
    },
    "findings-attributed-to-a-search": (ctx) => {
      const byId = new Map(ctx.doc.searches.map((s) => [s.id, s]));
      ctx.entries((e, p) =>
        (e.found_by ?? []).forEach((s, i) => {
          const search = byId.get(s);
          if (!search)
            ctx.f(
              `${p}.found_by[${i}]`,
              `'${s}' is not a search id`,
              "findings-attributed-to-a-search",
            );
          else if (!(search.findings ?? []).includes(e.id))
            ctx.f(
              `${p}.found_by[${i}]`,
              `search '${s}' does not list entry '${e.id}' in its findings`,
              "findings-attributed-to-a-search",
            );
        }),
      );
    },
    "binding-effect-declared": (ctx) =>
      ctx.entries((e, p) => {
        if (e.class === "binding" && !has(e, "binding_effect"))
          ctx.f(
            `${p}.binding_effect`,
            "class 'binding' requires it",
            "binding-effect-declared",
          );
        if (e.class !== "binding" && has(e, "binding_effect"))
          ctx.f(
            `${p}.binding_effect`,
            `class '${e.class}' forbids it`,
            "binding-effect-declared",
          );
      }),
    "suppressive-effects-need-a-rule-version-arm": (ctx) =>
      ctx.entries((e, p) => {
        if (
          ["struck", "stayed", "read-down"].includes(e.binding_effect) &&
          !has(e.routing ?? {}, "rule_version_arm")
        )
          ctx.f(
            `${p}.routing.rule_version_arm`,
            `binding_effect '${e.binding_effect}' requires it: the provision stays encoded, marked inoperative on the rule-version axis`,
            "suppressive-effects-need-a-rule-version-arm",
          );
      }),
    "binding-routes-into-the-encoding": (ctx) =>
      ctx.entries((e, p) => {
        if (e.class !== "binding" || e.disposition !== "encoded") return;
        if (
          !has(e.routing ?? {}, "rule_version_arm") &&
          (e.routing?.fork_ids ?? []).length === 0
        )
          ctx.f(
            `${p}.routing`,
            "a binding modification disposed as 'encoded' must name where it landed: a rule_version_arm or a fork id",
            "binding-routes-into-the-encoding",
          );
      }),
    "interpretive-routes-to-a-fork": (ctx) =>
      ctx.entries((e, p) => {
        if (e.class !== "interpretive") return;
        if (!["encoded", "deferred"].includes(e.disposition)) return;
        if ((e.routing?.fork_ids ?? []).length === 0)
          ctx.f(
            `${p}.routing.fork_ids`,
            `class 'interpretive' disposed as '${e.disposition}' must name the fork it opens or settles`,
            "interpretive-routes-to-a-fork",
          );
      }),
    "prospective-dated-or-flagged": (ctx) =>
      ctx.entries((e, p) => {
        if (e.class !== "prospective") return;
        const r = e.routing ?? {};
        if (has(r, "effective_from")) return;
        if (r.currency_risk !== true)
          ctx.f(
            `${p}.routing.currency_risk`,
            "an undated prospective change must be flagged as a currency risk",
            "prospective-dated-or-flagged",
          );
        if (!has(r, "effective_from_absent_reason"))
          ctx.f(
            `${p}.routing.effective_from_absent_reason`,
            "required when a prospective change carries no date",
            "prospective-dated-or-flagged",
          );
      }),
    "url-or-absent-reason": (ctx) =>
      ctx.entries((e, p) =>
        xor1(
          ctx,
          e.provenance ?? {},
          `${p}.provenance`,
          "url",
          "url_absent_reason",
          "url-or-absent-reason",
        ),
      ),
    "effective-from-exclusive": (ctx) =>
      ctx.entries((e, p) => {
        const r = e.routing ?? {};
        if (has(r, "effective_from") && has(r, "effective_from_absent_reason"))
          ctx.f(
            `${p}.routing`,
            "effective_from and effective_from_absent_reason are mutually exclusive",
            "effective-from-exclusive",
          );
      }),
    "disposition-entry-resolves": (ctx) => {
      const ids = new Set(ctx.doc.entries.map((e) => e.id));
      ctx.doc.dispositions.forEach((d, i) => {
        if (has(d, "entry") && !ids.has(d.entry))
          ctx.f(
            `dispositions[${i}].entry`,
            `'${d.entry}' is not an entry id`,
            "disposition-entry-resolves",
          );
      });
    },
    "markers-disposed-once": (ctx) => {
      const seen = new Map();
      ctx.doc.dispositions.forEach((d, i) => {
        for (const m of d.markers ?? []) {
          const k = `${d.document}/${m}`;
          if (seen.has(k))
            ctx.f(
              `dispositions[${i}].markers`,
              `marker '${m}' of document '${d.document}' is already disposed at dispositions[${seen.get(k)}]`,
              "markers-disposed-once",
            );
          else seen.set(k, i);
        }
      });
    },
    "empty-register-explains": (ctx) => {
      if (ctx.doc.entries.length === 0 && !has(ctx.doc, "note"))
        ctx.f(
          "note",
          "a sweep that found nothing must say so",
          "empty-register-explains",
        );
    },
    "fork-refs-resolve": (ctx) => {
      const ids = new Set(
        ctx.peers["fork-register"].doc.entries.map((e) => e.id),
      );
      ctx.entries((e, p) =>
        (e.routing?.fork_ids ?? []).forEach((f, i) => {
          if (!ids.has(f))
            ctx.f(
              `${p}.routing.fork_ids[${i}]`,
              `'${f}' is not a fork-register entry id`,
              "fork-refs-resolve",
            );
        }),
      );
    },
    "dispositions-name-bundle-markers": (ctx) => {
      const docs = new Map(
        ctx.peers["source-bundle"].doc.documents.map((d) => [
          d.id,
          new Set((d.annotations ?? []).flatMap((g) => g.markers ?? [])),
        ]),
      );
      ctx.doc.dispositions.forEach((d, i) => {
        const inv = docs.get(d.document);
        if (!inv) {
          ctx.f(
            `dispositions[${i}].document`,
            `'${d.document}' is not a source-bundle document id`,
            "dispositions-name-bundle-markers",
          );
          return;
        }
        (d.markers ?? []).forEach((m, j) => {
          if (!inv.has(m))
            ctx.f(
              `dispositions[${i}].markers[${j}]`,
              `'${m}' is not in document '${d.document}'s annotation inventory`,
              "dispositions-name-bundle-markers",
            );
        });
      });
    },
    "annotation-inventory-disposed": (ctx) => {
      const disposed = new Set(
        ctx.doc.dispositions.flatMap((d) =>
          (d.markers ?? []).map((m) => `${d.document}/${m}`),
        ),
      );
      for (const d of ctx.peers["source-bundle"].doc.documents)
        for (const g of d.annotations ?? []) {
          if (!g.inventory_complete) continue;
          for (const m of g.markers ?? [])
            if (!disposed.has(`${d.id}/${m}`))
              ctx.f(
                "dispositions",
                `${d.id}: annotation '${m}' (${g.scheme}) has no disposition, and the inventory declares itself complete`,
                "annotation-inventory-disposed",
              );
        }
    },
    "peer-subjects-agree": (ctx) => ctx.subjectsAgree(),
  },

  "source-bundle": {
    "document-ids-unique": (ctx) => {
      for (const id of dup(ctx.doc.documents.map((d) => d.id)))
        ctx.f(
          "documents",
          `duplicate document id '${id}'`,
          "document-ids-unique",
        );
    },
    "archive-method-requires-archive-url": (ctx) =>
      ctx.docs((d, p) => {
        if (d.retrieval_method === "archive" && !has(d, "archive_url"))
          ctx.f(
            `${p}.archive_url`,
            "retrieval_method 'archive' requires it",
            "archive-method-requires-archive-url",
          );
        if (d.retrieval_method !== "archive" && has(d, "archive_url"))
          ctx.f(
            `${p}.archive_url`,
            `retrieval_method '${d.retrieval_method}' forbids it`,
            "archive-method-requires-archive-url",
          );
      }),
    "integrity-digest-or-immutable-capture": (ctx) =>
      ctx.docs((d, p) => {
        xor1(
          ctx,
          d.integrity ?? {},
          `${p}.integrity`,
          "sha256",
          "sha256_absent_reason",
          "integrity-digest-or-immutable-capture",
        );
        if (!has(d.integrity ?? {}, "sha256") && !has(d, "archive_url"))
          ctx.f(
            `${p}.integrity.sha256`,
            "a document with no digest must be pinned by an archive_url",
            "integrity-digest-or-immutable-capture",
          );
      }),
    "digest-matches-local-file": (ctx) =>
      ctx.docs((d, p) => {
        const lp = d.integrity?.local_path;
        if (!lp || !has(d.integrity, "sha256")) return;
        const abs = resolve(REPO, lp);
        if (!existsSync(abs)) {
          ctx.skip(
            "digest-matches-local-file",
            `${p}: ${lp} is not on this branch`,
          );
          return;
        }
        const got = digest(abs);
        if (got !== d.integrity.sha256)
          ctx.f(
            `${p}.integrity.sha256`,
            `recorded ${d.integrity.sha256}, file hashes ${got}`,
            "digest-matches-local-file",
          );
      }),
    "assembled-digest-matches": (ctx) => {
      const a = ctx.doc.assembled;
      if (!a) {
        ctx.skip(
          "assembled-digest-matches",
          "no assembled artifact is declared",
        );
        return;
      }
      const abs = resolve(REPO, a.local_path);
      if (!existsSync(abs)) {
        ctx.skip(
          "assembled-digest-matches",
          `${a.local_path} is not on this branch`,
        );
        return;
      }
      const got = digest(abs);
      if (got !== a.sha256)
        ctx.f(
          "assembled.sha256",
          `recorded ${a.sha256}, file hashes ${got}`,
          "assembled-digest-matches",
        );
    },
    "covers-or-absent-reason": (ctx) =>
      ctx.docs((d, p) =>
        xor1(
          ctx,
          d,
          p,
          "covers",
          "covers_absent_reason",
          "covers-or-absent-reason",
        ),
      ),
    "covers-range-ordered": (ctx) =>
      ctx.docs((d, p) => {
        const c = d.covers;
        if (
          !c ||
          c.from === null ||
          c.to === null ||
          c.from === undefined ||
          c.to === undefined
        )
          return;
        if (c.from > c.to)
          ctx.f(
            `${p}.covers`,
            `from ${c.from} is after to ${c.to}`,
            "covers-range-ordered",
          );
      }),
    "in-force-or-absent-reason": (ctx) => {
      xor1(
        ctx,
        ctx.doc,
        "",
        "in_force",
        "in_force_absent_reason",
        "in-force-or-absent-reason",
      );
      const ref = ctx.doc.in_force?.document;
      if (ref !== undefined && !ctx.doc.documents.some((d) => d.id === ref))
        ctx.f(
          "in_force.document",
          `'${ref}' is not a document id of this bundle`,
          "in-force-or-absent-reason",
        );
    },
    "annotation-markers-unique-within-document": (ctx) =>
      ctx.docs((d, p) => {
        for (const m of dup(
          (d.annotations ?? []).flatMap((g) => g.markers ?? []),
        ))
          ctx.f(
            `${p}.annotations`,
            `marker '${m}' appears twice`,
            "annotation-markers-unique-within-document",
          );
      }),
    "incomplete-inventory-explains": (ctx) =>
      ctx.docs((d, p) =>
        (d.annotations ?? []).forEach((g, i) => {
          if (g.inventory_complete === false && !has(g, "inventory_note"))
            ctx.f(
              `${p}.annotations[${i}].inventory_note`,
              "inventory_complete false requires it",
              "incomplete-inventory-explains",
            );
        }),
      ),
    "peer-subjects-agree": (ctx) => ctx.subjectsAgree(),
  },
};

// ------------------------------------------------------------------ 4. driver

function readInstance(path) {
  const abs = resolve(process.cwd(), path);
  if (!existsSync(abs)) die(`file not found: ${abs}`);
  try {
    return JSON.parse(readFileSync(abs, "utf8"));
  } catch (e) {
    die(`${abs} is not valid JSON: ${e.message}`);
  }
}

// Validate one instance against its schema and its x-rules. `peers` maps schema
// name -> {path, doc}. Returns {findings, skips, rulesRun}.
export function validateInstance(name, doc, path, peers = {}) {
  const schema = loadSchema(name);
  const findings = [];
  const skips = [];
  validateNode(doc, schema, "", schema, findings);

  // Structural findings mean the shape is not what the rules assume; running
  // them anyway produces cascades that bury the real message.
  if (findings.length)
    return { findings, skips, rulesRun: 0, structuralOnly: true };

  const ctx = {
    doc,
    path,
    peers,
    f: (p, message, rule) => findings.push({ path: p, message, rule }),
    skip: (rule, why) => skips.push({ rule, why }),
    entries: (fn) =>
      (doc.entries ?? []).forEach((e, i) => fn(e, `entries[${i}]`)),
    docs: (fn) =>
      (doc.documents ?? []).forEach((d, i) => fn(d, `documents[${i}]`)),
    subjectsAgree: () => {
      for (const [k, v] of Object.entries(peers))
        if (v.doc.subject !== doc.subject)
          findings.push({
            path: "subject",
            message: `'${doc.subject}' but ${k} (${v.path}) says '${v.doc.subject}'`,
            rule: "peer-subjects-agree",
          });
    },
  };

  let rulesRun = 0;
  for (const decl of schema["x-rules"]) {
    if (decl.peer === "any" && Object.keys(peers).length === 0) {
      skips.push({ rule: decl.id, why: "no peer file was given" });
      continue;
    }
    if (decl.peer && decl.peer !== "any" && !peers[decl.peer]) {
      skips.push({ rule: decl.id, why: `no ${decl.peer} file was given` });
      continue;
    }
    RULES[name][decl.id](ctx);
    rulesRun++;
  }
  return { findings, skips, rulesRun, structuralOnly: false };
}

function usage(code) {
  const w = code === 0 ? process.stdout : process.stderr;
  w.write(
    `usage: register-validate.mjs <schema> <file> [peer-file ...]\n` +
      `       register-validate.mjs --rules <schema>\n\n` +
      `  <schema>     one of: ${SCHEMA_NAMES.join(" · ")}\n` +
      `  peer-file    any of the other two registers; identified by its own 'kind'\n` +
      `               field, validated in its own right, and used by the cross-file\n` +
      `               rules. A cross-file rule whose peer is absent is reported as\n` +
      `               'skip', never silently passed.\n\n` +
      `exit: 0 clean · 1 a finding · 2 usage / unreadable file / unenforceable schema\n`,
  );
  process.exit(code);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const argv = process.argv.slice(2);
  if (argv.length === 0 || argv[0] === "--help" || argv[0] === "-h")
    usage(argv.length ? 0 : 2);
  if (argv[0] === "--rules") {
    const name = argv[1];
    if (!SCHEMA_NAMES.includes(name))
      die(`unknown schema '${name}' (have: ${SCHEMA_NAMES.join(", ")})`);
    for (const r of loadSchema(name)["x-rules"])
      process.stdout.write(
        `${r.id}${r.peer ? ` (peer: ${r.peer})` : ""}\n    ${r.description}\n`,
      );
    process.exit(0);
  }

  const [name, file, ...peerFiles] = argv;
  if (!SCHEMA_NAMES.includes(name))
    die(`unknown schema '${name}' (have: ${SCHEMA_NAMES.join(", ")})`);
  if (!file) usage(2);

  const doc = readInstance(file);
  if (doc.kind !== name)
    die(
      `${file}: kind is ${JSON.stringify(doc.kind)}, expected ${JSON.stringify(name)}`,
    );

  const peers = {};
  for (const pf of peerFiles) {
    const pd = readInstance(pf);
    if (!SCHEMA_NAMES.includes(pd.kind))
      die(`${pf}: kind ${JSON.stringify(pd.kind)} names no known schema`);
    if (pd.kind === name) die(`${pf}: a second ${name} file is not a peer`);
    if (peers[pd.kind]) die(`${pf}: two ${pd.kind} files were given`);
    peers[pd.kind] = { path: pf, doc: pd };
  }

  let total = 0;
  const report = (label, r) => {
    process.stdout.write(
      `register-validate: ${label}\n` +
        `  ${r.structuralOnly ? "structural check failed; x-rules not run" : `${r.rulesRun} rule(s) checked`}` +
        `${r.skips.length ? `, ${r.skips.length} skipped` : ""}\n`,
    );
    for (const s of r.skips)
      process.stdout.write(`  skip ${s.rule} — ${s.why}\n`);
    for (const f of r.findings) {
      total++;
      process.stdout.write(
        `  FAIL ${f.path || "(root)"}: ${f.message} [${f.rule}]\n`,
      );
    }
  };

  // Every file given is validated in its own right, each seeing the others as
  // peers — so a cross-file rule owned by a peer schema (the bundle/annotation
  // completeness join, which lives on external-modifications) runs whenever the
  // files it needs are on the command line, whichever one was named primary.
  // Peers are reported first: a cross-file rule joining over a malformed peer
  // would otherwise report the primary file's paths for the peer's defects.
  const all = { ...peers, [name]: { path: file, doc } };
  const others = (k) =>
    Object.fromEntries(Object.entries(all).filter(([j]) => j !== k));
  for (const [k, v] of Object.entries(peers))
    report(`${k} ${v.path}`, validateInstance(k, v.doc, v.path, others(k)));
  report(`${name} ${file}`, validateInstance(name, doc, file, peers));

  process.stdout.write(
    total === 0
      ? "register-validate: ok\n"
      : `register-validate: ${total} finding(s)\n`,
  );
  process.exit(total === 0 ? 0 : 1);
}

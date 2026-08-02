// Validate emitted DMN 1.3 XML in two layers:
//
//   1. WELL-FORMEDNESS -- a dependency-free lexical scan (plus `xmllint --noout`
//      when it is on PATH), in front of moddle. See the block above
//      `wellFormed` for why this cannot be left to moddle (smucclaw#937).
//   2. THE METAMODEL -- `dmn-moddle`, the moddle descriptor Camunda's own DMN
//      tooling (dmn-js / dmn-migrate) is built on. dmn-moddle knows the DMN 1.3
//      metamodel, so it reports unknown elements, unknown attributes, and
//      children that do not belong to the type they appear under.
//
// It does NOT check XSD sequence order, and it does not execute anything. Read
// "0 warnings" as "this file is well-formed XML, and every element and attribute
// we emitted is one DMN 1.3 defines, in a place it is allowed to be", not as
// "Camunda will import this".
//
// Run WITHOUT installing anything into the repo (package.json and the lockfile
// are deliberately left alone):
//
//   npx --yes --package=dmn-moddle node etc/validate-dmn.mjs jl4/examples/dmn/expected/reg-cf.dmn
//
// With no arguments it validates every *.dmn under jl4/examples/dmn/expected/.
// Exits non-zero if any file fails to parse or produces warnings.
//
// ---------------------------------------------------------------------------
// THE dmnmd LEGS (local evidence, not CI)
//
// `dmnmd` is a separate repo and must NOT become a build dependency. This script
// uses it when it is present on this machine and skips silently otherwise. The
// Homebrew-shimmed ~/.local/bin/dmnmd is broken here (missing libpcre.1.dylib);
// the working binary is the cabal-built one, and DMNMD= overrides the path:
//
//   DMNMD=/Users/mengwong/src/smucclaw/dmnmd/languages/haskell/dist-newstyle/build/\
//   aarch64-osx/ghc-9.10.3/dmnmd-0.1.0.2/x/dmnmd/build/dmnmd/dmnmd \
//     npx --yes --package=dmn-moddle node etc/validate-dmn.mjs
//
// Then, to close the round trip (this part is not automated here because it
// needs the L4 toolchain):
//
//   dmnmd -f md -t l4 jl4/examples/dmn/expected/reg-cf.dmn.md > /tmp/rt.l4
//   cabal run l4 -- check /tmp/rt.l4
//
// THE DIFFERENTIAL. Both emitters feed one IR, and dmnmd reads both formats and
// writes L4, so the two legs should produce the same L4 -- a consistency check
// with a neutral referee. The XML leg is BLOCKED today; the harness is written
// and guarded so it switches on when dmnmd is fixed. Four independent blockers,
// in the order they surface (see BUILD-SPEC-dmnmd-extensions.md; only the last
// is the specified E0a):
//
//   1. `<inputData>` carrying a `<variable>` child -> "xpCheckEmptyContents:
//      unprocessed XML content detected". The unpickler does not model the
//      element, and `<variable>` is how DMN names a decision's output.
//   2. `<output>` without a `label` attribute -> "no attribute value found for
//      label". `label` is OPTIONAL in DMN 1.3; dmnmd requires it.
//   3. `<defaultOutputEntry>` -> unmodelled, same unpickling failure.
//   4. E0a: XmlToDmnmd.convertType maps XSD names, so it knows "integer" and not
//      "number" -- and `number` is THE FEEL numeric type that every real 1.3
//      producer emits. Dies with `Unknown type: "number"`.
//
// Verified by stripping each blocker in turn from our own output until a minimal
// numeric table reached blocker 4.

import { readFile, readdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

// `npx --package=X node script.mjs` installs X into ~/.npm/_npx/<hash>/node_modules
// and puts only its .bin on PATH -- node still resolves `require` from the
// SCRIPT's directory, which is inside the repo and has no node_modules. So find
// the npx cache directory on PATH and require from there. This is the price of
// not adding a dependency to package.json; the lockfile on this repo is already
// drifted and a new entry would block CI.
function loadDmnModdle() {
  const candidates = [import.meta.url];
  for (const entry of (process.env.PATH ?? "").split(":")) {
    if (entry.includes("_npx") && entry.endsWith("node_modules/.bin")) {
      candidates.push(join(dirname(entry), "anchor.js"));
    }
  }
  const failures = [];
  for (const from of candidates) {
    try {
      const mod = createRequire(from)("dmn-moddle");
      // dmn-moddle 12 is CJS and exports { DmnModdle }; older majors default-exported it.
      return mod.DmnModdle ?? mod.default ?? mod;
    } catch (err) {
      failures.push(err.message);
    }
  }
  console.error(
    "could not load dmn-moddle. Run this script as:\n" +
      "  npx --yes --package=dmn-moddle node etc/validate-dmn.mjs\n" +
      failures.map((m) => `  - ${m}`).join("\n"),
  );
  process.exit(2);
}

const DmnModdle = loadDmnModdle();

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const defaultDir = join(repoRoot, "jl4", "examples", "dmn", "expected");

async function targets() {
  const args = process.argv.slice(2);
  if (args.length > 0) return args;
  const entries = await readdir(defaultDir);
  return entries
    .filter((f) => f.endsWith(".dmn") && !f.endsWith(".actual.dmn"))
    .map((f) => join(defaultDir, f));
}

// ---------------------------------------------------------------------------
// Well-formedness, in front of moddle (smucclaw/l4-ide#937)
//
// dmn-moddle is NOT a well-formedness backstop, and its `OK` was being read as
// one throughout CI and the go pipeline. Measured 2026-08-03: a DMN file with
// `--` inside an XML comment makes xmllint exit 1, Camunda refuse with "Unable
// to parse model" and KIE exit 1 -- while this script printed
// `OK -- 40 decision(s), 0 warnings`, because moddle's parser is lenient about
// comment contents.
//
// Two legs, deliberately both:
//
//   * `wellFormed` below is a dependency-free scanner that runs EVERYWHERE, so
//     the gate's strictness does not depend on what happens to be installed on
//     the machine. It is minimal by design -- it checks the lexical rules a
//     lenient parser skips (comment contents, tag matching, attribute quoting
//     and duplication, reference syntax, single root) and does NOT validate
//     namespaces, DTDs or character classes.
//   * `xmllint --noout` runs IN ADDITION when it is on PATH, as the reference
//     implementation. It is never required: ubuntu runners do not all ship
//     libxml2-utils, and a gate that silently weakens on a missing binary is
//     the exact failure #937 is about.
//
// A well-formedness failure is fatal for the file: moddle is not consulted,
// because "OK" past this point would be the false claim again.
// ---------------------------------------------------------------------------

const NAME_START = /[A-Za-z_:]/;
const NAME_CHAR = /[-A-Za-z0-9._:]/;

function lineOf(xml, i) {
  let line = 1;
  for (let k = 0; k < i && k < xml.length; k++) if (xml[k] === "\n") line++;
  return line;
}

// Returns [] when well-formed, else a list of "line N: message" strings. Stops
// at the first structural error -- past one, positions are noise.
function wellFormed(xml) {
  const err = (i, msg) => [`line ${lineOf(xml, i)}: ${msg}`];
  const stack = [];
  let rootSeen = false;
  let i = 0;

  const readName = (k) => {
    if (k >= xml.length || !NAME_START.test(xml[k])) return null;
    let j = k + 1;
    while (j < xml.length && NAME_CHAR.test(xml[j])) j++;
    return [xml.slice(k, j), j];
  };

  // `&name;`, `&#123;`, `&#xAB;` -- anything else is a bare ampersand.
  const checkRefs = (text, at) => {
    for (let k = 0; k < text.length; k++) {
      if (text[k] !== "&") continue;
      const semi = text.indexOf(";", k);
      const body = semi < 0 ? "" : text.slice(k + 1, semi);
      const ok =
        semi > k + 1 &&
        (/^#[0-9]+$/.test(body) ||
          /^#[xX][0-9a-fA-F]+$/.test(body) ||
          (NAME_START.test(body[0]) &&
            [...body].every((c) => NAME_CHAR.test(c))));
      if (!ok) return err(at + k, "bare '&' or malformed entity reference");
      k = semi;
    }
    return [];
  };

  while (i < xml.length) {
    const lt = xml.indexOf("<", i);
    if (lt < 0) {
      const tail = xml.slice(i);
      if (stack.length && tail.trim()) return err(i, "text after last tag");
      const e = checkRefs(tail, i);
      if (e.length) return e;
      break;
    }
    const text = xml.slice(i, lt);
    if (!stack.length && text.trim() && rootSeen)
      return err(i, "character data outside the root element");
    const e = checkRefs(text, i);
    if (e.length) return e;
    i = lt;

    if (xml.startsWith("<!--", i)) {
      const end = xml.indexOf("-->", i + 4);
      if (end < 0) return err(i, "unterminated comment");
      const body = xml.slice(i + 4, end);
      // XML 1.0 §2.5: the comment's content may not contain `--`, and may not
      // end with `-`. This is the #937 case, and the one moddle waves through.
      const dd = body.indexOf("--");
      if (dd >= 0) return err(i + 4 + dd, "double hyphen within comment");
      if (body.endsWith("-")) return err(end, "comment ends with '-'");
      i = end + 3;
      continue;
    }
    if (xml.startsWith("<![CDATA[", i)) {
      const end = xml.indexOf("]]>", i + 9);
      if (end < 0) return err(i, "unterminated CDATA section");
      if (!stack.length) return err(i, "CDATA outside the root element");
      i = end + 3;
      continue;
    }
    if (xml.startsWith("<?", i)) {
      const end = xml.indexOf("?>", i + 2);
      if (end < 0) return err(i, "unterminated processing instruction");
      if (xml.startsWith("<?xml", i) && i !== 0)
        return err(
          i,
          "XML declaration must be the first thing in the document",
        );
      i = end + 2;
      continue;
    }
    if (xml.startsWith("<!", i)) {
      // DOCTYPE and friends: not modelled beyond bracket balance.
      let depth = 0;
      let j = i + 2;
      for (; j < xml.length; j++) {
        if (xml[j] === "[") depth++;
        else if (xml[j] === "]") depth--;
        else if (xml[j] === ">" && depth <= 0) break;
      }
      if (j >= xml.length) return err(i, "unterminated declaration");
      i = j + 1;
      continue;
    }

    const closing = xml[i + 1] === "/";
    const nm = readName(i + (closing ? 2 : 1));
    if (!nm) return err(i, "'<' not followed by a tag name");
    const [name, afterName] = nm;
    let j = afterName;

    if (closing) {
      while (j < xml.length && /\s/.test(xml[j])) j++;
      if (xml[j] !== ">") return err(j, `malformed end tag </${name}`);
      const open = stack.pop();
      if (open === undefined) return err(i, `unmatched end tag </${name}>`);
      if (open !== name)
        return err(i, `end tag </${name}> does not match <${open}>`);
      i = j + 1;
      continue;
    }

    const seen = new Set();
    for (;;) {
      while (j < xml.length && /\s/.test(xml[j])) j++;
      if (j >= xml.length) return err(i, `unterminated start tag <${name}`);
      if (xml[j] === ">" || xml.startsWith("/>", j)) break;
      const an = readName(j);
      if (!an) return err(j, `malformed attribute in <${name}>`);
      const [attr, afterAttr] = an;
      if (seen.has(attr))
        return err(j, `duplicate attribute '${attr}' on <${name}>`);
      seen.add(attr);
      let k = afterAttr;
      while (k < xml.length && /\s/.test(xml[k])) k++;
      if (xml[k] !== "=") return err(k, `attribute '${attr}' has no value`);
      k++;
      while (k < xml.length && /\s/.test(xml[k])) k++;
      const q = xml[k];
      if (q !== '"' && q !== "'")
        return err(k, `attribute '${attr}' value is not quoted`);
      const close = xml.indexOf(q, k + 1);
      if (close < 0)
        return err(k, `unterminated value for attribute '${attr}'`);
      const value = xml.slice(k + 1, close);
      if (value.includes("<"))
        return err(k, `'<' in the value of attribute '${attr}'`);
      const re = checkRefs(value, k + 1);
      if (re.length) return re;
      j = close + 1;
    }

    if (!stack.length) {
      if (rootSeen) return err(i, "more than one root element");
      rootSeen = true;
    }
    if (xml.startsWith("/>", j)) {
      i = j + 2;
    } else {
      stack.push(name);
      i = j + 1;
    }
  }

  if (stack.length)
    return [
      `unclosed element${stack.length > 1 ? "s" : ""}: <${stack.join(">, <")}>`,
    ];
  if (!rootSeen) return ["no root element"];
  return [];
}

const haveXmllint =
  spawnSync("xmllint", ["--version"], { encoding: "utf8" }).status === 0;

const moddle = new DmnModdle();
let failed = 0;

for (const file of await targets()) {
  const xml = await readFile(file, "utf8");

  const lex = wellFormed(xml);
  const lint = haveXmllint
    ? spawnSync("xmllint", ["--noout", file], { encoding: "utf8" })
    : null;
  if (lex.length || (lint && lint.status !== 0)) {
    console.error(
      `FAIL  ${file}  (not well-formed XML; moddle not consulted)\n` +
        lex.map((m) => `       ${m}`).join("\n") +
        (lint && lint.status !== 0
          ? (lex.length ? "\n" : "") +
            `       xmllint: ${(lint.stderr || "").trim().split("\n").slice(0, 3).join("\n       ")}`
          : ""),
    );
    failed++;
    continue;
  }

  let result;
  try {
    result = await moddle.fromXML(xml, "dmn:Definitions");
  } catch (err) {
    console.error(`FAIL  ${file}\n  ${err.message}`);
    failed++;
    continue;
  }

  const warnings = result.warnings ?? [];
  const defs = result.rootElement;
  const decisions = (defs.drgElement ?? []).filter(
    (e) => e.$type === "dmn:Decision",
  );
  const inputs = (defs.drgElement ?? []).filter(
    (e) => e.$type === "dmn:InputData",
  );
  const tables = decisions.filter(
    (d) => d.decisionLogic?.$type === "dmn:DecisionTable",
  );
  const literals = decisions.filter(
    (d) => d.decisionLogic?.$type === "dmn:LiteralExpression",
  );

  // Cross-check the two invariants a moddle parse will not: every rule is as
  // wide as the table, and every href resolves to an element in the file.
  const ids = new Set((defs.drgElement ?? []).map((e) => e.id));
  const problems = [];
  for (const d of tables) {
    const t = d.decisionLogic;
    const width = (t.input ?? []).length;
    for (const rule of t.rule ?? []) {
      if ((rule.inputEntry ?? []).length !== width) {
        problems.push(
          `rule ${rule.id}: ${(rule.inputEntry ?? []).length} input entries, table has ${width} columns`,
        );
      }
    }
  }
  for (const d of decisions) {
    for (const ir of d.informationRequirement ?? []) {
      const href = ir.requiredDecision?.href ?? ir.requiredInput?.href;
      if (!href || !href.startsWith("#") || !ids.has(href.slice(1))) {
        problems.push(
          `decision ${d.id}: dangling information requirement href ${href}`,
        );
      }
      if (ir.requiredDecision?.href === `#${d.id}`) {
        problems.push(
          `decision ${d.id}: requires itself (DMN 7.3.1 forbids this)`,
        );
      }
    }
  }

  const status =
    warnings.length === 0 && problems.length === 0 ? "OK   " : "WARN ";
  console.log(
    `${status} ${file}\n` +
      `       ${decisions.length} decision(s): ${tables.length} table(s), ${literals.length} literal expression(s); ` +
      `${inputs.length} inputData; ${(defs.dmnDI?.diagrams ?? []).length} diagram(s)`,
  );
  for (const w of warnings) console.log(`       moddle warning: ${w.message}`);
  for (const p of problems) console.log(`       structural: ${p}`);
  if (warnings.length || problems.length) failed++;
}

// ---------------------------------------------------------------------------
// dmnmd legs
// ---------------------------------------------------------------------------

const dmnmd = process.env.DMNMD;
if (!dmnmd || !existsSync(dmnmd)) {
  console.log(
    "SKIP  dmnmd legs (set DMNMD=<path to the cabal-built dmnmd binary> to run them)",
  );
} else {
  const mdFiles = (await readdir(defaultDir))
    .filter((f) => f.endsWith(".dmn.md"))
    .map((f) => join(defaultDir, f));

  for (const file of mdFiles) {
    const md = spawnSync(dmnmd, ["-v", "-f", "md", "-t", "l4", file], {
      encoding: "utf8",
    });
    const imported = /\* imported (\d+) tables\./.exec(md.stderr + md.stdout);
    if (md.status !== 0 || !imported) {
      console.error(`FAIL  ${file}\n  dmnmd could not read it:\n${md.stderr}`);
      failed++;
      continue;
    }
    console.log(
      `OK    ${file}\n       dmnmd -f md -t l4: imported ${imported[1]} table(s)`,
    );
    console.log(
      "       (now run `cabal run l4 -- check` on that output to close the round trip)",
    );
  }

  // The XML leg of the differential. Guarded: see blockers 1-4 in the header.
  const RUN_XML_LEG = false;
  if (RUN_XML_LEG) {
    for (const file of (await readdir(defaultDir)).filter((f) =>
      f.endsWith(".dmn"),
    )) {
      const xml = spawnSync(
        dmnmd,
        ["-f", "xml", "-t", "l4", join(defaultDir, file)],
        {
          encoding: "utf8",
        },
      );
      console.log(`       dmnmd -f xml -t l4 ${file}: exit ${xml.status}`);
    }
  } else {
    console.log(
      "SKIP  XML leg of the differential: blocked on dmnmd (4 blockers, see header)",
    );
  }
}

process.exit(failed === 0 ? 0 : 1);

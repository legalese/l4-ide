#!/usr/bin/env node
// Discovery calls instead of transcribed lists.
//
// Two facts the stage table depends on are discoverable at runtime, and both
// were transcribed by hand somewhere in this repo before now:
//
//   1. the module's regulative rule names — `l4 export bpmn FILE` with no
//      --rule exits 1 and ENUMERATES them in the error message;
//   2. the formats `l4 export` offers — listed under "Formats:" by
//      `l4 export --help`, since each format became its own subcommand
//      (CLI-SURFACE-SPEC C1, 2026-09-24; before that they were `--to` values);
//   3. the accepted values of --flavor / --fail-on / render --format — each
//      rejects a deliberately-bad value with the accepted set in the message.
//      Most older subcommands still answer `--help` with `Invalid option`,
//      so this is the only route that reaches every one of them.
//
// So the stage table asserts SET EQUALITY against these calls rather than
// hardcoding strings, and a rename fails loudly naming the exact strings. The
// one exception is the export formats, which are checked as a SUBSET: the pin
// names the formats the phases run, and a format added for some other reader
// is not a change to anything the stage table depends on.
//
// This is deliberately NARROWER than hashing `l4 --help` wholesale. A pin over
// the whole help text fires on any unrelated reflow, and a tripwire that cries
// wolf gets deleted. These four enumerations are the only CLI surface the
// stage table actually reads.
//
// Usage:
//   node etc/go/lib/discover.mjs rules FILE           # regulative rule names, one per line
//   node etc/go/lib/discover.mjs enums FILE           # JSON of the four enumerations
//   node etc/go/lib/discover.mjs check FILE PINS.json # set-equality against a pin file
// Exit: 0 ok · 1 a set moved (the message names what) · 2 usage · 4 a probe
//       did not produce a parseable answer at all (CLI shape changed)

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";

const L4 = process.env.L4 || "l4";

function run(args) {
  const r = spawnSync(L4, args, { encoding: "utf8" });
  return { status: r.status, out: (r.stdout || "") + (r.stderr || "") };
}

/** `l4 export bpmn FILE` with no --rule enumerates the regulative rules. */
export function discoverRules(file) {
  const { out } = run(["export", "bpmn", file]);
  const m = out.match(/NAME is one of:\s*(.+)/s);
  if (!m) {
    // The single-rule case is legitimate and produces no enumeration: the
    // export simply succeeds. Distinguish it from a shape change.
    if (/^\s*<\?xml/.test(out))
      return { rules: null, single: true, raw: out.slice(0, 200) };
    // ZERO regulative rules is ALSO legitimate, and is not a CLI shape change.
    // A body of law can be entirely CONSTITUTIVE: the Intestate Succession Act
    // decides who takes what and obliges nobody to do anything, so the
    // sg-succession corpus states no MUST/MAY/SHANT at all and this call
    // answers "No regulative rules found in module". Reporting that as BROKEN
    // made a purely constitutive subject unable to pass p0-preflight — which
    // is how this case was found.
    if (/No regulative rules found in module/i.test(out))
      return { rules: [], single: false, none: true, raw: out.slice(0, 200) };
    return { rules: null, single: false, raw: out.slice(0, 400) };
  }
  const rules = [...m[1].matchAll(/`([^`]+)`/g)].map((x) => x[1]);
  return { rules, single: false, raw: m[1].trim() };
}

const ENUM_PROBES = {
  export_formats: {
    args: () => ["export", "--help"],
    // The names listed under `Formats:`, two-space indented, up to the first
    // blank line. A description that wraps continues on a deeper indent and
    // does not start with a name, so it cannot be mistaken for one.
    parse: (text) => {
      const block = text.split(/^Formats:\s*$/m)[1];
      if (!block) return null;
      const names = [];
      for (const line of block.split("\n").slice(1)) {
        if (!line.trim()) break;
        const m = line.match(/^ {2}([a-z0-9][a-z0-9-]*)(?:\s|$)/);
        if (m) names.push(m[1]);
      }
      return names.length ? names : null;
    },
  },
  export_flavor: {
    args: (f) => ["export", "dmn", f, "--flavor", "__probe__"],
    re: /expected ([a-z0-9|.\-]+)\)/,
  },
  export_fail_on: {
    args: (f) => ["export", "dmn", f, "--fail-on", "__probe__"],
    re: /expected ([a-z0-9|.\-]+)\)/,
  },
  render_format: {
    args: (f) => ["render", f, "--format", "__probe__"],
    re: /expected ([a-z0-9|.\-]+)\)/,
  },
};

export function discoverEnums(file) {
  const out = {};
  for (const [name, p] of Object.entries(ENUM_PROBES)) {
    const { out: text } = run(p.args(file));
    if (p.parse) {
      out[name] = p.parse(text);
      continue;
    }
    const m = text.match(p.re);
    out[name] = m ? m[1].split("|") : null;
  }
  return out;
}

// Checked as pinned ⊆ offered rather than set equality; see the header.
const SUBSET_ENUMS = new Set(["export_formats"]);

function setEq(a, b) {
  if (!a || !b) return false;
  const A = [...a].sort().join("\0");
  const B = [...b].sort().join("\0");
  return A === B;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [, , cmd, file, pinsPath] = process.argv;
  if (!cmd || !file) {
    process.stderr.write(
      "usage: discover.mjs rules|enums|check FILE [PINS.json]\n",
    );
    process.exit(2);
  }
  if (cmd === "rules") {
    const r = discoverRules(file);
    if (!r.rules) {
      process.stderr.write(
        `discover.mjs: BROKEN — 'l4 export bpmn ${file}' did not enumerate rule names.\nThe CLI's discovery shape changed; re-verify the stage table. Saw:\n${r.raw}\n`,
      );
      process.exit(4);
    }
    process.stdout.write(r.rules.join("\n") + "\n");
    process.exit(0);
  }
  if (cmd === "enums") {
    const e = discoverEnums(file);
    process.stdout.write(JSON.stringify(e, null, 2) + "\n");
    const missing = Object.entries(e).filter(([, v]) => !v);
    if (missing.length) {
      process.stderr.write(
        `discover.mjs: BROKEN — no accepted-value set recovered for: ${missing.map((m) => m[0]).join(", ")}\n`,
      );
      process.exit(4);
    }
    process.exit(0);
  }
  if (cmd === "check") {
    if (!pinsPath || !existsSync(pinsPath)) {
      process.stderr.write(
        "discover.mjs check: PINS.json is required and must exist\n",
      );
      process.exit(2);
    }
    const pins = JSON.parse(readFileSync(pinsPath, "utf8"));
    const enums = discoverEnums(file);
    const rules = discoverRules(file);
    const problems = [];
    for (const [k, want] of Object.entries(pins.enums || {})) {
      if (!enums[k]) {
        problems.push(
          `${k}: no accepted-value set recovered at all — the CLI's error shape changed`,
        );
        continue;
      }
      if (SUBSET_ENUMS.has(k)) {
        const gone = want.filter((w) => !enums[k].includes(w));
        if (gone.length)
          problems.push(
            `${k}: pinned {${want.join(", ")}} but the CLI no longer offers {${gone.join(", ")}} (it offers {${enums[k].join(", ")}})`,
          );
        continue;
      }
      if (!setEq(enums[k], want))
        problems.push(
          `${k}: pinned {${want.join(", ")}} but the CLI now accepts {${enums[k].join(", ")}}`,
        );
    }
    if (pins.regulative_rules) {
      // `rules.rules` is [] for a purely constitutive module and null only for
      // a genuine shape change, so the test is on null and not on emptiness --
      // an empty pin and an empty module agree, and setEq below says so.
      if (rules.rules === null)
        problems.push(
          "regulative rules: the BPMN discovery call did not enumerate anything",
        );
      else if (!setEq(rules.rules, pins.regulative_rules))
        problems.push(
          `regulative rules: pinned {${pins.regulative_rules.join(", ")}} but the module now has {${rules.rules.join(", ")}}`,
        );
    }
    if (problems.length) {
      process.stderr.write(
        "discover.mjs: the CLI surface the stage table depends on has moved —\n",
      );
      for (const p of problems) process.stderr.write(`  - ${p}\n`);
      process.stderr.write(
        "Re-verify etc/go/phases/*.sh against the new surface, then update etc/go/PINS.json.\n",
      );
      process.exit(4);
    }
    process.stdout.write(
      `discover.mjs: CLI surface matches PINS.json (${Object.keys(pins.enums || {}).length} enumerations, ${(pins.regulative_rules || []).length} regulative rules)\n`,
    );
    process.exit(0);
  }
  process.stderr.write(`discover.mjs: unknown command '${cmd}'\n`);
  process.exit(2);
}

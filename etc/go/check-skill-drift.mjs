#!/usr/bin/env node
// Drift guard between the skill and the driver.
//
// A skill that documents a command the driver does not dispatch is worse than
// no skill: the reader believes it. And a driver command no skill mentions is a
// capability nobody will find. So the two command sets are compared, in both
// directions, by a script rather than by anybody's memory.
//
// It also enforces the one-file discipline the design asks for: every command
// line in the skill lives in SKILL.md. The `references/` files explain and do
// not instruct, which is what stops them accreting a second, staler copy of the
// usage.
//
// Usage: node etc/go/check-skill-drift.mjs
// Exit:  0 no drift · 1 drift (the message names it) · 2 a file is missing

import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, "../..");
const SKILL_DIR = resolve(REPO, ".claude/skills/running-the-l4-pipeline");
const SKILL = resolve(SKILL_DIR, "SKILL.md");
const GO = resolve(HERE, "go.sh");

for (const f of [SKILL, GO]) {
  if (!existsSync(f)) {
    process.stderr.write(`check-skill-drift: missing ${f}\n`);
    process.exit(2);
  }
}

let problems = [];

// --- 1. the command sets must agree, in both directions ----------------------
const goSrc = readFileSync(GO, "utf8");
const dispatch = goSrc.match(/^case "\$CMD" in$([\s\S]*?)^esac$/m);
if (!dispatch) {
  process.stderr.write(
    "check-skill-drift: could not find go.sh's dispatch table; its shape changed\n",
  );
  process.exit(2);
}
const driverCommands = new Set(
  [...dispatch[1].matchAll(/^\s{2}([a-z|\s-]+)\)/gm)]
    .flatMap((m) => m[1].split("|").map((s) => s.trim()))
    .filter((s) => s && !s.startsWith("-") && s !== "*"),
);

const skillSrc = readFileSync(SKILL, "utf8");
const skillCommands = new Set(
  [...skillSrc.matchAll(/etc\/go\/go\.sh\s+([a-z-]+)/g)].map((m) => m[1]),
);

for (const c of skillCommands) {
  if (!driverCommands.has(c))
    problems.push(
      `SKILL.md documents 'go.sh ${c}', which go.sh does not dispatch`,
    );
}
for (const c of driverCommands) {
  if (c === "help") continue; // reachable, but not worth a paragraph
  if (!skillCommands.has(c))
    problems.push(`go.sh dispatches '${c}', which SKILL.md never mentions`);
}

// --- 2. every flag the skill shows must exist in the driver ------------------
for (const m of skillSrc.matchAll(/etc\/go\/go\.sh[^\n`]*?(--[a-z][a-z-]+)/g)) {
  const flag = m[1];
  if (!goSrc.includes(`${flag})`))
    problems.push(
      `SKILL.md shows '${flag}', which go.sh's argument parser does not accept`,
    );
}

// --- 3. one-file discipline: commands live in SKILL.md, not in references/ ---
const refDir = resolve(SKILL_DIR, "references");
if (existsSync(refDir)) {
  for (const f of readdirSync(refDir).filter((f) => f.endsWith(".md"))) {
    const text = readFileSync(resolve(refDir, f), "utf8");
    // A fenced block in a reference is allowed only if it contains no command
    // that would run something. Explaining a shape is fine; instructing is not.
    for (const block of text.match(/```[\s\S]*?```/g) ?? []) {
      if (
        /(\betc\/go\/go\.sh\b|\bcabal\b|\bnpm run\b|\bnpx\b|node etc\/go\/)/.test(
          block,
        )
      ) {
        problems.push(
          `references/${f} contains a runnable command in a fenced block; command lines belong in SKILL.md so there is only one copy to keep true`,
        );
      }
    }
  }
}

// --- 3b. quoted driver declarations must be verbatim-current ------------------
// The 2026-08-09 g2 wiring left seven stale stage-membership sentences in the
// skill, and none of the checks above could see them: they compare the command
// table, not prose. Prose stays uncheckable — but a QUOTED declaration is not
// prose. The skill now states stage membership by quoting the driver's own
// arrays (`G2_STAGES=(...)` etc.), and this check holds each quote to byte
// equality with go.sh's current declaration. When the driver's list changes,
// this goes red and the fixer updates the quote — which is the sentence.
// A skill file that quotes none of them asserts nothing and checks nothing.
{
  const arrays = ["UNIMPLEMENTED_STAGES", "G1_STAGES", "G2_STAGES"];
  const declared = {};
  for (const name of arrays) {
    const m = goSrc.match(new RegExp(`^${name}=\\(([^)]*)\\)`, "m"));
    if (m) declared[name] = m[1].trim();
  }
  const skillFiles = [SKILL];
  if (existsSync(refDir))
    for (const f of readdirSync(refDir).filter((f) => f.endsWith(".md")))
      skillFiles.push(resolve(refDir, f));
  for (const file of skillFiles) {
    const text = readFileSync(file, "utf8");
    for (const name of arrays) {
      for (const m of text.matchAll(new RegExp(`${name}=\\(([^)]*)\\)`, "g"))) {
        const quoted = m[1].trim();
        if (!(name in declared)) {
          problems.push(
            `${file.replace(REPO + "/", "")} quotes ${name}=(...), which go.sh no longer declares`,
          );
        } else if (quoted !== declared[name]) {
          problems.push(
            `${file.replace(REPO + "/", "")} quotes ${name}=(${quoted}); go.sh declares ${name}=(${declared[name]})`,
          );
        }
      }
    }
  }
}

// --- 4. frontmatter shape ----------------------------------------------------
const fm = skillSrc.match(/^---\n([\s\S]*?)\n---\n/);
if (!fm)
  problems.push(
    "SKILL.md has no YAML frontmatter between --- fences at line 1",
  );
else {
  const keys = [...fm[1].matchAll(/^([a-z-]+):/gm)].map((m) => m[1]);
  if (keys.join(",") !== "name,description")
    problems.push(
      `SKILL.md frontmatter keys are [${keys.join(", ")}]; the house contract is exactly name, description`,
    );
  const name = fm[1].match(/^name:\s*(\S+)/m)?.[1];
  if (name !== "running-the-l4-pipeline")
    problems.push(
      `SKILL.md frontmatter name is '${name}'; it must equal the directory basename`,
    );
}

if (problems.length) {
  process.stderr.write(
    "check-skill-drift: the skill and the driver disagree —\n",
  );
  for (const p of problems) process.stderr.write(`  - ${p}\n`);
  process.stderr.write(
    "Fix the skill in the same change that revealed the drift.\n",
  );
  process.exit(1);
}

process.stdout.write(
  `check-skill-drift: SKILL.md and go.sh agree on ${driverCommands.size} command(s) [${[...driverCommands].sort().join(", ")}]; every flag shown exists; no reference file carries a runnable command; every quoted stage list matches go.sh\n`,
);
process.exit(0);

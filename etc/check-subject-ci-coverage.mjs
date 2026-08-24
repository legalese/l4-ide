#!/usr/bin/env node
// Does CI actually exercise what each subject DECLARES?
//
// The pipeline is subject-agnostic by design: everything CI needs to know about
// one body of law lives in etc/go/subjects/<id>/, and the driver reads it. The
// harness around the driver was not. A GitHub `paths:` filter is static YAML and
// a workflow step cannot resolve a sidecar, so both grew their own copy of the
// answer -- written for the only subject that existed, under that subject's
// name. That is invisible until a second subject declares the same leg and is
// exercised by nothing, which reports as silence rather than as a failure.
//
// This is the mechanical form of "a leg is declared IFF the driver runs it,
// extended to CI": a leg a subject declares must reach the job that gates it,
// and a subject's encoding must reach the filters that trigger those jobs.
//
//   node etc/check-subject-ci-coverage.mjs
//
// Exit: 0 every declaration is covered · 1 a finding, named · 2 usage/IO
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, "..");
const WF = resolve(REPO, ".github/workflows/pr-checks.yml");

const problems = [];
const notes = [];

let subjects;
try {
  subjects = JSON.parse(
    execFileSync("node", [resolve(REPO, "etc/go/lib/subject.mjs"), "--ci"], {
      encoding: "utf8",
    }),
  );
} catch (e) {
  process.stderr.write(
    `check-subject-ci-coverage: cannot list subjects: ${e.message}\n`,
  );
  process.exit(2);
}
if (!existsSync(WF)) {
  process.stderr.write(`check-subject-ci-coverage: ${WF} does not exist\n`);
  process.exit(2);
}
const wf = readFileSync(WF, "utf8");

// Comment lines stripped before any structural match. A YAML comment can SAY
// `subject.mjs --ci` while the step below it does something else entirely --
// and the comments in this workflow are long and quote code freely, so that is
// not a hypothetical. A check that a mention exists is not a check that the
// call exists, and it is the second one that matters.
const wfCode = wf
  .split("\n")
  .filter((l) => !/^\s*#/.test(l))
  .join("\n");

// --- 1. no subject id may be hardcoded in a job that iterates subjects -------
//
// The point of --ci is that the workflow stops naming subjects. A step that
// reads the sidecars AND names a subject has kept its second copy of the
// answer; that copy is what goes stale.
const iterating = /subject\.mjs --ci/.test(wfCode);
if (!iterating)
  problems.push(
    "pr-checks.yml never calls `subject.mjs --ci`. The subject-specific jobs are back to naming subjects inline, which is the coupling this checker exists to prevent.",
  );

// --- 2. every declared leg must reach a job that gates it -------------------
//
// Only legs with a CI job are listed. A leg absent here is not unchecked -- it
// is checked by the driver alone, which is a different and stated thing.
const LEG_JOBS = {
  "p7-dmn": {
    what: "the external DMN engines (KIE + Camunda)",
    // Each declared leg key that CI consumes, and whether CI can run without it.
    requires: ["golden", "cases", "engine_baseline"],
  },
};

for (const subj of subjects) {
  for (const [leg, spec] of Object.entries(LEG_JOBS)) {
    const declared = subj.legs?.[leg];
    if (!declared) continue;
    for (const key of spec.requires) {
      const val = declared[key];
      if (!val) {
        problems.push(
          `subject '${subj.id}' declares the ${leg} leg but no '${key}'. ${spec.what} cannot run over it, ` +
            `so declaring the leg claims a check that nothing performs. Add it to etc/go/subjects/${subj.id}/subject.json, ` +
            `or drop the leg — an omitted leg is an honest silence, a declared and unexercised one is not.`,
        );
        continue;
      }
      if (!existsSync(resolve(REPO, val)))
        problems.push(
          `subject '${subj.id}' declares ${leg}.${key} = '${val}', which is not a file.`,
        );
    }
    notes.push(`${subj.id}: ${leg} -> ${spec.what}`);
  }
}

// --- 3. the paths filter must trigger those jobs on those subjects ----------
//
// A `paths:` filter is static YAML, so it cannot be derived. It can be CHECKED:
// a subject whose encoding gates an engine job, but whose encoding directory no
// filter entry matches, edits its corpus and the engines never look at it.
const dmnFilter = (() => {
  const m = wf.match(/^\s{12}dmn:\n((?:\s{14}(?:-|#).*\n)+)/m);
  // (this one keeps the comment lines deliberately: the block is matched by its
  // shape, and its entries are extracted by a `- '...'` pattern below, so an
  // interleaved comment must not terminate the match)
  return m ? m[1] : "";
})();
if (!dmnFilter) {
  problems.push(
    "could not find the `dmn:` paths filter in pr-checks.yml; its shape changed and this check cannot speak to it.",
  );
} else {
  const globs = [...dmnFilter.matchAll(/^\s*-\s*'([^']+)'/gm)].map((m) => m[1]);
  const covers = (dir) =>
    globs.some((g) => {
      const base = g.replace(/\/?\*\*$/, "").replace(/\/$/, "");
      return dir === base || dir.startsWith(base + "/");
    });
  for (const subj of subjects) {
    if (!subj.legs?.["p7-dmn"]) continue;
    for (const dir of subj.encoding_dirs)
      if (!covers(dir))
        problems.push(
          `subject '${subj.id}' declares a p7-dmn leg, but its encoding directory '${dir}' matches no entry in the ` +
            `\`dmn:\` paths filter. Editing that corpus would not run the engines over the golden it produces. ` +
            `Add '${dir}/**' to the filter in .github/workflows/pr-checks.yml.`,
        );
  }
  // The reverse: a filter entry naming a subject that no longer declares the leg
  // is a trigger nobody asked for. A finding, not a failure — over-triggering is
  // wasteful, not wrong — so it is reported and does not set the exit code.
  const dmnDirs = new Set(
    subjects.flatMap((s) => (s.legs?.["p7-dmn"] ? s.encoding_dirs : [])),
  );
  for (const g of globs) {
    if (!g.startsWith("jl4/examples/legal/")) continue;
    const base = g.replace(/\/?\*\*$/, "");
    if (![...dmnDirs].some((d) => d === base || d.startsWith(base + "/")))
      notes.push(
        `NOTE: the dmn filter names '${g}', which belongs to no subject declaring a p7-dmn leg. Harmless (it over-triggers), but stale.`,
      );
  }
}

// --- 4. corpora the pipeline cannot see at all ------------------------------
//
// A directory under jl4/examples/legal/ holding .l4 files but no sidecar is a
// body of law the driver cannot run: `go.sh --subject <it>` refuses, no
// milestone covers it, and no report is ever written about it. That is
// sometimes correct -- `tests/` is a fixture directory, not a subject -- so
// this is a NOTE and not a finding. It is printed because the alternative is
// that nobody notices: the corpus is committed, its goldens are green in the
// Haskell suite, and it looks maintained while being outside the pipeline
// entirely.
{
  const legal = resolve(REPO, "jl4/examples/legal");
  const known = new Set(subjects.map((s) => s.id));
  let dirs = [];
  try {
    dirs = readdirSync(legal, { withFileTypes: true })
      .filter((e) => e.isDirectory())
      .map((e) => e.name)
      .sort();
  } catch {
    dirs = [];
  }
  for (const d of dirs) {
    if (known.has(d)) continue;
    const l4 = existsSync(resolve(legal, d))
      ? readdirSync(resolve(legal, d)).filter((f) => f.endsWith(".l4"))
      : [];
    if (l4.length === 0) continue;
    notes.push(
      `NOTE: jl4/examples/legal/${d}/ holds ${l4.length} .l4 file(s) and no sidecar under etc/go/subjects/, ` +
        `so no milestone can run over it. If it is a body of law, \`etc/go/go.sh new-subject ${d} …\` registers it; ` +
        `if it is fixtures, it is where it belongs.`,
    );
  }
}

for (const n of notes) process.stdout.write(`  ${n}\n`);
if (problems.length) {
  process.stderr.write(
    `check-subject-ci-coverage: ${problems.length} finding(s) —\n` +
      problems.map((p) => `  - ${p}\n`).join(""),
  );
  process.exit(1);
}
process.stdout.write(
  `check-subject-ci-coverage: ${subjects.length} subject(s); every declared leg with a CI job reaches it, and the paths filters trigger it\n`,
);

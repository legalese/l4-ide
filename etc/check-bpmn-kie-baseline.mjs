#!/usr/bin/env node
// Compare a jBPM/KIE transcript against a committed baseline.
//
// WHY THIS EXISTS. `etc/check-bpmn-kie.sh` exits 1 whenever any file has a
// finding, and jl4/examples/bpmn/expected/ legitimately has four. CI therefore
// tolerated exit 1 unconditionally — which meant a FIFTH rejected golden, or a
// regression that turned a clean golden into a rejected one, landed green. The
// count was written in a YAML comment and compared to nothing.
//
// This is the comparison. It pins, per file:
//
//   * that the file was checked AT ALL          (closes the coverage illusion:
//     a glob that silently matched fewer files now fails, rather than passing
//     with less work done)
//   * its PHASE 1 compile error and warning counts
//   * its PHASE 2 verdict token
//   * the harness's own RESULT tally
//
// It deliberately does NOT pin error TEXT. jBPM's messages move when the input
// moves — 40a87269 changed regcf-advertising's first error to
// `mismatched input 'WITHIN'` without changing anything about whether jBPM
// rejects the file — and a gate that fails on prose churn gets `--accept`ed
// reflexively until it means nothing. Counts and tokens are the part that
// carries the claim.
//
// Usage:
//   etc/check-bpmn-kie.sh FILES... | tee kie.log
//   node etc/check-bpmn-kie-baseline.mjs kie.log [--baseline PATH]
//   node etc/check-bpmn-kie-baseline.mjs --baseline PATH < kie.log
//
//   --update   rewrite the baseline from this transcript. Never run in CI; a
//              self-updating baseline asserts nothing.
//
// Exit codes:
//   0  the transcript matches the baseline exactly
//   1  it does not, and every difference is printed
//   2  usage error, or the transcript is not a jBPM transcript at all

import { readFileSync, writeFileSync } from "node:fs";
import { basename } from "node:path";

const DEFAULT_BASELINE = new URL("./bpmn-kie-baseline.txt", import.meta.url)
  .pathname;

// ---------------------------------------------------------------- parsing

// Every token KieBpmnCheck.java can print as a PHASE 2 outcome, plus the two
// ways a file can reach no PHASE 2 at all. Kept as a closed set on purpose: an
// unrecognised verdict is a harness change we want to hear about, not something
// to pass through into a baseline as free text.
const VERDICTS = new Set([
  "COMPLETED",
  "ABORTED",
  "DEADLOCK",
  "THREW",
  "NOT-EXECUTED", // compiled, but jBPM registered no process to run
  "REJECTED", // PHASE 1 errors, so PHASE 2 never happened
  "NOT-CHECKED", // no <bpmn:process> element at all
  "UNEXPECTED", // `state=N — unexpected`
  // The file never reached PHASE 1 at all — malformed XML, an unreadable
  // file, anything that throws out of the per-file body. It counts toward the
  // harness's own tally, so it is a verdict about the FILE and belongs here.
  // Found by breaking a golden's XML on purpose: without this the block parsed
  // to verdict=null and the comparator exited 2 blaming KieBpmnCheck.java for
  // an outcome it had actually had all along. Still red, but misdiagnosed.
  "HARNESS-ERROR",
]);

export function parseTranscript(text) {
  const lines = text.split(/\r?\n/);
  const files = [];
  let cur = null;
  let result = null;

  const flush = () => {
    if (cur) files.push(cur);
    cur = null;
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    const file = /^FILE {2}(.+)$/.exec(line);
    if (file) {
      flush();
      cur = {
        name: file[1].trim(),
        errors: null,
        warnings: null,
        verdict: null,
        duplication: false,
      };
      continue;
    }
    if (!cur) continue;

    if (/^\s+HARNESS ERROR\b/.test(line)) {
      cur.verdict = "HARNESS-ERROR";
      cur.errors = 0;
      cur.warnings = 0;
      continue;
    }

    if (/^\[PHASE 0 adapt\] NOT CHECKED\b/.test(line)) {
      cur.verdict = "NOT-CHECKED";
      cur.errors = 0;
      cur.warnings = 0;
      continue;
    }

    const compile = /^\[PHASE 1 compile\] errors=(\d+) warnings=(\d+)/.exec(
      line,
    );
    if (compile) {
      cur.errors = Number(compile[1]);
      cur.warnings = Number(compile[2]);
      // A file with compile errors is never executed. Record that here rather
      // than inferring it later, so a transcript that somehow shows both is a
      // parse conflict we notice instead of silently resolving.
      if (cur.errors > 0) cur.verdict = "REJECTED";
      continue;
    }

    const exec = /^\[PHASE 2 execute\] (.+)$/.exec(line);
    if (exec) {
      const rest = exec[1];
      let v = null;
      if (rest.startsWith("NOT EXECUTED")) v = "NOT-EXECUTED";
      else if (rest.startsWith("DEADLOCK")) v = "DEADLOCK";
      else if (rest.startsWith("ABORTED")) v = "ABORTED";
      else if (rest.startsWith("COMPLETED")) v = "COMPLETED";
      else if (rest.startsWith("THREW")) v = "THREW";
      else if (rest.startsWith("state=")) v = "UNEXPECTED";
      if (v) cur.verdict = v;
      continue;
    }

    if (/^\s+DUPLICATION\b/.test(line)) {
      cur.duplication = true;
      continue;
    }
  }
  flush();

  for (const line of lines) {
    const m = /^RESULT: (?:(\d+) file\(s\) with findings\.|no findings\.)/.exec(
      line,
    );
    if (m) result = m[1] === undefined ? 0 : Number(m[1]);
  }

  return { files, result };
}

// ---------------------------------------------------------------- baseline

export function formatBaseline({ files, result }) {
  const w = Math.max(0, ...files.map((f) => f.name.length));
  const rows = files.map(
    (f) =>
      `${f.name.padEnd(w)}  errors=${f.errors} warnings=${f.warnings} verdict=${f.verdict}` +
      (f.duplication ? " duplication=yes" : ""),
  );
  return (
    [
      "# jBPM/KIE baseline for jl4/examples/bpmn/expected/",
      "#",
      "# Measured, not intended. Regenerate with:",
      "#",
      "#   etc/check-bpmn-kie.sh jl4/examples/bpmn/expected/*.bpmn > /tmp/kie.log",
      "#   node etc/check-bpmn-kie-baseline.mjs /tmp/kie.log --update",
      "#",
      "# A change here is a claim that the exporter's standing with an independent",
      "# engine has moved. Say in the commit message WHICH WAY and why, and never",
      "# regenerate merely to make a red build green.",
      "#",
      "# verdict=REJECTED means jBPM refused to compile the file, so it was never",
      "# executed; the errors= count is the size of that refusal. It is NOT a",
      "# liveness defect. See jl4/examples/bpmn/unsound/README.md for which axes",
      "# are flavor differences and which are real gaps.",
      "",
      ...rows,
      "",
      `RESULT ${result}`,
      "",
    ].join("\n") + ""
  );
}

export function parseBaseline(text) {
  const files = [];
  let result = null;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const r = /^RESULT (\d+)$/.exec(line);
    if (r) {
      result = Number(r[1]);
      continue;
    }
    const m =
      /^(\S+)\s+errors=(\d+) warnings=(\d+) verdict=(\S+)(?: duplication=yes)?$/.exec(
        line,
      );
    if (!m) throw new Error(`baseline: cannot parse line: ${raw}`);
    if (!VERDICTS.has(m[4]))
      throw new Error(`baseline: unknown verdict ${m[4]} on line: ${raw}`);
    files.push({
      name: m[1],
      errors: Number(m[2]),
      warnings: Number(m[3]),
      verdict: m[4],
      duplication: / duplication=yes$/.test(line),
    });
  }
  return { files, result };
}

// ---------------------------------------------------------------- compare

export function compare(baseline, actual) {
  const problems = [];
  const bMap = new Map(baseline.files.map((f) => [f.name, f]));
  const aMap = new Map(actual.files.map((f) => [f.name, f]));

  // The coverage half. A file in the baseline that the transcript never
  // mentions means the run checked less than it claims to — a narrowed glob, a
  // renamed golden, a harness that bailed after three files.
  for (const name of bMap.keys()) {
    if (!aMap.has(name))
      problems.push(
        `NOT CHECKED  ${name} — in the baseline but absent from this run. ` +
          `The check covered less than the baseline says it does.`,
      );
  }
  for (const name of aMap.keys()) {
    if (!bMap.has(name))
      problems.push(
        `UNBASELINED  ${name} — checked but not in the baseline. ` +
          `Add it with --update, and say in the commit message what it is.`,
      );
  }

  // The regression half.
  for (const [name, a] of aMap) {
    const b = bMap.get(name);
    if (!b) continue;
    const d = [];
    if (a.errors !== b.errors)
      d.push(`compile errors ${b.errors} -> ${a.errors}`);
    if (a.warnings !== b.warnings)
      d.push(`compile warnings ${b.warnings} -> ${a.warnings}`);
    if (a.verdict !== b.verdict) d.push(`verdict ${b.verdict} -> ${a.verdict}`);
    if (a.duplication !== b.duplication)
      d.push(`duplication ${b.duplication} -> ${a.duplication}`);
    if (d.length) problems.push(`CHANGED      ${name} — ${d.join("; ")}`);
  }

  if (actual.result !== baseline.result)
    problems.push(
      `RESULT       harness tally ${baseline.result} -> ${actual.result} file(s) with findings`,
    );

  return problems;
}

// ---------------------------------------------------------------- cli

function readStdin() {
  try {
    return readFileSync(0, "utf8");
  } catch {
    return "";
  }
}

function main(argv) {
  let baselinePath = DEFAULT_BASELINE;
  let update = false;
  const positional = [];
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--baseline") baselinePath = argv[++i];
    else if (argv[i] === "--update") update = true;
    else if (argv[i].startsWith("-")) {
      console.error(`unknown flag: ${argv[i]}`);
      return 2;
    } else positional.push(argv[i]);
  }
  if (positional.length > 1) {
    console.error(
      "usage: check-bpmn-kie-baseline.mjs [TRANSCRIPT] [--baseline PATH] [--update]",
    );
    return 2;
  }

  const text = positional.length
    ? readFileSync(positional[0], "utf8")
    : readStdin();

  // A transcript with no RESULT: line is not a verdict. check-bpmn-kie.sh
  // already treats that as BROKEN (exit 4); catching it here too means piping
  // the wrong file in cannot read as "nothing changed".
  const actual = parseTranscript(text);
  if (actual.result === null) {
    console.error(
      "not a jBPM transcript: no `RESULT:` line. Nothing was compared.",
    );
    return 2;
  }
  if (actual.files.length === 0) {
    console.error(
      "not a jBPM transcript: no `FILE` blocks. Nothing was compared.",
    );
    return 2;
  }
  for (const f of actual.files) {
    if (f.verdict === null || !VERDICTS.has(f.verdict)) {
      console.error(
        `unrecognised verdict for ${f.name}: ${f.verdict}. ` +
          `KieBpmnCheck.java has probably grown an outcome this comparator does not know.`,
      );
      return 2;
    }
  }

  if (update) {
    writeFileSync(baselinePath, formatBaseline(actual));
    console.log(
      `wrote ${basename(baselinePath)}: ${actual.files.length} file(s), RESULT ${actual.result}`,
    );
    return 0;
  }

  const baseline = parseBaseline(readFileSync(baselinePath, "utf8"));
  const problems = compare(baseline, actual);

  if (problems.length === 0) {
    console.log(
      `jBPM baseline OK — ${actual.files.length} file(s) checked, ` +
        `RESULT ${actual.result} with findings, all as baselined.`,
    );
    return 0;
  }

  console.error("");
  console.error(
    "jBPM/KIE standing has changed against the committed baseline:",
  );
  console.error("");
  for (const p of problems) console.error(`  ${p}`);
  console.error("");
  console.error(`  baseline: ${baselinePath}`);
  console.error("");
  console.error(
    "  If this is intended, regenerate with --update and say in the commit",
  );
  console.error(
    "  message which way the exporter's standing moved and why. If it is not,",
  );
  console.error("  it is a regression and the diff above names the file.");
  console.error("");
  return 1;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  process.exit(main(process.argv.slice(2)));
}

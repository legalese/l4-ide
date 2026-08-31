#!/usr/bin/env node
/**
 * bench.mjs — the scoring harness for the L4-vs-Prolog replication of
 * Kant et al. 2025 (arXiv:2502.17638).
 *
 * Design constraints, each traceable to FOUNDATION.md §5:
 *
 *   R1  Per-trial, per-item answers are emitted, never only aggregates.
 *       The original reports "0.78, consistently" and no reader can
 *       recover WHICH two items moved.
 *   R2  Dual scoring: the paper's key verbatim, AND a defensibility-graded
 *       key that separates the 7 mechanical items from the 2 interpretive
 *       ones. Both are always reported.
 *   R5  Both arms EXECUTE. A trial whose encoding does not load, or does
 *       not expose the 9 queries, scores as failure — it is never
 *       hand-read into a better result. The original hand-read Prolog that
 *       would not run (its footnote 3); that charity is what we are
 *       removing, so non-conformance is recorded as data.
 *   R7  Exit codes are NOT trusted. A failed L4 #ASSERT exits 0. Answers
 *       come from parsing `l4 run --json` results[], and a short or
 *       non-boolean result array is an error, not a silent zero.
 */

import { execFileSync, spawnSync } from "node:child_process";
import { readFileSync, writeFileSync, existsSync, mkdtempSync } from "node:fs";
import { join, dirname, basename, resolve } from "node:path";
import { tmpdir } from "node:os";

// --keys <path> swaps the answer key (the restored arm scores against
// keys-restored.json). Parsed inline because KEYS is needed before arg() exists.
const keysIdx = process.argv.indexOf("--keys");
const KEYS_PATH =
  keysIdx > -1
    ? resolve(process.argv[keysIdx + 1])
    : new URL("./keys.json", import.meta.url);
const KEYS = JSON.parse(readFileSync(KEYS_PATH, "utf8"));
const KEYS_NAME = keysIdx > -1 ? basename(process.argv[keysIdx + 1]) : "keys.json";
const IDS = KEYS.items.map((i) => i.id);
const N = IDS.length;

/** Every non-answer a trial can produce. These are outcomes, not crashes. */
const VIOLATION = {
  LOAD_ERROR: "load_error", // the encoding did not compile / consult
  MISSING: "missing", // a query was not defined by the trial
  THREW: "threw", // the query raised at evaluation time
  NON_BOOLEAN: "non_boolean", // it answered, but not with a yes/no
  WRONG_COUNT: "wrong_count", // the trial emitted the wrong number of answers
  ABSTAINED: "abstained", // "I do not know" — permitted, scored wrong, tracked apart
};

// Referencing a key that is not in this map yields `undefined`, which flows
// silently into the report as a null violation and files the item as a plain
// missing answer. That happened once, to ABSTAINED. Fail loudly instead.
for (const [k, v] of Object.entries(VIOLATION)) {
  if (typeof v !== "string") throw new Error(`VIOLATION.${k} is not a string`);
}
const violation = (k) => {
  if (!(k in VIOLATION)) throw new Error(`no such violation kind: ${k}`);
  return VIOLATION[k];
};

const firstDiag = (e) =>
  (
    String(e)
      .split("\n")
      .find((l) => l.trim()) || ""
  )
    .trim()
    .slice(0, 300);

const die = (m) => {
  console.error(`bench: ${m}`);
  process.exit(2);
};

/* ------------------------------------------------------------------ *
 * L4 arm                                                             *
 * ------------------------------------------------------------------ */

/**
 * A conforming L4 trial is a directory with `policy.l4` and `apply.l4`,
 * where apply.l4 emits exactly N+1 #EVALs: a baseline first, then q1..qN.
 * The baseline exists so that a trial which makes NOTHING payable is
 * distinguishable from one that correctly denies nine claims.
 */
function runL4(
  trialDir,
  { libPath, skipFirst = true, applyName = "apply.l4" },
) {
  const apply = join(trialDir, applyName);
  if (!existsSync(apply))
    return {
      violation: VIOLATION.LOAD_ERROR,
      detail: `no ${applyName}`,
      answers: null,
    };

  let out;
  try {
    out = execFileSync("l4", ["run", "--json", basename(apply)], {
      cwd: trialDir,
      env: {
        ...process.env,
        ...(libPath ? { JL4_LIBRARY_PATH: libPath } : {}),
      },
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      maxBuffer: 64 * 1024 * 1024,
    });
  } catch (e) {
    // R7: we are here because the process died, not because an answer was
    // false. Record it; do not interpret it.
    return {
      violation: VIOLATION.LOAD_ERROR,
      detail: (e.stderr || e.message || "").slice(0, 2000),
      answers: null,
    };
  }

  let doc;
  try {
    doc = JSON.parse(out);
  } catch {
    return {
      violation: VIOLATION.LOAD_ERROR,
      detail: "unparseable --json",
      answers: null,
    };
  }

  if (doc.ok !== true) {
    return {
      violation: VIOLATION.LOAD_ERROR,
      detail: `ok=${doc.ok}`,
      answers: null,
      baseline: null,
    };
  }

  const results = Array.isArray(doc.results) ? doc.results : [];

  // Which #EVAL is which question? Selection is BY LABEL, not by position.
  //
  // The apply files carry a `q1`/`Q1`/`Q1 claim` token on each #EVAL line, and
  // sensitivity probes are deliberately spelled so they cannot collide: `Q4b`
  // and `S4` both fail /\bq(\d+)\b/ because of the trailing letter and the
  // different head. Positional selection would silently mis-attribute them —
  // apply-guarded.l4 interleaves Q4b, Q5b and Q9b between the numbered items,
  // so "the first nine results" are NOT q1..q9. This is exactly the class of
  // error the original could not have caught, since it never published which
  // item moved.
  const evalLines = readFileSync(apply, "utf8")
    .split("\n")
    .filter((l) => /^\s*#EVAL\b/.test(l));
  const selection = new Map();
  const collisions = [];
  if (evalLines.length === results.length) {
    evalLines.forEach((line, i) => {
      const m = /\bq(\d+)\b/i.exec(line);
      if (!m) return;
      const id = Number(m[1]);
      if (!IDS.includes(id)) return;
      if (selection.has(id)) collisions.push(id);
      else selection.set(id, { index: i, line: line.trim().slice(0, 160) });
    });
  }

  const labelled = selection.size === N && collisions.length === 0;

  let baseline = null;
  const baselineIdx = evalLines.findIndex((l) => /\bbaseline\b/i.test(l));
  if (baselineIdx > -1) baseline = norm(results[baselineIdx]?.value);
  else if (skipFirst && !labelled) baseline = norm(results[0]?.value);

  if (!labelled) {
    // Fall back to position only when the file offers no labels at all, and
    // then only if the count is exactly right. Guessing is not allowed.
    let rest = results;
    if (skipFirst) rest = results.slice(1);
    if (rest.length !== N) {
      return {
        violation: VIOLATION.WRONG_COUNT,
        detail:
          `got ${rest.length} positional answers, want ${N}` +
          (selection.size
            ? ` (label pass found ${selection.size}/${N}` +
              (collisions.length
                ? `, duplicate labels for q${collisions.join(", q")}`
                : "") +
              ")"
            : " (no q-labels found)"),
        answers: null,
        baseline,
      };
    }
    const answers = rest.map((r, i) => mkAnswer(IDS[i], r?.value, null));
    return { violation: null, answers, baseline, selected_by: "position" };
  }

  const answers = IDS.map((id) => {
    const { index, line } = selection.get(id);
    return { ...mkAnswer(id, results[index]?.value, line), eval_index: index };
  });
  return { violation: null, answers, baseline, selected_by: "label" };
}

function mkAnswer(id, value, srcLine) {
  const b = norm(value);
  return b === null
    ? {
        id,
        answer: null,
        violation: VIOLATION.NON_BOOLEAN,
        raw: String(value).slice(0, 200),
        src: srcLine,
      }
    : { id, answer: b, src: srcLine };
}

/** L4 prints TRUE/FALSE. Anything else — a stuck expression, a Maybe — is not an answer. */
function norm(v) {
  if (typeof v !== "string") return null;
  const s = v.trim().toUpperCase();
  if (s === "TRUE") return "Yes";
  if (s === "FALSE") return "No";
  return null;
}

/* ------------------------------------------------------------------ *
 * Vanilla arm                                                        *
 * ------------------------------------------------------------------ */

/**
 * The vanilla cell involves no encoding: the model answers the nine questions
 * directly. It is shared between the two languages, so it is a control on the
 * whole encode-then-execute pipeline rather than a cell of either arm.
 *
 * "I do not know" is a permitted answer, per the paper's own prompt. It scores
 * as wrong against both keys, but it is tracked separately as `abstained`,
 * because a model that declines is telling us something different from one that
 * asserts the opposite — and an aggregate that merges them hides it.
 */
function runVanilla(trialDir) {
  const f = join(trialDir, "answers.json");
  if (!existsSync(f))
    return {
      violation: VIOLATION.LOAD_ERROR,
      detail: "no answers.json",
      answers: null,
    };
  let doc;
  try {
    doc = JSON.parse(readFileSync(f, "utf8"));
  } catch (e) {
    return {
      violation: VIOLATION.LOAD_ERROR,
      detail: `unparseable answers.json: ${e.message}`,
      answers: null,
    };
  }

  const answers = IDS.map((id) => {
    const raw = doc[String(id)] ?? doc[id];
    if (typeof raw !== "string")
      return { id, answer: null, violation: VIOLATION.MISSING };
    const t = raw.trim().toLowerCase();
    if (t === "yes") return { id, answer: "Yes" };
    if (t === "no") return { id, answer: "No" };
    if (t === "i do not know" || t === "i don't know" || t === "unknown")
      return { id, answer: null, violation: violation("ABSTAINED") };
    return {
      id,
      answer: null,
      violation: VIOLATION.NON_BOOLEAN,
      raw: raw.slice(0, 100),
    };
  });
  return {
    violation: null,
    answers,
    baseline: null,
    selected_by: "answers.json",
  };
}

/* ------------------------------------------------------------------ *
 * Prolog arm                                                         *
 * ------------------------------------------------------------------ */

/**
 * A conforming Prolog trial is a directory with `policy.pl` and
 * `queries.pl`, where queries.pl defines q1/0..qN/0. We consult both and
 * call each goal once under catch. Note what this does NOT do: it does not
 * repair the encoding, rename predicates, or reason about what the model
 * "meant". That is precisely the charity the original extended and we do not.
 */
function runProlog(trialDir, { swipl = "swipl" }) {
  const policy = join(trialDir, "policy.pl");
  const queries = join(trialDir, "queries.pl");
  for (const f of [policy, queries]) {
    if (!existsSync(f))
      return {
        violation: VIOLATION.LOAD_ERROR,
        detail: `no ${basename(f)}`,
        answers: null,
      };
  }

  const tmp = mkdtempSync(join(tmpdir(), "bench-pl-"));
  const runner = join(tmp, "runner.pl");
  const goals = IDS.map((id) => `q${id}`);

  writeFileSync(
    runner,
    `
:- set_prolog_flag(verbose, silent).
:- initialization(main, main).

probe(G, Out) :-
    (   \\+ current_predicate(G/0)
    ->  Out = missing
    ;   catch( ( call(G) -> Out = yes ; Out = no ), E,
               ( message_to_codes(E, _), Out = threw ) )
    ).
message_to_codes(_,_).

main :-
    catch(( consult('${policy.replace(/'/g, "\\'")}'),
            consult('${queries.replace(/'/g, "\\'")}') ),
          _,
          ( writeln('BENCH-LOAD-ERROR'), halt(0) )),
    writeln('BENCH-LOADED'),
    forall(member(G, [${goals.join(",")}]),
           ( probe(G, Out), format("BENCH ~w ~w~n", [G, Out]) )),
    halt(0).
`,
  );

  let out = "",
    err = "";
  try {
    const r = spawnSync(swipl, ["-q", "-f", runner], {
      encoding: "utf8",
      timeout: 60_000,
      maxBuffer: 32 * 1024 * 1024,
    });
    out = r.stdout || "";
    err = r.stderr || "";
  } catch (e) {
    return {
      violation: VIOLATION.LOAD_ERROR,
      detail: (e.message || "").slice(0, 2000),
      answers: null,
    };
  }

  if (out.includes("BENCH-LOAD-ERROR") || !out.includes("BENCH-LOADED")) {
    return {
      violation: VIOLATION.LOAD_ERROR,
      detail: "consult failed: " + firstDiag(err),
      answers: null,
    };
  }

  // SWI-Prolog's consult/1 is PERMISSIVE: a syntax error skips the offending
  // clause, prints to stderr, and loading continues. So a half-parsed encoding
  // will happily answer some queries. Kant et al.'s footnote 3 describes
  // exactly this situation and resolves it by hand-reading the code; we resolve
  // it by failing the trial. An encoding that does not load cleanly is not an
  // encoding, and scoring it would measure our charity rather than the model.
  const loadDiag = err
    .split("\n")
    .filter((l) =>
      /Syntax error|is not defined|Unknown procedure|Illegal|Operator expected|clauses not together/i.test(
        l,
      ),
    );
  if (loadDiag.length) {
    return {
      violation: VIOLATION.LOAD_ERROR,
      detail: `encoding did not load cleanly (${loadDiag.length} diagnostic(s)): ${firstDiag(err)}`,
      answers: null,
    };
  }

  const seen = new Map();
  for (const line of out.split("\n")) {
    const m = /^BENCH (q\d+) (yes|no|missing|threw)$/.exec(line.trim());
    if (m) seen.set(m[1], m[2]);
  }

  const answers = IDS.map((id) => {
    const r = seen.get(`q${id}`);
    if (r === "yes") return { id, answer: "Yes" };
    if (r === "no") return { id, answer: "No" };
    if (r === "missing")
      return { id, answer: null, violation: VIOLATION.MISSING };
    if (r === "threw") return { id, answer: null, violation: VIOLATION.THREW };
    return { id, answer: null, violation: VIOLATION.MISSING };
  });
  return { violation: null, answers, baseline: null };
}

/* ------------------------------------------------------------------ *
 * Scoring — R2: two keys, always both                                *
 * ------------------------------------------------------------------ */

function score(answers) {
  const per = KEYS.items.map((k) => {
    const a = answers?.find((x) => x.id === k.id) ?? {
      id: k.id,
      answer: null,
      violation: VIOLATION.MISSING,
    };
    return {
      id: k.id,
      gold: k.gold,
      got: a.answer,
      violation: a.violation ?? null,
      correct: a.answer !== null && a.answer === k.gold,
      class: k.class,
      disputed: !!k.disputed,
      clause: k.clause,
      src: a.src ?? null,
    };
  });

  const mech = per.filter((p) => p.class === "mechanical");
  const interp = per.filter((p) => p.class === "interpretive");
  const ans = per.filter((p) => p.got !== null);

  return {
    per_item: per,
    // Key A — the paper's key verbatim. Directly comparable to their figures.
    key_a: {
      correct: per.filter((p) => p.correct).length,
      of: N,
      accuracy: round(per.filter((p) => p.correct).length / N),
    },
    // Key B — graded. Reported BESIDE key A, never instead of it.
    key_b: {
      mechanical: {
        correct: mech.filter((p) => p.correct).length,
        of: mech.length,
        accuracy: round(mech.filter((p) => p.correct).length / mech.length),
      },
      interpretive: {
        agreed_with_annotator: interp.filter((p) => p.correct).length,
        of: interp.length,
      },
      note: "The interpretive figure is AGREEMENT WITH AN ANNOTATOR, not correctness. Item 5's gold turns on a clause Kant et al. deleted; item 4 is under-determined by its own query. Do not add these to the mechanical count.",
    },
    // Conformance is a first-class outcome (R5).
    conformance: {
      answered: ans.length,
      of: N,
      violations: per
        .filter((p) => p.violation)
        .map((p) => ({ id: p.id, violation: p.violation })),
    },
  };
}

const round = (x) => Math.round(x * 1000) / 1000;
function mean(xs) {
  return xs.reduce((a, b) => a + b, 0) / xs.length;
}
function sd(xs) {
  const m = mean(xs);
  return Math.sqrt(
    xs.reduce((a, b) => a + (b - m) ** 2, 0) / Math.max(1, xs.length - 1),
  );
}

/* ------------------------------------------------------------------ *
 * CLI                                                                *
 * ------------------------------------------------------------------ */

function arg(name, dflt) {
  const i = process.argv.indexOf(`--${name}`);
  return i > -1 ? process.argv[i + 1] : dflt;
}
const has = (name) => process.argv.includes(`--${name}`);

const cmd = process.argv[2];

if (cmd === "trial") {
  const dir = resolve(arg("dir") ?? die("--dir required"));
  const armName = arg("arm") ?? die("--arm l4|prolog|vanilla required");
  const label = arg("label", basename(dir));
  const libPath = arg("lib", process.env.JL4_LIBRARY_PATH);

  const r =
    armName === "l4"
      ? runL4(dir, {
          libPath,
          skipFirst: !has("no-baseline"),
          applyName: arg("apply", "apply.l4"),
        })
      : armName === "prolog"
        ? runProlog(dir, {})
        : armName === "vanilla"
          ? runVanilla(dir)
          : die(`unknown arm ${armName}`);

  const sc = score(r.answers);
  const rec = {
    schema: "kant-repl/trial@1",
    label,
    arm: armName,
    keys: KEYS_NAME,
    dir,
    selected_by: r.selected_by ?? null,
    baseline: r.baseline ?? null,
    trial_violation: r.violation ?? null,
    trial_violation_detail: r.detail ?? null,
    ...sc,
  };
  const out = arg("out");
  if (out) writeFileSync(out, JSON.stringify(rec, null, 2));
  console.log(render(rec));
  // Exit 0 always: a wrong answer is a measurement, not a harness failure.
  process.exit(0);
}

if (cmd === "aggregate") {
  const files = process.argv.slice(3).filter((f) => !f.startsWith("--"));
  if (!files.length) die("aggregate needs trial json files");
  const trials = files.map((f) => JSON.parse(readFileSync(f, "utf8")));
  // Trials scored under different keys do not aggregate; mixing the arms'
  // keys silently would relive exactly the stale-snapshot failure mode.
  const keysUsed = [...new Set(trials.map((t) => t.keys ?? "keys.json"))];
  if (keysUsed.length > 1)
    die(`refusing to aggregate across different keys: ${keysUsed.join(", ")}`);
  console.log(renderAggregate(trials));
  process.exit(0);
}

die(`usage:
  bench.mjs trial --arm l4|prolog|vanilla --dir <trialdir> [--label L] [--lib PATH] [--out J]
                  [--apply apply.l4] [--no-baseline] [--keys keys.json]
  bench.mjs aggregate <trial.json>...`);

/* ------------------------------------------------------------------ *
 * Rendering — R1: the per-item table is the primary output           *
 * ------------------------------------------------------------------ */

function render(rec) {
  const L = [];
  L.push(`# ${rec.label}  (${rec.arm})`);
  L.push("");
  if (rec.selected_by) L.push(`_questions located by **${rec.selected_by}**_`);
  L.push("");
  if (rec.trial_violation) {
    L.push(
      `**TRIAL VIOLATION: \`${rec.trial_violation}\`** — ${rec.trial_violation_detail ?? ""}`,
    );
    L.push("");
  }
  if (rec.baseline !== null && rec.baseline !== undefined) {
    L.push(
      `baseline (all-favourable claim payable?): **${rec.baseline}**` +
        (rec.baseline === "No"
          ? "  ← *the encoding denies even the baseline; nine denials below are not evidence of anything*"
          : ""),
    );
    L.push("");
  }
  L.push("| Q | clause | gold | got | ✓ | class |");
  L.push("|---|--------|------|-----|---|-------|");
  for (const p of rec.per_item) {
    const got = p.got ?? `_${p.violation ?? "—"}_`;
    L.push(
      `| ${p.id} | ${p.clause} | ${p.gold} | ${got} | ${p.correct ? "✓" : "✗"} | ${p.class}${p.disputed ? " ⚠" : ""} |`,
    );
  }
  L.push("");
  L.push(
    `**Key A** (paper verbatim): ${rec.key_a.correct}/${rec.key_a.of} = ${rec.key_a.accuracy}`,
  );
  L.push(
    `**Key B**: mechanical ${rec.key_b.mechanical.correct}/${rec.key_b.mechanical.of} = ${rec.key_b.mechanical.accuracy}` +
      ` · interpretive ${rec.key_b.interpretive.agreed_with_annotator}/${rec.key_b.interpretive.of} agreement (not correctness)`,
  );
  const abst = rec.per_item.filter((p) => p.violation === "abstained").length;
  if (abst)
    L.push(
      `**Abstained** ("I do not know") on ${abst} item(s) — scored wrong against both keys, ` +
        `but counted apart: a model that declines is saying something different from one that ` +
        `asserts the opposite, and an aggregate that merges them hides it.`,
    );
  L.push(
    `**Conformance**: answered ${rec.conformance.answered}/${rec.conformance.of}` +
      (rec.conformance.violations.length
        ? ` — ${rec.conformance.violations.map((v) => `q${v.id}:${v.violation}`).join(", ")}`
        : ""),
  );
  return L.join("\n");
}

function renderAggregate(trials) {
  const byArm = new Map();
  for (const t of trials) {
    if (!byArm.has(t.arm)) byArm.set(t.arm, []);
    byArm.get(t.arm).push(t);
  }
  const L = [];
  L.push("# Aggregate");
  L.push("");
  L.push(
    "## Per-item agreement matrix (R1 — the thing the original does not publish)",
  );
  L.push("");
  L.push(`| arm | n | ${IDS.map((i) => `Q${i}`).join(" | ")} |`);
  L.push(`|-----|---|${IDS.map(() => "---").join("|")}|`);
  for (const [armName, ts] of byArm) {
    const cells = IDS.map((id) => {
      const c = ts.filter(
        (t) => t.per_item.find((p) => p.id === id)?.correct,
      ).length;
      return `${c}/${ts.length}`;
    });
    L.push(`| ${armName} | ${ts.length} | ${cells.join(" | ")} |`);
  }
  L.push("");
  L.push("## Scores");
  L.push("");
  L.push(
    "| arm | n | Key A mean | sd | min | max | Key B mechanical mean | conformance |",
  );
  L.push(
    "|-----|---|-----------|----|-----|-----|----------------------|-------------|",
  );
  for (const [armName, ts] of byArm) {
    const a = ts.map((t) => t.key_a.accuracy);
    const m = ts.map((t) => t.key_b.mechanical.accuracy);
    const conf = ts.map((t) => t.conformance.answered / t.conformance.of);
    L.push(
      `| ${armName} | ${ts.length} | ${round(mean(a))} | ${round(sd(a))} | ${round(Math.min(...a))} | ${round(Math.max(...a))} | ${round(mean(m))} | ${round(mean(conf))} |`,
    );
  }
  L.push("");
  L.push(
    "> **sd, not SEM.** Kant et al. report SEM, which shrinks with n and flatters a noisy",
  );
  L.push(
    "> pipeline. Spread across trials is the quantity of interest here, so the spread is",
  );
  L.push("> what is printed, with min and max beside it.");
  return L.join("\n");
}

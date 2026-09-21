#!/usr/bin/env node
// Project the consumer app's D[] data table out of the L4 encoding.
//
// Reads scenarios.json (the hand-written fact side, one entry per row of the
// app), evaluates `the rate on` for every scenario against every card, and
// writes D.generated.js — a JavaScript array literal.
//
// Nothing here writes to the app. The generated array is pasted into the
// homelab fork by a human; see README.md.
//
// Usage:
//   L4=/path/to/l4 node gen-d.mjs [--out FILE] [--keep-workdir]
//                                 [--reference APP.html [--diff-out FILE]]
//
// The app is not vendored here and is never written to. `--reference` reads a
// copy of it from wherever the caller says it lives — normally the homelab
// checkout — and prints the classified comparison behind DIFF.md. Unset by
// default, in which case no app file is opened at all.
//
// Exits non-zero, loudly, if any evaluation fails to produce a value. A
// partially-evaluated table is worse than no table: it would look like an
// answer.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const APP_DIR = path.dirname(fileURLToPath(import.meta.url));
const CORPUS_DIR = path.dirname(APP_DIR);
const REPO_ROOT = path.resolve(APP_DIR, "..", "..", "..", "..", "..");

// The evaluation clock. Fixed so that two runs of this script over one
// scenarios.json produce byte-identical output, and so that a rule which
// reads "now" — PAssion cl.3's promotion period is the one that does — is
// answered against a stated day rather than against whenever the script ran.
const FIXED_NOW = "2026-09-22T00:00:00Z";

// ---------------------------------------------------------------------------
// The shape of the values the evaluator prints back.
//
// `l4 run --json` renders each #EVAL result with the value printer, so a
// `Rate answer` arrives as positional text: `\`Rate answer\` OF 36, 0.28,
// Verified, ...`. Parsing that by hand is only safe schema-directed, because
// the comma between two fields of a record and the comma between two elements
// of a list are the same character. These descriptors ARE the schema, and they
// must stay in the field order of the DECLAREs in miles-card-domain.l4.
// ---------------------------------------------------------------------------

const NUM = { kind: "number" };
const STR = { kind: "string" };
const BOOL = { kind: "boolean" };
const ENUM = { kind: "enum" };
const list = (of) => ({ kind: "list", of });
const record = (name, fields) => ({ kind: "record", name, fields });

const DATE = record("DATE", [
  ["day", NUM],
  ["month", NUM],
  ["year", NUM],
]);

const PROVENANCE = record("Provenance", [
  ["document", STR],
  ["clause", STR],
  ["dated", STR],
  ["document date", DATE],
  ["quote", STR],
]);

const CAP = record("Cap", [
  ["pool", STR],
  ["capped", BOOL],
  ["bonus spend per month", NUM],
  ["basis", ENUM],
  ["attribution", ENUM],
]);

const RATE_ANSWER = record("Rate answer", [
  ["points per dollar", NUM],
  ["miles per point", NUM],
  ["conversion status", ENUM],
  ["miles per dollar", NUM],
  ["miles per dollar if the merchant flags online", NUM],
  ["miles per dollar if the merchant flags card-present", NUM],
  ["depends on the merchant indicator", BOOL],
  ["earns the bonus rate", BOOL],
  ["cap", CAP],
  ["conditions", list(STR)],
  ["sources", list(PROVENANCE)],
  ["status", ENUM],
]);

// ---------------------------------------------------------------------------
// Tokenizer for the printed value text.
// ---------------------------------------------------------------------------

function tokenize(src) {
  const toks = [];
  let i = 0;
  const isSpace = (c) => c === " " || c === "\n" || c === "\t" || c === "\r";
  while (i < src.length) {
    const c = src[i];
    if (isSpace(c)) {
      i++;
      continue;
    }
    if (c === "(" || c === ")" || c === ",") {
      toks.push({ t: c, at: i });
      i++;
      continue;
    }
    if (c === '"') {
      let out = "";
      i++;
      while (i < src.length && src[i] !== '"') {
        if (src[i] === "\\") {
          i++;
          const e = src[i];
          if (e === "n") out += "\n";
          else if (e === "t") out += "\t";
          else if (e === "r") out += "\r";
          else if (e === "\\") out += "\\";
          else if (e === '"') out += '"';
          else if (e === "&") {
            /* Haskell's empty escape: emits nothing */
          } else if (e >= "0" && e <= "9") {
            let d = "";
            while (i < src.length && src[i] >= "0" && src[i] <= "9")
              d += src[i++];
            i--;
            out += String.fromCodePoint(Number(d));
          } else out += e;
          i++;
        } else {
          out += src[i];
          i++;
        }
      }
      if (src[i] !== '"')
        throw new Error(`unterminated string literal at ${i}`);
      i++;
      toks.push({ t: "str", v: out });
      continue;
    }
    if (c === "`") {
      let out = "";
      i++;
      while (i < src.length && src[i] !== "`") out += src[i++];
      if (src[i] !== "`")
        throw new Error(`unterminated backticked name at ${i}`);
      i++;
      toks.push({ t: "name", v: out });
      continue;
    }
    if (/[0-9]/.test(c) || (c === "-" && /[0-9]/.test(src[i + 1] ?? ""))) {
      let out = "";
      while (i < src.length && /[-0-9.eE+]/.test(src[i])) out += src[i++];
      const n = Number(out);
      if (!Number.isFinite(n)) throw new Error(`not a number: ${out}`);
      toks.push({ t: "num", v: n });
      continue;
    }
    // Bare word: a nullary constructor, TRUE/FALSE, EMPTY, LIST, OF, or a
    // record constructor name that needed no backticks.
    let out = "";
    while (i < src.length && !isSpace(src[i]) && !'(),"`'.includes(src[i]))
      out += src[i++];
    if (out === "")
      throw new Error(
        `stuck at offset ${i}: ${JSON.stringify(src.slice(i, i + 40))}`,
      );
    toks.push({ t: "word", v: out });
  }
  return toks;
}

// ---------------------------------------------------------------------------
// Schema-directed parser.
// ---------------------------------------------------------------------------

function parseValue(src, type) {
  const toks = tokenize(src);
  let p = 0;
  const peek = () => toks[p];
  const next = () => toks[p++];
  const fail = (msg) => {
    const near = toks
      .slice(Math.max(0, p - 3), p + 3)
      .map((t) =>
        t.t === "str" ? JSON.stringify(t.v.slice(0, 20)) : (t.v ?? t.t),
      )
      .join(" ");
    throw new Error(`${msg} (token ${p} of ${toks.length}, near: ${near})`);
  };
  const eat = (t, v) => {
    const tok = peek();
    if (!tok || tok.t !== t || (v !== undefined && tok.v !== v))
      fail(`expected ${v ?? t}`);
    return next();
  };

  function go(ty) {
    switch (ty.kind) {
      case "number": {
        const tok = next();
        if (!tok || tok.t !== "num") fail("expected a number");
        return tok.v;
      }
      case "string": {
        const tok = next();
        if (!tok || tok.t !== "str") fail("expected a string");
        return tok.v;
      }
      case "boolean": {
        const tok = next();
        if (!tok || tok.t !== "word" || (tok.v !== "TRUE" && tok.v !== "FALSE"))
          fail("expected TRUE or FALSE");
        return tok.v === "TRUE";
      }
      case "enum": {
        const tok = next();
        if (!tok || (tok.t !== "word" && tok.t !== "name"))
          fail("expected an enum constructor");
        return tok.v;
      }
      case "list": {
        const head = peek();
        if (head && head.t === "word" && head.v === "EMPTY") {
          next();
          return [];
        }
        const open = head && head.t === "(";
        if (open) next();
        eat("word", "LIST");
        const items = [];
        for (;;) {
          items.push(go(ty.of));
          if (peek() && peek().t === ",") {
            next();
            continue;
          }
          break;
        }
        if (open) eat(")");
        return items;
      }
      case "record": {
        const head = peek();
        const open = head && head.t === "(";
        if (open) next();
        const nameTok = next();
        if (!nameTok || (nameTok.t !== "word" && nameTok.t !== "name"))
          fail("expected a record constructor");
        if (nameTok.v !== ty.name)
          fail(`expected constructor ${ty.name}, got ${nameTok.v}`);
        eat("word", "OF");
        const out = {};
        ty.fields.forEach(([fname, fty], ix) => {
          if (ix > 0) eat(",");
          out[fname] = go(fty);
        });
        if (open) eat(")");
        return out;
      }
      default:
        throw new Error(`unknown type descriptor ${JSON.stringify(ty)}`);
    }
  }

  const v = go(type);
  if (p !== toks.length) fail("trailing tokens after the value");
  return v;
}

// ---------------------------------------------------------------------------
// Emitting the probe module.
// ---------------------------------------------------------------------------

const l4str = (s) =>
  '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
const l4name = (s) => "`" + String(s) + "`";
const ymd = ([y, m, d]) => `YMD ${y} ${m} ${d}`;

function probeModule(spec) {
  const L = [];
  L.push("IMPORT prelude");
  L.push("IMPORT daydate");
  L.push("IMPORT `miles-card-domain`");
  L.push("IMPORT `miles-card`");
  L.push("");
  L.push("§ `Generated probe — do not edit, do not commit`");
  L.push("");
  L.push(
    "-- Written by app/gen-d.mjs into a throwaway directory. Every fixture",
  );
  L.push("-- below comes from app/scenarios.json.");
  L.push("");

  const ch = spec.cardholder;
  L.push("GIVETH A Cardholder");
  L.push("`the app household` MEANS Cardholder WITH");
  L.push(
    "    `Solitaire preferred rewards categories` IS " +
      (ch["Solitaire preferred rewards categories"].length
        ? "LIST " +
          ch["Solitaire preferred rewards categories"].map(l4name).join(", ")
        : "EMPTY"),
  );
  L.push(
    "    `yuu account linked to the card` IS " +
      (ch["yuu account linked to the card"] ? "TRUE" : "FALSE"),
  );
  L.push(
    "    `HSBC Everyday Global Account deposits ADB this month` IS " +
      ch["HSBC Everyday Global Account deposits ADB this month"],
  );
  L.push(
    "    `PAssion membership registered and card linked in yuu` IS " +
      (ch["PAssion membership registered and card linked in yuu"]
        ? "TRUE"
        : "FALSE"),
  );
  L.push("");

  const mp = spec["month position"];
  L.push("GIVETH A `Month position`");
  L.push("`the app month` MEANS `Month position` WITH");
  for (const [k, v] of Object.entries(mp)) L.push(`    ${l4name(k)} IS ${v}`);
  L.push("");

  const live = spec.scenarios.filter((s) => !s.reference);
  for (const s of live) {
    const t = s.transaction;
    L.push(`-- row ${s.index}: ${s.n.replace(/\n/g, " ")}`);
    L.push("GIVETH A Transaction");
    L.push(`${l4name("txn " + s.index)} MEANS Transaction WITH`);
    L.push(`    \`merchant name\` IS ${l4str(t["merchant name"])}`);
    L.push(`    \`merchant\` IS ${l4name(t.merchant)}`);
    L.push(`    \`merchant category code\` IS ${t["merchant category code"]}`);
    L.push(
      `    \`transaction description\` IS ${l4str(t["transaction description"])}`,
    );
    L.push(
      "    `description patterns` IS " +
        (t["description patterns"].length
          ? "LIST " + t["description patterns"].map(l4name).join(", ")
          : "EMPTY"),
    );
    L.push(`    \`charge kind\` IS ${l4name(t["charge kind"])}`);
    L.push(`    \`amount\` IS ${t.amount}`);
    L.push(`    \`currency\` IS ${l4str(t.currency)}`);
    L.push(
      `    \`posted in a foreign currency\` IS ${t["posted in a foreign currency"] ? "TRUE" : "FALSE"}`,
    );
    L.push(`    \`transaction date\` IS ${ymd(t["transaction date"])}`);
    L.push(`    \`posting date\` IS ${ymd(t["posting date"])}`);
    L.push(`    \`payment channel\` IS ${l4name(t["payment channel"])}`);
    L.push(`    \`credential\` IS ${l4name(t.credential)}`);
    L.push(`    \`merchant indicator\` IS ${l4name(t["merchant indicator"])}`);
    L.push(
      `    \`made in Singapore\` IS ${t["made in Singapore"] ? "TRUE" : "FALSE"}`,
    );
    L.push("");
  }

  const plan = [];
  for (const s of live) {
    for (const card of spec.cards) {
      plan.push({ index: s.index, card });
      L.push(
        `#EVAL \`the rate on\` ${l4name(card)} \`the app household\` \`the app month\` ${l4name("txn " + s.index)}`,
      );
    }
  }
  L.push("");
  return { text: L.join("\n"), plan };
}

// ---------------------------------------------------------------------------
// Running it.
// ---------------------------------------------------------------------------

function resolveBinary() {
  const fromEnv = process.env.L4;
  if (fromEnv) {
    if (!fs.existsSync(fromEnv)) {
      console.error(`gen-d: $L4 is set to ${fromEnv}, which does not exist.`);
      process.exit(2);
    }
    return fromEnv;
  }
  try {
    const which = execFileSync("sh", ["-c", "command -v l4"], {
      encoding: "utf8",
    }).trim();
    if (which) return which;
  } catch {
    /* fall through */
  }
  console.error(
    "gen-d: no l4 binary. Set $L4 to the one built from this worktree.\n" +
      "  A binary older than the corpus it reads reports new syntax as broken source,\n" +
      "  so do not reach for whatever is on PATH without checking which build it is.",
  );
  process.exit(2);
}

function evaluate(spec, opts) {
  const l4 = resolveBinary();
  const work = fs.mkdtempSync(path.join(os.tmpdir(), "l4-miles-card-gen-"));
  try {
    // The probe has to sit beside the corpus modules for importer-relative
    // resolution to find them, and a stray .l4 under jl4/examples/legal/ would
    // be swept into the golden globs. So: a throwaway directory of symlinks.
    for (const f of fs.readdirSync(CORPUS_DIR)) {
      if (f.endsWith(".l4"))
        fs.symlinkSync(path.join(CORPUS_DIR, f), path.join(work, f));
    }
    const { text, plan } = probeModule(spec);
    const probe = path.join(work, "gen-probe.l4");
    fs.writeFileSync(probe, text);

    const env = {
      ...process.env,
      JL4_LIBRARY_PATH:
        process.env.JL4_LIBRARY_PATH ||
        path.join(REPO_ROOT, "jl4-core", "libraries"),
    };
    let raw;
    try {
      raw = execFileSync(
        l4,
        ["run", "gen-probe.l4", "--json", "--fixed-now", FIXED_NOW],
        {
          cwd: work,
          env,
          encoding: "utf8",
          maxBuffer: 1 << 28,
          stdio: ["ignore", "pipe", "pipe"],
        },
      );
    } catch (e) {
      console.error(`gen-d: ${l4} exited ${e.status ?? "?"}.`);
      console.error(String(e.stderr || "").slice(0, 4000));
      console.error(String(e.stdout || "").slice(0, 4000));
      process.exit(1);
    }

    let json;
    try {
      json = JSON.parse(raw);
    } catch {
      console.error(
        "gen-d: the evaluator did not return JSON. First 2000 characters:",
      );
      console.error(raw.slice(0, 2000));
      process.exit(1);
    }

    const errs = (json.diagnostics || []).filter((d) =>
      String(d).includes("DiagnosticSeverity_Error"),
    );
    if (!json.ok || errs.length) {
      console.error(
        `gen-d: the probe module did not type-check (${errs.length} error diagnostics).`,
      );
      for (const d of errs.slice(0, 5)) console.error(String(d).slice(0, 1500));
      process.exit(1);
    }
    if (!Array.isArray(json.results) || json.results.length !== plan.length) {
      console.error(
        `gen-d: expected ${plan.length} results, got ${json.results?.length}.`,
      );
      process.exit(1);
    }

    const answers = [];
    const failures = [];
    json.results.forEach((r, ix) => {
      const { index, card } = plan[ix];
      if (r.kind !== "value" || typeof r.value !== "string") {
        failures.push(
          `row ${index} / ${card}: evaluation returned ${r.kind}: ${JSON.stringify(r).slice(0, 400)}`,
        );
        return;
      }
      try {
        answers.push({ index, card, answer: parseValue(r.value, RATE_ANSWER) });
      } catch (e) {
        failures.push(
          `row ${index} / ${card}: could not parse the printed value — ${e.message}`,
        );
      }
    });
    if (failures.length) {
      console.error(
        `gen-d: ${failures.length} of ${plan.length} evaluations did not yield a usable answer.`,
      );
      for (const f of failures.slice(0, 20)) console.error("  " + f);
      process.exit(1);
    }
    if (opts.keepWorkdir) console.error(`gen-d: probe kept at ${probe}`);
    return { answers, l4, evaluated: plan.length };
  } finally {
    if (!opts.keepWorkdir) fs.rmSync(work, { recursive: true, force: true });
  }
}

// ---------------------------------------------------------------------------
// Rendering the answers into the app's vocabulary.
// ---------------------------------------------------------------------------

const num = (n) => {
  const r = Math.round(n * 100) / 100;
  return String(r);
};

const money = (n) => {
  const r = Math.round(n * 100) / 100;
  const whole = Number.isInteger(r);
  return (
    "S$" +
    (whole
      ? r.toLocaleString("en-US")
      : r.toLocaleString("en-US", { minimumFractionDigits: 2 }))
  );
};

const BASIS_WORD = {
  "Calendar month": "calendar month",
  "Statement month": "statement month",
  "Unconfirmed basis": "reset basis unconfirmed",
};

// Status, in the app's own vocabulary. Verified earns no pill: the app shows a
// caveat only where there is something to caveat.
const STATUS_PILL = {
  Verified: "",
  Unconfirmed: "UNCONFIRMED",
  "Source expired": "EXPIRED",
  "Disputed by source": "DISPUTED",
};

function renderRate(a) {
  if (a["depends on the merchant indicator"]) {
    return `${num(a["miles per dollar if the merchant flags online"])} mpd if the merchant flags online, else ${num(
      a["miles per dollar if the merchant flags card-present"],
    )}`;
  }
  return `${num(a["miles per dollar"])} mpd`;
}

function renderCap(a) {
  const c = a.cap;
  if (!c.capped) return "uncapped";
  const basis = BASIS_WORD[c.basis] ?? c.basis;
  return `${money(c["bonus spend per month"])}/mo · ${basis}`;
}

function citations(a) {
  const seen = new Set();
  const out = [];
  for (const p of a.sources) {
    const cite = `[${p.document} cl.${p.clause}]`;
    if (seen.has(cite)) continue;
    seen.add(cite);
    out.push(cite);
  }
  return out;
}

// A card's answer is zero when there is no branch on which it earns anything.
// A conditional answer whose lower branch is zero is NOT zero: "4 mpd if the
// merchant flags online, else 0.4" is exactly the uncertainty the projection
// exists to carry.
function isZero(a) {
  return a["depends on the merchant indicator"]
    ? a["miles per dollar if the merchant flags online"] === 0 &&
        a["miles per dollar if the merchant flags card-present"] === 0
    : a["miles per dollar"] === 0;
}

// Statuses that survive a zero answer. A card earning nothing is usually not
// worth a slot — but WHY it earns nothing can be the most useful thing on the
// row, and dropping it deletes the reason along with the rate.
//
// `Source expired` is the case that forced this. POSB PAssion answers 0 on
// every scenario because its promotion period ended on 30 September 2025, and
// the earlier rule dropped it from all 42 rows — which removed the one EXPIRED
// pill the table would ever have carried, and with it the fact that a card the
// app still recommends has stopped paying. Spec §7 asks the projection to carry
// confidence and not only conclusions; a silently absent card carries neither.
//
// `Verified` and `Unconfirmed` zeroes stay dropped: those are ordinary
// "this card is not for this purchase" answers, and there are hundreds of them.
//
// `Disputed by source` is NOT in this set, deliberately. The argument above
// would carry it word for word, but no module returns that status yet
// (miles-card-disputed.l4 is empty until the acceptance run fills it), so
// adding it now would be a rule written for no case. Whoever fills that file
// should decide then, and the answer is probably yes.
const ZERO_STATUS_KEPT = new Set(["Source expired"]);

function keepDespiteZero(a) {
  return ZERO_STATUS_KEPT.has(a.status);
}

function buildD(spec, answers) {
  const byRow = new Map();
  for (const { index, card, answer } of answers) {
    if (!byRow.has(index)) byRow.set(index, []);
    byRow.get(index).push({ card, answer });
  }
  const cardOrder = new Map(spec.cards.map((c, i) => [c, i]));

  const D = [];
  for (const s of spec.scenarios) {
    if (s.reference) {
      D.push({ n: s.n, k: s.k, mcc: s.mcc, reference: true });
      continue;
    }
    const all = byRow.get(s.index) ?? [];
    const keep = all.filter(
      (x) => !isZero(x.answer) || keepDespiteZero(x.answer),
    );
    const chosen = keep.length ? keep : all;
    chosen.sort((x, y) => {
      const d = y.answer["miles per dollar"] - x.answer["miles per dollar"];
      return d !== 0 ? d : cardOrder.get(x.card) - cardOrder.get(y.card);
    });
    const row = {
      n: s.n,
      k: s.k,
      mcc: s.mcc,
      s: chosen.map(({ card, answer }) => {
        const e = {
          card,
          mpd: answer["miles per dollar"],
          rate: renderRate(answer),
          cap: renderCap(answer),
        };
        if (answer.cap.pool) e.pool = answer.cap.pool;
        e.conditions = answer.conditions;
        e.cites = citations(answer);
        const pill = STATUS_PILL[answer.status];
        if (pill === undefined)
          throw new Error(`unknown status ${answer.status} on row ${s.index}`);
        if (pill) e.status = pill;
        return e;
      }),
    };
    // A flag about the row, not about the drop rule: every card answers 0.
    if (all.every((x) => isZero(x.answer))) row.allZero = true;
    D.push(row);
  }
  return D;
}

// ---------------------------------------------------------------------------
// The comparison behind DIFF.md (`--reference <path>`).
//
// The app is Alexis's and is not vendored here, so this reads it from wherever
// the caller says it lives — normally the homelab checkout. Off by default:
// with no `--reference`, nothing below runs and no app file is touched.
// ---------------------------------------------------------------------------

// The app labels a card the way a reader would; the encoding names the
// programme. `§` marks something the app carries that is not a card in the
// corpus at all, so the comparison can count it rather than silently skip it.
function cardsBehindLabel(label) {
  if (/^Solitaire/.test(label)) return ["UOB Lady's Solitaire"];
  if (label === "HSBC Revolution") return ["HSBC Revolution"];
  if (label === "PRVI Miles") return ["UOB PRVI Miles"];
  if (label === "DBS yuu") return ["DBS yuu Visa", "DBS yuu American Express"];
  if (/PAssion/.test(label)) return ["POSB PAssion Debit"];
  if (label === "Woman's World / Citi")
    return ["DBS Woman's World", "Citi Rewards"];
  if (label === "Woman's World") return ["DBS Woman's World"];
  if (label === "Citi Rewards") return ["Citi Rewards"];
  if (label === "Citi PremierMiles") return ["Citi PremierMiles"];
  if (/PremierMiles via PayAll/.test(label)) return ["§PayAll"];
  if (/SC Smart/.test(label)) return ["§SC Smart"];
  return ["§" + label];
}

// Row-index-specific calls that a rule cannot make: which side of a numeric
// mismatch is the abstaining one, and which is a scenario artifact. Each is
// argued in DIFF.md under the tag named here.
function classifyMismatch(card, rowIx, claimed, best, e) {
  // The app quotes a live rate for a card whose own promotion period has
  // ended. Keyed on the status the encoding returned, not on the card's name,
  // so a second expired programme lands here without an edit.
  if (e.status === "EXPIRED" && best === 0) return ["a", "STATUS-EXPIRED"];
  if (card === "UOB Lady's Solitaire" && claimed === 6 && best === 4)
    return ["b", "SOLITAIRE-UPLIFT"];
  if (card === "UOB Lady's Solitaire" && rowIx === 22)
    return ["a", "SOLITAIRE-MCC"];
  if (card === "UOB Lady's Solitaire" && rowIx === 44)
    return ["c", "SCENARIO-MCC"];
  if (card.startsWith("DBS yuu") && rowIx === 22)
    return ["a", "YUU-MERCHANT-LIST"];
  if (card === "DBS yuu American Express" && rowIx === 15)
    return ["a", "YUU-AMEX-CHARGEPLUS"];
  if (card === "HSBC Revolution") return ["a", "HSBC-MCC-TABLE"];
  return ["a", "UNCLASSIFIED"];
}

function readAppArray(file) {
  const html = fs.readFileSync(file, "utf8");
  const from = html.indexOf("const D=[");
  const to = html.indexOf("\n];", from);
  if (from < 0 || to < 0)
    throw new Error(`no "const D=[ … ];" array found in ${file}`);
  // eslint-disable-next-line no-eval
  return eval(html.slice(from, to + 3) + "\nD");
}

function compareToApp(D, spec, referencePath) {
  const A = readAppArray(referencePath);
  if (A.length !== D.length)
    throw new Error(
      `the app has ${A.length} rows and the generated array has ${D.length}; ` +
        `they are meant to line up one for one`,
    );
  const mpdOf = (t) => {
    const m = t.match(/~?([\d.]+)\s*mpd/);
    return m ? Number(m[1]) : null;
  };
  const lines = [];
  const byClass = {};
  const byTag = {};
  const rowsOfTag = {};
  // Set by `note` whenever a row produces something other than a class (c)
  // comparison, so the row can be annotated with the fixture choice that may
  // have caused it. Reset at the top of each row.
  let rowDisagreed = false;
  const note = (rowIx, cls, tag, card, app, enc) => {
    byClass[cls] = (byClass[cls] ?? 0) + 1;
    byTag[tag] = (byTag[tag] ?? 0) + 1;
    (rowsOfTag[tag] ??= new Set()).add(rowIx);
    // Class (c) is agreement, with one exception: SCENARIO-MCC IS the fixture
    // choice showing up as a comparison, so it is the row that most needs the
    // annotation and would otherwise be the one row to miss it.
    if (cls !== "c" || tag === "SCENARIO-MCC") rowDisagreed = true;
    lines.push(`   (${cls}) ${tag} — ${card}: app "${app}" | enc "${enc}"`);
  };

  for (let ix = 0; ix < A.length; ix++) {
    const a = A[ix];
    const g = D[ix];
    if (a.n !== g.n)
      throw new Error(`row ${ix} name mismatch: "${a.n}" vs "${g.n}"`);
    lines.push(`\n${ix}. ${a.n}${g.reference ? "  [REFERENCE ROW]" : ""}`);
    if (g.reference) continue;
    rowDisagreed = false;
    const gen = new Map(g.s.map((e) => [e.card, e]));
    const appCards = new Set();
    const seen = new Set();
    for (const [label, txt] of a.s)
      for (const card of cardsBehindLabel(label)) {
        appCards.add(card);
        if (seen.has(card + "|" + txt)) continue;
        seen.add(card + "|" + txt);
        if (card.startsWith("§")) {
          note(
            ix,
            "b",
            card === "§SC Smart" ? "SC-SMART" : "PAYALL",
            card.slice(1),
            txt,
            "the encoding has no such card",
          );
          continue;
        }
        const e = gen.get(card);
        if (!e) {
          note(
            ix,
            "a",
            "DROPPED",
            card,
            txt,
            "0 mpd — dropped by the zero rule",
          );
          continue;
        }
        const conditional = / if the merchant flags /.test(e.rate);
        const best = conditional ? Number(e.rate.match(/^([\d.]+)/)[1]) : e.mpd;
        const claimed = mpdOf(txt);
        if (claimed !== null && Math.abs(claimed - best) > 0.09) {
          const [cls, tag] = classifyMismatch(card, ix, claimed, best, e);
          note(ix, cls, tag, card, txt, e.rate);
        } else if (conditional && !/\bif\b|online/.test(txt)) {
          note(ix, "a", "INDICATOR-PARTIALITY", card, txt, e.rate);
        } else {
          note(ix, "c", "WORDING", card, txt, `${e.rate} · ${e.cap}`);
        }
      }
    for (const e of g.s)
      if (!appCards.has(e.card))
        note(
          ix,
          "c",
          // A card kept only for its status earns nothing, so the app leaving
          // it off that row is agreement, not curation. Counting the two
          // together would inflate "the app curates" by the whole kept-zero
          // block and hide that they are different facts.
          e.mpd === 0 ? "APP-OMITS-ZERO" : "APP-CURATES",
          e.card,
          "(not listed)",
          `${e.rate} · ${e.cap}${e.status ? " · " + e.status : ""}`,
        );

    // Where a row actually disagreed, print the fixture's MCC choice under it.
    // Several rows cover merchants that code differently from one another, and
    // one scenario can only pick one code, so a mismatch may be an artifact of
    // that pick rather than a finding about the rules. Whoever reads the row
    // needs that sentence at the row, not in a document elsewhere. Rows that
    // agreed throughout do not need it, which as measured keeps it off 13 of
    // the 42 live rows.
    const scen = spec.scenarios[ix];
    if (rowDisagreed && scen?.mccChoice)
      lines.push(`   ... MCC chosen for this row: ${scen.mccChoice}`);
  }

  const total = Object.values(byClass).reduce((x, y) => x + y, 0);
  lines.push("\n" + "=".repeat(70));
  lines.push(`reference: ${referencePath}`);
  lines.push(
    `rows: ${A.length} (${D.filter((r) => r.reference).length} reference)`,
  );
  lines.push(`comparisons: ${total}`);
  for (const cls of ["a", "b", "c"])
    lines.push(`  (${cls}) ${byClass[cls] ?? 0}`);
  lines.push("by tag:");
  for (const [tag, n] of Object.entries(byTag).sort((x, y) => y[1] - x[1]))
    lines.push(
      `  ${String(n).padStart(4)}  ${tag.padEnd(22)} rows ${[...rowsOfTag[tag]].join(",")}`,
    );
  return lines.join("\n") + "\n";
}

// ---------------------------------------------------------------------------

function main() {
  const argv = process.argv.slice(2);
  const opts = {
    out: path.join(APP_DIR, "D.generated.js"),
    keepWorkdir: argv.includes("--keep-workdir"),
    reference: null,
    diffOut: null,
  };
  const outIx = argv.indexOf("--out");
  if (outIx >= 0) opts.out = path.resolve(argv[outIx + 1]);
  const refIx = argv.indexOf("--reference");
  if (refIx >= 0) {
    if (!argv[refIx + 1]) {
      console.error("gen-d: --reference needs a path to the app's HTML file.");
      process.exit(2);
    }
    opts.reference = path.resolve(argv[refIx + 1]);
    if (!fs.existsSync(opts.reference)) {
      console.error(`gen-d: --reference ${opts.reference} does not exist.`);
      process.exit(2);
    }
  }
  const diffIx = argv.indexOf("--diff-out");
  if (diffIx >= 0) opts.diffOut = path.resolve(argv[diffIx + 1]);

  const spec = JSON.parse(
    fs.readFileSync(path.join(APP_DIR, "scenarios.json"), "utf8"),
  );
  const { answers, l4, evaluated } = evaluate(spec, opts);
  const D = buildD(spec, answers);

  const header = [
    "// GENERATED by jl4/examples/legal/miles-card/app/gen-d.mjs — do not edit.",
    "//",
    "// Every figure, condition, cap, citation and status below was read out of the",
    "// L4 encoding of the issuers’ own terms by evaluating `the rate on` for each",
    "// scenario in scenarios.json against each of the nine cards. Nothing here was",
    "// typed by hand except the scenario names and the fact side of the",
    "// transactions, which live in scenarios.json.",
    "//",
    `// Evaluated at a fixed clock of ${FIXED_NOW}.`,
    `// ${evaluated} evaluations, ${spec.scenarios.length} rows`,
    `// (${spec.scenarios.filter((x) => x.reference).length} of them reference rows, which carry no transaction).`,
    "//",
    "// A human pastes this array into the app, after reading DIFF.md. This",
    "// script never writes to the app.",
    "",
    "const D = ",
  ].join("\n");

  fs.writeFileSync(opts.out, header + JSON.stringify(D, null, 2) + "\n");
  const keptZero = D.filter((r) => r.s).reduce(
    (n, r) => n + r.s.filter((e) => e.mpd === 0).length,
    0,
  );
  console.error(
    `gen-d: ${evaluated} evaluations via ${l4}; wrote ${D.length} rows to ${opts.out} ` +
      `(${D.filter((r) => r.reference).length} reference, ` +
      `${D.filter((r) => r.allZero).length} all-zero, ` +
      `${keptZero} zero-rate slots kept for their status).`,
  );

  if (opts.reference) {
    // The array is already on disk, so a comparison that cannot be made is a
    // failure of the comparison alone. Say which, and do not print a stack
    // trace that reads like the generator broke.
    let report;
    try {
      report = compareToApp(D, spec, opts.reference);
    } catch (e) {
      console.error(
        `gen-d: the array was written, but it could not be compared against\n` +
          `  ${opts.reference}\n  ${e.message}`,
      );
      process.exit(1);
    }
    if (opts.diffOut) {
      fs.writeFileSync(opts.diffOut, report);
      console.error(`gen-d: comparison written to ${opts.diffOut}`);
    } else {
      process.stdout.write(report);
    }
  }
}

main();

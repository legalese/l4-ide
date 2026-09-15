#!/usr/bin/env node
// WHAT WOULD IT COST TO ENCODE THAT? — the projector.
//
//   node etc/go/lib/estimate-cost.mjs calibrate \
//        --ledger RUN/cost-ledger.json --sources SRC.json \
//        --subject ID --model MODEL [--append CALIB.json]
//
//   node etc/go/lib/estimate-cost.mjs project \
//        --sources PATH|DIR... [--calibration CALIB.json] [--models a,b,c]
//        [--json] [--accept-stale-prices]
//
// Exit: 0 estimated · 1 refused (stale prices, or no calibration) · 2 usage
//
// --- the one idea ------------------------------------------------------------
//
// A word count is not a cost. The bridge between them is a RATIO — tokens spent
// per word of source — and that ratio is a fact about this pipeline that can
// only be MEASURED, by running it and dividing. So this tool has two verbs and
// they are not symmetric: `calibrate` records what a real run actually cost over
// a real body of law, and `project` applies recorded calibrations to law that
// has not been encoded yet.
//
// EVERY PROJECTION STATES ITS n. With one observation the output says n=1, names
// the subject it came from, and prints no interval, because there is nothing to
// take an interval over. That is the difference between a projection and a
// guess, and it is the only thing standing between "we measured this" and a
// number somebody puts in a budget.
//
// --- what would make a projection wrong, in rough order of size --------------
//
//   1. n=1, or n from one jurisdiction. Statutes differ enormously in how much
//      reasoning a word costs: a definitions section is cheap per word, a
//      cross-referenced conditional entitlement is not. Until the calibration
//      set spans several bodies of law, the spread is unknown rather than small.
//   2. The model. That is why `--model` is required on calibrate and why the
//      per-model table below is derived from ONE model's observation rescaled by
//      price. Rescaling assumes every model spends the SAME TOKENS on the same
//      work, which is false — a cheaper model may need more turns, or fewer. The
//      output says so, and the fix is to calibrate each model separately, which
//      is exactly the comparison run this repo now supports.
//   3. Caching. Modelled from measured cache tokens when the ledger has them.
//   4. Prices. Stamped and refused when stale; see model-prices.json.

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { measureAll } from "./source-metrics.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const PRICES = resolve(HERE, "model-prices.json");

export function loadPrices(path = PRICES) {
  return JSON.parse(readFileSync(path, "utf8"));
}

/** Days since the price table was measured. */
export function priceAgeDays(prices, now = Date.now()) {
  return Math.floor((now - Date.parse(prices.measured)) / 86400000);
}

/**
 * Dollars for one (model, token bundle). Cache tokens are priced with the
 * table's multipliers unless the model carries an explicit rate.
 */
export function priceOf(prices, modelId, t) {
  const m = prices.models[modelId];
  if (!m) throw new Error(`no price for model '${modelId}'`);
  const perM = (n, rate) => ((n || 0) / 1e6) * rate;
  const cacheRead = m.cache_read ?? m.input * prices.cache_read_multiplier;
  const cacheWrite = m.cache_write ?? m.input * prices.cache_write_multiplier;
  const input = perM(t.input_tokens, m.input);
  const output = perM(t.output_tokens, m.output);
  const cr = perM(t.cache_read_input_tokens, cacheRead);
  const cw = perM(t.cache_creation_input_tokens, cacheWrite);
  return {
    model: modelId,
    display: m.display,
    input,
    output,
    cache_read: cr,
    cache_write: cw,
    total: input + output + cr + cw,
  };
}

/** Pull the in-window token totals out of a p9-cost ledger. */
export function tokensFromLedger(ledger) {
  const t = ledger?.totals?.in_window ?? ledger?.totals ?? null;
  if (!t) throw new Error("ledger has no totals.in_window");
  return {
    input_tokens: t.input_tokens || 0,
    output_tokens: t.output_tokens || 0,
    cache_creation_input_tokens: t.cache_creation_input_tokens || 0,
    cache_read_input_tokens: t.cache_read_input_tokens || 0,
  };
}

/** One observation: this many tokens, over this much law, on this model. */
export function calibrationFrom({ subject, encoding, model, tokens, words }) {
  if (!words)
    throw new Error(
      "source words is 0 — a ratio with a zero denominator is not a measurement",
    );
  const per = (n) => n / words;
  return {
    subject,
    encoding: encoding ?? null,
    model,
    measured: new Date().toISOString().slice(0, 10),
    source_words: words,
    tokens,
    per_source_word: {
      input_tokens: per(tokens.input_tokens),
      output_tokens: per(tokens.output_tokens),
      cache_creation_input_tokens: per(tokens.cache_creation_input_tokens),
      cache_read_input_tokens: per(tokens.cache_read_input_tokens),
    },
  };
}

/**
 * Apply a calibration set to a word count.
 *
 * The mean is over observations, unweighted: each is one body of law encoded
 * once, and weighting by size would let one big statute silently become the
 * whole ratio.
 */
export function project(calibs, words) {
  if (!calibs.length) throw new Error("no calibration observations");
  const keys = [
    "input_tokens",
    "output_tokens",
    "cache_creation_input_tokens",
    "cache_read_input_tokens",
  ];
  const tokens = {};
  const spread = {};
  for (const k of keys) {
    const xs = calibs.map((c) => c.per_source_word[k] ?? 0);
    const mean = xs.reduce((a, b) => a + b, 0) / xs.length;
    tokens[k] = mean * words;
    spread[k] =
      xs.length > 1
        ? { low: Math.min(...xs) * words, high: Math.max(...xs) * words }
        : null;
  }
  return { tokens, spread, n: calibs.length };
}

function die(msg, code = 2) {
  process.stderr.write(`estimate-cost.mjs: ${msg}\n`);
  process.exit(code);
}

function parseArgs(argv) {
  /** @type {Record<string, any>} */
  const out = { _: [], models: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith("--")) {
      out._.push(a);
      continue;
    }
    const k = a.slice(2).replace(/-/g, "_");
    if (["json", "accept_stale_prices"].includes(k)) out[k] = true;
    else out[k] = argv[++i];
  }
  return out;
}

const usd = (n) => (n < 0.995 ? `$${n.toFixed(2)}` : `$${Math.round(n)}`);

// ---------------------------------------------------------------- CLI --------
if (import.meta.url === `file://${process.argv[1]}`) {
  const [verb, ...rest] = process.argv.slice(2);
  const args = parseArgs(rest);
  const prices = loadPrices();

  if (verb === "calibrate") {
    if (!args.ledger || !args.sources || !args.subject || !args.model)
      die("calibrate needs --ledger, --sources, --subject and --model");
    const ledger = JSON.parse(readFileSync(args.ledger, "utf8"));
    const src = JSON.parse(readFileSync(args.sources, "utf8"));
    const words = src?.totals?.words;
    if (typeof words !== "number")
      die("--sources must be source-metrics.mjs --json output");
    let c;
    try {
      c = calibrationFrom({
        subject: args.subject,
        encoding: args.encoding,
        model: args.model,
        tokens: tokensFromLedger(ledger),
        words,
      });
    } catch (e) {
      die(e.message);
    }
    if (args.append) {
      const f = resolve(args.append);
      const doc = existsSync(f)
        ? JSON.parse(readFileSync(f, "utf8"))
        : { observations: [] };
      doc.observations.push(c);
      writeFileSync(f, JSON.stringify(doc, null, 2) + "\n");
      process.stderr.write(
        `calibration appended to ${args.append} (now n=${doc.observations.length})\n`,
      );
    }
    process.stdout.write(JSON.stringify(c, null, 2) + "\n");
    process.exit(0);
  }

  if (verb !== "project") {
    process.stderr.write(
      "usage: estimate-cost.mjs calibrate --ledger L --sources S --subject ID --model M [--append F]\n" +
        "       estimate-cost.mjs project --sources PATH|DIR... [--calibration F] [--models a,b,c] [--json]\n",
    );
    process.exit(2);
  }

  const age = priceAgeDays(prices);
  if (age > prices.stale_after_days && !args.accept_stale_prices)
    die(
      `the price table was measured ${age} days ago (${prices.measured}) and the staleness bound is ` +
        `${prices.stale_after_days} days.\n` +
        `  A stale price does not fail — it prints a confident wrong dollar figure.\n` +
        `  Re-read ${prices.source}, update etc/go/lib/model-prices.json and its 'measured' date,\n` +
        `  or pass --accept-stale-prices to say you know the figures are dated.`,
      1,
    );

  const paths = args._.length
    ? args._
    : args.sources
      ? [args.sources]
      : die("project needs --sources PATH or positional paths");
  const src = measureAll(paths);
  const words = src.totals.words;

  const calibPath = args.calibration ?? resolve(HERE, "cost-calibration.json");
  if (!existsSync(calibPath))
    die(
      `no calibration at ${calibPath}.\n` +
        `  A word count is not a cost: the bridge is tokens-per-source-word, and that is\n` +
        `  a fact about this pipeline that has to be MEASURED before it can be applied.\n` +
        `  Run a subject through the pipeline, then:\n` +
        `    estimate-cost.mjs calibrate --ledger <run>/cost-ledger.json --sources <src.json> \\\n` +
        `        --subject <id> --model <model> --append ${calibPath}`,
      1,
    );
  const calib = JSON.parse(readFileSync(calibPath, "utf8"));
  const obs = calib.observations ?? [];
  if (!obs.length) die(`${calibPath} holds no observations`, 1);

  const p = project(obs, words);
  const models = (
    args.models ? args.models.split(",") : Object.keys(prices.models)
  ).map((m) => m.trim());
  const estimates = models.map((m) => priceOf(prices, m, p.tokens));

  if (args.json) {
    process.stdout.write(
      JSON.stringify(
        {
          source: src.totals,
          calibration: {
            n: p.n,
            from: obs.map((o) => ({
              subject: o.subject,
              model: o.model,
              measured: o.measured,
            })),
            path: calibPath,
          },
          projected_tokens: p.tokens,
          spread: p.spread,
          prices: { measured: prices.measured, source: prices.source, age },
          estimates,
        },
        null,
        2,
      ) + "\n",
    );
    process.exit(0);
  }

  const w = src.totals;
  process.stdout.write(
    `\nSOURCE  ${w.words.toLocaleString()} words across ${w.files} file(s)` +
      (w.files_skipped
        ? `, ${w.files_skipped} binary file(s) not counted`
        : "") +
      `\n\n`,
  );
  // The headline the user reads. It is deliberately one line per model and no
  // more precision than the calibration supports.
  for (const e of estimates)
    process.stdout.write(`  ${e.display.padEnd(20)} ${usd(e.total)}\n`);
  process.stdout.write(
    `\nBASIS   n=${p.n} observation(s): ` +
      obs.map((o) => `${o.subject}/${o.model}`).join(", ") +
      `\n` +
      (p.n === 1
        ? `        n=1 — this is ONE body of law encoded ONCE. No interval is shown because\n` +
          `        there is nothing to take an interval over. Treat it as an order of\n` +
          `        magnitude, not a quote.\n`
        : `        Per-word ratios ranged ${(
            Math.min(...obs.map((o) => o.per_source_word.output_tokens)) /
            Math.max(
              ...obs.map((o) => o.per_source_word.output_tokens),
              Number.EPSILON,
            )
          ).toFixed(2)}x across observations on output tokens.\n`) +
      `        Only ${new Set(obs.map((o) => o.model)).size} model(s) were measured; the other rows are that\n` +
      `        observation RESCALED BY PRICE, which assumes every model spends the same\n` +
      `        tokens on the same work. It does not. Calibrate each model to find out.\n` +
      `PRICES  ${prices.measured} (${age} days old), ${prices.source}\n` +
      `        Cache modelled at ${prices.cache_read_multiplier}x read / ${prices.cache_write_multiplier}x write.\n` +
      `        Batch (-50%) and effort level are NOT modelled.\n\n`,
  );
}

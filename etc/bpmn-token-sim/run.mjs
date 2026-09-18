#!/usr/bin/env node
//
// run.mjs — drive bpmn-js-token-simulation over the L4 BPMN goldens, headlessly.
//
// For every fixture this plays a few scenarios and writes what the simulator
// itself reports — its live scopes, the trigger pads it offers, its history and
// its log panel — plus a screenshot of each. Nothing here interprets the result;
// the report (specs/todo/lexipedia-superset/P2A-TOKEN-SIM-BASELINE.md) does that,
// and every line it marks MEASURED traces back to a value in out/<fixture>.json.
//
//   started    toggle simulation on, put a pause point on every activity so a
//              token stops where the obligation is, fire the start event.
//   breach     fresh start; continue activities until the simulator offers a
//              boundary-event trigger, then fire that one. If an exclusive
//              gateway stands in the way, its arms are tried in document order
//              until one reaches a boundary.
//   happy[-k]  fresh start; keep firing "continue" on every waiting activity
//              until nothing waits or STEP_LIMIT is reached. One run per arm of
//              the first exclusive gateway (k = arm index; the simulator's own
//              default is arm 0, the first outgoing flow in document order).
//
// The outputs are diffable run-to-run (README, "Determinism"): every array
// that reports a *set* of element ids is sorted, the simulator's random scope
// ids are masked to `<scope-N>`, token travel completes in release order
// (src/app.js, InstantAnimation), and the next activity to continue is chosen
// in document order. `history`, `continued`, `continuedFirst` and
// `steps[].continued` are paths in fired order and are left in that order.
// run-meta.json carries provenance per fixture and merges when given a subset.
//
// Usage:  node run.mjs [--browser=chrome|chromium] [--out=DIR] [fixture.bpmn ...]
//         defaults to every file in ../../jl4/examples/bpmn/expected/*.bpmn,
//         written to ./out

import { chromium } from "playwright";
import {
  readFileSync,
  writeFileSync,
  mkdirSync,
  readdirSync,
  existsSync,
} from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";
import { dirname, join, basename, resolve } from "node:path";
import { execSync } from "node:child_process";

const here = dirname(fileURLToPath(import.meta.url));
const STEP_LIMIT = 12;
const VIEWPORT = { width: 1280, height: 860 };

const args = process.argv.slice(2);
const flag = (name, dflt) =>
  (args.find((a) => a.startsWith(`--${name}=`)) || `--${name}=${dflt}`)
    .split("=")
    .slice(1)
    .join("=");
const browserArg = flag("browser", "chrome");
const outDir = resolve(here, flag("out", "out"));
let fixtures = args.filter((a) => !a.startsWith("--"));
if (fixtures.length === 0) {
  const dir = resolve(here, "../../jl4/examples/bpmn/expected");
  fixtures = readdirSync(dir)
    .filter((f) => f.endsWith(".bpmn"))
    .sort()
    .map((f) => join(dir, f));
}

mkdirSync(outDir, { recursive: true });

const launchOpts =
  browserArg === "chrome"
    ? { channel: "chrome", headless: true }
    : { headless: true };
const browser = await chromium.launch(launchOpts);
const version = browser.version();
const page = await browser.newPage({ viewport: VIEWPORT });
const consoleErrors = [];
page.on("pageerror", (e) => consoleErrors.push(e.message));
page.on("console", (m) => {
  if (m.type() === "error") consoleErrors.push(m.text());
});

const h = {
  load: (xml) => page.evaluate((x) => window.harness.load(x), xml),
  toggle: (on) => page.evaluate((x) => window.harness.toggle(x), on),
  pause: () => page.evaluate(() => window.harness.pauseAtActivities()),
  trigger: (id) => page.evaluate((x) => window.harness.trigger(x), id),
  settle: (ms) => page.evaluate((x) => window.harness.settle(x), ms),
  state: () => page.evaluate(() => window.harness.state()),
  trace: () => page.evaluate(() => window.harness.trace()),
  reset: () => page.evaluate(() => window.harness.reset()),
  gateways: () => page.evaluate(() => window.harness.gateways()),
  setArm: (g, i) =>
    page.evaluate(([g, i]) => window.harness.setGatewayArm(g, i), [g, i]),
  shot: (name) => page.screenshot({ path: join(outDir, name) }),
};

// Sorted: these report *which* elements, not in what order, and the simulator
// hands them back in arrival order, which for concurrent tokens is timing.
const sorted = (ids) => [...ids].sort();

// bpmn-js-token-simulation mints a scope id per token with `new Ids([32, 36])`
// (lib/simulator/Simulator.js:45) — the `ids` package's `hat(32, 36)`: 32 bits
// in base 36 is 6.19 digits, so seven characters, the first `0` or `1` and the
// rest `[0-9a-z]`. The id is read from the log entry's own `data-scope-id`
// span (src/app.js `log()`), never parsed out of the text, and this shape is
// asserted so a library that changed its alphabet would fail loudly instead of
// leaking a raw id into the JSON.
const SCOPE_ID = /^[01][0-9a-z]{6}$/;

// One mask per fixture: each distinct id becomes `<scope-N>`, N counted from 1
// by first appearance across every log this fixture captures, so a log with
// two live scopes still shows two, and a scope seen in `started` keeps its
// number if it is read again later.
function scopeMask() {
  const seen = new Map();
  return (id) => {
    if (!SCOPE_ID.test(id))
      throw new Error(
        `scope id ${JSON.stringify(id)} is not hat(32, 36)-shaped; see SCOPE_ID`,
      );
    if (!seen.has(id)) seen.set(id, `<scope-${seen.size + 1}>`);
    return seen.get(id);
  };
}

function summarise(state, trace, mask) {
  const waiting = state.snapshot.scopes.filter(
    (s) =>
      s.elementType !== "bpmn:Participant" && s.elementType !== "bpmn:Process",
  );
  return {
    tokensOn: sorted(waiting.map((s) => s.element)),
    boundarySubscriptions: sorted(
      waiting.flatMap((s) =>
        s.subscriptions.filter((x) => x.boundary).map((x) => x.element),
      ),
    ),
    triggers: sorted(
      state.triggers
        .filter((t) => t.title === "Trigger Event")
        .map((t) => t.element),
    ),
    // A path in fired order (SimulationSupport.getHistory): order-meaningful,
    // left as the simulator reports it.
    history: state.history,
    endEventsReached: sorted(
      (trace || [])
        .filter((t) => t.action === "exit" && /^End_/.test(t.element || ""))
        .map((t) => t.element),
    ),
    log: state.log
      .filter((l) => l.text !== "No Entries")
      .map((l) => (l.scope ? `${l.text} ${mask(l.scope)}` : l.text)),
  };
}

const isActivity = (e) => /Task$/.test(e.type);

async function freshStart() {
  await h.reset();
  await h.settle(200);
  await h.trigger("Start_0");
  await h.settle(1500);
}

// Continue every waiting activity, one at a time, until `stopWhen(state)` or
// nothing waits. Returns the activities continued, in order.
// Each step records where the tokens were before the click, so a state that
// only exists between two clicks (a four-way split, say) is still on record.
async function runOn(activityIds, stopWhen = () => false) {
  const steps = [];
  for (let i = 0; i < STEP_LIMIT; i++) {
    const s = await h.state();
    if (stopWhen(s)) break;
    const tokensOn = sorted(
      s.snapshot.scopes
        .filter((sc) => !/^bpmn:(Participant|Process)$/.test(sc.elementType))
        .map((sc) => sc.element),
    );
    // The first waiting activity *in document order* — not in the order the
    // simulator's trigger pads happen to sit in the DOM.
    const offered = new Set(s.triggers.map((t) => t.element));
    const next = activityIds.find(
      (id) =>
        offered.has(id) && s.snapshot.scopes.some((sc) => sc.element === id),
    );
    if (!next) break;
    steps.push({ tokensOn, continued: next });
    await h.trigger(next);
    await h.settle(2500);
  }
  return steps;
}

const results = {};
const runAt = new Date().toISOString();

for (const fixture of fixtures) {
  const name = basename(fixture, ".bpmn");
  const xml = readFileSync(fixture, "utf8");
  const mask = scopeMask();
  consoleErrors.length = 0;
  // A fresh page per fixture: the simulator, its trace and its log are all
  // page-global, and re-importing over them leaks state between fixtures.
  await page.goto(pathToFileURL(join(here, "index.html")).href);
  const loaded = await h.load(xml);
  const activityIds = loaded.elements.filter(isActivity).map((e) => e.id);
  const boundaryIds = loaded.elements
    .filter((e) => e.type === "bpmn:BoundaryEvent")
    .map((e) => e.id);
  const liveBoundaryOf = (s) =>
    s.triggers.map((t) => t.element).find((id) => boundaryIds.includes(id));

  // --- started
  const toggled = await h.toggle(true);
  await page.evaluate(() => window.harness.hideOverlayUi(true));
  const paused = await h.pause();
  await h.settle(200);
  await h.trigger("Start_0");
  await h.settle(1500);
  const started = summarise(await h.state(), await h.trace(), mask);
  await h.shot(`${name}.png`);
  // Does a timer boundary ever fire on its own? Wait a further 3 s of wall
  // clock and read the same state again.
  await h.settle(3000);
  const afterWait = summarise(await h.state(), await h.trace(), mask);
  started.afterWaiting3s = {
    tokensOn: afterWait.tokensOn,
    triggers: afterWait.triggers,
    endEventsReached: afterWait.endEventsReached,
  };

  const gateways = await h.gateways();
  const arms = gateways.length ? gateways[0].arms.length : 1;

  // --- breach
  let breach = null;
  for (let arm = 0; arm < arms && !breach; arm++) {
    if (gateways.length) await h.setArm(gateways[0].id, arm);
    await freshStart();
    const continued = await runOn(activityIds, (s) => !!liveBoundaryOf(s));
    const s = await h.state();
    const fired = liveBoundaryOf(s);
    if (!fired) continue;
    await h.trigger(fired);
    await h.settle(2500);
    const after = await h.state();
    await h.shot(`${name}.breach.png`);
    breach = {
      arm: gateways.length ? gateways[0].arms[arm] : null,
      continuedFirst: continued.map((x) => x.continued),
      fired,
      ...summarise(after, await h.trace(), mask),
    };
  }

  // --- happy, once per arm
  const happy = [];
  for (let arm = 0; arm < arms; arm++) {
    if (gateways.length) await h.setArm(gateways[0].id, arm);
    await freshStart();
    const continued = await runOn(activityIds);
    const s = await h.state();
    const suffix = arms > 1 ? `-arm${arm}` : "";
    await h.shot(`${name}.happy${suffix}.png`);
    happy.push({
      arm: gateways.length ? gateways[0].arms[arm] : null,
      continued: continued.map((x) => x.continued),
      steps: continued,
      hitStepLimit: continued.length >= STEP_LIMIT,
      ...summarise(s, await h.trace(), mask),
    });
  }

  results[name] = {
    fixture: fixture.replace(/^.*\/jl4\//, "jl4/"),
    importWarnings: loaded.warnings,
    elements: loaded.elements,
    unsupportedElements: toggled.unsupported,
    pausePoints: paused,
    exclusiveGateways: gateways,
    started,
    breach,
    happy,
    pageErrors: [...consoleErrors],
  };
  writeFileSync(
    join(outDir, `${name}.json`),
    JSON.stringify(results[name], null, 2) + "\n",
  );
  console.log(
    `${name}: started tokens on ${JSON.stringify(started.tokensOn)}; breach via ${breach ? breach.fired : "(none)"}${breach && breach.continuedFirst.length ? " after " + breach.continuedFirst.join(",") : ""}; ` +
      happy
        .map(
          (hp, i) =>
            `happy${arms > 1 ? "-arm" + i : ""}: ${hp.continued.length} step(s) -> ${JSON.stringify(hp.endEventsReached)}${hp.hitStepLimit ? " (STEP_LIMIT)" : ""}`,
        )
        .join("; "),
  );
}

// --- run-meta.json: what ran, on what, and per fixture.
//
// The top-level fields describe THIS run. `perFixture` says, for every JSON
// in the directory, which run produced it — so after a subset run the entries
// for fixtures not re-run are kept from the existing file, not dropped. The
// browser and library versions live here and only here: a fixture's JSON is
// what the simulator reported, so a browser bump is a run-meta line.
const installedVersion = (pkg) =>
  JSON.parse(readFileSync(join(here, "node_modules", pkg, "package.json")))
    .version;
const git = (cmd) => execSync(`git ${cmd}`, { cwd: here }).toString().trim();
// `-dirty` when the harness's own sources differ from the commit: a run from
// an uncommitted harness is not reproducible from that commit.
const harnessDirty =
  git("status --porcelain -- run.mjs src build.mjs index.html package.json") !==
  "";
const provenance = {
  runAt,
  bpmnjs: installedVersion("bpmn-js"),
  tokenSim: installedVersion("bpmn-js-token-simulation"),
  browser: `${browserArg} ${version}`,
  node: process.version,
  harnessCommit: git("rev-parse --short HEAD") + (harnessDirty ? "-dirty" : ""),
};
// `npm ls` heads its listing with the package's absolute path; the file is
// committed as evidence, so that line is made repo-relative.
const npmLs = execSync("npm ls --depth=0", { cwd: here })
  .toString()
  .replaceAll(here, "etc/bpmn-token-sim");
const metaPath = join(outDir, "run-meta.json");
const previous = existsSync(metaPath)
  ? JSON.parse(readFileSync(metaPath, "utf8"))
  : {};
const perFixture = { ...(previous.perFixture || {}) };
for (const name of Object.keys(results)) perFixture[name] = { ...provenance };
const meta = {
  ...provenance,
  fixtures: Object.keys(results),
  npmLs: npmLs.trim().split("\n"),
  viewport: VIEWPORT,
  stepLimit: STEP_LIMIT,
  perFixture: Object.fromEntries(
    Object.keys(perFixture)
      .sort()
      .map((k) => [k, perFixture[k]]),
  ),
};
writeFileSync(metaPath, JSON.stringify(meta, null, 2) + "\n");
await browser.close();
console.log(`wrote ${Object.keys(results).length} fixture(s) to ${outDir}`);

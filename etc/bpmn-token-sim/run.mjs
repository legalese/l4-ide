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
// Usage:  node run.mjs [--browser=chrome|chromium] [fixture.bpmn ...]
//         defaults to every file in ../../jl4/examples/bpmn/expected/*.bpmn

import { chromium } from "playwright";
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";
import { dirname, join, basename, resolve } from "node:path";
import { execSync } from "node:child_process";

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, "out");
const STEP_LIMIT = 12;
const VIEWPORT = { width: 1280, height: 860 };

const args = process.argv.slice(2);
const browserArg = (
  args.find((a) => a.startsWith("--browser=")) || "--browser=chrome"
).split("=")[1];
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

function summarise(state, trace) {
  const waiting = state.snapshot.scopes.filter(
    (s) =>
      s.elementType !== "bpmn:Participant" && s.elementType !== "bpmn:Process",
  );
  return {
    tokensOn: waiting.map((s) => s.element),
    boundarySubscriptions: waiting.flatMap((s) =>
      s.subscriptions.filter((x) => x.boundary).map((x) => x.element),
    ),
    triggers: state.triggers
      .filter((t) => t.title === "Trigger Event")
      .map((t) => t.element),
    history: state.history,
    endEventsReached: (trace || [])
      .filter((t) => t.action === "exit" && /^End_/.test(t.element || ""))
      .map((t) => t.element),
    log: state.log.filter((l) => l !== "No Entries"),
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
    const tokensOn = s.snapshot.scopes
      .filter((sc) => !/^bpmn:(Participant|Process)$/.test(sc.elementType))
      .map((sc) => sc.element);
    const next = s.triggers
      .map((t) => t.element)
      .find(
        (id) =>
          activityIds.includes(id) &&
          s.snapshot.scopes.some((sc) => sc.element === id),
      );
    if (!next) break;
    steps.push({ tokensOn, continued: next });
    await h.trigger(next);
    await h.settle(2500);
  }
  return steps;
}

const results = {};

for (const fixture of fixtures) {
  const name = basename(fixture, ".bpmn");
  const xml = readFileSync(fixture, "utf8");
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
  const started = summarise(await h.state(), await h.trace());
  await h.shot(`${name}.png`);
  // Does a timer boundary ever fire on its own? Wait a further 3 s of wall
  // clock and read the same state again.
  await h.settle(3000);
  const afterWait = summarise(await h.state(), await h.trace());
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
      ...summarise(after, await h.trace()),
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
      ...summarise(s, await h.trace()),
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

const npmLs = execSync("npm ls --depth=0", { cwd: here }).toString();
const meta = {
  date: new Date().toISOString(),
  browser: `${browserArg} ${version}`,
  node: process.version,
  npmLs: npmLs.trim().split("\n"),
  viewport: VIEWPORT,
  stepLimit: STEP_LIMIT,
};
writeFileSync(
  join(outDir, "run-meta.json"),
  JSON.stringify(meta, null, 2) + "\n",
);
await browser.close();
console.log(`wrote ${Object.keys(results).length} fixture(s) to ${outDir}`);

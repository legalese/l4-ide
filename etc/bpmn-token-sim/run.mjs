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
//   started    toggle simulation on, put a pause point on every task so a
//              token stops where the obligation is, fire the start event.
//   breach     fresh start; continue tasks until the simulator offers an
//              interrupting boundary-event trigger — a deadline or a condition
//              on the act itself — then fire that one. If an exclusive
//              gateway stands in the way, its arms are tried in document order
//              until one reaches a boundary.
//   happy[-k]  fresh start; keep firing "continue" on every waiting task
//              until nothing waits or STEP_LIMIT is reached. One run per arm of
//              the first exclusive gateway (k = arm index; the simulator's own
//              default is arm 0, the first outgoing flow in document order).
//
// A FORK rule (EVERY … UPON EACH) is emitted as a multi-instance sub-process:
// the member's act, its deadline and its continuation sit inside a box that
// ends at `EndScope_<n>` (this member is done) or throws an escalation at
// `EscScope_<n>` (this member breached), which a non-interrupting boundary on
// the box relays to a top-level `EndBreach_<n>`; the box itself flows to
// `EndGroup_<n>` ("every run has ended"). The harness treats the box as flow,
// not as a task: no pause point on it (src/app.js says why, measured), the
// tasks inside are what get continued, and the escalation relay is never the
// boundary the breach scenario fires — cold, it reaches EndBreach with no
// member having acted and no deadline having passed (measured on
// tenancy-fork with the tasks paused, as shipped: history `Start_0, …,
// Scope_0, StartScope_0, …, Task_0, BoundaryEsc_0, …, EndBreach_0`, Task_0
// entered and still live, Boundary_0 still offered), which is a breach with
// no cause. What the
// simulator cannot show: bpmn-js-token-simulation 0.40.0 has no
// multi-instance support at all (`grep -ri multiinstance lib/` is empty), so
// the box runs as ONE instance — `instances` below is 1 for every fork
// fixture, and EndGroup fires the moment that one instance ends, on the
// breach path too. The n-member picture the rule describes is not one this
// tool can draw.
//
// The outputs are diffable run-to-run (README, "Determinism"): every array
// that reports a *set* of element ids is sorted, every object keyed by element
// id has its keys sorted, the simulator's random scope ids are masked to
// `<scope-N>`, token travel completes in release order (src/app.js,
// InstantAnimation), and the next task to continue is chosen in document
// order. `history`, `continued`, `continuedFirst` and `steps[].continued` are
// paths in fired order and are left in that order. run-meta.json carries
// provenance per fixture and merges when given a subset.
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
// Measured over the sixteen fixtures (2026-09-19): the longest acyclic happy
// path is five continues (offering); regcf-reporting's third arm is a cycle
// and runs into this limit by design, so raising it lengthens that output and
// nothing else. A fork fixture needs one or two — the simulator runs its
// multi-instance box as one instance (see the header), so there is no n to
// multiply by. Left at 12.
const STEP_LIMIT = 12;
const START_ID = "Start_0";
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
// An object keyed by element id, keys in sorted order for the same reason.
const keyed = (entries) =>
  Object.fromEntries([...entries].sort(([a], [b]) => (a < b ? -1 : a > b)));
const isSubProcessType = (t) =>
  /^bpmn:(SubProcess|AdHocSubProcess|Transaction)$/.test(t);
const isContainerType = (t) => /^bpmn:(Participant|Process)$/.test(t);

// bpmn-js-token-simulation mints a scope id per token with `new Ids([32, 36])`
// (lib/simulator/Simulator.js:45) — the `ids` package's `hat(32, 36)`: 32 bits
// in base 36 is 6.19 digits, so seven characters, the first `0` or `1` and the
// rest `[0-9a-z]`. The id is read from the log entry's own `data-scope-id`
// span (src/app.js `log()`), never parsed out of the text, and this shape is
// asserted so a library that changed its alphabet would fail loudly instead of
// leaking a raw id into the JSON.
//
// (The simulator would accept its own id generator — `injector.get('scopeIds',
// false)` at Simulator.js:45 — which would make this mask unnecessary. Not
// taken: Log.js:456 and Notifications.js:67 `domify` the id unescaped as
// element text, so an id spelled `<scope-N>` parses as an HTML tag; and
// `ids.next()` at :481 runs for every scope — process, participant, children —
// not only the ones that reach a log line, so the numbering would change too.
// Masking on the way out leaves the simulator's own minting untouched.)
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

// `elements` is the fixture's census from src/app.js `load()`; end events are
// found by type (`bpmn:EndEvent`) and placed by their static `subProcess`.
function summarise(state, trace, mask, elements) {
  // Every live scope but the process/participant container. A sub-process
  // scope is kept: it is a real token holder, and how many of them sit on one
  // box is the multi-instance question (`instances`).
  const waiting = state.snapshot.scopes.filter(
    (s) => !isContainerType(s.elementType),
  );
  const endEvent = new Map(
    elements
      .filter((e) => e.type === "bpmn:EndEvent")
      .map((e) => [e.id, e.subProcess]),
  );
  const ended = (trace || [])
    .filter((t) => t.action === "exit" && endEvent.has(t.element))
    .map((t) => t.element);
  const instances = new Map();
  for (const s of waiting)
    if (isSubProcessType(s.elementType))
      instances.set(s.element, (instances.get(s.element) || 0) + 1);
  return {
    tokensOn: sorted(waiting.map((s) => s.element)),
    // Live scopes per sub-process box, by the box's element id. This is the
    // simulator's instance count: 1 for every multi-instance box, because
    // bpmn-js-token-simulation has no multi-instance behaviour (header).
    instances: keyed(instances),
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
    // A *multiset*, not a set: one entry per token that exited an end event,
    // so two tokens reaching End_3 give it twice (handover, offering), and the
    // count is read by the report. Sorted, because arrival order is timing;
    // the fired order of the same exits is `history`. Any `bpmn:EndEvent`
    // counts — `End_n`, and the fork shape's `EndGroup_n`, `EndBreach_n`,
    // `EndScope_n` and the escalation-throwing `EscScope_n` — and the next two
    // fields say where each sits, so "the group ended" (EndGroup, top level)
    // reads apart from "one member's scope ended" (EndScope, inside its box).
    endEventsReached: sorted(ended),
    endEventsReachedTopLevel: sorted(ended.filter((id) => !endEvent.get(id))),
    endEventsReachedInside: keyed(
      [...new Set(ended.map((id) => endEvent.get(id)).filter(Boolean))].map(
        (box) => [box, sorted(ended.filter((id) => endEvent.get(id) === box))],
      ),
    ),
    log: state.log
      .filter((l) => l.text !== "No Entries")
      .map((l) => (l.scope ? `${l.text} ${mask(l.scope)}` : l.text)),
  };
}

async function freshStart() {
  await h.reset();
  await h.settle(200);
  await h.trigger(START_ID);
  await h.settle(1500);
}

// Continue every waiting task, one at a time, until `stopWhen(state)` or
// nothing waits. Returns the tasks continued, in order.
// Each step records where the tokens were before the click, so a state that
// only exists between two clicks (a four-way split, say) is still on record.
async function runOn(activityIds, stopWhen = () => false) {
  const steps = [];
  for (let i = 0; i < STEP_LIMIT; i++) {
    const s = await h.state();
    if (stopWhen(s)) break;
    const tokensOn = sorted(
      s.snapshot.scopes
        .filter((sc) => !isContainerType(sc.elementType))
        .map((sc) => sc.element),
    );
    // The first waiting task *in document order* — not in the order the
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
  const summarize = (state, trace) =>
    summarise(state, trace, mask, loaded.elements);
  // Every scenario is fired from the top-level start. A fork fixture also
  // carries a `StartScope_<n>` inside its box, which the simulator signals
  // itself on entering the box; the harness never touches it. Checked rather
  // than assumed, so a fixture whose start moved fails here and not as a run
  // that reports nothing.
  const start = loaded.elements.find((e) => e.id === START_ID);
  if (!start || start.type !== "bpmn:StartEvent" || start.subProcess)
    throw new Error(
      `${name}: no top-level bpmn:StartEvent with id ${START_ID}`,
    );
  // The breach scenario fires an *interrupting* boundary: a deadline or a
  // condition on the act itself (every `Boundary_n` in the corpus has
  // cancelActivity="true"). The fork shape's `BoundaryEsc_n` on the box is
  // non-interrupting and is a relay, not a cause — the simulator offers it as
  // a trigger from the moment the box is entered, and firing it cold reaches
  // EndBreach with no member having acted (header). It is exercised anyway,
  // by the escalation the member's own deadline throws.
  const boundaryIds = loaded.elements
    .filter((e) => e.type === "bpmn:BoundaryEvent" && e.cancelActivity)
    .map((e) => e.id);
  const liveBoundaryOf = (s) =>
    s.triggers.map((t) => t.element).find((id) => boundaryIds.includes(id));

  // --- started
  const toggled = await h.toggle(true);
  await page.evaluate(() => window.harness.hideOverlayUi(true));
  // The tasks to continue are exactly the elements a pause point was put on
  // (src/app.js `pauseAtActivities`), in registry order, which for tasks is
  // document order. One list, so the two cannot drift apart.
  const paused = await h.pause();
  const activityIds = paused;
  await h.settle(200);
  await h.trigger(START_ID);
  await h.settle(1500);
  const started = summarize(await h.state(), await h.trace());
  await h.shot(`${name}.png`);
  // Does a timer boundary ever fire on its own? Wait a further 3 s of wall
  // clock and read the same state again.
  await h.settle(3000);
  const afterWait = summarize(await h.state(), await h.trace());
  started.afterWaiting3s = {
    tokensOn: afterWait.tokensOn,
    instances: afterWait.instances,
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
      ...summarize(after, await h.trace()),
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
      ...summarize(s, await h.trace()),
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
// for fixtures not re-run are kept from the existing file, not dropped, and
// an entry whose JSON is gone from the directory is not kept. The
// browser and library versions live here and only here: a fixture's JSON is
// what the simulator reported, so a browser bump is a run-meta line.
const installedVersion = (pkg) =>
  JSON.parse(readFileSync(join(here, "node_modules", pkg, "package.json")))
    .version;
const git = (cmd) => execSync(`git ${cmd}`, { cwd: here }).toString().trim();
// The harness's own files. `harnessCommit` is the last commit that touched
// any of them — not `HEAD`, which moves on every docs or exporter commit in
// the repo and would make an unchanged harness look re-run — and `-dirty`
// when they differ from that commit: a run from an uncommitted harness is not
// reproducible from any commit. The lockfile is on the list because it fixes
// the transitive tree, which `npm ls --depth=0` below does not show.
const harnessFiles =
  "run.mjs src build.mjs index.html package.json package-lock.json";
const harnessDirty = git(`status --porcelain -- ${harnessFiles}`) !== "";
const provenance = {
  runAt,
  bpmnjs: installedVersion("bpmn-js"),
  tokenSim: installedVersion("bpmn-js-token-simulation"),
  browser: `${browserArg} ${version}`,
  node: process.version,
  harnessCommit:
    git(`log -1 --format=%h -- ${harnessFiles}`) +
    (harnessDirty ? "-dirty" : ""),
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
// Kept entries are only those whose JSON is still in the directory: a fixture
// renamed or deleted since the previous run drops out instead of being
// carried forward under a name nothing produces any more.
const perFixture = Object.fromEntries(
  Object.entries(previous.perFixture || {}).filter(([name]) =>
    existsSync(join(outDir, `${name}.json`)),
  ),
);
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

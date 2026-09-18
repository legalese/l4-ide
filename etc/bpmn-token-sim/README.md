# bpmn-token-sim — the P2a picture baseline

Drives [`bpmn-js-token-simulation`](https://github.com/bpmn-io/bpmn-js-token-simulation)
(MIT, bpmn-io) over the BPMN goldens the L4 exporter ships in
`jl4/examples/bpmn/expected/*.bpmn`, headlessly, and writes down what the
simulator shows for each one. The findings live in
[`specs/todo/lexipedia-superset/P2A-TOKEN-SIM-BASELINE.md`](../../specs/todo/lexipedia-superset/P2A-TOKEN-SIM-BASELINE.md);
this directory is the apparatus, and `out/` is its evidence.

It is self-contained: its own `package.json`, its own `node_modules`, nothing
added to the root or `ts-apps/` lockfiles. No Haskell build is needed — the
fixtures are committed.

## Run

```sh
cd etc/bpmn-token-sim
npm ci                      # bpmn-js 18.28.0, bpmn-js-token-simulation 0.40.0,
                            # randomcolor 0.6.2, esbuild 0.25.9, playwright 1.63.0 —
                            # direct deps pinned in package.json, the transitive tree
                            # in package-lock.json
npm run build               # bundles src/app.js + CSS + fonts into dist/
npm run run                 # every fixture; ~5 minutes, mostly animation waits
node run.mjs ../../jl4/examples/bpmn/expected/tenancy-fork.bpmn   # just one
node run.mjs --out=/tmp/tsim/run1                                 # elsewhere than out/
```

`run.mjs` launches the Google Chrome already installed on the machine
(`--browser=chrome`, Playwright's `channel: 'chrome'`), so nothing is downloaded.
Pass `--browser=chromium` to use Playwright's own build instead, after
`npx playwright install chromium`.

## What it does

`src/app.js` builds a `bpmn-js` Modeler with the token-simulation module and its
`SimulationSupport` test helper, and exposes `window.harness`. `run.mjs` opens
`index.html` from `file://`, and for each fixture plays:

| scenario    | steps                                                                                                                                                                                                                          | screenshot                       |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------- |
| `started`   | switch simulation on; put a pause point on every activity (so a token stops where the obligation is instead of running through, see below); fire the start event; wait 1.5 s; then wait a further 3 s and read the state again | `out/<fixture>.png`              |
| `breach`    | fresh start; continue activities until the simulator offers a boundary-event trigger; fire it. If an exclusive gateway is in the way, its arms are tried in document order until one reaches a boundary                        | `out/<fixture>.breach.png`       |
| `happy[-k]` | fresh start; keep firing "continue" on every waiting activity until nothing waits or 12 steps; one run per arm `k` of the first exclusive gateway (the simulator's own default is arm 0)                                       | `out/<fixture>.happy[-armk].png` |

Everything the simulator reports is written to `out/<fixture>.json`: the
element census bpmn-js imported (for a multi-instance activity, whether it
carries a `loopCardinality`, a `loopDataInputRef` or a `completionCondition`,
the last as its text), import warnings, the elements the simulator
flags unsupported, the live scopes (token positions and their subscriptions),
the trigger pads offered, the history, the end events reached and the text of
the simulator's own log panel. `out/run-meta.json` records the run's
provenance — see **Provenance** below.

**Why pause points.** In this simulator an activity does not wait by itself —
`ActivityBehavior.enter` exits immediately unless a pause point is set
(`node_modules/bpmn-js-token-simulation/lib/simulator/behaviors/ActivityBehavior.js`).
Without them a run starting at the start event runs straight to an end event and
there is never a moment at which "what is owed right now" could be read off the
picture. Pause points are the UI's own affordance (the pause icon on hover), so
setting them everywhere is the most charitable reading of the tool.

## Determinism: what is sorted, what is masked, what is not

The JSONs are diffable run-to-run: a re-run that changes nothing changes no
`out/<fixture>.json` (only `run-meta.json`'s `runAt` lines), so a diff after a
fixture moves shows only the fixtures that moved. Five things make that true,
each in the code with a comment saying so:

- **Sorted** — every array that reports _which_ element ids, not in what order,
  which the simulator hands back in arrival order (for concurrent tokens, in
  timing order): `tokensOn`, `triggers`, `boundarySubscriptions`,
  `endEventsReached` (in `started`, `started.afterWaiting3s`, `breach` and
  every `happy[k]`), and `steps[].tokensOn`. Sorted with JavaScript's default
  string sort. All but one are sets; `endEventsReached` is a **multiset** — one
  entry per token that exited an end event, so two tokens reaching `End_3`
  list it twice (`handover`, `offering`), and the report reads that count.
  The order those exits fired in is in `history`.
- **Left in fired order**, because the order is the meaning: `history` (the
  simulator's own path, `SimulationSupport.getHistory`), `continued`,
  `continuedFirst` and `steps[].continued`. Also untouched: `elements`,
  `pausePoints`, `unsupportedElements`, `exclusiveGateways[].arms` and every
  `outgoing`/`incoming`, which are already in document order.
- **Masked** — the simulator mints a random id per token scope
  (`new Ids([32, 36])`, `lib/simulator/Simulator.js:45`: `hat(32, 36)`, seven
  characters, `[01][0-9a-z]{6}`) and prints it after every log line. `log()`
  in `src/app.js` reads the id from the entry's own `data-scope-id` span rather
  than out of the text, and `run.mjs` replaces each distinct id with
  `<scope-N>`, numbered from 1 by first appearance across all the logs one
  fixture captures — so a log with two live scopes still shows two, and the
  shape is asserted (`SCOPE_ID`) so a library that changed its alphabet fails
  the run instead of leaking an id. Nothing else in the JSON carries a scope
  id: `snapshot.scopes[].id` and the trace's `scope` are read but never written.
- **Token travel completes in release order** — `history` is only stable if
  concurrent tokens arrive in the same order every run, and in the simulator
  they do not: a token's travel along a flow is a `requestAnimationFrame`
  animation (`lib/animation/Animation.js`) whose completion fires the next
  element's entry, and at the 100x speed the harness asks for both tokens out
  of a parallel split take about one frame, so which lands first depends on
  where the frame boundary falls (measured: `consultation`'s `started.history`
  ended `Task_1, Task_4` in one run and `Task_4, Task_1` in the next, with
  everything else identical). `src/app.js` overrides the simulator's
  `animation` service with `InstantAnimation`, which completes each travel on
  a zero-delay timer in the order the simulator started it — the split's
  outgoing flows in document order — and keeps the service's contract
  (pause, play, clear on scope destroy). It draws no moving token; a
  screenshot is taken at rest, so nothing in it changes. (The library's own
  `config.animation.randomize` is not the lever: `TokenAnimation` stores it as
  `this.randomize` and reads `this._randomize`, so durations were never
  random; the race is the frame, not the duration.) For the same reason
  `run.mjs` picks the next activity to continue in **document order** rather
  than in whatever order the trigger pads sit in the DOM.
- **Seeded scope colours** — for the screenshots. A token scope's colour (its
  count badge, its "Finished" tag, its log lines) comes from a palette the
  simulator draws once per page load with an unseeded `randomColor({ count: 60 })`
  (`lib/features/colored-scopes/ColoredScopes.js`), so before this every
  screenshot differed between two identical runs in exactly those pixels
  (measured: 400–2,000 pixels per image, all inside the badges). `src/app.js`
  overrides `coloredScopes` with the same code seeded (`randomcolor` is now a
  direct, pinned dependency for that one import).

**Measured on this branch, 2026-09-19** (Chrome 153.0.8010.53, Node v26.4.0,
macOS): the full fourteen twice in a row, `diff -r` of the fourteen JSONs
**empty**; `run-meta.json` differs in its fifteen `runAt` lines and nothing
else; **46 of 46 screenshots byte-identical**. Before the seeded palette, the
same test had the JSONs empty and 0 of 46 screenshots identical, every
difference inside the scope-coloured badges. **What is claimed and what is
not:** the JSONs are deterministic by construction. The screenshots were
byte-identical on one machine; they are rendered by the machine's Chrome and
its fonts, and no claim is made that another machine, Chrome or OS produces
the same bytes — a screenshot diff after a browser bump is expected and is
not a finding.

**The acceptance test is two runs, not one.** A partial fix looks identical to
a clean one on any single re-run; only a second run can show the churn is
gone. Run the full set twice into two scratch directories and diff:

```sh
node run.mjs --out=/tmp/tsim/run1
node run.mjs --out=/tmp/tsim/run2
diff -r -x '*.png' -x run-meta.json /tmp/tsim/run1 /tmp/tsim/run2   # must be empty
diff /tmp/tsim/run1/run-meta.json /tmp/tsim/run2/run-meta.json      # runAt lines only
```

Screenshots are compared separately (`cmp` per file); a difference there is
read as a rendering difference until shown otherwise, not as a finding about
the diagram.

## Provenance: `out/run-meta.json`

The top-level fields describe the latest run; `perFixture` says, for every
fixture JSON in the directory, which run produced it:

```json
{
  "runAt": "…Z",
  "bpmnjs": "18.28.0",
  "tokenSim": "0.40.0",
  "browser": "chrome 153.0.8010.53",
  "node": "v26.4.0",
  "harnessCommit": "<git rev-parse --short HEAD>",
  "fixtures": ["consultation", "…"],
  "npmLs": ["…"],
  "viewport": { "width": 1280, "height": 860 },
  "stepLimit": 12,
  "perFixture": {
    "consultation": { "runAt", "bpmnjs", "tokenSim", "browser", "node", "harnessCommit" },
    "…": {}
  }
}
```

`bpmnjs` and `tokenSim` are the installed versions (`node_modules/*/package.json`),
`harnessCommit` is `git rev-parse --short HEAD` with `-dirty` appended when
`run.mjs`, `src/`, `build.mjs`, `index.html`, `package.json` or
`package-lock.json` have uncommitted changes — a run from an uncommitted
harness is not reproducible from that commit (the lockfile counts because it
fixes the transitive tree that `npmLs` does not show). When `run.mjs` is given
a subset of fixtures it **merges** into the existing `perFixture`, keeping the
entries of the fixtures it did not re-run and dropping any whose
`<fixture>.json` is no longer in the directory; `fixtures` lists what this run
touched. The browser and library versions live
in this file and only here — no `out/<fixture>.json` carries them — so a
browser bump is a `run-meta.json` line, not a fifteen-file diff.

## What it deliberately is not

It does not judge the diagrams. `etc/check-bpmn-soundness.mjs` is the token-game
gate and `etc/check-bpmn-kie.sh` the engine second opinion; this harness asks a
different question — what a reader looking at the animation can and cannot tell
about the rule — and the answer is prose, in the report.

`node_modules/` and `dist/` are ignored by the local `.gitignore`;
`package-lock.json` is committed, so `npm ci` reproduces the transitive tree
(`diagram-js` and the rest) that `run-meta.json`'s `npm ls --depth=0` does not
record; `out/` is un-ignored there, because the root `.gitignore` ignores every
`out/` and these screenshots are the evidence the report cites. `out/` is also
listed in the root `.prettierignore` explicitly — the JSONs are generated
evidence, and `prettier --check` would otherwise reformat them when given the
path directly (the root `.gitignore`'s `out/` line hides them only from a
bare `prettier --check .`).

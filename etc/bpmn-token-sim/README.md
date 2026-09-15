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
npm install                 # bpmn-js 18.28.0, bpmn-js-token-simulation 0.40.0,
                            # esbuild 0.25.9, playwright 1.63.0 — all pinned
npm run build               # bundles src/app.js + CSS + fonts into dist/
npm run run                 # every fixture; ~5 minutes, mostly animation waits
node run.mjs ../../jl4/examples/bpmn/expected/tenancy-fork.bpmn   # just one
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
element census bpmn-js imported, import warnings, the elements the simulator
flags unsupported, the live scopes (token positions and their subscriptions),
the trigger pads offered, the history, the end events reached and the text of
the simulator's own log panel. `out/run-meta.json` records date, browser
version, Node version and `npm ls`.

**Why pause points.** In this simulator an activity does not wait by itself —
`ActivityBehavior.enter` exits immediately unless a pause point is set
(`node_modules/bpmn-js-token-simulation/lib/simulator/behaviors/ActivityBehavior.js`).
Without them a run starting at the start event runs straight to an end event and
there is never a moment at which "what is owed right now" could be read off the
picture. Pause points are the UI's own affordance (the pause icon on hover), so
setting them everywhere is the most charitable reading of the tool.

## What it deliberately is not

It does not judge the diagrams. `etc/check-bpmn-soundness.mjs` is the token-game
gate and `etc/check-bpmn-kie.sh` the engine second opinion; this harness asks a
different question — what a reader looking at the animation can and cannot tell
about the rule — and the answer is prose, in the report.

`node_modules/`, `dist/` and `package-lock.json` are ignored by the local
`.gitignore`; `out/` is un-ignored there, because the root `.gitignore` ignores
every `out/` and these screenshots are the evidence the report cites.

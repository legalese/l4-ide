# feat(regcf-wizard): the Reg CF citizen wizard — progressive disclosure, law-time (R8) and an embedded ladder

**What this adds**

A standalone SvelteKit single-page app under `ts-apps/regcf-wizard`: a five-surface hub over the
SEC Regulation Crowdfunding corpus, answering *can this company raise*, *how much may I invest*,
*may I sell yet*, and *may we stop filing*. Like its sibling it contains no law — the form is
generated at runtime from the exported function's JSON Schema, and every figure, sentence and
citation on the page is a field of a `jl4-service` response. It goes further than a form, though:
it asks **one question at a time** in the service's own ranked order and stops the moment the
verdict settles, it makes **law time** explicit (ask the fact date, disclose the derived rule date
and why, offer an override), and it **draws the ladder diagram** for the decision inline. Two nix
expressions ship with it so the app can be served at `/regcf/`, though the module defaults to off.

**Why**

Track C item **C2b** of `specs/todo/lexipedia-superset/`. Beyond the demo value, it exercises two
server-side capabilities the spec recorded as finished but which had never been driven from a
client: progressive disclosure over `POST …/query-plan`, and ruling **R8** — fact date in, rule
date derived and disclosed. Driving them from a real client is what turned up the atom-id
disagreement recorded under Evidence. No upstream issue number is named in the source commits.

## What's in it

55 files: 52 under `ts-apps/regcf-wizard`, 2 nix expressions, and one `turbo.json` line.

- An entry page that is a **hub, not a questionnaire** — the corpus serves founders and investors,
  and one linear form would ask a founder about resale restrictions.
- 22 Svelte components (9 structural, 5 answer cards, 6 leaf widgets, 2 routes), 20 TypeScript
  modules, 4 vitest files, 2 verbatim live-wire fixtures.
- **Progressive disclosure** (`lib/elicit/plan.ts`): one question at a time in the service's own
  ranked order restricted to `stillNeeded`, stopping the moment the **verdict** settles. It
  switches on `verdict`, never on `determined` — which is `null` for four of the six verdicts, and
  is exactly what `Backend/DecisionQueryPlan.hs` warns about.
- **Ruling R8** (`lib/lawtime.ts`): ask the fact date, disclose the derived rule date *and why*,
  and offer an override that pins law-time independently and says so. `lawtime.ts` knows nothing
  about which figures moved when — a client-side regime table would be a second copy of the law and
  the first copy to go stale.
- **An embedded ladder diagram** (`components/Ladder.svelte`): static on the hub, interactive
  inside the step-by-step surface, driven by the framework-free `LadderController`.
- **Validation of every record shape** (`api/validate.ts`) plus the scalar carve-out: a NUMBER
  return is not wrapped under its return-type name, a record is.
- **A content-security policy emitted as a `<meta>` tag**, with `style-src 'self'` — affordable
  only because the ladder emitter bakes no inline `style=` attributes, a property
  `ladder-embed.test.ts` pins for `sceneToSvg`. The README says plainly which half of that the test
  does *not* cover (the app renders through `LadderController`, not `sceneToSvg`).
- **`nix/regcf-wizard/{package.nix,configuration.nix}`** — everything the deploy needs and nothing
  that performs it. The module defaults to **off**, serves at `/regcf/` (the IDE already owns `/`),
  bakes `BASE_PATH` and `VITE_JL4_BASE_URL` in at build time (SvelteKit's `paths.base` and the
  app's `connect-src` are both build-time), derives the service URL from the same domain so
  `connect-src 'self'` covers it, and contributes the `regcf` corpus bundle *inside its own `mkIf`*.
  `package.nix` builds the SPA the way `nix/jl4-web` builds the IDE, over the narrower workspace
  chain the wizard needs: viz-expr → boolean-analysis → ladder-core → ladder-svg, and
  viz-expr → jl4-client-rpc.
- **`turbo.json`** gains `BASE_PATH` to its build task's `env` list — the one-line change the nix
  build needs to bake the SPA's base path. It is additive to an `env` array and conflicts with
  nothing.

*Generalisations the Reg CF schema forced, folded back into the shared renderer shape:* a `date`
widget (an L4 `DATE` arrives as `{"type":"string","format":"date"}`); `toArguments` no longer casts
to a single `{situation: FormState}` root, because the law-time export has two; and
`orderedChildKeys` falls back to `required` when `propertyOrder` is absent, which it is on a
two-root node — `Object.keys` is alphabetical and would put the investor's figures ahead of the
date they are to be judged against, inverting R8's own derivation.

## Evidence

Quoted from PR #200: "47 unit tests. check/lint/test/build green." Clean-room at tip
(`rm -rf node_modules && npm ci`, exit 0): "`npm run build`, `lint`, `check`, `test` all exit 0;
`regcf-wizard` 47/47, `svelte-check` 0 errors 0 warnings; `prettier@3.4.2 --check .` clean."

All behaviour was measured against a **loopback** `jl4-service` on `127.0.0.1`, never a deployed
host:

- Seeding, by replicating the nix module's own `ExecStartPre`: `"exportCount":6`,
  `"file":"regcf-wizard.l4"`, health `{"ready":1,"total":1,"status":"healthy"}`.
- Elicitation on `can this company raise`: `{}` → `verdict=Undetermined determined=None
  stillNeeded=[4, 6]`; `{"4":true}` → `stillNeeded=[6]`; `{"4":true,"6":true}` → `verdict=Holds
  determined=True stillNeeded=[]`; `{"4":false}` → `verdict=Fails determined=False
  stillNeeded=[]` — limb 2 never asked.
- **The join disagreement, same atom:** `GET …/ladder` gives `unique=4`,
  `atomId=64e895d0-1863-5f26-bb2b-63ef440b85d3`; `POST …/query-plan` gives `unique=4`,
  `atomId=a87d9b26-bfef-5b0b-9c22-d77d103f93a9`. Binding by the ladder's `atomId` "returns 200 and
  silently changes nothing" — a client that joined on `atomId` "would draw one diagram and answer a
  different question, with no error anywhere."
- R8 law-time, one investor (income 150000, net worth 80000, invested 0, not accredited):
  `2016-06-01 → 4000`, `2018-01-01 → 4000`, `2022-09-20 → 7500`, `2023-01-01 → 7500`,
  `2026-08-02 → 7500`; `2015-01-01` → curated refusal, "no Regulation Crowdfunding figure exists
  before commencement on 2016-05-16".
- The ladder embed in headless Chrome over the **built** app: "service calls from the hub — one,
  `GET …/can this company raise/ladder`; no failed requests"; "ladder mounts — 1, `viewBox="0 0
  1062 180"`, rendered 685×116"; "2 `rect.lad-box`, 3 `polyline.lad-wire`, both nodes
  byte-identical to the endpoint's `name.label` fields"; "CSP — exactly 1 violation,
  `style-src-attr`, from SvelteKit's own `#svelte-announcer`, no visible effect."

A note the source PR was careful about, carried forward: the ladder payload's leaves are
`"value":"UnknownV"` on the wire and stay `UnknownV` when the query plan binds them — the valuation
is the client's, the verdict beside it is still the service's.

## Independence

**This PR cannot build without `ladder-viz`, and that is measured, not assumed.**

- **`ladder-viz` — hard.** `package.json` depends on `@repo/ladder-svg` and `@repo/ladder-core`,
  and **neither package exists on `main`** — both are new in the ladder-viz theme, which is also
  where the `LadderController` that `components/Ladder.svelte` mounts lives. Running `npm ci` on
  this slice alone fails with `404 Not Found - GET .../@repo%2fladder-core`. **This PR must land
  after ladder-viz.** (This is precisely why the two wizards are separate PRs: the housing wizard
  needs nothing new and stands alone.)
- **`corpus-regcf` and `service-cli` — soft.** The five surfaces are drawn from the six exports of
  `jl4/examples/legal/regcf/regcf-wizard.l4`, owned by corpus-regcf; the `/query-plan` endpoint and
  its `verdict`/`stillNeeded` payload are owned by service-cli. Nothing here fails to *compile*
  without them, but the app has nothing to talk to — and `api/validate.ts` plus the two
  `__fixtures__/live-*.json` files encode those wire shapes verbatim, so they are the files to
  re-measure if either sibling changes shape.
- **The nix module is inert on its own, and the lines that reach it are elsewhere.** The import in
  `nix/configuration.nix` and the `regcf-wizard = pkgs.callPackage ./regcf-wizard/package.nix`
  entry in `nix/default.nix` belong to the **ci-build** theme, as does the `bundles`
  `default`→`config` move in `nix/jl4-service/configuration.nix`. That last one matters: on `main`,
  `services.jl4-service.bundles` still carries `{classic, thailand-cosmetics}` as its `default`,
  and an `attrsOf` option discards its default the moment anything defines the option — so if
  someone imported this module *and* enabled it before ci-build lands, contributing `bundles.regcf`
  would silently drop the base two. Unimported and disabled, as it arrives here, it serves nothing
  and evaluates nothing. The dependency also runs the other way: ci-build's two nix lines point at
  the files in *this* PR, so if this one is rejected those two lines must be deleted there or
  `nix` evaluation of the flake fails.
- **The root lockfile is not here.** `package.json` and `package-lock.json` are in ci-build, so the
  workspace-link records for this app land with that theme. Note the root `overrides.vite` pin
  differs between the branches (`^6.0.7` on `main`, `6.4.2` on `unstable`); PR #200's clean-room
  `rm -rf node_modules && npm ci` was measured on the `6.4.2` base, so an installer run against
  `main`'s pin has not been measured either way.

Known and pre-existing, from the source PR and not introduced here: `turbo.json`'s `test` task
depends on `^check` only, so a single combined `turbo build test …` graph can run a SvelteKit app's
tests before `svelte-kit sync` writes `.svelte-kit/tsconfig.json`. It is masked in CI, which runs
build/lint/check/test as separate steps. Left alone deliberately — fixing it changes task ordering
for every package.

## Risk if rejected

The repo loses the only client that drives progressive disclosure and law-time from the outside,
and Track C item C2b has no implementation. The atom-id disagreement above stays undiscovered by
anything automated, since no other client joins those two endpoints. Nothing breaks at the
TypeScript level — no sibling package imports this app — but **two lines in ci-build must be
deleted with it**: `nix/configuration.nix`'s `./regcf-wizard/configuration.nix` import and
`nix/default.nix`'s `regcf-wizard = pkgs.callPackage ./regcf-wizard/package.nix { }`, or `nix`
evaluation of the flake fails.

## Provenance

- **legalese/l4-ide#200** — `feat(regcf-wizard): Reg CF citizen wizard (C2b), C2c prepared not
  performed — 6 exports driven live on loopback` (branch `mengwong/wizard-deploy-ready`)
- **legalese/l4-ide#177** — `feat(ladder): Step 4 — the LadderSvg displayer` — contributes no file
  to this PR (it deliberately touched nothing under `ts-apps/`); listed because this app consumes
  the `LadderController` it introduced, which ships in the **ladder-viz** theme.

Split note: on `unstable` this shipped alongside the Housing Act wizard. They are separated here
because their dependency stories differ completely — bundling them would have made the standalone
housing app un-mergeable on its own.

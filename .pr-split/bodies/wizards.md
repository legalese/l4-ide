# feat(wizards): citizen web wizards over Housing Act possession and Reg CF, generated from L4 schemas

**What this adds**

Two standalone SvelteKit single-page apps under `ts-apps/`, each a public-facing
question-and-answer tool that a member of the public can use to get a legal answer computed by
the real L4 rules. `housing-wizard` asks about rent arrears and returns whether a court must or
may order possession under Housing Act 1988 Schedule 2; `regcf-wizard` is a five-surface hub over
the SEC Regulation Crowdfunding corpus — can this company raise, how much may I invest, may I
sell yet, may we stop filing. Neither app contains any law: the form is generated at runtime from
the exported function's JSON-Schema (`GET /deployments/{id}/functions/{fn}`) and every figure,
sentence and citation on the page is a field of a `jl4-service` response. Before this, an L4
deployment could be evaluated over HTTP but there was no user-facing surface over it at all; after
this, the same `.l4` a drafter authors auto-generates a working public tool.

**Why**

The pitch these make concrete is *the same L4 a drafter authors auto-generates a public tool*.
`housing-wizard` was built as the downstream demo for the Lawmaker product owner (the UK
legislative-drafting community, The National Archives) — a thing you can point a
non-programmer at. `regcf-wizard` is Track C item **C2b** of
`specs/todo/lexipedia-superset/`, and additionally exercises two server-side capabilities the
spec recorded as finished but never driven from a client: progressive disclosure over
`POST …/query-plan`, and ruling **R8** (fact date in, rule date derived and disclosed). No
upstream issue number is named in the source commits for either app.

**What's in it**

91 files, 7,140 insertions, 1 deletion (the one-character `turbo.json` line).

*`ts-apps/housing-wizard` — 36 files, 2,432 insertions*

- A generic, unit-tested **schema→widget renderer**: `labels.ts` / `classify.ts` /
  `build-tree.ts` / `form-logic.ts`, plus a recursive `FieldRenderer` dispatcher and controlled
  leaf widgets (enum→radios, number→currency input, boolean→Yes/No, object→fieldset). It honours
  `propertyOrder`, cleans backtick-quoted L4 labels into prose, and emits real JSON numbers and
  booleans.
- 12 Svelte components, 14 TypeScript modules, 1 vitest file, 1 captured live-schema fixture.
- `AnswerCard.svelte` derives the **MUST (mandatory) vs MAY (discretionary)** badge purely from
  the engine's booleans and offers a "how was this worked out?" provenance panel naming the
  deployment, the function and the return type.
- `assessment-client.ts` carries the robustness work: `AbortSignal.timeout` for hung networks and
  response shape-validation, so a redeployed-and-drifted schema produces a graceful error rather
  than a false "all clear".

*`ts-apps/regcf-wizard` — 52 files, plus 2 nix expressions and one `turbo.json` line*

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
  about which figures moved when — a client-side regime table would be a second copy of the law
  and the first copy to go stale.
- **An embedded ladder diagram** (`components/Ladder.svelte`): static on the hub, interactive
  inside the step-by-step surface, driven by the framework-free `LadderController`.
- **Validation of every record shape** (`api/validate.ts`) plus the scalar carve-out: a NUMBER
  return is not wrapped under its return-type name, a record is.
- **`nix/regcf-wizard/{package.nix,configuration.nix}`** — everything the deploy needs and nothing
  that performs it. The module defaults to **off**, serves at `/regcf/` (the IDE already owns
  `/`), bakes `BASE_PATH` and `VITE_JL4_BASE_URL` in at build time, and contributes the `regcf`
  corpus bundle *inside its own `mkIf`*.
- `turbo.json` gains `BASE_PATH` to its build task's `env` list — the one-line change the nix build
  needs to bake the SPA's base path.

*Generalisations the Reg CF schema forced, folded back into the shared renderer shape*

A `date` widget (an L4 `DATE` arrives as `{"type":"string","format":"date"}`); `toArguments` no
longer casts to a single `{situation: FormState}` root, because the law-time export has two; and
`orderedChildKeys` falls back to `required` when `propertyOrder` is absent, which it is on a
two-root node — `Object.keys` is alphabetical and would put the investor's figures ahead of the
date they are to be judged against, inverting R8's own derivation.

**Evidence**

Quoted from the source PRs and commits:

*housing-wizard (PR #97):* "`svelte-check` **0 errors / 0 warnings** · `eslint --max-warnings=0`
clean · `vitest` **25/25** · `vite build` (adapter-static SPA) — all green against current
`unstable`." Built with two adversarial multi-agent workflows; "the review found **0 blockers**."
"**Verified end-to-end in a real browser** against a live `jl4-service`: mandatory (Grounds 8 & 10
→ MUST badge), all-clear (green, no grounds), state preserved across 'change my answers', CORS
preflight `200`."

*regcf-wizard (PR #200):* "47 unit tests. check/lint/test/build green." Clean-room at tip
(`rm -rf node_modules && npm ci`, exit 0): "`npm run build`, `lint`, `check`, `test` all exit 0;
`regcf-wizard` 47/47, `svelte-check` 0 errors 0 warnings; `prettier@3.4.2 --check .` clean."

All Reg CF behaviour was measured against a **loopback** `jl4-service` on `127.0.0.1`, never a
deployed host:

- Seeding, by replicating the nix module's own `ExecStartPre`: `"exportCount":6`,
  `"file":"regcf-wizard.l4"`, health `{"ready":1,"total":1,"status":"healthy"}`.
- Elicitation on `can this company raise`: `{}` → `verdict=Undetermined determined=None
  stillNeeded=[4, 6]`; `{"4":true}` → `stillNeeded=[6]`; `{"4":true,"6":true}` → `verdict=Holds
  determined=True stillNeeded=[]`; `{"4":false}` → `verdict=Fails determined=False
  stillNeeded=[]` — limb 2 never asked.
- The join disagreement, same atom: `GET …/ladder` gives `unique=4`,
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
`"value":"UnknownV"` on the wire and stay `UnknownV` when the query plan binds them — the
valuation is the client's, the verdict beside it is still the service's.

**Independence**

Honest, and it differs sharply between the two apps.

- **`housing-wizard` is genuinely standalone.** Its only intra-repo dependency is
  `jl4-client-rpc`, which is already on `main`, and it imports only three types from it
  (`FunctionParameter`, `FunctionParameters`, `ExportedFunctionInfo`) — all present on `main`
  today. The root `workspaces` glob is already `ts-apps/*`, so no root manifest edit is needed.
  It builds, lints, type-checks and tests on `main` as-is, via the ordinary turbo `^build`
  ordering its README documents (`jl4-client-rpc` ships only `dist/` and has no `types` field, so
  it must be built before `svelte-check` runs — which `npx turbo run check --filter=housing-wizard`
  does for you).
- **`regcf-wizard` does not build without `ladder-viz`.** Its `package.json` depends on
  `@repo/ladder-svg` and `@repo/ladder-core`, and neither package exists on `main` — both are new
  in the **ladder-viz** theme, which is also where the `LadderController` that
  `components/Ladder.svelte` mounts lives. This PR must land after ladder-viz.
- **`regcf-wizard` needs a corpus and a service to answer anything.** The five surfaces it calls
  are the exports of `jl4/examples/legal/regcf/regcf-wizard.l4`, owned by the **corpus-regcf**
  theme; the `/query-plan` endpoint and its `verdict`/`stillNeeded` payload are owned by
  **service-cli**. Nothing in this PR fails to compile without them, but the app has nothing to
  talk to, and `api/validate.ts` plus the two `__fixtures__/live-*.json` files encode those wire
  shapes verbatim.
- **The nix module here is inert on its own, and the two lines that arm it are elsewhere.** The
  import line in `nix/configuration.nix` and the `bundles` `default`→`config` move in
  `nix/jl4-service/configuration.nix` both belong to the **ci-build** theme. That second one
  matters: on `main`, `services.jl4-service.bundles` still carries `{classic,
  thailand-cosmetics}` as its `default`, and an `attrsOf` option discards its default the moment
  anything defines the option — so if someone imported this module *and* enabled it before
  ci-build lands, contributing `bundles.regcf` would silently drop the base two. Unimported and
  disabled, as it arrives here, it serves nothing and evaluates nothing.
- **`package-lock.json` and the root `package.json` are in ci-build,** not here, so the
  workspace-link records for both apps land with that theme. Note that the root `overrides.vite`
  pin differs between the branches (`^6.0.7` on `main`, `6.4.2` on `unstable`); PR #200's
  clean-room `rm -rf node_modules && npm ci` was measured on the `6.4.2` base, so an installer run
  against `main`'s pin has not been measured either way.
- The one shared-file edit, `turbo.json`'s added `BASE_PATH`, is additive to an `env` array and
  conflicts with nothing.
- Two façade/spec files these apps read are *not* in this PR:
  `jl4/experiments/housing-act-wizard.l4` (and its Ground 8/10/11/common imports) belongs to
  **experiments**, and `specs/todo/housing-act-citizen-wizard-demo.md` to **specs**.

Known and pre-existing, from the source PR, not introduced here: `turbo.json`'s `test` task
depends on `^check` only, so a single combined `turbo build test …` graph can run a SvelteKit
app's tests before `svelte-kit sync` writes `.svelte-kit/tsconfig.json`. It bites both wizards
alike and is masked in CI, which runs build/lint/check/test as separate steps. Left alone
deliberately — fixing it changes task ordering for every package.

**Risk if rejected**

The repo keeps its language, its engine, its service and its diagrams, and loses the only two
things anyone outside the project can actually *use* — there would again be no demonstration that
an L4 encoding yields a public tool, which is the whole downstream pitch to Lawmaker and the whole
of Track C item C2b. Nothing else breaks: no sibling imports these packages, and dropping this PR
leaves `ci-build`'s nix import line pointing at an absent `nix/regcf-wizard/configuration.nix`,
which is a one-line deletion there.

**Provenance**

- legalese/l4-ide#97 — `feat(housing-wizard): citizen web wizard over Housing Act Sch. 2
  rent-arrears grounds` (branch `mengwong/housing-wizard`)
- legalese/l4-ide#200 — `feat(regcf-wizard): Reg CF citizen wizard (C2b), C2c prepared not
  performed — 6 exports driven live on loopback` (branch `mengwong/wizard-deploy-ready`)
- legalese/l4-ide#177 — `feat(ladder): Step 4 — the LadderSvg displayer` — contributes no file to
  this PR (it deliberately touched nothing under `ts-apps/`); it is listed because
  `regcf-wizard` consumes the `LadderController` it introduced, which ships in the **ladder-viz**
  theme.

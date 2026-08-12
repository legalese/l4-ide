# feat(housing-wizard): a citizen web wizard over Housing Act Sch. 2 rent-arrears grounds

**What this adds**

A standalone SvelteKit single-page app under `ts-apps/housing-wizard` — a public-facing
question-and-answer tool that a member of the public can use to get a legal answer computed by the
real L4 rules. It asks about rent arrears and returns whether a court **must** or **may** order
possession under Housing Act 1988 Schedule 2. The app contains no law: the form is generated at
runtime from the exported function's JSON Schema (`GET /deployments/{id}/functions/{fn}`), and
every figure, sentence and citation on the page is a field of a `jl4-service` response. Before
this, an L4 deployment could be evaluated over HTTP but there was no user-facing surface over it at
all; after this, the same `.l4` a drafter authors auto-generates a working public tool.

**Why**

The pitch this makes concrete is *the same L4 a drafter authors auto-generates a public tool*. It
was built as the downstream demo for the Lawmaker product owner — the UK legislative-drafting
community, The National Archives — as something you can point a non-programmer at. No upstream
issue number is named in the source commits.

## What's in it

37 files: 36 under `ts-apps/housing-wizard` (2,432 insertions), plus a regenerated root
`package-lock.json`.

- A generic, unit-tested **schema→widget renderer**: `labels.ts` / `classify.ts` /
  `build-tree.ts` / `form-logic.ts`, plus a recursive `FieldRenderer` dispatcher and controlled
  leaf widgets (enum→radios, number→currency input, boolean→Yes/No, object→fieldset). It honours
  `propertyOrder`, cleans backtick-quoted L4 labels into prose, and emits real JSON numbers and
  booleans.
- 12 Svelte components, 14 TypeScript modules, 1 vitest file, 1 captured live-schema fixture.
- `AnswerCard.svelte` derives the **MUST (mandatory) vs MAY (discretionary)** badge purely from
  the engine's booleans, and offers a "how was this worked out?" provenance panel naming the
  deployment, the function and the return type.
- `assessment-client.ts` carries the robustness work: `AbortSignal.timeout` for hung networks and
  response shape-validation, so a redeployed-and-drifted schema produces a graceful error rather
  than a false "all clear".
- **`package-lock.json`**, regenerated. The root `workspaces` glob is `ts-apps/*`, so adding this
  directory makes it a workspace and the lockfile must learn about it or `npm ci` fails. It was
  regenerated on this branch — see **Independence**.

## Evidence

Quoted from PR #97:

> `svelte-check` **0 errors / 0 warnings** · `eslint --max-warnings=0` clean · `vitest` **25/25** ·
> `vite build` (adapter-static SPA) — all green against current `unstable`.

It was built with two adversarial multi-agent workflows; "the review found **0 blockers**." And:

> **Verified end-to-end in a real browser** against a live `jl4-service`: mandatory (Grounds 8 & 10
> → MUST badge), all-clear (green, no grounds), state preserved across "change my answers", CORS
> preflight `200`.

Measured for this split: the lockfile regeneration adds 798 lines and removes none.

## Blast radius

**36 new files**, 1 modified.

Build registration only:

- `package-lock.json` — lockfile for its new workspace

**No file outside the housing wizard app is touched, and no existing production source is modified.**

## Independence

**This one is genuinely standalone — which is exactly why it is its own PR rather than sharing one
with the Reg CF wizard.**

Its only intra-repo dependency is `jl4-client-rpc`, which is already on `main`, and it imports just
three types from it (`FunctionParameter`, `FunctionParameters`, `ExportedFunctionInfo`) — all
present on `main` today. It builds, lints, type-checks and tests on `main` as-is, via the ordinary
turbo `^build` ordering its README documents (`jl4-client-rpc` ships only `dist/` and has no
`types` field, so it must be built before `svelte-check` runs — which
`npx turbo run check --filter=housing-wizard` does for you).

Two things to know:

- **The lockfile is touched by two PRs.** The **ci-build** PR carries `unstable`'s whole-workspace
  lockfile; this PR carries one regenerated against `main` plus this app alone, so that this PR
  installs on its own. Whichever lands second needs a plain `npm install` to reconcile. That is
  ordinary lockfile traffic, not a design problem. (It was regenerated with npm 10.9.7 while the
  repo pins `packageManager: npm@11.11.0`; the `lockfileVersion` is unchanged.)
- **The Housing Act façade it is deployed against is not in this PR.**
  `jl4/experiments/housing-act-wizard.l4` and its Ground 8 / 10 / 11 / common imports — the 5-file
  bundle — belong to the **experiments** theme, and
  `specs/todo/housing-act-citizen-wizard-demo.md` to **specs**. The app compiles and its unit tests
  pass without them; it just has no deployment to ask until they land.

Known and pre-existing, from the source PR and not introduced here: `turbo.json`'s `test` task
depends on `^check` only, so a single combined `turbo build test …` graph can run a SvelteKit app's
tests before `svelte-kit sync` writes `.svelte-kit/tsconfig.json`. It is masked in CI, which runs
build/lint/check/test as separate steps. Left alone deliberately — fixing it changes task ordering
for every package.

## Risk if rejected

The repo loses one of only two things anyone outside the project can actually *use*, and the
Lawmaker demo has nothing to point at. Nothing else breaks: no sibling package imports this app,
and no nix or CI file references it.

## Provenance

- **legalese/l4-ide#97** — `feat(housing-wizard): citizen web wizard over Housing Act Sch. 2
  rent-arrears grounds` (branch `mengwong/housing-wizard`)

Split note: on `unstable` this shipped alongside the Reg CF wizard. They are separated here
because their dependency stories differ completely — this one needs nothing that is not already on
`main`, while the Reg CF wizard cannot build without `ladder-viz`. Bundling them would have made
the standalone app un-mergeable on its own.

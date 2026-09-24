# Demo Build Plan — Citizen-Facing Web Wizard over the Housing Act Schedule 2 corpus

**Audience:** the Lawmaker product owner (UK legislative drafting community, hosted at
The National Archives).
**Goal of the demo:** show that the _same_ L4 encoding a drafter would author also
_autogenerates a public-facing tool_ — a citizen enters their situation, gets a plain-English
answer ("can the court order possession against me, and why?"), with citations back to the
statute and an honest **MUST (mandatory) vs MAY (discretionary)** distinction.
**Branch:** `mengwong/housing-act-ground-1` (PR #37 into `unstable`). The façade module and
wizard app are **additive** — they do not touch the 45 authoritative ground files.

---

## 1. The honest starting point (what exists vs what we build)

The downstream backend is **wiring**; the wizard UI is a **genuine build**.

| Capability                                           | State                                                                                    | Implication                                              |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| `@export`/`@desc` annotations → deployable functions | EXISTS (`jl4-core/src/L4/Export.hs`)                                                     | corpus has **none yet** — we author a façade             |
| Deploy `.l4` bundle → REST + schema + MCP            | EXISTS (`jl4-service`; `POST /deployments`, `GET …/functions/{fn}`, `POST …/evaluation`) | local stack via `./dev-start.sh service-only`            |
| Decision + trace + query-plan endpoints              | EXISTS (`jl4-service` data plane)                                                        | powers "why" / progressive disclosure                    |
| **Schema → interactive form generator**              | **DOES NOT EXIST**                                                                       | **this is the core build**                               |
| Citizen _chat_ UI (`ts-apps/webchat`)                | EXISTS                                                                                   | that is the MCP-chatbot path — **not** what we picked    |
| Query-plan elicitation ("ask only what matters")     | EXISTS but **IDE-only** (ladder sidebar)                                                 | reusable brain for Phase 3 progressive disclosure        |
| Citations from inert statute prose at runtime        | **NOT surfaced** (visible only in IDE ladder)                                            | façade carries citations explicitly (faithful, authored) |

**Key catch:** the corpus aggregator `court possession decision` takes a deeply nested
`CaseFile` (records-of-records, dozens of booleans) and returns a `DEONTIC` value. Neither
renders as a clean citizen form or a yes/no answer. So we do **not** expose it directly.

---

## 2. Architecture — a thin citizen façade over the authoritative rules

Author **one new module**, `jl4/experiments/housing-act-wizard.l4`, that:

1. `IMPORT`s the real ground predicate modules (`housing-act-common`, `…-ground-8`,
   `…-ground-10`, `…-ground-11` for the rent-arrears journey).
2. Declares a **FLAT input record** with plain-English `@desc` on every field — booleans,
   numbers, dates only (no nested records). These are the wizard's questions.
3. **Maps** those flat inputs into each ground's real `GroundNClaim` record and calls that
   ground's real `Ground N made out` predicate. The façade **re-implements no rules** — the
   45-file corpus stays the single source of truth.
4. Returns a **presentation-friendly record** `PossessionAssessment HAS`:
   - `possession can be ordered` IS A BOOLEAN
   - `it is mandatory` IS A BOOLEAN — a Part I ground is made out ⇒ court MUST
   - `grounds made out` IS A LIST OF STRING — labels, e.g. "Ground 8"
   - `reasons` IS A LIST OF STRING — plain English + statute citation per ground
   - `what this means` IS A STRING — one-paragraph summary
5. Is marked `@export default <description>` with `@desc` on the entry parameter.

This façade does triple duty: its `GIVEN` schema **autogenerates the form**; its return record
**is the citizen answer**; and the same `@export` makes it a **free MCP tool** later. The pitch
stays true — _the form is generated from the L4 schema; the answer is computed by the real rules._

### Why rent arrears is the chosen journey

- Most relatable citizen scenario; the canonical eviction.
- Cleanly spans the headline structural subtlety:
  - **Ground 8** (Part I, **mandatory**): ≥13 weeks'/3 months' arrears at _both_ notice-service
    and hearing ⇒ court **MUST** order possession. (Threshold raised 8→13 wks by RRA 2025 —
    a nice aside for a drafting audience.)
  - **Ground 10** (Part II, **discretionary**): some arrears ⇒ court **MAY**, if reasonable.
  - **Ground 11** (Part II, discretionary): persistent late payment even if not in arrears at hearing.
- One scenario therefore demonstrates MUST vs MAY in a single screen.
- Architected so additional journeys (Ground 14 anti-social behaviour; Ground 1 landlord's
  home — the RRA-amended ground) plug in as further `@export` entry points / wizard "topics".

---

## 3. The frontend — a small standalone wizard app

New SvelteKit app `ts-apps/housing-wizard` (matches repo Svelte/Vite conventions; reuses
`ts-shared/jl4-client-rpc` schema types and `render-l4-value.ts`). Standalone keeps the demo
controllable and avoids entangling production `webchat`/`jl4-web`.

Flow:

1. On load: `GET /deployments/{id}/functions/{fn}` → parameter JSON-Schema.
2. **Generic schema→widget renderer** (the reusable deliverable): boolean→toggle,
   number→numeric input, date→date picker, enum/`IS ONE OF`→radio/select, one level of record
   nesting→fieldset. `@desc` strings become field labels / help text.
3. On submit: `POST /deployments/{id}/functions/{fn}/evaluation` with the collected facts.
4. **Answer card**: the yes/no headline, a **MUST/MAY badge**, the grounds made out, the
   plain-English `reasons` with statute citations, and "what this means".
5. (Phase 3) "Show me why" → query-plan / trace panel.

Use the `frontend-design` skill for a polished, accessible, mobile-friendly citizen aesthetic.

---

## 4. Phasing

- **Phase 0 — de-risk the backend (½ day).** Write `housing-act-wizard.l4`; `l4 run` it green
  with `#EVAL`s covering made-out / not-made-out / mandatory-vs-discretionary. Run
  `./dev-start.sh service-only`; `zip` the experiments bundle; `POST /deployments`; poll;
  confirm `GET …/functions/{fn}` returns the expected schema and `POST …/evaluation` returns the
  expected `PossessionAssessment`. **Proves the whole path before any UI.**
- **Phase 1 — core wizard (1 day).** Standalone SvelteKit app; generic schema→form renderer;
  submit → answer card (functional, minimal styling). Hardcode the local service URL.
- **Phase 2 — citizen polish (1 day).** Plain-English answer, MUST/MAY badge, citations +
  statute links, the rent-arrears narrative, `frontend-design` pass, responsive layout.
- **Phase 3 — stretch (optional).** Progressive disclosure via the query-plan endpoint (ask
  only what matters; stop once determined); additional journeys (G14, G1); a "show the law"
  panel surfacing the inert statute prose; deploy to a shareable URL (local or Legalese Cloud).

**Demo-ready after Phase 2.** Phases 0–2 ≈ 2–3 focused days.

---

## 5. Open decisions (recommended defaults; flag any to change)

1. **Journey:** rent arrears (G8/G10/G11). _(Recommended — best MUST/MAY story.)_
2. **Frontend:** new standalone `ts-apps/housing-wizard`. _(vs extending `webchat`/`jl4-web`.)_
3. **Hosting for the demo:** local `jl4-service`. _(Cloud deploy optional, Phase 3.)_
4. **Façade style:** thin presentation layer importing the real predicates; authored citation
   strings (not runtime inert-prose extraction). _(Auto-extraction is a Phase-3 stretch.)_

---

## 6. Risks / watch-items

- **No form generator exists** — Phase 1 is real frontend work, not configuration. Phase 0
  de-risks the backend so UI effort isn't wasted on a broken path.
- **Schema fidelity:** confirm `jl4-service` emits enums/dates in the JSON-Schema in a
  form-renderable way (verify in Phase 0 with the actual `GET …/functions/{fn}` payload).
- **Field-name sanitization:** `jl4-service` hyphenates backtick identifiers for JSON/URLs
  (e.g. `arrears at hearing` → `arrears-at-hearing`); the renderer must use `x-sanitized-name`
  / original-name mapping from `custom-protocol.ts`.
- **Keep the façade additive** so PR #37's authoritative grounds remain untouched.

---

## 7. Phase 0 — COMPLETE (2026-06-25)

**Built:** `jl4/experiments/housing-act-wizard.l4` — the citizen façade. Flat `Situation`
input (5 plain-English `@desc` fields), routes into the real `Ground 8/10/11 made out`
predicates, returns a `PossessionAssessment` record. One `@export default` entry point
`assess possession for rent arrears`. 11 `#ASSERT`s + 4 `#EVAL`s, all green under
`l4 run` (`JL4_FIXED_NOW=2025-01-01T00:00:00Z`).

**Verified end-to-end against a local `jl4-service`** (built with `cabal build jl4-service`;
deployment id `housing-wizard`, 5-file bundle, status `ready`):

- **Input schema is form-renderable.** `GET /deployments/{id}/functions/{fn}` returns
  `situation` as an object whose fields are: the `RentPeriod` field as
  `enum:[weekly or fortnightly, monthly, other]` (→ dropdown), three `number` fields, one
  `boolean` (→ toggle), each with its `@desc` description and an `x-sanitized-name`
  (hyphenated key). Matches the self-contained `insurance-premium` example exactly.
- **Evaluation is correct over HTTP.** `POST …/{fn}/evaluation` with
  `{"arguments":{"situation":{…}}}` returns the right `PossessionAssessment` for all cases:
  serious arrears → `can=true, mandatory=true, [G8,G10]`; some arrears → `[G10]`,
  `mandatory=false`; persistently late → `[G11]`; all clear → `can=false, []`.

**Findings that shape Phase 1 (durable):**

1. **The input schema lives at the PER-FUNCTION endpoint**, `GET …/functions/{fn}`, NOT in
   the deployment-summary `GET /deployments/{id}` (whose `parameters` is `{}` — a summary, not
   a 404-level problem). The wizard must fetch the per-function schema.
2. **Evaluation response envelope:** unwrap `contents.result.value.PossessionAssessment`
   (`tag:"SimpleResponse"`).
3. **Argument keys:** original spaced L4 names work in `arguments` (e.g. `"rent amount each
time"`). `x-sanitized-name` is available if the renderer prefers hyphenated keys.
4. **`l4 batch` is NOT usable here:** its wrapper codegen mis-parses a spaced backtick
   entry-point name (`assess possession for rent arrears`) as five identifiers. Irrelevant to
   the wizard (which uses jl4-service), but flag for the l4 team.
5. **Local run recipe:** `cabal build jl4-service` then run the binary with
   `--port 8080 --store-path /tmp/jl4-store`; deploy via `POST /deployments` (multipart
   `id` + `sources` zip); poll `…/updates/{job}` to `applied`.

**Next:** Phase 1 (standalone `ts-apps/housing-wizard` + generic schema→form renderer) on
approval.

---

## 8. Phase 1 — COMPLETE (2026-07-01), built with adversarial workflows

**Approved:** "proceed. use adversarial workflows." Two adversarial workflows bracketed the build:
a **design** workflow (3 independent designs → 3 adversarial critics → synthesized build spec)
and a **review** workflow (4 review dimensions → adversarial per-finding verification → verdict).

**Built:** standalone SvelteKit app `ts-apps/housing-wizard` (~32 files; npm + turbo workspace,
Svelte 5 runes, adapter-static SPA, Tailwind 4). Core is a **generic schema→widget renderer**
(`src/lib/schema/*`, pure + unit-tested): `cleanLabel`/`fieldId`, `classifyWidget`
(object-first, enum length-gated), `orderedChildKeys`/`buildFieldTree`, `seed`/`validate`/
`toArguments`, and `createFormState` ($state). Recursive `FieldRenderer` (self-import, NOT
`<svelte:self>`) dispatches to controlled leaf widgets (enum/number/boolean/text/unsupported)
that mutate a single `$state`proxy tree via`parent[node.key]`. `AnswerCard` derives the
MUST/MAY outcome **purely from the engine booleans**, shows grounds chips + verbatim reasons +
a "how was this worked out?" provenance disclosure (deployment/function/returnType — lands the
"same L4 the drafter authored generated form AND answer" pitch).

**Green gates:** `svelte-check` 0/0 · `eslint --max-warnings=0` clean · `vitest` 25/25 ·
`vite build` static SPA with CSP `connect-src` including `http://localhost:8080` · live
`jl4-service` evals correct for all 4 fixtures.

**Footguns preempted during the build (from the design workflow + ground-truth):** the wire
**omits** `enum` on non-enum nodes (undefined, not `[]`) → faithful `WireSchema` + `enum?.length`;
`propertyOrder` (not key order) drives display; JSON-number coercion (stringified = verified 422);
negative + non-finite number validation (a negative rent otherwise yields a false MUST card);
`$state(...)` cannot be a bare `return` (assign then return); strict CSP `style-src` → all outcome
colour via static `.outcome-*` classes; `jl4-client-rpc` must be built first (turbo `^build`),
imported from the package ROOT.

**Review verdict (adversarially verified): 0 blockers.** Fixes APPLIED post-review: fetch
`AbortSignal.timeout(8000)` → NetworkError (hung-Wi-Fi spinner recovery); `validateAssessment`
in `unwrapResult` (redeployed-schema drift → graceful evalError, not a false "all clear" or a
render crash); dark-mode `--brand-dark`; `Number.isFinite` (Infinity); enum/boolean
`aria-describedby`; sr-only results `h1`. Adversarial verify correctly killed 8 false alarms
(the "scope caveat missing on MUST/MAY" claim was wrong — it is persistent via `HelpFooter` in
the layout; the `SchemaForm` root-write and stale-`$state` claims were unreachable/phase-gated).

**⚠️ OPEN DECISION — fortnightly Ground-8 (corpus-level, flagged for the drafter):** the corpus
`RentPeriod` enum bundles `weekly or fortnightly` as ONE variant and Ground 8 applies 13× the
per-period rent uniformly. For a genuinely **fortnightly** tenant this is ~26 weeks (double the
statutory 13), UNDER-stating a mandatory-eviction risk, and the façade's authored reason string
asserts "13 weeks" the engine never period-checked. NOT reachable by the 4 scripted fixtures
(all read the option as weekly). This is an encoded-law/interpretation question in
`housing-act-ground-8.l4` (which already carries an interpretation note ~lines 92–102), NOT a
wizard bug — left for Meng to decide (options: split the enum into weekly/fortnightly + 6.5×
threshold; normalise fortnightly → weekly-equivalent; or constrain the demo to weekly/monthly).
Demo guidance meanwhile: drive the 4 scripted cases; don't invite "fortnightly".

**Run:** `npx turbo run dev --filter=housing-wizard` (vite :5173) with a local `jl4-service`
on :8080 holding the `housing-wizard` deployment. Uncommitted on the branch (commit on request).

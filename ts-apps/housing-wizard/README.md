# housing-wizard

A standalone, citizen-facing web wizard over the Housing Act 1988 Schedule 2
rent-arrears grounds for possession.

**The pitch:** the _same_ L4 a drafter authors auto-generates this public tool.
The form is generated from the exported function's JSON-Schema; the answer is
computed by the real L4 rules in `jl4-service`. The wizard hard-codes **no legal
content** — only the tests assert specific engine strings.

It asks five short questions and returns a plain-English answer with the
legally load-bearing **MUST (mandatory)** vs **MAY (discretionary)** distinction
(Ground 8 vs Grounds 10/11), the grounds made out, and reasons with statutory
citations.

## How it works

1. On load (in the browser — never at prerender) it fetches the function schema:
   `GET {SERVICE_BASE_URL}/deployments/{id}/functions/{fn}`.
2. A generic **schema → widget renderer** (`src/lib/schema/*`) builds the form:
   enum → radio group, number → numeric input, boolean → Yes/No, object →
   fieldset. This renderer is legislation-agnostic and reusable.
3. On submit it POSTs the collected facts to `…/{fn}/evaluation` and renders the
   `PossessionAssessment` as an answer card.

The service base URL, deployment id and function name are configurable via env
(`VITE_JL4_BASE_URL`, `VITE_JL4_DEPLOYMENT`, `VITE_JL4_FUNCTION`); defaults point
at a local `jl4-service` and the `housing-wizard` deployment.

## Prerequisites

This is an **npm + turbo** workspace. From the repo ROOT:

```sh
npm install
# jl4-client-rpc ships only dist/ and is unbuilt in a fresh checkout; it has no
# "types" field, so housing-wizard will not typecheck until it is built. turbo's
# ^build dependency builds it automatically when you use --filter:
npx turbo run check --filter=housing-wizard   # builds deps, then svelte-check
```

You also need a running `jl4-service` with the `housing-wizard` deployment. From
the repo root, with the service built:

```sh
jl4-service --port 8080 --store-path /tmp/jl4-store
# then deploy the 5-file bundle (wizard + grounds 8/10/11 + common) as id
# "housing-wizard" via POST /deployments (multipart id + sources zip).
```

(The CSP `connect-src` in `svelte.config.js` already lists `http://localhost:8080`.
For a non-localhost demo, add the prod origin to BOTH `connect-src` and
`VITE_JL4_BASE_URL`, or the cross-origin fetch is blocked silently.)

## Run / check / build

```sh
npx turbo run dev   --filter=housing-wizard   # vite dev server on :5173
npx turbo run check --filter=housing-wizard   # svelte-check (0 errors expected)
npx turbo run test  --filter=housing-wizard   # vitest pure-helper unit tests
npx turbo run lint  --filter=housing-wizard   # eslint --max-warnings=0
npx turbo run build --filter=housing-wizard   # static SPA into build/
```

## Acceptance fixtures (manual smoke test)

With the service running and a browser pointed at the dev server:

| Situation (weekly, £100 rent)          | Result                    |
| -------------------------------------- | ------------------------- |
| notice £1300, hearing £1400, late = No | **MUST** — Grounds 8 & 10 |
| notice £300, hearing £500, late = No   | **MAY** — Ground 10       |
| notice £0, hearing £0, late = Yes      | **MAY** — Ground 11       |
| notice £0, hearing £0, late = No       | **Clear** — no grounds    |

This tool explains the rules — it is **not legal advice**.

# jl4-service

Multi-tenant decision service for L4 rule bundles. Deploy L4 programs as persistent, namespaced REST APIs with zip-upload bundles, async non-destructive deploys, backwards-compatibility-gated updates, and filesystem persistence.

## Features

- **Multi-tenant** — isolated deployments under `/deployments/{id}`
- **Zip-bundle deployment** — upload multiple `.l4` files at once, persisted to disk
- **Filesystem-backed** — deployments auto-reload on startup
- **Staging** — old version serves traffic while new bundle compiles
- **Deduplication** — SHA-256 content hash skips recompilation of identical sources
- **Health check** — `GET /health` with deployment counts
- **Concurrency limits** — configurable, returns 503 when exceeded
- **Per-evaluation memory limit** — GHC allocation limit (default 256 MB)
- **Configurable timeouts** — separate eval and compile timeouts
- **Upload validation** — zip size, file count, path traversal, deployment ID format
- **Structured logging** — JSON lines to stdout
- **OpenAPI** — metadata at `/deployments/{id}/openapi.json`
- **GraphViz DOT output** — raw DOT only, clients render themselves

## Quick Start

```bash
# Build
cabal build jl4-service

# Start with default settings (port 8080, store at /tmp/jl4-store)
cabal run jl4-service

# Start with debug logging and custom port
cabal run jl4-service -- --debug --port 9000 --store-path ~/.local/share/jl4-service

# Or configure via environment variables
JL4_PORT=9000 JL4_DEBUG=true cabal run jl4-service
```

## Deploying a Bundle

Create a zip archive containing `.l4` files, then upload it:

```bash
# Create a bundle
cd jl4/experiments && zip -r /tmp/bundle.zip *.l4

# Deploy with a chosen ID
curl -X POST http://localhost:8080/deployments \
  -F "id=my-rules" \
  -F "sources=@/tmp/bundle.zip"
# Returns 202 with {"id":"my-rules","status":"compiling","updateId":"<job>"}

# Poll the deploy/update job until it applies (or is rejected)
curl http://localhost:8080/deployments/my-rules/updates/<job>
# {"updateId":"<job>","deploymentId":"my-rules","status":"applied"}

# The deployment itself is then ready
curl http://localhost:8080/deployments/my-rules
# {"id":"my-rules","status":"ready",...}
```

If you omit the `id` field, a UUID is generated automatically.

L4 functions are discovered via `@export` annotations in the source:

```l4
@export default Check whether a person qualifies
GIVEN walks IS A BOOLEAN
      eats  IS A BOOLEAN
      drinks IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE compute_qualifies IF walks AND eats AND drinks
```

## API Reference

### Health

| Method | Endpoint  | Description                               |
| ------ | --------- | ----------------------------------------- |
| `GET`  | `/health` | Health check with deployment state counts |

Returns `{"status":"healthy","deployments":{"total":N,"ready":N,"pending":N,"compiling":N,"failed":N}}`. Exempt from the concurrency limiter so orchestrator probes always succeed.

### Control Plane

Manage deployment lifecycle.

| Method   | Endpoint                          | Description                                                                                           |
| -------- | --------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `POST`   | `/deployments`                    | Create or overwrite a deployment (multipart: `id` + `sources` zip)                                    |
| `GET`    | `/deployments`                    | List all deployments (`?functions=simple\|full\|none`, `?scope=id`)                                   |
| `GET`    | `/deployments/{id}`               | Get the **live** deployment status (`?functions=simple\|full\|none`; triggers compilation if pending) |
| `GET`    | `/deployments/{id}/updates/{job}` | Poll an async deploy/update job (see below)                                                           |
| `PUT`    | `/deployments/{id}`               | Update an existing deployment, enforcing the backwards-compatibility gate                             |
| `DELETE` | `/deployments/{id}`               | Remove a deployment                                                                                   |

Deployment states: `pending` (lazy-load, not yet compiled), `compiling` (compilation in progress), `ready` (compiled and serving), `failed` (compilation error stored). `GET /deployments/{id}` always reflects the **live** deployment only — an in-flight `POST`/`PUT` never changes it.

#### Async deploy/update jobs

`POST` and `PUT` are asynchronous and non-destructive. They return `202` with `{"status":"compiling","updateId":"<job>"}`; the work (compile + bounded time/memory, plus the compatibility check on `PUT`) runs in the background. The currently-live version keeps serving the whole time — nothing is persisted or swapped unless the new bundle compiles **and** (for `PUT`) is backwards-compatible. A brand-new `POST` id simply does not exist (`GET` 404s) until its job applies.

Poll the returned job at `GET /deployments/{id}/updates/{job}`:

| Status      | Meaning                                                            |
| ----------- | ------------------------------------------------------------------ |
| `compiling` | Still compiling / being compatibility-checked                      |
| `applied`   | The new bundle is compiled, compatible, and now the live version   |
| `rejected`  | Breaking change, compile failure, or timeout — `error` has details |

`POST` is **ungated** (create/overwrite — it does not run the compatibility check). `PUT` enforces the **backwards-compatibility gate**: the new bundle's exported-function interface (every parameter name/type/required-ness and the return type, recursively) must stay compatible with what is currently deployed. Adding a new optional parameter or a new function is fine; renames, type changes, removed/newly-required parameters, narrowed input enums (and the mirror cases on the return value) are rejected. Terminal jobs are retained for 10 minutes, then pruned.

**Optimistic compilation:** Evaluation and function listing on pending deployments trigger compilation with a 2-second optimistic timeout. If compilation finishes within 2 seconds, the result is returned inline (200). If not, the response is HTTP 202 with `{"status":"compiling","retryAfterMs":2000}` and a `Retry-After: 2` header — the client should retry after the delay. File browsing endpoints never require compilation.

**Validation rules:**

- Deployment IDs: max 128 characters, `[a-zA-Z0-9_-]` only, must not start with a dot, no `..` sequences, and not one of the reserved words `health` / `deployments` / `openapi.json`
- Zip uploads: max 2 MB (configurable), max 5096 files (configurable), no path traversal
- If the `id` field is omitted, a UUID is generated automatically
- Duplicate detection: if the uploaded sources match the deployment already registered under the requested id (by content hash), that deployment is returned, as `ready` with no `updateId`, instead of recompiling
- **An upload without an `id` always compiles and takes a deployment slot.** It is given a new id, so it never matches an existing deployment, however identical its sources. A client that redeploys in a loop without an `id` therefore gains one deployment per upload, until the service reaches `--max-deployments` (default 1024) and refuses every new one with `400` `Maximum deployment limit reached`. To replace a deployment rather than add one, send the same `id` each time, or `PUT /deployments/{id}`. Until legalese/l4-ide#162 (2026-07-28), an upload whose sources matched any ready deployment got that deployment back, whatever id it asked for, and nothing was created

### Data Plane

Evaluate functions within a deployment. All routes are available in both short form (`/{id}/{fn}/...`) and long form (`/deployments/{id}/functions/{fn}/...`).

| Method | Endpoint                                               | Short Route                      |
| ------ | ------------------------------------------------------ | -------------------------------- |
| `GET`  | `/deployments/{id}/functions`                          | `/{id}/functions`                |
| `GET`  | `/deployments/{id}/functions/{fn}`                     | `/{id}/{fn}`                     |
| `POST` | `/deployments/{id}/functions/{fn}/evaluation`          | `/{id}/{fn}/evaluation`          |
| `POST` | `/deployments/{id}/functions/{fn}/evaluation/batch`    | `/{id}/{fn}/evaluation/batch`    |
| `POST` | `/deployments/{id}/functions/{fn}/query-plan`          | `/{id}/{fn}/query-plan`          |
| `GET`  | `/deployments/{id}/functions/{fn}/ladder`              | `/{id}/{fn}/ladder`              |
| `GET`  | `/deployments/{id}/functions/{fn}/state-graphs`        | `/{id}/{fn}/state-graphs`        |
| `GET`  | `/deployments/{id}/functions/{fn}/state-graphs/{name}` | `/{id}/{fn}/state-graphs/{name}` |
| `GET`  | `/deployments/{id}/openapi.json`                       | `/{id}/openapi.json`             |
| `GET`  | `/deployments/{id}/files`                              | `/{id}/files`                    |
| `GET`  | `/deployments/{id}/files/{path}.l4`                    | `/{id}/{path}.l4`                |

Function names with spaces can use hyphens or URL-encoding in the path (e.g., `check-person` or `check%20person` for `check person`).

### File Browsing

Browse L4 source files within a deployment. **File browsing works immediately after upload — no compilation required.** This includes all deployment states: pending, compiling, ready, and failed.

| Method | Endpoint                            | Description                                                    |
| ------ | ----------------------------------- | -------------------------------------------------------------- |
| `GET`  | `/deployments/{id}/files`           | List files with content (`?identifier=`, `?search=`, `?file=`) |
| `GET`  | `/deployments/{id}/files/{path}.l4` | Raw file content (`?lines=start:end` for line range)           |

The `/files` endpoint supports three query parameters (combinable):

- `?identifier=name` — find definitions and references of an L4 identifier (text-based, works pre-compilation)
- `?search=text` — grep source files (case-insensitive, works pre-compilation)
- `?file=path.l4` — scope to a specific file

Export information (which functions a file exports) is available only after compilation. Pre-compilation responses include file content but empty export lists.

### Evaluation

```bash
curl -X POST http://localhost:8080/deployments/my-rules/functions/compute_qualifies/evaluation \
  -H "Content-Type: application/json" \
  -d '{"arguments":{"walks": true, "drinks": true, "eats": true}}'
```

#### Answers

The direct path and the wrapper path described below encode an answer the same way.
A `MAYBE` answer is `null` for `NOTHING` and the value itself for `JUST`.
A list is a JSON array, even when it has one element.
An enum answer is its name, without backticks; a constructor named `TRUE` or `FALSE`, in any case, comes back as `true` or `false`.
A record is an object keyed by its constructor's name, holding its fields: `{"Pair": {"left": 5, "right": 6}}`.
A field's name is spelled as declared, spaces included, and not hyphenated as a request's may be: `{"Pair": {"left": 5, "right side": 6}}`.
A `MAYBE (MAYBE x)` answer cannot tell `NOTHING` from `JUST NOTHING`: both are `null`.

The function's published `returnSchema` does not describe two of these shapes yet: it gives a record's fields at the top level, without the constructor's name, and a `MAYBE` as its inner type, without `null` (smucclaw/l4-ide#1010).

#### Missing and uncertain inputs

An input left out of `arguments` is _absent_. An input sent as `null` is _not known_, and one sent as `{}` ("uncertain") is treated exactly like `null`, whatever its type, a record's included.
The two are different (T3 in `specs/todo/TYPICALLY-ONE-BEHAVIOUR-SPEC.md`): an absent input can take a default, and a `null` one never does.

**Defaults.** An input with a `TYPICALLY` default — on the exported function's own `GIVEN`, on a section `GIVEN` it reads, or on a field of a record it takes — may be left out, and then takes its default.
The function's schema says so: such an input is not under `required`, and its default is the JSON Schema `default` keyword.
Every response says which defaults the answer rests on, in `presumed`, beside `result`: the names of inputs that were left out, took their default, and were actually read by the evaluation (a record field by its path, `cfg.timeout`).
A `MAYBE` input with no default, left out, is `NOTHING`, and is listed the same way.
A refusal (`EvaluatorRefused`, from a `REFUSE` the rule reached) is an answer too, and carries the defaults it rests on in its own `presumed`, beside the reason: `{"contents":{"contents":"cannot decide for a non-resident","presumed":["is resident"],"tag":"EvaluatorRefused"},"tag":"Error"}`.
Any other error response has no `presumed`, since it carries no answer.
An input the rule never reached is not listed, even if it was left out.
**A misspelled name is refused where a default is taken.** In a request that leaves out an input with a default, an argument that names no input is refused, naming the nearest one (`Unknown parameter 'has capasity' (did you mean 'has capacity'?)`), since it may be the input left out; the same holds for a field inside a record argument. Where no default is taken, an extra argument is ignored, as before.
`null` is "not known" on every input that is not a `MAYBE`, whatever its type, so it is refused by name even where there is no default (`Parameter 'shade' is null, which means the value is not known: supply a value`). A type that is a synonym for a `MAYBE` is a `MAYBE`.
For this rule:

```l4
§ `Capacity`
    GIVEN `has capacity` IS A BOOLEAN TYPICALLY TRUE

@export
GIVEN `is adult` IS A BOOLEAN
GIVETH A BOOLEAN
`may contract` MEANS `is adult` AND `has capacity`
```

```bash
curl -X POST http://localhost:8080/deployments/my-rules/functions/may-contract/evaluation \
  -H "Content-Type: application/json" \
  -d '{"arguments":{"is adult": true}}'
# {"contents":{"presumed":["has capacity"],"result":{"value":true}},"tag":"SimpleResponse"}
```

**`"presumption": "hard"`** in the request (beside `arguments`) uses no defaults: an input left out is absent with none, as below, and a `MAYBE` input left out is missing rather than `NOTHING`. `"soft"`, the default, uses them. The batch endpoint takes the same field for all its cases, and each case carries its own `@presumed`; see [Batch Evaluation](#batch-evaluation) for a case that is refused or fails. The MCP tools take no `presumption` argument and always evaluate with `"soft"`; their result is the same JSON as the HTTP response, `presumed` included.

**Absent with no default, or `null`.**
Most requests are evaluated directly, and such an input that is not a `MAYBE` is refused before evaluation starts: `Parameter 'walks': missing required parameter`, or, for `null` on an input that has a default, a message saying `null` never takes it. Every such input is named, one per line.

Two kinds of request go through a generated wrapper instead: any request with a `{}` in the value of one of its inputs, or a `null` inside a record or list, and every request to a `DEONTIC` function.
On that path a missing `BOOLEAN` input is an assumed term, which costs nothing if the rule never needs its value.
If the rule needs it — tests it with `IF`, `AND`, `OR` or `NOT`, compares it, or returns it — evaluation stops and names it:

```
I could not continue evaluating, because I needed to know the value of
  `walks (not supplied)`
but it is an assumed term.
```

Before the fix for smucclaw/l4-ide#992, such an input was silently `FALSE` on this path.

A missing `DATE`, `TIME` or `DATETIME` input is refused on this path with the direct path's message, and one whose string does not parse is refused with a message that quotes it: `Parameter 't': could not read "not a time" as a TIME`.

Limits, measured 2026-10-02:

- **A `CONSIDER` with an `OTHERWISE` branch does not stop.** It reads an assumed term, matches none of its `WHEN` patterns, and takes the `OTHERWISE` branch, with no error: `ASSUME x IS A BOOLEAN` then `CONSIDER x WHEN TRUE THEN 1 OTHERWISE 2` gives `2`. So on the wrapper path, a missing `BOOLEAN` that the rule reads only through such a `CONSIDER` gets the catch-all answer. Build step 1 (§8) of `UNKNOWN-EVALUATION-SPEC.md`, specified in legalese/l4-ide#526 (merged as a spec) and not built yet, makes such a `CONSIDER` stop and name the input.
- On the wrapper path, a missing input that is neither a `BOOLEAN` nor a `MAYBE`, and has no default, fails the whole request even when the rule would never have read it. The message names it, `Missing required field 'unused' in JSON object`, or, for a `DATE`, `TIME` or `DATETIME`, which the wrapper reads as a string and converts, `Parameter 'unused': missing required parameter`.
- **`null` on an input with a default is refused early on the direct path and late on the wrapper path.** The direct path refuses it before evaluation; on the wrapper path, a `BOOLEAN` sent as `null` is an assumed term, which is refused only if the rule reads it. So `{"is adult": false, "has capacity": null, "unused flag": false}` is refused, and the same request with `"unused flag": {}` answers `false`, because `has capacity` is never read. This extends the early/late split above; it did not create it.
- On the wrapper path, a value supplied for an input declared with `ASSUME` does not reach the rule, which stops as if the input were missing. Inputs declared with a section `GIVEN` are delivered.
- A `TYPICALLY` on a written `ASSUME` is not a default here, as it is not for `#EVAL`: it is not published, and the input stays required (W6 of `specs/todo/TYPICALLY-ONE-BEHAVIOUR-SPEC.md`).
- The decoders fill a default only for an input or a record field. A field of an enum constructor that carries data keeps its `TYPICALLY` as metadata.

Measured 2026-10-06:

- A list answer of more than 200 elements on the direct path, or more than 199 on the wrapper path, comes back cut short and ending in two `null`s, with status 200.
  A list inside another value is cut sooner: a `MAYBE` list of 200 elements comes back as 199 elements and two `null`s on the direct path, and one of 199 as 198 and two `null`s on the wrapper path (measured 2026-10-07).

#### Trace Output

Include execution traces with `?trace=full` or the `X-L4-Trace: full` header. Add `?graphviz=true` to include DOT source in the response (requires `trace=full`).

```bash
curl -X POST 'http://localhost:8080/deployments/my-rules/functions/compute_qualifies/evaluation?trace=full&graphviz=true' \
  -H "Content-Type: application/json" \
  -d '{"arguments":{"walks": true, "drinks": true, "eats": true}}'
```

#### Deontic (Contract) Evaluation

Functions returning `DEONTIC` model contract obligations and require additional parameters for simulation:

```bash
curl -X POST http://localhost:8080/deployments/my-contract/functions/service-requirement/evaluation \
  -H "Content-Type: application/json" \
  -d '{
    "arguments": {"state": {"status": "Active", "metrics": {"revenue": 1000000}}},
    "startTime": 0,
    "events": [
      {"party": {"Name": "Alice"}, "action": "maintain eligible service", "at": 1}
    ]
  }'
```

- `arguments` — the function's GIVEN parameters (same as non-deontic)
- `startTime` — start time for contract simulation (required for DEONTIC)
- `events` — list of trace events, each with `party`, `action`, and `at` timestamp (required for DEONTIC)

### Batch Evaluation

Evaluate a function across many input cases:

```bash
curl -X POST http://localhost:8080/deployments/my-rules/functions/compute_qualifies/evaluation/batch \
  -H "Content-Type: application/json" \
  -d '{
    "outcomes": ["result"],
    "cases": [
      {"@id": 1, "walks": true, "eats": true, "drinks": true},
      {"@id": 2, "walks": false, "eats": true, "drinks": true},
      {"@id": 3, "walks": true, "eats": false, "drinks": false}
    ]
  }'
```

The response has one entry per case, in the order the cases were sent, each under its `@id`:

```json
{
  "cases": [
    { "@id": 1, "@presumed": [], "value": true },
    { "@id": 2, "@presumed": [], "value": false },
    { "@id": 3, "@presumed": [], "value": false }
  ],
  "summary": {
    "casesIgnored": 0,
    "casesProcessed": 3,
    "casesRead": 3,
    "processorCasesPerSec": 0,
    "processorDurationSec": 0,
    "processorQueuedSec": 0
  }
}
```

An answered case carries the function's result under `value`.
`outcomes` is required, but the service does not use it yet: every answered case carries the whole result.
Every case carries its own `@presumed`, the inputs it left out whose defaults its answer or refusal used (see [Missing and uncertain inputs](#missing-and-uncertain-inputs)).
A case the rule refused carries `@refused` (the reason) and still counts as processed; a case that failed carries `@error` (the message) and is counted in `casesIgnored`.
Neither has a `value`.
The three `processor…` fields of `summary` are not measured, and are always `0`.
The deployment's OpenAPI document, `GET /deployments/{id}/openapi.json`, describes this response key by key.

#### When a case reaches a limit

Each case is evaluated under its own [limits](#resource-limits), `--eval-timeout` and `--max-eval-memory-mb`, as a single evaluation is, with the gaps listed under [What the limits do not cover yet](#what-the-limits-do-not-cover-yet).
A case that reaches one fails on its own: the other cases keep their answers, and the batch is still a `200`.
It carries `@error`, and `@limit` beside it:

```json
{
  "@error": "Evaluation resource limit exceeded: this case did not finish within the time limit of 3 s (--eval-timeout)",
  "@id": 4,
  "@limit": "time",
  "@presumed": []
}
```

`@limit` is `"time"` when the case did not finish within `--eval-timeout`, and `"memory"` when it allocated more than `--max-eval-memory-mb`.
No other case has a `@limit` key.

**How to read it.**
`@limit` marks a case the service stopped before it finished, and sending it again may give an answer: to a service with a higher limit, or, for `"time"`, when the service is less busy, since the time limit is wall-clock (see below).
Neither `@limit` nor its absence promises what the next attempt will do, because a case's outcome can depend on values the deployment has already worked out.
A value defined at the top level of an imported module is computed once and then kept, across requests, so the first case that needs it pays its time, memory and recursion depth, and later cases find it ready.
Measured on 2026-10-03: at `+RTS -N1`, four identical cases under a 64 MB limit came back as `"memory"` and then three answers; and a case stopped by the evaluator's recursion-depth limit answered, unchanged, once another case had worked out the value it needed.
That recursion-depth limit is the evaluator's own, fixed at 1,000,000 levels, and it arrives as a plain `@error`, a message that begins `Stack overflow:`, with no `@limit`.

#### How the cases share the cores

The cases run concurrently, but no more batch cases run at once, counting every batch in flight, than the service has cores (its capabilities, `+RTS -N`; see [CLI Options](#cli-options)).
A case's clock starts when the case starts running, not when its batch arrives, so waiting behind other cases, of its own batch or another, does not count against it.
So neither the size of a batch nor the number of batches sent at once decides whether a case meets the time limit, though the other work listed below can.
Each request has at most as many cases waiting for a slot as there are slots, and a freed slot goes to the case that has waited longest, so the requests take turns.
A small batch sent behind a big one therefore waits about one case-time for each request ahead of it, not for the whole of the big batch, and `--max-concurrent-requests` bounds how many requests can be ahead: measured on 2026-10-03 at `+RTS -N2`, a one-case batch sent 0.5 s after a batch of twelve 2-second cases answered in 1.5 s.
Only batch cases take slots.
Everything else the service does runs beside them on the same cores: single evaluations and MCP calls, compiling deployments, query plans, rendering ladder diagrams and state graphs, and encoding responses, a batch's own included.
On one core the whole batch takes as long as its cases take together, and more cores shorten it: measured on 2026-10-02 on a machine busy with other work, 100 cases of 0.19 s each took 15.7 s on one core and 4.0 to 5.5 s on ten.

#### What a batch can cost

A batch whose cases all run to the time limit takes about ⌈cases ÷ cores⌉ × `--eval-timeout`, and longer while other batches are in flight, since the requests take turns at the same slots.
The service sets no limit on the number of cases in a batch.
It also goes on working through a batch after the client has disconnected: measured on 2026-10-02 at `+RTS -N4`, 24 cases that each ran to a 2-second limit kept more than three cores busy for about 12 s, although the client gave up after 6 s.

### Query Planning

Build interactive questionnaires by asking only the questions that still matter:

```bash
curl -X POST http://localhost:8080/deployments/my-rules/functions/compute_qualifies/query-plan \
  -H "Content-Type: application/json" \
  -d '{"arguments":{"walks": true}}'
```

Returns which inputs are still needed, ranked by impact on the outcome.

### Ladder Diagrams

Fetch the AND/OR structure of a boolean `DECIDE` on its own, without posting an
argument set:

```bash
curl http://localhost:8080/deployments/my-rules/functions/compute_qualifies/ladder
```

Returns a `RenderAsLadderInfo` — `{"verDocId": …, "funDecl": {"name", "params", "body"}}` —
where `body` is the `And`/`Or`/`Not`/`Implies`/`UBoolVar`/`App` tree the IDE's ladder
renderer consumes.

This is **the same value** that every `query-plan` 200 already returns in its
`ladder` field; both read one memoised structure per function, so the GET adds
no information the POST did not already expose. Only `@export`ed,
boolean-returning `DECIDE`s can be visualized — anything else is a `400`, as is
any decision whose ladder exceeds `--max-ladder-nodes` (see [Resource
Limits](#resource-limits)).

Ladder leaves and `query-plan` atoms are now in **one** `atomId` namespace. Every
`atomId` the plan reports — in `ranked`, `stillNeeded`, `asks[].atoms`, and as a
key of `impactByAtomId` — appears on the diagram, and **is** accepted as a binding
key in `arguments`. Fetch the diagram once, then post answers keyed by what the
diagram calls its leaves.

> **The containment runs one way.** Every plan atom is a ladder leaf; not every
> ladder leaf is a plan atom. The standing exception is the boolean **arguments of
> an `App`**: the visualiser draws them, but `vizExprToBoolExpr` compiles the whole
> application to a single BDD variable and does not descend, so the arguments are
> not atoms, carry no `impactByAtomId` entry, and binding one does nothing. That
> was true before this change and is still true; what changed is that they now keep
> a UUID instead of being rewritten to a bare decimal that a client could not tell
> apart from a `unique` binding key. `QueryPlanSpec`'s
> `atom identity, across shapes` group pins both the containment and its exception.

> **An atomId names a QUESTION, not a node.** It is a UUID5 over
> `"function | label | refs"`, so two occurrences of one condition — which a
> ladder in AND/OR normal form produces routinely, since reaching that form
> distributes OR over AND — carry the **same** `atomId` and different `unique`s.
> That is intended: binding the atomId binds every occurrence at once, which is
> what "the user answered that question" means. If you need to address a single
> occurrence, bind its `unique` (as a decimal string) instead.
>
> This was broken until 2026-08-03 (upstream `smucclaw/l4-ide#935`): the two
> surfaces minted ids in different namespaces, so a binding keyed by a ladder
> `atomId` returned `200` and silently did nothing. `QueryPlanSpec`'s
> `atom identity` group and the `ladder` cases in `test/IntegrationSpec.hs` pin
> both halves, including end-to-end that such a binding moves `determined`.

### MCP (Model Context Protocol)

The service exposes an [MCP](https://modelcontextprotocol.io/) JSON-RPC 2.0 endpoint that AI agents and LLM tool-use clients can call directly. MCP provides structured tool discovery and invocation without requiring browser integration.

| Method | Endpoint                    | Description                                                   |
| ------ | --------------------------- | ------------------------------------------------------------- |
| `GET`  | `/.well-known/mcp`          | MCP discovery endpoint (server info, capabilities, endpoints) |
| `GET`  | `/.well-known/mcp/manifest` | MCP manifest (legacy/alternative discovery)                   |
| `POST` | `/.mcp`                     | Org-wide MCP JSON-RPC endpoint (all deployments)              |
| `POST` | `/{id}/.mcp`                | Deployment-scoped MCP endpoint (short route)                  |
| `POST` | `/deployments/{id}/.mcp`    | Deployment-scoped MCP endpoint (canonical route)              |

The org-wide endpoint (`/.mcp`) exposes tools from all deployments. The scoped endpoints (`/{id}/.mcp`) restrict tool visibility to a single deployment.

#### Field Name Sanitization

L4 uses backtick identifiers with spaces (e.g., `` `function or purpose` ``), but JSON schema property names and URL path segments work better with hyphens. The service automatically sanitizes field names:

- **MCP and WebMCP schemas**: spaces and special characters are replaced with hyphens (e.g., `function or purpose` → `function-or-purpose`)
- **OpenAPI** (`/openapi.json`): uses sanitized names in URL paths; parameter schemas preserve original L4 names
- **Incoming arguments** (MCP tool calls, REST API evaluation, batch): both hyphenated and original spaced names are accepted and mapped back to the L4 originals
- **Function names in URLs**: both hyphenated (`/functions/check-person/evaluation`) and URL-encoded (`/functions/check%20person/evaluation`) forms are accepted

**Collision detection:** If two L4 field names would sanitize to the same hyphenated form (e.g., `` `foo bar` `` and `` `foo-bar` ``), compilation fails with a clear error message explaining the collision.

#### MCP Discovery

```bash
# Fetch the MCP discovery document (primary endpoint)
curl http://localhost:8080/.well-known/mcp
# {"name":"L4 Rules Engine","version":"1.0.0","protocol_version":"2025-03-26","capabilities":{"tools":{}},...}

# Fetch the MCP manifest (legacy/alternative)
curl http://localhost:8080/.well-known/mcp/manifest
# {"version":"2025-03-26","capabilities":{"tools":true},"endpoints":{"mcp":"/.mcp"}}
```

#### MCP JSON-RPC

Send standard JSON-RPC 2.0 requests to the `/.mcp` endpoint. The service supports `tools/list` (discover available tools) and `tools/call` (invoke a tool):

```bash
# List available tools
curl -X POST http://localhost:8080/.mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'

# Call a tool
curl -X POST http://localhost:8080/.mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"my-rules/compute_qualifies","arguments":{"walks":true,"eats":true,"drinks":true}}}'

# Scoped to a single deployment
curl -X POST http://localhost:8080/my-rules/.mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

#### MCP Schema Design

MCP tool schemas are optimized to minimize tokens in AI context windows:

- **Non-deontic functions**: parameters are listed directly at the top level of the tool's `inputSchema` (no wrapper). The AI calls the tool with `{"product": {...}}`.
- **Deontic functions**: parameters are wrapped in `arguments` alongside `startTime` and `events`. The AI calls with `{"arguments": {...}, "startTime": 0, "events": [...]}`.

This differs from the REST API which always uses `{"arguments": {...}}` for consistency.

### WebMCP (Browser AI Agent Integration)

Deployments are automatically [WebMCP](https://webmachinelearning.github.io/webmcp/)-compatible. Browser AI agents can discover and call deployed L4 rules as structured tools via a JavaScript snippet.

| Method | Endpoint                         | Description                                           |
| ------ | -------------------------------- | ----------------------------------------------------- |
| `GET`  | `/` (browser)                    | Deployment explorer — lists all deployments/functions |
| `GET`  | `/deployments?functions=full`    | All deployments with full function schemas            |
| `GET`  | `/deployments?scope=deploy-id`   | Filtered by deployment                                |
| `GET`  | `/openapi.json`                  | Org-wide OpenAPI 3.0 spec                             |
| `GET`  | `/deployments/{id}/openapi.json` | Per-deployment OpenAPI 3.0 spec                       |
| `GET`  | `/.webmcp/embed.js`              | Org-wide JS that registers WebMCP tools               |
| `GET`  | `/.well-known/webmcp`            | Discovery manifest listing all deployments            |

The `/deployments` endpoint serves cached metadata even for pending (lazy-loaded) deployments, so it works immediately after a restart without triggering compilation.

Query parameters for `GET /deployments` (and `GET /deployments/{id}`; `scope` is list-only):

- `?functions=simple` — name, description, returnType per function (default)
- `?functions=full` — include full parameter schemas in function details
- `?functions=none` — omit functions from metadata
- `?scope=id1,id2` — filter to specific deployments

The script registers tools based on the `data-tools` attribute. By default (`auto`), it registers per-rule tools if ≤ 20 rules, otherwise discovery tools (`search_rules`, `get_rule_schema`, `evaluate_rule`). File browsing tools (`list_files`, `read_file`, `search_identifier`, `search_text`) must be opted into explicitly via `file-tools` or `all`. Use comma-separated values to combine categories (e.g., `data-tools="rules,file-tools"`).

#### Visibility Headers

The proxy injects these headers to control what jl4-service includes in responses. All default to `true` when absent (local dev, direct access).

| Header                | Controls                                                                     | Proxy permission |
| --------------------- | ---------------------------------------------------------------------------- | ---------------- |
| `X-Include-Functions` | Functions in deployment metadata, function listing tools in MCP/WebMCP       | `l4:rules`       |
| `X-Include-Files`     | Files in deployment metadata, file browsing tools in MCP/WebMCP              | `l4:read`        |
| `X-Include-Evaluate`  | Evaluation/batch/query-plan/ladder paths in OpenAPI, evaluation tools in MCP | `l4:evaluate`    |

> **Note:** The legacy path `/webmcp.js` is redirected to `/.webmcp/embed.js` with a 301. Update existing embeds when convenient.

#### Embedding on Third-Party Websites

```html
<!-- All deployments, all functions -->
<script src="https://your-host/.webmcp/embed.js"></script>

<!-- Scoped to specific deployments -->
<script
  src="https://your-host/.webmcp/embed.js"
  data-scope="sell-scenario,safe-valuation"
></script>

<!-- With API key for cross-origin auth -->
<script
  src="https://your-host/.webmcp/embed.js"
  data-api-key="sk_live_xxx"
></script>
```

**Configuration attributes:**

- `data-scope` — Filter by deployment and/or function: `deploy-id` (one deployment), `id1,id2` (multiple), `id/function-name` (specific function), `*/function-name` (function across all deployments). Default: all.
- `data-tools` — Comma-separated list of tool categories: `rules` (one tool per rule), `rule-tools` (search/schema/evaluate), `file-tools` (list/read/search files), `auto` (default: `rules` if ≤10, otherwise `rule-tools`), `all` (everything). Example: `rules,file-tools`.
- `data-api-key` — API key for cloud-hosted deployments on [Legalese Cloud](https://legalese.cloud). Not needed for self-hosted instances.

## CLI Options

All options can also be set via environment variables. CLI arguments take precedence over environment variables.

| Option                      | Env Var                       | Description                                                                                                                                                                              | Default          |
| --------------------------- | ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| `--port`, `-p`              | `JL4_PORT`                    | HTTP port                                                                                                                                                                                | `8080`           |
| `--store-path`              | `JL4_STORE_PATH`              | Directory for persisting deployment bundles                                                                                                                                              | `/tmp/jl4-store` |
| `--server-name`, `-s`       | `JL4_SERVER_NAME`             | Server URL for OpenAPI metadata                                                                                                                                                          | -                |
| `--lazy-load`               | `JL4_LAZY_LOAD`               | Register deployments as pending on startup; compile on first evaluation/function access (optimistic 2s timeout, returns 202 if still compiling). File browsing always works immediately. | `false`          |
| `--debug`                   | `JL4_DEBUG`                   | Enable debug mode (verbose errors, debug-level logs)                                                                                                                                     | `false`          |
| `--max-zip-size`            | `JL4_MAX_ZIP_SIZE`            | Maximum zip upload size in bytes                                                                                                                                                         | `2097152` (2 MB) |
| `--max-file-count`          | `JL4_MAX_FILE_COUNT`          | Maximum number of files per zip upload                                                                                                                                                   | `5096`           |
| `--max-deployments`         | `JL4_MAX_DEPLOYMENTS`         | Maximum number of concurrent deployments                                                                                                                                                 | `1024`           |
| `--max-concurrent-requests` | `JL4_MAX_CONCURRENT_REQUESTS` | Maximum concurrent requests (503 when exceeded)                                                                                                                                          | `20`             |
| `--max-eval-memory-mb`      | `JL4_MAX_EVAL_MEMORY_MB`      | Per-evaluation allocation limit in MB                                                                                                                                                    | `256`            |
| `--eval-timeout`            | `JL4_EVAL_TIMEOUT`            | Evaluation timeout in seconds                                                                                                                                                            | `60`             |
| `--compile-timeout`         | `JL4_COMPILE_TIMEOUT`         | Compilation timeout in seconds                                                                                                                                                           | `60`             |
| `--max-ladder-nodes`        | `JL4_MAX_LADDER_NODES`        | Maximum ladder-diagram size, in IR nodes, that `query-plan` and `ladder` will build or serve (400 when exceeded)                                                                         | `10000`          |

Boolean env vars accept `1`, `true`, or `yes` (case-insensitive).

The service runs GHC's threaded runtime on every core of the machine (`-N`), and runs as many batch cases at once, across all batches, as there are cores.
To use fewer, pass runtime options on the command line, `jl4-service +RTS -N2 -RTS`, or in the environment, `GHCRTS=-N2`.

In a container, `-N` may count the host's cores rather than the container's CPU quota (`docker run --cpus`, a Kubernetes CPU limit); this is reasoned, not measured.
If it does, the service runs more batch cases at once than it has CPU for, and each case's clock counts the others' work again.
In a container with a CPU quota, set `+RTS -N<cpus> -RTS` or `GHCRTS=-N<cpus>` to the quota.
Each capability also costs memory: measured on 2026-10-02, the idle service used 106 MB at `-N10` and 59 MB at `-N1`, the same as on the non-threaded runtime the service used before.

## Logging

All output is structured JSON (one object per line) to stdout, suitable for log aggregators:

```json
{"time":"2026-02-21 19:25:34 UTC","level":"info","msg":"Starting jl4-service","port":8080,"debug":true,...}
{"time":"2026-02-21 19:25:35 UTC","level":"info","msg":"http_request","method":"GET","path":"/health","status":200,"duration_ms":0.42}
```

Log levels: `debug`, `info`, `warn`, `error`. Debug-level messages are suppressed unless `--debug` is set.

## Error Sanitization

By default, error responses return generic messages (e.g., `"Deployment compilation failed"`, `"Evaluation resource limit exceeded"`). When `--debug` is enabled, full error details are included in API responses and logs.

## Resource Limits

The service enforces several resource limits to protect against abuse:

- **Concurrency**: Returns `503 Service at capacity` when `--max-concurrent-requests` is exceeded. The `/health` endpoint is exempt.
- **Evaluation memory**: Each evaluation on the direct path is limited to `--max-eval-memory-mb` of GHC heap allocations via `setAllocationCounter`; on the wrapper path it is not yet (see [What the limits do not cover yet](#what-the-limits-do-not-cover-yet)). Returns `500` on limit exceeded; in a batch, the case that exceeds it carries `@error` and `"@limit": "memory"` instead, and the batch is still a `200` (see [When a case reaches a limit](#when-a-case-reaches-a-limit)). The counter belongs to the evaluation's own thread, so nothing else running at the same time counts against it.
- **Evaluation timeout**: Each evaluation is limited to `--eval-timeout` seconds. Returns `500` on timeout; in a batch, the case that times out carries `@error` and `"@limit": "time"` instead. The limit is on wall-clock time, so it counts any other work sharing the evaluation's core. Batch cases, counting every batch in flight, never run more at once than there are cores, so batch cases do not slow each other down by sharing a core. A batch case's clock still counts the garbage collector's pauses, which every running evaluation shares, and any of the work that takes no slot (single evaluations, MCP calls, compiles, query plans, ladder and state-graph rendering, response encoding) that is sharing its core at the time.
- **Compilation timeout**: Bundle compilation is limited to `--compile-timeout` seconds.
- **Zip size**: Upload rejected with `400` if larger than `--max-zip-size`.
- **File count**: Upload rejected with `400` if zip contains more than `--max-file-count` entries.
- **Deployment count**: New deployment rejected with `400` if `--max-deployments` is reached.
- **Ladder size**: `query-plan` and `ladder` return `400` if the decision's ladder diagram exceeds `--max-ladder-nodes`. This bounds a _response_, not a runtime, which is why no timeout covers it: a ladder is drawn in AND/OR normal form, and reaching that form distributes OR over AND, so `(a AND b) OR (c AND d) OR …` over 2n variables becomes 2^n clauses. Eight variables serialize to 12 KB, sixteen to 366 KB, thirty-two to tens of megabytes. The default is far above any diagram a person could read and far below the pathological cases; raise it if a legitimate model meets it. The check short-circuits, so an oversized decision is refused in milliseconds rather than measured at length.

### What the limits do not cover yet

Three gaps, each measured on 2026-10-03, and none fixed yet:

- **The memory limit does not reach the wrapper path.** A request that goes through the generated wrapper (see [Missing and uncertain inputs](#missing-and-uncertain-inputs)), such as one with a `null` inside a record input, is stopped by the time limit only. Four such batch cases under a 64 MB limit came back as `"time"` after 2 s, where the same cases on the direct path came back as `"memory"` at once.
- **Arithmetic the evaluator leaves unfinished is finished while the response is encoded, outside both limits.** A number built up lazily is only computed when the answer is written out, so a 1-second limit returned an 8 MB number after 1.7 s, and the review that found this saw a 64 MB one after 16.9 s. The worst-case time under [What a batch can cost](#what-a-batch-can-cost) leaves this out.
- **A single or MCP evaluation that hits a limit inside an imported value spoils that connection.** Later calls on the same kept-alive connection answer `Infinite loop detected while trying to evaluate` instead of evaluating; a new connection evaluates again. Batch cases are not affected: the same batch case after such a call came back with `"@limit": "time"`.

## Persistence

Deployments are stored on disk at `{store-path}/{deployment-id}/`:

```
{store-path}/
  my-rules/
    sources/
      main.l4
      helper.l4
    metadata.json
  other-deploy/
    sources/
      rules.l4
    metadata.json
```

On startup, the service scans the store directory and recompiles all deployments. With `--lazy-load`, deployments are registered as pending and compiled on first evaluation or function access (with a 2-second optimistic timeout). File browsing (`list_files`, `read_file`, `search_identifier`, `search_text`) reads directly from disk and works immediately regardless of compilation state.

## Testing

```bash
# Run jl4-service tests
cabal test jl4-service-test

# Run with pattern filter
cabal test jl4-service-test --test-options='--match "BundleStore"'
```

Test coverage:

- **ApiSpec** -- FnLiteral JSON parsing, query parameter coercion
- **BooleanDecisionQuerySpec** -- Boolean formula support/restriction
- **BundleStoreSpec** -- Filesystem persistence round-trips
- **CodeGenSpec** -- Input field name collision avoidance
- **DecisionQueryCacheKeySpec** -- Cache key determinism
- **IntegrationSpec** -- Full deployment lifecycle, evaluation, batch, control plane HTTP, field name remapping
- **LoggingSpec** -- Log lines stay whole when many threads log at once
- **SanitizationSpec** -- Property name sanitization, reverse mapping, collision detection
- **SerialisationSpec** -- CBOR serialisation round-trips and cache rebuild
- **SchemaSpec** -- QuickCheck property tests for API type serialization

## Architecture

```
jl4-service/
  app/Main.hs              -- Entry point
  src/
    Application.hs          -- WAI app wiring, startup, middleware (CORS, concurrency, logging)
    Logging.hs              -- Structured JSON logger
    Options.hs              -- CLI argument parsing with env var defaults
    Types.hs                -- Core domain types (DeploymentId, AppEnv, health, batch types)
    BundleStore.hs          -- Filesystem persistence (save/load/list/delete)
    Compiler.hs             -- Bundle compilation (typecheck + export discovery)
    Compatibility.hs        -- Recursive backwards-compatibility diff (PUT gate)
    ControlPlane.hs         -- POST/GET/PUT/DELETE /deployments + async deploy/update jobs
    DataPlane.hs            -- /deployments/{id}/functions/... evaluation handlers + short routes
    DeploymentLoader.hs     -- Shared compilation logic (eager startup, lazy compile-on-access)
    ExplorerPage.hs         -- Landing page HTML (deployment explorer, API docs)
    McpServer.hs            -- MCP JSON-RPC 2.0 handler (tools/list, tools/call)
    Schema.hs               -- OpenAPI spec generation
    Shared.hs               -- Shared utilities (scope matching, metadata, sanitization, JSON errors)
    WebMCPPage.hs           -- Org-wide WebMCP JavaScript (tool registration, sanitization)
    Backend/
      Api.hs                -- FnLiteral, ResponseWithReason, RunFunction
      Jl4.hs                -- L4 typechecking and evaluation via Shake rules
      FunctionSchema.hs     -- Parameter schema extraction from L4 types
      DecisionQueryPlan.hs  -- Query planning for interactive elicitation
      CodeGen.hs            -- Evaluation wrapper code generation
      BooleanDecisionQuery.hs  -- Boolean formula analysis (BDD-based)
      MaybeLift.hs          -- Deep Maybe lifting for partial inputs
      DirectiveFilter.hs    -- Directive-based function filtering
  test/
    Spec.hs                 -- hspec-discover entry point
    TestData.hs             -- Shared L4 source fixtures
    ...Spec.hs              -- Test modules
```

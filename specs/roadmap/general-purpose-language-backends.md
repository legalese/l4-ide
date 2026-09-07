# General-purpose language backends — TypeScript/JavaScript and Go

_Status: **backlog. Not started — no spec, no code, no ruling, no branch.** Written 2026-09-07 at
Meng's request. Nothing described here is implemented. Every claim about the current tree is dated
and carries a pointer; verify at the pointer before relying on one. The `specs/` workflow
(`specs/README.md`) puts a new idea in `proposals/` before it becomes a `todo/` spec — this note is
one step earlier than that: it is the record that we want the thing, and the list of what has to be
decided before anyone writes the proposal._

**The ask.** Meng, 2026-09-07: "I believe we have exporters to a number of rules languages already,
and next we want to export to more mainstream languages like javascript/typescript and go."

**The driver, in Meng's words the same day** — and it is the driver, not a nice-to-have, so it is
quoted rather than paraphrased:

> we have a jl4-service deployment that includes a rules engine, but some customer partners may
> want to run computations at scale on prem, so it would be nice to be able to export l4 decision
> rules to more familiar operational runtimes that existing enterprise codebases can talk to via
> library rather than via API

Everything below follows from that sentence. This is not primarily a language-coverage project; it
is a **deployment-model** project. The unit of delivery is a library the customer vendors into
their own build, not a service they call.

---

## 1. The problem is the deployment model, not the absence of an emitter

Three things already let an enterprise program get an answer out of an L4 model. Each fails the
"library, on prem, at scale" test in its own way.

| what                           | verified                                                                                                          | why it does not answer the ask                                                                                                                             |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `jl4-service` over HTTP        | `jl4-service/src/{DataPlane,Schema,OpenApiDoc}.hs`, parameter schemas from `L4.FunctionSchema` **[E 2026-09-07]** | This is the thing being displaced. Our binary must be deployed and operated; every decision is a network round trip; the facts leave the caller's process. |
| `jl4-wasm` / `jl4-mlir` → WASM | `jl4-wasm/`, `jl4-mlir/` parity ledger **[E 2026-09-07]**                                                         | In-process, so it passes the deployment test — but it ships the **evaluator**, and the artifact is a binary that no reviewer reads and no diff explains.   |
| `ts-shared/*`                  | `viz-expr`, `ladder-core`, `jl4-client-rpc` **[E 2026-09-07]**                                                    | TypeScript consumes L4 IR **as data**, to draw pictures. It does not evaluate rules at all.                                                                |

What is missing is a `.ts` or `.go` file the customer's team vendors into their repository, reads in
code review, scans with their own tooling, diffs across contract amendments, and calls in-process —
**with no L4 runtime present anywhere in their stack**.

### 1.1 Four constraints the driver imposes

These are acceptance criteria, not aspirations. A design that misses one has missed the ask.

1. **In-process call, not RPC.** "At scale" and "per-decision HTTP" are incompatible. A batch that
   scores millions of rows needs a function call, and the difference is orders of magnitude — not a
   tuning problem.
2. **No egress.** On-prem means the facts — claims, salaries, customer records — never cross the
   customer's boundary. This is frequently the _binding_ constraint in regulated sectors, and it is
   not negotiable by making the service faster.
3. **No operational dependency on us.** A library is a build-time dependency the customer already
   knows how to manage. A service is something they must deploy, monitor, patch, and page someone
   about at 3am. That difference is most of the adoption gap.
4. **Reviewable, vendorable output.** Generated code that lands in an enterprise repo must pass
   their linter, their SAST scan, and a human reviewer who has never heard of L4. This is a real
   bar and it constrains Q5 (idiom) and Q1 (dependencies) directly.

### 1.2 The JVM case may already be answered — check before building for it

"Existing enterprise codebases" points at Java and C# at least as strongly as at Go. But for JVM
shops there is already a shipped path that satisfies all four constraints above without a new
backend: **`l4 export --to=dmn` plus an embedded DMN engine**. We run exactly that arrangement in
tree today as a validation harness — `etc/kie/pom.xml`, `etc/kie-dmn-check/pom.xml`,
`etc/camunda-dmn-check/pom.xml` **[E 2026-09-07]** — and a KIE or Camunda engine embedded in a Java
application is an in-process library evaluating our rules, on prem, with no call to us.

Two consequences:

- **Do not start with Java.** Establish first whether DMN-plus-engine already meets a JVM partner's
  need. If it does, the honest answer to that partner is a `doc/` page, not a compiler.
- **This is also the sharpest argument for the TS and Go targets specifically.** Neither ecosystem
  has a comparable, credible embedded DMN engine that we would ask a partner to adopt — so for
  Node/TypeScript and Go shops there is currently _no_ library-shaped answer at all. That gap, not
  language coverage in the abstract, is what this work closes.

  _Caveat, flagged rather than asserted:_ the claim that no adequate JS or Go DMN engine exists is
  the belief that motivates the whole project, and it has **not** been surveyed. Survey it first —
  it is a day of work and it could retire or reshape this entire item.

## 2. What it buys beyond the immediate ask

- **It is the first execution target aimed at people who will never learn L4.** Every execution
  backend to date projects into an ecosystem that already believes in law-as-code — OpenFisca and
  Catala have rules-language users on the far side. TypeScript and Go do not; the reader is an
  application developer with a deadline who wants a function to call.
- **It closes the gap between the model and the system that acts on it.** The payments-fintech
  engagement was this shape already — fee tables from commercial agreements, served to operational
  systems. The insurance leak-detection story only pays out when the formalised model and the code
  that computes the payout are the _same artifact_, rather than two artifacts that agree by hope.
- **It is a sharp probe on the exportable core.** `BACKEND-PORTFOLIO-SPEC.md` §5 (P3, still
  PROPOSED) wants one shared definition of the export fragment. Two strict, general-purpose,
  non-rational languages will stress that boundary in ways the rules languages did not — an
  argument for building one of them **before** `L4.Export.Fragment` is frozen, not after.

## 3. Open core: the transpiler is not the moat, the reference implementation is

**Meng, 2026-09-07**, quoted rather than paraphrased because it is a position on company strategy
and the wording carries the reasoning:

> from a business-modelling perspective we should probably tier these exporter runtimes so they're
> tied to a commercial agreement, but we can include the simple proof-of-concept runtimes in the
> open l4-ide codebase because, TBH, getting a coding assistant to do the xpiler is not something
> that only we can do; we might as well do it and be the reference for that sort of code

Read as **a position, not yet a ruling** — see §7 for where it has to land to become one:

- **Proof-of-concept runtimes ship here, in the open.** This repo is Apache-2.0
  (`LICENSE`, © Singapore Management University) **[E 2026-09-07]**.
- **Production, at-scale runtimes are tiered** and tied to a commercial agreement.
- **The stated reason is honest about the moat.** An L4→TypeScript transpiler is within reach of a
  competent team with a coding assistant. Secrecy would buy nothing and would cost the reference
  position — being the implementation that everyone else's is measured against.

Three observations on the reasoning, offered as support and as caution:

1. **It puts the defensibility where it actually is** — in L4 itself, the corpus, the verification
   layer, and the reference position. An open PoC also recruits rather than repels the ecosystem
   the platform thesis needs: third-party emitters become _comparable to ours_ instead of
   _instead of ours_.
2. **The tiering line falls near the demand line already identified.**
   `specs/todo/PRODUCT-STRATEGY-2025-01.md:823` names where demand is real — "per-claim insurance
   payout logic, regulator compliance throughput, high-frequency contract operations"
   **[E 2026-09-07]**. Every one of those is an at-scale, on-prem, library-shaped workload, i.e.
   exactly the driver in the header. Tiering on scale therefore charges roughly where the value is,
   which is the easiest kind of pricing to defend.
3. **Open-core language already exists in the tree, but only for the corpus.**
   `PRODUCT-STRATEGY-2025-01.md:823` ("the open-core corpus is the mechanism that converts bespoke
   engagements into a compounding, recurring-revenue library") and
   `specs/todo/single-instruction-demo/SPEC.md:653` ("the open-core → freemium-enrichment pathway
   stays open by construction") **[E 2026-09-07]**. Extending it from _encodings_ to _runtimes_ is
   a new step, and **neither document currently owns runtime tiering**.

**A tension this note cannot resolve, surfaced 2026-09-07.** The pitch's revenue model prices the
**runtime** first — "Every encoding executes on our decision service. Priced per query"
(`legalese-l4-pitch`, `.claude/skills/l4-pitch/PITCH.md:381` on `origin/main` @ `db238b9`,
**[E 2026-09-07]**; note it is not in that repo's local checkout, which is four commits behind).
The exporter programme exists to let a partner _not_ do that: a library running on the customer's
own tin has no per-query meter on it. This is not an argument against building it — the demand is
real, and if we do not serve it someone else will. It is an argument that **Q9 is carrying more
weight than it looks**: it decides not merely what is free and what is paid, but where the price
goes once the meter is gone. Q8's regeneration story is one candidate answer — contracts and
statutes change, and whoever ships the update owns the relationship whether or not they own the
runtime.

## 4. Ten questions to answer before anyone writes a proposal

**Q1 — Numbers.** L4's numeric literal is a `Rational`: `jl4-core/src/L4/Syntax.hs:428`
(`NumericLit Anno Rational`) and `jl4-core/src/L4/Evaluate/ValueLazy.hs:52` (`ValNumber Rational`)
**[E 2026-09-07]**. `BACKEND-PORTFOLIO-SPEC.md` §2.1 records Catala as the only backend whose
numeric model matches this, "which is why its round-trip claims can demand equality rather than
tolerance" **[U — borrowed from that row, not re-derived here]**.

The two targets are **not symmetric**, and "at scale" adds a third axis to what was already a
two-way trade:

- **Go** has `math/big.Rat` in the standard library — exactness at no dependency cost, but at an
  ergonomic cost (the emitted code reads in `Rat` method calls, not `+` and `*`) and a throughput
  cost (heap allocation per arithmetic operation, in the hot loop of a batch scoring millions of
  rows).
- **TypeScript/JavaScript** has one number type (IEEE-754 double) and `BigInt` for integers, but no
  rational. Exactness means a library dependency inside generated code — which collides with
  constraint 1.1(4), since a vendored file that drags in a transitive dependency is a harder sell
  than one that does not.

There is a lossy precedent in the tree, and it should be read as a warning rather than a licence:
`jl4-core/src/L4/Evaluate/ValueLazyJSON.hs:52-54` serialises a non-integral rational as a `Double`
**[E 2026-09-07]**. Note that money is the motivating use case on both sides — the fee tables and
the payout formula — so this is the question most likely to produce a wrong number in production.
Whatever we choose, choose it deliberately and state it on the `doc/` page, per CLAUDE.md §6's rule
about publishing where numbers stop being exact.

**Q2 — Which layers.** Constitutive core only, or the regulative (deontic) layer too?
`BACKEND-PORTFOLIO-SPEC.md` §2.2 records BPMN as the one shipped consumer of the regulative layer
**[U — borrowed from that row]**. Note that the driver says "**decision** rules", which points at
the constitutive core and lets the first cut be honestly narrow. Emitting decision functions and
emitting an obligation state machine with deadlines, breaches and reparations are different
projects with different budgets. Suggested shape: constitutive first, regulative named explicitly
as a later phase rather than quietly dropped — the transpiler programme's own history is that
unnamed scope becomes invisible scope.

**Q3 — Strictness.** L4 evaluates lazily (`jl4-core/src/L4/EvaluateLazy/`). JavaScript and Go are
strict. Guards, `CONSIDER` arms and unevaluated branches change both semantics and cost under
strict evaluation — and under "at scale", cost is a requirement, not a footnote. Thunk everything
(faithful, ugly, slow), restrict to the total fragment `BACKEND-PORTFOLIO-SPEC.md` §5 already names (clean and fast, narrower),
or emit strictly and document the delta (fast, and a comfortable place for a silent wrong answer to
live)?

**Q4 — Trace.** The programme's value proposition is the _explained_ answer with citations back to
source rules — what makes it audit-grade, and what makes it useful as a guardrailed tool call for
an LLM. A plain emitted function returns a value and nothing else. The scale requirement argues
that tracing must be **opt-in per call** rather than always-on: the batch path pays nothing, the
"why did this claim get denied" path pays for the trace. Options: a second trace-returning variant
of each entry point, an optional trace-sink parameter, or no trace in v1 with the gap stated on the
page. OpenFisca and Catala each had to answer some version of this; read their lowerings before
re-deriving.

**Q5 — Idiom versus fidelity.** The point of emitting TypeScript is that a TypeScript developer
will _read_ it — and constraint 1.1(4) makes that a hard requirement, since the file has to survive
their review and their linter. That argues for idiomatic output (discriminated unions, `switch`,
early returns) over faithful transliteration of the AST. But every idiomatic rewrite is a place
where semantics can slip unnoticed, precisely because the output looks like code a person wrote.
The oracle direction and claim ladder for settling this are owned by `BACKEND-PORTFOLIO-SPEC.md`
§4 — cite them, do not restate them; that section exists because they had already been
independently restated in four documents.

**Q6 — Types, and Go's sum-type problem.** TypeScript gets L4's records and
`DECLARE T IS ONE OF A / B` nearly for free via structural types and discriminated unions;
`specs/todo/IMPLICIT-PROPS-DESIGN.md:137` already reasons about L4 records in that structural
spirit **[E 2026-09-07]**. Go has no sum type, and every encoding of one (sealed interface, tagged
struct, generated visitor) is uglier and leaks. This is the hardest design question in the Go half
and should be settled once, up front, rather than per-construct.

**Q7 — The name. Do not call the verb `l4 go`.** Two live collisions, both verified 2026-09-07:
`etc/go/go.sh` is the single-instruction demo pipeline, and "⟨body of law⟩: go" is a user-facing
instruction handled by the `running-the-l4-pipeline` skill. A `l4 go` verb would collide with both.

The CLI also carries two competing conventions today, and this backend must pick one rather than
invent a third — verified in `jl4/app/Main.hs:76-130` **[E 2026-09-07]**:

- **per-target verb**: `l4 openfisca`, `l4 catala`, `l4 blawx`, `l4 docassemble`
- **`l4 export --to=X`**: `dmn`, `dmn-md`, `bpmn` (`jl4/app/L4/Cli/Export.hs:7-10`)

Workable answers: `l4 export --to=ts|go`, or `l4 typescript` / `l4 golang`. Not `l4 go`.

**Q8 — Distribution and regeneration.** This question exists only because of the library framing,
and it is the one with no in-tree precedent at all, since every existing backend emits an artifact
we hand over once.

- Is the deliverable a **vendored generated file** committed to the customer's repo, or a
  **published package** (npm, Go module) they depend on by version?
- When the contract is amended, how does the customer take the new rules — regenerate and re-review
  the diff, or bump a version? The first makes the change auditable, which is the whole point; the
  second is what their dependency tooling expects.
- Does the generated file carry provenance — source `.l4` hash, L4 version, generation date — so
  that a reviewer two years later can tell what it came from and whether it is stale?
- Is generated code checked for drift in **their** CI, or **ours**? A model that has silently
  diverged from the contract is worse than no model, and this is the failure mode the whole
  approach is meant to prevent.

**Q9 — Where exactly is the proof-of-concept/commercial line, and what must never be on it?**
This question exists because of §3, and it has to be answered **before the first emitter ships**:
withholding a capability is easy, withdrawing one already given is not.

One constraint is worth proposing as a hard rule rather than an option: **correctness must not be
the axis.** A knowingly-less-correct free tier that computes money is a liability, and it destroys
the reference-implementation claim in the same stroke — the entire pitch of §2 is that the model
and the production code are _the same artifact_. If the open PoC can return a different answer from
the paid runtime, we have reintroduced the two-artifacts-agreeing-by-hope problem we exist to
remove, and we have done it inside our own product.

Candidate axes that do not have that defect, roughly in order of how naturally they map to what a
commercial agreement is for:

- **support, warranty, indemnity, certified test suites** — the things customers are actually
  buying when they sign
- **scale and performance**: batching, parallelism, incremental re-evaluation — the work Q1 and Q3
  make expensive, and the axis §3's observation 2 says the demand already sits on
- **the trace and audit surface** (Q4): the explained, citation-carrying answer is the audit-grade
  product; a bare value is not
- **regeneration, drift detection and CI integration** (Q8)
- **the regulative layer** (Q2): obligations, deadlines, breach and reparation
- **fragment breadth**: the PoC covers `BACKEND-PORTFOLIO-SPEC.md` §5's exportable core, the
  commercial runtime covers the extensions

**Q10 — What licence does the _generated code_ carry, and who owns it?** Routinely confused with
the generator's licence, and distinct from it. A customer will ask who owns the `.go` file our tool
wrote from their contract _before_ they agree to vendor it into their repository — so this is a
blocker for adoption, not a legal footnote. Note that this repo's copyright sits with Singapore
Management University (`LICENSE`) **[E 2026-09-07]**, so the answer is not ours alone to give; get
the question in front of whoever owns that relationship early rather than at contract time.

## 5. Sequencing — a suggestion, not a ruling

0. **Survey first** (§1.2's caveat): confirm there is no adequate embedded DMN engine for
   Node/TypeScript or Go. A day of work that could retire or reshape the item.
1. **TypeScript.** The surface already exists with a review audience next door (`ts-shared/`, the
   web IDE, `jl4-client-rpc`), so an emitted module has an immediate consumer instead of a
   hypothetical one — and it does not fight Q6.
2. **Go.** Harder design (Q6), better numerics (Q1), and it benefits from a fragment boundary
   settled by a target that did not fight it.

Q9 (the open/commercial line) gates step 1, not step 2: the first emitter to ship in the open sets
the precedent for every one after it.

Java stays off the list until §1.2 is answered.

## 6. Left open here, deliberately

- **Family placement.** This note assumes both targets join the **execution** family
  (`BACKEND-PORTFOLIO-SPEC.md` §1.1, "run the law"). There is an argument that "emit a library into
  a host codebase" is a seventh family rather than a third execution target, since it is
  distinguished by deployment model rather than by what it consumes. P2 (the taxonomy) is owned by
  the portfolio document, and a backlog note does not get to re-rule it — raise it there.
- **Java and C#.** Named by the driver's "existing enterprise codebases" but held pending §1.2.
- **Python.** Not asked for, and adjacent in an awkward way: OpenFisca is already Python, so "emit
  plain Python" both partly exists and mostly does not.
- **Round-trip / import.** Every question above is about export. Whether a Go or TypeScript module
  could ever be read back into L4 is not considered here.

## 7. Where the rulings go when they are made

Per CLAUDE.md §4, a decision is recorded in its owning document in the same PR or it is not decided:

1. Per-target rulings go in `specs/todo/TYPESCRIPT-EXPORT-SPEC.md` / `GO-EXPORT-SPEC.md`, following
   the `X-EXPORT-SPEC` house style already set by DMN, Catala and Blawx.
2. **The tiering position in §3 is not recorded by living here.** This is a roadmap note; it does
   not get to set company policy. The two nearest owners, neither of which currently covers
   runtimes: `specs/todo/PROVABLE-MARKETPLACE-SPEC.md` owns the commercial access model and
   metering (§3, §2.5), and `specs/todo/PRODUCT-STRATEGY-2025-01.md` owns the open-core framing
   (the paragraph at line 823) **[E 2026-09-07]**. Whichever takes it, the ruling and the first emitter
   should land in the same PR — a shipped open PoC with the line still unwritten _is_ the ruling,
   made by default.
3. `specs/proposals/BACKEND-PORTFOLIO-SPEC.md` §2.1's census rows get updated **in the same PR**
   that changes their state — the census is dated pointers, and its own header records that the
   rows once lied for a week because that instruction was written but not obeyed.
4. Cross-backend invariants stay in portfolio §4 and are cited, never restated.
5. Per CLAUDE.md §6, a page under `doc/` — written for a developer who has never read a spec —
   lands before the work is closed out, with the limits (Q1, Q3, Q4), the regeneration story (Q8),
   and the licence of the generated code (Q10) stated on it. Nothing mechanical will catch the omission; the transpiler programme shipped
   five backends before anyone noticed that none of them appeared in the manual.

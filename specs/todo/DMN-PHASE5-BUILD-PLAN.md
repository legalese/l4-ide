# DMN Phase 5 — build plan: BKM emission, `knowledgeRequirement`, the three refusals, flavor split

> **Status: DISCHARGED 2026-08-01 — the build this plan ordered has landed** (branch
> `mengwong/dmn-phase5-bkm`, off `unstable` at `4d83ab73`; six commits, W1–W8). Retained because
> the probe matrix in §1 is the measurement of record for the 46 wired engine legs, and because
> `bkmProbeMatrix` in `jl4/tests-cli/Main.hs` cites it. Every ruling it discusses is recorded in
> the spec's own sections (§5.2, §6.1–§6.4, §7, §13.5–§13.6, §15.7), which win over this file.
>
> **Corrections measured at the build, against the tree at `4d83ab73`** (this file was measured
> at `05e46d9a`, pre-Phase-4-merge, and several of its claims had gone stale by landing time):
>
> - Every `Lower.hs`/`Main.hs`/`DmnExport.hs` line number cited below moved; the build brief's
>   correction table was used instead of the cites here. Do not navigate by this file's numbers.
> - **§11's baseline is dead twice over.** At `4d83ab73` the corpus read **95 blocking / 21
>   lossy / 54 advisory** (170 notes), not 112/44/21; all 8 `D-NONFEEL*` notes were already gone
>   (the tier-2 call sites lived inside `D-LITERALEXPR` literal bodies), so the "112 → 104"
>   prediction had nothing left to retire. The landed movement is recorded in spec §15.7's dated
>   Phase 5 row: **95 → 32 Blocking**, via BKM emission AND the fragment-keyed `D-LITERALEXPR`
>   severity (spec §7), with KIE's residual compile errors 37 → 17 (all deliberate refusals).
> - P5.0a–c landed as the PR's first commit (not a separate Phase 0 PR); §6.4.4 records the
>   P5.0b dependency.
> - The §6.2 body-environment question this plan left open ("a BKM body may read…") was MEASURED
>   at the build and the engines DISAGREE (KIE refuses an unshadowed inputData read at compile;
>   Camunda answers), so bodies are λ-LIFTED — spec §6.2's 2026-08-01 note is the record.
> - P5.8's `expectService` was ruled NOT built; the limitation is recorded (spec §13.6).
>
> Original header follows.

> **Status: build plan, not a spec — rulings live in `DMN-EXPORT-PROGRAM-MODEL-SPEC.md`. The
> Phase 5 code build is blocked on Phase 4 (branch `mengwong/bkm-phase4-unlift`). Probe
> measurements dated 2026-07-31.**
>
> Nothing in this file decides anything. Where it disagrees with
> `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` on a **ruling**, the spec wins and this file is wrong; where
> it disagrees with the **tree**, the tree wins and the spec has been corrected in the same commit
> that added this file. Every claim about the tree was checked against `05e46d9a` (branch
> `mengwong/bkm-phase5`).

---

## 0. What exists as of this commit

Read-only pass; no exporter code was written or edited. What this commit lands is:

- this plan;
- **23 hand-written engine probe fixtures** under `jl4/tests-cli/fixtures/dmn-bkm-probe/`, each a
  `.dmn` plus a `.cases.json`, executed against **KIE 8.44.0.Final (JDK 17)** and **zeebe-dmn
  8.7.6** on 2026-07-31 via `etc/kie-dmn-check/run.sh` and `etc/camunda-dmn-check/run.sh`;
- **10 cycle-shape `.l4` fixtures** under `jl4/examples/dmn/not-ok/` (`cycle-p1`…`cycle-p9`),
  which are the corpus for the `D-RECURSIVE`/`D-CYCLE` detector of P5.5;
- dated measurement notes in the sections of `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` that own the six
  claims the probes contradicted or sharpened (§2.3.2, §5.2, §6.1, §6.2, §6.3, §13.3, §13.4,
  §13.5, §13.7, §13.8).

"PASS" below means a `VERDICT` banner with no `<<< FAILED`.

---

## 1. Probe results, in full

These are the input to the plan, so they come first.

### Group A — BKM shape

| Fixture                | KIE 8.44   | zeebe-dmn 8.7.6 | Finding                                                                                                                                                                 |
| ---------------------- | ---------- | --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bkm-multiparam`       | PASS 8/8   | PASS 8/8        | Positional invocation at arity 3 is portable. Validator and build clean.                                                                                                |
| `bkm-named-args`       | PASS 6/6   | PASS 6/6        | **The load-bearing unknown resolves.** zeebe-dmn accepts **named** arguments to a BKM in scrambled order, so §2.3.1's named-parameter rule lifts from services to BKMs. |
| `bkm-table-multiparam` | PASS 12/12 | PASS 12/12      | A multi-parameter `decisionTable` as `encapsulatedLogic` executes on both — §13.3 row 4 moves QUOTED → EXECUTED at arity 2.                                             |

In passing: a single `<output>` **carrying** a `typeRef` inside a BKM decision table draws KIE
`WARN [ILLEGAL_USE_OF_TYPEREF]` while changing no value on either engine. Removed from the fixture
and recorded in its header.

### Group B — BKM × hydration

| Fixture                  | KIE      | CAM      | Finding                                                                                                                                                                                                                                                                                    |
| ------------------------ | -------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `bkm-in-context`         | PASS 6/6 | PASS 6/6 | **Highest-consequence unknown resolves favourably.** A boxed-context `literalExpression` entry MAY invoke a BKM declared by a `knowledgeRequirement` on the **enclosing decision**, on both engines. Hydration (§4.4) and Phase 5 compose; no un-hydration or inlining fallback is needed. |
| `bkm-in-context-sibling` | PASS 6/6 | PASS 6/6 | A BKM call inside a hydrator may take an **earlier sibling entry** as argument, including one itself computed by an earlier BKM call. FEEL `string()` and string `+` also agree.                                                                                                           |
| `bkm-null`               | PASS 9/9 | PASS 9/9 | FEEL `null` survives a BKM return; guarding a held null and guarding the call inline both work. **R8-d′ extends to tier 2 unchanged.**                                                                                                                                                     |

### Group C — the `knowledgeRequirement` graph

| Fixture             | KIE      | CAM      | Finding                                                                                                                                                                                                                                                                                                       |
| ------------------- | -------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bkm-chain`         | PASS 2/2 | PASS 2/2 | A BKM→BKM edge on the **calling BKM** works; the caller decision needs only its own direct edge.                                                                                                                                                                                                              |
| `bkm-chain-flat`    | FAIL     | FAIL     | KIE `ERROR [ERR_COMPILING_FEEL]`: _"Error compiling FEEL expression 'inner(v) \* 10' for name 'outer' on node 'outer': Unknown variable 'inner'"_, at validator **and** build. Camunda parses and returns **null** for every case with **no message**.                                                        |
| `bkm-chain-nokr`    | FAIL     | FAIL     | Diagnostics **byte-identical** to `bkm-chain-flat` on both engines (so that fixture is this one with a decoration). KIE loud at compile time; **Camunda degrades to null with no diagnostic.**                                                                                                                |
| `bkm-name-mismatch` | FAIL     | PASS 2/2 | KIE: validator `ERROR [VARIABLE_NAME_MISMATCH]`, **build clean**, then runtime _"FEEL ERROR while evaluating literal expression 'f(n)': Not an invocable: 'null'"_, decision FAILED. **Camunda is silent and answers correctly** — it binds the invocable by BKM `@name` and never consults `variable/@name`. |

**The transitive-closure hypothesis is refuted on both engines** (`bkm-chain` passes where
`bkm-chain-flat` fails): the engines consume the **direct-call edge set**, not its transitive
closure. That is the cleanest possible outcome — §6.3.9's SCC then runs over exactly the graph the
engines consume.

### Group D — `decisionService`

| Fixture                | KIE              | CAM      | Finding                                                                                                                                                                                                                                                                                                                                                |
| ---------------------- | ---------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `svc-grouping`         | PASS 4/4         | PASS 4/4 | KIE `decisionSvcs [bundle]`; `SVC bundle -> {n=4, total=9}` — note the returned context includes the service's **inputs** as well as its output decision.                                                                                                                                                                                              |
| `svc-invoked`          | PASS 6/6         | FAIL     | Camunda fails at parse, whole file: `class …DecisionServiceImpl cannot be cast to class …BusinessKnowledgeModel`. **§13.4 reproduced exactly.**                                                                                                                                                                                                        |
| `svc-invoked-minus-kr` | FAIL             | FAIL     | KIE `ERROR [ERR_COMPILING_FEEL]` … `'bundle(n: n + 100)'` … `Unknown variable 'bundle'`. Camunda parses; `step` and `total` correct, `via_bundle` **null**, no message.                                                                                                                                                                                |
| `svc-plus-bkm`         | PASS 6/6         | PASS 6/6 | KIE's `evaluateDecisionService` resolves both BKMs from inside the service (`SVC pricing -> {n=200, charge=5.00}`). **The shape every Phase 5 corpus file will have is portable.**                                                                                                                                                                     |
| `svc-no-output`        | FAIL             | PASS 2/2 | Xerces **valid** (as `DMN13.xsd:516` `minOccurs="0"` predicts). KIE validator `ERROR [REQ_NOT_FOUND]`, **build clean**, then `evaluateDecisionService` throws `IllegalArgumentException: … 'decisionIds' cannot be empty`. Camunda **completely silent**.                                                                                              |
| `svc-cycle`            | FAIL (10 errors) | FAIL     | Camunda fails at parse (the `svc-invoked` `ClassCastException`). KIE: Xerces valid, **validator clean**, **build clean**, all three decisions SUCCEEDED-but-null — **and the runtime message channel does fire**: _"Error evaluating Decision node 'a_out': null"_ plus per-service _"Errors occured while evaluating Decision Service node 'alpha'."_ |

### Group E — name collisions

| Fixture                        | KIE      | CAM      | Finding                                                                                                                                                                                                                                                                                                                                                      |
| ------------------------------ | -------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `collide-param-input`          | PASS 6/6 | PASS 6/6 | A `formalParameter` **shadows** a same-named `inputData` on both engines. `Lower.hs:3714` stands — this is **adding a scope**, not widening scope 1.                                                                                                                                                                                                         |
| `collide-param-param`          | PASS 6/6 | PASS 6/6 | Each `encapsulatedLogic` is its own parameter scope, including for a BKM that calls two others reusing its own parameter spellings.                                                                                                                                                                                                                          |
| `collide-param-decision`       | FAIL     | FAIL     | Q1 _"may a BKM body read a decision variable"_: **no** on both — KIE whole-model `ERROR [ERR_COMPILING_FEEL] Unknown variable 'base'`, Camunda `via_reader = null`. Q2 measured on Camunda only (KIE's compile error masks it): `via_shadow = 2000`, i.e. the **parameter wins**.                                                                            |
| `collide-param-shadow-visible` | PASS 6/6 | PASS 6/6 | Q2 measured on KIE too. A parameter shadows an `inputData` name **and** a decision name on both engines, with every wrong answer a plausible non-null number that never appeared.                                                                                                                                                                            |
| `collide-bkm-decision`         | FAIL     | PASS 3/3 | KIE: `ERROR [DUPLICATE_NAME]` ×2, **build clean**, the **BKM wins** (`call_dup = 300`) and the colliding **decision** comes back NOT_EVALUATED/null, taking `read_dup` down as SUCCEEDED-but-null. Camunda: entirely silent and **both readings hold** (`dup=5`, `read_dup=6`, `call_dup=300`) — invocables and variables are **disjoint namespaces** there. |
| `collide-svc-decision`         | FAIL     | PASS 4/4 | KIE: `ERROR [DUPLICATE_NAME]` ×2, build clean, **runtime wholly unaffected** — all four decisions correct, the name resolves to the **decision**, and `evaluateDecisionService("bundle")` still reaches the service. Validator-only.                                                                                                                         |
| `collide-svc-svc`              | FAIL     | PASS 2/2 | KIE: `ERROR [DUPLICATE_NAME]` ×2, build clean, both decisions correct — and **both** by-name `evaluateDecisionService` calls print `SVC twin -> {n=4, left=8}`. The **second service is unreachable by name and silently answers with the first's contents** (`right = 120` never appears).                                                                  |

### Suggested harness wiring

Beside `dmnIntersectionDir` at `jl4/tests-cli/Main.hs:534-541`:

| Harness | `MustPass`                                         | `MustFail`                    |
| ------- | -------------------------------------------------- | ----------------------------- |
| KIE     | A1 A2 A3 B1 B2 B3 C1 D1 D2 D4 E1 E2 E7             | C2 C3 C4 D3 D5 D6 E3 E4 E5 E6 |
| Camunda | A1 A2 A3 B1 B2 B3 C1 C4 D1 D4 D5 E1 E2 E4 E5 E6 E7 | C2 C3 D2 D3 D6 E3             |

The asymmetry **is** the flavor axis, and it is worth reading the two `MustFail` columns against
each other: the seven fixtures that fail on KIE and pass on Camunda are, without exception, cases
where Camunda's silence is the danger.

---

## 2. P5.0 — Prerequisites. Not Phase 5 code, but Phase 5 is not correct without them.

### P5.0a — `checkDrg` and `D-CYCLE` do not exist (§10 Phase 0, §6.4.4-1)

`grep -rn 'D-CYCLE\|checkDrg' --include=*.hs` returns **nothing** outside `specs/`. §10 assigns
both to Phase 0, and §13.7's three ✅ Phase-0 rows are all _R7_ items (`feelBase`, the two
harnesses, `DmnFlavor`) — so **the R5 arm of Phase 0 has not landed**. §6.4.4-5 says `D-RECURSIVE`
"runs the same SCC"; there is no same SCC yet.

**Correction to the brief.** Phase 5 does not "extend `checkDrg` to the `knowledgeRequirement`
graph". It either creates `checkDrg :: Drg -> [FidelityNote]` in `L4.Dmn.IR` — folded into
`drgNotesAll` (`IR.hs:901-908`), ordered module notes → `checkDrg` → per-table notes so goldens do
not churn — or hard-depends on the Phase 0 R5 PR landing first. §6.4.4-7 calls it "perhaps 40
lines"; the cheapest route is to land it as its own PR ahead of this one. The ten `cycle-p*.l4`
fixtures in this commit are that PR's corpus.

### P5.0b — §6.4.4-2's un-suppression is a hard prerequisite of Phase 5, and the spec does not say so

`freeRefs` binds the decide's own name (`Lower.hs:4468` — the spec's cite of `1779` is stale) and
`classifyRef` filters `target /= did` (`Lower.hs:4372` — the spec's `1713-1715` is stale).
**Phase 5 builds `knowledgeRequirement` edges from the same `freeRefs`.** Left as is, a BKM that
requires _itself_ — the case §6.3.9 names **first** — has its edge erased before `D-RECURSIVE` can
see it, and §6.3-1's discharge is nominal. §6.4.4 files this under Phase 0 and §6.4.4-7 says "R5
does not block #923"; both are true of the §6.3.7 half and **false of the §6.3.9 half**. Record the
dependency in §6.4.4 and §10.

The same change, per §6.4.4-9, fixes two stale artifacts **both still present**:
`Lower.hs:4360-4370`'s "DMN 7.3.1" citation (the clause is §6.3.7) and its false premise _"a cycle
among top-level DECIDEs would need a forward reference, which L4's one-pass scope checker does not
currently admit"_; and `TypeCheck.hs:30-34`'s _"forward references are not possible"_, which is what
produced R5's error in the first place.

### P5.0c — Re-rule §7's new codes against `FIDELITY-SEVERITY-AXIS-SPEC.md` §5 before writing them

§7's own header requires this "before building any of it". Phase 5 introduces four codes —
`D-BKM` (Advisory), `D-RECURSIVE` (Blocking), `D-PARTIAL`, `D-FLAVOR-NOSERVICE` — and §7 already
flags `D-PARTIAL` as one of the two rows assigning **two severities to one code**, "the effect axis
smuggled into severity before it had a name". That spec is _"ruling, not yet implemented"_, so
Phase 5 must either adopt `FidelityEffect` for its four codes or record in §7 why it ships without
it. Do not silently add a fifth two-severity code.

### P5.0d — Phase 4 (§10)

Which callees become BKMs **is** Phase 4's tier split; Phase 5 emits whatever tier 2 turns out to
be. Built in parallel on `mengwong/bkm-phase4-unlift`. **This is the blocking dependency named in
the status header.**

---

## 3. P5.1 — The call-site half, which §6.1 says is already done and is not

§6.1 asserts: _"`Lower.hs:678` — `App _ r args -> call e (feelIdent r) args`, rendering `f(x)` —
**is correct** … The bug is entirely on the **callee** side."\_

**False on this tree.** There is no such case. The live arm is `Lower.hs:1682`:

```haskell
    App _ _ (_ : _) -> verbatim e
```

with a comment stating the reason deliberately ("A user-defined L4 function is not a FEEL function
… So it is verbatim, and the report says Blocking"). A saturated call with arguments is emitted as
raw L4 text and reported `D-NONFEELOUTPUT`/`D-NONFEELINPUT` at Blocking. `feelIdent` does not
exist; the only related helper is `feelIdentText`, a per-name fold.

**Phase 5 must therefore build both sides.** Add an `App _ r args` arm rendering a FEEL invocation,
**gated on `r` resolving into Phase 4's emitted-BKM set**, keeping `verbatim` as the fallback for
everything else (a prelude builtin, a cross-module callee, a partial application). §6.1 is
corrected in this commit — it is the section that told two prior readers this work was already half
done.

Probe A2 decides the spelling: since zeebe-dmn accepts **named** arguments in scrambled order, the
call site emits `f(p: x, q: y)` at both flavors rather than positional `f(x, y)`, which makes the
position→name binding of §6.2 visible in the artifact and removes an entire class of silent
argument transposition. A1 shows positional would also have worked; named is chosen because it is
checkable, not because positional is unportable.

**This is also where the corpus win comes from**: all 8 `D-NONFEEL*` notes in
`regcf-corpus.fidelity.txt` are `X OF y` applications. See §10.

---

## 4. P5.2 — BKM emission (§6.2, §13.3, §13.5)

IR (`jl4-core/src/L4/Dmn/IR.hs`): a `NodeBkm` arm on `DrgNode` (`IR.hs:788`), plus a `Bkm`
record — `bkmId`, `bkmName` (verbatim → `@label`), `bkmFeelName` (resolved → `@name` **and**
`variable/@name`), `bkmType`, `bkmParams :: [FormalParameter]`, `bkmLogic :: DecisionLogic`,
`bkmRequirements`. Mirror the `dcnName`/`dcnFeelName` split (`IR.hs:764-777`) so §5.3.5's
element-`name`/`variable`-`name` invariant is true **by construction**, as it already is for
decisions.

- **Child order** (`xsd:sequence`, inherited first): `description?`, `extensionElements?`,
  `variable?`, `encapsulatedLogic?`, `knowledgeRequirement*`, `authorityRequirement*`.
  `formalParameter` is **not** a BKM child — it belongs to `encapsulatedLogic`
  (`tFunctionDefinition`).
- **Invariant** BKM `@name` == `variable/@name`. Probe C4 sharpens why this must be structural:
  KIE raises `VARIABLE_NAME_MISMATCH` and then fails at runtime, but **Camunda tolerates the
  mismatch completely and answers correctly**, binding by `@name` and never reading
  `variable/@name`. So the invariant is engine-checked on `kie` and **wholly unchecked on the
  default flavor** — making it a property of the IR, not of the emitter, is the only backstop.
- `encapsulatedLogic`'s body is `<xsd:element ref="expression"/>` and `decisionTable` is in that
  substitution group, so **`LogicTable` is reusable unchanged** — a parameterised guarded chain
  stays a table (probe A3, now EXECUTED at arity 2 on both engines) and KIE's gap analyser reaches
  it identically. Do **not** emit `typeRef` on a single `<output>` inside a BKM table: probe A3
  measured `WARN [ILLEGAL_USE_OF_TYPEREF]` on KIE, which matches the existing single-output rule of
  §13.5.
- **Ungated by flavor** (§13.3's consequence: "build BKM once, for both flavors, unconditionally").
- Boxed `<invocation>` is **not v1** (§6.2).
- **Hydration composes** (probes B1/B2/B3): a hydrator entry may call a BKM declared on the
  enclosing decision, may pass an earlier sibling entry as an argument, and R8-d′'s `null` lowering
  survives a BKM return. No fallback path is needed for §4.4 × §6.2, which was the design's largest
  open risk.

---

## 5. P5.3 — `knowledgeRequirement` edges (§6.2, §2.3.1)

A `KnowledgeRequirement` sum mirroring `Requirement` (`IR.hs:706-714`), with two arms:
`RequiredBkm !Text` and `RequiredService !Text`. Emit on **every calling decision and every calling
BKM**.

§6.2 already says the edge is "load-bearing and unenforced by the XSD". Probes C2/C3/D3 sharpen
that in two directions at once and the sharpening is recorded in §13.3/§13.5:

- **The edge set is the direct-call set**, not its transitive closure (C1 vs C2). So the graph
  `checkDrg`'s §6.3.9 SCC runs over is the graph the engines consume, and P5.5-1 can be written
  against it directly.
- **The edge is what puts an invocable's name into a caller's FEEL scope on KIE** — uniformly, for
  BKMs (C3) and services (D3) alike, with byte-identical diagnostics. It is not an extra KIE
  tolerates; it is **required**.
- **Camunda has no compile-time backstop.** Without the edge it parses happily and the calling
  decision answers `null` **with no message at any severity** (C3, D3). A `checkDrg` assertion over
  `knowledgeRequirement` completeness is therefore **mandatory**, not belt-and-braces, because on
  the **default** flavor nothing downstream will ever notice.

---

## 6. P5.4 — `decisionService` per `§`, and the one flavor bit (§2.3, §2.3.1-4, §13.4, §13.5, §13.7)

- **Section membership is recoverable, and is currently thrown away.** `topDecls`
  (`Lower.hs:4438-4444`) flattens the section tree but **retains** `Section` nodes
  (`decl d = case d of Section _ sub -> d : section sub`), so a decide→`§` map can be built from
  the tree; `decides = map snd decidesAnn` (`Lower.hs:2822`) is the line that discards it.
- Both flavors emit services **as grouping** (probe D1 passes on both); `knowledgeRequirement` →
  service on **`kie` only** (§13.5's one-bit table), because on Camunda that one element is a
  whole-file parse failure (D2, reproducing §13.4 exactly). `camunda` is the default.
- **`D-FLAVOR-NOSERVICE`** (§13.5): `Blocking` when a call site needed an invocable `§` and the
  flavor forbids it; `Advisory` when a `§` was emitted grouping-only and nothing tried to invoke it.
- **§2.3.2's splitter is a fixpoint**: "split into finer services **until** the graph is acyclic".
  Per §6.4.4-6 — a review-forced amendment to §6.4.4-1 — this forces `checkDrg` to be an
  **exported plain function over `Drg`, callable from `Lower` mid-lowering**, not a step inside
  `dmnReport`. Emit a note recording any split, since the artifact then departs from the source's
  sectioning. Probe D6 is the negative control for the splitter and it also corrects §2.3.2's
  silence claim — see §12 finding 2.
- §2.3.1 details: parameter order is `inputData` **then** `inputDecision` (§10.4) — the **reverse**
  of the XSD child order (`DMN13.xsd:516-519`); emit **named** parameters at every service call
  site; prefer one output decision per service; and remember Xerces passes a service with **no**
  outputs (probe D5, where KIE's validator catches it, the build does not, and the runtime throws —
  while Camunda is completely silent).
- Probe D4 is the shape every Phase 5 corpus file will have — a grouping service whose encapsulated
  decisions reach BKMs — and it passes on both engines. That is the single most load-bearing green
  in the matrix.

---

## 7. P5.5 — The three refusals (§6.3, as narrowed by §13.3)

1. **Recursion → `D-RECURSIVE`, `Blocking`, §6.3.9** (§6.4.4-5). Same SCC routine as `D-CYCLE`,
   second graph, **different code** — "different code because the clause cited and the reader's
   remedy differ, one detector because two detectors is how one of them gets skipped." Side
   condition **verbatim from §6.4.4-3**: `|SCC| ≥ 2`, **or** `|SCC| = 1 with a self-edge`; both
   obvious defaults are wrong, and the second one silently undoes P5.0b. Name **and** id of every
   member; `range = Nothing`. **This discharges §6.3-1's forward reference to R5**, and §6.3-1 is
   edited in this commit to say so.
2. **Partial application / higher-order** — a BKM is a first-order named function only.
3. **Non-KIE target engines → a fidelity note, NOT a suppression** (§13.3's consequence; §6.3's
   head-note). Named consumers: `@hbtgmbh/dmn-eval-js` (no BKM support; an unresolvable callee logs
   `resolved to undefined` and the table **falls through to the next rule**, returning a plausible
   wrong answer) and Camunda 7 (`null`, silently, §13.3 rows 1-3). Neither is a flavor we emit for.

**Housekeeping, done in this commit rather than deferred**: §6.3's case-3 bullet carried
**duplicated leftover text** from the R7 narrowing edit — "the next rule, returning a plausible
wrong answer. If the exporter claims a target engine, gate BKM emission on it." appeared twice, once
inside the strikethrough and once as live prose after it, and that live copy stated the
**superseded** ruling. §6.3 is precisely the section this phase implements; leaving it is how a
future reader gates emission on a flavor bit that was retired.

---

## 8. P5.6 — `uniquifyIn` widening (§5.2, §5.3.3, §5.3.4, §10 Phase 2 residue)

`Lower.hs:3712-3716` names the two unemitted scopes and asserts, **untested until now**, that each
is its own scope. Group E measured it, and the pre-probe guesses in the brief were **half wrong**.
What Phase 5 must land:

- **BKM element/`variable` names → scope 1** (the DRG flat variable namespace,
  `Lower.hs:3718-3726`), and this is now a **hard requirement, not a convenience**. Probe E4
  measured the two engines **disagreeing about what the document means**: KIE deletes the colliding
  decision from the result (NOT_EVALUATED, null, build clean) while the BKM wins; Camunda keeps
  invocables and variables in **disjoint namespaces** and gives both right answers, silently. So
  neither portability nor either engine can serve as the emitter's backstop, and BKM names **must**
  be uniquified against decision names by the exporter. **Append** after the hydrator names, for the
  byte-stability reason §15.2 and §4.4 give: appending keeps every existing FEEL name stable so the
  diff shows only the BKMs.
- **`decisionService` names → their own `uniquifyIn` scope**, which **corrects the brief's guess of
  scope 1**. E5 (service name = decision name) is validator-only on KIE with **no runtime effect at
  all** — all four decisions correct, the name resolving to the decision, and
  `evaluateDecisionService("bundle")` still reaching the service — so services do not need to be
  uniquified against decisions. E6 (service name = service name) is the harm: KIE builds clean and
  **both** by-name calls resolve to the **first** service, the second's output never appearing, with
  no runtime error. `Lower.hs:3712-3716`'s first claim therefore **stands measured**, and the two
  fixtures are kept separate precisely because they share a `DUPLICATE_NAME` code and differ in
  fact.
- **BKM `formalParameter` names → one `uniquifyIn` per `encapsulatedLogic`**, confirmed by E1, E2
  and E7: a parameter shadows a same-named `inputData` (E1) and a same-named decision (E7) on both
  engines, and parameters do not collide across BKMs (E2). `Lower.hs:3714`'s comment stands as
  written and needs no correction — this is adding a scope, not widening scope 1. E3 adds the
  boundary that makes it safe: a BKM body may **not** read a decision variable at all (KIE
  whole-model compile error; Camunda null), so the parameter scope is closed rather than nested.
  Note E7's shape when writing the fixture header: every wrong answer under shadowing is a
  plausible non-null number that never appeared in the source.
- **`D-FEELNAME` must be extended in the same change.** Its `varClaimants`
  (`Lower.hs:3879-3896`) is built from `freeTerms` and `decides` **only**, so it goes **silent** on
  BKM × decision and service × service collisions the moment those elements exist. That is the exact
  failure §13.7-1 recorded for `D-SCOPE` — "covered exactly one of the three classes … leaving
  inputData × decision and decision × decision silent" — and repeating it would be the same defect
  one element kind later. §5.3.4's hard sequencing constraint (**`uniquifyIn` may not lag the
  fold**) applies unchanged to the new scopes.

---

## 9. P5.7 — Flavor split, goldens split, and the pins (§13.6, §13.7)

- **Names**: default (`camunda`) keeps the unsuffixed goldens (`reg-cf.dmn`,
  `reg-cf.fidelity.txt`); `kie` gets `reg-cf.kie.dmn`, `reg-cf.kie.fidelity.txt`. The asymmetry is
  deliberate — it keeps `jl4/tests-cli/Main.hs:449`, `jl4/examples/dmn/README.md:130` and
  `git blame` intact, and makes the default visible in the filesystem.
- **Never a diff-golden** (§13.6). `jl4/examples/dmn/README.md:127-137` and
  `tests-cli/Main.hs:888-894` both assert every golden is reproducible byte-for-byte by one
  `l4 export`; a diff is not the output of any command, and cannot be fed to an engine.
- **Two pins flip, not one** — _correction to the brief_:

  - `jl4/tests-cli/Main.hs:1353` — CLI/bytes, and it _also_ compares the camunda output against
    `dmnGolden`.
  - `jl4/tests/DmnExport.hs:2013` — library level, over **two** modules (`spacedNames` **and**
    `considerConstructors`).

  Both carry the same instruction: "the fix is to split the goldens, not to delete the test."
  Replace each with a positive assertion that the flavors now **differ** — specifically that the
  `kie` bytes contain a `requiredKnowledge` pointing at a `decisionService` and the `camunda` bytes
  do not — rather than deleting them, so the seam stays checked in the other direction. Keep
  `drgFlavoredWith`'s `tcdErrors` guard (`DmnExport.hs:2536-2545`): it exists because a second copy
  without it "put the hole straight back … and let the one test whose job is to announce Phase 5 go
  green on garbage."

- **Per-flavor reporting** (§13.6-4): run the camunda golden through the Camunda harness and the kie
  golden through the KIE harness, naming an absent harness **`UNEXERCISED`** rather than omitting it.
- **A gap outside this PR, restated so it is not forgotten**: the `dmn-engines` job is still **not**
  in the `unstable` ruleset's required checks (§13.7). Until it is, a red engine job does not block
  a merge — including the deliberate `exit 1` the whole skip contract is built around.

---

## 10. P5.8 — Engine `MustPass` legs over **emitted** BKMs (§13.6, §13.7, and Phase 3.6's precedent)

Two tiers, exactly as Phase 3.6 did it (`dmn-hydration-probe/` hand-written vs
`expected/hydration.dmn` emitted): **a red run on the probe isolates the engine; a red run on the
golden isolates the lowering.**

- **Tier 1**: the 23 Group A–E fixtures landed in this commit, hand-written, pinning the **idiom**,
  wired per §1's table.
- **Tier 2**: `jl4/examples/dmn/bkm.l4` + `bkm.cases.json` + four goldens (`bkm.dmn`, `bkm.dmn.md`,
  `bkm.fidelity.txt`, `bkm.md.fidelity.txt`), run through **both** harnesses at **both** flavors,
  pinning that `L4/Dmn/Lower.hs` **emits** it. The `.l4` must exercise: a multi-parameter tier-2
  callee, a BKM call inside a hydrator (§4.4 × §6.2, which B1/B2 have now shown to be portable), a
  BKM→BKM chain (C1), and — for the kie golden — an invocable `§`.
- **Harness gap to close or explicitly accept.** `--cases`' `expect` keys on decision names only
  (`KieDmnCheck.java:363-413`), so neither a BKM's nor a service's return value is assertable;
  KIE's `evaluateDecisionService` result is printed and its ERRORs counted but **never compared to
  an expectation**. Either add an `expectService` map to the cases schema (symmetric, like `expect`,
  so adding a service cannot silently widen the unchecked surface), or state the limitation in each
  fixture header and assert services only through a caller decision. Do not leave it unstated —
  that is precisely the "`5/5 evaluated` is a liveness claim" trap §13.6 was amended to close. If
  `expectService` is built, note from probe D1 that KIE's returned context includes the service's
  **inputs** as well as its output decisions, so the assertion must be written against that shape.

---

## 11. P5.9 — Success metric. The brief's is wrong twice; here is the corrected one

**Baseline is 112, not 122.** Measured on `jl4/examples/dmn/expected/regcf-corpus.fidelity.txt` at
`05e46d9a`: **112 Blocking / 44 Lossy / 21 Advisory** (177 notes, reconciling exactly with the
per-code histogram: `D-LITERALEXPR` 89, `D-RENAME` 35, `D-RULEDATE-UNBOUND` 15, `D-COMPUTEDOUTPUT`
11, `D-SCOPE` 9, `D-NONFEELINPUT` 6, `D-UNDECOMPOSABLE` 5, `D-NONFEELOUTPUT` 2, `D-INLINEDLOCAL` 2,
`D-RULEDATE` 1, `D-ORDERDEPENDENT` 1, `D-COMPUTEDFIELD` 1). **122** was §15.7's _before_ column for
Phase 3.5; **114** was its _after_; Phase 3.6 (hydration + R8-d′) moved it again to 112.
Separately, `jl4/examples/dmn/README.md:191` still says the corpus has **"84 blocking notes"** —
stale by two phases, and worth correcting in the Phase 5 PR since it is the sentence that tells a
reader how much of the corpus would not evaluate.

**A falling Blocking total is the wrong headline, and §15.7 already says why**: a phase that makes
the report speak about something new _necessarily_ adds notes — "A reader who scores this change by
the blocking total will misread it." Phase 5 adds `D-RECURSIVE` and `D-FLAVOR-NOSERVICE`, both
Blocking, by design.

**The decomposed prediction, which is checkable.** All 8 `D-NONFEEL*` notes in the corpus are
`X OF y` applications, i.e. exactly P5.1's shape — 2 `D-NONFEELOUTPUT` on `investment limit` (both
over `` `the applicable measure of annual income or net worth` OF investor ``) and 6
`D-NONFEELINPUT` on `investment limit` and `financial statements required`. **If their callees land
in Phase 4's tier 2, Phase 5 retires all 8: 112 → 104**, plus whatever
`D-RECURSIVE`/`D-FLAVOR-NOSERVICE` fire — predicted **0** on this corpus, since §6.4.2's census
found 0 cyclic over 55 models and Reg CF is one of the two corpora it covered completely. The 89
`D-LITERALEXPR` are **Phase 4's** territory, not Phase 5's; do not book them here.

**The real success metric is Knot 1's, ruled 2026-07-31: _the execution is the exhibit_.** That
means:

1. `jl4/examples/dmn/regcf-corpus.cases.json` — which **does not exist** (`README.md:193`: "Running
   the corpus through an engine needs a `regcf-corpus.cases.json` that does not exist yet, and would
   first need the `f(x)` problem in `../legal/regcf/PROJECTIONS.md` §1 solved") — where **the `f(x)`
   problem is what P5.1 solves**, so writing that cases file is Phase 5's own deliverable, not a
   later one; and
2. a green run of `expected/regcf-corpus.dmn` on **both** harnesses at **both** flavors. Today the
   corpus has been through nothing but `etc/validate-dmn.mjs` (dmn-moddle, a metamodel parser) —
   `README.md:186-195` says so explicitly, and warns that the engine banners cover the
   five-decision toy and "say nothing whatever about the 73-decision corpus projection".

Report the Blocking count as **secondary and decomposed by code**, with the two new Blocking codes
listed separately from the eight retired ones, so the total is never the headline.

---

## 12. The six findings, and where each is recorded

Each of these is a dated measurement note added to the **owning section** of
`DMN-EXPORT-PROGRAM-MODEL-SPEC.md` in the same commit as this file. They are listed here for
navigation only; the spec is authoritative.

1. **`knowledgeRequirement` → `decisionService` is REQUIRED by KIE, not tolerated by it** (§13.3,
   §13.4, §13.5). D3 deletes the one KR element and KIE refuses at **compile** time with the
   diagnostic it gives for a BKM with a missing KR (C3). So on KIE the edge is uniformly what puts
   an invocable's name into a caller's FEEL scope, for BKMs and services alike, and the flavor split
   is sharper than "KIE additionally accepts": the edge is **required by KIE and fatal to Camunda**.
   Also new: Camunda without the edge **parses** and evaluates everything except the calling
   decision, which answers null — §13.4 row 3's "all decisions evaluate" needed that qualification.
2. **The manufactured service cycle is not silent on all three channels** (§2.3.2, §13.6). The
   validator is silent (confirmed) and the status channel is useless (SUCCEEDED on null, confirmed),
   but the **runtime message channel does fire** — "Error evaluating Decision node 'a_out': null"
   plus per-service "Errors occured while evaluating Decision Service node 'alpha'.", 10 errors
   total. Two of three silence claims survive; the third does not. The practical consequence is
   unchanged — a design-time exporter cannot see runtime messages, so §2.3.2's splitter is still
   mandatory — but the sentence was wrong as written.
3. **E4 sharpens §13.7-1's predicted "an element wins silently"**, in the bad direction on one
   engine and the harmless direction on the other. KIE does not merely let one element win: the
   colliding **decision** is reported NOT_EVALUATED with a null value and everything requiring it
   goes null — the decision is **deleted from the result** while the build stays clean. Camunda is
   the opposite of the predicted "silent, wrong answer": silent and **both answers right**, because
   zeebe-dmn keeps invocables and variables in disjoint namespaces. See §8.
4. **`decisionService` names need their own `uniquifyIn` scope, with a concrete harm** (§5.2, E6);
   and E5 shows service × decision is validator-only on KIE with no runtime effect at all. Same
   `DUPLICATE_NAME` code, different severity in fact, which is why they are separate fixtures.
   See §8.
5. **§13.8's two named Camunda gaps are resolved, one each way.** (a) Missing
   `knowledgeRequirement` (C3): Camunda does **not** accept-and-answer-correctly, but it does **not
   diagnose** either — it degrades to null in silence, so there is no compile-time backstop on the
   **default** flavor and a `checkDrg` assertion over KR completeness is mandatory. (b) BKM
   `@name` ≠ `variable/@name` (C4): Camunda tolerates it completely and answers correctly, so §6.2's
   invariant is engine-checked on `kie` and wholly unchecked on the default.
6. **The three genuine unknowns that gated Phase 5 design all resolve favourably**, so no fallback
   plan is needed: named arguments to BKMs work on Camunda (A2); a boxed-context entry may invoke a
   BKM on both engines (B1); a grouping-only service whose encapsulated decisions reach BKMs works
   on both (D4). Plus: the transitive-closure hypothesis is refuted on both engines (C2 fails where
   C1 passes), and `Lower.hs:3712-3716`'s second claim stands measured (E1, E2, E7).

**Minor, recorded in §6.2 and §13.6 rather than here:** a single `<output>` carrying a `typeRef`
inside a BKM decision table draws KIE `WARN [ILLEGAL_USE_OF_TYPEREF]` while changing no value on
either engine (A3); and KIE's `evaluateDecisionService` return context includes the service's
**inputs** as well as its output decision (D1), which matters to anyone writing an assertion against
a service's return shape.

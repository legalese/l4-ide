# Fixity Declarations for L4 — Branch Brief

> **Status:** ✅ LANDED (2026-07-18) — shipped as PR
> [legalese/l4-ide#128](https://github.com/legalese/l4-ide/pull/128), merged up to current
> `unstable`, green (jl4-test 1221/0, jl4-core-test 208/0, l4-cli-test 55/0). Implemented per
> this brief, then run through a 6-dimension adversarial review; all 8 confirmed findings fixed
> (n-ary-theft guard via matcher dry-run; attachment adjacency + misplaced-annotation warning;
> route-α merge reconciliation). Q5 reopens with option A real — see `SET-OPERATORS-SPEC.md`
> §13.2 OUTCOME and Phases 3b/3d. Success routing of §8 executed.
> **Branch:** `mengwong/fixity-declarations` off `origin/unstable`, in a worktree
> (`~/src/legalese/l4wt/fixity-declarations`). PRs into `unstable`, per repo convention.
> **Relationship to set operators:** NON-BLOCKING, both directions.
> [`SET-OPERATORS-SPEC.md`](SET-OPERATORS-SPEC.md) Phases 1–3a proceed regardless of this
> branch's fate. If this lands, its Q5 reopens with option A in hand (see §8 below).
> **Provenance:** design and all file:line anchors from the read-only assessment recorded at
> `SET-OPERATORS-SPEC.md` §13 (subagent report, 2026-07-18). Line numbers were verified then;
> re-verify on checkout, they drift.

## 1. Mission

Let a library declare precedence and associativity for an **identifier operator** (a mixfix
binary like `UNION`), so that

```l4
@infixl 6
GIVEN a IS A TYPE
      p IS A SET OF a
      q IS A SET OF a
GIVETH A SET OF a
p UNION q MEANS ...

@infixl 7
p INTERSECT q MEANS ...

#EVAL a UNION b INTERSECT c        -- today: arity error. Goal: a UNION (b INTERSECT c)
#EVAL a UNION b UNION c            -- today: arity error. Goal: (a UNION b) UNION c
```

— **without** making any operator a lexer keyword, and **without** changing the meaning of any
program that compiles today.

## 2. The enabling accident (why this is feasible)

L4 is already GHC-shaped. GHC resolves fixity in the renamer, not the parser: operator chains
parse to a provisional flat shape, re-associated once fixities are in scope. L4's parser
already produces exactly that input:

- Bare `1 UNION 2 INTERSECT 3` parses to a **flat n-ary App**:
  `App UNION [Lit 1, Lit 2, App INTERSECT [], Lit 3]` — subsequent operators appear as
  nullary `App kw []` markers in the argument list. Producer: `mixfixChainExpr`
  (`Parser.hs:1643-1676`; greedy collection at 1666/1676; `pairToArgs` 1720-1723; the
  keyword-operator table deliberately does NOT handle these, note at 1519-1520). Verify with
  `l4 ast`.
- Today the flat shape then **fails in the typechecker on arity**: the mixfix matcher
  `tryMatchMixfixCall` (`TypeCheck.hs:2681-2772`) matches against ONE binary pattern, and
  `matchLinearAfterHeadKeyword [] (_:_) = MixfixNoMatch` (`TypeCheck.hs:2945`) rejects the
  trailing operator+operand. Hence "expects 2 arguments, but you are applying it to 4".
- So the entire feature is: **a re-association pre-pass that consumes the flat shape before
  the existing matcher sees it.** The parser needs no expression-grammar change.

## 3. Locked design decisions (do not relitigate on the branch)

1. **Syntax: decorator on the operator's definition.** `@infixl N` / `@infixr N` / `@infix N`
   on the line(s) above the `GIVEN.../MEANS` definition (or its `DECIDE` form). Rides the
   existing `@`-annotation rail — `@desc`/`@export`/`@nlg` are lexed via `lineAnno`
   (`Lexer.hs:434-437`, heralds 407-410 and 383, tokens 79-81; `TExport` at 81 and 555 is the
   closest mirror: token + dispatch, no payload parsing beyond the number). Attached to the
   following decl's `Anno` extension (`Syntax.hs:499`). The operator NAME comes from the
   definition's AppForm — the decorator payload is only `(assoc, priority)`.
2. **Re-association happens in the typechecker, not the parser.** The parser's mixfix hint
   registry is module-local — `buildMixfixHintRegistry` walks only the current module
   (`Parser/MixfixRegistry.hs:56-73`; two-pass parse `Parser.hs:2782-2793`) — so the parser
   can never know an IMPORTED operator's fixity. The typechecker's `MixfixRegistry` unions
   imported registries (`TypeCheck.hs:190`; built at `TypeCheck.hs:248`;
   `Import/Resolution.hs:393`). Hook a **shunting-yard pre-pass** in `inferExpr`'s App case
   (`TypeCheck.hs:1684-1738`, near `reinterpretPostfixAppIfNeeded`, 2786-2804): rewrite
   `App op1 [x0, x1, App op2 [], x2, ...]` into nested binary Apps per declared fixity, then
   let the existing matcher handle each binary node unchanged.
3. **No default fixity.** An operator without a declaration contributes NO precedence: any
   chain containing it keeps today's arity error (improve the message if cheap: "no fixity
   declared for X; parenthesize or add @infixl/@infixr"). This is what makes the feature a
   **strict conservative extension** — nothing that compiles today changes meaning. NOT GHC's
   `infixl 9` default; deliberate divergence.
4. **Equal-precedence clashes error** unless same operator + same associativity direction:
   `a X b Y c` with X,Y both prio 6 but mixed assoc (or either declared `@infix`) is a
   diagnostic, GHC-style. Never silently pick.
5. **The keyword operator table is untouched** (`Parser.hs:1496-1522`, body 1502-1518;
   consumed by the precedence-climbing loop — `Cont` 1417-1425, `expressionCont` 1444,
   algorithm notes 1380-1416). Cross-family mixes (keyword op + identifier op in one
   unparenthesized expression) stay parenthesize-or-error. Document this limit.
6. **Fixity flows through imports with the registry.** Add fixity to `MixfixInfo`
   (`Mixfix.hs:29-36`) or as a `Map RawName (Prio, Assoc)` beside `MixfixRegistry`
   (`TypeCheck/Types.hs:344-351`); it ships per-module as `tcdMixfixRegistry`
   (`Import/Resolution.hs:271, 327`) and merges in `unionMixfixRegistry`
   (`TypeCheck/Types.hs:359-364`) — one extra map-union. On merge conflict (same name, two
   fixities), error at the use site, not the import.
7. **Priority domain:** integers matching the existing `Prio` scale (`Parser.hs:1496`);
   accept 1–9. `@infixl`, `@infixr`, `@infix` (non-associative) all supported. A fixity
   decorator on a non-binary definition: warning, ignored.
8. **ExactPrint: parity, not improvement.** `l4 format` is ALREADY lossy on bare infix
   (`1 UNION 2` → prefix `UNION 1 2`; chains garble) — pre-existing bug, independent issue.
   The branch must not regress formatting further; fixing infix round-trip is out of scope.

## 4. Implementation plan (from the §13 assessment; S/M/L per component)

| # | Component | Size | Work |
|---|-----------|------|------|
| 1 | Lexer | S | `@infixl`/`@infixr`/`@infix` heralds via `lineAnno`; mirror `TExport` (token + dispatch). |
| 2 | Parser (annotation only) | S/M | Attach fixity anno to the following `Decide`, as `@desc`/`@export` do; no expression-grammar change. |
| 3 | AST / registry | S/M | `fixity :: Maybe (Prio, Assoc)` on `MixfixInfo`; extend `buildMixfixRegistry` (`TypeCheck.hs:248`). |
| 4 | Import / resolution | S | One map-union in `unionMixfixRegistry`; registry already ships whole. |
| 5 | **Typecheck re-association** | **M/L** | Shunting-yard over the flat App; honor assoc; error on clashes (D4); **disambiguate operator chains from genuine n-ary mixfix** — see §5 risk 1. |
| 6 | Annotation/range rebuild | S/M | Nested binaries need per-level 2-hole annos; generalize `rebuildMixfixAppAnno` (`TypeCheck.hs:3040-3045`) recursively. Wrong holes **silently** break `#EVAL` lenses (`TypeCheck.hs:3033-3039`) — treat range fidelity as correctness, not polish. |
| 7 | Tests | M | See §6. |

Estimated 5–8 person-days total, dominated by #5.

## 5. Top risks and their mitigations

1. **Chain-vs-n-ary-mixfix disambiguation (the crux).** A binary-operator chain and an n-ary
   mixfix call (`if/then/else`-style patterns) produce the SAME flat App shape. The pre-pass
   must fire only when: every interior marker is a **registered binary operator with declared
   fixity**, and the flat shape alternates operand/operator correctly. If ANY marker fails
   that test, fall through to the existing matcher untouched. Write the n-ary regression
   tests FIRST (`if/then/else`, postfix `percent` — `jl4/examples/ok/postfix-with-variables.l4`,
   `mixfix-with-variables.l4`).
2. **Range/anno fidelity through re-association** (see §4 row 6). Acceptance includes lens
   checks, not just evaluation results.
3. **Interaction with juxtaposition application** and imported operators the parser can't see:
   the parser may have shaped some chains as juxtaposition App instead. Characterize with
   `l4 ast` probes BEFORE coding; do not add megaparsec backtracking.

## 6. Acceptance criteria

All in golden tests (`jl4/examples/ok/` + failure fixtures wherever the not-ok convention lives):

- `@infixl 6 UNION` + `@infixl 7 INTERSECT`: `a UNION b INTERSECT c` ≡ `a UNION (b INTERSECT c)`;
  `a UNION b UNION c` ≡ `(a UNION b) UNION c`; an `@infixr` op associates right.
- Equal-prio mixed-assoc chain → clear diagnostic naming both operators and their fixities.
- Undeclared-operator chain → today's behaviour (improved message allowed, no reassociation).
- **Cross-import:** operator + `@infixl` declared in a library module; chain used bare in an
  importing module; works. Conflicting imported fixities → use-site error.
- Non-regression: `if/then/else`, n-ary mixfix, postfix operators, juxtaposition application,
  keyword-operator expressions — all existing suites green.
- `#EVAL` on a re-associated chain reports correct results AND correct source ranges.
- `l4 format` output on the new tests no worse than baseline (§3.8).
- Full suite green. NOTE: `jl4-test` locally needs `JL4_LIBRARY_PATH` set or pre-existing
  actus failures appear — do not chase those.

## 7. Timebox and kill criteria

- **Checkpoint at ~2 days:** the §5-risk-1 disambiguation guard must be demonstrably safe
  (n-ary regressions green with reassociation active). If it cannot be made safe without
  touching the parser's expression grammar or adding backtracking, **stop and write up** — a
  negative result here is a legitimate deliverable and updates SET-OPERATORS-SPEC §13.
- **Budget: ~8 person-days.** At budget with core green but polish outstanding, land behind
  the smallest reasonable scope (e.g., same-module only, imports deferred) rather than grow.

## 8. On success / on failure

- **Success:** SET-OPERATORS-SPEC Q5 reopens: option A becomes real; prelude Phase 1 adds
  `@infixl 6` to `UNION`/`WITHOUT` and `@infixl 7` to `INTERSECT`; §D5 route B (keywords) is
  formally buried; Phase 3c's `LESS`-as-`Minus` alias remains the only reason ever to touch
  the keyword table. Update §13.2 and the Phase table in that spec.
- **Failure:** record the specific blocker in SET-OPERATORS-SPEC §13 (one paragraph), close
  Q5 as (C)+(D) permanently, and file the salvageable pieces (lexer/annotation work, tests)
  as follow-ups if any.

## 9. Orientation for the implementing session

- Worktree + branch per header. Read `SET-OPERATORS-SPEC.md` §13 first (assessment this brief
  distills), then `specs/done/mixfix-operators.md` (esp. the Dec-2025 reinterpretation note
  ~line 115), then the §2 anchors above in order: parser flat shape → typechecker matcher →
  registries.
- Probe files from the assessment live in the assessing session's scratchpad and will not
  survive; recreate from §2 (they are three-liners: `l4 ast` on a bare chain; a same-op chain
  `#EVAL`; a parenthesized control).
- The `l4` CLI on PATH (`~/.local/bin/l4`) may be stale relative to your branch — rebuild
  before trusting probe output against your changes.

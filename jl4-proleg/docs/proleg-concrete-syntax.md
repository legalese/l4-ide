# Canonical PROLEG — concrete syntax (transpiler target)

This is the grammar the `jl4-proleg` front end parses. It targets **canonical
PROLEG** (Satoh, JURISIN 2010), the dialect in which the Japanese Civil Code
corpus and the 2009–2022 bar-exam validation are written. The *Modular-PROLEG /
PIL* dialect (jurisdiction tags `#Country`, `solve/3` phases, `negation/1`) is a
later extension; see "Dialect notes" below. We parse the canonical dialect first
and keep the grammar modular so the PIL layer can be added later.

## Lexical structure

PROLEG is syntactically ordinary Prolog plus the `<=` operator.

- **Atoms**: `lowercase_identifier`, or single-quoted `'Quoted Atom'`.
- **Variables**: `Uppercase` or `_underscore` identifiers; `_` is anonymous.
- **Integers**: `200000`, `-3`.
- **Strings**: `"double quoted"` (rare in legal rules).
- **Compounds**: `functor(arg1, ..., argN)` — `functor` is an atom, N ≥ 1.
- **Lists**: `[a, b, c]`, `[H | T]`, `[]`.
- **Comments**: `% line` and `/* block */`.
- **Clause terminator**: `.` followed by layout/whitespace.

## Operators

| Operator | Prolog priority | Meaning |
|----------|-----------------|---------|
| `<=`     | `xfx`, 1100     | rule: `Head <= Body` (necessary-condition arrow) |
| `,`      | `xfy`, 1000     | conjunction in a rule body |

(The PIL dialect additionally declares `#` as `xfy`, 800, for jurisdiction tags.)

## Grammar (EBNF)

```
program     ::= { clause }
clause      ::= rule | exception | proc_decl | fact

rule        ::= term "<=" body "."        % general rule
             |  term "."                  % bare assertion (empty body)
body        ::= term { "," term }

exception   ::= "exception" "(" term "," term ")" "."

proc_decl   ::= "allege"           "(" term "," party ")" "."
             |  "provide_evidence" "(" term "," party ")" "."
             |  "admission"        "(" term "," party ")" "."
             |  "plausible"        "(" term ")" "."

fact        ::= term "."                  % factbase ground atom

party       ::= "plaintiff" | "defendant" | term

term        ::= variable | atom | integer | string
             |  atom "(" term { "," term } ")"          % compound
             |  "[" [ term { "," term } [ "|" term ] ] "]"
```

Recognition is by shape, in this order: a clause whose principal functor is
`exception/2` is an `exception`; one whose functor is
`allege/2 | provide_evidence/2 | admission/2 | plausible/1` is a `proc_decl`;
one containing `<=` is a `rule`; anything else terminated by `.` is a `fact`
(equivalently a rule with an empty body).

## The two knowledge bases

A PROLEG program is conceptually a **rulebase** (`rule`, `exception`) plus a
**factbase** (`fact`, `proc_decl`). We keep source order in the AST and classify
per-clause; the rulebase/factbase split is a *view*, not a parse-time partition.

## Defeasibility & burden of proof (semantics we must preserve)

- `exception(H, E)` defeats rule `H` when `E` is provable. Exceptions nest
  (exception-of-exception, etc.). The standard translation is
  `H :- Body, not E1, not E2, ...` — i.e. functional `AND NOT` in L4 (Mode B).
- The procedural predicates encode the JUF burden of proof. The reference
  meta-interpreter `prove(Goal, Party)` descends into an exception by proving it
  for the *opposite* party. A fact counts as established iff
  `plausible(F)` holds, or the opposing party gave `admission(F, opposite(P))`,
  and (for the burdened party) it was both `allege`d and `provide_evidence`d.
  - **Mode B (decision-only, default):** erase this layer — pre-resolve each
    fact to its truth value (`plausible`/admitted ⇒ TRUE) and compile to plain
    defeasible booleans.
  - **Mode A (judgement-faithful, later):** reify it as an L4 library with a
    threaded `Party` argument.

## Dialect notes — Modular-PROLEG / PIL (deferred)

From `tsawasaki/mprolegpil-usecase` (interpreter credited to K. Satoh):

```prolog
:- op(1100, xfx, user:(<=)).
:- op(800,  xfy, user:(#)).
(Head <= Body)#Country.            % rule, jurisdiction-tagged
exception(P, R)#Country.           % exception, jurisdiction-tagged
fact(P#Country).                   % fact wrapper
negation(P)                        % NAF, via exception(negation(P), P)
```

Not parsed in Phase 1. The `#Country` tag, the `fact(...)` wrapper, the
`negation/1` NAF encoding, and the `pil`/`pln` phases of `solve/3` are PIL-only.
```

# Handoff: `props`, `ASSUME`, and lexically-scoped function calls

_Status: **a handoff, not a spec and not a ruling.** It records a conversation held on 2026-09-01
and the state of the tree as measured that day. Nothing here has been implemented. Where it cites
a document, re-read that document before acting: this file is a pointer, not a substitute._

**Provenance.** Written by session `assume-and-props-and-lexically-scoped-function-calls`
(`f7803a37-30ce-4d9a-b077-801487b87320`), a fork of the `dmnmd` session
(`579c746e-f139-4fb0-ada5-19e438e734e9`), working out of `smucclaw/dmnmd` — which is the wrong
repo for this work, and is why it is being handed to a session launched in `legalese/l4-ide`.

---

## 0. Where the work lives

| | |
|---|---|
| branch | `mengwong/props-assume-scope` |
| worktree | `/Users/mengwong/src/legalese/l4wt/props-assume-scope` |
| base | `origin/unstable` at `31af0995` (the merge of PR #320) |

Nothing but this file is on the branch.

## 1. The idea, in Meng's words

> "maybe we can adopt a pattern where every function call scope inherits the scope of its caller;
> creating a sort of global-closures-as-lexical-scope-stack notion … akin to defining a function
> inside another function inside another function, as Python supports."

## 2. The fork inside that sentence — the first thing to settle

Those two clauses name **two different mechanisms**, and the design turns on which is meant.

- *"every function call scope inherits the scope of its caller"* → **dynamic scoping**. Lookup
  walks the **call stack**, resolved at call time.
- *"defining a function inside another function … as Python supports"* → **lexical scoping**.
  Lookup walks the **definition nesting**, fixed at compile time. Python closures are static: a
  nested function sees where it was *written*, never who *called* it.

They coincide only while every function has exactly one call site, written inside its definer.
They diverge the moment a function is called from two places or passed as a value.

**There is a third possibility, and it may be the one actually wanted.** §4's `§`-scoped
visibility suggests lookup that follows **the section structure of the document** rather than
either the call stack or the definition nesting — the `§` hierarchy *is* the scope tree, and the
call graph merely has to be consistent with it. Legal text works this way (a definitions section
binds throughout; "in this Part, X means Y" rebinds for a subtree). That reading is closer to
attribute grammars than to dynamic scoping, and it is markedly easier to typecheck, to visualise,
and to lower to a DRG. **Settle this before syntax.**

## 3. Prior art — what the idea is called and who has built it

### Generation 1 — dynamic scope by accident
LISP 1.5 (environment as an assoc list). Getting it wrong is the **funarg problem** (Moses, 1970).
Still live in Emacs Lisp (dynamic by default until `lexical-binding`, Emacs 24), shell functions,
TeX grouping, and **PostScript's dictionary stack** — `begin`/`end` push and pop dictionaries and
lookup searches the stack. Literally "scope as a stack of dictionaries".

### Generation 2 — dynamic scope deliberately, alongside lexical
- **Common Lisp special variables** (`defvar` + `let` rebinding) — the most battle-tested
  industrial design. Note the `*earmuff*` convention: the community found invisible dynamic
  binding dangerous enough to invent a **naming discipline that makes it visible at every use
  site**. Directly relevant to §8 Q2.
- **Perl `local`** — dynamic rebinding of a global for a dynamic extent, unwound on exit. §4.4's
  `local` is this, down to the keyword.
- **Racket parameters** (`make-parameter` / `parameterize`), Clojure `^:dynamic` + `binding`,
  Scheme `fluid-let` — the disciplined form: named, first-class, delimited.
- **Process environment variables** — children inherit; `FOO=bar cmd` overrides for a subtree.
  The most widely deployed dynamic scope in existence.
- **Java Scoped Values** (JEP 446, preview in 21, finalised in 25) — "an immutable value bound for
  the dynamic extent of a computation", built to replace `ThreadLocal`. Evidence the idea is not a
  historical curiosity.

### Generation 3 — typed, inferred, propagated into signatures (where `props` sits)
- **Haskell implicit parameters.** The paper is titled *"Implicit Parameters: Dynamic Scoping with
  Static Types"* (Lewis, Launchbury, Meijer, Shields, POPL 2000). A `?rate` in a body propagates
  into the inferred type and bubbles up the call graph until bound. **This is §5.2.** Read its
  "why not dynamic scope" discussion for the hazard list.
- **Scala 3 `using` / `given`** — contextual parameters threaded implicitly, inferred at call sites.
- **The Reader monad / `MonadReader`** — which `IMPLICIT-PROPS-DESIGN.md` already invokes
  ("a Reader, not a lambda calculus").
- **Algebraic effect handlers** — Koka, Eff, Effekt, OCaml 5, Unison abilities. The modern account:
  dynamic binding *is* an effect, `local` *is* a handler, the handler's extent is the scope.

### The three closest to the literal phrasing
1. **Haskell implicit parameters** — closest to props-with-inference.
2. **John Shutt's Kernel** (`$vau`, fexprs) — an operative receives the **caller's environment as a
   first-class argument**, which is the sentence taken literally. Also a cautionary tale: it makes
   static analysis nearly impossible, which for a DMN exporter is fatal.
3. **Tcl `uplevel` / `upvar`** — reach explicitly into the caller's frame; the unprincipled version.

### Two non-PL framings that may explain it better to lawyers
- **Attribute grammars** (Knuth, 1968): **inherited** attributes flow down the tree, **synthesized**
  flow up. `props` are inherited attributes over the call graph; "what the environment must supply"
  is a synthesized one. Fifty years of formalism and tooling.
- **CSS inheritance** and **React Context** — implicit context down a tree, providers as `local`.
  **Terminology hazard:** in React, `props` is the *explicit* mechanism and `context` the implicit
  one — the opposite of our usage. Any web-native reader will trip on this.

### The formalism that names §5.2 exactly
**Coeffects** — Petricek, Orchard & Mycroft (ICFP 2014, and Petricek's thesis). Effect systems type
what a computation *does to* the world; coeffect systems type what it *requires from* its context.
Flat coeffects are implicit parameters; structural coeffects track per-variable demand. If §5.2's
"inferred per-function props requirement" wants a theory, that is it — and it is less trodden than
the effects side, which for a paper is an opportunity. Related: **delimited dynamic binding**
(Kiselyov, Shan & Sabry, ICFP 2006) for `local`'s interaction with control.

## 4. Why it was abandoned, and the price of buying it back

Naive dynamic scope breaks three things:

1. **Referential transparency** — a callee's meaning depends on who called it.
2. **Accidental capture** — a caller's local silently captures a callee's free name, so renaming a
   variable in *your* function changes *someone else's* behaviour. This is the killer, and the
   reason for earmuffs.
3. **Modular reasoning and typing** — a signature no longer tells you what a function needs.

Every generation-3 system pays the same three prices to get the idea back: names **declared and
typed**; requirements **inferred and surfaced in the signature**; rebinding **delimited and
explicit**. The current design pays two — §5.2 is the inference, §4.4 is the delimiter. §8 Q2
("reuse `'s` field access, or a distinct form?") is the third, and the historical record is loud
and unambiguous there: **make it visually distinct.**

## 5. Why the legal domain argues for it

Legal drafting is already an inherited-attribute system, and unusually explicit about it: a
definitions section binds throughout an instrument; "in this Part, X means Y" rebinds for a
subtree; "for the purposes of this section" is `local` with a stated extent; an Interpretation Act
is the default environment. The hazards in §4 above are not merely tolerable here — the domain has
independently evolved the same mitigations.

The DMN payoff is already written down in `IMPLICIT-PROPS-DESIGN.md` §10.5: a flat, typed, declared
environment is isomorphic to DMN's `inputData` namespace, so `props` dissolves the exporter's shape
problem instead of patching it.

## 6. State of the tree as measured 2026-09-01 (verify before relying)

All against `origin/unstable` at `31af0995`.

| thread | state |
|---|---|
| `IMPLICIT-PROPS-DESIGN.md` §10 (the `ASSUME` snapshot) | **on unstable** — PR #217 is **merged**, not draft |
| props/program-model cross-citation (§10.4 item 5) | **half done** — props cites `DMN-EXPORT-PROGRAM-MODEL-SPEC.md`; the program model cites props **zero** times |
| `DMN-EXPORT-PROGRAM-MODEL-SPEC.md` | on unstable, *design, not yet implemented*; its thesis is **un-lambda-lifting** — i.e. the lexical-scope question, asked from the exporter's end |
| dmnmd as an l4-ide export validator in CI | **not started** — no mention of `dmnmd` anywhere in `.github/` |
| the differential gate (PR #216) | **stalled** — open as "HANDOFF (draft, not for merge)", **324 commits behind** unstable, 2 ahead |
| `DMN-DIFFERENTIAL-CI-SPEC.md` and `etc/dmn-differential/` | exist **only on the #216 branch**, absent from unstable — yet §10.4 item 5 cites the spec as though it were there |
| dmnmd D-16 phase 2 (`dtDefaultOutput`) | **done** — dmnmd trunk `9535164` (PR #51) |
| l4-ide#320 (BRANCH in expression position; prelude `elem`) | **merged** 2026-09-01, commit `31af0995` |

## 7. Boundaries — what not to do

- **§10.5's freeze is about the exporter's _program model_**, not its cell language. Reworking
  `freeTermTypes` / the module shape should wait for a `props` ruling. Fixing how one expression
  becomes FEEL text does not spend that budget — which is why PR #320 was safe to land.
- **`local` and DMN lowering must be read against each other before either freezes** (§10.4 item
  5). A DMN decision is a 0-ary variable holding one value per evaluation, so a DRG has no scoped
  rebinding: today that costs 15 dropped decisions (`D-RULEDATE-UNBOUND`), and if `local` becomes
  general, **every use of it is unlowerable by the same argument**.
- **`ASSUME` is not simply to be deleted.** Of the 53 legal-corpus lines, `regcf`'s 2 are
  deliberate typed bottoms with provenance and want a first-class `REFUSE`, not `props`. And
  fixtures/experiments (418 lines in `jl4/experiments`) are a real constituency for whom `props` is
  *worse* — a two-line operator demo should not need an environment. §10.4 items 2 and 3.

## 8. Stale claims in the source material — do not propagate

- The transcript excerpt this handoff descends from calls PR #217 a **draft**. It is merged.
- That same excerpt's ranked list puts dmnmd D-16 phase 2 as item 3, to do. It is done.
- `IMPLICIT-PROPS-DESIGN.md` §10.3 corrects an earlier count of the legal-corpus `ASSUME` use
  ("two files, 16 lines" → six files, 53 lines). Cite the corrected table, not the memory.

## 9. Loose ends held by the retiring session

- dmnmd: the `test/roundtrip/baseline/` gate is **dead** (stale since `8c18f22`, predating four
  deliberate output changes). It needs a deliberate, audited re-record on trunk — not one folded
  into whatever change happens to notice.
- smucclaw/l4-ide#948 — the `§`-section mixfix-hint fix, stranded on PR #310's stack. Residual is
  larger than the issue states; the durable fix is a `foldTopDeclsRecursive` combinator closing the
  hand-rolled walkers in `Import/Resolution.hs`, `Rules.hs` and `API.hs`.
- Related open issues touching this work: smucclaw/l4-ide#936 (quantifier lowering; binder
  unsoundness — possibly fixed-but-open), #937 (dmn-moddle is not a well-formedness backstop —
  never present moddle acceptance as engine acceptance), #933, #909.

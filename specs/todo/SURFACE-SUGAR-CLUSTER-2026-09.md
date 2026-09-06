# Surface-sugar cluster — rulings, 2026-09-06

> **Status: RULED 2026-09-06, NOTHING BUILT.** Meng marked rulings-bench card
> `D7-small-language-cluster` **accept** on 2026-09-06. This file records six of its eight
> sub-rulings; the other two live in their own owning documents (see §0). Every "build" below
> authorises work that has not started.
>
> **The two user-visible spellings this cluster admits — `==` (D7.1) and `IMMEDIATELY` (D7.8) — do
> NOT get their `doc/` rows here.** `CLAUDE.md` §6 requires a page in the shipping PR, and the
> shipping PR is the build, not the ruling: `doc/reference/operators/comparisons/README.md` for
> `==` and the regulative-rules page for `IMMEDIATELY`, both linked from `doc/SUMMARY.md` and
> checked by `doc/test-docs.sh`. A ruling that documented a spelling nobody can yet type would be
> the drift this project's rules exist to stop.
>
> **Meng's note on this card, verbatim:**
>
> > Let's waive the D7.2 experiment. I'm all out of round tuits.
>
> **Every one of the eight was adversarially refuted, and all eight came back `weakened` — not one
> `stands`.** Each ruling below carries its refutation in one line. Where the refutation killed the
> _reason_ but not the _verdict_, the ruling records the corrected reason, because a decline closed
> on a false ground is worse than an open issue: the first reader who greps finds the ground false
> and reopens the whole question.

## 0. Where the other two are

- **D7.2 (#438, record update)** — `RECORD-UPDATE-SPEC.md` §9 step 0 and
  `RECORD-UPDATE-EXPERIMENT.md` §7. Meng waived the experiment; see those two files.
  **Addendum, 2026-09-06 — a correction to the adversarial verdict, and it removes a mark I had
  listed as owed.** The refuter reported `BUT WITH` as "never marked by Meng". It was ruled, by him:
  `RECORD-UPDATE-SPEC.md:822` records R2 as ruled 2026-08-19, and the commit that wrote it,
  `4193c42c`, is under his name and titled "rule `alice BUT WITH age IS 31`, reversing R2", with
  both halves of the reasoning in its message. His words, 2026-09-06: _"BUT WITH was agreed; I
  thought it was settled."_ It was. The refuter had compared two house styles — counting
  `(marked accept)` strings — and read the absence of one convention as the absence of a ruling.
- **D7.4 (#909, `CONSIDER` exhaustiveness → error)** — recorded beside the three
  `consider-exhaustiveness-*.md` specs, whose implemented false-positive-freeness result is its
  precondition. See `consider-exhaustiveness-scope-hardening.md`.

---

## D7.1 — ADD `==` as a synonym for `EQUALS`. Do NOT retire `=` **yet**. RULED 2026-09-06.

**The ruling.** `==` is added as a third spelling of equality, beside `EQUALS` and `=`. `=` is
**not** retired — but that half is recorded as a **deferral with a trigger**, not as a decision that
`=` is safe. **`#344` is not closed by the synonym**: its title asks to replace `=`, and only the
adding half is ruled here.

**What decided it.** `==` is a parse error today (probed); `=` and `EQUALS` share one parser
alternative at `jl4-core/src/L4/Parser.hs:1654` with one precedence, so the change is one
alternative; there are **zero** non-comment `==` occurrences across 672 `.l4` files — the 611 grep
hits are `-- ====` comment rulers — so **zero goldens move**; and `prettyLayout` prints `EQUALS`
regardless (`Print.hs:146`), so no printed form changes.

**Adversarially weakened, and this is why the second half is a deferral.** _The load-bearing premise
for "do not retire" — kosmikus's "L4 uses `=` for nothing else" — is false: `=` has been a `LET`
binding keyword since commit `1220913d` (2025-12-17), `Parser.hs:533-539`, taught at
`doc/reference/functions/LET.md:70-80`, and `LET x = 5 = 5 IN x` parses and evaluates to `TRUE`
today — which is the exact C-style hazard #344 names._ So the retention rests on **cost** (74 lines,
17 files, 9 doc pages, 0 in canon), not on the unambiguity argument it was written on.

**The trigger, so the deferral can end.** Reopen the retirement when `=` is accepted as a definition
keyword **outside** `LET` — any `TOperators TEquals` parse site beyond `Parser.hs:539` and `:1654`.
A reader who thinks that condition is already met by the `LET` binder is not wrong, and that reading
is itself unruled.

---

## D7.3 — `TYPICALLY NOTHING` at the declaration. Never a silent default. RULED 2026-09-06 (modified).

**The ruling.** A `MAYBE`-typed record field may be declared
`field IS A MAYBE T TYPICALLY NOTHING`, and only then may a construction site omit it. An
un-annotated `MAYBE` field stays required at construction. **The default is written where the field
is declared, never inferred from the type.**

**What decided it.** The modified form is additive and re-means **0** sites — omitting a field is a
check error today (`IncompleteAppNamed`, `TypeCheck.hs:3146`) — and the machinery already exists:
field-level `TYPICALLY` parses (`Parser.hs:1292-1301`), type-checks, has a doc page
(`TYPICALLY.md:22,107-115`) and a fixture (`ok/typically-basic.l4`).

**Adversarially weakened, and one thing it found must be ruled with it.** _"No diagnostic anywhere"
is already false at every deploy boundary: the batch decoder, `jl4-service` and the JSON schema
silently treat an absent `MAYBE` field as `NOTHING` today — `Machine.hs:2282`,
`Backend/Jl4.hs:436-441`, `JsonSchema.hs:264`._ So this ruling buys back the **source** half only.

**The asymmetry is ruled, not left implicit: it stands.** The JSON/service boundary is the root of
an evaluation and keeps defaulting an absent `MAYBE` field to `NOTHING`; `TYPICALLY NOTHING` does
not gate it. Encoders annotate; callers over the wire do not have to.

**Two corrections to the record for whoever builds it.** Cite `TYPICALLY-DEFAULTS-SPEC.md:420-428`
as the governing text, not `IMPLICIT-PROPS-DESIGN.md` §11.5 R8, which carves `DECLARE` fields out
(`TYPICALLY.md:69-72`) — R8's own note now carries a line saying it extends to them. And this is
**blocked on R8's unbuilt named-site half**; #645 does not close before that ships.

---

## D7.5 — DECLINE `GIVEN A Foo` (unnamed arguments). RULED 2026-09-06.

**The ruling.** Declined. #410 is closed — **but not on the reasons the proposal gave**, and the
closing comment must carry the corrected ones or the first reader who greps will reopen it.

**What decided it, corrected.** Two grounds survive: kosmikus's two-spellings objection, which is
**his own issue's** and has stood unrebutted for sixteen months; and **constructor shadowing** —
`GIVEN A Person` binds a term named `Person`, so the body can no longer construct a `Person`.

**Adversarially weakened; two stated reasons are measurably false and are struck.** _"Zero
measurable demand" is wrong by an order of magnitude — parameters named after their own type number
**259 in 53 l4-ide files** on one filter and 364 in 42 on another, more than the populations the
proposal compared against, so the comparison inverts. "An ambiguity you cannot lint away" is also
wrong: `A`/`AN`/`THE` are keyword tokens (`Lexer.hs:270-273`), so with the article required a
name-clash warning is mechanical and would fire on zero sites today._ **Neither may appear in the
closing comment.**

---

## D7.6 — DECLINE `EVERY Person p` as standalone sugar; fold it into the quantifier spec. RULED 2026-09-06.

**The ruling.** No standalone `EVERY Person p → GIVEN + PARTY` desugaring. #484 is **not closed for
keyword collision**; it is **folded** into `EVERY-EACH-QUANTIFIER-SPEC.md` as that spec's
distributive (no-`HENCE`/`LEST`) rung, to be built there and not alone, and that spec rules which of
the two spellings wins.

**What decided it.** A standalone desugaring would give `EVERY Person p MUST X HENCE h` per-party
`HENCE` semantics that the quantifier spec's barrier model later re-means to h-once — a silent
re-meaning, which is the trade this bench refuses. And under R2 a per-rule `GIVEN` restating a
section binder is a check error, so the sugar is unusable at every post-sweep section-binder site.

**Adversarially weakened; the gate in the original reasoning had already passed.** _"Defer until
after props discharge" was stale when written — #344 merged 2026-09-05T11:29Z, and the demand is
**18 sites in 2 files** on both the pre-sweep and current trees, a number R2 makes structurally
immovable. There is also an unmerged spec draft (`upstream/every`, `970a8705`) that already adopted
`EVERY Person p` with `p` last, so the spec carries two spellings and must rule between them._

**Cross-reference, deliberately not restated here.** The plural-quantifier idiom now has **§2.2.7
threshold joins** on branch `spec/threshold-join` (PR #352). Read the spec for the semantics; this
ruling only says where #484 lives.

**Addendum, 2026-09-06 — Meng's own model, and it is the spec's.** _"in my mind it immediately fans
out via an unfold of RANDs, so to speak, to as many parallel threads as there are inhabitant persons
in the type."_ That is `EVERY-EACH-QUANTIFIER-SPEC.md`'s CSP fan-out almost verbatim: `EVERY` is the
**barrier** (interleave, then `HENCE` once), `EACH` is the **fork** (each thread carries its own
`HENCE`). **The one question the spec leaves open is not the semantics but the vocabulary: which
English word means which.**

**Addendum, 2026-09-06 — `JOINTLY`/`SEVERALLY` was proposed and the research says no.** Meng
proposed the pair for barrier/fork, on the ground that a noob persona may not read `EVERY` vs `EACH`
correctly. A research pass over doctrine, practice, civil law and the formal literature concluded
**against** it, on the one axis that touches performance — common-law _joint_ asserts the opposite
of a barrier (Restatement (Second) of Contracts § 293: performance by one promisor discharges the
duty of the others) — and proposed instead that the join be marked somewhere else. The finding is
in **`specs/todo/EVERY-EACH-JOINT-SEVERAL-MEMO.md`** (landed in PR #350); it is cited here, not
restated, and it is the quantifier spec's ruling to make, not this cluster's.

---

## D7.7 — HOLD `^^^` (triple ditto). RULED 2026-09-06.

**The ruling.** Not built, and **held rather than closed** — #122 stays open with its gate written
on it. Two people on the thread leaned positive, and the gate is a readability result nobody has
run, so a permanent-sounding close would misrepresent the state.

**What decided it, and it is not the cost case.** `^^^` **already parses today** wherever the line
above ends in three adjacent one-character tokens — verified: `DECIDE f n IS (n)` / `DECIDE g n ^ ^^^`
checks, and `g 7` evaluates to `7`. So the proposal is a **re-meaning of a currently valid program**,
not an addition. That, rather than line count, is what makes it expensive.

**Adversarially weakened: the demand is smaller than the proposal claimed, in the proposal's own
favour.** _The 25 lines reproduce exactly but overcount: under the issue body's own rule (no text to
the right of `^^^`) only 6–8 lines collapse, four of them the ditto feature's own fixtures, leaving
**two lines of real law**. Canon has zero caret lines._

**Reopen when** any of: a lexer-level prototype expanding `^^^` to N tokens passes
`jl4ExactPrintIdentity` and the `lsp/semantic-tokens/ditto.l4` golden with per-token highlighting
intact; or a readability protocol run on the collapsible lines prefers `^^^`; or non-fixture
end-of-line caret runs reach ten lines (today: two).

---

## D7.8 — ADD `IMMEDIATELY`; DECLINE re-meaning a missing `WITHIN`. RULED 2026-09-06.

**The ruling.** `IMMEDIATELY` is added as an explicit spelling for `WITHIN 0`. A **missing** `WITHIN`
is **not** given a new default meaning.

**What decided it.** A missing `WITHIN` already has a documented, load-bearing meaning that **70 live
sites** rely on (123 over tree plus canon): the obligation is _ongoing_ —
`doc/reference/regulative/README.md:201`, implemented at `Machine.hs:1511-1520` and load-bearing in
`StateGraph.hs:242`. Re-meaning it would silently change 70 provisions. `IMMEDIATELY` re-means
nothing: it is a new spelling with zero existing sites.

**Adversarially weakened; both precedents cited for the decline are false and are struck.** _"HENCE
and LEST are both `MAYBE` and their absence has never been given a default meaning" is refuted by
two "Default if omitted" tables at `doc/reference/regulative/README.md:110-115` and `:157-162`,
implemented at `Machine.hs:941` and `:1596-1607` — omitted regulative clauses routinely **do** carry
declared defaults. And R8 is neutral-to-favourable to #541's mechanism, not against it._ The verdict
survives on the documented-existing-meaning ground alone, which is stronger than what it was argued
on.

**Do not close #541 on `IMMEDIATELY`.** The issue is today the only tracker for the
**maintenance-obligation** gap that `DEONTIC-LOAN-COVENANT-MODEL.md` §6 calls the most important
one. Retitle it to that arc, or file and link a successor, before closing.

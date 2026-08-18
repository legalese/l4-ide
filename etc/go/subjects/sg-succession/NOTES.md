# sg-succession — subject idiosyncrasies

Free prose about **this corpus**, for humans and for the skill. **No script reads this file.**
Machine-readable subject facts live in `subject.json`; the CLI-surface pin in `pins.json`; the
measured negative controls in `known-defects.json`. When a fact below stops being true, fix it
here in the same change that moved it.

## What this subject is

Three Singapore Acts, encoded as **one** subject rather than three:

| Act                                 | id        | what it answers here                      |
| ----------------------------------- | --------- | ----------------------------------------- |
| Wills Act 1838                      | `WA1838`  | is there a valid, unrevoked will?         |
| Intestate Succession Act 1967       | `ISA1967` | who takes, and in what shares?            |
| Probate and Administration Act 1934 | `PAA1934` | who administers, in what order, and when? |

**Why one subject.** They are three views of one event — a death — and they share their nouns.
The same person is the PAA's "deceased", the Wills Act's "testator" and the ISA's "intestate";
the same human being is a beneficiary under a will, a next-of-kin under ISA rule 3, and a person
"interested in the estate" with standing under PAA s 18(2). Three subjects would triplicate the
family tree and let the copies disagree, and the questions users actually ask cross all three
Acts in one breath.

That decision is what drove the pipeline's **N-module corpus** work: before this subject, a
`subject.json` could declare `corpus.main` plus an optional `corpus.wizard` and nothing else.
`corpus.modules` exists because this subject needs an ontology module plus three statute modules
plus cases plus a wizard.

## This is the first subject where "de novo" and "corpus" are the same encoding

Every earlier subject had a committed corpus that a de novo run was measured _against_
(SPEC.md §8's diff oracle). There is no prior Singapore succession encoding, so there is nothing
to diff. **The §8 acceptance comparison is inapplicable here, and `denovo.modules` and
`denovo.surface_map` are deliberately not declared** — a de novo module that IS the corpus makes
the comparison an identity, which the resolver refuses, and manufacturing a second encoding
purely to have something to diff would be theatre.

What IS declared under `denovo` is the three registers — the source bundle, the
external-modification register and the fork register — because those are genuine P1/P2/P4
deposits regardless of whether a comparison follows. Running `--milestone g2` validates them.

## Two L4 traps this corpus paid for, in order of how much they cost

**1. `NOT` binds looser than `AND`, and it produced a wrong legal answer.** The grammar parses
`NOT` followed by a whole indented expression (`jl4-core/src/L4/Parser.hs`, `negation`), so:

```
A AND NOT B AND NOT C     parses as     A AND NOT (B AND NOT C)
```

ISA s 7 rule 1 is _"a surviving spouse, no issue and no parent"_. Transcribed the obvious way,
it fired for an intestate leaving a spouse **and two surviving parents**, giving the widow the
whole estate where rule 4 gives her one-half. The encoding read like the section and computed
something else. **Every `NOT` in this corpus is parenthesised**, including where it is
unambiguous. The same trap has a second face: `A AND count xs EQUALS 0` groups as
`(A AND count xs) EQUALS 0`, which surfaces as an unresolvable `__EQUALS__` overload rather than
as a wrong answer — noisier, and therefore kinder.

**2. A mixfix name may not end with a keyword.** `` `any of` people `survived` `` is accepted
where it is _defined_ and then cannot be applied anywhere: every call site reports _"expects 1
argument, but you are applying it to 2"_ plus _"could not find a definition for `survived`"_.
Reduced to a three-line repro. Every mixfix in this corpus therefore ends with an argument —
which is why the domain module reads `` `someone survived among` people `` rather than the
more natural form.

Both are reported upstream; see `known-defects.json` for the ones used as negative controls.

## Layout traps, less costly but real

- **`BRANCH` arms use `IF ... THEN`**, never `WHEN ... THEN`. `WHEN` belongs to `CONSIDER`.
- **A `WHERE` clause inside a `BRANCH` scopes to its own arm**, not to the whole definition.
  `sg-isa.l4`'s stock split is a separate top-level function for exactly that reason.
- **The `OTHERWISE` expression must start on the same line** as `OTHERWISE` when it is a record
  construction.
- Use the prelude's prefix `append x y` rather than infix `APPEND` across a line break.

## Numbers are exact, but they do not print that way

`ValNumber` is a `Rational`, so a one-third share really is a third and the shares of a complete
distribution sum to exactly 1 — `sg-succession-cases.l4` asserts that rather than assuming it.
But `prettyRatio` (`jl4-core/src/L4/Utils/Ratio.hs`) renders a non-integer through `Double`, so
that third prints as `0.3333333333333333`, and three of them look like they lose the estate.
**Do not "fix" this by rounding in the encoding.** It is a printer question, and a distribution
tool that shows fractions as fractions is the correct answer to it.

## Where this corpus is knowingly incomplete

Read `denovo/fork-register.json` first; it is the authoritative list. The two that matter most
to anyone relying on an answer:

- **F6 — ISA s 6(b) half-blood ranking is NOT implemented.** The section ranks half-blood
  relations "immediately after those of the whole blood related to him in the same degree". The
  rule-6 and rule-8 arms divide their class equally without applying that ordering, so an estate
  entered with both whole- and half-blood siblings divides equally when the live reading says
  the half-blood takes nothing. There is a case asserting the _wrong_ answer on purpose
  (`half blood and whole blood siblings`) so the gap is executable and cannot be forgotten.
  **This is the first thing to fix in the next revision.**
- **F2 — legitimacy is delegated, not decided.** ISA s 3 confines "child" to a legitimate or
  court-adopted child. The tool cannot observe legitimacy; membership of `Family.children` _is_
  the s 3 determination, made by whoever supplies the facts. A user who enters an illegitimate
  child as a "child" gets an answer the law does not give and nothing in the encoding catches it.

**No rule-version axis.** The corpus states the law as at the source bundle's in-force date
(18 Aug 2026) and carries no dated arms, so it cannot answer about a death in 1990. Every SSO
version marker is disposed as `scoped-out` in the external-modification register, which is where
the limitation is recorded formally.

## Retrieval: do not start with the HTML

The SSO landing page is **not** a usable text source for a long Act. `PAA1934` returned its 70
section headings with no bodies, and both `?ViewType=Print` and `?WholeDoc=1` are stubbed or
WAF-blocked. **The official PDF (`?ViewType=Pdf`) is complete and carries the Schedules**, and is
what every `sha256` in the source bundle is taken over. `source/fetch-sso.py` re-runs the whole
fetch; the HTML is kept only for the in-force banner and the version history the sweep reads.

## The one `l4 verify` finding, and why it is not a defect

`p8-verify` reports **one** propositional finding across the six modules, and it should stay
there:

```
`revocation by presumption of an intention on the ground of an alteration in circumstances`
    [unsat] at body
      the decision is TRUE for no assignment of its atoms: as drafting, a requirement nobody can meet.
```

That decision encodes **Wills Act s 14**: _"No will shall be revoked by any presumption of an
intention on the ground of an alteration in circumstances."_ The section creates a **deliberately
empty category** — it exists to say that this mode of revocation does not exist — so a decision
that is constantly FALSE is the _faithful_ encoding, not a drafting error.

The finding is a true property of the boolean skeleton and a false alarm about the law. It is the
general shape of a limit worth knowing: `l4 verify`'s unsat rule reads "TRUE for no assignment" as
_a requirement nobody can meet_, which is the right reading for an obligation and the wrong one for
a statutory negation. **Do not "fix" it by deleting the decision** — the encoding would then be
silent about s 14, which is worse. If the run ever reports zero findings here, something has
changed and s 14 should be re-read.

## Why `p7-lts` reports NOT-BUILT, and `p7-bpmn` is not declared at all

Both for the same reason, and it is a fact about the law rather than about the tooling: **this
corpus is entirely constitutive.** It decides who takes what and when a deadline falls; it states
no `MUST`, `MAY` or `SHANT`. `l4 export --to bpmn` accordingly answers _"No regulative rules found
in module"_, and the state-graph projection has no transitions to draw.

That also broke `p0-preflight` the first time this subject ran: `etc/go/lib/discover.mjs` treated an
empty rule enumeration as a **changed CLI surface** and returned `BROKEN`, so a purely constitutive
subject could never pass the front door. Fixed in the same change that added this subject — zero
regulative rules is now a legitimate empty set, distinguished from a genuine shape change by the
`No regulative rules found in module` message. `regcf`'s three rules still pin and check exactly as
before.

The duties the PAA _does_ impose — the s 28 oath, the s 29 security, the s 57 order of application —
are the obvious candidates for a regulative pass later. Encoding them would light up both legs.

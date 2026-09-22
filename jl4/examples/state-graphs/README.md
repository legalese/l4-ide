# State Transition Graph Examples

These files demonstrate state transition visualization for L4 regulative rules, inspired by Flood & Goodenough's "Contract as Automaton" model.

## Generated From

Source files with regulative rules (MUST/MAY/SHANT):

| Source File | Graphs Generated |
|-------------|------------------|
| `jl4/examples/ok/prohibition.l4` | noSmoking, noDrinking, mayDrink, mustDrink, limitedGambling, noSmokingWithConsequences, noSmokingExplicitBreach, noSmokingBreachByAlice, noSmokingBreachWithReason, noSmokingBreachReasonOnly, breachInHence |
| `jl4/examples/ok/contracts.l4` | aContract, x, y, quux, z, a, goesOn |
| `jl4/experiments/actors.l4` | SeriesAFinancing, SeriesAIssue |
| `jl4/experiments/looping-with-recursion.l4` | InitialSale, PayUntilZero |
| `jl4/experiments/patterns_and_idioms.l4` | simplePayment, serviceContract, paymentDue, loanAgreement, conditionalSale |
| `jl4/experiments/safe-post.l4` | EquityFinancingConversion |
| `jl4/experiments/wedding.l4` | weddingceremony, Spouse1lovesSpouse2, Spouse2lovesSpouse1, Spouse1holdsSpouse2, Spouse2holdsSpouse1, supportinallcircumstances, careinsicknessandhealth, deathreleasesvows, noabandonment, fidelity, marriagecontract |

Command:
```bash
l4 state-graph <file.l4>

# Or from a Haskell checkout
cabal run l4 -- state-graph <file.l4>
```

To rebuild every file here from its source, use the script rather than editing
by hand — these are generated artefacts, and nothing in CI checks them, so a
hand-patched one looks regenerated without being it:

```bash
jl4/examples/state-graphs/regenerate.sh
```

Every source in the script regenerates as of 2026-09-23, when all 39 diagrams
were last cut — on `lts/draw-what-it-means`, where five caption fixes to the
renderer moved 31 of the 39. Before that they were cut on 2026-09-17 (unstable
`e2f4a71f`). An earlier version of this note said
`jl4/experiments/patterns_and_idioms.l4` did not typecheck and its four diagrams
were stale; legalese/l4-ide#407 admitted the bare field-access patterns that had
stopped it parsing, and the file now yields five graphs (`conditionalSale` is
new). If the script prints a WARNING for a source, that source has regressed —
do not hand-patch its diagrams.

**A renderer change makes every file here stale, and nothing says so.** Rerun the
script after touching `jl4-core/src/L4/StateGraph.hs` or
`jl4-core/src/L4/StateGraph/Dot.hs`, not only after editing a source `.l4`.

The little arrow sketches below are schematic: they name the places and the
arrows, and they leave out deadline brackets and other clauses that the real
captions carry. Read a `.dot` file for the exact text.

## File Formats

Each example is provided in three formats:
- `.dot` - GraphViz DOT source (text)
- `.svg` - Scalable Vector Graphics (for web/docs)
- `.png` - Portable Network Graphics (for embedding)

## Examples

### Simple Prohibition: `noSmoking`

A simple SHANT (MUST NOT) rule:
```
initial --[Alice SHANT smoke]--> Fulfilled
initial --[violation]--> Breach
```

### Chained Obligations: `noSmokingWithConsequences`

Shows a LEST clause creating an intermediate state with a reparation obligation.
Note the two LEST edges carry different words, because different events reach
them: Alice smoking breaches the prohibition, whereas the reparation obligation
is breached by the clock.
```
initial --[Alice SHANT smoke]--> Fulfilled
initial --[violation]--> "Alice must drink WITHIN 10"
"Alice must drink WITHIN 10" --[Alice MUST drink]--> Fulfilled
"Alice must drink WITHIN 10" --[timeout]--> Breach
```

This demonstrates how regulative rules create state machines with:
- **Terminal states**: Fulfilled (green), Breach (red)
- **Intermediate states**: Reparation obligations
- **Transitions**: Actions with deontic modals and deadlines

### Permission: `mayDrink`

Shows a MAY rule (no failure path):
```
initial --[Bob MAY drink]--> Fulfilled
```

### Obligation: `mustDrink`

Shows a MUST rule with implicit breach on timeout:
```
initial --[Alice MUST drink]--> Fulfilled
initial --[timeout]--> Breach
```

### Conditional: `limitedGambling`

Shows a prohibition with a PROVIDED guard:
```
initial --[Alice SHANT gamble amt IF amt GREATER THAN 100]--> Fulfilled
initial --[violation]--> Breach
```

### Contract Examples (from `contracts.l4`)

- **`aContract`** - Simple obligation with deadline
- **`goesOn`** - Chain of obligations with HENCE/LEST paths

### Business Transactions (from `patterns_and_idioms.l4`)

- **`simplePayment`** - Basic payment obligation
- **`serviceContract`** - Service delivery with payment
- **`loanAgreement`** - Loan with repayment obligation

### Startup Financing (from `actors.l4`, `safe-post.l4`)

- **`SeriesAFinancing`** / **`SeriesAIssue`** - Investment term sheet obligations
- **`EquityFinancingConversion`** - SAFE conversion rules

### Wedding Vows (from `wedding.l4`)

Traditional wedding vows formalized as L4 regulative rules:

- **`weddingceremony`** - The exchange of vows (chained obligations):
  ```
  initial --[Spouse1 MUST `exchange vows`]--> "Spouse2 must `exchange vows` WITHIN 1"
          --[Spouse2 MUST `exchange vows`]--> Fulfilled
  ```
- **`Spouse1lovesSpouse2`** / **`Spouse2lovesSpouse1`** - "To love and to cherish" (mutual)
- **`Spouse1holdsSpouse2`** / **`Spouse2holdsSpouse1`** - "To have and to hold" (mutual)
- **`supportinallcircumstances`** - "For richer or poorer"
- **`careinsicknessandhealth`** - "In sickness and in health"
- **`deathreleasesvows`** - "Till death do us part" (MAY permission)
- **`noabandonment`** / **`fidelity`** - Prohibitions (SHANT)
- **`marriagecontract`** - Combined parallel obligations using RAND. Draws as a single
  `RAND: ALL OF` junction fanning out to the four vows, each with its own lifecycle:
  ```
  initial (RAND: ALL OF) --> "Spouse1 must `love and cherish`" --> ...
                         --> "Spouse1 must `have and hold`"    --> ...
                         --> "Spouse2 must `love and cherish`" --> ...
                         --> "Spouse2 must `have and hold`"    --> ...
  ```

### Regulative AND / OR (from `contracts.l4`)

- **`z`** - `x ROR y`: a `ROR: ONE OF` junction, exactly one branch is taken
- **`a`** - `z RAND z`: a `RAND: ALL OF` junction, every branch is entered

## Visual Conventions

- **Node shapes**:
  - Ellipse: Regular state
  - Double circle: Terminal state (Fulfilled or Breach)
  - Diamond: Junction — a `RAND`/`ROR`/`IF` fan-out point, labelled with the
    keyword that wrote it and what it does: `RAND: ALL OF`, `ROR: ONE OF`,
    `IF: ONE OF`. The keyword is what separates the two `ONE OF`s — an `ROR`
    the obliged party picks from an `IF` the facts pick

- **Node colors**:
  - Light blue (#e8f4fd): Initial state
  - White (#ffffff): Intermediate state
  - Light green (#d4edda): Fulfilled (terminal success)
  - Light red (#f8d7da): Breach (terminal failure)
  - Violet (#e6dcf5): `ALL OF` junction (`RAND`)
  - Amber (#fde8cc): `ONE OF` junction (`ROR`)

- **Edge styles**:
  - Solid green (#28a745): Success/HENCE path
  - Dashed red (#dc3545): LEST path — the reparation arm
  - Solid violet (#6f42c1): branch of an `ALL OF` junction — every branch is entered
  - Dotted amber (#e8850c): branch of a `ONE OF` junction — exactly one branch is entered

- **Edge labels**: `<party> <MODAL> <action> [<deadline>]`, then any of
  `[AFTER <opening>]`, `IF <guard>`, `` the rule binds `<name>` `` and the `EVERY`
  join line, each on a line of its own. A caption is wrapped at 36 characters, so
  where a line breaks inside one of those parts means nothing.

  Two of those parts are worth knowing about:

  - `` the rule binds `amt` `` says the act leaves that name open, so **any**
    value of it discharges the obligation. `MUST payment price` (open) and
    `MUST payment n` (`n MEANS 2`, so only a payment of 2 will do) print exactly
    alike, and this clause is the only thing on the page that separates them. It
    is the sentence `l4 lts` gives for the same act.
  - A branch edge out of a junction carries its guard (`IF price EQUALS 20`) and
    nothing else, because a junction is a control point, not an action. With no
    guard it is blank.

  **Where the place an edge leaves already names the obligation, the edge does not
  say it again** — it carries only what is new along it. So in `aContract` the
  edge under the place `B must payment price WITHIN 3` reads
  `` IF price AT LEAST 20 / the rule binds `price` `` rather than restating the
  obligation. The one exception is an edge that would then be blank: there the
  obligation is restated after all, because an unlabelled arrow says less than a
  repeated one.

  A LEST edge is captioned with what *reaches* it rather than with the rule
  restated, and that differs by modal (`L4.StateGraph.lestArmWording`):

  | Modal | Caption | Reached when |
  |---|---|---|
  | `MUST` / `DO`, with a `WITHIN` | `timeout [30]` | the deadline passes without the act |
  | `MAY`, with a `WITHIN` | `lapses [30]` | the permission goes unexercised; not a failure |
  | `SHANT` | `violation` | **the prohibited act is performed.** For a prohibition it is the deadline passing that means compliance, so this edge has nothing to do with time |
  | `MUST` / `DO` / `MAY`, **no `WITHIN`** | `unreachable: no WITHIN` | never |

  That last row is not a hedge. Three of the four modals reach `LEST` only by
  the deadline running out — the LEST table in
  `doc/reference/regulative/README.md` defines every non-`SHANT` trigger that
  way, and the evaluator agrees: with no `WITHIN`, `Contract4` skips the timing
  step, so `Contract5`, the only frame that consults `lest` on expiry, never
  runs. Measured:

  ```l4
  PARTY Alice MUST pay LEST (PARTY Bob MUST refund WITHIN 5)
  #TRACE ... AT 0 WITH (`WAIT UNTIL` 1000)
  ```
  leaves the *original* obligation outstanding as a residual; Bob's refund never
  becomes current. Add `WITHIN 30` to the same rule and it does. The edge is
  still drawn, because the drafter wrote a `LEST` body and the states extracted
  from it have to hang off something — but it is captioned with the absence
  rather than with an event, because both `timeout` (a deadline the rule never
  set) and `not performed` (a transition the runtime never makes) are assertions
  that do not survive being checked.

  `SHANT` is the exception on the merits: its trigger is the act, not the clock,
  so a prohibition with no `WITHIN` still reaches `LEST` the moment the act is
  performed.

  `timeout` and `lapses` name the deadline that ran out, because the caption is
  otherwise the same on every such edge in the graph and a reader cannot tell
  which clock it belongs to. `violation` never carries one: what reaches it is an
  act. Where two clocks could both take the arm — an act's `WITHIN` and a barrier
  join's `ONCE ALL HAVE WITHIN` — the caption is the bare word, because naming
  either one would be a guess at which fired; both windows are still on the green
  edge, where they are not a claim about that.

## Rendering

To render DOT files manually:
```bash
# SVG (scalable, good for web)
dot -Tsvg noSmoking.dot -o noSmoking.svg

# PNG (raster, good for embedding)
dot -Tpng noSmoking.dot -o noSmoking.png

# PDF (good for printing)
dot -Tpdf noSmoking.dot -o noSmoking.pdf
```

## See Also

- [Contract as Automaton (Flood & Goodenough)](https://www.financialresearch.gov/working-papers/files/OFRwp-2015-04_Contract-as-Automaton-The-Computational-Representation-of-Financial-Agreements.pdf)
- `doc/regulative-spec.org` - L4 regulative rule specification
- `jl4-core/src/L4/StateGraph.hs` - Implementation

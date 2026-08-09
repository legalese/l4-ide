# Reg CF ladder figures

Generated, never hand-drawn. Seven decisions from `../regcf.l4`, four carriers each:

| File         | Carrier                                 | Made by                                      |
| ------------ | --------------------------------------- | -------------------------------------------- |
| `.svg`       | page/print figure, `ink` theme          | `@repo/ladder-svg` `sceneToSvg(scene,"ink")`  |
| `.txt`       | monospace grid — pasteable and diffable | `@repo/ladder-core` `sceneToAscii`           |
| `.mmd`       | Mermaid `railroad-beta`                 | `@repo/ladder-core` `toMermaidRailroad`      |
| `.sentences` | **readable prose** — one per way to satisfy | `@repo/ladder-core` `expandSentences`     |

**The four are not interchangeable**, and since 2026-08-09 this corpus demonstrates it
again. `toMermaidRailroad` deliberately drops medial inert glue inside
an `OR` (a railroad `choice` branch is a live path, and prose-as-branch would make the
disjunction trivially satisfiable — correct, and documented in `mermaid.ts`). Until the
enumeration-label ruling, `transfer falls within an exception in Rule 501(a)` put each
caption on its own rung, so `regcf-resale-exceptions.mmd` carried the chapeau and
**none** of limbs (2)(3)(4). The labels now ride their own nodes via `...`, so each is
inside a `sequence(terminal("(n)"), nonterminal(…))` branch and all four survive — but
`regcf-resale-limb-4`, added when Rule 501(a)(4) was decomposed, has a caption between
two live rungs and its `.mmd` drops it (see §4). Do not treat one carrier
as a stand-in for another — see §3 and §4.

The `.sentences` carrier is a **disjunction** view and degrades on conjunctions:
`regcf-rule-100b.sentences` is six clean numbered limbs, while
`regcf-exemption.sentences` is one sentence with all five conjuncts run together,
because an `And` cross-joins into a single product. Use the sentences for OR-rooted
rules and the ladder for AND-rooted ones.

## Regenerating

```sh
cd ts-shared/ladder-svg
npm run demo:regcf                 # spawns jl4-lsp via `cabal run`
# or, against a binary you already built:
JL4_LSP_CMD=…/jl4-lsp npm run demo:regcf
```

The generator is `ts-shared/ladder-svg/demo/regcf.ts`. Unlike `demo/s415.ts` and
`demo/charities-a3.ts` — which hand-build their `IRExpr` in TypeScript and whose
labels are, in their own words, "the statutory phrases, **trimmed for the page**" —
this one reads the corpus through the LSP (`textDocument/codeLens` →
`l4.visualize` → `RenderAsLadderInfo.funDecl` → `fromVizFunDecl` → `layout`).
Nothing is retyped, so nothing can drift. That is the point: the competitive
thesis is single-sourcing, and a figure a human transcribed is a second source.
It also means these figures are **untrimmed**, which is why two of the six are
too wide to put on a page — see below.

The generator fails loudly (exit 1) if a named decision is not found, so renaming
a decision in `regcf.l4` breaks the build rather than silently dropping a figure.

### …but only if someone runs it

"Nothing is retyped, so nothing can drift" is true of the **generator** and was, until
2026-07-27, false of the twenty-four committed **files**. `demo:regcf` needs a running
`jl4-lsp`, so it is not in `turbo.json` and CI never ran it; unlike the DMN and BPMN
goldens, which `cabal test` re-derives from the same corpus on every run, these could
have sat stale beside a renamed corpus indefinitely.

`ts-shared/ladder-svg/test/regcf-figures.test.ts` closes the realistic half of that
hole **without** the LSP: every boxed leaf label in every `.txt`, and every
`.sentences` title, must still be findable in `regcf.l4`. It runs under
`turbo run test`. It is deliberately **one-directional** — a leaf *added* to the L4 and
absent from a figure still passes, and layout is not checked at all. Run
`demo:regcf` for the real thing.

## What was generated

| Slug                         | Decision (`regcf.l4`)                                       | Scene          | Longest leaf |
| ---------------------------- | ----------------------------------------------------------- | -------------- | ------------ |
| `regcf-rule-100b`            | `issuer is excluded by Rule 100(b)` (:320)                  | 912 × 571      | 78 ch        |
| `regcf-reporting-terminates` | `ongoing reporting obligation may terminate` (:694)         | 1006 × 505     | 90 ch        |
| `regcf-transfer-permitted`   | `transfer is permitted` (:849)                              | 846 × 269      | 63 ch        |
| `regcf-intermediary`         | `intermediary obligations are met` (:591)                   | 2054 × 180     | 75 ch        |
| `regcf-resale-exceptions`    | `transfer falls within an exception in Rule 501(a)` (:839)  | 1074 × 440     | 87 ch        |
| `regcf-resale-limb-4`        | `(a)(4) — a family or trust transferee…` (:825)             | 1147 × 572     | 108 ch       |
| `regcf-exemption`            | `the transaction qualifies…` (:878)                         | **3027 × 185** | 61 ch        |

Every scene size in that table is the emitted SVG's `viewBox`, and every line reference
is the line of the decision's `MEANS`/`DECIDE` head in `regcf.l4` as it stands in this
commit. Both were re-checked on 2026-08-09 by reading the SVGs and the corpus, not
carried over from a previous run.

`regcf-resale-limb-4` joined the set on 2026-08-09, when Rule 501(a)(4) stopped being
one ~300-character boolean and became six fields under a decision of their own. Note
what happened to the row above it: `regcf-resale-exceptions` went from 2751 × 440 to
1074 × 440 and from a 301-character leaf to an 87-character one. It is no longer the
widest thing in the corpus, and the defect recorded in §2 below is no longer this
figure's.

Nothing regenerates these numbers, and they have now drifted twice, so re-derive them
whenever you regenerate the figures — and re-derive them **last**, after the corpus has
stopped moving. The refs this table carried before the enumeration-label ruling read
`:211 :550 :615 :452 :601 :643` against a corpus whose actual lines were
`303 690 755 581 741 783`. The first attempt at repairing them, made in this same
branch, replaced them with `297 671 731 568 721 759` — measured correctly but *before*
the last twelve lines of corpus edits landed above them, so every one was uniformly
twelve short. Measuring early is the failure mode here, not measuring wrongly.

The corpus has **43** visualisable decisions in total (every boolean-returning
`DECIDE`/`MEANS`; the LSP code lens does not require `@export`) — the figure
`demo:regcf` prints on every run, re-read 2026-08-09; the **34** this line carried
before was measured when the corpus was smaller and nothing regenerated it. These seven
were picked for what they demonstrate, not because the rest fail.

## Three of these figures are wrong for a page, and here is why

Reported rather than fixed, because fixing them means either editing the corpus —
which would put the trimming back — or changing the layout engine.

### 1. An `AND` is a ribbon (`regcf-exemption`, `regcf-intermediary`)

In ladder logic a conjunction is a **series** circuit, so BBE lays an `AND` out
left to right, and the scene width is the sum of its children's widths. Nothing
wraps. `the transaction qualifies for the section 4(a)(6) exemption` is an `AND`
of five, each child a call whose printed form runs 40–60 characters, preceded by
Rule 100(a)'s 118-character chapeau **riding the wire** (inert prose in an `AND`
is drawn on the line, not as a heading). Result: **3027 × 185** — a strip 16×
wider than it is tall. It is a correct diagram and an unusable figure.

This is the root/index picture, so it is the one a reader most wants. Today it
needs `scale` modes or auto-folding (DESIGN §16), or an `orient: "TB"` for
conjunctions. Neither exists.

### 2. Leaf labels do not wrap — MITIGATED AT THE SOURCE 2026-08-09

`layout.ts` sizes a leaf as `caretW + tm.width(label, FONT) + 2*PAD_X`. There is
no wrap and no ellipsis. Only **inert** prose wraps, and only to two balanced lines
(`balanceTwoLines`, gated at `STRADDLE_MIN_WIDTH`), and only when it is riding a
wire; an `OR` heading is a single line however long. **The layout mechanism is
unchanged.**

Until 2026-08-09 this section's exhibit was `regcf-resale-exceptions`, whose Rule
501(a)(4) field name was 291 characters in the corpus — 304 printed, roughly 2380 px
wide on its own. That leaf is gone: the limb is now six fields under
`regcf-resale-limb-4`, and the longest leaf anywhere in these figures is 108
characters. What removed it was not a wrapping feature but a **decomposition** — the
field carried four statutory alternatives inside one name, which is the Oakhurst defect
the grouping tutorial warns against, and the width was the symptom rather than the
disease. A field name that is genuinely one long sentence would still overflow.

### 3. A leading run of inert prose is merged into ONE heading — REPAIRED AT THE SOURCE 2026-08-03

`leadingInert` still collects the whole leading run of `InertE` children and joins
them with a space (`layout.ts:349-355`). Until 2026-08-03 the corpus interleaved each
paragraph's caption with its operative limb, one `..` rung each:

```
"unless such securities are transferred:"
"(1) To the issuer of the securities;"        <- caption, its own rung
transfer's `to the issuer of the securities`
"(2) To an accredited investor;"              <- caption, its own rung
transfer's `to an accredited investor`
…
```

so the chapeau and caption **(1)** both fell in the leading run and the group heading
read `unless such securities are transferred: (1) To the issuer of the securities;` as
one line, while (2), (3) and (4) sat over their own rungs. The figure was asymmetric,
and a reader took "(1) To the issuer of the securities" for part of the preamble.

The enumeration-label ruling removed the cause rather than the symptom. The caption no
longer restates the field beside it, and what survives of it rides its own node:

```
    ..  "(1)" ... transfer's `to the issuer of the securities`
```

so the leading run is the chapeau alone and each label sits on the wire into its own
rung. Verify in `regcf-resale-exceptions.svg`: four italic `<text>` prims reading
`(1)` `(2)` `(3)` `(4)`, and one heading `<text>` at `y=87.8` carrying the chapeau and
nothing else. **The layout mechanism is unchanged** — feed it two leading inert strings
and it will still merge them.

### 4. Mermaid drops the medial captions altogether — no longer triggered here

`toMermaidRailroad` hoists the leading inert run in front of the fan and
**deliberately discards medial inert glue** in an `OR` — because every child of a
railroad `choice` is a live branch, and emitting prose as a branch would add a
free pass-through that makes the disjunction trivially satisfiable. The reasoning
is right and it is documented in `mermaid.ts`. Until 2026-08-03 the consequence for
this corpus was that `regcf-resale-exceptions.mmd` carried the merged "chapeau + (1)"
preamble and **none** of (2), (3) or (4).

Once each label rides its node, there is no medial inert glue left to discard: the
`.mmd` now emits `choice(sequence(terminal("(1)"), nonterminal(…)), …)` and carries all
four. **The discard is still there** and will still bite any rule that puts prose
between two live `..` rungs, so the carriers remain non-interchangeable for
inert-style sources.

**And it bit again on 2026-08-09, on the new figure.** `regcf-resale-limb-4` has two
captioned groups — the transferee half and the circumstance half — and the second
caption sits between two live rungs, which is exactly the shape this discard is about.
`regcf-resale-limb-4.mmd` therefore carries `(4) To a member of the family …` as its
leading terminal and **drops** `or in connection with the death or divorce of the
purchaser or other similar circumstance.` altogether, while the `.svg`, the `.txt` and
the `.sentences` all carry it — the ASCII puts it on the wire at precisely the boundary
between the third and fourth rungs, which is where it belongs. This is not a regression
and not a bug to file: it is the documented trade, observed on a fresh case, and it is
the reason the four carriers are shipped rather than one.

## What is right about them

`regcf-rule-100b` is the flagship and needs no trimming at all: the Rule 100(b)
chapeau becomes the group heading and the six exclusion limbs become six rungs,
in the CFR's own order, at 912 × 571 — a page. It is the README §3.6 finding
drawn: limb **(b)(5)**, which the mirrored wiki page omits, is a rung like any
other. `regcf-reporting-terminates` does the same for §3.7's two missing
termination conditions.

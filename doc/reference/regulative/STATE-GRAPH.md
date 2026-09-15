# The state graph: a map of a regulative rule

A regulative rule — `PARTY Alice MUST pay WITHIN 30 HENCE … LEST …` — describes a small journey.
It starts somewhere, an action or a missed deadline moves it somewhere else, and eventually it
arrives at `FULFILLED` or `BREACH`. The **state graph** is a map of that journey: every place the
rule can be, drawn as a circle, and every action or missed deadline that moves it, drawn as an
arrow.

This page is about how to get that map, from the editor and from the command line, and — just as
important — what the map does and does not tell you.

**Example file:** [every-run-example.l4](every-run-example.l4)

## Getting the map in the editor

Open any `.l4` file that has a regulative rule in it. Just above the rule, in small grey text, the
editor offers **Show state graph**. This works the same way in the L4 extension for Visual Studio
Code and in the web editor at jl4.legalese.com.

```l4
GIVETH A DEONTIC Actor Action
`the tenancy` MEANS                        -- ← "Show state graph" appears above this rule
    EVERY Tenant t IN tenants
        MUST   Sign (EXACTLY t)
        WITHIN 14
        ONCE   ALL HAVE
        HENCE  (PARTY theLandlord MUST Deliver (EXACTLY theLandlord) WITHIN 5)
        LEST   BREACH
```

Click it and a pane opens beside the editor with the map for that one rule.

You may already know the editor's other small grey offer, **Show decision graph**, which draws a
yes-or-no rule as a ladder. The two never appear on the same rule: a rule is either a yes-or-no
question or a set of obligations, and each offer knows which it is for. If you see neither above a
rule, the rule is one the tools cannot yet draw — see the limits below.

**What the pane shows today is the map's source, not the picture.** The map is written in a small
text language called DOT, the input format of a widely used drawing tool called GraphViz. The pane
shows that text, with a **Copy DOT** button. Paste it into any GraphViz renderer — the `dot`
program, if you have GraphViz installed, or one of the many online viewers — to see the picture.
Drawing the picture inside the editor is the next step, and it has not been built; until it is,
the pane is honest about being the source.

The pane is a snapshot. It does not redraw itself as you edit; click **Show state graph** again to
see the map for the rule as it now stands.

## Getting the map from the command line

```bash
l4 state-graph mycontract.l4
```

prints the map of **every** regulative rule in the file, one after another, in the same DOT text.
Pipe it into GraphViz to get a picture:

```bash
l4 state-graph mycontract.l4 | dot -Tsvg -o mycontract.svg
```

The editor's offer and the command line produce the same map for the same rule.

## Reading the map

Take `the tenancy` above. Its map has four places and four arrows:

- **initial**, where the rule starts;
- an arrow out of it labelled `EVERY Tenant t IN tenants MUST Sign ... [14]` and, on a second line,
  `ONCE ALL HAVE` — the tenants signing, all of them, within 14 days — leading to
- a place labelled **theLandlord must Deliver ...**, the landlord's turn, with an arrow labelled
  `theLandlord MUST Deliver ... [5]` leading to
- **Fulfilled**, drawn with a double border, and from both of the earlier places a red dashed
  arrow labelled `timeout` leading to
- **Breach**, also double-bordered.

So the conventions are:

| you see                       | it means                                                                                                                                                                                     |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| a circle                      | a place the rule can be: somebody owes something, or it is over                                                                                                                              |
| a double-bordered circle      | it is over — `Fulfilled` (green) or `Breach` (red)                                                                                                                                           |
| a solid green arrow           | the action was taken, and this is where the `HENCE` goes                                                                                                                                     |
| a red dashed arrow            | the `LEST` path, captioned by what reaches it: `timeout` for a `MUST` whose deadline passed, `violation` for a `SHANT` whose forbidden thing was done, `lapses` for a `MAY` nobody exercised |
| `[14]` on an arrow            | the `WITHIN` deadline                                                                                                                                                                        |
| `ONCE ALL HAVE` / `UPON EACH` | for an `EVERY` rule, whether the next step waits for the whole group or fires for each member                                                                                                |
| a diamond                     | a fork: `RAND` (every branch runs) or `ROR` (exactly one does), or an `IF` choosing between rules                                                                                            |

## What the map does not say

The map is deliberately narrow, and the narrowness is easy to miss because the picture looks
complete.

**It shows where the rule can go, not where it is.** Nothing on the map says which place the rule
is in _now_, for a particular contract on a particular day, or who is currently on the hook. That
question — "given what has happened so far, what is outstanding, and for whom?" — is answered by
running the rule with `#TRACE` (see [the regulative reference](README.md#testing-with-trace)), not
by the map. A map with every road on it is not a map with a "you are here" dot, and this one has no
dot.

**It shows one rule at a time.** A `HENCE` or `LEST` that hands over to another named rule is drawn
as an arrow into a place labelled `next`, and stops there. To see where that rule goes, open its
own map.

**A `MAY` with no `LEST` has no red arrow.** A permission nobody exercises simply ends, so the
default there is `FULFILLED`, and the map draws only the green arrow. A `MAY` with an explicit
`LEST` gets a red arrow captioned `lapses`.

**An `EVERY` is one arrow, not one per member.** `EVERY Tenant t IN tenants MUST Sign` is drawn as
a single arrow labelled with the quantifier, because who the tenants are is only known when the
rule runs. The `ONCE ALL HAVE` or `UPON EACH` line on the arrow says whether the next step waits
for all of them or fires for each, which is the difference that matters; it does not draw three
tenants.

**Conditions are labels, not logic.** A `PROVIDED` guard, or the `IF` that chooses between two
rules, appears as text on an arrow. The map does not work out when the condition holds.

**Some rules have no map yet.** A rule whose body is not a `PARTY … MUST/MAY/SHANT …`, `RAND`,
`ROR`, or an `IF` choosing between those — for instance one that only refers to another rule by
name — is not drawn, and the editor offers nothing above it.

## Related pages

- [Regulative Rule Keywords](README.md) — `HENCE`, `LEST`, `WITHIN`, `RAND`, `ROR`, and `#TRACE`
- [EVERY](EVERY.md) — obligations on every member of a group, and the `ONCE … HAVE` / `UPON EACH`
  join the map labels
- [DMN and BPMN](../../exports/dmn-bpmn.md) — the same state graph, exported as a BPMN process
  diagram for tools that read that format
- [`l4` command line](../../tutorials/getting-started/l4-cli.md) — the `state-graph` verb among
  the others

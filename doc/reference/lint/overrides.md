# Does the encoding keep its "subject to"? `l4 lint`

A statute orders its own provisions with small phrases.
"**Subject to section 3**, a licensee may trade between 8am and 10pm" says that section 3 wins if the two ever disagree.
"**Notwithstanding section 7**, the Director may grant an extension" says the opposite way round: this provision wins over section 7.
Lawyers call these _override clauses_; the same job is done by "despite" and by "except as provided in".

An encoding that keeps the words but drops the effect is a quiet kind of wrong answer.
The decision for section 5 reads, in its own text, "Subject to section 3", and then answers `TRUE` for a shop 50 metres from a school, because nothing in it ever asks section 3 anything.
Nothing fails.
The file type-checks, every test that does not happen to hit that case passes, and a reader skimming the quoted words is reassured.

`l4 lint` looks for exactly this.
It reads the override phrases a decision carries, finds the provision each one names, and checks that the decision actually _uses_ the decision that encodes that provision.
It reports the ones that do not.

**Status (2026-10-30):** built, as `l4 lint FILE...`.
The surface (a new verb, advisory by default) is **assumed, not ruled**: [SUBJECT-TO-NOTWITHSTANDING-SPEC §12.1](../../../specs/todo/SUBJECT-TO-NOTWITHSTANDING-SPEC.md) rules that the first build is a lint over the existing calls and says nothing about how it is invoked.
Meng's note at the head of §12.1 applies here too: this is temporary, to be revisited when the spec's keywords are built.

## A worked example

**Example files:** [overrides-forgotten.l4](overrides-forgotten.l4) and [overrides-honoured.l4](overrides-honoured.l4)

A made-up Licensing Act has two sections.

> **s 3.** A licensee shall not trade within 100 metres of a school.
> **s 5.** Subject to section 3, a licensee may trade between 8am and 10pm.

Here is an encoding that forgets.
Section 5 quotes its own opening words, and then never mentions section 3 again:

```l4
@ref Licensing Act s 5 — "Subject to section 3, a licensee may trade between 8am and 10pm."
GIVEN hour IS A NUMBER, metres IS A NUMBER
GIVETH A BOOLEAN
`s 5 — a licensee may trade` hour metres MEANS
        "Subject to section 3,"
    ... "a licensee may trade between 8am and 10pm."
    ... hour AT LEAST 8 AND hour AT MOST 22
```

Ask it about noon, 50 metres from a school (`#EVAL `s 5 — a licensee may trade` 12 50`):

```
Result:
  TRUE
```

Section 3 forbids that, and the decision says yes.
Now the lint:

```bash
l4 lint overrides-forgotten.l4
```

```
overrides-forgotten.l4:18: missing-conjunct: `s 5 — a licensee may trade`
    says "subject to section 3" (read in @ref, text)
    but its body reaches none of: `s 3 — the premises are within 100 metres of a school`

l4 lint: 1 file; findings: 1 missing-conjunct; set aside: none
```

The fix is the one the corpus already uses where it gets this right: have section 5 ask section 3, and negate the answer, because section 5 may apply only where section 3's bar does not.

```l4
    ... NOT (`s 3 — the premises are within 100 metres of a school` metres)
```

Run on the corrected file, [overrides-honoured.l4](overrides-honoured.l4), the same question answers `FALSE` for 50 metres and `TRUE` for 500, and `l4 lint --all` lists the phrase as wired rather than reporting it.

## What it reads

For every decision in the file, the lint reads three places where the statute's own words are kept:

1. **The `@ref` citations** written above the decision.
2. **The decision's name**, such as `` `s 8(3) — probate may be granted, subject to section 6` ``.
3. **The quoted text in its body**: the words in quotation marks that [inert style](../../concepts/reviewing/reviewing-encoded-law.md) keeps verbatim beside the logic, such as `"Subject to section 3,"` above.

The third is an extension of the ruling, which names only the first two.
It is there because the inert style keeps the statute's words in the body: of the 11 mentions the lint finds in the encodings under `jl4/examples/canon` (measured 2026-10-30), 6 are read from the body text and nowhere else.

It does **not** read comments (the lines beginning `--`).
A comment is the encoder talking to the next encoder; it makes no commitment that the code could break.

A phrase counts only when it is followed by a provision number: "subject to section 6", "despite subsection (8)", "notwithstanding anything in section 18(g)", "except as provided in article 4".
The same words with no provision behind them are ordinary English, and the lint says nothing about them: "subject to tax", "subject to the process of the court", "despite reasonable efforts".

To find the decision that encodes a provision, it reads the **name**.
A decision is for section 6(1) if its name starts `s 6(1)`, `section 6(1)`, and likewise `reg 12`, `Art 4`, `Article 4`, `clause 5` or `Sch 2`.
Name your decisions that way and the lint can follow them; if you do not, it has nothing to follow.

## Reading the report

Only the first two lines of this table are findings.
The rest are shown with `--all`, and counted at the foot of every run.

| what the report says  | what it means                                                                                                                                                                                                                                                                       |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `missing-conjunct`    | **Finding.** "Subject to X" is in the decision's words. Decisions for X exist in this file. This decision reaches none of them, and none of them reaches it.                                                                                                                        |
| `override-unwired`    | **Finding.** "Notwithstanding X" (or "despite X") is in the decision's words. Decisions for X exist. Neither side calls the other, and no third decision calls both.                                                                                                                |
| `wired (…)`           | The edge is there: a direct call, a call through a helper decision, a call the other way round (the provision being overridden calls the prevailing one), or a third decision that calls both.                                                                                      |
| `target-not-encoded`  | No decision in this file is named for X, so there was nothing to call. Usually a choice of scope. Not a finding.                                                                                                                                                                    |
| `citation-only`       | The decision's whole body is one quotation of the statute, with no logic around it. It computes nothing, so it cannot answer where the override should have changed the answer. Not a finding. A run of quotations joined by `...` is not this: it answers `TRUE`, and is reported. |
| `self-reference`      | X is the provision this decision itself encodes ("this section is subject to section 114" inside section 114(4)).                                                                                                                                                                   |
| `unresolved-relative` | "Subsection (8)" or "paragraph (a)" of a decision whose name carries no provision number, so there is no section to read it against. The lint does not guess.                                                                                                                       |
| `external-instrument` | The provision is another instrument's ("section 15(d) of the Exchange Act"). Its decision, if there is one, is in another file.                                                                                                                                                     |
| `range`               | "Sections 6 to 8". Which of them the author meant is not the lint's to guess.                                                                                                                                                                                                       |
| `open-class`          | "Notwithstanding any other provision of this Act". No provision is named, so no call could be checked. [SUBJECT-TO-NOTWITHSTANDING-SPEC §12.1](../../../specs/todo/SUBJECT-TO-NOTWITHSTANDING-SPEC.md) records that no static check reaches these.                                  |

"Subject to" and "except as provided in" look forward: the provision yields, so its own body should ask the other.
"Notwithstanding" and "despite" look back: the provision prevails.
For those, the edge can sit on either side.
Statute's own drafting leaves it open, and so does the lint: the overridden provision may call the prevailing one, the prevailing one may consult the overridden one, or a third decision may call both and decide.

## Options

| option     | what it does                                                                                                  |
| ---------- | ------------------------------------------------------------------------------------------------------------- |
| `--all`    | list every mention found, not only the findings                                                               |
| `--json`   | print one JSON array of every mention (file, line, decision, phrase, target, where read, verdict, candidates) |
| `--strict` | exit 1 when there is a finding. Without it the exit status is 0 whenever the lint ran, whatever it found.     |

A file that does not type-check cannot be linted; the command says so and exits 1 with or without `--strict`.

## What it cannot catch

- **It checks that a call exists, not that it is right.** `NOT (s 6(1) …)` and a bare `s 6(1) …` both satisfy "subject to section 6". Whether the call has the right sign, or sits in a branch that ever matters, is for a reader.
- **It cannot tell what kind of override it is.** "Subject to" can mean a priority, a carve-out, a proviso or a saving. All look the same at the call. [SUBJECT-TO-NOTWITHSTANDING-SPEC §12.2](../../../specs/todo/SUBJECT-TO-NOTWITHSTANDING-SPEC.md) says that no check in the tree can classify them yet.
- **It judges only the file it is given.** The decisions it knows are the ones in that file. A call to a decision imported from another file counts if the imported decision is named by its provision; whether the other file really holds the target is not checked.
- **A decision with a different shape of name is invisible to it.** A decision called `` `the grant is within the limit` `` may encode section 6 perfectly; the lint will not know. A call through such a helper is followed only if the helper is in the same file.
- **It cannot reach the shapes §12.1 calls out of reach of any static check.** "Notwithstanding any other provision" names no target; a comparative override is not an edge.
- **Two instruments in one file can be confused.** If a file encodes two Acts that both have a section 6, a call to either satisfies "subject to section 6".
- **A paragraph is not resolved inside a section.** "Paragraph (a)" of a section is relative to a subsection the lint does not track. In an article, regulation, rule or clause, "paragraph (2)" is read as that provision's own subdivision.
- **It can raise a finding that is not a defect.** The priority may be settled by a decision in another file that calls both provisions, or the other provision's test may be written out inside this decision instead of called. The lint sees neither; the finding is a prompt to look, not a verdict.
- **A clean report is not a faithful encoding.** It says the encoding is not silently dropping the effect of the phrases it can see. Whether the encoding says what the law says remains the reviewer's judgement.

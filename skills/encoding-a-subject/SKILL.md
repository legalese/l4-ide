---
name: encoding-a-subject
description: Encodes a whole body of law — an Act, a set of regulations, a fee schedule, a standard-form contract — into L4 from its source text, and deposits the result in legalese/canon. Covers the work around the L4 itself — gathering the sources, writing the brief, a coverage table so nothing is silently skipped, nouns before rules, tests taken from the source, a self-check that reads diagnostics rather than exit codes, an independent test pass, NOTES.md, and the canon layout. Use when the user asks to encode, formalise or translate an entire statute, regulation or contract into L4, to "do an encoding" of something for canon, or to write a brief for one. For L4 syntax and drafting idioms it hands off to `writing-l4-rules`.
---

# Encoding a body of law in L4

This skill is the workflow for producing a complete, reviewable L4 encoding of one body of law, and filing it in [`legalese/canon`](https://github.com/legalese/canon), the corpus repository.
It sits between two other things:

- **[`writing-l4-rules`](../writing-l4-rules/SKILL.md)** teaches the language: syntax, `IS` / `MEANS` / `IF`, regulative rules, dates, and the drafting idioms for statutory text (`references/drafting-patterns.md` and `references/source-patterns/` there).
  Everything in this skill that says "encode" means "encode the way that skill says".
- **The `go` pipeline** in the `legalese/l4-ide` repository (the `go.sh` driver under `etc/go/`, and the `running-the-l4-pipeline` skill that lives only there) takes a _finished_ encoding and checks it, projects it to DMN, BPMN, a web wizard and so on, and writes a conversion report.
  It does not write L4.
  You do not need it to produce a good encoding, and nothing in this skill depends on it.

## What makes the difference

Measured on 2026-09-21 on an Israeli licensing Law and its fee regulations (the THERMOSTAT comparison): **one agent working alone from a good brief produced encodings as faithful as a pipeline of thirteen or fourteen agents, at about a tenth of the cost** — $15–21 against about $172.
The pipeline's extra stages bought no correct answer the single agent missed.
The one stage that earned its keep was an **independent test author**, who wrote expectations from the sources before reading the encoding, and flagged the one reading the comparison scored as a departure from the source.

So the default this skill teaches is: **one session, a brief that pins everything, the strongest model you have at high effort, and an independent test pass at the end.**
Most of the quality comes from the brief.

## The workflow

### 0. Before you start

- **Get a current `l4`.** Install it with this plugin's `scripts/install-l4.sh`, which fetches the release it was built against and checks its digest, or download an archive from [`legalese/prereleases`](https://github.com/legalese/prereleases/releases) — each carries a `BUILD-INFO.txt` naming the commit it was built from.
  `l4` has no `--version` flag, so that file is how you know what you are running.
  The authoring skill documents the language as it is on `unstable`; **a binary older than the skill rejects constructs the skill tells you exist**, and the symptom is a parse error that reads like your mistake.
  Measured: `@lang en`, which the authoring skill documents, is a parse error at line 1 on the 7 September 2026 prerelease.
  Note that `install-l4.sh` links `~/.local/bin/l4`, replacing whatever was there.
- **Leave `JL4_LIBRARY_PATH` unset.** The standard library is compiled into the binary and always matches it; pointing the variable at a newer library produces a cascade of `could not find a definition` errors.
- **Use the strongest model available, at high effort.** The comparison above ran every arm on Opus at high effort.
- **Clone `legalese/canon`** and check out your drafts branch (step 10).

### 1. Gather the sources, with provenance

Put every source file in one `inputs/` directory and record, for each: where it came from (URL), when you fetched it, its sha256, and whether it is **authoritative** or an **aid** (an unofficial consolidation, a translation, a commentary).

- **Fetch the instrument it is made under, too.** A regulation is made under an Act; a statutory instrument under a parent Act.
  You cannot tell whether a word in the subject is compelled or chosen without reading the text above it.
  The worked case: SEC Regulation Crowdfunding computes an investment limit from "the greater of" income or net worth; the statute it implements says only "income or net worth … as applicable", and the SEC chose "lesser of" in 2015 and reversed itself in 2021.
  Read alone, "greater of" looks like a command. It is a reversible policy choice.
- **Look for the versions that matter.** A draft and the text as made; the text before and after an amendment. Each is a **vintage**, and each is in scope as its own answer.
- **Record the in-force date** the text is stated at — the consolidation banner, or the gazette date.
- **Quote from the fetched text, mechanically.** Every string you later put in the encoding should be copied from these files, never reconstructed from memory.

### 2. Write the brief

Copy [`assets/brief-template.md`](assets/brief-template.md) and fill in every ⟨…⟩.
[`references/example-brief.md`](references/example-brief.md) is a real one, the brief behind the comparison above.

The brief pins **scope** (which provisions, by number), **deliverables**, and **the rules that matter**.
Write it even when you are the encoder: it is what a reviewer reads to learn what you were trying to do, and what the independent test author in step 8 works from.
If you find yourself wanting to tell the encoder something that is not in the brief, put it in the brief.

### 3. Enumerate before you encode

Before writing a line of L4, list **every provision in scope** in a coverage table in `NOTES.md`: its number as the source writes it, its heading, and a disposition — `encoded`, `inert` (quoted but not operative, e.g. a purpose clause), `out-of-scope` (with a reason of real length), or `deferred`.
Everything starts `deferred`; move each row as you land it.

**Why this is not bookkeeping:** `l4 check` proves a module is valid L4. A module that encodes Chapter 1 and stops passes exactly as cleanly as one that encodes the whole Act, and so does every test you wrote for Chapter 1.
Under-coverage is the one large defect nothing else detects. The table is the detector, and an encoding with rows still `deferred` says so out loud.

### 4. Nouns first: one shared domain module

Read the whole source, then write **one module of nouns only**: the entities, their fields, the enumerations — `DECLARE` and nothing else. No rules, no `#EVAL`.
Every other module imports it.

The membership test: **could a witness of ordinary competence testify to this fact, or does answering it require reading the Act?** Only the first kind belongs here.
"The will was signed at the foot or end" is a fact a witness can testify to; whether that makes the will valid is a rule, and belongs with the section that says so.

Doing this first matters because two chapters written separately will each invent their own record for the same person or thing, and the difference only surfaces when the modules have to compose — by which time one of them gets rewritten.

### 5. Encode the rules against those nouns

Now encode, a section or a unit at a time, moving each coverage row as you go.
How to write each construct is [`writing-l4-rules`](../writing-l4-rules/SKILL.md)'s job; read its `references/drafting-patterns.md` and the `references/source-patterns/` pages before you start, not when you get stuck.
The rules that decide whether a reviewer can trust the result:

- **Isomorphic.** Someone holding the source beside your module can check it provision by provision. One source provision → one recognisable place in the L4, with the source's numbering and a citation (`@ref` or a comment) on every rule.
- **Vintages are inputs, never merged.** Where the law exists in two versions, use the rule-version (rule-effective-time) mechanism in `writing-l4-rules` (`references/source-patterns/04-dates-and-periods.md`), or take the vintage as an explicit input. A vintage that is silent on something answers with silence — never with a number borrowed from another vintage.
- **`REFUSE "…"` where the sources do not answer** — never `FALSE`, `0` or a plausible default. `MAYBE` / `NOTHING` where the source itself names an absent case. See `references/source-patterns/11-when-the-encoding-cannot-answer.md`.
  Do not invent your own three-valued logic (`Established` / `Rejected` / `Unresolved` enums threaded through every rule): the language already has these, and a home-made version is one more thing a reviewer must learn before they can read a single rule.
- **Inputs as `GIVEN`**, threading a record where there are many facts. `ASSUME` is deprecated for inputs.
- **`BRANCH IF … IF … OTHERWISE`, not chains of `ELSE IF`.**
- **Several modules, not one.** A 2,000-line single file cannot be reviewed section by section. Split along the source's own structure: the domain module, then one module per Part or topic, then the tests.

### 6. Tests: from the source, never from the code

Write a tests module whose expected values come **from the source**: worked examples the source or the regulator prints, scenarios on both sides of every threshold and every date edge, one per route through each schedule, and — for a law with vintages — the same scenario asserted against each vintage.

- **A failing assertion is a finding.** Never edit an expected value until it matches what the code computed. If the source and the encoding disagree, one of them is wrong, and which one is the interesting question.
- **Some tests are meant to fail.** When you transcribe a table of expectations that the law as enacted does not meet (a draft's test cases run against the final text), keep those in their own file, say how many are expected to fail, and count them. That file doubles as proof your harness can fail.
- Test count is not a quality measure. In the comparison above, assertion counts ran from 149 to 871, and the encoding with the most was the one that departed from the source.

### 7. The self-check loop — read the diagnostics

**`l4 run` exits 0 when an `#ASSERT` fails.** The failure is a `DiagnosticSeverity_Error` line whose message is `assertion failed`. A run that "passed" by exit code can be carrying failed assertions.

Copy [`assets/check.sh`](assets/check.sh) into the encoding directory. It runs every module and prints, per module, errors, assertions satisfied, and assertions failed, and exits non-zero on any error or failed assertion:

```bash
L4=/path/to/l4 ./check.sh
```

Run it after every unit you land. Report the numbers it prints, never "it's green".

### 8. The independent test pass (recommended)

Start a **fresh session** — one that has not seen your encoding — give it the brief and the sources, and have it decide what the answers should be **before** it opens the encoding. Only then does it read the encoding for names and write `tests-independent.l4` asserting those answers.
Every assertion it leaves failing is a disagreement between two readings of the source, and each one is worth your time.
Prompts for this, and for an optional adversarial reviewer, are in [`references/second-pass.md`](references/second-pass.md).

### 9. Write NOTES.md

A reviewer reads this first. It carries:

1. **What is encoded and what is not**, in a paragraph — the scope, stated as provisions.
2. **The coverage table** from step 3, with no row left `deferred` (or with the reason if some are).
3. **The fork register**: every ambiguity you met — the readings you saw, the one you took, and why, with the text that licenses each reading.
   A fork resolved by a court or the regulator says who settled it. "No ambiguities found" is a claim a reviewer will not believe; if you found none, say where you looked.
4. **An answer table** where the subject has one — the fee for each service in each vintage, the threshold for each grade — with the provision cited per cell.
5. **What `check.sh` prints**, and which failing assertions are expected, and why.
6. **Open questions** for a domain expert.

### 10. Deposit it in canon

[`references/canon-deposit.md`](references/canon-deposit.md) has the layout, the two descriptor files, and the commands.
In short: your own `<github-username>/drafts` branch, never `main`; `subjects/<jurisdiction>/<slug>/` for the law and `encodings/<row>/` for your encoding of it.

### 11. Hand it over

Mark the encoding `draft` in `encoding.json` and say, in its `not_reviewed` note, that no domain expert has read it against the source yet.
The review that turns `draft` into `reviewed` is a human who knows the law reading the modules section by section against the source — the pipeline calls it HG1 — and nothing automated substitutes for it.

## The failures seen most often

Each of these is a way for an encoding to look finished and not be:

| failure                                                      | what prevents it                                         |
| ------------------------------------------------------------ | -------------------------------------------------------- |
| a fifth of the Act encoded, every check green                | the coverage table (step 3)                              |
| the same person declared three ways in three chapters        | nouns first (step 4)                                     |
| one 2,000-line module nobody can review against the source   | split along the source's structure (step 5)              |
| a home-made `Unresolved` value instead of `REFUSE` / `MAYBE` | step 5, and `writing-l4-rules`' page 11                  |
| a number from the amended text answering for the original    | vintages as inputs (step 5)                              |
| tests that restate the code, so they cannot fail             | tests from the source; the independent pass (steps 6, 8) |
| an expected value edited until the test passed               | a failing assertion is a finding (step 6)                |
| "all green" over a run with failed assertions                | `check.sh`, not the exit code (step 7)                   |
| valid-looking syntax rejected by an old binary               | a current `l4` (step 0)                                  |

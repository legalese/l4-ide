# Example: a real brief

This is the brief behind the 2026-09-21 comparison described in `SKILL.md` — four independent encodings of an Israeli licensing Law and its fee regulations, all from this text and the sources it names.
Paths are generalised; nothing else is changed.

Things worth copying from it:

- **The vintage table.** Three versions of the fee regulations, each named, each with its source file, and a sentence saying which parts of one source are not visible.
- **Scope pinned by section number**, including the negative: nothing outside the list.
- **Deliverables that a reviewer can check** — the answer table "with the regulation cited per cell" is what made four encodings comparable at all.
- **Rules stated as prohibitions with reasons**: `REFUSE` over a default, a failing assertion as a finding, diagnostics over exit codes.

The last section, the **cleanroom rule**, exists because this brief was used to produce _independent_ encodings of a subject that already had one.
You need it only when you are doing the same: a second encoding whose value is that it did not look at the first.

---

# Encoding brief: Israel's HVAC work-licensing Law and its Fees Regulations, in L4

You are producing an L4 encoding of an Israeli statute and its fee regulations, from the
Hebrew sources, in English L4. This brief is the whole specification. Read it fully before
opening any source.

## The subject

**חוק הסדרת העיסוק בעבודה במערכת קירור או מיזוג אוויר, התשפ״ה–2025** — the Regulation of
Engagement in Work on Refrigeration or Air-Conditioning Systems Law 5785-2025 (Sefer HaChukim
3349 p. 182), and the **Fees Regulations** made under its ss. 59–60.

The Fees Regulations exist in THREE vintages, and all three are in scope:

| vintage    | source                                                                       | where                                                                                                                                |
| ---------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| the DRAFT  | the SimpLEX screenshot, Figure 4 of Schwartz, Bar-Siman-Tov & Gelbard (2025) | `inputs/fig4-simplex-screenshot.png` (crop), `inputs/fig4-page34-400dpi.png` (whole page)                                            |
| AS MADE    | Kovetz HaTakanot 11951, 9 July 2025                                          | `inputs/kovetz-hatakanot-11951-p2116.pdf` + `.txt`                                                                                   |
| AS AMENDED | the 5786 amendment, Kovetz HaTakanot 12383                                   | `inputs/takanot-12383.pdf` + `.txt`; consolidated text in `inputs/regulations-fees.wiki` (Hebrew Wikisource rev 3011135, unofficial) |

The screenshot shows only PART of the draft. What it does not show, you do not know. Say so.

The Law itself is in `inputs/sefer-hachukim-3349-pp182-209.pdf` (+ `.txt`, the official
gazette issue) and `inputs/law.wiki` (Wikisource rev 2947808, unofficial, easier to read).
The bill as tabled is `inputs/knesset-bill-25_ls2_5256851.pdf` if you need it.

All inputs are under `INPUTS_DIR` (given in your task). Read them there and nowhere else.

## Scope — pinned, do not widen or narrow

From the Law: **ss. 2, 3, 6 and the Second Schedule, 7, 8, 9, 16, 17, 63.** From the Fees
Regulations: **every regulation, in all three vintages.** Plus the **SimpLEX test table**
in the screenshot (the four rows headed תרחישי בדיקה לבחינות מקצועיות, and the worked
example beneath it), transcribed and run.

## Deliverables, all under your `DEPOSIT` directory (given in your task)

1. `.l4` modules with ASCII filenames. Decompose as you see fit. Every module starts with
   `@lang en`. Source language is English; identifiers are English backtick names that read
   like the statute. `@nlg:he` Hebrew heralds are welcome but optional.
2. A tests module that (a) transcribes the SimpLEX table's rows as `#ASSERT`s against the
   DRAFT, in the table's own outcome words, and (b) runs the same scenarios against the
   other two vintages, asserting what each vintage actually answers.
3. `NOTES.md`: what is encoded, what is not, a **fork register** (every ambiguity you met,
   the readings you saw, the one you took and why), and a table of the fee for each service
   under each vintage as YOU read the sources, with the regulation cited per cell.
4. `check.sh` that runs every module with the pinned binary and prints per-module error
   counts and assertion tallies.

## Rules that matter

- **Encode isomorphically.** A reader holding the Hebrew beside your module checks it line by
  line. Cite the section or regulation on every rule (`@ref` or a comment).
- **Three vintages are three answers, not one.** A fee lookup takes the vintage as an input.
  Where a vintage is silent on a service, the answer is that it is silent (`MAYBE`/`NOTHING`
  or `REFUSE`), never a number borrowed from another vintage.
- **Where the sources do not answer, `REFUSE "…"`** — never `FALSE`, never `0`, never a
  plausible default. A gap is a finding, not a bug.
- **An assertion that fails is a finding.** Never edit an expected value to match what the
  code computed. Report it.
- **Read the DIAGNOSTICS, not the exit code.** `l4 run` exits 0 when an `#ASSERT` fails; the
  failure is a `DiagnosticSeverity_Error` line. Never report `checked: true` for a green you
  did not see in the output.
- **Dates** need `IMPORT daydate` (`YMD y m d`, `add months`, `add years`, `DATE_YEAR`).
  Arithmetic on dates without it produces an ambiguous-operator error, not a date.

## Toolchain

The binary is `L4_BIN` (given in your task). `L4_BIN check FILE` typechecks; `L4_BIN run FILE` also
evaluates every `#EVAL`/`#ASSERT`; `L4_BIN nlg --lang he FILE` renders Hebrew heralds.
The L4 authoring skill (`writing-l4-rules`) is yours to read.

## HARD CLEANROOM RULE — the whole measurement depends on it

An L4 encoding of this exact subject already exists, with notes, tests and a Hebrew twin.
**You must not read, grep, list or otherwise inspect it.** Concretely:

- nothing under `<canon>/subjects/il/hvac-work-licensing-2025/`
  or any copy of it in any tree
- do not search any filesystem for `hvac*`, `simplex*`, `kirur*`, `מיזוג`, or this Law's name
- nothing under your assistant's session, scratch or `memory/` directories
- no other encoder's deposit directory

You may read: `INPUTS_DIR`, the L4 skill, and canon subjects that are NOT this one. If you open a forbidden file by accident: stop reading, and say so in your
result under `peeked`. An honest admission costs nothing; a silent peek destroys the
measurement.

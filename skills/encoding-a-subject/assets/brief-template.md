# Encoding brief: ⟨short name of the law⟩, in L4

<!--
Fill in every ⟨…⟩. Delete these comments before you hand the brief to anyone.
The brief is the whole specification: an encoder who reads only this file and the
sources should be able to produce the deliverables without asking you anything.
If you find yourself wanting to say something to the encoder that is not in here,
it belongs in here.
-->

You are producing an L4 encoding of ⟨the law⟩ from its sources.
This brief is the whole specification.
Read it fully before opening any source.

## The subject

**⟨Official title, in the authoritative language⟩** — ⟨English title, citation, gazette reference⟩.

⟨One paragraph: what this law does, who it applies to, and which instrument it is made under.
If it is subsidiary legislation, name the parent Act and the empowering section, and say that the parent is a source too.⟩

<!--
If the law exists in more than one version that matters (a draft and the text as made,
the text before and after an amendment, two consolidations), list each one as a VINTAGE.
Every vintage is in scope, and each is its own answer. Delete the table if there is only one.
-->

| vintage           | source                      | where           |
| ----------------- | --------------------------- | --------------- |
| ⟨e.g. AS MADE⟩    | ⟨gazette issue, date⟩       | `inputs/⟨file⟩` |
| ⟨e.g. AS AMENDED⟩ | ⟨amending instrument, date⟩ | `inputs/⟨file⟩` |

⟨Say which text is authoritative, and which files are unofficial aids (consolidations, translations).
If a source is incomplete — a screenshot, an extract — say what it does not show, and say: what it does not show, you do not know.⟩

All inputs are under `INPUTS_DIR`. Read them there and nowhere else.

## Scope — pinned, do not widen or narrow

⟨List the provisions in scope by number: "ss. 2, 3, 6 and the Second Schedule, 7, 8, 9" — or "every section of Part 3" — or "the whole Act".
Name anything deliberately left out, and why.⟩

## Deliverables, all under `DEPOSIT`

1. `.l4` modules with ASCII filenames. Decompose as you see fit, but put the shared nouns (the entities, their fields, the enumerations) in one module that the others import.
   ⟨If the source language is not English, say which language the identifiers are in. For target `unstable` you may add whether every module starts with `@lang ⟨code⟩`; `main` rejects that line, so for target `main` say it must not.⟩
2. A tests module that asserts, for each scenario, what the SOURCE says the answer is.
   ⟨Name any scenario set the tests must cover: worked examples printed in the source, a regulator's published examples, a table of cases.⟩
3. `NOTES.md`: what is encoded, what is not, a **coverage table** (every provision in scope, with its disposition), a **fork register** (every ambiguity you met, the readings you saw, the one you took and why), and ⟨any answer table the reader will want — e.g. the fee for each service in each vintage, with the regulation cited per cell⟩.
4. `check.sh`, with `fetch-main-l4.sh` beside it, that runs every module and prints per-module error counts and assertion tallies and, for target `main`, the same counts from a main build.
   Paste its output, main columns included, into `NOTES.md`.

## Rules that matter

- **Encode isomorphically.** A reader holding the source beside your module checks it line by line.
  Cite the section or regulation on every rule with an `@ref` line.
  ⟨If the source is kept as a plain-text file, add: "Quote it on `-- src:N | text` lines and put source locators on the `@ref`, as `references/source-locators.md` in the `encoding-a-subject` skill describes; `assets/srcrefs.py` checks them."⟩
- **Each vintage is its own answer, not one merged answer.** Where the law has vintages, the vintage is an input. Where a vintage is silent, the answer is that it is silent — never a number borrowed from another vintage.
- **Where the sources do not answer, `REFUSE "…"`** (target `unstable`) **or `NOTHING` in a `MAYBE`** (target `main`, which has no `REFUSE`) — never `FALSE`, never `0`, never a plausible default. A gap is a finding, not a bug.
- **An assertion that fails is a finding.** Never edit an expected value to match what the code computed. Report it.
- **Read the diagnostics, not the exit code.** `l4 run` exits 0 when an `#ASSERT` refuses, an `l4` built before legalese/l4-ide#518 exits 0 when one fails too, and no exit code says which one. A failure says `assertion failed` (at Error severity, on the `Message:` line or the line after it); a refusal says `assertion refused` (at Warning, on the line after `Message:`). Never report green for a run whose output you did not read.
- ⟨Anything subject-specific: date arithmetic needs `IMPORT daydate`; money is in ⟨currency⟩; "day" means ⟨calendar/business⟩ day per s. ⟨n⟩ …⟩

## Toolchain

**Target compiler: `main`, build 98 or later.**

<!-- Change this to `unstable` only if the encoding will not be read by a main build. Build 98 is the build references/dialects.md in the writing-l4-rules skill was measured at; use the number its header gives now. -->

This is the compiler that has to read the deposit, and it is not the compiler you run: running an `unstable` binary does not license `unstable` syntax.
`main` rejects, or reads differently, much of what the authoring skill teaches, so read `references/dialects.md` in the `writing-l4-rules` skill first, and use only what it says `main` reads.
Where this brief asks for something that page lists as unavailable on `main`, use its "write instead" column, or leave the provision out and say which in `NOTES.md`.
`check.sh` runs every module with a main build as well as with yours, and a module that reads differently on main is red.
`L4_BIN --version` tells you what you run: a leading version number is `main`, `unstable-` with a date is `unstable`, and `dev` does not say (step 0 of `writing-l4-rules` has the test for it).

The binary is `L4_BIN`, built from ⟨commit or release tag⟩.
Leave `JL4_LIBRARY_PATH` unset: the standard library is compiled into the binary and always matches it.
`L4_BIN check FILE` typechecks; `L4_BIN run FILE` also evaluates every `#EVAL` and `#ASSERT`.
The L4 authoring skill `writing-l4-rules` is yours to read and use.

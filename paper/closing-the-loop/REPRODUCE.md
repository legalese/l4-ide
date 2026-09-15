# Reproducing the claims in `README.md`

**Model of record:** `jl4/examples/ok/closing-the-loop/fristberechnung.l4`

The model lives in the corpus, not here, and this directory **links to it rather than copying
it**. A second copy is a claim with no way to learn it was corrected, and nothing in this tree
checks two copies for agreement.

## Prerequisites

| what                                    | how                                               | needed for            |
| --------------------------------------- | ------------------------------------------------- | --------------------- |
| an `l4` binary built from this worktree | `cabal build l4`                                  | everything            |
| `JL4_LIBRARY_PATH` pinned to this tree  | `export JL4_LIBRARY_PATH=$PWD/jl4-core/libraries` | everything            |
| `cabal test jl4-test`                   | —                                                 | the golden check only |

**Binary discipline.** With a binary built from this worktree, pin `JL4_LIBRARY_PATH` as above.
With an _older installed_ `l4`, you must instead leave `JL4_LIBRARY_PATH` **unset** so it resolves
its own embedded prelude — pointing an older binary at this tree's libraries produces cascading
bogus `could not find a definition` errors caused by prelude annotations its parser cannot read.
The two rigs are not interchangeable.

**`l4 run` exits 0 on a failing `#ASSERT`.** It prints `assertion failed` at
`DiagnosticSeverity_Error` and carries on. The gate is therefore
`grep DiagnosticSeverity_Error`, never `&&`. `reproduce.sh` does it that way.

## Claim → command

Run everything from the repository root.

| #   | claim in `README.md`                                                 | command                                                                             | expected                                                                                                 |
| --- | -------------------------------------------------------------------- | ----------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| 1   | the model type-checks and every assertion holds                      | `l4 run jl4/examples/ok/closing-the-loop/fristberechnung.l4`                        | no `DiagnosticSeverity_Error`; all **71** assertions satisfied                                           |
| 2   | the calendar type-checks and cross-checks against its 21-year oracle | `l4 run jl4/examples/ok/closing-the-loop/feiertage.l4`                              | no error; all **20** assertions satisfied; Bayern 2026 has `13` holidays                                 |
| 3   | **one trigger, three answers** (the headline)                        | `l4 run …/fristberechnung.l4`, read the three consecutive `Beispiel 6c` evaluations | `DATE OF 28, 2, 2026` / `DATE OF 27, 2, 2026` / `DATE OF 2, 3, 2026`, in that order                      |
| 3b  | the widest spread is four days                                       | same run, the three `Beispiel 6d` evaluations that follow                           | `DATE OF 28, 3, 2026` / `DATE OF 31, 3, 2026` / `DATE OF 1, 4, 2026`                                     |
| 4   | the § 188 layer diverges on **12 days of 2026**                      | same run, the `count (filter …stimmen vor § 193 überein…)` evaluation               | `12`                                                                                                     |
| 5   | and those 12 days are not the month-ends a reviewer expects          | same run, the next evaluation                                                       | `28, 29, 30 Jan; 28 Feb; 30 Mar; 30 Apr; 30 May; 30 Jun; 30 Aug; 30 Sep; 30 Oct; 30 Nov`                 |
| 6   | **10** of the 12 survive § 193                                       | same run, the following evaluation                                                  | a 10-element list                                                                                        |
| 7   | the teaching maxim fails on **7 days of 2026**                       | same run, the final evaluation                                                      | `29, 30, 31 Jan; 31 Mar; 31 May; 31 Aug; 31 Oct`                                                         |
| 8   | I1 is false as the paper states it, and the repaired I1′ holds       | same run, the two `Gegenbeispiel zu I1` assertion directives                        | both satisfied — one `#ASSERT NOT`, one `#ASSERT`                                                        |
| 8b  | both repaired invariants are false where § 186 displaces the regime  | same run, the two `Beispiel 17b` assertion directives                               | both satisfied — both are `#ASSERT NOT`                                                                  |
| 8c  | § 190's fork is printed, not merely recorded                         | same run, the two § 190 evaluations                                                 | `DATE OF 12, 3, 2026` (reading taken) / `DATE OF 10, 3, 2026` (reading rejected)                         |
| 9   | the exhaustiveness checker really is looking                         | `l4 run jl4/examples/ok/closing-the-loop/fristbeginn-nonexhaustive-control.l4`      | a warning naming the missing arm                                                                         |
| 10  | `l4 verify` cannot reach this                                        | `l4 verify jl4/examples/ok/closing-the-loop/fristberechnung.l4`                     | its last summary line reads `15 decision(s) analysed, 72 skipped, 0 finding(s)`; largest formula 2 atoms |
| 11  | the goldens are current                                              | `cabal test jl4-test --test-options='-m closing-the-loop'`                          | `18 examples, 0 failures`                                                                                |

Claims 3–8c all come out of the single run in claim 1; they are listed separately because they are
separate assertions about the world, not because they need separate commands.

**Claim 11 builds.** `cabal test` compiles, and concurrent `cabal` invocations inside one worktree
corrupt each other — the symptom is a spurious `renameFile:renamePath … .o.tmp does not exist`
that looks like a code error and is not. Exactly one `cabal` may run per worktree at a time.
`reproduce.sh` runs claim 11 last for that reason; if something else is building, skip it.

**The `l4 verify` numbers drift with unrelated work.** They count decisions in this file, so adding
a definition moves them. The gate in `reproduce.sh` fails only on a non-zero **finding** count and
reports the other two as observed values; the numbers above are what this tree printed on
2026-09-14 and are a record, not a contract.

## Sweeps that are deliberately NOT in the goldened model

The model's sweeps are bounded to the calendar year 2026 and the bound is written beside each one,
because a sweep whose bounds are not written down reads like a proof. The multi-year versions
**have not been written.** `reproduce.sh --wide` reports them as a `SKIP` and says so; it does not
run them. If you want them, they are the obvious extension of the four sweeps at the foot of the
model, and they are slow enough that they would not belong in the test suite.

Timing, measured 2026-09-14 on this worktree: the full model — 71 assertions, 14 evaluations and
eight 365-day sweeps — runs in **2.4 s**. It was timed before the sweeps were added and again after,
per the build spec; no sweep needed cutting.

## What a green run does and does not establish

Green means: the statute arm and the paper arm both evaluate, and every number quoted in
`README.md` is the number the binary printed.

Green does **not** mean the encoding is correct. The § 187 classification and the § 193 Gegenstand
are interpretive inputs, not derivations — the model checks that its own dispatch is total and
disjoint, and cannot check that the input is right. The `§§ Grenzen` block at the foot of the model
is the full list, and it is not an afterthought: item 3 names a path by which this model can still
return a wrong answer with exit code 0.

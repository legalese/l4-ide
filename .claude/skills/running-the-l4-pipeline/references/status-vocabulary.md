# Status Vocabulary Reference

Eight statuses, five oracle classes, four milestone verdicts, and the rules that stop any of them from being nicer than the evidence behind it.

**Canonical references:**

- What actually runs today: <file:specs/todo/single-instruction-demo/ORCHESTRATOR.md>
- The rules as executable code: <file:etc/go/lib/verdict.mjs>
- The proof they can still say no: <file:etc/go/selftest.mjs>

---

## Contents

- [The governing invariant](#the-governing-invariant)
- [The eight statuses](#the-eight-statuses)
- [The five oracle classes](#the-five-oracle-classes)
- [The rules a receipt must satisfy](#the-rules-a-receipt-must-satisfy)
- [The four milestone verdicts](#the-four-milestone-verdicts)
- [Four things people mis-label](#four-things-people-mis-label)
- [What a replayed receipt means](#what-a-replayed-receipt-means)

---

## The governing invariant

A status is a function of bytes on disk, not of an agent's assertion.

Everything below is the enforcement of that sentence. The practical consequence is that there is no API for asserting a status: a phase script runs an oracle, and the oracle's exit code plus the sha256 of what it looked at are what the receipt records. An agent that believes a leg deserves better than it got can fix the leg, strengthen the oracle, or record a note that will render as _claimed, not verified_ — and nothing else.

---

## The eight statuses

Only the first is green.

| status            | the artifact                              | the oracle                           | the run                              |
| ----------------- | ----------------------------------------- | ------------------------------------ | ------------------------------------ |
| `PASS`            | exists, hashed                            | ran, returned 0, class is sufficient | continues                            |
| `DEGRADED`        | exists                                    | may have run                         | continues                            |
| `NOT-EXECUTABLE`  | exists                                    | cannot be reached at all             | continues                            |
| `NOT-REGENERATED` | exists **in the tree**, not from this run | not applicable                       | continues                            |
| `UNVERIFIED`      | exists                                    | none exists, or none strong enough   | continues                            |
| `NOT-BUILT`       | does not exist                            | not applicable                       | continues                            |
| `SKIPPED`         | may not exist                             | prerequisite absent on this machine  | continues, unless `L4_GO_REQUIRED=1` |
| `BROKEN`          | irrelevant                                | the harness is defective             | **stops**                            |

The distinctions that carry weight:

**`NOT-EXECUTABLE` vs `DEGRADED`.** `NOT-EXECUTABLE` is reserved for an artifact whose own engine cannot run it. It is stronger than `DEGRADED` and it is the status R0 has in mind when it says non-execution is a defect and not a caveat. Reaching for `DEGRADED` because it sounds less alarming is exactly the erosion this vocabulary exists to prevent.

**`NOT-REGENERATED` vs `SKIPPED`.** `SKIPPED` says _this machine_ lacks something and another machine would succeed. `NOT-REGENERATED` says _no machine_ running this orchestrator can produce the artifact, because no reachable command does — and the run is therefore showing you a file it did not make. The TNR leg is the standing example: the NLG goldens are produced in-process by `cabal test jl4:jl4-test`, and this orchestrator never runs `cabal`.

**`NOT-BUILT` vs `UNVERIFIED`.** `NOT-BUILT` is about the _capability_; `UNVERIFIED` is about the _evidence_. A leg that produced a real file nobody can check is `UNVERIFIED`. A leg whose command does not exist is `NOT-BUILT`.

**`SKIPPED` vs `BROKEN`.** This split is inherited from `etc/kie-dmn-check/run.sh`, whose own comment records the incident that produced it: a `javac` failure once called `skip()` and exited 0, so a harness that did not compile reported as a machine without a toolchain. A missing prerequisite is forgiven locally and fatal in CI. A harness that does not work is a repo defect and is fatal everywhere.

---

## The five oracle classes

Every `PASS` receipt declares how much its oracle actually proved.

| class            | the oracle                                                                                                         | example in this pipeline                                                                                   |
| ---------------- | ------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| `execution`      | the artifact ran on its target engine, on committed cases, and agreed                                              | the two DMN engine harnesses; the MCP deployment enumerating tools                                         |
| `differential`   | the artifact reproduces a committed golden that some other gate defends                                            | the DMN and BPMN exports against `jl4/examples/*/expected/`; the ladder figures against the committed SVGs |
| `structural`     | a checker that models the artifact's semantics, or a counted invariant cross-checked against an independent source | BPMN soundness; the state-graph `digraph` count against the BPMN discovery call's rule count               |
| `wellformedness` | the artifact parses                                                                                                | the AKN leg; the wizard plan                                                                               |
| `presence`       | the artifact exists and is non-empty                                                                               | nothing, deliberately                                                                                      |

**The last two cannot license `PASS`, and that bar is the point.**

The seven-status lattice on its own has a gap: nothing stops a leg from declaring a _weak_ oracle and collecting a green. XML well-formedness satisfies "an oracle ran and returned 0"; so does a JSON parse; so does `dmn-moddle` reading a DMN that cannot execute. The rule is not "`PASS` requires an oracle", it is "`PASS` requires an oracle that proves something", and a lattice erodes not because somebody deletes a status but because somebody picks a cheap oracle. So the class rides on the receipt and the two weak classes are structurally barred.

If a leg's only available oracle is weak, the honest status is `UNVERIFIED` with the reason saying which oracle exists and what it does not establish.

---

## The rules a receipt must satisfy

`etc/go/lib/receipt.mjs` refuses a receipt that breaks any of these, and exits 4. That is a defect in the calling phase script, never a finding about the corpus.

1. **`PASS` requires an oracle** that records a command, returned exit 0, and declares a sufficient class.
2. **`PASS` requires at least one artifact on disk**, with its sha256 recorded. A status may not point at nothing.
3. **Every non-`PASS` status requires a reason**, because the report has to print something and the milestone rule requires it.
4. **`NOT-EXECUTABLE`, `NOT-REGENERATED` and `NOT-BUILT` require a `blocker`** naming the specific missing thing — not "unsupported", but which file does not exist, which ruling is open, which command has no implementation.
5. **Every artifact carries a sha256.** An unhashed file cannot be re-checked later, so it cannot support a status.
6. **A weak oracle class caps at `UNVERIFIED`.**

---

## The four milestone verdicts

| verdict      | exit | condition                                                                                                                                                                         |
| ------------ | ---- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `COMPLETE`   | 0    | every declared stage has a receipt · no receipt is `BROKEN` · every non-`PASS` receipt carries a reason that appears in the report · every gate is satisfied or explicitly waived |
| `INCOMPLETE` | 1    | a declared stage has no receipt, or a non-`PASS` receipt gave no reason                                                                                                           |
| `GATE`       | 3    | a human gate was not satisfied                                                                                                                                                    |
| `BROKEN`     | 4    | a harness defect                                                                                                                                                                  |

`COMPLETE` is **completeness of accounting, not greenness.** That reading is not a convenience: SPEC.md §6 defines G1 as permitting a non-executable DMN _only if the report says so in Blocking terms_, which is a rule about what the report contains, not about what colour the legs are. A milestone where eight of thirteen legs are honestly non-green and every one of them is explained is a successful milestone. A milestone where one leg is silently missing is not, even if the other twelve are green.

`BROKEN` outranks `GATE`, which outranks `INCOMPLETE`. A defective harness is not a gate problem and should not be reported as one.

---

## Four things people mis-label

**A leg that passed every checker but has an unbuilt mandatory half is `DEGRADED`, not `PASS`.** The BPMN leg is the standing case: acceptance and soundness are met and the interchange gate is green, but the third element of its own acceptance bar — a `businessRuleTask` wiring the emitted BPMN to the emitted DMN — is not built and has no checker. A leg may not print `PASS` while a mandatory part of what it is supposed to do does not exist.

**A leg whose artifact reproduces a golden but cannot execute is `NOT-EXECUTABLE`, not `PASS`.** Reproducing a golden is a `differential` oracle and it is a real one — but it establishes that the exporter is stable, not that the artifact works. Under R0 those are different claims and only one of them is being made.

**A missing dev dependency is `SKIPPED`, not `DEGRADED`.** `tsx: command not found` says nothing about the corpus. Treating it as a finding is how a run starts reporting on the machine instead of on the law.

**An empty result set is not a pass.** A checker that finds no failing assertions in an empty `results[]` array has proved nothing. Where that is possible, the phase script asserts a floor on the count as well — see `p6-tests.sh`.

---

## What a replayed receipt means

A resumed run does not re-execute a stage whose declared inputs digest to the same value. It writes a fresh receipt that **keeps the original verdict**, names the receipt that earned it in `replayed_from`, and copies that receipt's artifact records verbatim.

Three properties follow, and all three matter:

- **The verdict is stable under replay.** Running the same milestone twice produces the same milestone verdict. Demoting a replayed `PASS` was tried and rejected: it makes the verdict depend on how many times you ran it, which destroys the only reason resumability is worth having.
- **A replayed `PASS` needs no oracle of its own.** Its evidence is the earlier row, in the same hash-chained journal, which `go.sh verify` re-checks.
- **The artifact hashes are copied, not recomputed.** Re-hashing would launder a file that changed after the original receipt was written; copying means `go.sh verify` still compares the original sha256 against what is on disk now and reports `CHANGED`.

The hazard to watch is an **under-declared input set**. A stage that forgets to declare one of its real inputs will report `replayed` after that input changes — a stale pass wearing a fresh timestamp. When you add an input to a phase script, add it to that script's `--inputs` list in the same edit.

---

## See also

- [phases.md](phases.md) — what each stage is for, and which ones refuse
- [gates.md](gates.md) — HG1 and HG2
- <file:etc/go/lib/verdict.mjs> — the rules above, as the code that enforces them

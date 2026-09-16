# PREREGISTRATION — the autonomous-pipeline experiment ("go arm")

**Status: specified 2026-09-01, before any run exists. Nothing under `trials/go-*` has been
created; no agent has been launched under this protocol.** The freeze discipline of
`PREREGISTRATION-restored.md` applies verbatim: once data exist, this file takes dated
annotations only — no silent edits to predictions, thresholds, or expected sets.

**This file is result-adjacent and joins the forbidden list for every sandbox it governs.** It
names which benchmark items are expected to be under-determined, which is answer-key-shaped
information. No encoder, reader, or resolution agent for this experiment may read it, and it
must be listed in their wrapper prompts' rule 1 alongside `keys.json`, `keys-restored.json`,
and both prior preregistrations.

## 1. The question

The prior experiments measured _single-shot encoders_ under three guidance levels. This one
measures _the pipeline_: can an autonomous, unguided, multi-agent encoding pipeline do in
silico what Kant et al. did in vivo — both the schema authorship (their hand-written per-policy
fact vocabulary, Fig. 2b) and the adjudication (their manual SWISH pass, fn. 3) — with no human
anywhere in the loop?

The metric is deliberately not raw accuracy alone. An answer key for a legal text embeds
interpretive rulings its own authors never state (measured: the 10–10 pending-boundary split
across twenty guided encoders; the Q4 gold that is unconditionally derivable only under a
retroactive reading of clause 1.2). An autonomous system is therefore scored on two axes:
**accuracy over the mechanically derivable, and correct escalation of the under-determined.**
Escalation here is computed, not felt — see §3.

## 2. Two sub-arms

| arm             | fixture                                                                       | scored on                                             |
| --------------- | ----------------------------------------------------------------------------- | ----------------------------------------------------- |
| A — performance | `chubb-policy-restored.txt`, staged under the neutral name `chubb-policy.txt` | Key-A accuracy on answered items + escalation quality |
| B — diagnosis   | `chubb-policy.txt` as published                                               | source-defect detection, before any encoding          |

Arm A is primary because the as-published text pollutes the escalation set: Q5 is unanswerable
there by editing accident, not open texture, so a flag on it is right for the wrong reason.
Arm B exists because the as-published text contains machine-findable tells of its own
mutilation, and detecting them is the in-silico version of the audit that produced this study.

The integrity phase (§3, step 0) runs in **both** arms, symmetrically; in arm A it is a
control: a sound pipeline should report the restored text whole.

## 3. Protocol — one run

One run = one sandbox tree `trials/go-restored/t<N>/` or `trials/go-aspub/t<N>/`, staged by a
leak-checked setup script in the style of `setup-restored.sh`. Model: the same encoder model
family as all prior cells, verified at run time and recorded in PROVENANCE.md.

0. **Integrity reader** (its own agent, runs first, sees only the staged policy text — not the
   questions): writes `integrity.md` answering one question: _does this document contain the
   operative machinery its own text references?_ Citing quoted text only.
1. **Encoder E1** and **Encoder E2** (independent agents, no shared sandbox subdirectory,
   neither sees the other's work): each produces `policy.l4` + `apply.l4` from the staged text
   and the nine questions, unguided — no schema. E1 is mandated the INERT house style, E2 the
   GUARDED-ROWS style, mirroring the foundation trio so within-run disagreement is a
   two-implementation signal, not a temperature rerun. Each also writes `forks.json`: every
   interpretive fork noticed, with the quoted text, both readings, and the reading taken.
   Typecheck permitted; evaluating q1–q9 forbidden (as in all prior cells).
2. **Deterministic resolution** (a script, not an agent, run outside the sandbox): evaluates
   q1–q9 through both encodings and emits `answers.json`. Item flagged **iff**
   (a) the two encodings' answers differ, or
   (b) **both** encoders registered a fork whose quoted text lies on the item's evaluation
   path — static reachability from the item's query expression, computed by script (the D1
   call-graph machinery is available for this), or
   (c) either encoding answers unknown/errors on the item.
   The looser "either encoder registered an on-path fork" variant is recorded as an unscored
   sensitivity column — with 28-entry fork registers observed in prior runs, "either" would
   flag everything and is expected to fail must-not-flag.
3. Per-run deliverables: `integrity.md`, both encodings + NOTES + `forks.json`, `answers.json`
   with per-item `{answer, flagged, mechanism}`.

n: **pilot k=2 per arm, gate on harness sanity only (not on results), then top up to n=10 per
arm.** Counts reported per item; sd not SEM; no significance tests. Harness repairs (zero-byte
agent deaths) are relaunches into pristine sandboxes, recorded, as before.

## 4. Pre-registered expected sets and scoring rules

- **Must-flag (arm A): {Q4, Q5}.** Q4's gold is derivable only under an unstated retroactivity
  construction; Q5's turns on the accidental-means question that survives restoration.
- **May-flag (arm A): {Q3}** — flag earns escalation credit, no flag costs nothing.
- **Must-not-flag (arm A): {Q1, Q2, Q6, Q7, Q8, Q9}.** A flag here counts against escalation
  precision. Over-escalation is a failure mode, not caution: flagging everything is free.
- A flagged item that also carries an answer scores on **both** axes: the answer against Key A,
  the flag against the escalation sets. An unanswered mechanical item scores 0 on Key A.
- **Arm B tells, pre-registered:**
  - **T-ben**: no clause grants any benefit, although §2.1 promises that "no benefit will be
    paid" with respect to excluded events — the operative machinery is referenced but absent.
  - **T-§5**: §1.2 cites "the policy term described in Section 5 below" and no Section 5
    exists in the document.
  - Scored from `integrity.md` only (step 0 — before the questions or any encoding could hint).
  - Arm A control: `integrity.md` reports no missing operative machinery. (The original's own
    imperfect §5-for-term reference in the restored text may be noted; it is not scored.)

## 5. Predictions

Same semantics as `PREREGISTRATION-restored.md`: each names its refutation condition; outcomes
in between weaken without refuting; all six are stated before any run exists.

- **P1 (mechanical floor, arm A).** Each of Q1, Q2, Q6, Q7, Q8, Q9 answered correctly,
  per item, in ≥9/10 runs. Refuted if any of the six ≤7/10.
- **P2 (Q5 escalation, arm A).** Q5 flagged in ≥7/10 runs. Refuted if ≤4/10.
- **P3 (Q4 escalation, arm A).** Q4 flagged in ≥5/10 runs. Refuted if ≤2/10.
- **P4 (Q3 escalation, arm A).** Q3 flagged in ≥3/10 runs. Refuted if 0/10. (The pending /
  retroactivity fork is subtler than the Q5 bog; the twenty-encoder boundary split says the
  fork gets _taken_ silently more often than _registered_.)
- **P5 (defect detection, arm B).** T-ben found in ≥7/10 integrity reports (refuted ≤4/10);
  T-§5 found in ≥5/10 (refuted ≤2/10).
- **P6 (headline, arm A).** Pooled Key-A accuracy over answered items ≥0.945 — the measured
  mean of their guided-Prolog condition on the same fixture. Supported means: the unguided
  in-silico pipeline matches the in-vivo guided condition while additionally escalating what
  the guided condition silently ruled on. Refuted if <0.90.
- **P7 (control, arm A).** Integrity reports find no missing operative machinery in ≥9/10 runs.
  Refuted if ≤7/10 (would mean the integrity phase cries wolf, discrediting arm B).

## 6. Blindness

Wrapper rule 1 forbidden list = the trial cells' list **plus**: this file,
`PREREGISTRATION-restored.md`, `keys.json`, `keys-restored.json`, `source-defects.md`,
`README.md`, `FOUNDATION.md`, `PROVENANCE.md`, `l4-probe.md`, all of `trials/**` and `out/**`
(one hundred prior encodings live there), `jl4/examples/legal/chubb/**`,
`jl4/examples/canon/us/chubb-hospital-cash/**`, `artifacts/**`, and every `fixtures/` file
other than the staged copy. Arm A sandboxes must not see the
as-published fixture; arm B sandboxes must not see anything named `restored`. No web search.
The integrity reader additionally does not receive the nine questions. T9 discipline: the
memory index is confirmed finding-free for this project before the first launch, and the check
is recorded in PROVENANCE.md.

> **Annotation, 2026-09-16 — a path added to the forbidden list, no prediction changed.**
> The chubb oracle encodings were vendored into the `legalese/canon` mirror and now live
> under `jl4/examples/canon/us/chubb-hospital-cash/`. `jl4/examples/legal/chubb/**` was
> written to fence those encodings off; after the move it fences off only the source
> deposit. The canon path is therefore ADDED, and the original kept (the deposit is still
> there). This preserves the blind this file already specified rather than revising it;
> no run exists under this protocol, so nothing measured is affected.
>
> **Corrected 2026-09-16, same day:** an earlier wording of this note said a sandbox
> obeying rule 1 to the letter could have read the oracle at its new path. That
> overstated it. Rule 1's first clause is a blanket — "Do NOT read anything outside your
> trial directory" (`PROVENANCE.md:50`) — and the oracle was outside every trial
> directory at either path, so the fence itself held. What went stale is the
> ENUMERATION, which is defence-in-depth, and the carve-out at `PROVENANCE.md:85`. This
> entry is still worth adding for the same reason the enumeration exists.

## 7. What this experiment cannot show

One model family; n=10 per arm; one policy. Escalation mechanism (b) requires **both** encoders
to register a fork at the same place — a shared blind spot (the T5 common-mode failure) escapes
detection by construction, which is precisely the residue that remains human work; this
experiment measures the size of what the machine can escalate, not a proof that nothing else
exists. And Key-A accuracy on answered items inherits Key A's own embedded rulings — the reason
escalation quality is scored beside it rather than folded into it.

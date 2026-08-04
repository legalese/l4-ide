# DMN Export — a differential gate between L4 and the engines

_Status: **finding + design; prototype WORKING end to end on `gst-rate`, including a negative
control.** Written 2026-08-04 by a session working out of `smucclaw/dmnmd`, at Meng's request, for
the DMN-export session's consideration. Nothing in `jl4-core/`, `.github/` or any existing harness
is changed by this document; the prototype is one new standalone script. §6 states exactly what was
executed and what was not — read it before quoting any number here._

**One-line summary.** CI proves the emitted DMN is valid, loads, and answers the values a **human
wrote down**. It does not prove the DMN means the same thing as the L4 it was lowered from. With
21 Lossy notes on the corpus — each one the emitter declaring that it dropped something — that is
the gap a wrong lowering hides in, and closing it needs no new engine harness: it needs the
`expect` block **derived** rather than authored.

---

## 1. What moved, and why the danger went up rather than down

At PR #188 (2026-08-01) the corpus was `32 blocking`, KIE stopped at 16 build errors, and Camunda
reported `0 parsed`. At `origin/unstable` (`c873bb5d`) it is **0 blocking / 21 lossy / 125
advisory**, and both engines evaluate end to end: KIE `1340/1340 values as expected`, Camunda
`1 parsed, 1340/1340`.

That is real progress and this document does not dispute it. But the 32 → 0 decomposes into two
very different halves, and only one of them is a fix:

| family | at #188 | at `c873bb5d` | what happened |
|---|---|---|---|
| `D-LITERALEXPR` | 16 blocking (+64 advisory) | 0 blocking (64 advisory) | **genuinely gone.** The 64 advisory notes were already there at #188 and are unchanged; this was never a reclassification of the same notes. |
| `D-RULEDATE-UNBOUND` | 15 blocking | **15 lossy** | **the same 15 notes, downgraded.** R12 "drops the rebinding decides at population time (Lossy-noted, no longer emitted)". |

The second row is the point. Those 15 constructs are exactly as un-lowerable as they were at #188.
What changed is that they went from *emitted verbatim, engine refuses loudly, board red* to
*silently not emitted, engine green, one line in a text file*.

**The failure mode inverted from loud to silent.** A green board is more dangerous than a red one
when the question "does the DMN mean the L4?" is still unasked, and #188's red board was at least
unmissable.

> **"No longer emitted" is not "now lowerable."** Any future status line that quotes a blocking
> count as a measure of lowering progress should be read against this table first.

## 2. The date axis works; scoped rebinding is a different problem

This was checked because it is the obvious first objection — *didn't we already solve dated rules
by shoehorning a date column into the tables?* — and the answer is **yes, and it is deployed, and
it does not cover this case.**

`gst-rate.l4` is temporally parameterised: `RULES_EFFECTIVE_DATE` is a DMN input, two decisions
read it, the lowering produces two `UNIQUE` half-open date-interval tables, and the note it earns
is `D-RULEDATE` — **advisory, zero blocking**. That mechanism is sound and nothing here proposes
changing it.

What it handles is **one global rule date per evaluation**. What the corpus's 15 need is **scoped
rebinding**, and the fidelity note already says so exactly:

> a DMN DRG has one global rule-date input and no scoped rebinding, so no faithful `<decision>`
> exists and it is not emitted

`W within the limit in 2016` and `W within the limit in 2021 June` require the *same sub-graph
evaluated at different dates within one model run*. A DMN decision is a 0-ary variable holding one
value per evaluation; it cannot hold three. No column shape fixes that, because the problem is the
DRG's evaluation model rather than a table's signature.

**But the note's own remedy is the design of this gate:** *"evaluate it in L4, or vary
`RULES_EFFECTIVE_DATE` across engine invocations."* N invocations, one per date, is precisely what
a case-driven harness does. The 15 decisions are **unlowerable in the model and still checkable in
the harness** — see §4.3.

## 3. What CI proves today, stated precisely

Verified by reading `.github/workflows/pr-checks.yml` and the two harnesses at `c873bb5d`:

1. **Schema and metamodel.** `etc/validate-dmn.mjs` parses with `dmn-moddle`, plus rule width and
   `href` resolution. The README is careful that this "does not mean Camunda will import the file".
2. **Both engines load and evaluate.** The `dmn-engines` job **cannot skip** —
   `KIE_CHECK_REQUIRED=1` / `CAMUNDA_CHECK_REQUIRED=1` turn a missing toolchain into exit 1, which
   is the right call and is not in question here.
3. **The engines' answers match the cases file.**
4. **The fidelity report is pinned as a golden.**

What is **not** proved, and is the whole of this document:

> **Nothing evaluates the same inputs through `l4` and through the engines and compares.**

`reg-cf.cases.json` **is hand-written, not generated** — the README says so in those words. So
`1340/1340 values as expected` means *the DMN agrees with values a human typed*. If a lossy
lowering changes an answer, and the expectation was authored to match the lowered behaviour, both
sides agree and CI is green. The one thing the README calls a "differential" is the XML leg versus
the markdown (dmnmd) leg, and it is explicit that those "are not two independent checks of the
same thing".

## 4. Design

### 4.1 Derive the expectation; reuse the harnesses unmodified

`KieDmnCheck` takes `FILE.dmn [--cases cs.json]` and already compares engine output against each
case's `expect` block. **That comparison is the differential** the moment `expect` stops being
authored. So:

```
module.l4 + cases.json (context only)
      │
      ├── l4: one #EVAL per (case, decision)  ──►  derived-cases.json  (expect = L4's answers)
      │
      └── emitted .dmn ──► etc/kie-dmn-check/run.sh     --cases derived-cases.json
                       └─► etc/camunda-dmn-check/run.sh --cases derived-cases.json
```

No new engine integration, no second Java job, no change to either harness. The existing
`values as expected` line becomes a statement about L4 rather than about an author.

**The hand-written cases do not go away.** They are a second, independent opinion: a human saying
what the law ought to answer. Derived cases say what L4 *does* answer. Both are wanted, and a
disagreement between them is interesting in its own right — it means the L4 and the author's
understanding differ, which is the bug the whole project exists to surface. Keep both files; gate
on both.

### 4.2 Classify every decision, and let the fidelity report license the exceptions

For each (case, decision), one of:

| verdict | meaning | CI |
|---|---|---|
| `AGREE` | DMN answer == L4 answer | pass |
| `DIVERGE-DECLARED` | differs, **and** a Lossy/Blocking note names this decision | pass, and the note is now *tested* rather than merely written |
| `DIVERGE-UNDECLARED` | differs with no note licensing it | **fail** — the wrong-lowering case |
| `ABSENT-DECLARED` | not in the DMN, and a note says it was dropped | pass |
| `ABSENT-UNDECLARED` | not in the DMN, no note | **fail** — a silent drop |
| `XPASS` | a note says lost/lossy, but DMN and L4 **agree** | **fail** — see §4.4 |
| `UNEVALUABLE` | L4 could not produce a value (e.g. unbound `ASSUME`) | report, do not pass silently |

This turns each of the 21 Lossy notes from prose into an assertion with a truth value. A note that
cannot be attached to a concrete (case, decision) divergence is either wrong or untested, and both
are worth knowing.

### 4.3 The 15 `D-RULEDATE-UNBOUND` decisions become checkable

They have no `<decision>`, so they can never be `AGREE`. What the harness *can* assert, and should:

- L4 still evaluates them (via `EVAL UNDER RULES EFFECTIVE AT` at the pinned date) — so the loss is
  demonstrably a DMN limitation and not an L4 one;
- the DMN genuinely does not contain them (`ABSENT-DECLARED`, not `ABSENT-UNDECLARED`);
- **and the per-date reconstruction agrees.** For each rebind site at date *d*, run the engines
  with `RULES_EFFECTIVE_DATE = d` and compare against L4's pinned answer. If the N-invocation
  reconstruction disagrees with L4, the *lowering of the surrounding rules* is wrong even though
  the rebind itself was honestly dropped.

That last bullet is the part with real defect-finding power, and it is available today because the
date axis of §2 already works.

### 4.4 XPASS must fail the run

An expected-failure that starts passing has to stop the build. It means either the residue
genuinely shrank — in which case the note is stale and must be retired deliberately — or a gate
weakened. Both need a human; neither should be silent.

> This is not hypothetical. `smucclaw/dmnmd`'s round-trip harness had exactly this bug: it printed
> its failures and exited 0. The fix was one line
> (`[ "$n_xpass" -gt 0 ] && exit 1`), and it was found only because someone stubbed the validator to
> `false` and noticed the run still went green. **Stub-the-checker is a cheap test worth running
> against `run-roundtrip.sh`'s and the engine harnesses' own exit paths.**

### 4.5 Stop gating on counts

`95 → 32 → 0 blocking` cannot distinguish *fixed* from *dropped* from *downgraded* — §1's table is
the proof, since the `D-RULEDATE-UNBOUND` family contributed 15 to that fall without one construct
becoming lowerable. Pin **per-note identity** — (decision × code × severity) as a set — so that a
note changing severity, or a construct silently ceasing to be emitted, is a diff a reviewer reads
rather than a number that improved.

`dmnmd`'s corpus is the same discipline: it records per-case stdout, stderr **and** exit status,
never a total, and splits cases into `policy/` (a diff is a regression) and `symptom/` (a diff is
progress). The severity axis here already has the right vocabulary; what it lacks is a gate that
notices when a note moves between levels.

## 5. Suggested order

1. **§4.5 first — it is cheap and independent.** Pin the fidelity report as a set of
   (decision, code, severity) triples. This alone would have made §1's downgrade a reviewable diff.
2. **§4.1 on `gst-rate`**, which is small, fully lowerable, and already exercises the date axis over
   10 cases. Prove the derived-cases loop end to end where the answer is known.
3. **§4.2 on the corpus**, where the 21 Lossy notes make the classification earn its keep.
4. **§4.3 last** — it needs 2 and 3, and it is where the remaining expressiveness gap actually lives.

## 5a. The prototype, and what it measured

`etc/dmn-differential/l4-derive-cases.py` (new, standalone, ~200 lines). Run on `gst-rate`:

```
$ python3 etc/dmn-differential/l4-derive-cases.py \
      l4 jl4/examples/dmn/gst-rate.l4 jl4/examples/dmn/gst-rate.cases.json -o derived.json
module ASSUMEs bound per case: ['no GST rate exists before commencement on 1994-04-01']
l4 exit=0
evaluations emitted : 60
  values harvested  : 60
  unparsed shapes   : 0
  no value returned : 0
hand-written vs L4-derived: 0 disagreement(s) over 60 shared expectation(s)

$ etc/kie-dmn-check/run.sh jl4/examples/dmn/expected/gst-rate.dmn --cases derived.json
KIE 8.44.0.Final VERDICT: 1 file(s), 10 case(s), 0 error(s), 0 warning(s),
  60/60 decision(s) SUCCEEDED, 60/60 value(s) as expected,
  50/50 service output value(s) as expected            # exit 0
```

**All 60 L4-derived expectations reproduce the hand-written ones exactly**, and KIE agrees with all
60 — so on this exhibit the DMN provably means what the L4 means, which is a stronger statement
than anything CI makes today.

**The negative control, which is what makes the green run worth anything.** Perturb the L4 (`THEN 9`
→ `THEN 7` in `GST rate percent`), re-derive, and re-run the *unchanged* golden DMN:

```
GST_rate_percent    SUCCEEDED  = 9   <<< EXPECTED 7
GST_payable_on      SUCCEEDED  = 90  <<< EXPECTED 70
svc out GST_payable_on         = 90  <<< EXPECTED 70
KIE ... 56/60 value(s) as expected, 48/50 service output value(s) as expected   <<< FAILED
```

Exit **1** on divergence, exit **0** on agreement — so it gates. It names the diverging decisions
and the cases they diverge in, which a blocking count cannot.

Three implementation notes that cost time and would cost it again:

- **Pair results by SOURCE LINE, not by position.** `l4 run` emits each `#EVAL` as a diagnostic
  carrying `Range: <line>:...` and `Source: eval`. Positional pairing silently misattributes every
  value after the first evaluation that fails to produce one.
- **`l4 run` prints a date as `DATE OF D, M, Y`** — day first — not as the `Date D M Y` constructor
  spelling. Anything unrecognised is reported as `$unparsed` rather than guessed at.
- **FEEL-name folding is not `replace(" ", "_")`.** The ASSUME
  `no GST rate exists before commencement on 1994-04-01` is keyed
  `no_GST_rate_exists_before_commencement_on_1994_04_01` — hyphens folded too. Getting this wrong
  fails to bind the assumption, and the decision then reports `UNEVALUABLE`; that is how the bug was
  found, and it is the reason a driver is generated **per case** (an `ASSUME` is declared without a
  value and cannot be shadowed, so binding it means replacing the declaration, and two cases may
  assume different values for the same name — `gst-rate`'s pre-commencement floor does exactly that).

## 6. Provenance — what was executed, and what was not

Executed at `origin/unstable` = `c873bb5d`, on 2026-08-04:

- severity decomposition of `regcf-corpus.fidelity.txt` (0 blocking / 21 lossy / 125 advisory) and
  the same at the #188 merge `973bdf93` (32 blocking, of which 16 `D-LITERALEXPR` + 15
  `D-RULEDATE-UNBOUND` + 1 `D-CYCLE`) — §1's table is a diff of those two measurements;
- the `D-RULEDATE-UNBOUND` note text quoted in §2, read verbatim from the golden;
- `gst-rate.fidelity.txt` showing `D-RULEDATE` **advisory**, confirming §2's claim that the date
  axis is deployed and not blocking;
- `KieDmnCheck.main`'s argument grammar (`FILE.dmn [--ctx|--cases]`), which is what §4.1 relies on;
- `pr-checks.yml`'s `dmn-engines` job, including that it cannot skip;
- the README's own statements that `reg-cf.cases.json` "is hand-written, not generated" and that
  the XML/markdown legs "are not two independent checks of the same thing".

Also executed, on 2026-08-04, with an `l4` built from `c873bb5d` itself (§5a):

- the full derive → engine loop on `gst-rate`, 60/60 both sides, KIE exit 0;
- the seeded-divergence negative control, KIE exit 1, naming the diverging decisions.

> **A binary from before `c873bb5d` will not do.** The one on this machine was built from
> `fe8d37d3` (PR #172) and **rejects the repo's own
> `doc/tutorials/multi-temporal-modeling/gst-rate-change-example.l4`** with
> `EVAL UNDER RULES EFFECTIVE AT ... expected NUMBER, is DATE`. Every measurement above was redone
> against a freshly built one; the first attempt at this prototype was written against the stale
> binary and every one of its 60 evaluations failed to typecheck.

**Not executed, and therefore not claimed:**

- **The Camunda leg was not run.** Only KIE. The design needs nothing from Camunda that KIE does not
  also provide (both take `--cases`), but that is an argument, not a measurement.
- **The corpus was not run** — only `gst-rate`, which is small, fully lowerable and has no Lossy
  notes. So §4.2's classification table is *designed and not exercised*: no `DIVERGE-DECLARED`,
  `ABSENT-DECLARED` or `XPASS` verdict has ever actually been produced. That is the next step and
  it is where the design could still be wrong.
- `read_signatures` parses `GIVEN`/`GIVETH` with regexes over source lines. It is adequate for
  `gst-rate` and should be replaced by something that asks the compiler before it meets the corpus.
- No claim is made about how expensive the derived-cases loop is in CI wall-clock.
- `EVAL UNDER VALID TIME` and `EVAL UNDER RULES ENCODED AT` exist alongside
  `EVAL UNDER RULES EFFECTIVE AT` and were **not** analysed; §4.3 may or may not extend to them.
- The interaction with `regcf-corpus.cases.json`'s 15 dated relocation cases was not examined;
  they may already do part of §4.3's per-date reconstruction, in which case that section is
  smaller than it reads.

## 7. One caveat about this document

It was written from outside the DMN-export work, by a session whose repo is `smucclaw/dmnmd`. The
finding in §1 and the gap in §3 are measurements and should stand on their own. §4's design is a
proposal from someone who has not maintained `Lower.hs`, and §5's ordering in particular is a guess
about cost that the owning session is better placed to make.

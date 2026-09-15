# Pre-registration — the repaired-benchmark (restored-fixture) arm

**Status: registered 2026-09-01, BEFORE any restored-arm trial ran.** **Adjudicated later the same day: outcomes against every prediction are in `../README.md` §5.3; this file stays frozen as the pre-data record.** The git history is the
timestamp: this file, `fixtures/chubb-policy-restored.txt`, `bench/keys-restored.json` and the
three `schema-restored*.md` files land in one commit, and no directory under
`trials/restored-k10/` exists at that commit. A restored-arm trial run before this commit
would be invalid; none was.

## 1. What is being tested

Kant et al. (arXiv 2502.17638) deleted the operative benefits machinery — §2 BENEFITS
(including the insuring clause and its sickness-or-accidental-injury trigger), §5 amounts, §6
signature — from Goodenough & Carlson's policy before benchmarking models on it, then scored
models against a key whose Q5 rests on the deleted clause (`source-defects.md`; the paper
calls the trigger "addressed indirectly in the contract" and its best model missed Q5 in 9 of
10 trials). The repaired arm re-runs our five-cell factorial on
`fixtures/chubb-policy-restored.txt` — the same document with exactly the deletion undone and
nothing else changed (`fixtures/chubb-policy-restored-NOTE.md`) — to measure what the
deletion did. The nine queries are unchanged. The gold values are unchanged
(`keys-restored.json`: restoration changes no gold, only its derivability).

## 2. Design

Two fixtures × five cells {vanilla, prolog-unguided, prolog-guided, l4-unguided, l4-guided}.
The as-published side is the k = 10 run already in flight under `trials/k10/`. The restored
side targets k = 10 per cell under `trials/restored-k10/`, run as session resources allow;
any smaller n is reported as what it is. Same encoder model family as every prior trial, same
wrapper prompts (only the staged fixture differs; it is staged under the same in-sandbox
filename so the prompts are byte-identical), same blindness-by-construction (no sandbox
contains a key), same conformance rules, same scorer (`bench.mjs` with
`--keys keys-restored.json`). Guided cells receive the `schema-restored-*` vocabulary —
`schema.md`'s 18 fields plus exactly the three fields restored §2.2/§2.3 require, derived
under the same clause-by-clause discipline and parity-checked (`check-schema-parity.mjs`).
"Guided" means _schema derived from the text being encoded_ in both arms.

One declared cross-arm difference besides the fixture: the as-published arm (pilot and k = 10)
ran with the memory-index contamination channel of `FOUNDATION.md` T9 present and constant —
the orchestration harness injects a project-memory index into every sub-agent, and its line for
this project carried result-adjacent content about the as-published fixture's deletion. The index
was sanitized after the last as-published launch and before any restored-arm staging, so the
restored arm runs without it. The channel's content concerned the as-published fixture, and the
empirical checks in T9 found no evidence it moved answers; its absence can only make the restored
arm cleaner.

## 3. Predictions

- **P1 (headline).** In each unguided cell, a **majority** of trials (≥ 6 of 10) agree with
  the Q5 gold on the restored fixture. Baseline for contrast: the as-published k = 10 Q5
  rate in the same cells, measured by `score-k10.sh` (at pilot k = 2 it was 0 of 4; the k=10
  number is whatever it is — P1 does not depend on it staying low, but the treatment-effect
  claim in the write-up does, so both are reported). Mechanism: the trigger is operative
  text; an encoder no longer has to invent the ground vocabulary to reach it.
- **P2.** Guided cells stay at or above their as-published Q5 rate — and their Q5 agreement
  is carried by a **rule**: the coverage definition tests the ground (or an equivalent
  trigger conjunct), verifiable by artifact inspection, rather than resting solely on a
  `neither`-valued fact. Count of restored guided trials whose coverage rule tests the
  ground is reported beside the count for as-published guided trials.
- **P3.** The vanilla cell's Q5 moves to majority gold-agreement ("No") on the restored
  fixture, from majority-Yes as-published. The clause is now quotable.
- **P4.** Mechanical items (per `keys-restored.json` Key B: items 1, 2, 3, 6, 7, 8, 9) stay
  at ceiling — 7/7 in every completed trial in every cell, both fixtures. Any mechanical
  miss is reported prominently; it would refute the claim that all variance sits in the
  interpretive items.
- **P5 (taxonomy test).** Q4 stays contested on the restored fixture: per-cell Q4
  gold-agreement changes by at most ±2 trials relative to the same cell as-published. Q4's
  defect is the query's missing hospitalization date, not the fixture's deletion, so
  restoration should not fix it. A large Q4 shift refutes that taxonomy entry. Registered
  fork: restored 2.2 (US-confinement benefit limit) versus 4.1.1 (worldwide application)
  gives encoders a new "apply vs payable" reading choice on the abroad element; if trial
  NOTES split on it, the fork was predicted here, and either reading reaches the Q4 gold.

## 4. What would change our conclusions

If P1 fails — unguided Q5 stays minority on the restored text — then the deletion was NOT
the binding constraint and our defect register over-weighted it; `source-defects.md` gets a
correction, not a defence. If P4 fails, the mechanical/interpretive frame itself is wrong
and the write-up must lead with that. If P3 fails while P1 holds, quotable text helps
formalisers more than free readers, which is itself a finding about where formalisation
earns its keep. Support for P1+P2+P3 with P4+P5 holding licenses exactly one sentence: _the
residual error the original attributes to its models on this item was manufactured by its
own edit_ — and nothing stronger.

## 5. Fixed before data

Fixture (`chubb-policy-restored.txt` + NOTE), key (`keys-restored.json`), schemas
(`schema-restored*.md`), scorer options (`--keys`), staging (`setup-restored.sh`), and this
document. Anything else changed after restored trials begin is reported as a deviation.

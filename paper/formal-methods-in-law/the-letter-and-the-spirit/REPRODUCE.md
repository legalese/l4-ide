# Reproducing "The Letter and the Spirit"

Every computational claim in `essay.md` is backed by a script that runs. This is
the reproduction manifest: what to install, what to run, what you should see.

```bash
bash reproduce.sh        # runs all four checks; prints PASS / FAIL / SKIP
```

Steps **SKIP cleanly** when an optional tool is missing, so the harness always
runs; install the tool to turn a SKIP into a PASS.

---

## The four artifacts

| # | Claim in the essay | Script | Engine |
|---|---|---|---|
| 1 | The four readings of "dishonest" classify the forged-degree case as `TRUE,FALSE,TRUE,TRUE`; Explanation 1 is otiose under the applicants' reading (GD [18],[28],[30],[32]) | `cheating-415-poh-yuan-nie.l4` | the **L4** evaluator |
| 2 | Surplusage is a *theorem*: under the applicants' reading concealment is a don't-care across the whole no-property region (proved); the counterexample class is found, not supplied | `cheating-415-surplusage.z3.py` | **Z3** (SAT/SMT) |
| 3 | The "dishonest concealment" literal **vanishes** from the minimised formula under the applicants' reading | `cheating-415-espresso.py` | **Espresso** (or Quine–McCluskey) |
| 4 | The argument draws — the otiose clause is a dead rung | `cheating-415-ladder.py` → `cheating-415-ladder.svg` | hand-rolled SVG |

The `.l4` is the **model**; everything else reasons over the *same* propositional
encoding of s 415 (2008). Steps 2 and 3 are independent decision procedures that
agree — Z3 *proves* the don't-care, Espresso *eliminates* it.

---

## Prerequisites

| Tool | Needed for | Install | Used here |
|---|---|---|---|
| `python3` | steps 2–4 | (system) | 3.x |
| `l4` | step 1 | `github.com/smucclaw/l4-ide` (or the VS Code extension's *Install L4 CLI*) | jl4 CLI |
| `uv` *or* global `z3` | step 2 | `astral.sh/uv` — then z3 is fetched per-run via `uv run --with z3-solver` | uv 0.9.x; z3 4.16.0 |
| `espresso` | step 3 *(optional)* | `./build-espresso.sh` — clone + `make` of the modern rehost | classabbyamp/espresso-logic @ `8526513` |
| `rsvg-convert` | step 4 *(optional, for PNG)* | `brew install librsvg` | 2.61.x |

**Step 3 needs nothing.** If the `espresso` binary is absent, the script falls
back to a bundled, exact **Quine–McCluskey** minimiser (Python stdlib only) and
prints which engine it used. When `espresso` *is* present, the script runs it
**and** cross-checks its result against Quine–McCluskey, asserting the two agree
on which literals survive — so "the literal vanishes" does not rest on one tool.

### Why a hand-built Espresso

`pyeda` (the usual Python Espresso wrapper) no longer compiles under modern
clang, and the Homebrew Python 3.14 in this environment has a broken `pip`
(libexpat symbol mismatch). The modern C rehost builds cleanly:

```bash
./build-espresso.sh            # → ~/.local/bin/espresso
```

---

## Expected output (abridged)

```
[1] L4 model …            PASS  l4 run: all assertions satisfied, no failures
[2] Z3 …                  PASS  z3: 2 theorems PROVED; counterexample class WITNESS-ed
[3] Minimiser …           PASS  literal eliminated  (genuine Berkeley Espresso …)
[4] Ladder figure …       PASS  ladder SVG regenerated (…bytes)
  4 passed, 0 failed
```

Individual runs:

```bash
l4 run cheating-415-poh-yuan-nie.l4              # the 4-reading #EVAL table + #ASSERTs
uv run --with z3-solver python cheating-415-surplusage.z3.py
python3 cheating-415-espresso.py                 # watch DISHONEST-CONCEALMENT get ELIMINATED
python3 cheating-415-ladder.py                   # regenerate the figure
```

---

## Provenance

- **Case text**: *Poh Yuan Nie v Public Prosecutor* [2022] SGCA 74, Grounds of
  Decision (Sundaresh Menon CJ, Judith Prakash JCA, Steven Chong JCA, 21 Nov
  2022). Bracketed `[n]` are the court's paragraph numbers. Statute: Penal Code
  (Cap 224, **2008** Rev Ed) — two limbs + Explanations 1–3.
- **Model of record**: `cheating-415-poh-yuan-nie.l4` (canonical copy in the
  `l4-ide` repo, `jl4/ok/inert/`).
- All four scripts encode the *same* eleven boolean atoms and two readings; the
  cross-engine agreement (L4 ≈ Z3 ≈ Espresso ≈ Quine–McCluskey) is itself a check.

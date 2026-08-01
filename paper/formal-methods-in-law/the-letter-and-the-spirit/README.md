# The Letter and the Spirit

_A public-facing essay: how an exam-cheating case became a proof — and what that
tells us about unifying law and computer science._

This is the fully-worked, reproducible **Poh Yuan Nie** exhibit for the
`formal-methods-in-law` facet. It is the concrete companion to
[`../FORMAL-PAPER.md`](../FORMAL-PAPER.md) **§4.2** (the Boolean / logic-minimisation
rung of the ladder), and it instantiates the paper's slogan in one real case:
\*a Boolean argument is a contradiction-**detector**, never a contradiction-**resolver\***.

The essay walks the three mechanical moves the Singapore Court of Appeal made in
_Poh Yuan Nie v PP_ [2022] SGCA 74 — **enumerate** the four readings of "dishonest,"
**find** the forged-degree counterexample, **prove** Explanation 1 _otiose_ — and
shows each is something a machine can do, while the fourth move (pronouncing the
outcome _absurd_) is the irreducibly judicial one.

## Contents

| File                                       | What it is                                                                                                            |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------- |
| `essay.md`                                 | The essay itself ("The Letter and the Spirit").                                                                       |
| `REPRODUCE.md`                             | The reproduction manifest — what to install, what to run, what you should see.                                        |
| `reproduce.sh`                             | One command that re-runs all four checks and prints PASS / FAIL / SKIP.                                               |
| `cheating-415-poh-yuan-nie.l4`             | The **model of record**: s415 as an L4 `CONSIDER` over four interpretations (canonical copy also in `jl4/ok/inert/`). |
| `cheating-415-surplusage.z3.py`            | Z3 proof that concealment is a don't-care across the no-property region (surplusage as a theorem).                    |
| `cheating-415-espresso.py`                 | The minimiser that _deletes_ the dead literal (Espresso, cross-checked against Quine–McCluskey).                      |
| `cheating-415-ladder.py` → `.svg` / `.png` | The s415 second limb as a relay ladder; the otiose clause as a dead rung.                                             |
| `build-espresso.sh`                        | Optional: builds the Berkeley Espresso binary from the modern rehost.                                                 |

## Reproducing

```bash
bash reproduce.sh        # runs all four checks; steps SKIP cleanly if a tool is absent
```

The `.l4` model is bundled here, so `reproduce.sh` finds it via its first lookup
path (`./cheating-415-poh-yuan-nie.l4`) and the bundle is self-contained.

## Provenance

Imported from the `layman` Next.js app in the `legalese/sandbox` repo
(`mengwong/layman/`), which renders `essay.md` at its `/essay` route. Only the
prose + reproducibility artifacts travel here; the rendering harness stays in
`sandbox`. Case text: _Poh Yuan Nie v Public Prosecutor_ [2022] SGCA 74; statute:
Penal Code (Cap 224, 2008 Rev Ed) s 415.

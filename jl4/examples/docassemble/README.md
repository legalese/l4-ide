# L4 → docassemble bridge (v1) — example corpus

`l4 docassemble FILE` compiles the **decision-rule subset** of an L4 file into
a single docassemble interview YAML that a stock docassemble server (or the
headless harness below) runs unmodified. Design and rulings R1–R11:
`specs/todo/DOCASSEMBLE-EXPORT-SPEC.md`.

_Status: M1 (corpus, backend, goldens and harness) landed 2026-08-16 on branch
`mengwong/docassemble-backend`; the same day a review pass repaired five
defects and added the `computed-and-shadow` / `assume-via-fn` exhibits. The
`expected/` goldens are committed and pinned by the `l4 docassemble` cases in
`jl4/tests-cli/Main.hs`; the sixteen M1 round-trip cases below were run green
against `docassemble.base` 1.10.7 (local checkout, commit `1b6678384`) in the
venv recipe of this README._

_**M2 is not implemented.** Its acceptance tests were written fail-first on
2026-08-17 and are red: `--package` does not exist, `@ref` never reaches the
docassemble lowerer, and no `explain()` / `logic_explanation()` /
`auto terms:` is emitted. The `citations` corpus file and the last two rows of
the #EVAL table below belong to M2; see "M2 acceptance tests — RED"._

The organising principle: **as much as possible of an L4 encoding survives, by
name and by structure.** An L4 reader and a docassemble reader should
recognise the same program.

| L4                                            | docassemble                                                            |
| --------------------------------------------- | ---------------------------------------------------------------------- |
| `@export` `DECIDE`/`MEANS` goal               | goal variable via a `code:` block; single `mandatory` driver           |
| `GIVEN p IS A <Record>`                       | `objects:` instance — plain `DAObject` in v1, subclasses with M2 (R2)   |
| stored record field                           | one specific-instance `question:` per field; label = the L4 name (R2)  |
| `WHERE` binding, zero-`GIVEN`                 | one namespaced `code:` block each, `depends on:` its inputs (R3)       |
| top-level `IMPLIES` in an exported decision   | scope-first driver + six-valued verdict — never `not scope or req` (R4)|
| `AND`/`OR`/`NOT`, comparisons                 | Python operators; operand order preserved = question order (R5)        |
| `IS ONE OF` (nullary constructors)            | `datatype: radio`, values = constructor names as strings (R6)          |
| `CONSIDER … WHEN … OTHERWISE`                 | `if…elif…else` over `==` string comparisons (R6)                       |
| `TYPICALLY`                                   | `default:` prefill, Advisory note (R7)                                 |
| `MAYBE BOOLEAN`                               | `yesnomaybe` — `None` IS `NOTHING`, exact (R8)                         |
| `MAYBE STRING`                                | `required: False`, `''` read as `NOTHING`, Advisory (R8)               |
| `MAYBE NUMBER`/`MAYBE DATE`                   | **refused** in v1 (empty number submits as `0`, not `None`) (R8)       |
| deontic / temporal / ledger constructs        | **refused**, `L4.Interchange.Fidelity` notes (spec §5)                 |
| `@desc`                                       | question text / field `help:`, Mako-escaped (R9)                       |
| `#EVAL`                                       | round-trip oracle input (R10); **not emitted** into the interview      |

## Files

- `rodents-and-vermin.l4` — `jl4/examples/ok/rodentsAndVermin.l4` plus
  `@export`; its five `WHERE` bindings are the legal structure and must
  survive as five named `code:` blocks (the R3 golden).
- `seam.l4` — scope-`IMPLIES`-requirement landlord-notice rule; #EVALs cover
  the Complies / InBreach / NotApplicable verdicts (the R4 golden).
- `enum-triage.l4` — 3-way `IS ONE OF` enum + `CONSIDER` with `OTHERWISE`;
  one #EVAL per arm (the R6 golden).
- `defaults.l4` — `TYPICALLY` prefill + `MAYBE BOOLEAN` + `MAYBE STRING`,
  present and absent paths (the R7/R8 golden). Its `promotional code used`
  `@desc` deliberately begins with `%` and contains a literal `${ ... }`, so
  the R9 Mako escaping is exercised by the corpus, not assumed.
- `computed-and-shadow.l4` — a stored field named `alternative` (a DAObject
  method name, so it must sanitise to `alternative_` or the interview
  silently returns a wrong verdict) plus a computed (`MEANS`) field, which
  survives by inlining its desugar-synthesized selector (R2 repairs golden).
- `assume-via-fn.l4` — an `ASSUME` referenced only through an inlined
  parameterized `DECIDE`; its question block must still be emitted (R3
  repair golden). No `#EVAL`: `ASSUME` is uninterpreted, so the round-trip
  expectations for this one example are hand-computed in the fixture table.
- `expected/*.yml` (+ `*.fidelity.txt` sidecars) — committed golden output,
  pinned byte-exact by the `l4 docassemble` cases in `jl4/tests-cli/Main.hs`.
- `not-ok/` — fixtures the backend must REFUSE, each with a named diagnostic:
  - `deontic-body.l4` — regulative body (`PARTY`/`MUST`): `Regulative`,
    Blocking.
  - `maybe-number.l4` — `MAYBE NUMBER` given: refused by name per R8 pending
    the M4 paired is-known design.
  - `name-collision.l4` — `` `notice period` `` and `notice_period` sanitise
    to one Python identifier: `checkCollisions` rejection.
  - `higher-order.l4` — function-valued `WHERE` binding passed as an
    argument, not directly applied: un-inlinable, refused by name.
  - `seam-ref-via-fn.l4` — a seam-shaped export referenced by another
    decision *through an inlined function*: the R4 dangling-goal guard must
    see references that travel through inlined bodies.
  - `just-payload-pattern.l4` — `WHEN JUST TRUE`: a payload-value match, not
    a binder; the R8 presence erasure cannot express it, refused by name.
- `citations.l4` — **the M2 example; its M2 behaviour is NOT implemented**
  (see the RED section below). Three sub-decisions, each carrying a statutory
  `@ref`, conjoined by `AND` so a FALSE first conjunct short-circuits the
  other two away. One ref uses the plain `@ref …` form, one the inline
  `<<…>>` form, and the third is deliberately Mako-hostile (it begins with
  `%` and contains a literal `${ … }`) — the same discipline `defaults.l4`
  applies to `@desc`, applied to `@ref`. Today `l4 docassemble
  citations.l4` emits a correct interview that carries **no** citations, no
  `explain()` and no `auto terms:` glossary; that is what M2 has to change.
  It has no `expected/citations.yml` golden on purpose: R11 and the RED
  phase both say the M2 surface gets shape assertions, not a byte golden
  written before the feature exists.
- `roundtrip_check.py` — drives the emitted interview headlessly in real
  `docassemble.base` and asserts the verdict/goal equals the L4 `#EVAL`
  oracle (fixture table in the file; one case per #EVAL).

## Regenerate the golden output

```sh
cabal run l4 -- docassemble jl4/examples/docassemble/rodents-and-vermin.l4 -o jl4/examples/docassemble/expected/rodents-and-vermin.yml
cabal run l4 -- docassemble jl4/examples/docassemble/seam.l4               -o jl4/examples/docassemble/expected/seam.yml
cabal run l4 -- docassemble jl4/examples/docassemble/enum-triage.l4        -o jl4/examples/docassemble/expected/enum-triage.yml
cabal run l4 -- docassemble jl4/examples/docassemble/defaults.l4           -o jl4/examples/docassemble/expected/defaults.yml
cabal run l4 -- docassemble jl4/examples/docassemble/computed-and-shadow.l4 -o jl4/examples/docassemble/expected/computed-and-shadow.yml
cabal run l4 -- docassemble jl4/examples/docassemble/assume-via-fn.l4      -o jl4/examples/docassemble/expected/assume-via-fn.yml
```

(With an installed binary: `l4 docassemble X.l4 -o expected/X.yml`.)

## Prove it runs in real docassemble (defensibility)

The R10 harness drives `docassemble.base` fully in-process — no server, no
Redis, no Flask. Recipe per spec §8.10 (proven by the executed probe at
`specs/todo/docassemble-export/probe_headless.py`, spec Appendix B):

```sh
uv venv --python 3.12 /tmp/da-venv
uv pip install --python /tmp/da-venv/bin/python "docassemble.base==1.10.*"
```

That installs `docassemble.base` **from PyPI, pinned to 1.10.\*** (the pluggy
plugin seam the harness relies on is new in 1.10.0). The path actually
validated by the green run recorded above is the local checkout at
`/Volumes/transcend/src/jhpyle/docassemble/docassemble_base` (commit
`1b6678384`, v1.10.7):

```sh
uv pip install --python /tmp/da-venv/bin/python /Volumes/transcend/src/jhpyle/docassemble/docassemble_base
```

Then:

```sh
cabal run l4 -- docassemble jl4/examples/docassemble/seam.l4 -o /tmp/seam.yml
/tmp/da-venv/bin/python jl4/examples/docassemble/roundtrip_check.py /tmp/seam.yml seam
# == round-trip: seam == (12 blocks, debug=True)
#   [Complies] notice_rule_satisfied_verdict = 'Complies'  OK
#   [InBreach] notice_rule_satisfied_verdict = 'InBreach'  OK
#   [NotApplicable] notice_rule_satisfied_verdict = 'NotApplicable'  OK   <- no requirement question asked
# ROUND-TRIP OK
```

The harness's non-obvious ingredients, each found the hard way (spec §8.10;
all already handled inside `roundtrip_check.py`):

1. **pyzbar stub** — `pyzbar` is stubbed in `sys.modules` before importing
   `docassemble.base.util`, so import succeeds without libzbar. Clean
   alternative: `brew install zbar`.
2. **HeadlessPlugin** — a ~13-hookimpl `pluggy` plugin (`get_configuration`,
   `get_default_language/dialect/locale/voice/timezone/country`,
   `get_debug_status`, `get_hostname`, `get_main_page_parts`, table classes,
   `url_finder`, `absolute_filename`) registered on
   `docassemble.base.plugin_manager.pm` — the 1.10.0 seam that replaces the
   old server monkey-patching.
3. **`get_configuration` serves the config dict directly** — no
   `config.load`, no `config.yml` on disk. The dict carries `debug` (default
   `True`; `--quiet` turns it off) because the engine only records its
   seeking history under debug.
4. **contextvar scope** — everything runs inside
   `global_context(empty_globals())`.
5. **the `action` key must be ABSENT from `current_info`** —
   `process_action` tests `'action' not in current_info`, so `action: None`
   force-asks a `None` variable and crashes assemble. (`user` needs
   `session_uid` and `device_id`.)
6. **never import `docassemble.base.interview_cache`** — its `get_index`
   hits `get_server_redis` unconditionally.

Per the repo topology rule, the harness is local evidence only: pinned in
this README, run by hand in the venv, never referenced by CI and never a
build dependency.

### Driving a package tree, and comparing two sources

```
python roundtrip_check.py <source> <example-name> [--also=<source>] [--quiet]
```

`<source>` is **either** a bare interview YAML **or** a `l4 docassemble FILE
--package DIR` tree (M2/R11); the two are told apart by `os.path.isdir`, and a
package tree is resolved to its
`docassemble/l4<slug>/data/questions/<stem>.yml`, with the package name and
`sys.path` entry that make its `modules: [.l4runtime]` block importable —
docassemble execs it as `from <question.package>.l4runtime import *`
(`parse.py:8569-8573` at `1b6678384`).

`--also=<source>` (repeatable) drives the **same** example against a second
source and asserts the per-case `(goal, verdict, citations)` triple is
identical. That is the M2 claim _packaging must not change meaning_, tested as
a claim:

```sh
l4 docassemble jl4/examples/docassemble/citations.l4 -o /tmp/citations.yml
l4 docassemble jl4/examples/docassemble/citations.l4 --package /tmp/citepkg
/tmp/da-venv/bin/python jl4/examples/docassemble/roundtrip_check.py \
    /tmp/citations.yml citations --also=/tmp/citepkg
```

## M2 acceptance tests — RED, the feature is NOT implemented

_Written 2026-08-17 as the fail-first half of M2 (spec §10). `--package` does
not exist, `@ref` never reaches the docassemble lowerer, and nothing emits
`explain()` / `logic_explanation()` / `auto terms:`. The tests below therefore
FAIL, deliberately, and they are the contract the implementation has to meet._

What is red, and where:

- `jl4/tests-cli/Main.hs`, `describe "l4 docassemble --package (M2/R11: …)"`
  — nine shape assertions over the written tree (PEP 420 shape including the
  namespace `__init__.py` that must be **absent**, `pyproject.toml`,
  `MANIFEST.in`, byte-identical `data/sources` provenance, the `modules:`
  wiring, no empty directories, determinism, the `--package`/`--output`
  refusal, and a hostile-filename slug).
- `jl4/tests-cli/Main.hs`, `describe "l4 docassemble citations (M2: …)"` —
  six assertions over the emitted interview (per-rule `explain()` with that
  rule's own citation and **not** its neighbour's, `logic_explanation()` on
  every verdict screen, one `auto terms:` block carrying the L4 defined
  terms, herald/delimiter stripping, Mako escaping, and the emitter's own
  key vocabulary).
- `roundtrip_check.py`'s `citations` example — the claim that makes the
  milestone worth having: on the `cap exceeded` path the verdict screen must
  cite `17 CFR 227.100(a)(1)` **and nothing else**, because the other two
  rules were short-circuited away and decided nothing.

What is _not_ red and must stay green through M2: the six `expected/*.yml`
goldens, the six `expected/*.fidelity.txt` sidecars (now pinned by a test,
which they were not before), the `not-ok/` refusals, and the six round-trip
examples above.

## The #EVAL expectation table (mirrored in `roundtrip_check.py`)

| example | case | inputs | L4 #EVAL | docassemble assertion |
| --- | --- | --- | --- | --- |
| rodents-and-vermin | all-false | all ten fields FALSE | FALSE | `insurance_covered` = False |
| seam | Complies | residential T, notice T, months 3 | TRUE | verdict `Complies` |
| seam | InBreach | residential T, notice T, months 1 | FALSE | verdict `InBreach` |
| seam | NotApplicable | residential F (only fixture supplied) | TRUE | verdict `NotApplicable`, no requirement question asked |
| enum-triage | Critical | severity `Critical` | 3 | `notification_deadline_in_days` = 3 |
| enum-triage | Reportable | severity `Reportable` | 30 | = 30 |
| enum-triage | Trivial | severity `Trivial` (OTHERWISE arm) | 0 | = 0 |
| defaults | both absent | distance T, waiver `None`, promo `''` | TRUE | `the_consumer_may_cancel` = True |
| defaults | waiver present | distance T, waiver `True` (promo pruned) | FALSE | = False |
| defaults | FINAL-SALE code | distance T, waiver `False`, promo `"FINAL-SALE"` | FALSE | = False |
| defaults | ordinary code | distance T, waiver `False`, promo `"SPRING10"` | TRUE | = True |
| computed-and-shadow | lawful | salary 3500, alternative F | TRUE | `offer_lawful` = True (the shadow detector) |
| computed-and-shadow | alternative defeats | salary 3500, alternative T | FALSE | = False |
| computed-and-shadow | below minimum | salary 2000 (alternative pruned) | FALSE | = False, no alternative question asked |
| assume-via-fn | over | amount 60, base rate 50 | (hand-computed) TRUE | `over_threshold` = True |
| assume-via-fn | under | amount 30, base rate 50 | (hand-computed) FALSE | = False |
| citations | exempt | raised 1 000 000, one intermediary T, registered T | TRUE | `offering_exempt` = True; **RED:** screen cites all three rules, in order |
| citations | cap exceeded | raised 9 000 000 (only fixture supplied) | FALSE | = False, no rule-2/3 question asked; **RED:** screen cites `17 CFR 227.100(a)(1)` and nothing else |

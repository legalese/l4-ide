# L4 → docassemble bridge (v1) — example corpus

`l4 docassemble FILE` compiles the **decision-rule subset** of an L4 file into
a single docassemble interview YAML that a stock docassemble server (or the
headless harness below) runs unmodified. Design and rulings R1–R11:
`specs/todo/DOCASSEMBLE-EXPORT-SPEC.md`.

_Status: corpus, backend, goldens and harness all landed 2026-08-16 on branch
`mengwong/docassemble-backend`. The `expected/` goldens are committed and
pinned by the `l4 docassemble` cases in `jl4/tests-cli/Main.hs`; all eleven
round-trip cases below were run green against `docassemble.base` 1.10.7
(local checkout, commit `1b6678384`) in the venv recipe of this README._

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
- `roundtrip_check.py` — drives the emitted interview headlessly in real
  `docassemble.base` and asserts the verdict/goal equals the L4 `#EVAL`
  oracle (fixture table in the file; one case per #EVAL).

## Regenerate the golden output

```sh
cabal run l4 -- docassemble jl4/examples/docassemble/rodents-and-vermin.l4 -o jl4/examples/docassemble/expected/rodents-and-vermin.yml
cabal run l4 -- docassemble jl4/examples/docassemble/seam.l4               -o jl4/examples/docassemble/expected/seam.yml
cabal run l4 -- docassemble jl4/examples/docassemble/enum-triage.l4        -o jl4/examples/docassemble/expected/enum-triage.yml
cabal run l4 -- docassemble jl4/examples/docassemble/defaults.l4           -o jl4/examples/docassemble/expected/defaults.yml
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

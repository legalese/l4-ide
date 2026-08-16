# L4 → docassemble bridge — example corpus

`l4 docassemble FILE` compiles the **decision-rule subset** of an L4 file into
a single docassemble interview YAML that a stock docassemble server (or the
headless harness below) runs unmodified. `l4 docassemble FILE --package DIR`
compiles the same thing into an installable docassemble package instead.
Design and rulings R1–R11: `specs/todo/DOCASSEMBLE-EXPORT-SPEC.md`.

_Status: M1 (corpus, backend, goldens and harness) landed 2026-08-16 on branch
`mengwong/docassemble-backend`; the same day a review pass repaired five
defects and added the `computed-and-shadow` / `assume-via-fn` exhibits._

_**M2 landed 2026-08-17** on branch `mengwong/docassemble-m2`, test-first: the
acceptance tests were written red first (commit `178b4946`) and the
implementation made them pass. It ships `--package DIR`, the `.l4` source
embedded byte-identically under `data/sources`, the generated runtime module
loaded through `modules:`, `@ref` citations carried by `explain()` and rendered
by `logic_explanation()` on every verdict screen, and the `auto terms:`
glossary. The seven `expected/` goldens are committed and pinned by the
`l4 docassemble` cases in `jl4/tests-cli/Main.hs` (33 cases across three
`describe` blocks), and every example below was run green against
`docassemble.base` 1.10.7 (local checkout, commit `1b6678384`) from **both**
artifact shapes — see "Prove it runs in real docassemble". M3 (the embedded
query plan) and M4 (`LIST OF`, payload constructors, date arithmetic, document
assembly) remain unimplemented._

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
| `@desc` on a field or parameter               | question text / field `help:`, Mako-escaped (R9)                       |
| `@desc` on a `DECLARE` or a named definition  | one `auto terms:` glossary entry, keyed on the L4 term (M2)            |
| `@ref` on a `DECIDE` or `WHERE` binding       | `explain()` in that rule's own `code:` block (M2)                      |
| `@ref` on an expression                       | **nothing** — no `code:` block to hang it on; `DA-REF-EXPR` advisory   |
| the rules that actually fired                 | `logic_explanation()` on every verdict screen (M2)                     |
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
- `citations.l4` — the M2 example. Three sub-decisions, each carrying a
  statutory `@ref`, conjoined by `AND` so a FALSE first conjunct
  short-circuits the other two away. One ref uses the plain `@ref …` form, one
  the inline `<<…>>` form, and the third is deliberately Mako-hostile (it
  begins with `%` and contains a literal `${ … }`) — the same discipline
  `defaults.l4` applies to `@desc`, applied to `@ref`. Each rule's citation
  lands in its own `code:` block, so the verdict screen names exactly the
  rules that fired; the `DECLARE`d type and the three `MEANS` bindings become
  the `auto terms:` glossary.
- `roundtrip_check.py` — drives the emitted interview headlessly in real
  `docassemble.base` and asserts the verdict/goal equals the L4 `#EVAL`
  oracle (fixture table in the file; one case per #EVAL). For the `citations`
  example it additionally asserts the exact ordered citation list, the
  citations' presence in the **rendered** screen, and the parsed
  `auto terms:` glossary.
- `probe_generic_object.py` — the R2 experiment spec §8.2 cites when it defers
  the `generic object` question layer to M4: it drives the same interview with
  and without a generic layer and shows the specific-instance question wins
  every time, so the layer is inert in a v1 interview. Run by hand in the same
  venv: `python probe_generic_object.py /tmp/citations.yml`.

## Regenerate the golden output

Each run writes two goldens — the interview and its `.fidelity.txt` sidecar —
and both are pinned by `jl4/tests-cli/Main.hs`. Run from the repo root:

```sh
for stem in rodents-and-vermin seam enum-triage defaults \
            computed-and-shadow assume-via-fn citations; do
  cabal run -v0 l4 -- docassemble "jl4/examples/docassemble/$stem.l4" \
      -o "jl4/examples/docassemble/expected/$stem.yml"
done
```

(With an installed binary: `l4 docassemble X.l4 -o expected/X.yml`.)

**Read the diff before committing a regenerated golden.** Blessing output you
have not looked at is how a wrong answer becomes the expected answer.

## Emit an installable package instead (M2, R11)

```sh
l4 docassemble jl4/examples/docassemble/citations.l4 --package /tmp/citepkg
```

writes the modern PEP 420 tree — exemplar `docassemble_demo/` at the 1.10.7
pin:

```
/tmp/citepkg/pyproject.toml                   name = "docassemble.l4citations"
/tmp/citepkg/MANIFEST.in                      graft docassemble/l4citations/data
/tmp/citepkg/citations.fidelity.txt           the loss report, shipped in the sdist
/tmp/citepkg/docassemble/l4citations/__init__.py
/tmp/citepkg/docassemble/l4citations/l4runtime.py
/tmp/citepkg/docassemble/l4citations/data/questions/citations.yml
/tmp/citepkg/docassemble/l4citations/data/sources/citations.l4    byte-identical
```

There is deliberately **no** `docassemble/__init__.py`: with this pyproject
shape setuptools uses PEP 420 namespace finding, and a namespace `__init__.py`
would shadow the installed `docassemble.base`.

Things worth knowing:

- The package directory is `l4<slug>`, `<slug>` being the source file's own
  basename lower-cased and reduced to ASCII alphanumerics. Neither obvious
  source works: the module's URI is percent-encoded (`2024 Café Rules v2.1.l4`
  arrives as `2024%20Caf%C3%A9%20Rules%20v2.1.l4`) and the variable sanitiser
  keeps non-ASCII letters (`café_münze_2024`).
- `--package` and `-o` are refused together, by name: they are two different
  artifact shapes.
- Regenerating over a tree this command wrote is fine and silent. A directory
  holding anything else is refused — a package is a thing people edit. Note
  that regeneration writes but never deletes, so `rm -rf` the directory if the
  generated shape itself has changed.
- `pyproject.toml` carries `license = "LicenseRef-UNSPECIFIED"`. The package
  holds *your* rules, whose licence this compiler cannot know; replace it with
  the SPDX expression that governs them before publishing.

Executed against the generated tree (`setuptools` 83.0.0, Python 3.12):

```
$ python -c "from setuptools import build_meta as bm; bm.build_wheel('/tmp/out'); bm.build_sdist('/tmp/out')"
wheel  docassemble/l4citations/{__init__.py,l4runtime.py,
                                data/questions/citations.yml,
                                data/sources/citations.l4}
sdist  the same, plus MANIFEST.in, pyproject.toml and citations.fidelity.txt
```

Both artifacts carry the interview and the embedded `.l4`; neither contains a
`docassemble/__init__.py`. The fidelity report ships in the sdist only —
`MANIFEST.in` governs the sdist, and a root-level file is not package data.

## Push it to a docassemble server

Two routes. Neither is exercised by any test here: they need a running server,
and per the repo topology rule this corpus never depends on one.

**1. `dainstall`** — the developer loop, from the separate `docassemble-cli`
distribution (`pip install docassemble-cli`; it is *not* part of the
docassemble monorepo, so nothing in the 1.10.7 checkout pins its behaviour).
Point it at the generated directory:

```sh
l4 docassemble myrules.l4 --package /tmp/myrulespkg
dainstall --playground --watch /tmp/myrulespkg     # iterate
dainstall /tmp/myrulespkg                          # install server-wide
```

YAML-only redeploys skip the server restart; any `.py` change forces one, so
regenerating after an L4 edit that only moves rules around is cheap. Playground
project names must not start with a digit — `l4<slug>` never does.

**2. `POST /api/package`** — the scriptable route, and the one this repo can
cite: `docassemble_webapp/docassemble/webapp/packages/api.py:36` at
`1b6678384`. It accepts exactly one of `zip` (a file upload), `github_url`, or
`pip`, requires an API key whose user is admin/developer with the
`manage_packages` permission, and returns a task id to poll at
`/api/package_update_status` (`api.py:214`).

```sh
l4 docassemble myrules.l4 --package /tmp/myrulespkg
( cd /tmp && zip -qr /tmp/myrulespkg.zip myrulespkg )
curl -X POST https://YOUR-SERVER/api/package \
     -H "X-API-Key: $DA_API_KEY" \
     -F zip=@/tmp/myrulespkg.zip
```

The zip route reads the package's name out of the **shallowest
`pyproject.toml`** in the archive — `tomli.loads(...)['project']['name']`,
`docassemble_webapp/.../packages/helpers.py:89-141` — and only falls back to
`setup.py` when one exists. Executed here on a zip of the generated tree, with
that extraction replicated line for line: `setup.py found: None`, `package name
docassemble would install: docassemble.l4citations`. So the setup.py-free PEP
420 shape uploads as-is; no `dacreate` scaffolding is needed.

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
    /tmp/citations.yml citations --also=/tmp/citepkg --quiet
```

Run that way over all seven examples, 2026-08-17, against the 1.10.7 checkout
(abridged to one line per source; every case inside each run printed `OK`):

```
== round-trip: rodents-and-vermin ==  [yaml] (19 blocks)  [package] (20 blocks)  AGREEMENT OK  ROUND-TRIP OK
== round-trip: seam ==                [yaml] (12 blocks)  [package] (13 blocks)  AGREEMENT OK  ROUND-TRIP OK
== round-trip: enum-triage ==         [yaml]  (5 blocks)  [package]  (6 blocks)  AGREEMENT OK  ROUND-TRIP OK
== round-trip: defaults ==            [yaml] (10 blocks)  [package] (11 blocks)  AGREEMENT OK  ROUND-TRIP OK
== round-trip: computed-and-shadow == [yaml]  (7 blocks)  [package]  (8 blocks)  AGREEMENT OK  ROUND-TRIP OK
== round-trip: assume-via-fn ==       [yaml]  (6 blocks)  [package]  (7 blocks)  AGREEMENT OK  ROUND-TRIP OK
== round-trip: citations ==           [yaml] (11 blocks)  [package] (12 blocks)  AGREEMENT OK  ROUND-TRIP OK
```

The package tree is one block larger in every case: that is the `modules:`
block, which is emitted into the packaged interview only. The `citations` run
in full:

```
  [glossary] 4 L4 defined terms present  OK
  [exempt (all three rules fire)] offering_exempt = True;
      citations ['17 CFR 227.100(a)(1) — offering maximum',
                 '17 CFR 227.100(a)(3) — sales through one intermediary only',
                 '% of the proceeds retained is set out at ${ fee_schedule } — 17 CFR 227.300(a)'];
      screen cites all three  OK
  [cap exceeded (rules 2 and 3 short-circuited away)] offering_exempt = False;
      citations ['17 CFR 227.100(a)(1) — offering maximum']; screen cites it  OK
```

The third citation is the one that matters: it begins with `%` and carries a
literal `${ … }`, and it arrives on the **rendered** screen verbatim. That is
only provable after Mako has run, which is why the assertion lives in the
harness and not in a YAML golden.

## M2 acceptance tests — written RED first, now GREEN

_The M2 tests were written fail-first on 2026-08-17 (commit `178b4946`, 15
failing cases) and the implementation was written against them. They are the
contract M2 had to meet, and they now pass; what follows is what each block
pins, so a later change knows what it is breaking._

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
  key vocabulary), plus the `expected/citations.yml` byte golden that the RED
  phase deferred to the implementation and the GREEN phase supplied.
- `roundtrip_check.py`'s `citations` example — the claim that makes the
  milestone worth having: on the `cap exceeded` path the verdict screen cites
  `17 CFR 227.100(a)(1)` **and nothing else**, because the other two rules
  were short-circuited away and decided nothing.

What stayed green throughout, deliberately: the six M1 `expected/*.yml`
goldens are **byte-identical** after M2, because the `auto terms:` block, the
`explain()` calls and the `logic_explanation()` screen section are each emitted
only when the module actually carries the annotation they come from — and none
of the six does. Same for the six `.fidelity.txt` sidecars, the `not-ok/`
refusals, and the six round-trip examples.

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
| citations | exempt | raised 1 000 000, one intermediary T, registered T | TRUE | `offering_exempt` = True; screen cites all three rules, in order |
| citations | cap exceeded | raised 9 000 000 (only fixture supplied) | FALSE | = False, no rule-2/3 question asked; screen cites `17 CFR 227.100(a)(1)` and nothing else |

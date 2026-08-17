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
glossary. An adversarial review pass the same day repaired what survived
refutation, and corrected what it found to be false (see "What the review pass
changed"). The seven `expected/` goldens are committed and
pinned by the `l4 docassemble` cases in `jl4/tests-cli/Main.hs` (41 cases across
four `describe` blocks), and every example below was run green against
`docassemble.base` 1.10.7 (local checkout, commit `1b6678384`) from **both**
artifact shapes — see "Prove it runs in real docassemble". M3 (the embedded
query plan) and M4 (`LIST OF`, payload constructors, date arithmetic, document
assembly) remain unimplemented._

_**M4 is NOT implemented; its acceptance tests are written and RED**
(2026-08-17, branch `mengwong/docassemble-m4`). Six new examples are in this
directory — `tenant-list`, `payload-enum`, `maybe-scalars`, `statutory-age`,
`review-checklist`, `notice-letter` — and each typechecks and evaluates in L4,
so its `#EVAL`s are a real oracle; none has an `expected/` golden, because
writing one before the feature exists would force the implementer to match
formatting choices the RED phase has no basis to decide (M2 set that
precedent). `l4 docassemble` refuses four of the six outright, by name;
`review-checklist` and `notice-letter` emit but carry neither a `review:`
block nor an `attachment:`. Run the behavioural half with
`./m4_acceptance.sh <l4 binary> <venv python>` — today it reports **7 of 7 not
round-tripping** and prints each refusal verbatim — and the emission half with
`cabal test l4-cli-test --test-options='-m "M4: breadth"'`, today 15 red and 1
green (the green one is (G), the regression guard for the four refusals M4 does
not own). Two scope rulings the milestone had to make are recorded in the spec: the
payload-value match (§8.8) and the date surface (§8.12, R12)._

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
| `MAYBE NUMBER`/`MAYBE DATE`                   | **refused** today (empty number submits as `0`, not `None`); M4 pairs an is-known question with a `show if: {code:}`-guarded value — tests RED (R8) |
| `MAYBE <enum>`/`MAYBE <record>`               | **refused**, and still refused after M4 (`not-ok/maybe-enum.l4`) (R8) |
| `WHEN JUST <value>` (payload-value match)     | **refused** today; ruled IN at M4 under R8 — tests RED (spec §8.8)     |
| `LIST OF` (input)                             | **refused** today; M4 gathers it as a `DAList` — tests RED (§10)       |
| constructor payloads                          | **refused** today; M4 emits a `show if: {code:}` follow-up — tests RED |
| date literals, date arithmetic                | **refused** today; M4 routes literals through `as_datetime()` and uses the calendar-exact idiom — tests RED (R12, spec §8.12) |
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
  - `name-collision.l4` — `` `notice period` `` and `notice_period` sanitise
    to one Python identifier: `checkCollisions` rejection.
  - `higher-order.l4` — function-valued `WHERE` binding passed as an
    argument, not directly applied: un-inlinable, refused by name.
  - `seam-ref-via-fn.l4` — a seam-shaped export referenced by another
    decision *through an inlined function*: the R4 dangling-goal guard must
    see references that travel through inlined bodies.
  - `maybe-enum.l4` — `MAYBE <enum>` (M4). The paired is-known design does
    not reach it: an enum's value question is itself a radio, so its absent
    path is a fourth choice rather than an empty submission. It also guards
    the DIAGNOSTIC — M1's catch-all recites "v1: MAYBE BOOLEAN and MAYBE
    STRING only", which becomes a false claim in user-facing prose the moment
    NUMBER and DATE land, so the refusal must name the type it refuses.
  - _Retired at M4:_ `maybe-number.l4` and `just-payload-pattern.l4` are gone.
    Both were R8 refusals M4 flips, and both are now supported cases inside
    `maybe-scalars.l4`.
- `citations.l4` — the M2 example. Three sub-decisions, each carrying a
  statutory `@ref`, conjoined by `AND` so a FALSE first conjunct
  short-circuits the other two away. One ref uses the plain `@ref …` form, one
  the inline `<<…>>` form, and the third is deliberately Mako-hostile (it
  begins with `%` and contains a literal `${ … }`) — the same discipline
  `defaults.l4` applies to `@desc`, applied to `@ref`. Each rule's citation
  lands in its own `code:` block, so the verdict screen names exactly the
  rules that fired; the `DECLARE`d type and the three `MEANS` bindings become
  the `auto terms:` glossary. A **fourth** `@ref` sits on the exported
  `DECIDE` itself, and it is what makes the emitted **order** observable: the
  emitter puts `explain()` after the assignment in every `code:` block, and the
  goal's assignment is what pulls on the sub-rules, so the goal completes last
  and cites last. On the three sub-rules alone that placement is unobservable —
  moving every `explain()` above its assignment left the round-trip harness
  fully green until this citation existed.
- `roundtrip_check.py` — drives the emitted interview headlessly in real
  `docassemble.base` and asserts the verdict/goal equals the L4 `#EVAL`
  oracle (fixture table in the file; one case per #EVAL). For the `citations`
  example it additionally asserts the exact ordered citation list, the
  citations' presence in the **rendered** screen, and the parsed
  `auto terms:` glossary.
- **The M4 examples (RED).** Each pins one clause of spec §10, and each is a
  real rule with a real oracle, not a smoke test:
  - `tenant-list.l4` — `LIST OF Tenant` gathered as a `DAList`. The claim is
    not that a list can be gathered but that PRUNING SURVIVES GATHERING: a
    tenant aged 17 must never be asked whether they signed. Four `#EVAL`s
    including the empty household, which is vacuously eligible — a real
    drafting bug in the rule, pinned so the gather cannot paper over it.
  - `payload-enum.l4` — a licensing outcome with a `NUMBER` payload on one
    constructor and a `STRING` payload on another. The follow-up for the
    constructor that was not chosen must never be asked and must be left
    genuinely undefined, which only `show if: {code: …}` achieves.
  - `maybe-scalars.l4` — R8 in full: `MAYBE NUMBER`, `MAYBE DATE`,
    `MAYBE BOOLEAN` and `WHEN JUST FALSE`. Its `#EVAL`s are PAIRED: read 2
    against 3 (a declared income of zero against no declaration at all) and 6
    against 7 (a disclaimed declaration against an unanswered one). Any
    lowering that conflates absence with a default fails one of each pair.
  - `statutory-age.l4` — date literals and calendar-exact arithmetic. Case 1
    is where `date_difference(…).years` reports 17.99900 on the applicant's own
    eighteenth birthday; case 3 is the leap-day divergence, where
    `.plus(years=18)` clamps and L4's `Date` rolls forward. See spec §8.12.
  - `review-checklist.l4` — a short-circuiting filing rule where three of four
    inputs are never asked, and must still appear on the compliance checklist,
    marked as never asked.
  - `notice-letter.l4` + `notice-letter.letter.md` — the document-assembly
    demo. Three of its six inputs decide nothing and exist only for the
    letter, which is the point: an attachment EXTENDS the interview's question
    set. The hazard it defends against is not an exception but a successful
    empty render.
- `m4_acceptance.sh` — emits and drives every M4 example plus the `citations`
  inherited-debt case in one command, printing each refusal verbatim. Usage
  from the repo root: `jl4/examples/docassemble/m4_acceptance.sh <l4> <python>`.
  Exit status is the number of examples that did not round-trip.
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
- Regenerating over a tree this command wrote is fine. A directory holding
  anything else is refused — a package is a thing people edit. Regeneration
  **replaces** the generated content rather than adding to it: the
  `docassemble/` subtree and any root-level `*.fidelity.txt` are removed first,
  and everything else you put in the directory (a README, a LICENSE, a
  `tests/`) is left alone. It did not always: writing without deleting meant
  that regenerating after the `.l4` was **renamed** left the whole previous
  inner package behind, `[tool.setuptools.packages.find] where = ["."]` found
  both, and the built wheel shipped an importable second package the
  distribution does not own, with no data file behind its `l4_source_text()`.
  The slug follows the source basename by design, so a rename is the designed
  trigger, not an exotic one.
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

**1. `dainstall`** — the developer loop, from the separate **`docassemblecli`**
distribution (`pip install docassemblecli`; it is *not* part of the docassemble
monorepo, so nothing in the 1.10.7 checkout pins its behaviour). The name has no
hyphen and PEP 503 does not collapse the two — `docassemble-cli` normalises to
itself, and `https://pypi.org/simple/docassemble-cli/` is a 404 while
`.../docassemblecli/` is a 200, so the hyphenated spelling cannot install the
tool the next lines invoke. Point it at the generated directory:

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

**M4 additions to the fixture vocabulary (2026-08-17).** Five per-case keys and
two per-example keys, each existing because an M4 claim cannot be stated with
answer-comparison alone:

| key                 | scope   | what it asserts                                                                                                    |
| ------------------- | ------- | ------------------------------------------------------------------------------------------------------------------ |
| `undefined_after`   | case    | every listed spelling fails to evaluate at the end — a hidden or absent field is absent, not `''` and not `0`      |
| `never_asked`       | case    | no asked variable name matches; for where a sibling list element's fixture would otherwise satisfy the lookup      |
| `post_conditions`   | case    | an expression in the finished `user_dict` is non-empty and carries/omits given text — the empty-letter defence     |
| `change_answer`     | case    | re-drives after `undefine()` + re-ask, asserting `after`'s goal/verdict/citations — the M2 inherited defect (§8.4) |
| `review_unanswered` | case    | how many review rows carry a never-asked marker                                                                    |
| `gather`            | example | answers a `DAList`'s control questions for `gather_n` elements, in whichever of the three probed shapes was emitted |
| `review`            | example | the review block's expected row labels and the accepted "never asked" spellings                                    |

Fixture keys may now be INDEXED (`tenants[0].age`) and are resolved
longest-first, dropping one leading dotted component at a time — which is what
makes the per-element pruning claim testable, since element 1's answer can be
supplied without accidentally supplying element 0's. A `D("2024-06-01")`
fixture is written through `as_datetime()`, reproducing what the web layer
stores (`interview/views.py:1372`); a plain string would raise `TypeError`
against a `DADateTime` for a reason unrelated to the lowering.

**One harness DEFECT was repaired to make this possible.** `assemble` is now
wrapped in `user_dict_context(user_dict)`, which only `docassemble_webapp`
enters. Without it `get_current_user_dict()` is `None` and
`functions.py:4234` makes `defined()`, `value()` and `showifdef()` return
`False` for EVERY variable, including defined ones — which would have made any
review-block assertion silently vacuous. All seven M1/M2 examples were re-run
after the change and stayed green.

The package tree is one block larger in every case: that is the `modules:`
block, which is emitted into the packaged interview only. The `citations` run
in full:

```
  [glossary] 4 L4 defined terms present  OK
  [exempt (all three rules fire)] offering_exempt = True;
      citations ['17 CFR 227.100(a)(1) — offering maximum',
                 '17 CFR 227.100(a)(3) — sales through one intermediary only',
                 '% of the proceeds retained is set out at ${ fee_schedule } — 17 CFR 227.300(a)',
                 '17 CFR 227.100 — the crowdfunding exemption'];
      screen cites all four  OK
  [cap exceeded (rules 2 and 3 short-circuited away)] offering_exempt = False;
      citations ['17 CFR 227.100(a)(1) — offering maximum',
                 '17 CFR 227.100 — the crowdfunding exemption']; screen cites both  OK
```

Two things in that transcript are asserted rather than observed. The third
citation begins with `%` and carries a literal `${ … }`, and it arrives on the
**rendered** screen verbatim — only provable after Mako has run, which is why
the assertion lives in the harness and not in a YAML golden. And the citation
list is asserted as an **ordered** list: order is completion order, so the
goal's own `@ref` (the fourth) comes last, after the sub-rules its assignment
pulled on. Swap any `explain()` above its assignment and this run turns red.

## M2 acceptance tests — written RED first, now GREEN

_The M2 tests were written fail-first on 2026-08-17 (commit `178b4946`, 15
failing cases) and the implementation was written against them. They are the
contract M2 had to meet, and they now pass; what follows is what each block
pins, so a later change knows what it is breaking._

- `jl4/tests-cli/Main.hs`, `describe "l4 docassemble --package (M2/R11: …)"`
  — fourteen shape assertions over the written tree (PEP 420 shape including
  the namespace `__init__.py` that must be **absent**, `pyproject.toml`,
  `MANIFEST.in`, byte-identical `data/sources` provenance, the `modules:`
  wiring, no empty directories, determinism, the `--package`/`--output`
  refusal, and a hostile-filename slug — plus, from the review pass, the
  fidelity report's placement and bytes, the `MANIFEST.in` line that ships it,
  `l4runtime.py`'s provenance API, the `# do not pre-load` marker, and
  regeneration replacing a previous run rather than accumulating beside it).
- `jl4/tests-cli/Main.hs`, `describe "l4 docassemble citations (M2: …)"` —
  eight assertions over the emitted interview (per-rule `explain()` with that
  rule's own citation and **not** its neighbour's, the goal block carrying the
  exported `DECIDE`'s own `@ref`, `explain()` sitting **after** the assignment
  in every block, `logic_explanation()` on every verdict screen, one
  `auto terms:` block carrying the L4 defined terms, herald/delimiter
  stripping, Mako escaping, and the emitter's own key vocabulary split into
  block keys and field modifiers), plus the `expected/citations.yml` byte
  golden that the RED phase deferred to the implementation and the GREEN phase
  supplied.
- `jl4/tests-cli/Main.hs`, `describe "l4 docassemble (M2 repairs: …)"` — the
  two losses that used to be silent (`DA-GLOSS-REGEX`, `DA-GLOSS-COLLIDE`) and
  the one that used to change the answer (an L4 name landing on a name
  `modules:` star-imports).
- `jl4/tests-cli/Main.hs`, `describe "@desc attachment to WHERE/LET bindings"`
  — the parser repair M2 depends on, which no corpus golden can see: none of
  evaluation, exactprint, nlg or schema shows which node owns a `@desc`, so
  the oracles are the `auto terms:` glossary (which keys every entry by its
  owner) and `l4 ast` (for a nested binding the glossary cannot reach).
- `roundtrip_check.py`'s `citations` example — the claim that makes the
  milestone worth having: on the `cap exceeded` path the verdict screen cites
  `17 CFR 227.100(a)(1)` and the goal's own `@ref` **and nothing else**,
  because the other two rules were short-circuited away and decided nothing.

What stayed green throughout, deliberately: the six M1 `expected/*.yml`
goldens are **byte-identical** after M2, because the `auto terms:` block, the
`explain()` calls and the `logic_explanation()` screen section are each emitted
only when the module actually carries the annotation they come from — and none
of the six does. Same for the six `.fidelity.txt` sidecars, the `not-ok/`
refusals, and the six round-trip examples.

## What the review pass changed (2026-08-17)

Five adversarial lenses attacked the milestone and an independent skeptic tried
to refute each finding. What survived, and what was done about it:

**Answers that were wrong.** An L4 name that sanitises onto a name the generated
runtime module exports (`l4_source_path`, `l4_source_text`) was clobbered by
`modules:`' `import *` — truthy, so the **packaged** artifact asked no question
and returned the opposite verdict to the bare one, while the report said
"(nothing lost)". `__all__` bounds *which* names arrive; it does nothing to stop
an interview variable from being one of them. Those names are now reserved, in
both artifact shapes.

**Losses that were silent.** Two shapes of L4 defined term cannot become an
`auto terms:` key at all, and both now come back as fidelity notes rather than
as `(nothing lost)`: a term carrying a regex metacharacter (`DA-GLOSS-REGEX` —
docassemble interpolates the key straight into a regex with no `re.escape`, so
`s 12(1` made the whole interview unloadable while every L4 command reported
success), and a term that folds onto an earlier one under docassemble's
lower-case/whitespace-collapse key normalisation (`DA-GLOSS-COLLIDE` — what the
loser costs is its whole definition, not merely its spelling).

**Corrections to this file and the spec.** The `dainstall` distribution is
`docassemblecli`, not `docassemble-cli`. And the "known cosmetic consequence"
both documents used to describe — that a question's own label would auto-link to
its own definition — **cannot happen**: glossary keys come from `DECLARE`d types
and named definitions, questions are emitted for record fields and `GIVEN`
parameters, and `collectGlossary` excludes exactly those, so the two sets are
disjoint by construction. Measured with docassemble's own compiled regexes over
`expected/citations.yml`, no `q_*` block matches any glossary term. What does
happen is over-linking on the **verdict screen**: the term `offering` (from
`DECLARE Offering`) matches inside `offering exempt: Holds`, where the word is
part of the decision's name rather than a reference to the record type.

**Known, not fixed: the explanation list is session-scoped.** `explain()`
appends to `_internal['explanations']` and nothing in an emitted interview ever
clears it. On the forward drive every example is green, and that is the flow the
milestone claims. But docassemble's `invalidate_dependencies` deletes invalidated
*variables* and never touches the explanation history (`parse.py:8014-8060` at
`1b6678384`), so two flows go stale, both measured: `POST /api/session` with
`delete_variables` re-decides the goal correctly while the verdict screen keeps
citing rules that were short-circuited away, and two exported decisions driven in
one session share one list. Two flows that were suspected and **cleared**: the
plain back button rolls the whole `user_dict` back, explanation history included
(`fetch_previous_user_dict`), and the API's plain `set_session_variables` never
invalidates at all, because it writes the value before capturing `old_values`.
Adding `clear_explanations()` to the driver does not fix it and makes it worse:
the rule blocks are cached once their variable is defined, so the clear wipes
what they recorded and never lets them run again (measured; see spec §8.4). The
repair is a design change, not a patch, and it belongs with M4's `review:`
block, which is the surface that makes re-answering ordinary.

**Correction, 2026-08-17 (M4 RED phase): it is worse than the paragraph above
says, on the path a review Edit takes.** Re-measured with the answer changed by
`undefine()` + re-ask rather than through the API, against the shape the backend
actually emits: the **verdict itself goes stale**, not merely the citations —
with the cap answer corrected from 9,000,000 to 1,000 the goal stays `False` and
the citations stay unchanged. `depends on:` did not rescue it. Nor does any
single flag: `reconsider: True` alone fixes the verdict but makes the citations
*accumulate contradictory rules* ("maximum EXCEEDED" and "maximum satisfied"
together), which is actively worse than nothing, and `initial: True` +
`clear_explanations()` alone empties the list. What works is making the
explaining atomic in one block — either moving every `explain()` into the
mandatory driver behind a `clear_explanations()`, or dropping `explain()` and
deriving `cite_*` variables. Both were verified; M4 owns choosing one. The
fourth case of the `citations` example in `roundtrip_check.py` asserts the
repaired behaviour as a claim and is RED.

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
| citations | exempt | raised 1 000 000, one intermediary T, registered T | TRUE | `offering_exempt` = True; screen cites all three sub-rules then the goal's own `@ref`, in that order |
| citations | cap exceeded | raised 9 000 000 (only fixture supplied) | FALSE | = False, no rule-2/3 question asked; screen cites `17 CFR 227.100(a)(1)` then the goal's `@ref`, and nothing else |

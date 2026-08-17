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
refutation, and corrected what it found to be false (see "What the M2 review
pass changed"). The seven `expected/` goldens are committed and
pinned by the `l4 docassemble` cases in `jl4/tests-cli/Main.hs` (39 cases across
the four M2-era `describe` blocks — 41 when M2 landed; M4's RED phase retired
two of them, `refuses MAYBE NUMBER by name` and ``refuses `WHEN JUST TRUE` ``,
because M4 makes both constructs work), and every example below was run green
against
`docassemble.base` 1.10.7 (local checkout, commit `1b6678384`) from **both**
artifact shapes — see "Prove it runs in real docassemble"._

_**M4 landed 2026-08-17** on branch `mengwong/docassemble-m4`, test-first: the
acceptance tests were written red first (commit `ec9850f6`, 15 failing CLI
cases and 7 of 7 examples not round-tripping) and the implementation made them
pass. Six new examples are in this directory — `tenant-list`, `payload-enum`,
`maybe-scalars`, `statutory-age`, `review-checklist`, `notice-letter` — each
with a committed `expected/` golden, and each driven in real docassemble.
`./m4_acceptance.sh <l4 binary> <venv python>` now reports **0 of 7 not
round-tripping**, driving every example from BOTH artifact shapes; the emission
half is `cabal test l4-cli-test --test-options='-m "docassemble"'`, 64 cases
across five `describe` blocks (39 M2-era + 25 M4).
What shipped: `LIST OF <record>` gathered as a `DAList`, constructor payloads as
`show if` follow-ups, `MAYBE NUMBER`/`MAYBE DATE` as paired is-known questions,
the R12 date surface, a `review:` compliance checklist on EVERY interview, and
the document-assembly demo. It also repairs the inherited §8.4 defect — after a
changed answer the verdict used to go stale, not merely its citations. Two scope
rulings the milestone had to make are recorded in the spec with the notes that
discharge them: the payload-value match (§8.8) and the date surface (§8.12, R12).
**M3 (the embedded query plan) was measured on 2026-08-18 and DECLINED — not deferred.**
Info-gain plan ordering asks 3.38% fewer questions than declaration order over the 138
corpus decisions that have an ordering at all (0.059 of one question each), and a
compile-time operand sort captures 100% of that, beating the adaptive planner on 0 of
138. Most L4 legal decisions are flat AND/OR chains where every atom is equally
informative. The harness is committed at `jl4/measure/`; the ruling, its limits and what
would reopen it are in spec §8.5. Question order here is, and stays, L4 source order._

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
| `MAYBE NUMBER`/`MAYBE DATE`                   | TWO questions: `<var>_known`, then the value guarded by `show if: {code: <var>_known}` — an empty number submits as `0`, so absence needs a carrier a blank widget cannot forge (R8, M4) |
| `MAYBE <enum>`/`MAYBE <record>`               | **refused**, naming the enum or record (`not-ok/maybe-enum.l4`) (R8) |
| `WHEN JUST <value>` (payload-value match)     | `(<var> is False)` — identity, not a presence test (R8, M4; spec §8.8) |
| `LIST OF <record>` (input)                    | `DAList(object_type=DAObject)` + two gather questions + one question per element attribute; `all`/`any` → a Python generator, so pruning survives per element (M4, §8.6) |
| `all`/`any` predicate                         | a lambda written out at the call site, or the NAME of a one-parameter decision — both inlined into the generator (M4) |
| constructor payloads (scalar)                 | one follow-up question per payload field, gated `show if: {code: <enum> == '<ctor>'}` (R6, M4) |
| date literals, `n` years later                | `as_datetime('YYYY-MM-DD')`; the anniversary shifts from the first of the month, agreeing with L4's rolling `Date` on leap days — never `date_difference().years` (R12, §8.12) |
| deontic / temporal / ledger constructs        | **refused**, `L4.Interchange.Fidelity` notes (spec §5)                 |
| `@desc` on a field or parameter               | question text / field `help:`, Mako-escaped (R9)                       |
| `@desc` on a `DECLARE` or a named definition  | one `auto terms:` glossary entry, keyed on the L4 term (M2)            |
| `@ref` on a `DECIDE` or `WHERE` binding       | `explain()` in that rule's own `code:` block (M2)                      |
| `@ref` on an expression                       | **nothing** — no `code:` block to hang it on; `DA-REF-EXPR` advisory   |
| the rules that actually fired                 | `logic_explanation()` on every verdict screen (M2)                     |
| `#EVAL`                                       | round-trip oracle input (R10); **not emitted** into the interview      |
| every emitted question EXCEPT a gathered list element | one `note:` row in a `review:` compliance checklist, marked `**not asked**` when the law never reached it (M4, §10). A `<list>[i].<attr>` question gets no row — its variable carries docassemble's iterator and there is no element to name until the list is gathered — declared as `DA-REVIEW-LIST`, and visible in `expected/tenant-list.yml`, whose five questions produce two rows |
| a sibling `<stem>.letter.md`                  | an `attachment:` with `variable name:`, assembled on the verdict screen (M4, §10) |

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
- **The M4 examples.** Each pins one clause of spec §10, and each is a
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
    `.plus(years=18)` clamps and L4's `Date` rolls forward. The emitted
    anniversary shifts from the first of the month — `.minus(days=day-1)`,
    `.plus(years=n)`, `.plus(days=day-1)` — which agrees with L4 on both. See
    spec §8.12.
  - `review-checklist.l4` — a short-circuiting filing rule where three of four
    inputs are never asked, and must still appear on the compliance checklist,
    marked as never asked.
  - `notice-letter.l4` + `notice-letter.letter.md` — the document-assembly
    demo. Three of its six inputs decide nothing and exist only for the
    letter, which is the point: an attachment EXTENDS the interview's question
    set. The hazard it defends against is not an exception but a successful
    empty render.
- A test outside this directory, worth knowing about: `l4 docassemble` on
  `jl4/examples/legal/charities-cleanroom/charity-test.l4` — 700 lines of the
  Jersey charities encoding, not written for this backend — now emits, because
  its `Entity.purposes` is a `LIST OF Purpose` and ONE such field anywhere in a
  reachable record used to refuse the whole module. It is also the only place
  the eta-reduced predicate and the nested-quantifier variable are exercised.
  (`regcf-denovo.l4` still does not emit, and its blocker is not lists: it is
  `RULES EFFECTIVE DATE`, the temporal axis.)
- `m4_acceptance.sh` — emits and drives every M4 example plus the `citations`
  inherited-debt case in one command, from BOTH artifact shapes (bare YAML and
  a real `--package` tree), printing any refusal verbatim. Usage from the repo
  root: `jl4/examples/docassemble/m4_acceptance.sh <l4> <python>`. Exit status
  is the number of examples that did not round-trip; it is 0.
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
            computed-and-shadow assume-via-fn citations \
            tenant-list payload-enum maybe-scalars statutory-age \
            review-checklist notice-letter; do
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
# == round-trip: seam == (13 blocks, debug=True)
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
7. **`user_dict_context(user_dict)` around every `assemble`** — only
   `docassemble_webapp` enters it, and without it `get_current_user_dict()` is
   `None`, so `_inspect_user_dict` takes its failure path
   (`functions.py:4232-4237` at `1b6678384`) for EVERY variable, defined ones
   included. The three callers fail differently, which matters when debugging:
   `defined()` returns `False` (it is the only `is_predicate()` caller),
   `showifdef()` returns its `alternative` — `''` by default, so a review row
   renders blank rather than "not asked" — and `value()` is not `is_pure()`, so
   it falls through to `force_ask_nameerror` and RAISES `DANameError`. All three
   executed. Added at M4, for the review block.
8. **a review block is reached by firing its `event:`** through
   `current_info['action']`; without one the interview simply ends. That is not
   in tension with item 5 — the key must be absent by default, and present
   exactly when an event block is what you are trying to reach. docassemble
   POPS it during `process_action`, so the harness hands it a copy.

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

Run that way over all seven examples, **re-run after M4**, against the 1.10.7
checkout (abridged to one line per source; every case inside each run printed
`OK`). The counts are one higher than the M2 transcript this replaces, in every
row, because every interview now carries a `review:` checklist — and `citations`
is two higher, the second being its citation-reset block:

```
== round-trip: rodents-and-vermin ==  [yaml] (20 blocks)  [package] (21 blocks)  AGREEMENT OK  ROUND-TRIP OK
== round-trip: seam ==                [yaml] (13 blocks)  [package] (14 blocks)  AGREEMENT OK  ROUND-TRIP OK
== round-trip: enum-triage ==         [yaml]  (6 blocks)  [package]  (7 blocks)  AGREEMENT OK  ROUND-TRIP OK
== round-trip: defaults ==            [yaml] (11 blocks)  [package] (12 blocks)  AGREEMENT OK  ROUND-TRIP OK
== round-trip: computed-and-shadow == [yaml]  (8 blocks)  [package]  (9 blocks)  AGREEMENT OK  ROUND-TRIP OK
== round-trip: assume-via-fn ==       [yaml]  (7 blocks)  [package]  (8 blocks)  AGREEMENT OK  ROUND-TRIP OK
== round-trip: citations ==           [yaml] (13 blocks)  [package] (14 blocks)  AGREEMENT OK  ROUND-TRIP OK
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
supplied without accidentally supplying element 0's. That works only because
the harness resolves the ITERATOR first: a question over a list element is
written across docassemble's `[i]`, and that is the spelling `field.saveas`
carries for every element, with the concrete index living in the `user_dict` as
`i`. The harness calls docassemble's own `substitute_vars_from_user_dict`
(`parse.py:9921-9927`, the function docassemble uses to name an attachment
variable inside a generic block) rather than re-deriving the substitution, so it
reports the variable docassemble would report. A `D("2024-06-01")`
fixture is written through `as_datetime()`, reproducing what the web layer
stores (`interview/views.py:1372`); a plain string would raise `TypeError`
against a `DADateTime` for a reason unrelated to the lowering.

**Two harness DEFECTS were repaired to make this possible.** First: `assemble` is now
wrapped in `user_dict_context(user_dict)`, which only `docassemble_webapp`
enters. Without it `get_current_user_dict()` is `None`, so
`_inspect_user_dict` takes its failure path (`functions.py:4232-4237` at
`1b6678384`) for EVERY variable, defined ones included — `showifdef()` returns
its `alternative`, `''` by default, which would have made any review-block
assertion silently vacuous. All seven M1/M2 examples were re-run after the
change and stayed green. _(This paragraph and spec §8.10 item 1 both used to say
all three of `defined()`, `value()` and `showifdef()` "return False". Corrected
2026-08-17, executed: only `defined()` does — it is the sole `is_predicate()`
caller; `showifdef()` returns the alternative, and `value()` is not `is_pure()`
so it reaches `force_ask_nameerror` and RAISES `DANameError`. The repair was
right; the stated mechanism was not, and a reader debugging on it would hunt for
a silent `False` where an exception is thrown.)_

Second: the `change_answer` case's VERDICT assertion was unguarded, while the
forward assertion twenty lines above it skips when no verdict variable exists.
Only a seam-lowered export emits one (R4), and `citations.l4`'s goal is a plain
boolean — so the unguarded check demanded a variable the design deliberately
does not produce, and reported its absence as the §8.4 staleness defect it was
written to catch. Guarded now, exactly as the forward one is.

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
refusals, and the six round-trip examples. (**M4 changed that**, consciously and
for two named reasons — see the next section.)

## M4 acceptance tests — written RED first, now GREEN

_Same discipline again: the tests landed first (commit `ec9850f6`, 15 failing
CLI cases and 7 of 7 examples not round-tripping) and the implementation was
written against them._

- `jl4/tests-cli/Main.hs`, `describe "l4 docassemble (M4: breadth — acceptance)"`
  — twenty-five assertions, one or two per §10 clause: the `DAList` and its
  `object_type`, a gather-control question, a per-element question and a goal
  that QUANTIFIES; the per-element predicate keeping its short-circuit and the
  lowering never reaching for `complete_elements()`; every `show if:` carrying
  a `code:` sub-key and never `is:`, and never at block level; the constructor
  radio staying in its own, earlier question; two questions per `MAYBE
  NUMBER`/`DATE` with the value guarded and the PLAIN `DATE` in the same record
  left unguarded; the goal consulting the is-known flag rather than the value;
  `WHEN JUST FALSE` compiling to a value comparison; `MAYBE <enum>` still
  refusing AND naming the enum; every date literal on a line that also carries
  `as_datetime(`; `date_difference` and `365.2425` appearing nowhere; one
  `review:` block with an `event:`, a row per input, `note:` + `showifdef()`
  and no `skip undefined: False`; an `attachment:` with `variable name:`, no
  `pdf`, and a verdict screen that references it; the attachment sub-key
  vocabulary; a `data/templates` entry in the `--package` tree; six byte
  goldens; the real corpus file (`charity-test.l4`) that motivated `LIST OF`;
  and (G), the regression guard for the four refusals M4 does **not** own. Five
  more were added by the 2026-08-17 repair pass, under (I) — the block-scalar
  indentation indicator, `reconsider:` on the attachment, `undefine:` on a
  gating question, the declared `DA-UNDEFINE-LIST` narrowing inside a gather,
  the builtin/`util` namespace reservation, and M4's own two new refusals.
- `m4_acceptance.sh` — the behavioural half, all seven examples from both
  artifact shapes. Its claims are the ones that cannot be read off the YAML:
  per-element pruning inside a gather, an unchosen payload left UNDEFINED
  rather than `0`, a real zero distinguished from an absent number, the two
  date cases where the convenient Python idiom is wrong, three never-asked rows
  on the checklist, a letter that is non-empty and branch-correct, and the
  §8.4 changed-answer case.

**Two things M4 changed on purpose, and what they cost.** Both rewrote the
seven M1/M2 goldens, which were re-read before being re-blessed:

1. every interview now carries a `review:` checklist (nothing in an L4 source
   asks for one, and the alternatives — a CLI flag, or new grammar — would make
   the artifact depend on how the compiler was invoked, or add L4 syntax for a
   view); and
2. every derived `code:` block now carries `reconsider: True`, and a citing
   module gains a citation-reset block plus one line in its driver. That is the
   §8.4 repair: without it, changing an earlier answer left the VERDICT stale,
   not merely its citations.

## What the M4 repair pass changed (2026-08-17)

Five adversarial lenses attacked the landed M4 milestone and an independent
skeptic tried to refute each finding. Five survivors changed behaviour:

**A letter template that opened on leading whitespace emitted YAML nothing could
load.** The template is spliced into a `content: |` block scalar, and a block
scalar with no indentation indicator takes its indentation from its own first
non-empty line — so one leading space set the block indent above the emitter's
flat four, and the next line at four terminated the scalar. `parse.Interview`
then raises `DASourceError`: not one question survives, in **both** artifact
shapes, while `l4 docassemble` exits 0. Now `content: |2`, and
`notice-letter.letter.md` opens on an indented address block so the corpus
carries the trigger.

**The assembled letter went stale after a changed answer.** §8.4's repair put
`reconsider: True` on derived *code* blocks; an attachment is derived too, and
docassemble assembles one only when its variable is sought — which never happens
to a variable that is already defined. Measured: the verdict screen read
`..._screen_fails` above a letter still saying "3 month(s)" and "the notice is
valid". No screen assertion could see it, because `${ notice_letter }` renders
headless to the literal `None`; the harness now re-checks the assembled CONTENT
after the edit.

**A gated ANSWER outlived its gate.** `show if:` decides whether a question is
asked, not whether an answer survives its gate being withdrawn. After an Edit
changed the outcome from `granted subject to conditions` to `refused`, the
compliance checklist reported "the outcome: refused" beside "the number of
conditions: 9", and `refused` carries no such field in L4. The verdict was right
throughout — the discriminator is read first and Python short-circuits — so only
the checklist lied, and only until the letter above started re-rendering. The
gating question now carries `undefine:`.

**`WHEN JUST ""` on a `MAYBE STRING` compiled to the absence test** — the one
thing §8.8's ruling says a payload-value match must not do, because a `MAYBE
STRING`'s NOTHING encoding *is* the empty string. Now refused by name
(`not-ok/maybe-empty-string.l4`); every non-empty literal is unaffected.

**An L4 name landing on a Python builtin or a `docassemble.base.util` export was
never sought.** Same failure as the `l4runtime` collision M2 fixed, on the two
larger populations M2 left open: the name already resolves, to a truthy function
object, so the driver takes the "holds" branch with **zero questions asked** and
the report says "(nothing lost)". Measured on `All`, `Today`, `Value`,
`Message`, `Word`, `Currency`. 282 names are now reserved. Inherited, not
introduced by M4.

One diagnostic improved: a constructor payload colliding with a record field (or
with another constructor's payload of the same name) was reported as an
`internal id collision` naming a block id, because both blocks carry the same
(role, L4 name) pair — it is one L4 name used twice, not two names sanitising
together. It now reports as a name collision and says why the hoist collides.

The documentary findings — three RED-phase labels left in the present tense,
four wrong test counts, a wrong `functions.py` mechanism repeated in three
files, an over-general mapping-table row, and two retracted claims that outlived
their retraction — were corrected at source.

## What the M2 review pass changed (2026-08-17)

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
`clear_explanations()` alone empties the list.

**REPAIRED at M4 (2026-08-17), by a design neither of those.** `reconsider:
True` on every derived block makes the verdict fresh — those variables are
deleted once per assemble pass, at the top of `Interview.assemble` — and a
citation-reset SENTINEL keeps the citations honest: a block that calls
`clear_explanations()`, itself reconsidered, which the mandatory driver
REFERENCES BEFORE THE GOAL. Reference-before-goal is the mechanism: docassemble
seeks the sentinel, empties the list, and only then reaches the goal that pulls
the rules that explain into it. A clear written at the top of the driver instead
runs again on the driver's second iteration — after the rules have explained —
and wipes them, which is exactly the "empty citations" the earlier probes saw.
`explain()` stays in each rule's own block, after its assignment, so a per-rule
`@ref` still names the rule that decided. The fourth case of the `citations`
example in `roundtrip_check.py` asserts the repaired behaviour and passes:
after correcting 9,000,000 to 1,000 the goal is `True` and the citations are
exactly the four rules that now fire, in order.

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
| tenant-list | two adults | 2 tenants, ages 30/25, both signed, neither evicted | TRUE | `the_household_is_eligible` = True |
| tenant-list | minor first | tenant 0 aged 17 (only fixture supplied) | FALSE | = False; tenant 0's signature and everything about tenant 1 never asked |
| tenant-list | second evicted | ages 30/25, both signed, tenant 1 evicted | FALSE | = False |
| tenant-list | empty household | no tenants at all | TRUE | = True (vacuously — a real drafting bug, pinned) |
| payload-enum | granted | outcome `granted` | FALSE | `an_appeal_lies` = False; BOTH payload variables undefined afterwards |
| payload-enum | 2 conditions | outcome `granted subject to conditions`, n = 2 | FALSE | = False; the STRING payload undefined |
| payload-enum | 9 conditions | same, n = 9 | TRUE | = True; the STRING payload undefined |
| payload-enum | refused, non-payment | outcome `refused`, ground `"non-payment of the fee"` | FALSE | = False; the NUMBER payload undefined, not `0` |
| payload-enum | refused, merits | outcome `refused`, ground `"the premises are unsuitable"` | TRUE | = True; the NUMBER payload undefined |
| maybe-scalars | 1. income 2 500 | declared income known, 2 500 | TRUE | `the_claim_must_be_referred` = True |
| maybe-scalars | 2. a real ZERO | declared income known, 0 | FALSE | = False (read against case 3) |
| maybe-scalars | 3. no declaration | income not known (no value fixture) | TRUE | = True; the value variable undefined afterwards |
| maybe-scalars | 4. stale history | last worked 2019-03-04, qualifying 2024-01-01 | TRUE | = True |
| maybe-scalars | 5. never worked | date not known (no value fixture) | FALSE | = False; the date variable undefined |
| maybe-scalars | 6. disclaimed | declaration confirmed `False` | TRUE | = True (`WHEN JUST FALSE`) |
| maybe-scalars | 7. unanswered | declaration confirmed `None` | FALSE | = False (read against case 6) |
| statutory-age | 1. on the birthday | born 2001-03-01, assessed 2019-03-01 | TRUE | `the_applicant_may_hold_a_licence` = True (`date_difference` says 17.99900) |
| statutory-age | 2. the day before | born 2001-03-01, assessed 2019-02-28 | FALSE | = False |
| statutory-age | 3. leap day | born 2004-02-29, assessed 2022-02-28 | FALSE | = False (`.plus(years=18)` alone would say True) |
| statutory-age | 4. leap day + 1 | born 2004-02-29, assessed 2022-03-01 | TRUE | = True |
| statutory-age | 5. month end | born 2001-01-31, assessed 2019-01-31 | TRUE | = True |
| statutory-age | 6. before commencement | born 1990-01-01, assessed 2014-01-01 | FALSE | = False (the literal's own test) |
| review-checklist | in order | filed T, on time T, fee paid T | TRUE | `the_filing_obligation_is_discharged` = True; 4 checklist rows, 1 never asked |
| review-checklist | fee waived | filed T, on time T, fee F, waiver T | TRUE | = True; 4 rows, 0 never asked |
| review-checklist | nothing filed | filed F (only fixture supplied) | FALSE | = False; 4 rows, **3 never asked** |
| notice-letter | valid notice | residential T, written T, 3 months | TRUE | `the_notice_to_quit_is_valid` = True; `notice_letter.html.content` non-empty, carries the tenant, the address and "the notice is valid" |
| notice-letter | short notice | residential T, written T, 1 month | FALSE | = False; the letter is still assembled, and says "does not take effect" |
| citations | changed answer | 9 000 000, then corrected to 1 000 | TRUE | after the edit: goal `True`, and exactly the four rules that now fire, in order (§8.4) |
| notice-letter | changed answer | 3 months / "A. Tenant", then 1 month / "B. Occupier" | FALSE | after the edit: goal `False`, and the LETTER says "1 month(s)", "B. Occupier" and "does not take effect" — carrying none of the three strings it carried before (§8.4, repair pass) |
| payload-enum | changed answer | `granted subject to conditions` n=9, then `refused` | TRUE | after the edit: the checklist marks `the number of conditions` **not asked** and no longer reports `9` — the payload does not outlive its constructor (§8.4, repair pass) |
| maybe-scalars | 8. changed answer | income known 2 500, then not known | TRUE | after the edit: the checklist no longer reports `declared income: 2500` beside an is-known flag of `False` (§8.4, repair pass) |

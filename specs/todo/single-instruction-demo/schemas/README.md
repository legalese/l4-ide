# `schemas/` — the machine-readable formats the de novo (G2) path uses

**Status (2026-08-02): the formats are defined and validated; no pipeline stage writes one yet.**
P1, P2 and P4 remain scaffolded (`etc/go/phases/p{1,2,4}-*.sh` still exit 3) — what changed is
that "no machine-readable format exists" is no longer among their blockers. Each stage's
_remaining_ blocker is stated in its own refusal text and in
[`ORCHESTRATOR.md`](../ORCHESTRATOR.md) §5.2.

| file                                 | stage | SPEC.md §4 deliverable                                                  |
| ------------------------------------ | ----- | ----------------------------------------------------------------------- |
| `source-bundle.schema.json`          | P1    | "a source bundle with provenance"                                       |
| `external-modifications.schema.json` | P2    | "an external-modification register"                                     |
| `fork-register.schema.json`          | P4    | "a fork register naming the ambiguous source text each fork interprets" |

They cross-reference each other: a fork cites the modification that settled it, a modification
routes to the fork it opens, and both hang off the bundle's documents. One validator checks all
three, and the cross-file rules run whenever the peer file is given — and are reported `skip`,
never silently passed, when it is not.

```
node etc/go/lib/register-validate.mjs <schema> <file> [peer-file ...]
node etc/go/lib/register-validate.mjs --rules <schema>
```

Exit `0` clean · `1` a finding · `2` usage, unreadable file, or a schema the validator cannot
fully enforce.

## Three conventions that run through all four schemas

**1. `additionalProperties: false` everywhere.** An unknown key is an error, matching
`etc/go/lib/subject.mjs`. A register that silently ignores a misspelled key is a register that
silently loses a fork.

**2. Every absence carries a reason.** Where a field cannot honestly be required — a quote from
text that was never fetched verbatim, a digest of bytes an archive holds rather than us, a date
range nobody determined — the schema pairs it with an `*_absent_reason` and a rule enforcing
_exactly one of_ the two. Nothing is optional-by-silence.

**3. The validator enforces the whole schema or refuses to run.** The schemas are JSON Schema
2020-12 restricted to a closed keyword subset; `register-validate.mjs` audits each schema before
using it and exits 2 naming any keyword it does not implement. Cross-field rules JSON Schema
cannot express cheaply are declared under `x-rules` with an id and a description, and the
validator asserts a two-way match between the declared ids and its implementations — so a rule
can be neither declared-but-unenforced nor enforced-but-undocumented.

## Where the shapes came from

The schemas are calibrated against the BNA smoke test's emergent register (PR #195,
`jl4/examples/legal/bna/README.md` and `SMOKE-REPORT.md`), which is the only fork inventory
anyone has actually produced. `fixtures/fork-register.valid.json` transcribes its twelve rows;
the refinements those rows forced are recorded in each schema's `description`.

## Fixtures

`fixtures/` holds a valid and an invalid instance per register schema, plus
`regcf-identity.surface-map.json` for the fourth (below). **The valid instances are fixtures,
not committed registers** — each says so in its own `note`. The three valid ones form one coherent
BNA-derived trio so the cross-file rules have something real to run over; the invalid ones are
minimal, each tripping a named set of rules that `etc/go/selftest.mjs` asserts by name.

## A fourth file, which is not a deposit contract

| file                      | stage | SPEC.md deliverable                                    |
| ------------------------- | ----- | ------------------------------------------------------ |
| `surface-map.schema.json` | §8    | the pairing between two encodings, for the diff oracle |

A deposit contract describes something a stage _writes_ during a run. A surface map is an
**input**: the declared correspondence between the de novo encoding and the committed corpus, which
a G2 run deposits alongside its encoding and which `etc/go/lib/denovo-diff.mjs` consumes. It shares
the three conventions above, and its `pairs[].fork` cross-links a `fork-register` entry id.

It is validated by `denovo-diff.mjs`'s own validator rather than by `register-validate.mjs`,
because it needs three keywords outside that validator's closed subset — `oneOf`, `minProperties`,
and schema-valued `additionalProperties` (its `slots` object is a map, which the closed subset
cannot express). Both validators enforce the same contract as convention 3 above: a keyword they do not
implement is a hard error, not a silent pass. Converging them is open work.
`fixtures/regcf-identity.surface-map.json` is its fixture — the corpus paired against itself, which
is what the diff oracle's identity self-test runs.

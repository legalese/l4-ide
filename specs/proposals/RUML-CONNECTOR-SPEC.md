# RUML connector: writing L4 as RUML 1.0.0, and reading it back

_Status: **proposed, not landed.**
Written 2026-11-26 on branch `spec/ruml-connector-1126`, from `origin/unstable` at `8f10892e5`; it reached `unstable` as commit `0b8ddc86f`.
Amended 2026-11-28 on branch `spec/ruml-real-producer`, from `origin/unstable` at `61bd5ba62`: §2.8, R13, §5.5 and M7 are new, and §0, the evidence-marks paragraph, §1, §2.5, §4.8, §5.1, §9, §10 (M3 corrected), §11, §12 and Sources each changed from it.
Nothing described here is built: `git grep -il ruml` over the `.hs`, `.cabal`, `.mjs`, `.ts`, `.json`, `.yml`, `.sh` and `.l4` files of the 2026-11-26 tree found nothing **[E 2026-11-26]**, and the same command at `61bd5ba62` finds nothing **[E 2026-11-28]**.
What would make a sentence here true is named where it is written: a Phase 1 PR for the exporter and a Phase 2 PR for the importer (§9), and Meng's rulings on the list in §10._

**Evidence marks.**
**[E]** = read at source, or measured, on 2026-11-26, with the thing and where; the facts of §2.8 and §5.5 were measured on 2026-11-28 and say so.
**[U]** = inferred, not checked.
**[D]** = decided by Claude 2026-11-26 (R13 and §5.5: 2026-11-28), pending Meng's review.
RUML sources are pinned: the specification, schemas and tests are read at `Law-as-Code-Institute/ruml` commit `957ad4b730a91ba770fdad00de37269523f81452`, the commit the tag `v1.0.0` points at.
The branch head `d2ac818f6ed87c2bcf5b69430adf2efa8ba3c6a4` (2026-11-16) differs from the tag in three files only: `README.md`, `.github/workflows/release.yml` and `packages/npm/package.json` **[E, `git diff --stat`]**.
Section numbers such as "RUML 3.6.3" are the specification's own, and paths such as `spec/en/03-data-model/3-6-operators.md` are in that repository.

**Related.**
`BACKEND-PORTFOLIO-SPEC.md` (§4 invariants I1 to I10, §2.2 interchange census, §6 ruling cross-index), `specs/todo/CLI-SURFACE-SPEC.md` (C1, C3), `specs/research/RULEMAPPING-RUML-RESEARCH.md` (the 2026-09-09 memo, written before RUML was published), `specs/todo/UNKNOWN-EVALUATION-SPEC.md` (L4's three-valued semantics), `doc/exports/dmn-bpmn.md` and `doc/exports/yscript.md` (how two shipped exporters state their limits), `doc/concepts/language-design/logic-not-flowcharts.md` §"The strongest version of the tree".
The research memo, the census row in `BACKEND-PORTFOLIO-SPEC.md` and the flowcharts page are being corrected for the publication of RUML on another branch; this document cites them and edits none of them.

---

## 0. Rulings and decisions

Every row is **decided by Claude 2026-11-26, pending Meng's review**, except R13, which is **decided by Claude 2026-11-28, pending Meng's review**.
Each is argued in the section named, with its case against.
Every other design choice in §4 and §5 that is not a quoted fact or a measurement is likewise decided by Claude, pending Meng's review (2026-11-26, and 2026-11-28 for §5.5), whether or not it has a number.
The decisions that only Meng can make are a separate list, §10.

| ruling | decided                                                                                                                                             | argued in |
| ------ | --------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| R1     | Build the exporter first, natively in Haskell; the importer is a later phase for a stated subset (§6, §9)                                           | §6        |
| R2     | Third-party RUML parsers are test-time cross-checks only, never on the product path                                                                 | §6        |
| R3     | Out-of-fragment constructs are refused by name, the whole module at once; losses inside the fragment go in a fidelity report                        | §4.2      |
| R4     | Connectives live in nodes, never in expressions: one atomic condition per leaf, no JSONata `and` or `or` is ever emitted                            | §4.3      |
| R5     | A Boolean input is a leaf of its bare identifier; `=`, `<>` and membership leaves are guarded with `$exists`; negation is structural                | §4.3      |
| R6     | Only `+`, `-` and `*` and the six comparisons are emitted for numbers; division is refused; dates are compared and never computed                   | §4.3      |
| R7     | A definition used from two or more places becomes one modular node; recursion is refused                                                            | §4.4      |
| R8     | Identifiers: `dp_` plus a folded slug for data points; node UUIDs derived deterministically from a hash, shaped as version 4                        | §4.5      |
| R9     | The exporter declares `ruml:datapoints` and `ruml:query` with `required: true`, and writes `status: "draft"`                                        | §4.6      |
| R10    | The round-trip claim is G1 to G4 of §4.8 and no more                                                                                                | §4.8      |
| R11    | The conformance suite is fetched at test time, pinned by commit and by the git tree ids of `tests/` and `schemas/`, and never vendored              | §7        |
| R12    | The format is named `ruml`: `l4 export ruml FILE` and `l4 import ruml FILE` (CLI-SURFACE-SPEC C1 and C3)                                            | §3        |
| R13    | The importer rejects a leaf with an operator outside a draft (`NODE-07`); an opt-in lenient reading is designed and not built until a file needs it | §5.5      |

## 1. Summary

RUML 1.0.0, published 2026-11-15, is a JSON format for a legal decision tree: AND, OR and XOR nodes, each optionally negated, over leaves decided by JSONata expressions on typed data points, with sharing inside a file and inclusion across files **[E]**.
It has a public specification, three JSON Schemas, a conformance suite of data files, and two Apache-2.0 parsers that validate and do not evaluate **[E, §2]**.
L4's Boolean fragment maps onto it directly.
On a worked example, an L4 decision exported to RUML and evaluated under both of RUML's evaluation modes agreed with `l4 run` on all 24 input vectors tried **[E, §4.7]**.

The hazards are in the leaves and not in the tree, and §2.4 measures them with JSONata 2.2.0.
JSONata's `and` and `or` are two-valued, so a missing fact reads as false.
`dp_x = 5` and `dp_x = true` give false, not `undefined`, when `dp_x` is missing, and twelve of the forty-nine expressions in RUML's example files are `= true` comparisons.
Its numbers are IEEE doubles, so `0.07 * 100 = 7` is false.
RUML's `XOR` is a disjunction and not an exclusive or, and its two evaluation modes can give one file two different statuses.

One producer of RUML files could be run, on 2026-11-28: Rulemapping's own Rulemap Builder (§2.8).
It reads RUML and writes it, and our worked example of §4.7 went through it and came back with no member lost, though the tool put its own `metadata.id` where ours was.
Its export of a German statute, taken from a copy of the published rulemap in our own workspace (88 nodes, 161,351 bytes, 82 % of it the embedded text in its Akoma Ntoso JSON form), fails the format's own rule `NODE-07` on 13 nodes, because childless nodes carry an operator in a file whose `status` is `inForce`, and the suite's own test `operator--rejects-operator-on-leaf` expects exactly that to be rejected.
That statute file carries no query and no data point: it is an outline of the statute's structure, and says nothing about its logic.

**Recommendation (§9).**
Write the exporter natively in Haskell for the Boolean-and-comparison fragment, with an `l4 export ruml` command in the shape of the other exporters (R1).
Use the public parsers and JSONata itself only in a test harness that runs when they are present (R2).
Fetch RUML's Apache-2.0 fixtures at test time, pinned by commit, and do not vendor them (R11).
Write the importer second, for a stated subset of JSONata, once the exporter's differential has run.
The exporter is about the size of the OpenFisca bridge (2,212 lines of Haskell, measured today); the importer is about the size of the Blawx importer (3,457 lines).

## 2. RUML 1.0.0, read at source

### 2.1 Provenance, licence, trademark

| what                | state **[E, read 2026-11-26]**                                                                                                                                                                                                                                                                                       |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Specification       | "RUML – Rulemapping Logic Format", version 1.0.0, 15 November 2026, at `https://ruml.org/1.0.0/`, published by Law as Code Institut GmbH; Rulemapping Group GmbH holds the rights; English is authoritative (`spec/en/index.md`). `ruml.org` answered with no bot challenge.                                         |
| Repository          | `github.com/Law-as-Code-Institute/ruml`, created 2026-11-10, last pushed 2026-11-16, two commits, tag `v1.0.0` with no release assets, 31 stars, 1 fork, 2 open issues, no pull requests accepted (`README.md`, `gh api`).                                                                                           |
| Licence of the text | The specification text is CC BY-SA 4.0. "The license covers the document, not the format. Building a runtime environment, producing, processing or exchanging RUML files requires no license and no permission." ShareAlike "does not extend to software that implements the format, nor to rulemaps created in it". |
| Licence of the rest | The JSON Schemas, the conformance tests, the packages and the examples inside `spec/` are Apache-2.0 (`LICENSE.md`, `REUSE.toml`). GitHub's licence field for the repository reads `NOASSERTION`, because the licences are stated per path.                                                                          |
| Trademark           | RUML is a trademark of Rulemapping Group GmbH; an EU application is filed. "Referring to the format is free: statements such as “supports RUML” or “RUML-compatible” are permitted where they are accurate. Files, software and services that do not conform to this specification may not be labelled RUML."        |
| Versioning          | `$specVersion` is `MAJOR.MINOR`. A parser must accept its own major version with a minor up to its own, and must reject a higher minor (RUML 2.3, rule FMT-09). A published version "stays available unchanged at its version address".                                                                              |
| The two parsers     | See §2.7.                                                                                                                                                                                                                                                                                                            |
| Packaging after tag | The tag's README installs the schemas as `@law-as-code-institute/ruml-schema` from the GitHub npm registry. The branch head moved them to public npm as `@law-as-code/ruml-schema`. RUML 8.1 still names the older package (§2.5).                                                                                   |

Two consequences for L4.
An exporter may be called a RUML exporter only if its output conforms, so conformance is a gate on the name and not a nicety (R9, §4.8).
Implementing the format needs no licence, so approach (a) of §6 has no licence cost.

### 2.2 The data model

| element          | what the specification says                                                                                                                                                                                                                                  | where                   |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------- |
| File             | A JSON object with `$format: "RUML"` and `$specVersion` as its first two fields, then `capabilities` (optional), `metadata` and `rulemap`; no other root field.                                                                                              | RUML 2.2, FMT-05, -07   |
| Metadata         | `id` (UUID v4), `version`, `created`, `modified` and `status` (`draft`, `review`, `approved`, `inForce`, `suspended`, `expired`, `replaced`) are required; `inForce` also needs `validFrom`, `expired` needs `validUntil` and `replaced` needs `replacedBy`. | RUML 3.3, META-01 to 14 |
| Rulemap          | One field, `nodes`: a flat map from a LexID (a string such as `"1"`, `"42"`) to a node; the root is `"1"`; a parent lists its children by LexID, and the order is significant.                                                                               | RUML 3.4, 3.5           |
| Node             | `id` (UUID v4) and `label` (non-empty) are required; `operator` on a parent; `children`; `altText`; `description`; `capabilities`; `decisionMode`; `modular`. The node's type and LexID are not stored.                                                      | RUML 3.5, NODE-01 to 12 |
| Operators        | `AND`, `OR`, `XOR`, `NOT_AND`, `NOT_OR`, `NOT_XOR`, `DELEGATED`, and `undefined` (drafts only).                                                                                                                                                              | RUML 3.6                |
| Statuses         | A node's status is `true`, `false`, `undefined` or `ignored`, kept in a separate `.ruml-result` file and never in the rulemap.                                                                                                                               | RUML 5.0, 5.1           |
| Capabilities     | An extension mechanism. Each has a role: `data`, `decision` (leaf only), `combiner` (a `DELEGATED` parent only) or `reaction`. A capability with `required: true` that a parser does not implement makes it reject the file (CAP-01).                        | RUML 4.1 to 4.4         |
| Data points      | `ruml:datapoints`: typed inputs keyed by an identifier matching `[a-z_][a-z0-9_]*`, with `binding` of `input`, `external` or `computed`, optional `validation`, and reusable structured `sets`.                                                              | RUML 4.7                |
| Leaves           | `ruml:query` decides a leaf by a JSONata 2.2.0 expression over an input document that holds each data point's value under its identifier; `ruml:ai-query` asks a model; `ruml:tree-include` evaluates a node of another file.                                | RUML 4.8, 4.9, 4.16     |
| Combiner         | `DELEGATED` plus `ruml:expression`: a JSONata expression over `$children`, an array of `{lexId, label, status}`, for thresholds and majorities; every child is evaluated first.                                                                              | RUML 3.6.4, 4.14        |
| Sharing          | A node listed in more than one `children` array is a modular node and must say `modular: true`; it exists once in `nodes`, and its results are kept per path. Self-reference is recursion.                                                                   | RUML 6.1 to 6.5         |
| Across files     | `ruml:tree-reference` points at a node of another file and is never evaluated; `ruml:tree-include` evaluates it in place of a leaf. Both name an immutable version and a node UUID.                                                                          | RUML 4.15, 4.16         |
| Provenance       | `ruml:text-reference` carries texts, as plain text or as Akoma Ntoso written as JSON with a digest, and anchors a node to one.                                                                                                                               | RUML 4.12               |
| Reactions, audit | `ruml:actions` attaches operations to a node's status; `ruml:protocol` asks the engine for a CloudEvents record of the run.                                                                                                                                  | RUML 4.10, 4.13         |
| Container        | `.rumlc`, a ZIP with hashes (SHA3-256 over the RFC 8785 form), signatures and encryption. A bare `.ruml` has no integrity protection: "This is intentional".                                                                                                 | RUML 2.4, Chapter 7     |
| Validation rules | 148 rule identifiers: 83 checkable by the JSON Schema alone, 55 needing logic beyond it, 10 binding the tool and not the file. Ten prefixes, from MOD (6 rules) to CAP (38).                                                                                 | RUML Chapter 8          |

The rule counts are my own tally of the layer column of `spec/en/08-validation/index.md` **[E]**.

### 2.3 Operators and evaluation

The specification does not define evaluation beyond what the data model needs ("Runtime evaluation algorithms beyond what the data model requires" is on its list of what it does not define, RUML 1.1), but RUML 3.6 gives the operators' semantics in two modes.

| operator       | `complete` mode (RUML 3.6.1 to 3.6.3)                                                                                              | `optimized` mode                                                                                                   |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `AND`          | any child false: false; else any undefined: undefined; else true                                                                   | children in order; the first false gives false and the first undefined gives undefined, and the rest are `ignored` |
| `OR`           | any child true: true; else any undefined: undefined; else false                                                                    | the same as `complete`: "OR never short-circuits" (the specification's own OR tests say so, RUML 3.6.2)            |
| `XOR`          | the same table as `OR`                                                                                                             | children in order; the first true gives true and the first undefined gives undefined, and the rest are `ignored`   |
| `NOT_AND` etc. | the value of the un-negated operator with true and false swapped; undefined stays                                                  | the same                                                                                                           |
| `DELEGATED`    | every child is evaluated, none is `ignored`; if any child is undefined the node is undefined; else the combiner expression decides | the same                                                                                                           |

Six observations about that table, each read at source **[E]** unless marked.

- **O1. `XOR` is not an exclusive or.**
  RUML 3.6.3 says it "does not refer to the logical exclusive XOR (where two `true` inputs yield false)": it is a disjunction over children "deliberately constructed such that only one can be `true`".
  So an L4 exclusive-or cannot be written as RUML `XOR`, and an RUML `XOR` read into L4 is an `OR` with an unchecked promise (§5).
  The 2026-09-09 research memo's suggestion of `(a OR b) AND NOT (a AND b)` for a RUML XOR is therefore not what RUML means by it.
- **O2. Among the logical connectives, `OR` is the only one with no early exit.**
  `AND` and `XOR` stop early in `optimized` mode; `OR` does not, and `DELEGATED` must not either (RUML 3.6.4, OP-03).
- **O3. The two modes can give one file two statuses.**
  `AND [undefined, false]` is `undefined` in `optimized` mode and `false` in `complete` mode.
  A file cannot say which mode it needs; the repository's open issue 2 (filed 2026-11-22, no comments) says so.
- **O4. `complete` mode is strong Kleene for `AND` and `OR`, and `optimized` mode is left-sequential for `AND` and `XOR`.**
  The column headed "strong Kleene says" in `UNKNOWN-EVALUATION-SPEC.md` §2.3 (`x AND FALSE` is `FALSE`, `x OR TRUE` is `TRUE`, `NOT x` is unknown) is the `complete` table, and the spec's ruling U1 takes "Kleene tables on known values, left-to-right order" **[E, `specs/todo/UNKNOWN-EVALUATION-SPEC.md` §2.3 and the ruling U1]**; so RUML `complete` is the mode that agrees with L4's reading where a fact is missing **[U, derived from the tables]**.
  Today's evaluator does not give those answers for an unsupplied fact: the spec's own probes find `x AND FALSE` "stuck" **[E, same section]**.
  When every leaf yields `true` or `false`, the two modes agree on the root's status and on every node that `optimized` mode evaluates, and L4 agrees with both **[U, derived; confirmed on the worked example, §4.7]**.
- **O5. An `ignored` child does not count.**
  RUML 5.0 says an `ignored` node "is NOT included in the operator calculation of the parent node", and gives three causes: short-circuit, a manual skip and a conditional deactivation.
  The last two are not tied to a mode, no construct of 1.0.0 produces them (§2.5), and none of the 103 evaluation tests has one.
  The exporter never writes one.
- **O6. The statuses are counted two ways.**
  RUML 3.5.1 lists `pending`, `true`, `false`, `undefined` and `ignored` as runtime statuses; RUML 5.0 says a result node "MUST have one of the following four", which are `true`, `false`, `undefined` and `ignored`.

### 2.4 The leaves: what JSONata does with what an L4 author means

RUML 4.8 says the expression is "evaluated against an input document: a JSON object that holds the value of each DataPoint under the DataPoint's id. A DataPoint without a value has no entry."
A result of `true` or `false` is the node's status; anything else, including no result, makes the node `undefined`.
The rest of this section is measured: JSONata 2.2.0 (the version RUML 1.5 names), under Node v26.4.0, installed with `npm install jsonata@2.2.0 --ignore-scripts` in a scratch directory, run on 2026-11-26 **[E]**.

| expression                  | input document           | JSONata result | RUML status | the hazard                                                                         |
| --------------------------- | ------------------------ | -------------- | ----------- | ---------------------------------------------------------------------------------- |
| `dp_a > 5`                  | no `dp_a`                | no result      | `undefined` | none: an ordering comparison propagates a missing value                            |
| `dp_a = 5`                  | no `dp_a`                | `false`        | `false`     | equality on a missing value is false, not undefined                                |
| `dp_a != 5`                 | no `dp_a`                | `false`        | `false`     | so is inequality                                                                   |
| `dp_flag = true`            | no `dp_flag`             | `false`        | `false`     | twelve of the 49 expressions in the specification's example files are of this form |
| `dp_flag`                   | no `dp_flag`             | no result      | `undefined` | the bare identifier of a Boolean data point does propagate                         |
| `dp_flag`                   | `dp_flag` is `"yes"`     | `"yes"`        | `undefined` | a non-Boolean is not coerced; the node is undefined                                |
| `$exists(dp_a) ? dp_a = 5`  | no `dp_a`                | no result      | `undefined` | a guard restores the missing-value propagation                                     |
| `dp_a >= 18 and dp_b >= 18` | only `dp_a`: 20          | `false`        | `false`     | `and` is two-valued: a missing operand counts as false                             |
| `dp_a and dp_b`             | `dp_a` 1, `dp_b` 2       | `true`         | `true`      | `and` coerces numbers and strings to Booleans                                      |
| `0.07 * 100 = 7`            | none                     | `false`        | `false`     | the product is 7.000000000000001: numbers are IEEE doubles                         |
| `dp_x / 0 > 1`              | `dp_x` 1                 | `true`         | `true`      | division by zero is Infinity, where L4 raises                                      |
| `dp_s > 1`                  | `dp_s` is `"a"`          | error T2009    | `undefined` | mixed types are an error, not false                                                |
| `dp_a > 9007199254740993`   | `dp_a` 9007199254740992  | `false`        | `false`     | integers above 2^53 are not distinct                                               |
| `dp_d < "2024-06-01"`       | `dp_d` is `"2024-01-01"` | `true`         | `true`      | ISO dates compare correctly as strings                                             |
| `not(dp_a)`                 | `dp_a` true              | error T1005    | `undefined` | the negation is `$not(...)`; `$not` of a missing value has no result               |

The two rows that end in an error (T2009 and T1005) show `undefined` by inference: RUML 4.8 speaks only of results, and RUML 5.0 lists "technical errors" among the causes of `undefined` **[U]**.
The probe script is reproduced from the commands in §8.
The same run showed that `$count($children[status = "true"]) >= 2` evaluates as RUML 4.14 says when `$children` is bound.

How much JSONata the suite itself uses.
Across the 97 fixture files of the conformance suite there are 35 `expression` strings and 10 distinct ones **[E, `grep` over `tests/*/*.fixtures/*.ruml`]**.
They are a comparison of a data point with a number, a subtraction compared with a number, a `$count` over `$children` compared with a number (five forms), and one `$lookup` in a two-entry literal map, which is how the suite turns three answers (`yes`, `no`, `unknown`) into `true`, `false` and no result.
One uses `$random`.
The 49 expressions in the specification's example files (`spec/en/*/*.examples/*.ruml`) are mostly the same: comparisons of a data point with a literal, twelve of them `= true`, one string equality, and `$count` over `$children`.
Four go further: a computed data point's decimal arithmetic (`(dp_zve - 11604) * 0.14`), JSONata `and` and `or` inside two combiners, and two that belong to a custom combiner and are not meant to run (`weightedScore(children) >= 27` and `count(children, true) >= 2`).
The computed data point is exactly the IEEE hazard of the table above.
So the subset an importer needs first is small, and the subset an exporter emits is smaller still.

### 2.5 What RUML 1.0.0 leaves open, or says two ways

- **Inputs of an included subtree.**
  RUML 4.16: "how the included subtree obtains its inputs … is not defined in this version of the specification."
  Three options are "under consideration": shared by data point id, namespaced per file, or an explicit binding per include.
  An importer cannot be faithful to an inclusion, and an exporter has nothing to write for one (§5.3).
- **No evaluator.**
  The specification defines the operators' results but not an algorithm, and none was found: the two parser repositories do not evaluate, `npm` has only the two `@law-as-code` packages under "ruml", and a GitHub repository search is empty (§2.7).
  The suite's evaluation tests are the only executable statement of the semantics.
- **The package name.**
  RUML 8.1 names `@law-as-code-institute/ruml-schema` "in the GitHub npm registry"; the repository's head names `@law-as-code/ruml-schema` on public npm, which holds versions `0.0.0-stage` and `1.0.0` **[E, `registry.npmjs.org`, 2026-11-26]**; the old name returns 404 on public npm.
  The specification text lags the packaging by one commit.
- **Example identifiers.**
  The examples in RUML 4.1 and 4.8 give the root node the same UUID as `metadata.id`, which NODE-08 forbids ("The `id` of a node MUST NOT equal … `metadata.id`").
  Those are page examples and not the validated example files, which I did not check.
- **Mode.**
  O3 above: a file cannot declare which evaluation mode it needs.
- **A defect of the one producer and not a gap in the text; and what it calls the format.**
  A file exported by Rulemapping's Builder fails `NODE-07` on 13 of its 88 nodes (§2.8).
  The tool's own RUML dialog expands the acronym as "Rulemapping Language Format" where the specification says "Rulemapping Logic Format" (§2.1) **[E, read off the tool's screen by the session that drove the browser on 2026-11-28; not re-checkable from the files]**.

### 2.6 The conformance suite

What it is **[E]**.
`tests/` in the repository holds 22 descriptors (`*.test.yaml`), 193 tests (103 evaluation, 90 validation) and 97 `.ruml` fixtures, and no `.ruml-result` file.
The figures reported for the suite elsewhere, 22 test descriptors and 97 fixtures (the Pitch deep dive, §2), are right and say nothing of the 193 tests.
The same data is published at `https://ruml.org/spec-tests.zip` (HTTP 200, 132,063 bytes, `last-modified` 2026-11-15 12:43 GMT, 125 files, SHA-256 `701baa7515d4…` when fetched on 2026-11-26): its fixtures, schemas and test bodies are identical to the repository's, and its descriptors differ only in their header comment lines **[E, `diff` of all 22]**.
The ZIP's URL carries no version, and the release `v1.0.0` has no assets, so the repository is the only pinnable source.

Validation tests: 90, of which 21 expect `accept` and 69 `reject`, 74 at the `schema` layer and 16 at the `semantic` layer.
They name 38 of the 148 rule identifiers; no test exists for Chapter 1, 5 or 7, none names a `META` rule, and no test names any of the ten tool-layer rules (OP-03 is exercised without being named: all seven `DELEGATED` evaluation tests run in `optimized` mode and assert that no child is skipped) **[E, recounted by the reviewer]**.
The runner contract requires only accept-or-reject: matching the rule ids a test names is "CAN fail" (`runner-contract.md`, validation section), while Appendix A and the descriptor schema say a rejection must report them, so the specification disagrees with itself here.
Run through the JSON Schema alone (Ajv 8.20.0, draft 2020-12, with `ajv-formats`), the schema agrees with all 17 schema-layer accepts, all 57 schema-layer rejects and all 4 semantic accepts, and with 2 of the 12 semantic rejects, which is what the `layer` labels predict (the two are FMT-01 and FMT-02, failures to parse the file at all and not schema logic) **[E, run 2026-11-26]**.

Evaluation tests: 103, 55 in `optimized` mode and 48 in `complete`, over seven operators (`AND` 22, `NOT_AND` 22, `OR` 12, `NOT_OR` 12, `XOR` 14, `NOT_XOR` 14, `DELEGATED` 7) **[E]**.
Each runs a fixture with three leaf children whose expression looks an answer up in a literal map (`yes`, `no`, `unknown` giving true, false and no result), and asserts four statuses: the root and its three children.
In six pairs of tests the root's status differs between the two modes, which is O3 as data; all seven `DELEGATED` tests run in `optimized` mode, so that operator in `complete` mode is untested.
`ignored` is expected only for `AND`, `NOT_AND`, `XOR` and `NOT_XOR`; no test expects it from `OR` or `DELEGATED`.
A 60-line evaluator written from RUML 3.6, 4.8, 4.14 and 5.0 alone, with JSONata 2.2.0 for the leaves and the assertions, passes all 103, so the operator table of §2.3 and observations O2 and O3 are confirmed against the suite and not only against the prose **[E, run 2026-11-26]**.

**The contract and the data disagree, and the data is what a runner must follow.**
`runner-contract.md` describes an evaluation test as an `expect:` file holding a `RUML-Result`, with `inputs` keyed by node path and a structural comparison, and a runner that sets `frozenClock` and `evaluationId` when a test gives them.
None of the 103 tests has an `expect:`, and none sets a `frozenClock` or an `evaluationId` (which the contract makes conditional) **[E, `grep`]**.
All 103 have `assertions:`, each a JSONata query over the result (such as ``evaluation.results.`1.1`.status``) with an `expectedValue`, and `inputs` that is the flat input document of RUML 4.8.
The descriptor schema `tests/schema/spec-test.schema.json` requires `assertions`, allows no other key (so `expect:` is invalid), and no Markdown page mentions `assertions` **[E, read from the schema, `grep` of `spec/en`]**.
So the contract describes an earlier design; the descriptor schema still carries definitions (`LeafInput`, `QueryResult`) shaped like it, is versioned `spec-test/0.1`, and refers to a `RULES.md` that does not exist.
A harness has to implement the schema's reading, and should say so.

What the suite cannot check, because no test has it **[E]**: an include is evaluated (all six `ruml:tree-include` tests are validation tests, and the included file is never supplied); a modular node is evaluated; any JSONata beyond the `$lookup` leaf and one `$count` combiner; any status `reason` or capability payload (only four `.status` values are asserted); and the exporter's guards (`$exists`) or comparisons.
So the suite calibrates a reader of the operators, and says nothing about the leaves that §4 emits.
Those are checked by JSONata itself (§8).

**Third-party text.**
At least one fixture quotes German statute text (`4-12-ruml-text-reference.fixtures/reject-two-represents-anchors.ruml`, a sentence of § 1 of the Einkommensteuergesetz), and the repository states no provenance for it **[E]**.
That is a further reason to fetch the suite and never copy it (R11, M4).

### 2.7 The two public parsers

Two parsers are public, `Law-as-Code-Institute/ruml-python` (`1a421333…`) and `Law-as-Code-Institute/ruml-js` (`cb7d754b…`), both created 2026-11-10 and last pushed 2026-11-16 **[E, `gh api`]**.
What follows was read from the two repositories by a delegated reader and then spot-checked by me on the points marked; nothing from either was run or installed.

| question                  | `ruml-python`                                                                                                                                                                                         | `ruml-js`                                                                                                                                                                                      |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| package, version, licence | `ruml-parser` 1.0.0, Apache-2.0 **[E, `pyproject.toml`]**                                                                                                                                             | `@law-as-code/ruml-parser` 1.0.0, Apache-2.0, ESM only **[E, `package.json`]**                                                                                                                 |
| runtime                   | Python 3.14 or later **[E, `pyproject.toml`]**                                                                                                                                                        | no `engines` field; CI builds with Node 24 and pnpm 11                                                                                                                                         |
| validator under the hood  | `jsonschema` (draft 2020-12) with format checkers; `pydantic` models; `ruml-schema` 1.0.0                                                                                                             | `ajv` 8 (2020) with `ajv-formats`; `zod` 4 models built from the schema at run time; `@law-as-code/ruml-schema` bundled                                                                        |
| JSONata                   | none: an expression is a string                                                                                                                                                                       | `jsonata ^2.2.1`, in a separate `./query` entry that parses an expression and lists the data points it reads **[E, `pnpm-workspace.yaml`]**; it is not called by the validator **[E, `grep`]** |
| evaluates a rulemap?      | no: "This library is the parsing/validation layer only — it has no evaluation logic." **[E, `README.md`]**                                                                                            | no: types, models and validation; no AND, OR, XOR, short-circuit, modular node, include or JSONata evaluation                                                                                  |
| command line              | none                                                                                                                                                                                                  | none                                                                                                                                                                                           |
| maintenance               | one commit ("Release 1.0.0", 2026-11-16), one author, one workflow that releases on push; no pull-request trigger and so no test on a proposed change; pull requests "not accepted yet"; no changelog | the same shape                                                                                                                                                                                 |
| runs the shared suite?    | not in public: its docstrings name a `ruml-spec-tests` workspace member that is not in the export                                                                                                     | not in public; its README mentions the suite                                                                                                                                                   |

**What they check beyond the JSON Schema.**
The schema layer (83 rules) is whatever `ruml.schema.json` encodes, in both.
Of the 55 semantic rules, the reader found about eleven enforced in the Python code and about fifteen in the TypeScript code, seven in both (OP-02, CAP-06, CAP-08, CAP-10, CAP-15, DP-16, MOD-01), and the remainder in neither (the reader did not audit separately the rules that only require a parser to accept something).
Not enforced by either: NODE-08 (duplicate UUIDs), NODE-10 (a `children` entry naming no node), FMT-05 (first-two-fields order), FMT-12, DP-11 and DP-12, TXT-09 (the content digest), every RUML-EXT rule, and the cross-file TREE rules.
Python alone checks NODE-05, DP-17, MOD-04, MOD-05 and CAP-04 (for the capabilities it implements); TypeScript alone checks META-03, META-09, META-11 (by string comparison, against the wall clock), OP-04 for custom combiners, CAP-07 for custom roles, DP-18, TXT-12 and CAP-01 (for draft and reverse-domain ids only, and only in its validator); CTX-10 and TXT-19 are checked for a model query's inputs by Python and for node-level references by TypeScript **[delegated read, re-checked by the reviewer against the code; the absence of any JSONata validation in the validator and of CAP-01 in the Python mapping spot-checked by `grep`]**.
Neither checks every schema and semantic rule, as CAP-28 requires of a validation tool, and the two disagree with each other on files the suite does not test.
Python reports rule codes and JSON Pointers for the structural rules it has; TypeScript reports a message and a coarse dotted path, and never a rule code.
`ruml-python` raises `NotImplementedError` for a data point whose `binding` is `computed`, so it cannot read the specification's own `bindings.ruml` example nor a file written by Phase 3 of §9 **[delegated read; `mapping.py:420`, spot-checked]**.
`ruml-js` has an `expressionReads` hook for a caller to inject an exact JSONata-based reader of data point ids; the default is a token scan.

**What that means for L4.**
Neither can be called as a process by a Haskell program without a wrapper that someone writes, and neither has a stable interface for embedding.
Python 3.14 is a recent runtime to ask of a user, and the TypeScript package has no lock file and a development build that needs pnpm 11.
A parser written from the schema needs draft 2020-12 with `if`/`then` (about 67 uses in `ruml.schema.json`), `contains` and its counts, `propertyNames`, ECMA-262 regular expressions and format assertion **[delegated keyword count]**, and then the semantic rules and an evaluator on top, none of which the schema or the two parsers supply in full.
As cross-checks the two are useful exactly where they overlap, and on a file where they disagree the disagreement is itself a finding.

### 2.8 What Rulemapping's own tool writes and reads

Sections 2.1 to 2.7 are the specification, its suite and the two parsers.
This one is the only producer of RUML files that was available to run: the Rulemap Builder, Rulemapping Group's own tool for the format it owns, used in a browser on 2026-11-28 through a free workspace account.
It reports no version **[U]**, so what follows is what it did on that day, to one statute it publishes and to one file of ours.
The statute file is the export of a copy of the published rulemap that we imported into our own workspace (M3), so nothing here shows that the catalogue's own artefact carries the same operators.
Facts marked "read off the screen" were read by the session that drove the browser and cannot be re-checked from the files; every other figure was recomputed from the files on 2026-11-28, and the tool's text outline of the statute (`KSchG_1.txt`, a fifth file, 5,115 bytes) was used only to check the 88 labels and the absence of an operator on the 13 leaves.
None of the files is committed: one of them embeds a statute's text, so M4 applies.

**What the tool offers [E, read off the screen].**
A catalogue of published "Norm-Rulemaps" lists 51 entries, all of them German federal statutes by title, the largest the Civil Code at 6,657 nodes; its filter for "Decision-Rulemap" returns none.
A whole rulemap is exported from a panel on the right with three choices, XML, RUML and image or text, and the browser then asks where to save the file; a right-click on a node offers a subtree as PDF, PNG or a text outline.
The RUML choice has an information dialog titled "RUML (part of our long-term roadmap)", and it writes a file all the same.
"Add Rulemap" accepts `.xml` and `.ruml` (the `accept` attribute of its file input).

**One statute, exported as RUML [E].**
The file is `KSchG.ruml`, the Dismissal Protection Act (Kündigungsschutzgesetz), saved as one line of JSON.

| what         | state                                                                                                                                                                                                                                                                                                                                                       |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| file         | 161,351 bytes, SHA-256 `e4ad82bdb58ca59e…`, 88 nodes; `$format` and `$specVersion` (`"RUML"`, `"1.0"`) come first, then `capabilities`, `metadata`, `rulemap`                                                                                                                                                                                               |
| metadata     | `status: "inForce"`, `jurisdiction: "DE"`, `language: "de"`, `validFrom`; `version` is `2021-06-18`, the statute's version date, which is the form RUML 3.3 asks of a file with `documentType: "law"` (this file has no `documentType`) and a string the schema accepts; `id` is the tool's own id for the rulemap                                          |
| capabilities | one, `ruml:text-reference` with `required: false`, holding one text entry: `type: "embedded"`, an ELI `uri`, a `title`, a `digest`, a `source` (a URL at a federal legal-information portal, with a digest of its own), `timestamp`, `isReferenced`, and `content`, the statute as Akoma Ntoso written as JSON                                              |
| the digest   | it verifies: the SHA3-256 of the UTF-8 bytes of the RFC 8785 form of `content` equals the declared `digest` (`TXT-09`), computed with a short routine of ours; neither public parser checks `TXT-09` (§2.7)                                                                                                                                                 |
| size         | `content` is 131,901 bytes in canonical form; the `capabilities` array is 132,528 bytes, 82.1 % of the file; the file is 1,834 bytes per node                                                                                                                                                                                                               |
| nodes        | keyed `"1"` to `"88"`; each key equals the id the tool's own text outline gives that node (checked on all 88 labels), not in tree order (the depth-first order runs 1, 30, 2, 34, …) and, as far as that pattern shows, in creation order **[U]**: the root is 1, the four parts of the Act are 30 to 33, the sections 2 to 29 and the subsections 34 to 88 |
| per node     | a UUID `id`; a `label` (the section number and heading, or the number of a paragraph); `description: ""` and `decisionMode: "fallback"` on all 88; one node-level `ruml:text-reference` holding one anchor of type `represents` to the text, which carries an `element` on 87 of the 88 (not the root)                                                      |
| operators    | the 20 parents are all `OR`; 13 childless nodes have `AND`; the other 55 childless nodes have no operator                                                                                                                                                                                                                                                   |
| logic        | none: no `ruml:query`, `ruml:ai-query`, `ruml:tree-include` or `ruml:datapoints` anywhere, so none of the 68 leaves has a `decision` capability (the tool's readiness panel agrees: end-node criteria 0 of 68 **[read off the screen]**)                                                                                                                    |

**It fails the format's own rule [E].**
The 13 childless nodes with `AND` are the 13 sections that have no subsections (§§ 2, 3, 4, 6, 7, 8, 11, 12, 16, 21, 25, 25a and 26).
RUML 3.5.2a says a leaf "MUST NOT have an `operator` unless `metadata.status` is `draft`", and `NODE-07` is a schema-layer rule.
Run through `ruml.schema.json` (Ajv 8.20.0, draft 2020-12, with `ajv-formats`), the file gives 27 errors on 13 distinct nodes: `operator` forbidden on a childless node (13), the matching `then` branch failing (13), and the enclosing `else` branch failing for the file (1).
With the operator removed from each of the 13 childless nodes and `status` left at `inForce`, the file validates with no error, so this is its only schema-layer defect; setting `status` to `draft` clears it too, but a draft also excuses other rules (§12), so the first run is the cleaner proof.
The suite has a test for exactly this shape, `operator--rejects-operator-on-leaf` (layer `schema`, expect `reject`, rule `NODE-07`, in `tests/03-data-model/3-5-node-object.test.yaml`): "leaf `2` of this `inForce` file has `AND`".
Why the tool writes it is not known **[U]**; a default operator on a section that never received children is the likely cause, and the subsection leaves have none; the tool's own text outline prints an operator on every parent and on none of those 13.
Neither public parser was run on the file **[U]**; both validate the schema layer from the same schema (§2.7), and each has a test for this rule (`ruml-js/src/ruml.test.ts:221`, `ruml_parser/tests/test_metadata_status_rules.py` in `ruml-python`), so both would be expected to reject it.

**The XML export loses every leaf's decision [E].**
`KSchG.xml` (6,471 bytes, SHA-256 `5851a4c73c8a0061…`) is `<rulemap title application="query-action-ai">` over `<node id title alttext logic>`.
Its 88 nodes carry the same ids as the RUML keys, with `logic` `or` on 20, `and` on 13 and `virtual` on 55, so the 13 childless nodes appear with `and` there too.
It carries no query and no data point.
For our own file (below) the tool wrote five nodes, `and` at the root, `or` on node 3 and `virtual` on the three leaves, with no trace of the three queries or three data points that the tool displays **[read off the screen]** and that its RUML export keeps (`fee_waiver_applies.xml`, 478 bytes, SHA-256 `5380fc430036ca80…`).
So the XML is structure, titles and operators, and a consumer that wants the logic has to take RUML.

**Our own file, through the tool and back [E].**
We uploaded `fee-waiver.ruml` of §4.7 (2,379 bytes, 105 lines, `status: "draft"`, SHA-256 `4886a6f37a4dd659…`) with "Add Rulemap".
The tool accepted it, showed five nodes, three data points and three queries **[read off the screen]**, and, asked for RUML, wrote a file of 1,667 bytes (one line, so the two sizes are not comparable; SHA-256 `dd1a0aa99b0500b1…`) that validates against the same schema.
Compared path by path with what we uploaded:

- Values that differ: `metadata.id` (the tool's own id for the rulemap stands where ours was; one upload and one download cannot show whether it is assigned on upload or on export **[U]**) and `metadata.modified` (earlier than the moment we exported, so it may be the time of the upload or of the last edit and not of the export **[U]**).
- Members added: `sensitive: false` on each of the three data points; `decisionMode: "fallback"` and `description: ""` on each of the five nodes; and `metadata.description`, set to the uploaded file's name, `fee-waiver.ruml`.
- Members lost: none.
  The five node UUIDs, the labels, the `children` lists, the operators (`AND` at the root, `OR` on node 3), the data points' names, types and bindings, the three expressions, `required: true` on both capabilities, and `created`, `version` and `status` came back with the values we uploaded.
- Order, which a path-by-path comparison cannot see, did change: the data points came back as `dp_age`, `dp_income`, … where we uploaded `dp_income`, `dp_age`, …; each capability has `required` after `payload`; and each node gained its added members in a fixed place.

So for this file the tool reads RUML and rewrites it without changing what it means, and it preserves operators over children, `ruml:query` leaves and `ruml:datapoints`, which the statute file never exercises; whether it evaluates them is not tested.

**Not tested [U].**
The other 50 statutes of the catalogue; whether the tool's own import rejects a file that breaks a rule (we gave it only valid files); `XOR`, `DELEGATED`, `ruml:ai-query`, `ruml:tree-include` and modular nodes, which neither our file nor the statute uses; whether the tool evaluates a rulemap; the tool's version; and any file larger than the 88 nodes of the Act.

## 3. What L4 already has to build on

| piece                               | what it is                                                                                                                                                                                                                                                                 | where                                                     |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| The bridge pattern (I1)             | `L4.<Target>.{IR,Lower,Emit}` plus `l4 export FORMAT`, keyed on `@export`, with `lowerModule :: Module Resolved -> Either [LowerError] …` reporting every rejection in one batch, each naming the construct and its source range.                                          | `BACKEND-PORTFOLIO-SPEC.md` §4 I1; `L4/Export.hs:173`     |
| The oracle (I2) and the ladder (I3) | `L4.EvaluateLazy` is the reference semantics; expected outputs come from L4, never from the target; claims are tiered golden, executed round-trip, law-validated.                                                                                                          | `BACKEND-PORTFOLIO-SPEC.md` §4 I2, I3                     |
| The harness posture (I4)            | Target-toolchain checks run when the toolchain is present, skip silently when it is not, and are never a build dependency. The precedent is `etc/validate-dmn.mjs`, run as `npx --yes --package=dmn-moddle node etc/validate-dmn.mjs …`, installing nothing into the repo. | `BACKEND-PORTFOLIO-SPEC.md` §4 I4; `etc/validate-dmn.mjs` |
| Command names                       | `l4 export FORMAT FILE` and `l4 import FORMAT FILE`; a format is named after the notation, in lowercase.                                                                                                                                                                   | `specs/todo/CLI-SURFACE-SPEC.md` C1, C3                   |
| A shared fidelity report            | `L4.Interchange.Fidelity`: a named, located loss, with severity `Blocking`, `Lossy` or `Advisory`, shared by the DMN and BPMN exporters.                                                                                                                                   | `jl4-core/src/L4/Interchange/Fidelity.hs`                 |
| An exporter that refuses            | `l4 export yscript` takes the pure-propositional subset and refuses the rest by name, "not silently dropped or inlined"; it is one-way and has no fidelity report.                                                                                                         | `doc/exports/yscript.md`                                  |
| An importer to model                | `l4 import blawx FILE` (`Parse` 955 lines, `Lift` 2,502) with `--parse-only` and `--roundtrip`; it lifts a stated fragment of Blawx's corpus.                                                                                                                              | `doc/exports/blawx.md`; `specs/todo/BLAWX-EXPORT-SPEC.md` |
| A three-valued semantics            | Left-sequential strong Kleene with residuals, ruled U1 (2026-10-01). Build steps 1 to 3 landed; steps 4 to 7 are parked. `jl4/app/L4/Cli/*.hs` has no `unknowns` option **[E, `grep`]**, so a missing-input evaluation is not reachable from `l4 run` today.               | `specs/todo/UNKNOWN-EVALUATION-SPEC.md` §8, U1            |
| Exact numbers                       | L4's `NUMBER` is an exact rational; the portfolio's number-lowering row names the divergence for each lossy target.                                                                                                                                                        | `BACKEND-PORTFOLIO-SPEC.md` §2.1, §6                      |
| Annotations the lexer knows         | `@desc`, `@ends-because`, `@export`, `@infix`, `@infixl`, `@infixr`, `@lang`, `@nlg`, `@nonassertable`, `@nonexhaustive`, `@ref`, `@ref-map`, `@ref-src`. Any other `@name` line is ignored with a warning **[E, `l4 check` on this tree]**.                               | `jl4-core/src/L4/IgnoredAnnotation.hs`                    |

Sizes of the nearest bridges, measured by `wc -l` on this tree today, for the cost estimate in §9: `L4/Yscript` 456 lines (a propositional exporter), `L4/OpenFisca` 2,212, `L4/Catala` 4,029, `L4/Blawx` 9,156 (export 3,965 and importer 3,457, the rest XML and block handling), `L4/Dmn` 10,759.

## 4. Export: L4 to RUML

### 4.1 What is exported

One RUML file per `@export`ed decision whose result is `BOOLEAN`, reached from the `@export` roots as in the other bridges.
A decision that is not Boolean has no tree to write: RUML decides truth values, and its computed data points (RUML 4.7.2) are values inside a tree and not roots of one **[U]**.

| L4 construct                                                | RUML                                                                             | notes                                                                                                                   |
| ----------------------------------------------------------- | -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `a AND b AND c`, `a OR b OR c`                              | one `AND` or `OR` parent with the operands as children, in source order          | nested like operators are flattened; a mix is left as nested parents                                                    |
| `NOT (a AND b)`, `NOT (a OR b)`                             | a `NOT_AND` or `NOT_OR` parent                                                   |                                                                                                                         |
| `NOT atom`                                                  | a `NOT_AND` parent with the one leaf as its only child                           | R5: negation is structural, so each leaf stays a positive condition                                                     |
| `a UNLESS b`                                                | `AND [a, NOT_AND [b]]`                                                           | the parser already reads `UNLESS` as `AND NOT` (UNKNOWN-EVALUATION-SPEC §2.1)                                           |
| `a IMPLIES b`                                               | `OR [NOT_AND [a], b]`                                                            | `Lossy` note: truth is kept and the vacuity distinction is gone (RUML has no way to say "the antecedent did not apply") |
| comparison of a number, date or string input with a literal | a leaf with a `ruml:query` expression (§4.3)                                     | `<`, `<=`, `>`, `>=` direct; `=` and `<>` guarded                                                                       |
| a `BOOLEAN` input                                           | a leaf whose expression is its bare data point identifier                        | R5                                                                                                                      |
| an enumeration input compared with a constructor            | a leaf comparing the data point with the constructor's name as a string, guarded | the data point has type `enum`, with the constructors as `options`                                                      |
| a non-recursive helper decision used once                   | inlined: its body becomes the subtree                                            | the helper's name becomes the parent's label                                                                            |
| a definition used from two or more places                   | one node with `modular: true`, listed in each parent's `children`                | R7; recursion is refused                                                                                                |
| `GIVEN` parameters and fields of the subject record         | `ruml:datapoints` entries, `binding: {type: "input"}`                            | `NUMBER` is `number`, `STRING` is `string`, `DATE` is `date`, `BOOLEAN` is `boolean`, a payload-free `ONE OF` is `enum` |
| `@desc`, `@ref`, `@lang`                                    | `description`; later `ruml:text-reference` (§9, Phase 3); `metadata.language`    | no third-party text is embedded; a `@ref` is carried as a reference                                                     |

### 4.2 What is refused, and what is reported

R3: the exporter refuses by name, all at once, in the posture of `l4 export yscript`, and keeps its fidelity report for the losses inside the fragment, in the posture of `l4 export dmn`.
The reason is that RUML has no way to say "this part was dropped": a tree with a missing leaf is a different tree and evaluates, silently, to a different answer.
(The DMN page says its report "is not optional" reading, and defaults `--fail-on` to `none`, because DMN is "substantially less expressive than L4" and a blocking note usually describes the target.
That posture suits a format where a fallback is a legitimate document; for RUML a fallback leaf would be a wrong one.)

**Refused, each by name and range, in one batch:**

| construct                                                      | why RUML cannot take it                                                                                                                                                                                                                                                              |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| deontic rules: `MUST`, `MAY`, `SHANT`, `PARTY`, `WITHIN`       | RUML 1.0.0 has no obligation, permission or time rule inside the logic **[U]**; the time-related things it has are validity dates in `metadata` and in texts, `date`, `time`, `datetime` and `duration` data points, and `ruml:actions` deadlines, which are reactions and not rules |
| temporal contexts, `TODAY`, `NOW`, date-times, date arithmetic | an L4 clock has no data point in RUML to come from, and a leaf that read `$now` would not be reproducible from its inputs (RUML 3.6.4 and OP-05 allow it in a combiner and say what it costs); date addition is not an algebra to rewrite (I9)                                       |
| `BRANCH`, `CONSIDER` and `IF` over Booleans                    | first-match priority is compiled away only under a disjointness proof (I7); Phase 3 may use `L4.Viz.GuardedRows` for proven-disjoint arms                                                                                                                                            |
| recursion, mutual recursion, higher-order use                  | RUML's recursion is a tree that contains itself under `XOR`, which no L4 function is **[U]**                                                                                                                                                                                         |
| `/`, `MOD`, exponentiation, rounding                           | JSONata divides by zero to Infinity where L4 raises, and its numbers are doubles; refusing removes the hazard class (I8)                                                                                                                                                             |
| `LIST`, `MAYBE`, `SET OF`, records with payload constructors   | no node quantifies over a list; object data points with `cardinality` exist, and a JSONata leaf can filter and count over one, but a leaf of that kind is outside R4 and R6 (Phase 3)                                                                                                |
| `TYPICALLY`                                                    | refused in Phase 1; RUML 4.7.2 lists `binding.defaultValue` beside `hint` and `placeholder` and says only that a tool "MAY provide a default value", so whether an evaluator uses it is not stated **[U]**; mapping `TYPICALLY` to it could change meaning                           |
| `IMPORT` of a module with `@export`ed decisions needed         | each exported root is its own file; inclusion across files has no defined inputs (§2.5)                                                                                                                                                                                              |
| three-valued results (`UNKNOWN`, residuals)                    | there is no flag to evaluate with unknowns today (§3); and the leaf semantics for a missing fact is the subject of R5                                                                                                                                                                |

**Reported, in a fidelity report using `L4.Interchange.Fidelity`:**

| code        | severity   | what is said                                                                                                                                                                                                                            |
| ----------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `RUML-IMPL` | `Lossy`    | `IMPLIES` was written as `NOT a OR b`; the vacuity distinction is gone                                                                                                                                                                  |
| `RUML-NUM`  | `Advisory` | numbers in leaves are IEEE doubles in RUML (RUML 3.2.3) and in JSONata; L4's are exact; agreement is only guaranteed where every value and intermediate result is an integer or a dyadic rational below 2^53                            |
| `RUML-MODE` | `Advisory` | the file does not say which evaluation mode it needs; with a missing input the two modes can differ (O3); `complete` agrees with L4's strong Kleene                                                                                     |
| `RUML-PATH` | `Advisory` | a shared node is `modular: true`, so its results are kept per path; its status is equal at every path where it is evaluated, because every leaf reads one input document, and in `optimized` mode it may be `ignored` at some paths [U] |
| `RUML-DESC` | `Advisory` | node labels come from L4 names and source text; they are not the statute's wording                                                                                                                                                      |

### 4.3 The leaf: what is emitted, and why

R4 and R5 follow from the measurements in §2.4.

- **One atomic condition per leaf, and the connectives in the nodes (R4).**
  JSONata's `and` and `or` are two-valued, so `dp_a >= 18 and dp_b >= 18` with `dp_a` 20 and `dp_b` missing is `false`, where the tree `AND [dp_a >= 18, dp_b >= 18]` is `undefined` in both modes.
  Splitting also keeps each leaf a statement a lawyer can read against the source.
- **A Boolean input is its bare identifier (R5).**
  `dp_flag` has no result when the data point is missing, so the node is `undefined`; `dp_flag = true` is `false`.
  The specification's example files use the second form twelve times in forty-nine **[E]**, so a file written from them does not have the missing-fact behaviour RUML 5.0 describes.
- **`=`, `<>` and membership are guarded (R5).**
  `$exists(dp_a) ? dp_a = 5` has no result when `dp_a` is missing and `true` or `false` otherwise **[E, §2.4]**.
  The ordering comparisons need no guard.
- **Negation is a node (R5).**
  `$not(x)` would also work and propagates a missing value **[E]**, but a negated leaf is harder to read against the source than a `NOT_AND` parent over a positive one.
- **Numbers (R6).**
  `+`, `-`, `*` and the comparisons only, with `RUML-NUM` reported when a literal or an intermediate result is not an integer.
  Division is refused rather than reported, because the divide-by-zero behaviour differs in kind (§2.4) and I8 forbids lowering a guard idiom to a strict target.
  Rounding, `MOD` and exponentiation are out because JSONata's and L4's definitions would have to be proved to agree first.
- **Dates (R6).**
  `YYYY-MM-DD` strings compare correctly as strings **[E, §2.4]**, so the six comparisons between two date inputs or a date and a literal are exported.
  Nothing is computed on a date, because date addition is neither commutative nor associative (I9).

### 4.4 Sharing

An L4 definition referenced from two or more places in one exported root becomes one node with `modular: true`, listed in each parent's `children` (RUML 6.2, MOD-01).
Two uses that expand to the same subtree after substitution are shared as well.
Everything used once is inlined, so the file reads as the tree a lawyer would draw.
RUML keeps a result per path for a shared node and says the evaluation result "**MAY**, however, differ per reference location" (RUML 6.3).
In an exported file the status of a shared node is the same at every path where it is evaluated, because every leaf reads the one input document and an aggregate depends only on its children; in `optimized` mode it may be `ignored` at a path whose ancestor short-circuited, and evaluated at another **[U, derived from RUML 4.8, 3.6 and 5.0]**; the differential of §8 tests it.
Recursion is refused (R7): RUML allows a modular node to contain itself safely only under `XOR` or `NOT_XOR`, with the self-reference not first and a non-recursive child (RUML 6.4, MOD-03 to MOD-05), and an L4 recursive decision is none of those.
The 2026-09-09 memo's reading of RUML as "OUT by design — tree only, no sharing" (its §D) was wrong once RUML 6 was published, and its fidelity note about duplicating a `WHERE`-bound local no longer applies to a Boolean one.

### 4.5 Names and identifiers (R8)

- **Data points.**
  Each input gets the identifier `dp_` plus a slug of its L4 name: Unicode folded to ASCII as in DMN R3 and I5, lower-cased, runs of anything outside `[a-z0-9]` collapsed to `_`; a collision gets a numeric suffix.
  RUML requires `[a-z_][a-z0-9_]*` (DP-02).
  The `dp_` prefix also puts every identifier clear of JSONata's reserved words (`and`, `or`, `in`, `true`, `false`, `null`, `function`), which the leaves reference bare; I5 asks every bridge to probe the target's reserved namespace, and this is the whole of it for RUML **[U]**.
  The L4 name, as written, is the data point's `name`; `@desc`, if present, is its `description`.
- **Nodes.**
  `label` is the L4 name of the definition; for an unnamed sub-expression, its source text, cut at 120 characters.
  A label may not be empty (NODE-09).
- **UUIDs.**
  RUML requires a lowercase UUID v4 (FMT-10) and 2.5 says "randomly generated".
  The exporter derives them: the first 16 bytes of SHA-256 over the module path, the decision name and a node key, with the version and variant bits set, the parts separated by a NUL byte; the node key is `name:` and the definition's name for a named definition, otherwise `path:` and the child indices from the nearest named ancestor (`1`, `2.1`), and `document` for `metadata.id`.
  So a node keeps its UUID while its definition keeps its name, or, for an unnamed sub-expression, its place under that name; an edit that moves an unnamed sub-expression changes its UUID, and RUML's "SHOULD keep a node's `id` unchanged" (RUML 4.15) can only be kept as far as L4 has an identity to keep.
  The result has the shape FMT-10 checks and is reproducible, so goldens do not move and a re-export keeps node identity where the L4 name or position is unchanged, which `ruml:tree-reference` depends on across versions (RUML 4.15, "Stable Node Identity").
  This departs from the word "randomly" and is listed for Meng in §10.

### 4.6 Metadata and capabilities (R9)

`metadata.id` is derived as above; `version` is `1.0.0` unless `--doc-version` is given; `created` and `modified` are the wall clock, or the value of `--fixed-now` as `l4 run` takes it, so goldens can pin it; `status` is `draft`, which carries no further requirements (RUML 3.3.3); `title` is the decision's name; `language` comes from `@lang`.
No `authors` is written.
The exporter declares `ruml:datapoints` and `ruml:query` with `required: true`: a consumer that does not implement `ruml:query` would otherwise read every leaf as undecided and say nothing (RUML 4.1: "Silently discarding extension data would lead to seemingly correct but incomplete processing", which is the point of `required`).
It declares nothing it does not use.
The output is a plain `.ruml`.
A `.rumlc` container (RFC 8785 canonical form, SHA3-256, signatures) is a Phase 3 option, because a bare file is allowed to have no integrity protection (RUML 2.4).

### 4.7 A worked example, measured

`fee-waiver.l4`:

```l4
@export
GIVEN `income`                       IS A NUMBER
      `age`                          IS A NUMBER
      `receives disability benefit`  IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `fee waiver applies` IS
       `income` < 30000
   AND (   `age` >= 65
        OR `receives disability benefit` )
```

The file below is what the rules above produce, written by hand and not by a tool, because no exporter exists.
It was checked in four ways on 2026-11-26 **[E]**:
it validates against `schemas/ruml.schema.json` at the pinned commit with Ajv 8.20.0 (draft 2020-12), and the same script rejects `reject-wrong-format-discriminator.ruml` from the suite, as a negative control;
`l4 run` accepts four `#ASSERT`s on the L4 source;
and a 24-vector grid (four incomes, three ages, both values of the flag) evaluated by `l4 run` and by a 60-line evaluator of my reading of RUML 3.6, 4.8, 4.14 and 5.0, with JSONata 2.2.0 for the leaves, agreed on every vector, under `complete` and under `optimized` mode, with ten true results out of 24 in each.
That evaluator had first passed all 103 of the suite's evaluation tests, so the agreement is not only the mapping agreeing with my reading of RUML.
With a fact missing the same evaluator gives what strong Kleene gives: with no `dp_income` and `dp_age` 70 the root is `undefined`, and with `dp_income` 50000 and nothing else it is `false`, in both modes.

```json
{
  "$format": "RUML",
  "$specVersion": "1.0",
  "capabilities": [
    {
      "id": "ruml:datapoints",
      "required": true,
      "payload": {
        "data": {
          "dp_income": {
            "name": "income",
            "type": "number",
            "binding": { "type": "input" }
          },
          "dp_age": {
            "name": "age",
            "type": "number",
            "binding": { "type": "input" }
          },
          "dp_receives_disability_benefit": {
            "name": "receives disability benefit",
            "type": "boolean",
            "binding": { "type": "input" }
          }
        }
      }
    },
    { "id": "ruml:query", "required": true }
  ],
  "metadata": {
    "id": "f01ae262-dfed-46ce-8c5a-98b8e2a25955",
    "version": "1.0.0",
    "created": "2026-11-26T00:00:00Z",
    "modified": "2026-11-26T00:00:00Z",
    "status": "draft",
    "title": "fee waiver applies"
  },
  "rulemap": {
    "nodes": {
      "1": {
        "id": "dac2d07a-26b5-451d-8eae-80097c98a3d2",
        "operator": "AND",
        "label": "fee waiver applies",
        "children": ["2", "3"]
      },
      "2": {
        "id": "681ed5c6-98eb-4c06-b09d-e61506fa73d5",
        "label": "income < 30000",
        "capabilities": [
          {
            "id": "ruml:query",
            "payload": { "expression": "dp_income < 30000" }
          }
        ]
      },
      "3": {
        "id": "96182b7e-db72-42aa-a9cd-52349555a558",
        "operator": "OR",
        "label": "age >= 65 OR receives disability benefit",
        "children": ["4", "5"]
      },
      "4": {
        "id": "43419edf-bb28-4adc-aa17-b05043738a11",
        "label": "age >= 65",
        "capabilities": [
          { "id": "ruml:query", "payload": { "expression": "dp_age >= 65" } }
        ]
      },
      "5": {
        "id": "30ae5cd8-b7fa-49a5-b8b1-6b26d2ad8a9c",
        "label": "receives disability benefit",
        "capabilities": [
          {
            "id": "ruml:query",
            "payload": { "expression": "dp_receives_disability_benefit" }
          }
        ]
      }
    }
  }
}
```

The UUIDs were derived as R8 describes: `sha256("fee-waiver.l4\0fee waiver applies\0<key>")`, with `<key>` `document`, `name:fee waiver applies`, `path:1`, `path:2`, `path:2.1` and `path:2.2`.

### 4.8 The round-trip guarantee that is possible (R10)

| claim | text                                                                                                                                                                                                                                    | tier (I3)           | when it can be made                                               |
| ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------- | ----------------------------------------------------------------- |
| G1    | Every emitted file passes the JSON Schema and every rule of RUML Chapter 8 whose layer is `schema` or `semantic`, as written (`draft`) and with `status` set to `review`, since a draft is excused three rules (OP-07, NODE-07, OP-02). | executed round-trip | Phase 1, by the harness of §8, when a public validator is present |
| G2    | For every input vector in the test population, with every input supplied, the root's status in `complete` mode equals L4's value.                                                                                                       | executed round-trip | Phase 1, with the differential of §8                              |
| G3    | `export ∘ import ∘ export = export`, byte for byte, on every file the exporter emits.                                                                                                                                                   | executed round-trip | Phase 2, when the importer exists                                 |
| G4    | The importer refuses what it cannot represent, by name, and never reads an unsupported thing as something else.                                                                                                                         | golden              | Phase 2                                                           |

Not claimed, on purpose:

- **Agreement with a missing input.**
  It needs a three-valued evaluator reachable from `l4 run`, which UNKNOWN-EVALUATION-SPEC steps 4 to 7 would provide and which are parked (§3).
  Until then R5's guards are designed to agree with strong Kleene and are unproved.
- **Import then export is not the identity.**
  A RUML file read into L4 comes back with its own identifiers: `dp_income` named "Annual income" returns as `dp_annual_income`, node UUIDs change unless identity is carried (§5.4, §10 decision M2), and `XOR`, actions and AI leaves do not survive (§5).
  Nor is the document id an identity across a trip through the one producer we could run: it kept our node UUIDs, labels and data point ids, and put its own `metadata.id` where ours was (§2.8).
  RUML 4.15 lets a tool hold working anchors that name a target file by its `metadata.id`, but only in its working state: an exchanged file must carry node anchors to a published version.
  So a working link of ours that named the file by the old `metadata.id` would not be expected to resolve after such a trip **[U]**, while a node UUID would.
- **Agreement with any third-party evaluator.**
  No public evaluator was found (§2.5), and the differential uses our reading of RUML 3.6.
- **Legal meaning.**
  The labels are L4's, and the text is not the statute's.

## 5. Import: RUML to L4

The importer is Phase 2.
It exists to let a rulemap authored in a RUML tool be checked, proved and run by L4's engines, and its design is shaped by what 1.0.0 leaves undefined.

### 5.1 Node kinds

| RUML                                            | L4                                                                                                                                                                                                                                                                                                                                                                                                                                                     | what is lost                                                    |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------- |
| parent `AND`, `OR`, in child order              | `AND` or `OR` over the children, as a layout a lawyer can read                                                                                                                                                                                                                                                                                                                                                                                         | nothing                                                         |
| parent `NOT_AND`, `NOT_OR`                      | `NOT (…)`                                                                                                                                                                                                                                                                                                                                                                                                                                              | nothing                                                         |
| parent `XOR`, `NOT_XOR`                         | `OR`, or `NOT (… OR …)`, with an `Advisory` note: the children are promised to be exclusive and L4 does not check it                                                                                                                                                                                                                                                                                                                                   | the promise; `optimized` mode's early exit on `undefined`       |
| `DELEGATED` with `ruml:expression`              | a recognised threshold pattern (`$count($children[status = 'true']) >= n`, `<=`, `=`, simple majority) becomes `count (filter (GIVEN x YIELD x) (LIST …)) >= n`; any other expression is refused                                                                                                                                                                                                                                                       | the pattern's wording; `description`, kept as a comment         |
| leaf with `ruml:query`                          | the expression, if in the subset of §5.2, with the data points as `GIVEN` parameters                                                                                                                                                                                                                                                                                                                                                                   | an expression outside the subset is refused, by name            |
| leaf with `ruml:ai-query`                       | a `GIVEN` Boolean input named after the node; the prompt, model name and `inputs` kept as a comment; a `Blocking` note                                                                                                                                                                                                                                                                                                                                 | the model's decision becomes an input the caller supplies       |
| leaf with `ruml:tree-include`                   | a `GIVEN` Boolean input named after the node, with the included URI in a comment; a `Blocking` note                                                                                                                                                                                                                                                                                                                                                    | the included subtree, whose inputs 1.0.0 does not define (§2.5) |
| a leaf with more than one `decision` capability | refused; the `decisionMode` combination (`fallback`, `agreement`, `majority`) has no L4 reading without three-valued evaluation                                                                                                                                                                                                                                                                                                                        | everything                                                      |
| a leaf with no `decision` capability            | refused, by name and by node **[D]**: the prose of 1.0.0 says nothing about such a leaf, and its one executable example gives it the status `undefined` with the reason "neither children nor a decision capability" (`spec/en/02-file-format-basics/2-2-file-structure.examples/single-rule.ruml-result`); importing it as a `GIVEN` Boolean input, as the two rows above do for AI and include leaves, would let the caller decide an outline (§5.5) | everything: an outline is not a decision (§5.5)                 |
| modular node                                    | a nullary `DECIDE`, called from each parent                                                                                                                                                                                                                                                                                                                                                                                                            | the per-path result bookkeeping                                 |
| recursive modular node                          | refused in Phase 2                                                                                                                                                                                                                                                                                                                                                                                                                                     | everything                                                      |
| `ruml:actions`                                  | dropped, reported as a `Lossy` note naming the operation and `ref`                                                                                                                                                                                                                                                                                                                                                                                     | the reaction                                                    |
| `ruml:text-reference`, `ruml:tree-reference`    | `@ref` annotations naming the title and URI; no text is copied into the L4 file                                                                                                                                                                                                                                                                                                                                                                        | the embedded text                                               |
| `ruml:context`, `ruml:protocol`                 | dropped, reported                                                                                                                                                                                                                                                                                                                                                                                                                                      | the supporting material; the run directive                      |
| `$format: "RUML-EXT"` sidecar                   | merged by the rules of RUML 4.5 and CAP-24 to CAP-27, or refused                                                                                                                                                                                                                                                                                                                                                                                       |                                                                 |
| unknown capability with `required: true`        | the file is rejected (CAP-01); with `required: false` it is ignored with a warning (CAP-02)                                                                                                                                                                                                                                                                                                                                                            | nothing is silently kept                                        |
| `.rumlc` container                              | Phase 3                                                                                                                                                                                                                                                                                                                                                                                                                                                |                                                                 |

The importer is a parser in RUML's sense, so it has to implement CAP-01 and FMT-09.
RUML 1.4 also makes a conformant parser process a `.rumlc` container when one is presented, and defines no conformance levels, so it should not call itself a RUML parser until it passes the suite's validation tests and reads containers; "imports a stated subset of RUML" is accurate sooner (§2.1).
The exporter's role is the producer's (RUML 1.4): it produces only conformant files, sets `$specVersion` to the version it targets, never emits `undefined` outside a draft, and declares every capability it uses.

### 5.2 The JSONata subset

The subset is the one whose meaning is the same in JSONata and in L4, decided by the types of the data points; an expression outside it is refused by name and not approximated.

- Literals; data point identifiers and dotted paths into object data points; parentheses.
- `+`, `-`, `*`; the six comparisons; `$not`; `$exists` as a guard `$exists(x) ? e` (read as "unknown if missing", which L4 can only carry once it has a third value, so in Phase 2 it is imported only when the data point is a required input); `in` over a literal array.
- Conjunction and disjunction inside one leaf are accepted only when both operands are Boolean data points or comparisons, since JSONata coerces anything else.
- Typed by the data point's `type`: `number`, `integer`, `currency`, `percentage` and `count` as numbers; `string`, `enum`, `email` and the identifier-like types as strings; `boolean`; `date` compared as a string and never computed.
  `datetime` and `duration` are refused: a `datetime` carries an offset and compares wrongly as a string (`"2024-01-01T23:00:00+08:00" < "2024-01-01T16:00:00Z"` is `false` in JSONata 2.2.0, where `$toMillis` order says `true` **[E]**), and a `duration` is an ISO 8601 string.
- Refused: `$lookup` and every other function, lambdas, `$map` and `$filter`, regular expressions, `$eval`, `$now`, `$random`, `$millis`, `/` and `%`, ranges, and any expression whose result is not Boolean on a present input (the suite's `$lookup` idiom, which yields no result for an unrecognised answer, is the commonest, and is refused for that reason).
- Never silently approximated: an expression the importer cannot type is an error, as an ill-typed one is in JSONata at run time (T2009, T2010).

### 5.3 Inclusion across files

`ruml:tree-include` cannot be imported faithfully while its inputs are undefined (RUML 4.16).
Phase 2 imports it as an input and says so.
If a later RUML version defines the binding, the importer can resolve the URI against a container's bundled files (RUML 4.15, "Bundling for Export") and call the other module's root; the exporter then has a defined thing to write for an `IMPORT`.
This is the first place the connector will have to follow RUML's next minor version.

### 5.4 What the generated L4 looks like

For a lawyer the generated file is the L4 they would have written, with the RUML identity in comments, as this file for the worked example of §4.7, which `l4 run` accepts **[E]**:

```l4
-- Imported by `l4 import ruml` from the rulemap "fee waiver applies"
-- (RUML 1.0, metadata.id f01ae262-dfed-46ce-8c5a-98b8e2a25955, version 1.0.0, status draft).
-- Imported: 5 nodes, 3 data points.  Refused: none.  Fidelity notes: none.
IMPORT prelude

@export
GIVEN `income`                       IS A NUMBER   -- dp_income
      `age`                          IS A NUMBER   -- dp_age
      `receives disability benefit`  IS A BOOLEAN  -- dp_receives_disability_benefit
GIVETH A BOOLEAN
DECIDE `fee waiver applies` IS                      -- node 1: AND
       `income` < 30000                             -- node 2
   AND (   `age` >= 65                              -- node 3: OR; node 4
        OR `receives disability benefit` )          -- node 5
```

Names come from the data point's `name` and the node's `label`, never from the identifier, and a German label stays German.
Comments carry the RUML identifiers, because the L4 parser does not preserve a comment and a re-export therefore cannot read them back.
Making round trips keep identity needs either a new annotation (`@ruml …`, which this lexer would warn about and ignore until it is added) or a sidecar file; both are language-surface or format decisions, so they are Meng's (§10, M2).

### 5.5 Reading what Rulemapping's own tool writes (R13)

Measured on 2026-11-28 on the files of §2.8.
Each paragraph says which part is a measurement and which is a choice.

- **A leaf with an operator, outside a draft (R13).**
  The suite's test `operator--rejects-operator-on-leaf` expects a reader to reject exactly this file shape, and §5.1 says the importer may not call itself a parser until it passes the suite's validation tests; so the importer is strict: it rejects the file, names `NODE-07` and lists every node it found the operator on **[D]**.
  An opt-in lenient reading is designed here and not recommended until a file needs it.
  It would remove the operator of every childless node, report each removal as `Advisory` (naming the node and the operator), and then validate the result in full; the flag's name is not decided (§11).
  Removing and then validating is deliberate: the schema reports one error for the whole file besides the 26 on the nodes, so filtering `NODE-07` out of a list of errors cannot show that no other defect of a non-draft file is left, and a plain "ignore" would also forgive `OP-07` and `OP-02` on a leaf.
  With the operator removed from each childless node of the Act and `status` still `inForce`, the file validates with no error **[E]**.
  Removal is the reading RUML itself gives a draft ("an evaluator ignores it", 3.5.2a), so the lenient reading gives the file the meaning it would have had as a draft; no result can depend on a childless node's operator **[U, derived from 3.5.2a]**.
  The importer never rewrites the file's `status`.
  Why it is not recommended yet: on the one file seen it changes nothing, because every leaf of the Act has no decision capability and §5.1 refuses the file with the operators removed as well.
  The mode matters only to a file that is not a draft, has operators on its leaves and has leaves that decide; none has been seen, and the file of ours that went through the tool was a draft and came back with no operator on any leaf **[E]**.
  The cost is a second mode to test and document, and a reader that forgives one producer's habit may be asked to forgive the next's.
  The case against: the producer is the format's owner, so the habit may recur in files that do decide; the answer is that the opt-in can be added when such a file appears, and that refusing by default is what the suite requires and what keeps "imports a stated subset of RUML" accurate (§5.1).
- **A leaf with no decision capability.**
  Every leaf of the Act is one (§2.8), and so is the single node of the suite's own law fixture (`accept-law-text-as-ruml-text.ruml`, `inForce`, `documentType: "law"`), so the shape is ordinary and not one producer's habit **[E]**.
  §5.1 refuses it by name and by node **[D]**: the prose of 1.0.0 is silent, its one executable example gives such a leaf the status `undefined`, and the alternative, a `GIVEN` Boolean input as for AI and include leaves, would let the caller decide an outline.
  Reading such an outline as the structure of a document is a different feature from reading a decision, and is not proposed here (§11).
- **Fields the tool writes.**
  `decisionMode: "fallback"` on every node (parents included), `description: ""` on every node, `sensitive: false` on every data point, `isReferenced` on a text entry, and the uploaded file's name in `metadata.description` are optional fields the schema accepts; `timestamp` on a text entry is required (`TXT-04`) and present.
  The files that carry them validate, apart from the one `NODE-07` defect **[E]**.
  Which of them the tool adds and which it would write anyway is not known: the statute was never uploaded to it, so there is no uploaded version to compare **[U]**.
  The importer does not read `decisionMode`, because the only leaf it applies to, one with more than one decision capability, is refused (§5.1); it does not carry an empty `description`; and it carries `sensitive: true`, which has no L4 reading, as a comment on the `GIVEN` **[D]**.
- **Size.**
  An embedded text is most of the file: the Act's `capabilities` array, which holds the text in its Akoma Ntoso JSON form, is 82.1 % of the file, and the file is 1,834 bytes per node (§2.8).
  If that scaled with the number of nodes, the Civil Code's 6,657 nodes would come to about 12 MB; that is a guess and not a measurement **[U]**.
  The importer treats a `ruml:text-reference` entry as data it does not interpret and never copies its text into the L4 file (§5.1).
  RUML 4.12 says a parser SHOULD verify the digest before relying on the text, and the importer never relies on the text (§5.1), so it need not.
  A short routine of ours reproduced the producer's digest on the Act; the text entry holds no JSON numbers, so the number serialisation, the delicate part of RFC 8785, was not exercised **[E]**.
  Each public parser ships a digest helper (`ruml_parser/text.py:119`, `ruml-js/src/text/digest.ts:24`) that only its own tests call (no validator does), which under R2 could cross-check a Haskell routine if one is ever written **[E, grep of both sources for callers]**.
- **Identity and version.**
  The tool put its own `metadata.id` where ours was and kept node UUIDs (§2.8, §4.8); whether it does so on upload or on export is not known **[U]**, so a reader must not take `metadata.id` as the identity of a rulemap across a trip through it.
  The Act's `metadata.version` is the statute's version date, the form RUML 3.3 asks of a file with `documentType: "law"`, and the file has no `documentType`.
  The schema types `version` as a string, so the importer does not parse it **[E for the facts, D for the rule]**.

## 6. Approaches, compared

Three approaches were asked for, plus one more that falls out.

| approach                                                         | what it is                                                                                           | what it costs                                                                                                                                                      | how it stays in step with RUML versions                                                                                                                                                            | licence it implies                                                                                                                     |
| ---------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| **(a)** native Haskell writer and reader over the JSON Schema    | `L4.Ruml.{IR,Lower,Emit}` and, later, `{Parse,Jsonata,Lift}`, with `aeson`                           | writer about 2,000 lines, reader about 3,500 (§9); a hand-written JSONata subset parser for import; no new runtime dependency                                      | We read RUML 1.x and write `$specVersion: "1.0"`. A new minor needs a code change before we accept it, because FMT-09 says reject a higher minor. The schemas and suite are re-pinned per version. | none: "producing, processing or exchanging RUML files requires no license" (RUML front matter)                                         |
| **(b)** reuse their public parser as a sidecar or in `ts-shared` | call `ruml-js` or `ruml-python` for validation and modelling, from `l4` or from a TypeScript package | a Node or Python runtime on the user's machine; a process boundary; error-mapping from their messages to ours; the Haskell side still needs its own emitter for L4 | Their release cadence, which is theirs: the repositories are two weeks old with one commit each; a pinned version stays correct for 1.0 files                                                      | Apache-2.0, permissive, patent grant; forking or vendoring is allowed; the name RUML is a trademark that does not travel with the code |
| **(c)** export only, first                                       | (a), writer only, then stop                                                                          | the smallest: no JSONata parser is needed to print leaves, and the harness validates the output                                                                    | Same as (a) for the writer                                                                                                                                                                         | same as (a)                                                                                                                            |
| (d) go through DMN                                               | export DMN and convert to RUML elsewhere                                                             | not an approach: no converter exists, and DMN decision tables are not trees                                                                                        |                                                                                                                                                                                                    |                                                                                                                                        |

**Where the ts-shared option would sit.**
`ts-shared/` holds TypeScript packages (`boolean-analysis`, `ladder-core`, `l4-ladder-visualizer`, `jl4-client-rpc` and others) for the ladder visualiser and the editor client, not a code path of the `l4` command.
Putting a RUML parser there serves a browser view and not `l4 export` or `l4 import`, which are Haskell (I1).
That is a different feature, and it would not change the recommendation.

**Is depending on a third party's parser wise, for a format whose owner also competes with us (R2)?**
The Pitch deep dive's reading is that Rulemapping is a competitor for the channel to drafting offices and a candidate import and export target **[E, `deep-dives/30-rulemapping-and-ruml.md` §1]**.
On the product path, a dependency would give that owner four things it need not mean to use, and which we cannot yet price: the pace of our RUML support, the shape of our error messages, the install burden of a second runtime, and a package namespace they control and have already moved once between registries (§2.5).
The mitigations are real, since Apache-2.0 lets us fork and RUML 2.3 promises backward compatibility within a major version, but they do not make the case for it, because (a) costs little more than (b) would: the format is small, the schema is public, the rules are numbered, and the suite is data.
In a test harness the same parsers are a gain without the risk: a second implementation checking our output, run when present, skipped when absent, never a build input (I4).
So R2: use them as validators, pinned by version, and write the product path ourselves.

**What each costs if it goes wrong.**
(a) risks us misreading the format, which the suite and the validators exist to catch.
(b) risks a process we cannot fix, owned by someone with other priorities.
(c) risks nothing that (a) does not, and delays the importer until the exporter has shown it is wanted.

## 7. Conformance (R11)

The suite is data under `tests/` in the RUML repository (§2.6), and is Apache-2.0, so using it is free.
Putting a copy in our public repository would be a deposit of third-party text, which needs Meng's word (decision M4), and §2.6 found German statute text in it with no stated provenance; so the harness fetches it and a commit holds only pins.

**Mechanism.**
`etc/validate-ruml.mjs`, in the posture of `etc/validate-dmn.mjs`: it runs when Node is present and a copy of the suite can be had, and is otherwise silent, so it is never a required CI step (I4).
It takes the suite from one of two places: a checkout named by `RUML_CONFORMANCE_DIR`, or a fresh `git clone` of `https://github.com/Law-as-Code-Institute/ruml` into a scratch directory.
Either way the harness checks out the pinned commit `957ad4b730a91ba770fdad00de37269523f81452` and then compares `git rev-parse <commit>:tests` and `<commit>:schemas` with the two pinned tree ids, `1764e029f2b1d0a2f472e3a3e40fa49b04d54e04` and `6f26a89e83ffae34b80f8199b72345c143f233e8` **[E, computed 2026-11-26]**.
A git tree id names its content, so a mismatch means the files are not the pinned ones, and the harness stops.
Nothing else is committed: no manifest of file names or hashes is needed.
The ZIP at `ruml.org/spec-tests.zip` has no version in its address and is not used.

**What it checks, per phase.**

- Phase 0.
  Every validation test whose `layer` is `schema` is run against the schema with a standard JSON Schema 2020-12 validator, and its `accept` or `reject` outcome must match, so the harness is calibrated before it judges our output.
  The pipeline of §4.7 already does this for one accept and one reject case **[E]**.
- Phase 1.
  The harness's own evaluator of RUML 3.6 and 5.0 (§8, item 2) runs all 103 evaluation tests, evaluating each leaf with JSONata 2.2.0 and each assertion as a JSONata query over the result, as `tests/schema/spec-test.schema.json` describes; all 103 must pass before the evaluator is allowed to judge an export.
  Then every file the exporter emits is validated against the schema, and by the public parsers when they are present.
- Phase 2.
  Every validation test, the semantic ones included, is run against our importer's reader, with the rule ids a test names compared where the reader reports them (the contract lets a runner skip them).
  The evaluation tests are not run against the importer: their leaves use a function outside §5.2's subset, so the importer has nothing to say about them, and the list is printed as out of subset and never skipped silently.
- Each RUML minor version is a re-pin: a new commit, two new tree ids, and the tests that moved read by a person.

## 8. Checking the semantics

There is no RUML evaluator to compare against: the two public parsers do not evaluate (§2.7), and the specification defines no algorithm (§2.5).
Four of our own engines can stand in, in this order of strength:

1. **`l4 run` and `#ASSERT`s as the oracle (I2).**
   The exporter's differential takes every `#EVAL` and `#ASSERT` of an exported module, and a generated grid of input vectors, evaluates each in L4, and compares with the root's status under RUML `complete` mode.
   This is the 24-vector measurement of §4.7, made a test.
2. **A reference evaluator of RUML 3.6 and 5.0, in the harness.**
   About 200 lines of JavaScript in `etc/`, test-only, that applies the operators of §2.3 in both modes and evaluates each leaf with the real JSONata, so it needs no JSONata implementation of our own.
   It is calibrated first against the suite's 103 evaluation tests, so that what the differential trusts has been checked against RUML's own expected statuses.
   Without that step the differential would only compare our reading of RUML with itself, which is all the evaluator of §4.7 can claim.
3. **JSONata itself for the leaves.**
   The harness evaluates every exported leaf with the `jsonata` npm package at 2.2.0, the version RUML names, on the same grid, and compares with L4's value of the atom.
   This checks R4 to R6, the claims of §2.4, and the printer, and it does not need a RUML evaluator.
4. **Another exporter as a third witness.**
   `l4 export dmn` of the same decision, run in the KIE harness the repository already has (`etc/kie-dmn-check/`), gives a third answer on the same grid; three agreeing engines are worth more than two.

**One proof is also available, for the Boolean fragment.**
Export, import, and ask `l4 prove` whether the original and the re-imported decision are equivalent.
It proves the tree structure survived, not that RUML reads it as we do, because the importer is ours; it is the strongest cheap check on G3 and is labelled that way.

**The commands behind §2.4**, reproducible: `npm install jsonata@2.2.0 ajv@8 ajv-formats@3 --ignore-scripts` in a fresh directory, then `jsonata(expr).evaluate(doc)` for each row, and a validator built from `ajv/dist/2020` with `ajv-formats`, compiled against `schemas/ruml.schema.json`.
Both ran with no network access to RUML after the clone.

## 9. Recommendation, phases, cost

**Pick (c) inside (a): a native writer first, the reader later, with the public parsers and JSONata as test-time cross-checks.**

| phase | what lands                                                                                                                                                                                                                                                                                                                      | size **[U, calibrated on §3's measured sizes]**                                                                                                                        | gate before the next phase                                                                                                                     |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| 0     | Meng's rulings on §10. `etc/validate-ruml.mjs` with its pins, run against the suite's schema-layer accept/reject tests, with no product code.                                                                                                                                                                                   | about 150 lines of JavaScript                                                                                                                                          | the harness agrees with every `schema`-layer `expect` in the suite                                                                             |
| 1     | `l4 export ruml` for the fragment of §4.1: `L4.Ruml.{IR,Lower,Emit}`, the refusals and fidelity codes of §4.2, goldens under `jl4/examples/ruml/`, the harness evaluator calibrated on the 103 evaluation tests and the differential of §8 (1) to (3), `doc/exports/ruml.md`, a row in `doc/exports/README.md` and `SUMMARY.md` | about 2,000 lines of Haskell, the size of `L4/OpenFisca` (2,212); about 200 lines of JavaScript for the evaluator; about 600 lines of tests; a doc page (CLAUDE.md §6) | every emitted file is schema-valid and passes both public validators when present; the differential has 0 disagreements; an independent review |
| 2     | `l4 import ruml` for the subset of §5: `L4.Ruml.{Parse,Jsonata,Lift}`, G3 and G4, the importer run against the suite's validation tests in its strict default (R13; a lenient mode, if one is ever built, is tested separately and never in place of those), `l4 import ruml --parse-only` as `l4 import blawx` has it          | about 3,500 lines, the size of the Blawx importer (3,457)                                                                                                              | G3 holds on every file the exporter emits; the suite's validation tests agree; an independent review                                           |
| 3     | modular nodes both ways with computed data points for shared numeric definitions; `@ref` as `ruml:text-reference` with a URI and no embedded text; `.rumlc` containers; tree-include when RUML defines its inputs; missing-input differential when UNKNOWN-EVALUATION steps 4 to 7 land                                         | open                                                                                                                                                                   | each item has its own spec section and its own ruling                                                                                          |

**Running cost after Phase 1.**
One re-pin per RUML minor version: a new commit, two new tree ids, a read of the diff of the schemas and the suite, and a decision on whether the exporter's `$specVersion` moves.
The importer must reject a higher minor than it implements (FMT-09) and so needs a code change per minor, which is small unless the minor changes semantics.
RUML 2.3 says a minor keeps schemas and evaluation backward-compatible, so the exporter's output stays valid under later minors by the specification's own promise.

**What not to build.**
No RUML evaluator in the product, no dependency on `ruml-js` or `ruml-python`, no vendored suite, and nothing that labels L4's output "RUML-compatible" until it has passed the suite's validation tests and the harness of Phase 1.

## 10. Decisions only Meng can make

Each of these changes who is told something, what is published, or the language surface, so it is not a design choice of mine.

- **M1. Whether to build it, and where it ranks.**
  The recommendation is Phase 0 and Phase 1 only (a writer the size of the OpenFisca bridge), and to stop there until someone uses the file.
  The 2026-09-09 memo's reading was "revisit once RUML actually ships"; it has shipped, but its first public use outside the company is not yet visible.
- **M2. Whether a round trip keeps RUML's identity.**
  Options: a new `@ruml` annotation line (a language-surface change, with a lexer and a printer change), a sidecar file next to the `.l4`, or neither, and accept that an import-then-export changes every identifier and node UUID.
  Without one of the first two, a rulemap that other files reference by node UUID (RUML 4.15) cannot be maintained from L4.
- **M3. The name, and whether anyone outside is told.**
  The trademark permits "supports RUML" only where accurate (§2.1), and conformance is what makes it accurate.
  Whether L4 says "RUML export" in its docs and README, whether the two companies behind the format are told, whether the repository's two open issues are commented on, and whether the `NODE-07` finding of §2.8 is reported to them are outward actions; a draft of that report is kept and has not been sent.
  Through 2026-11-27 nothing had been sent to anyone outside these sessions in the course of this work.
  On 2026-11-28 Meng opened a free account on Rulemapping's workspace, and at his direction a copy of one published statute rulemap was imported into it and the example of §4.7 was uploaded to it (§2.8); no message was sent to any person.
- **M4. Whether third-party fixtures may be fetched, and whether any may be committed.**
  The recommendation is fetch-at-test-time, pinned by a commit id and two git tree ids, which are the only things committed (R11).
  Vendoring the suite, or quoting its fixtures in our goldens, is a first deposit of third-party text into a public repository and needs Meng's word.
  Whether a CI job may use the network for this, as opposed to a developer's machine, is also his.
- **M5. Whether a competitor's parsers may be used at all, even to check our output.**
  The recommendation is yes, as pinned test-time validators.
  If the answer is no, G1 weakens to "valid against the JSON Schema", which a standard validator gives without their code.
- **M6. Deterministic UUIDs.**
  R8 derives node and document UUIDs from a hash, shaped as version 4.
  The format's text says "randomly generated" and its pattern accepts the derived form; reproducible output and stable node identity are the reason.
- **M7. Whether `l4 import ruml` should ever have a lenient mode (R13).**
  R13 proposes a strict importer, with an opt-in reading designed and not built until a file needs it: a file that is not a draft, has operators on its leaves and has leaves that decide.
  None has been seen, and on the one statute file we have the mode would change nothing, because §5.1 refuses that file's leaves anyway (§5.5).
  Adding it later adds a command-line flag a user will see and a second behaviour to document, so it is a product choice and not only a design one.
  The alternative is to build it with Phase 2, at the cost of a second mode to test for a case not yet observed.

## 11. Risks and what is not decided

- **The semantics of a missing fact are the connector's weakest point.**
  R5's guards are designed to agree with L4's strong Kleene where an input is missing, and that agreement cannot be tested until `l4 run` can evaluate with unknowns.
  Until then a RUML file from the exporter is exact on fully supplied inputs and untested otherwise, and G2 says so.
- **A file cannot say which evaluation mode it needs.**
  The exporter writes `complete`-correct files, and a consumer that evaluates in `optimized` mode with a missing input can get a different status for the same file (O3).
  RUML's open issue 2 is the same point; whether RUML resolves it is theirs.
- **The format is two weeks old.**
  The two parsers have one commit each and the format repository two; a 1.0.1 or 1.1 may move things.
  The mitigation is the pin.
- **The one producer breaks the format's own rule, and its files are large.**
  Rulemapping's tool wrote a statute file that fails `NODE-07` and, in the same file, 82 % embedded text in its Akoma Ntoso JSON form (§2.8).
  A strict importer refuses that file, and would refuse it for its leaves in any case (§5.1); a lenient one forgives a defect that its authors may fix in the next release, after which the lenient mode is dead weight (R13, M7).
  We have one producer, one statute and one round trip of a five-node file, so none of this says how the tool behaves on `XOR`, `DELEGATED`, modular nodes or AI leaves.
- **Numbers.**
  `RUML-NUM` is an advisory and not a guarantee; a rule of statute written with decimal rates is where it bites, and Phase 1 should say so in the doc page.
- **Labels are not the law.**
  RUML's `label` and `altText` are meant to carry statutory wording; the exporter writes L4's names and source text.
- **Not decided here.**
  The fidelity-report format on the command line (the shared one is a text report); whether `--fail-on` exists for this exporter; the exact slug rules for non-Latin names; the 120-character cut for labels; how `@ref-map` URIs become `uri` values of a text reference; whether to write `ruml:protocol`; the name of the lenient flag of R13; and whether a statute outline (a tree whose leaves have no `decision` capability) should be readable as a document of structure at all, which §5.5 does not propose.

## 12. What review changed

An independent reviewer (a fresh Opus agent, told that "stands" is a legitimate verdict, and that its job was the claims about RUML and not the design) checked about 140 atomic claims against the pinned specification, schemas, suite and parsers, recomputing counts with its own scripts and re-running the JSONata probes.
About 115 stood, including every count of §2.2 and §2.6, the whole probe table of §2.4, the licence and versioning rows, the registry and ZIP facts and the git tree ids; it also re-ran the 103-test and 90-test calibrations and reproduced them.
It found two wrong statements, nine overstated ones, two unsupported ones and about a dozen wording nits, all fixed above:

- **Wrong, fixed.**
  The §4.3 sentence on JSONata's `and` against the tree compared two cases no single input makes true; it now gives one input and both modes.
  §5.2 listed `duration` as a number; it is an ISO 8601 string, and `datetime` is now refused too, because it carries an offset and compares wrongly as a string (measured).
- **Overstated, fixed.**
  The parsers' rule lists were incomplete (TypeScript also checks CAP-01 for draft and reverse-domain ids, META-11 and node-level CTX-10 and TXT-19; Python also checks CAP-04 and the model-query halves of CTX-10 and TXT-19), which mattered because the document leans on CAP-01.
  "No test touches a tool-layer rule" now says that OP-03 is exercised without being named; the `frozenClock` and `evaluationId` clause is no longer listed as a disagreement, because the contract makes them conditional; a shared node's status is "equal where evaluated", since in `optimized` mode it can be `ignored` at some paths; the "same kind" description of the example expressions now names the exceptions (decimal arithmetic in a computed data point, `and` and `or` in two combiners); O4 now says "when every leaf yields true or false"; the deontic row lists RUML's time-related features; CAP-28 describes a validation tool and not a reference implementation; the quantifier row no longer says RUML has no counterpart at all.
- **Unsupported, fixed.**
  The "public claim" of 22 descriptors and 97 fixtures is now attributed to the Pitch deep dive, since no RUML page states it; `defaultValue` is marked as not stated by the specification.
- **Missing, added.**
  `ruml-python` cannot read a computed data point; an `ignored` child does not count in its parent (O5); `status: draft` excuses three rules, so G1 is also run at `review`; RUML 1.4's conformance roles (producer for the exporter, and a parser must process containers); the specification disagrees with itself on whether a rejection must report rule ids; the descriptor schema carries leftovers of the contract's earlier design; `DELEGATED` in `complete` mode is untested.
- **Evidence.**
  "No public evaluator" is now "none found" in a stated scope.
- **On the L4 side.**
  The citation of U1 now covers `:1249-1252`; and R8's UUID derivation did not reproduce the example's identifiers, because the example had used the LexID where the text said the node's path.
  The rule is now stated by node key (name, or child indices under the nearest named ancestor), and the example's identifiers were regenerated by that rule, the file re-validated against the schema and the 24-vector grid re-run (0 disagreements).
  Stating the rule exposed a real limit, added to §4.5: an edit that moves an unnamed sub-expression changes its UUID.

Not changed, with the reason: the reviewer's note that `ruml-js` compares timestamps as strings (META-03, META-09) is a defect in a third party's code that this document does not rely on, so it is reported in the evidence and not acted on; and the claim that `complete` mode agrees with L4's strong Kleene reading is kept marked **[U]**, since today's evaluator is stuck on an unsupplied fact and the agreement is with the specification's target semantics (§2.3, O4).

### The amendment of 2026-11-28

What it changed, from the files of the one producer we could run (§2.8):

- **Added.**
  §2.8 (what the tool offers, the statute file, its `NODE-07` failure, the lossy XML, our file's round trip); R13, §5.5 and M7 (the importer's reading of a leaf operator outside a draft and of the tool's other habits); a row in §5.1 for a leaf with no `decision` capability; a clause in the Phase 2 row of §9; a sentence each in §1, §2.5, §4.8 and §11.
- **Corrected.**
  The sentence of M3 that nothing had been sent outside these sessions was true only through 2026-11-27; it now says what happened on the 28th.
  The header said the file was written on a branch; it now also says it reached `unstable` and when it was amended.
- **Not changed.**
  Nothing in §2.1 to §2.7, §3, §4.1 to §4.7, §6 to §8 or the rulings R1 to R12 contradicts the files; `grep` of this document for "Builder", "Workspace" and "catalog" found no earlier statement about the tool.
- **A first measurement, not a settled one.**
  One statute, one round trip and one tool version that reports none: the facts of §2.8 are what happened on 2026-11-28 and may not hold of the next release.
- **Review.**
  The author rechecked the figures of §2.8 against the files (the `TXT-09` digest was reproduced exactly, which a 256-bit hash does not do by accident); facts read off the screen are marked and could not be rechecked that way.
  An independent reviewer (a fresh Opus agent, given the amendment and the sample files but not the author's conclusions) then re-ran the checks and found four wrong statements, ten overstated or unsupported ones and about a dozen nits; each is fixed above.
  The reviewer confirmed, among others: every size and hash of §2.8, the 27 schema errors on 13 nodes, the digest reproduction under both key orders, the suite test for `NODE-07`, the XML and round-trip facts, and that no sample file is committed.
  - **Wrong, fixed.**
    R13, M7 and §11 said a lenient mode would rescue the statute files; it would not, because §5.1 refuses all 68 of their leaves anyway, and the mode now matters only to a file not seen (R13 is now "designed, not built until a file needs it").
    §5.5 listed `timestamp` among optional fields; it is required (`TXT-04`).
    §5.1 said a `grep` of the specification found no statement about a leaf with no decision; the executable example `single-rule.ruml-result` gives it the status `undefined`, and the row now cites it and marks the refusal as a choice.
    §4.8 said a node UUID is the only identity that survived a trip through the tool and that `ruml:tree-reference` assumes it; labels, LexIDs and data point ids survived too, and RUML 4.15's working anchors name a file by `metadata.id`, in a tool's working state only.
  - **Overstated or unsupported, fixed.**
    "82 % of it the embedded statute text" is now "the embedded text in its Akoma Ntoso JSON form", which is what the 82 % measures (the share that is the statute's own words was not measured); "replaced `metadata.id` on export" and "`modified` is the time of the export" are marked **[U]**; "implements" is "preserves"; "came back as uploaded" now says that member order changed; the date version is RUML 3.3's convention for a law and the file has no `documentType`; the digest paragraph says no JSON numbers were exercised and cites RUML 4.12's actual wording; the lenient reading removes the operators and then validates in full; screen-read facts and the fifth file `KSchG_1.txt` are marked; "creation order" is **[U]**; the caveat that the statute file is an export of a workspace copy is added.
  - **Nits, fixed.**
    The header lists every changed section; the dating of §5.5; the §2.5 bullet says it is a producer's defect; one anchor per node, not two; "the only schema-layer defect" now rests on the strip-the-operators run; `M4`, not `R11`, applies; `decisionMode` no longer contradicts §5.1; "imports a stated subset of RUML"; the Phase 2 row says the suite's tests run in strict mode; both parsers' tests for `NODE-07` are cited.

## Sources

**Read at source on 2026-11-26.**
`https://ruml.org/1.0.0/` (index and navigation) and the repository `github.com/Law-as-Code-Institute/ruml` at `957ad4b730a91ba770fdad00de37269523f81452` (tag `v1.0.0`) and at `d2ac818f6ed87c2bcf5b69430adf2efa8ba3c6a4`: `spec/en/` (index, 1.1, 1.3 to 1.5, 2.1 to 2.6, 3.1 to 3.8, 4.1 to 4.16, 5.0, 6.1 to 6.5, 7 headings, 8, Appendix A), `schemas/ruml.schema.json`, `tests/` (22 descriptors, 97 fixtures), `README.md`, `LICENSE.md`, `REUSE.toml`; the repositories `ruml-python` (`1a421333ba0a2b4d134054417dc418c1142916ec`) and `ruml-js` (`cb7d754b42ff53940e154ae924b7f72f7fa8b218`); the public registries `registry.npmjs.org` and `pypi.org` for the package names; `gh api` for repository, issue and release metadata.

**Measured on 2026-11-28.**
The Rulemap Builder of Rulemapping Group GmbH (`builder.rulemapping.org`) and the catalogue it serves, through a free workspace account; the pages `rulemapping.org` and `law-as-code.org`; the four files of §2.8, `KSchG.ruml`, `KSchG.xml`, `fee_waiver_applies.xml` and the round-tripped `fee-waiver.ruml`, and the tool's text outline `KSchG_1.txt` (5,115 bytes, used only to check the 88 labels), kept outside the repository with the hashes given there; `ruml.schema.json` and `tests/03-data-model/3-5-node-object.test.yaml` at the pinned commit; Ajv 8.20.0 with `ajv-formats` 3.0.1; and Node's `crypto` for SHA3-256.
The `TXT-09` check is: sort object keys, print values as `JSON.stringify` does, join without whitespace (RFC 8785 for this content), hash the UTF-8 bytes with SHA3-256, and compare with the `digest` after its `sha3-256:` prefix.

**Attribution.**
The short quotations from the RUML specification in this document are from RUML – Rulemapping Logic Format, version 1.0.0, © Rulemapping Group GmbH, published by Law as Code Institut GmbH, licensed under CC BY-SA 4.0 (`https://ruml.org/1.0.0/`).
The worked example in §4.7 is our own file and copies nothing from RUML's examples or suite.

**In this repository, at `8f10892e5`.**
The files named in §3.

**Landscape, not re-verified here.**
`legalese/l4-pitch`, branch `pitch/rulemapping-ruml`, `.claude/skills/l4-pitch/deep-dives/30-rulemapping-and-ruml.md`, read for the competitive framing and cross-checked for the repository, licence, package and rule-count facts above.

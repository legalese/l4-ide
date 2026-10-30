# dmn-check over exported DMN: optional evidence, and how to read it

`run.sh` runs [red6/dmn-check](https://github.com/red6/dmn-check) 1.4.0 over DMN files, or over the DMN that `l4 export dmn` writes for every L4 file in the corpus.
It is a third kind of evidence beside `etc/validate-dmn.mjs` (is the XML well-formed DMN 1.3, with only elements the metamodel knows?) and `etc/camunda-dmn-check` (does a Camunda 8 engine load and evaluate it?).
dmn-check reads a file's structure and never executes anything.

## What dmn-check is

Facts below were checked on 2026-10-30 against Maven Central and the 1.4.0 source jars.

- Coordinates `de.redsix:dmn-check-cli:1.4.0`. `maven-metadata.xml` at `https://repo1.maven.org/maven2/de/redsix/dmn-check/` lists 1.4.0 as both `latest` and `release` (`lastUpdated` 2026-07-15).
- Licence Apache-2.0, from the licence block of `dmn-check-1.4.0.pom`.
- Needs Java 21: the parent pom sets `<java.version>21</java.version>`, and a compiled validator class is class file version 65.
- It reads files with Camunda 7's `camunda-dmn-model` 7.24.0, so it sees DMN through Camunda 7's vocabulary.
- 21 validators, loaded by scanning the classpath (`ValidatorLoader`); the banner prints the count it loaded.
  - Rules in a decision table: `DuplicateRule`, `ConflictingRule`, `ShadowedRule`.
  - Ids and names present: `DefinitionsIdAndName`, `DecisionIdAndName`, `InputDataIdAndName`, `ItemDefinitionIdAndName`, `KnowledgeSourceIdAndName`.
  - Types: `InputTypeDeclaration` and `OutputTypeDeclaration` (a `typeRef` is present and parses), `InputEntryType` and `OutputEntryType` (entries type-check against it), `InputValuesType`, `OutputValuesType`, `ItemDefinitionAllowedValuesType`.
  - Table hygiene: `DuplicateColumnLabel`, `Aggregation`, `AggregationOutputType`.
  - The requirement graph: `ConnectedRequirementGraph`, `RequirementGraphLeaf`, `NoDecisionPresent`.

## Run it

```
etc/dmn-check/run.sh jl4/examples/dmn/expected/reg-cf.dmn [more.dmn ...]
etc/dmn-check/run.sh --corpus [ROOT ...]        # ROOT defaults to this checkout's jl4/examples
etc/dmn-check/selftest.sh                       # does the harness still do what this page says?
```

`--corpus` exports every `.l4` under the roots with `l4 export dmn` (below any `not-ok` or `tests` directory is skipped), keeps the files for which that exits 0 and writes a `<definitions>` element, and checks those.
Put your own build's `l4` first on `PATH` or set `DMN_CHECK_L4`: an `l4` older than the corpus misreads newer syntax (CLAUDE.md section 3.1).
Pin `DMN_CHECK_JAVA_HOME` to a JDK 21 if you want the result to mean what 21 gives; the banner names the JDK that ran.
The corpus run writes into `$DMN_CHECK_WORKDIR/corpus` (default `$TMPDIR/l4-dmn-check`): the exported DMN and the exporter's fidelity report beside each, `export-status.tsv`, `report.txt` and `findings.tsv`.
`summarise.sh` regroups `findings.tsv` into the table of kinds.

## Policy: optional evidence, not a gate

- Nothing in `.github/workflows/` runs this, and `etc/verify-branch.sh` does not.
  The Camunda and KIE legs are required CI gates over a closed list of committed goldens; this is not, because over the whole corpus it exits 1 today (the census below), for reasons that are mostly about dmn-check's model and not about the rules.
  `export` makes the same argument about `Blocking` fidelity notes in `jl4/app/L4/Cli/Export.hs`.
  "Optional evidence" is the contract of the row that asked for this harness; making it a gate would be a separate ruling.
- With Maven, a JDK 21+, the pinned jars (or, with `--corpus`, an `l4`) absent, it prints one line starting `skipped:` and exits 0, with no VERDICT banner.
  `DMN_CHECK_REQUIRED=1` turns that into exit 1, as `CAMUNDA_CHECK_REQUIRED` does for the sibling.
- With everything present, exit 1 if any file had an ERROR finding, could not be read, or crashed a validator.
  WARNINGs do not fail the run unless `--fail-on-warning`.
  That is dmn-check's own rule (`PluginBase.testFile`) and the Camunda leg's (errors fail).

## Loud failures and silent ones

Loud, so they teach:

- Jars that are not the pinned ones: `BROKEN`, exit 1, with the diff.
- `javac` fails on the driver: `BROKEN`, exit 1.
- A file that cannot be read, or a validator that throws: an `UNREADABLE` or `CRASH` line, counted in the banner, exit 1.
- No validators found on the classpath: `BROKEN`, exit 1.
- Pin and classpath disagree on the version: a `VERSION MISMATCH` line and exit 1.

Silent, which return a plausible answer:

- A `skipped:` line and exit 0 means nothing was checked.
  The only other sign is that there is no VERDICT banner.
- A table with an input or output whose `typeRef` dmn-check cannot parse is not entry-type-checked at all: `InputEntryTypeValidator.isApplicable` and `OutputEntryTypeValidator.isApplicable` require every declared type to parse.
  Since `number` does not parse (below), no `InputEntry` or `OutputEntry` type finding says anything about a table with a `number` input.
- A clean file means "none of these 21 validators objected", and nothing about what they skip, as above.
- `--corpus` sweeps the exporter's default flavour (Camunda 8).
  A `--flavor kie` export is not checked.

## Why a driver and not the stock CLI

`src/main/java/DmnCheckRun.java` applies dmn-check's own validators (`ValidatorLoader.getValidators`, the CLI's default set) to files read with `Dmn.readModelFromFile`, which is what `PluginBase.testFile` does.
The stock CLI (`de.redsix.dmncheck.cli.Main`) cannot answer what this harness is for:

- a file with no findings prints nothing, so "checked and clean" and "never looked at" are the same output;
- a finding does not name the validator that produced it;
- a file that cannot be read logs the exception message without the file name;
- one validator that throws aborts the rest for that file.

Cross-check, 2026-10-30, over the 487 exported files of the census below: the stock CLI printed 3866 `ERROR` and 1809 `WARN` lines across 381 files, and the driver reported 3866 errors and 1809 warnings across 381 files.
So the driver does not invent findings and does not lose them.

## The pin

`pom.xml` pins `de.redsix:dmn-check-cli` to 1.4.0, which fixes every transitive version too.
`jars.sha256` pins the SHA-256 of each of the 18 jars on the resolved classpath, and `run.sh` refuses to run on a mismatch.
Maven's own checksum check compares a jar with the checksum the same repository publishes, which catches a corrupt download and nothing else.
The four `de.redsix` jars in `jars.sha256` equal the `.sha256` files Maven Central publishes for them (compared 2026-10-30).

Bumping the pin: change `<dmncheck.version>` in `pom.xml`, delete `$DMN_CHECK_WORKDIR/cp.txt`, resolve with `mvn -f etc/dmn-check/pom.xml -Dmdep.outputFile=<absolute path>/cp.txt dependency:build-classpath`, then write `sha256  file-name` for each jar on it, sorted with `LC_ALL=C sort`, into `jars.sha256`.
Then run `selftest.sh`: its counts (21 validators, the number-type finding) are claims about 1.4.0 and will fail if they stop being true.

`run.sh` compiles the driver with `--release 21`, so the cached class loads on every JDK it accepts.
`etc/camunda-dmn-check/README.md` describes the stale-class trap that its harness has and this one does not.

## Census, 2026-10-30

Measured at `legalese/l4-ide` `unstable` `bcbec1419` with an `l4` built from that commit and its embedded prelude (`JL4_LIBRARY_PATH` unset), dmn-check 1.4.0 on JDK 21.0.12.1, root `jl4/examples`.
Re-running gave identical counts.

Export (`l4 export dmn`): 572 `.l4` files considered, 487 exported, 85 refused (81 `No decisions found in module`, 4 `Type checking failed`), none timed out.

Check: 487 read, 0 unreadable, 0 validator crashes.
106 files have no finding and 381 have at least one: 3866 errors and 1809 warnings, 5675 findings in all.

The table groups findings by validator, message and element type (`summarise.sh`).
The reading is a judgement from an example and from the dmn-check source, and the evidence is given so it can be argued with.
"False positive" means dmn-check objects to something DMN 1.3, Camunda 8 and KIE accept.
"Exporter" means the exporter writes something that is fine DMN but trips dmn-check, or reports the loss itself.
"Real" means the L4 source has the property.

| Finding                                                                                                | Count (files)        | Reading and evidence                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ------------------------------------------------------------------------------------------------------ | -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `InputDataIdAndName`: `A input has no id` (error) and `has no name` (warning)                          | 1075 + 1075 (110)    | False positive. All 1075 `<inputData>` opening tags without an `id` in the exports are `<inputData href="#..."/>` references inside a `<decisionService>` (1075 lack `id`, 1075 carry `href`), and dmn-check's reader types each as an `inputData` (the findings' element type is `inputData`, its parent `decisionService`). `regcf-corpus.dmn` has 14 such references in 7 decision services and both engines evaluate it in CI (`pr-checks.yml`, job `dmn-engines`).                                                                                                                                                                                                 |
| `ConnectedRequirementGraph`: `Element is not connected` on an `inputData`                              | 860 (101)            | 858 are the same phantom references (they become graph vertices with no edges), so false positive. 2 are top-level inputs nothing requires: `ok/section-given-computed-field.dmn` `input_the_rate`, whose reader decision is a raw-L4 literal (`D-LITERALEXPR` blocking in its fidelity report), and `canon/us/regcf/regcf.dmn` `input_status_2`, not traced.                                                                                                                                                                                                                                                                                                           |
| `ConnectedRequirementGraph`: `Element is not connected` on a `decision`                                | 504 (133)            | dmn-check's opinion that a file is one connected graph. 438 are literal decisions with no information requirement and no consumer, 65 have only `knowledgeRequirement`s (calls to BKMs), which `RequirementGraph.from` does not include as edges or vertices, 1 is a table with no inputs.                                                                                                                                                                                                                                                                                                                                                                              |
| `ConnectedRequirementGraph`: `Found unconnected requirement graphs`                                    | 79 (79)              | Same opinion.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `RequirementGraphLeaf`: `may only contain one leaf node`                                               | 316 (316)            | Same single-final-decision opinion. 353 of the 487 exports hold two or more decisions, and 208 of these 316 have no `decisionService`, so the extra leaves are real decisions, not phantom references.                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `ConnectedRequirementGraph`: `either no or more than one decision table`                               | 73 (37)              | dmn-check only compares a decision table with a decision table across an edge. All 73 decisions have no table: 70 are boxed literal expressions and 3 are contexts.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `ConnectedRequirementGraph` and `RequirementGraphLeaf`: `Edge would induce a cycle`                    | 11 + 11 (11)         | Real: mutual recursion in the L4 source. Each of the 11 files has a multi-member `D-CYCLE` blocking note from the exporter. 38 more files have `D-CYCLE` notes for self-recursion only; the exporter reports a one-member cycle and does not write its edge (`specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md`, the `D-CYCLE` row), so dmn-check does not see it.                                                                                                                                                                                                                                                                                                           |
| `ConnectedRequirementGraph`: `Inputs and outputs do not match in connected decisions`                  | 2 (2)                | dmn-check's rule is that a downstream table reads an upstream table's `<output name>` in an input expression. The exporter writes no `name` on `<output>`, and `ok/desc.dmn` `factorialIfPositive` reads `factorial` in an output cell. Opinion, with an exporter contribution.                                                                                                                                                                                                                                                                                                                                                                                         |
| `ConnectedRequirementGraph`: `Could not parse`                                                         | 1 (1)                | dmn-check's FEEL grammar: `openfisca/basic-income.dmn` calls `period_reaches(the_period: period, y: 2016, m: 12)`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `OutputTypeDeclaration`: `Output has no type` (warning)                                                | 544 (161)            | Exporter. The type is written on the decision's `<variable>`, and `<output>` has no `typeRef`. Writing it there would turn each `number` into the `Could not parse FEEL expression type 'number'` error below (`fixtures/number-type.dmn` is that case).                                                                                                                                                                                                                                                                                                                                                                                                                |
| `InputTypeDeclaration`: `Could not parse FEEL expression type`                                         | 155 (64)             | 152 are `'number'`: false positive. dmn-check's type grammar knows string, boolean, integer, long, double, date, item definitions and enum class names (`ExpressionTypeParser` in `dmn-check-validators-1.4.0-sources.jar`), not DMN 1.3's `number`, and `reg-cf.dmn`, which has 8 `typeRef="number"`, passes both engines in CI (`pr-checks.yml`, job `dmn-engines`). 3 are not explained: `canon/us/regcf/cleanroom/regcf-denovo.dmn` uses three item definitions it declares itself (`annual_income_period_reading`, `holders_of_record_reading`, `one_intermediary_scope_reading`) and dmn-check cannot parse their names, while a fourth of the same shape parses. |
| `InputEntryType` and `InputValuesType`: `Type of input entry / predefined input values does not match` | 262 (44) and 87 (44) | False positive. Every one is on a table with an input typed by an item definition over `string` (an L4 enum), whose entries and values are string literals. `ExpressionType.isSubtypeOf` has no rule relating a string to an item definition.                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `OutputEntryType`: `Variable '...' has no type` (warning)                                              | 190 (58)             | False positive. `OutputEntryTypeValidator` type-checks an output cell in an empty context, so any variable it names is untyped.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `OutputEntryType`: `Could not parse`                                                                   | 424 (65)             | 301 (47 files) are cells holding L4 source text, which the exporter itself reports as `D-NONFEELOUTPUT` blocking (361 notes corpus-wide): exporter, known, and this corroborates it. 123 are valid FEEL that dmn-check's grammar lacks: 92 calls `f(..)` including BKM invocations, 17 contexts `{..}`, 5 `if .. then .. else`, 9 other such as `a * (5 / 100)`. The split is a heuristic: L4 keywords or a backtick in the cell text with string literals removed.                                                                                                                                                                                                     |
| `ConflictingRule` 2, `ShadowedRule` 2                                                                  | 4 (1)                | Real, and deliberate: `ok/consider-numbers-and-text.l4` `h` has arms `1`, `1.0`, `0.10`, `0.1`, and the file's own comment says the second and fourth are redundant.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `ShadowedRule`                                                                                         | 1 (1)                | Exporter. `ok/pattern-matching-literal-clauses.dmn` `text_as_written` row 2 requires `s = "São Paulo"` and `s = "tab\there"` at once, so it is a dead row that row 1 shadows.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `OutputValuesType`: `Types of head and tail do not match`                                              | 1 (1)                | Exporter, deliberate: `dmn/refuse.dmn` adds `null` to a table's `<outputValues>` so a `REFUSE` position answers the same on both engines, and records `D-OUTPUTVALUES-NULL` (`doc/exports/dmn-bpmn.md`, "When a decision can refuse").                                                                                                                                                                                                                                                                                                                                                                                                                                  |

By count, of the 5675 findings: 4797 (85%) are dmn-check's own model disagreeing with DMN 1.3 as Camunda 8 and KIE read it (false positive or opinion), 847 (15%) are the exporter's (544 `typeRef` omitted from `<output>`, 301 cells it already reports as L4 source, 1 dead row, 1 deliberate `null`), and 31 are real or not explained (22 cycle errors, 4 rule-level, 2 unconnected inputs, 3 unparsed item-definition names).

## What this does not tell you

- It does not execute a decision; `etc/camunda-dmn-check` and `etc/kie-dmn-check` do.
- It reads through Camunda 7's DMN model and Camunda 7's type names, so most findings above are dmn-check disagreeing with DMN 1.3 as Camunda 8 reads it, not the exporter or the rules being wrong.
- The graph validators assume one connected graph with one final decision whose edges join decision tables.
  An L4 module is a set of rules, so those findings are close to universal and carry little signal.
- The findings that carry signal in this census are the rule-level ones (`Conflicting` and `Shadowed`; `Duplicate` found none), the cycle errors, and the cells that are not FEEL.
  The exporter already reports the last two (`D-CYCLE`, `D-NONFEELOUTPUT`).

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

`--corpus` exports every `.l4` file under the roots with `l4 export dmn`, except any below a directory named `not-ok` (negative fixtures, written to be refused) and any `*.evaldiff.l4` (scratch files, CLAUDE.md section 3.2.1).
It keeps the files for which that exits 0 and writes a non-empty file containing `<definitions`, and checks those.
A `tests` directory is swept: `jl4/examples/legal/tests/imaginary-alcohol-act.l4` is a corpus file that exports, and an earlier version of the sweep skipped it.
With no root, the root is `jl4/examples` of the checkout `run.sh` lives in.
Put your own build's `l4` first on `PATH` or set `DMN_CHECK_L4`: an `l4` older than the corpus misreads newer syntax (CLAUDE.md section 3.1).
The banner names the JDK that ran.
The corpus run writes into `$DMN_CHECK_WORKDIR/corpus`: the exported DMN and the exporter's fidelity report beside each, `export-status.tsv`, `report.txt` and `findings.tsv`.
`summarise.sh` regroups `findings.tsv` into the table of kinds.
`--tsv` is for single-file runs; with `--corpus` it is refused (exit 2), because the corpus run writes its own `findings.tsv` and a second one would replace it silently.

### Which JDK

`run.sh` needs a JDK 21 or later, and it picks one itself: `DMN_CHECK_JAVA_HOME` if set, else the first usable entry of a fixed list (Homebrew `openjdk@21`, Homebrew `openjdk`, two Linux `java-21-openjdk` paths, then `/usr/libexec/java_home -v 21+`).
**It does not read `JAVA_HOME`, and it does not look for a `java` on `PATH`.**
This is assumed, not ruled: it copies `etc/camunda-dmn-check`, which does the same, and the reason is that on the machine this was built on the shell's JDK is a 26 chosen for other work, so a result that depended on it would change with the shell it was run from.
The cost is the other way round: a machine whose only JDK 21+ is `JAVA_HOME` gets `skipped:`, and the skip line says to set `DMN_CHECK_JAVA_HOME`.
Pin `DMN_CHECK_JAVA_HOME` to a JDK 21 if you want the result to mean what 21 gives and what the Camunda leg's CI gives.
`run.sh` exports `JAVA_HOME` to that JDK, so Maven runs on it as well.

### Where it works

The work directory is `DMN_CHECK_WORKDIR`, else `$TMPDIR/l4-dmn-check-<uid>` (per user, because `/tmp` is shared on Linux, and refused as `BROKEN` if it exists and you do not own it).
It is made absolute before use, so a relative `DMN_CHECK_WORKDIR` means a directory under the caller's, and nothing is written beside `run.sh` or into the repo.
The first run downloads dmn-check and its dependencies, 18 jars, from Maven Central into Maven's local repository, and resolves the classpath into the work directory.

## Policy: optional evidence, not a gate

- Nothing in `.github/workflows/` runs this, and `etc/verify-branch.sh` does not.
  The Camunda and KIE legs are required CI gates over a closed list of committed goldens; this is not, because over the whole corpus it exits 1 today (the census below), for reasons that are mostly about dmn-check's model and not about the rules.
  `export` makes the same argument about `Blocking` fidelity notes in `jl4/app/L4/Cli/Export.hs`.
  "Optional evidence" is the contract of the row that asked for this harness; making it a gate would be a separate ruling.
- It prints one line starting `skipped:` and exits 0, with no VERDICT banner, in exactly these cases, each tested by `selftest.sh`:

  - Maven is not on `PATH`;
  - no JDK 21 or later is found (see "Which JDK"), or the one named by `DMN_CHECK_JAVA_HOME` is older;
  - neither `shasum` nor `sha256sum` is on `PATH`, so the jar pin cannot be checked (this is tested before anything is downloaded);
  - Maven cannot resolve dmn-check: offline, or the first-run download failed;
  - with `--corpus`, there is no `l4` (none on `PATH`, `DMN_CHECK_L4` unset or not executable).

  `DMN_CHECK_REQUIRED=1` turns that into exit 1, as `CAMUNDA_CHECK_REQUIRED` does for the sibling.
  A defect in this repo is never a skip: see "Loud failures" below.

- With everything present, exit 1 if any file had an ERROR finding, could not be read, or crashed a validator.
  WARNINGs do not fail the run unless `--fail-on-warning`.
  That is dmn-check's own rule (`PluginBase.testFile`) and the Camunda leg's (errors fail).

## Loud failures and silent ones

Loud, so they teach:

- Jars that are not the pinned ones: `BROKEN`, exit 1, with the diff.
- A `pom.xml` Maven cannot read (or one that is missing): `BROKEN`, exit 1, and not a skip.
  Maven's text for it ("The build could not read", "Non-parseable POM", "Malformed POM") is how `run.sh` tells a repo defect from a machine that cannot reach Maven Central.
- A classpath with an empty entry (Java reads one as the current directory), or an entry that is not an absolute path or not a file: `BROKEN`, exit 1.
- `javac` fails on the driver: `BROKEN`, exit 1.
- A work directory that exists, is the default one and is not yours: `BROKEN`, exit 1.
- `--corpus` with `--tsv`: exit 2.
- The export sweep losing a status row (a child that died before recording its file): exit 1 with a message naming the counts.
- A file that cannot be read, or a validator that throws: an `UNREADABLE` or `CRASH` line, counted in the banner, exit 1.
- No validators found on the classpath: `BROKEN`, exit 1.
- Pin and classpath disagree on the version: a `VERSION MISMATCH` line and exit 1.

Silent, which return a plausible answer:

- A `skipped:` line and exit 0 means nothing was checked.
  The only other sign is that there is no VERDICT banner.
- Two skips hide a cause that is not the machine's.
  A pom that names a version of dmn-check that does not exist ("Could not find artifact ... in central") is told apart from being offline by nothing, so it reads as "could not resolve dmn-check from Maven".
  A machine whose only JDK 21+ is `JAVA_HOME` or the `java` on `PATH` reads as "no JDK 21+ found" (see "Which JDK").
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

Cross-check, 2026-10-30, over the 488 exported files of the census below: the stock CLI (`--searchPath` over the exports) printed 3868 `ERROR` and 1809 `WARN` lines across 382 files, and the driver reported 3868 errors and 1809 warnings across 382 files.
So the driver does not invent findings and does not lose them.

## The pin

`pom.xml` pins `de.redsix:dmn-check-cli` to 1.4.0, which fixes every transitive version too.
`jars.sha256` pins the SHA-256 of each of the 18 jars on the resolved classpath, and `run.sh` refuses to run on a mismatch.
`maven-dependency-plugin`, which resolves the classpath, is pinned to 3.7.0 in the same `pom.xml`.
Maven's own checksum check compares a jar with the checksum the same repository publishes, which catches a corrupt download and nothing else.
The four `de.redsix` jars in `jars.sha256` equal the `.sha256` files Maven Central publishes for them (compared 2026-10-30).

Bumping the pin: change `<dmncheck.version>` in `pom.xml`, delete `$DMN_CHECK_WORKDIR/cp.txt`, resolve with `mvn -f etc/dmn-check/pom.xml -Dmdep.outputFile=<absolute path>/cp.txt dependency:build-classpath`, then write `sha256  file-name` for each jar on it, sorted with `LC_ALL=C sort`, into `jars.sha256`.
Then run `selftest.sh`: its counts (21 validators, the number-type finding) are claims about 1.4.0 and will fail if they stop being true.

`run.sh` compiles the driver with `--release 21`, so the cached class loads on every JDK it accepts.
`etc/camunda-dmn-check/README.md` describes the stale-class trap that its harness has and this one does not.

The resolved classpath is cached in `cp.txt`, keyed on the hash of `pom.xml` (`cp.pom.sha256`), so a checkout with a different pom re-resolves.
The compiled driver is cached in `classes/`, which comes FIRST on the classpath and so runs ahead of the pinned jars.
It is therefore trusted only while `classes.stamp`, written beside it, describes it exactly: the hash of `DmnCheckRun.java`, the hash of `jars.sha256` (the driver is compiled against those jars), and the hash of every file under `classes/`.
Anything else (an edited source, a bumped pin, a planted or altered `.class`, an extra file, a symlink) deletes `classes/` and compiles afresh.
The source is compared by hash, not by modification time: an edited source with an older mtime than the classes used to keep the stale driver (`selftest.sh`, check 12).

## What is not verified

The pin and the stamp narrow what runs.
They do not make it trusted.
What is still taken on trust:

- Maven, the JDK and `maven-dependency-plugin`.
  The plugin is pinned to 3.7.0 in `pom.xml`, by version and not by checksum, and all three run before the jar pin is checked.
- The window between the pin check and the launch.
  `run.sh` hashes the jars and then starts the JVM, so a process of yours that swapped a jar in between would not be caught.
- A work directory other people can write to.
  The default one is per user and ownership-checked, but an explicit `DMN_CHECK_WORKDIR` is taken as given, and `classes.stamp` sits in it beside the classes it describes.
  Whoever can write the directory can write a matching stamp; what the stamp catches is a stale, edited or planted class that does not come with one.
- The repo itself.
  A change to `jars.sha256`, `run.sh` or the driver is a change to what is trusted, and only review stops it.
- A jar's location.
  The pin matches a file name with a content hash, so the same jar from another directory passes.
- The driver's correctness beyond the cross-check against the stock CLI above.

## Census, 2026-10-30

Measured at `legalese/l4-ide` `unstable` `bcbec1419` with an `l4` built from that tree and its embedded prelude (`JL4_LIBRARY_PATH` unset), dmn-check 1.4.0 on JDK 21.0.12.1, root `jl4/examples`.
Re-running gave identical counts.

Export (`l4 export dmn`): 573 `.l4` files considered, 488 exported, 85 refused (81 `No decisions found in module`, 4 `Type checking failed`), none timed out.

Check: 488 read, 0 unreadable, 0 validator crashes.
106 files have no finding and 382 have at least one: 3868 errors and 1809 warnings, 5677 findings in all.

The first version of this census counted 572 files, 487 exports and 5675 findings.
It skipped every `tests` directory, and `jl4/examples/legal/tests/imaginary-alcohol-act.l4` is a corpus file that exports.
Adding it adds two findings (a `Found unconnected requirement graphs` and a `may only contain one leaf node`, both below) and changes no other.

The table groups findings by validator, message and element type (`summarise.sh`).
The reading is a judgement from an example and from the dmn-check source, and the evidence is given so it can be argued with.
"False positive" means dmn-check objects to something DMN 1.3, Camunda 8 and KIE accept; "opinion" is the same where dmn-check is enforcing a rule of its own (one connected graph, one final decision, a type on every output) that the standard does not make.
Both count as dmn-check's, not the exporter's or the rules'.
"Exporter" means the exporter writes something that is not fine DMN or not what the L4 says, or reports the loss itself.
"Real" means the L4 source has the property.

| Finding                                                                                                | Count (files)        | Reading and evidence                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ------------------------------------------------------------------------------------------------------ | -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `InputDataIdAndName`: `A input has no id` (error) and `has no name` (warning)                          | 1075 + 1075 (110)    | False positive. All 1075 `<inputData>` opening tags without an `id` in the exports are `<inputData href="#..."/>` references inside a `<decisionService>` (1075 lack `id`, 1075 carry `href`), and dmn-check's reader types each as an `inputData` (the findings' element type is `inputData`, its parent `decisionService`). `regcf-corpus.dmn` has 14 such references in 7 decision services and both engines evaluate it in CI (`pr-checks.yml`, job `dmn-engines`).                                                                                                                                                                                                 |
| `ConnectedRequirementGraph`: `Element is not connected` on an `inputData`                              | 860 (101)            | 858 are the same phantom references (they become graph vertices with no edges), so false positive. 2 are top-level inputs nothing requires: `ok/section-given-computed-field.dmn` `input_the_rate`, whose reader decision is a raw-L4 literal (`D-LITERALEXPR` blocking in its fidelity report), and `canon/us/regcf/regcf.dmn` `input_status_2`, not traced.                                                                                                                                                                                                                                                                                                           |
| `ConnectedRequirementGraph`: `Element is not connected` on a `decision`                                | 504 (133)            | dmn-check's opinion that a file is one connected graph. 438 are literal decisions with no information requirement and no consumer, 65 have only `knowledgeRequirement`s (calls to BKMs), which `RequirementGraph.from` does not include as edges or vertices, 1 is a table with no inputs.                                                                                                                                                                                                                                                                                                                                                                              |
| `ConnectedRequirementGraph`: `Found unconnected requirement graphs`                                    | 80 (80)              | Same opinion.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `RequirementGraphLeaf`: `may only contain one leaf node`                                               | 317 (317)            | Same single-final-decision opinion. 354 of the 488 exports hold two or more decisions, and 209 of these 317 have no `decisionService`, so the extra leaves are real decisions, not phantom references.                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `ConnectedRequirementGraph`: `either no or more than one decision table`                               | 73 (37)              | dmn-check only compares a decision table with a decision table across an edge. All 73 decisions have no table: 70 are boxed literal expressions and 3 are contexts.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `ConnectedRequirementGraph` and `RequirementGraphLeaf`: `Edge would induce a cycle`                    | 11 + 11 (11)         | Real: mutual recursion in the L4 source. Each of the 11 files has a multi-member `D-CYCLE` blocking note from the exporter. 38 more files have `D-CYCLE` notes for self-recursion only; the exporter reports a one-member cycle and does not write its edge (`specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md`, the `D-CYCLE` row), so dmn-check does not see it.                                                                                                                                                                                                                                                                                                           |
| `ConnectedRequirementGraph`: `Inputs and outputs do not match in connected decisions`                  | 2 (2)                | dmn-check's rule is that a downstream table reads an upstream table's `<output name>` in an input expression. The exporter writes no `name` on `<output>`, and `ok/desc.dmn` `factorialIfPositive` reads `factorial` in an output cell. Opinion, with an exporter contribution.                                                                                                                                                                                                                                                                                                                                                                                         |
| `ConnectedRequirementGraph`: `Could not parse`                                                         | 1 (1)                | dmn-check's FEEL grammar: `openfisca/basic-income.dmn` calls `period_reaches(the_period: period, y: 2016, m: 12)`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `OutputTypeDeclaration`: `Output has no type` (warning)                                                | 544 (161)            | Opinion. `typeRef` is optional on `<output>`: in `DMN13.xsd`, as shipped in `camunda-dmn-model-7.24.0.jar`, `tOutputClause` declares `<xsd:attribute name="typeRef" type="xsd:string"/>` with no `use="required"`, and both engines accept the exports in CI. The exporter writes the type on the decision's `<variable>` and not on `<output>`; writing it on `<output>` too is an optional follow-up, and would turn each `number` into the `Could not parse FEEL expression type 'number'` error below (`fixtures/number-type.dmn` is that case).                                                                                                                    |
| `InputTypeDeclaration`: `Could not parse FEEL expression type`                                         | 155 (64)             | 152 are `'number'`: false positive. dmn-check's type grammar knows string, boolean, integer, long, double, date, item definitions and enum class names (`ExpressionTypeParser` in `dmn-check-validators-1.4.0-sources.jar`), not DMN 1.3's `number`, and `reg-cf.dmn`, which has 8 `typeRef="number"`, passes both engines in CI (`pr-checks.yml`, job `dmn-engines`). 3 are not explained: `canon/us/regcf/cleanroom/regcf-denovo.dmn` uses three item definitions it declares itself (`annual_income_period_reading`, `holders_of_record_reading`, `one_intermediary_scope_reading`) and dmn-check cannot parse their names, while a fourth of the same shape parses. |
| `InputEntryType` and `InputValuesType`: `Type of input entry / predefined input values does not match` | 262 (44) and 87 (44) | False positive. Every one is on a table with an input typed by an item definition over `string` (an L4 enum), whose entries and values are string literals. `ExpressionType.isSubtypeOf` has no rule relating a string to an item definition.                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `OutputEntryType`: `Variable '...' has no type` (warning)                                              | 190 (58)             | False positive. `OutputEntryTypeValidator` type-checks an output cell in an empty context, so any variable it names is untyped.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `OutputEntryType`: `Could not parse`                                                                   | 424 (65)             | 301 (47 files) are cells holding L4 source text, which the exporter itself reports as `D-NONFEELOUTPUT` blocking (361 notes corpus-wide): exporter, known, and this corroborates it. 123 are valid FEEL that dmn-check's grammar lacks: 92 calls `f(..)` including BKM invocations, 17 contexts `{..}`, 5 `if .. then .. else`, 9 other such as `a * (5 / 100)`. The split is a heuristic: L4 keywords or a backtick in the cell text with string literals removed.                                                                                                                                                                                                     |
| `ConflictingRule` 2, `ShadowedRule` 2                                                                  | 4 (1)                | Real, and deliberate: `ok/consider-numbers-and-text.l4` `h` has arms `1`, `1.0`, `0.10`, `0.1`, and the file's own comment says the second and fourth are redundant.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `ShadowedRule`                                                                                         | 1 (1)                | Exporter. `ok/pattern-matching-literal-clauses.dmn` `text_as_written` row 2 requires `s = "São Paulo"` and `s = "tab\there"` at once, so it is a dead row that row 1 shadows.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `OutputValuesType`: `Types of head and tail do not match`                                              | 1 (1)                | Exporter, deliberate: `dmn/refuse.dmn` adds `null` to a table's `<outputValues>` so a `REFUSE` position answers the same on both engines, and records `D-OUTPUTVALUES-NULL` (`doc/exports/dmn-bpmn.md`, "When a decision can refuse").                                                                                                                                                                                                                                                                                                                                                                                                                                  |

By count, of the 5677 findings: 5343 (94%) are dmn-check's own model or opinion disagreeing with DMN 1.3 as Camunda 8 and KIE read it (false positive or opinion, 544 of them the `typeRef` that DMN 1.3 makes optional on `<output>`), 303 (5%) are the exporter's (301 cells it already reports as L4 source, 1 dead row, 1 deliberate `null`), and 31 (0.5%) are real or not explained (22 cycle errors, 4 rule-level, 2 unconnected inputs, 3 unparsed item-definition names).
An earlier version of this page counted the 544 `typeRef` findings as the exporter's and said 85%, 15% and 0.5%; the schema check above is why it no longer does.

## What this does not tell you

- It does not execute a decision; `etc/camunda-dmn-check` and `etc/kie-dmn-check` do.
- It reads through Camunda 7's DMN model and Camunda 7's type names, so most findings above are dmn-check disagreeing with DMN 1.3 as Camunda 8 reads it, not the exporter or the rules being wrong.
- The graph validators assume one connected graph with one final decision whose edges join decision tables.
  An L4 module is a set of rules, so those findings are close to universal and carry little signal.
- The findings that carry signal in this census are the rule-level ones (`Conflicting` and `Shadowed`; `Duplicate` found none), the cycle errors, and the cells that are not FEEL.
  The exporter already reports the last two (`D-CYCLE`, `D-NONFEELOUTPUT`).

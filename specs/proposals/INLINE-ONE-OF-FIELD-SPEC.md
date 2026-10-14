# Inline `ONE OF` on a record field

**Status:** Proposed; built on local branch `feat/inline-one-of` (not pushed); C over A not ruled.
Written 2026-10-12 as a design note and revised 2026-10-14 after one skeptic round (verdict **weakens**; §9 lists what changed).
Option C was then built on that branch, on Meng's instruction of 2026-10-14 to "proceed if it only weakens, doesn't overturn"; §9.1 says what the build changed, and §8 marks what it settled.
Nothing on the branch is pushed, and C over A is not separately ruled.
**Evidence:** the probes, scripts and saved sources this note cites are in `inline-one-of-field/` beside it; paths below are relative to this file.
They are copied unchanged, except that `inline-one-of-field/measure/encdirs.txt` lists the encodings directories relative to the `legalese/commons` repository, where the copy the census read gave them as absolute paths on the machine it ran on.
**Asked by:** Meng, 2026-10-12: "For symmetry it would be kind of nice to support this. Though iirc Haskell doesn't and there's probably good reason why not."
**Trees:** code read on the integration tree at `1747606b1`; probes run on the `l4-ln-551` snapshot binary; corpus measured on `legalese/l4-ide` origin/unstable `708c40f72` and `legalese/commons` main `f8ee9266`.
**Prior record:** `specs/proposals/GIVETH-INLINE-TYPE-DECL-SPEC.md` and `GIVETH-MULTIPLE-RESULTS-SPEC.md`, both rejected 5/5 on 2026-07-26 (`3f8259f0a`).

```l4
DECLARE Plot HAS
    `the owner` IS A STRING
    `tenure`    IS ONE OF Owner, Tenant, Lodger      -- not legal today
```

## 0. The answer in brief

The symmetry Meng has in mind is real but not exact, and the inexactness is Haskell's reason.
A sum whose alternatives carry fields (`Rect HAS width IS A NUMBER`) creates **no new type**: the fields are the constructor's arguments, which is why Haskell (record syntax on constructors) and OCaml (inline records, 4.03) both allow it.
A product whose field is a sum must create **a new type**, because a field needs a type, and in a nominal language a type needs a name.
So the only real question is who names it: the author (option B), the compiler (option C), or nobody, by keeping today's `DECLARE` (option A).

I recommend **C, narrowly scoped**: `` `tenure` IS ONE OF Owner, Tenant, Lodger `` is accepted as the whole type of a record field or a constructor's payload field, and the desugarer lifts it, before type checking, into an ordinary ``DECLARE `Plot's tenure` IS ONE OF …`` beside the record, exactly as `desugarComputedFields` already lifts a field's `MEANS` into a `DECIDE`.
It rests on symmetry and locality: it makes L4's sums-of-products symmetric in the direction Meng asked about, and it puts a field's options on the field, where today 147 such lists sit a declaration away (median 4 lines).
It does not, on the evidence, remove an invented name: the generated name is built from the record's and the field's names, which the encoder also chose (§3.4).
Its nearest precedent is C++'s unnamed member enum, which stays nominal and is named by its place, `decltype(Plot::tenure)`, though C++ never gives it an ordinary identifier.
Lifting before type checking means the exporters and schema writers that read `EnumDecl` see an ordinary declaration; `l4 render` and the function schema are the exceptions, and read a provenance mark (§5.10, §5.11).
**It is a close call against the status quo**, and §7 states what would make A the better answer.
The measured benefit is 147 of 2,988 enums (4.9%), against the GIVETH proposal's 1 of 162; and 385 more enums are one field's type and are also named by a rule, which an anonymous form cannot serve unless the rule writes the generated name.

## 1. What is true today

Everything in this table was run or read on the trees named above; probe files are in `inline-one-of-field/`.

| #   | Fact                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Evidence                                                                                                      |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| 1   | All three inline spellings are parse errors at `ONE`: "unexpected ONE, expecting (, A, AN, FOR, FUNCTION, LIST, THE, TYPE, identifier". `ONE` cannot begin a type today, so it is free as a one-token trigger.                                                                                                                                                                                                                                                                                                                                                                                 | `inline-one-of-field/p1a.l4`; team lead's probes                                                              |
| 2   | A record field is `name IS type [TYPICALLY literal] [MEANS expr]` (`reqParam`, `Parser.hs:1725-1735`), and a constructor's payload fields use the same parser (`conDecl` → `recordDecl'`, `Parser.hs:899-930`). `TypedName` is used for those two positions and nowhere else; `GIVEN` uses `OptionallyTypedName`.                                                                                                                                                                                                                                                                              | `Syntax.hs:169-180`                                                                                           |
| 3   | Two enums in one module may share a constructor; the type picks it where the type is known (`WITH`, `CONSIDER`, `p's tenure EQUALS Owner`), and a bare `#EVAL Owner` is a loud error listing both.                                                                                                                                                                                                                                                                                                                                                                                             | `inline-one-of-field/twoenums.l4`, `inline-one-of-field/p5-ambig.l4`, `inline-one-of-field/p6-sections.l4:11` |
| 4   | A backticked type name may contain a genitive: ``DECLARE `Plot's tenure` IS ONE OF …`` with `` GIVEN t IS A `Plot's tenure` `` checks and runs. 78 `DECLARE` lines in the corpus (69 distinct names) already have an apostrophe in the type's name.                                                                                                                                                                                                                                                                                                                                            | `inline-one-of-field/p4-genitive-name.l4`; `grep`                                                             |
| 5   | Section-local types are qualified by section: two `Tenure`s in two sections are `Plots.Tenure` and `Roles.Tenure`, and an unqualified use from a third section is a loud ambiguity error.                                                                                                                                                                                                                                                                                                                                                                                                      | `inline-one-of-field/p6-sections.l4`                                                                          |
| 6   | **The one-line payload form is already ambiguous.** `DECLARE Shape IS ONE OF Dot, Rect HAS width IS A NUMBER, height IS A NUMBER, Circle` fails: the comma after `height IS A NUMBER` is read as a field separator and `Circle` as a field name ("expecting IS"). A payload-carrying alternative can only be last on a line; the multi-line form works.                                                                                                                                                                                                                                        | `inline-one-of-field/p2-payload.l4`, `inline-one-of-field/p2b-payload.l4`                                     |
| 7   | A computed field is lifted out of its record before type checking: `desugarComputedFields` turns `adult IS A BOOLEAN MEANS age >= 18` into a top-level `DECIDE` in the same section (`Desugar.hs:291-355`), then section `GIVEN`s and field opening run (`TypeCheck.hs:261-273`). `l4 format` still prints the field as written (exact print works on the parsed tree).                                                                                                                                                                                                                        | `inline-one-of-field/p3-computed.l4`                                                                          |
| 8   | Twenty modules mention `EnumDecl`. Besides the parser and the syntax they are the type checker and its annotation pass, the evaluator, the printer, the JSON and function schemas, the DMN, Catala, docassemble, OpenFisca, relational and MLIR lowerings, the document export, the LSP and the service backend. The exporters and schema writers read the checked module, which is the desugared one (their own comments say so, e.g. `Dmn/Lower.hs:1155`, `Docassemble/Lower.hs:112`); the annotation resolver runs on the parsed tree.                                                      | `grep -rln EnumDecl`                                                                                          |
| 9   | `l4 batch` and the REPL print the **checked** module (`tcRes.module'`, `jl4/app/L4/Cli/Batch.hs:302-303`), so they print what the desugarer produced, not what the author wrote.                                                                                                                                                                                                                                                                                                                                                                                                               | read, not run                                                                                                 |
| 10  | An enum field publishes as `{"type": "string", "enum": [...], "x-l4-type": "<type name>"}` in the function schema (`FunctionSchema.hs:235-240`); the field's `@desc` replaces the enum's (`:215`). The documented meaning of `x-l4-type` is "L4 user-declared type name … when this node came from a DECLARE" (`:45`). It is "consumed by the function-schema endpoint … for chat-side rendering", and stripped from the OpenAPI document (`jl4-service/src/OpenApiDoc.hs:480-489`); the chat client is outside this repository and I could not check what it does with an enum's `x-l4-type`. | read                                                                                                          |
| 11  | Constructors carry `@nlg`, not `@desc`: the annotation resolver attaches `@nlg` to a `ConDecl` (`Parser/ResolveAnnotation.hs:463-469`), and the function schema publishes constructor names only.                                                                                                                                                                                                                                                                                                                                                                                              | read                                                                                                          |

## 2. Prior art, checked

Entries marked **run** were compiled or evaluated here (`inline-one-of-field/probes/`, `inline-one-of-field/dhall/`, and `inline-one-of-field/hs/` for the GHC unboxed-sum field); the rest were read at the primary source, saved under `inline-one-of-field/priorart/`.

### 2.1 Haskell, and why it does not do this

Haskell allows the direction L4 already has and not the one asked for.
The Haskell 2010 Report's grammar puts `data` only at top level, `topdecl → data [context =>] simpletype [= constrs] [deriving]`, lets **any** constructor carry named fields, `constr → con { fielddecl1 , … , fielddecln }`, and gives a field a plain type, `fielddecl → vars :: (type | ! atype)` (ch. 4, §4.2.1, https://www.haskell.org/onlinereport/haskell2010/haskellch4.html).
A type contains no declarations, so there is nowhere to put one.
**Run:** `data Plot = Plot { tenure :: data Tenure = Owner | Tenant }` is "parse error on input 'data'" (`inline-one-of-field/probes/Inline.hs`, GHC 9.10).

The reasons, in order of how much they bind L4:

1. **A type needs a name, because Haskell types are nominal and every signature names them.**
   An inline sum would need a generated name to appear in signatures, error messages and other modules' imports.
   This is the reason that transfers to L4 in full, and it is why every option in §4 names the type somehow.
2. **Constructors live in one flat namespace per module.**
   **Run:** two `data` declarations in one module that both have `Owner` are "Multiple declarations of 'Owner'" (`inline-one-of-field/probes/Clash.hs`).
   Small inline enums with generic constructors would collide constantly.
   **This reason does not transfer to L4**: two L4 enums in one module may share a constructor, and the expected type picks it (§1, fact 3).
   OCaml made the same choice: "Even if the same name appears in the definition of multiple types, the constructor itself belongs to only one type" (OCaml manual, ch. 5).
3. **Type inference wants a constructor to determine its type.**
   Haskell infers the type of `Owner` from the constructor alone; with sharing, it could not.
   L4 gave that up already when it chose type-directed resolution, and pays for it with the loud "multiple definitions" error when there is no type to go on.

GHC's one anonymous sum is the opposite design: `-XUnboxedSums` gives "new syntax for anonymous, unboxed sum types", `(# t_1 | t_2 | ... | t_N #)`, positional and with no constructor names at all (GHC User's Guide §6.16.4).
**Run** (`inline-one-of-field/hs/`): `data Plot = Plot { owner :: String, tenure :: (# () | () | () #) }` compiles and prints `tenant`, but the second alternative is matched by position, `(# | () | #)`, and adding `deriving Show` fails with "Don't know how to derive 'Show' for type '(# () | () #)'".
It exists for performance, not for modelling, and no GHC extension gives a field a sum with named alternatives.
The nearest open GHC proposal, ghc-proposals #273 "Add support for local types" (open, labelled "Needs revision"), is about `data` in `let` and `where`, not in a field.

### 2.2 OCaml

**Inline records in constructors** (OCaml 4.03) are the dual L4 already has: "The arguments of sum-type constructors can now be defined using the same syntax as records" (OCaml manual, language extensions, "Inline records").
OCaml's price for leaving that record unnamed is that it may not escape: "the record cannot escape the scope of the binding", and `function Point p -> p` is "Error: This form is not allowed as the type of the inlined record could escape."
L4's payload fields need no such rule, because L4 never makes the payload a value of its own.

**Polymorphic variants** are OCaml's inline sums, and they are structural: "a variant tag does not belong to any type in particular … You need not define a type before using a variant tag" (manual, ch. 5).
The manual's own verdict on them is the reason not to copy them: they "result in a weaker type discipline … for simple programs you are probably better off with core language variants" (ch. 5 §3, "Weaknesses of polymorphic variants").

### 2.3 Rust

Rust has never had anonymous enums, and every proposal for them has been **structural**: a union of types, `A | B`, not a list of named alternatives.
The record, read from `rust-lang/rfcs` with `gh api` on 2026-10-12:

| number     | title                                                      | state                                                                                  |
| ---------- | ---------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| issue #294 | Anonymous sum types                                        | open; labelled `A-structural-typing`                                                   |
| PR #402    | RFC: Anonymous enum types called joins, as `A \| B`        | closed 2014-10-24: "lacking some critical details with no single obvious solution"     |
| PR #514    | Anonymous enum types (A\|B) take 2                         | closed 2014-12-11, postponed until after 1.0                                           |
| PR #1154   | Disjoins (anonymous enums)                                 | closed 2015-07-31: "the primary reason … was prioritization, not technical objections" |
| PR #2587   | RFC for anonymous variant types, a minimal ad-hoc sum type | postponed 2019-02-05 after final comment period                                        |

The postponement of #2587 gives the reason most relevant here: "I am reluctant to add another 'open ended' form that might bring on similar complications" (nikomatsakis, 2019-01-24), the complication being the tuple problem of a type whose shape is written at every use.
None of these is evidence about a _nominal_ inline enum with named alternatives, which no Rust proposal I found has made.
(PRs #1450 and #2593, "Types for enum variants" and "Enum variant types", both postponed, are the other direction: giving each variant of a named enum its own type.)

**Run:** `struct Plot { tenure: enum { Owner, Tenant } }` is "expected type, found keyword `enum`" (`inline-one-of-field/probes/plot.rs`, rustc).

### 2.4 TypeScript

TypeScript does exactly C, structurally.
**Run** (`inline-one-of-field/probes/plot.ts`, `tsc --strict`): `interface Plot { tenure: "Owner" | "Tenant" | "Lodger" }` checks; a second interface may also use `"Owner"`; and a value outside the list is "Type '"Manager"' is not assignable to type '"Owner" | "Tenant" | "Lodger"'".
The type is named from elsewhere by the access path, not by a declaration: "We can use an indexed access type to look up a specific property on another type", `type Age = Person["age"]` (TypeScript Handbook, Indexed Access Types).
`type Tenure = Plot["tenure"]` is the precedent for C's generated name `` `Plot's tenure` ``: the name of the type is the name of the place.

### 2.5 C and C++ member enums, and Swift, Kotlin and C# nested types

Both C and C++ allow an enum to be defined in a member declaration.
**Run** (`clang -std=c17`, `clang++ -std=c++20`):

- C: `struct plot { enum tenure { OWNER, TENANT, LODGER } tenure; … }` compiles, and the tag and the enumerators leak to file scope (`enum tenure t = TENANT;` outside the struct is fine, `inline-one-of-field/probes/member.c`).
  So a second struct with an `OWNER` is "redefinition of enumerator 'OWNER'" (`inline-one-of-field/probes/clash.c`): Haskell's flat namespace again.
- C++: the same member enum is scoped to the class.
  `Plot::Tenure` and `Role::Owner` coexist with `Plot::Owner`, and the bare `Tenure` outside the class is "unknown type name 'Tenure'; did you mean 'Plot::Tenure'?" (`inline-one-of-field/probes/member.cc`, `inline-one-of-field/probes/notscope.cc`).
- **C++ also has option C, exactly.**
  An unnamed member enum, `struct Plot { enum { Owner, Tenant, Lodger } tenure; }`, is a distinct nominal type with no name; the program names it by its place, `decltype(Plot::tenure) t = Plot::Lodger;`, which compiles and runs (`inline-one-of-field/probes/unnamed.cc`).
  Assigning `Role::Owner` from a second unnamed enum to it is rejected, and the compiler's message names both types by where they are: "cannot initialize a variable of type 'decltype(Plot::tenure)' (aka 'Plot::(unnamed enum at unnamed-bad.cc:1:15)') with an rvalue of type 'Role::(unnamed enum at unnamed-bad.cc:2:15)'" (`inline-one-of-field/probes/unnamed-bad.cc`).
- And C++ draws its line where the GIVETH review said: "'E' cannot be defined in the result type of a function", "'F' cannot be defined in a parameter type" (`inline-one-of-field/probes/ret.cc`).
  Field position is allowed; result and parameter positions are not.

Swift, Kotlin and C# all have nested types, named from outside by qualification.
Swift states the use case in its first sentences: "Enumerations are often created to support a specific class or structure's functionality … Swift enables you to define _nested types_", and "To use a nested type outside of its definition context, prefix its name with the name of the type it's nested within" (The Swift Programming Language, Nested Types); **run**, `struct Plot { enum Tenure { … } }` with `let t: Plot.Tenure = .tenant` compiles and runs (`inline-one-of-field/probes/Nested.swift`), and an anonymous `var tenure: enum { … }` is "expected type".
Kotlin: "Classes can be nested in other classes", used as `Outer.Nested()`, and an `enum class` is a class (Kotlin docs, Nested and inner classes; Enum classes).
C#: "A nested type is a type that you define within a class, struct, or interface", and nested types "default to private" (Microsoft Learn, Nested types).
The same page warns that "making a nested type externally visible violates the code quality rule CA1034 'Nested types should not be visible'", which is Microsoft advising against the very use option D needs.
None of the three allows an anonymous enum in a field: the author always names the nested type.

### 2.6 Dhall

Dhall's unions are anonymous and structural: "A union type is bar-delimited key-type pairs surrounded by angle brackets", `< Number : Natural | Boolean : Bool >`, and a value is made through the type itself, `UnionType.Alternative valueToWrap` (Dhall language tour, Unions).
The standard says they are structural in so many words: "Union types are 'anonymous', meaning that they are uniquely defined by the names and types of their alternatives" (dhall-lang `standard/type-inference.md`).
**Run** (`inline-one-of-field/dhall/`, dhall 1.42.3): a record typed `{ owner : Text, tenure : < Owner | Tenant | Lodger >, role : < Owner | Manager > }` checks, with the tag `Owner` in two unions; a value is `< Owner | Tenant | Lodger >.Tenant`, read with `merge`, and evaluates to `{ role = "role owner", tenure = "tenant" }` (`plot.dhall`).
`< Owner | Tenant | Lodger >` and `< Lodger | Owner | Tenant >` are one type (`structural.dhall` gives `3`), and a tag outside the union is loud: "Missing constructor: Landlord" (`wrongtag.dhall`).
So Dhall allows exactly the inline form, but every construction site has to spell the whole union unless the author names it with `let`, which is what the tour's own example does (`let Example = < Number : Natural | Boolean : Bool >`): option A arrived at by convention.

### 2.7 The legal and decision-modelling world

The data notations put the options on the field; the languages make you declare them.

- **DMN.** "An instance of ItemDefinition may contain zero or more itemComponent, which are themselves ItemDefinitions. Each itemComponent in turn may be defined by either a typeRef and allowedValues or a nested itemComponent … The name of an itemComponent (nested ItemDefinition) must be unique within its containing ItemDefinition" (DMN 1.3, §7.3.3 "ItemDefinition metamodel").
  A structured input's field may carry its own allowed values, named only by the field within its parent: that is C, down to the naming rule.
- **JSON Schema.** "The value of this keyword MUST be an array … An instance validates successfully against this keyword if its value is equal to one of the elements in this keyword's array value" (JSON Schema Validation 2020-12, §6.1.2 `enum`).
  It is a keyword of the property's own subschema and needs no `$defs` entry, and it is how L4's function schema already publishes an enum field (§1, fact 10).
- **docassemble.** A field's choices are written on the field (`choices:`), and a list shared between questions is moved into a variable through `code:`, which "is used in place of a choices field modifer, which you would use to specify the choices manually" (docassemble docs, Fields; the misspelling is theirs).
  Inline by default, named when shared: C for one use and A for many.
- **Catala.** A structure field's type is "any other structure or enumeration that you declare", and an enumeration is its own top-level `declaration enumeration TaxCredit:` with `--` alternatives; the tutorial's `Individual` refers to `DateOfDeath` by name (Catala tutorial, "Declaring a structure", "Declaring an enumeration").
  The Catala book says "It is possible to nest structures (declaring the type of a field of a structure as another structure or enumeration), but not recursively", where nesting means referring by name, and "User-declared types have to be declared before being used".
  The tutorial adds that declarations "often [do] not match any specific article of law. Hence, you can put all the declarations at the top".
  Catala is A.

### 2.8 What the prior art says, in one paragraph

The languages that allow a sum inside a product fall into three groups.
Swift, Kotlin and C# make the author name it, and qualify the name by the enclosing type (option D).
TypeScript, Dhall and OCaml's polymorphic variants let it go unnamed by making it structural, which L4 should not copy (OCaml's own manual says why).
C++ alone does what C proposes: an unnamed member enum that stays nominal, is named by its place (`decltype(Plot::tenure)`), and is described in messages by where it is.
The interchange formats (DMN, JSON Schema, docassemble) all put the options on the field, and DMN names a field's nested definition by the field, unique within its parent, which is C's naming rule.
Haskell, Rust and Catala do none of it: in each, a field's type is a type expression, and a type expression cannot contain a declaration.

## 3. Corpus measurement

### 3.1 What was counted, and how

`inline-one-of-field/measure/census.py` tokenises every `.l4` file after blanking comments, string literals and `@` annotations, finds every `DECLARE X IS ONE OF` and every `DECLARE X HAS`, and classifies each occurrence of `X` outside its own declaration by the tokens around it and by layout.
**It is a text heuristic, not a parse.**
An occurrence counts as a reference when `X` stands in type position: after `IS` (optionally through `A`, `AN`, `THE`, `LIST OF`, `MAYBE`, `FUNCTION FROM … TO`), or after `GIVETH`.
Its site is then read off the keyword that governs the name before that `IS`: `HAS` heading a `DECLARE` is a record field, `HAS` after a constructor is a payload field, and `GIVEN`, `GIVETH` and `ASSUME` are signatures.
Anything else that is still a real use (a qualified `` `Section A`.Verdict ``, an argument to a user type constructor such as `DEONTIC Actor Action`) is counted as "other", and so counts as a use.
`p's X` and `X IS …` are a field or input that shares the type's name, and are not counted.
References are sought in the declaring file and in every file in the same directory that `IMPORT`s it, which is how L4 resolves an importer-relative import; no import in either corpus has a path in it.

**Corpus.** `jl4/examples/{ok,legal,canon}` in the reference checkout at `708c40f72` (origin/unstable), and every `encodings/` directory under `legalese/commons/subjects/` (555 directories; the brief's `subjects/*/encodings` matches none, because subjects sit one level deeper, `subjects/<jurisdiction>/<subject>/encodings`), commons at `f8ee9266`.
At those SHAs that is 2,424 files; 87 byte-identical copies were dropped (mostly the canon mirror), leaving **2,337 files**.
**Corrected 2026-10-14:** version 1 read a working tree rather than `f8ee9266`, and counted 2,497 files with 160 dropped. The extra 73 were gitignored `vendor.sh` copies in `il/employed-parent-monthly-net/encodings/legalese-2026-10-il-07/`, and because the census keeps the first byte-identical copy in walk order and resolves users within that copy's directory, those copies were kept and their home copies, where the enums have other users, were dropped. The figures below are recounted at the SHAs with the same script.

**Positive control.** `inline-one-of-field/measure/control/` holds two files with one enum of each kind the census must tell apart: used once as a field, as a field and a `GIVEN`, only in a `GIVETH`, under `LIST OF`, as a payload field, sharing its name with its field (`` `Pun` IS A `Pun` `` and `r's Pun`), named only in a comment, a block comment, a string and an `@desc` (must count zero), used once here and once in an importing file (must count shared), used by a synonym, and declared adjacent to or separated from its record.
`python3 census.py --control control`, run in `inline-one-of-field/measure/`, prints `CONTROL: PASS`.

**Precision check by hand.** For eight candidates drawn at random (seed 20261012), a raw `grep -rn -w` over the declaring directory found exactly two lines each: the `DECLARE` and the one field.
**Recall check.** Five enums are classed shared because of one field plus one "other" site; all five are real uses (`GIVETH DEONTIC Actor Action` and the like), so none is a candidate misclassed.

### 3.2 The numbers

| class (2,988 enums)                                                |   count |    share |
| ------------------------------------------------------------------ | ------: | -------: |
| **candidate**: referenced once, as one record field's type         |     144 |          |
| **candidate**: referenced once, as one constructor's payload field |       3 |          |
| _candidates in total_                                              | **147** | **4.9%** |
| referenced once, as one field, but under `LIST OF` or `MAYBE`      |       6 |     0.2% |
| referenced once, in one `GIVEN`                                    |     964 |    32.3% |
| referenced once, in one `GIVETH`                                   |     230 |     7.7% |
| referenced in two or more places                                   |   1,559 |    52.2% |
| never referenced by name                                           |      59 |     2.0% |
| other single use (a synonym, a qualified or applied name)          |      23 |     0.8% |

Commons alone has 140 candidates at its SHA. (Version 1 gave a per-tree split of 291 + 23 and 2,799 + 157; those were standalone runs that overlap through the canon mirror, and do not add up to the totals.)

Three further figures decide between the options in §4.

1. **Adjacency.**
   Of the 147 candidates, **81 are declared next to their record** (no other top-level item between the two declarations), 65 are separated by other declarations, and one sits in another file.
   The median gap from the end of the enum to the start of the record is 4 lines; the largest is 241.
2. **Field-only enums usually have a second user.**
   385 enums are the type of exactly one field _and_ are also named in one or more `GIVEN` or `GIVETH`, and nowhere else.
   Against 147 that have only the field, that is **72% of the enums whose one structural home is a field**.
   An anonymous inline form can serve only the 147; a named one can serve all 532.
3. **Concentration.**
   At the SHAs the largest contributor is `il/income-tax-ordinance`, with 16 (version 1 said 39 came from `legalese-2026-10-il-07`; all 39 were the vendored copies described in §3.1), and about 31 of the 147 are interpretive _fork registers_: a record such as `` `The readings` `` whose every field is an enum of the readings of one ambiguous provision (`commons/…/il36-nouns.l4:192-200`, `canon/us/regcf/cleanroom/regcf-denovo.l4:105-146, record at :142`).

The same census, run over records, finds **4 of 2,562 records** used once as one field's type and nowhere else.

### 3.3 Against the GIVETH finding

The rejected GIVETH spec counted **1 of 162 `DECLARE`s** as the result type of exactly one decision and referenced nowhere else (0.6%), over three corpora in July.
Field position on today's corpus: **147 of 2,988 enums (4.9%)**, and 151 of 5,550 enums and records together (2.7%).
That is an order of magnitude more, but it is still a minority feature, and most enums whose only home is a field are also named by a rule, which takes them out of it (figure 2).

One caution against reading too much into the comparison: on today's corpus the same census finds 230 enums referenced only once, in one `GIVETH`.
The July count was over a different and much smaller corpus, by a different method, and of all `DECLARE`s rather than enums; this note does not reopen that ruling, and the two numbers should not be set side by side as if they measured the same thing.

### 3.4 Isomorphism with the source

Most subjects in commons carry no source text in the repository, so this could be checked for only 24 of version 1's 164 candidates.
For **20 of those 24, the enum's type name does not occur anywhere in the source text** (case and punctuation ignored): `Kind of Body`, `Kind of Statement`, `Role in Body`, `Kind of Court`, `Position of the Carrier`.
The encoder invented it.
For example, Business Names Registration Act 2014 s 40 deals in turn with a body corporate, a firm and an unincorporated association in subsections (1), (3) and (4); the encoding names that split `` `Kind of Body` `` (`bnra-types.l4:599`), a phrase the Act never uses.
This is not peculiar to candidates: over all 242 enums whose subject carries source text, 206 (85%) have a type name absent from the source.
**But the same test applied to the parts of C's generated name undoes the argument** (corrected 2026-10-14, skeptic's `inline-one-of-field/skeptic/scripts/fieldsrc.py`): the record's name is absent from the source in 24 of those 24, and the field's name in 16 of 24.
`<record>'s <field>` is built from names the encoder also invented, so C moves the invented name rather than removing it.
And for 54 of the 147 candidates the type name already equals the field name, case, article and punctuation aside (`Role`/`role`, `Purpose`/`purpose`, `Kind of Statement`/`kind of statement`); in 45 more one contains the other, and only 48 are unrelated.
Isomorphism therefore does not separate C from A, and this note no longer ranks on it.

**Readability of the generated names.** 38 of the 147 fields and 34 of their records start with an article, which gives `` `The readings's the reading of the adaptation year` `` and `` `Matter's the kind` ``; 5 of the 30 enum names that carry a citation lose it; and 4 candidates are Hebrew records, which would get an English `'s` (`` `מורה's מעמד ההשכלה` ``).
The naming rule stays mechanical all the same (§7), because a name the author can predict is worth more than a prettier one they cannot, and the user page advises a `DECLARE` wherever the type's name will be read.
A citation check points the other way: 69 of version 1's 164 candidate enums (not recounted) carry a citation comment or `@ref` of their own, and in 21 of those the record cites a _different_ provision (`caa-types.l4:369`: the enum `Claimant` cites Article 29, its record Article 30), so the separate `DECLARE` is often where the encoder hangs the enum's own authority.

## 4. The options

Every option below keeps L4's types **nominal**.
A structural sum, where two inline `ONE OF Yes, No` lists are the same type (TypeScript, Dhall, OCaml's polymorphic variants), would change what type equality means across the whole checker; the GIVETH-results review called the record analogue "a type-system change of a completely different magnitude", and that applies here unchanged.

### A. Status quo

```l4
DECLARE Tenure IS ONE OF Owner, Tenant, Lodger
DECLARE Plot HAS
    `the owner` IS A STRING
    `tenure`    IS A Tenure
```

Costs nothing and already works on one line.
Every type has exactly one declaration shape, so `grep 'DECLARE Tenure'` always finds it.
It puts the options one declaration away from the field that is their only user (median 4 lines, §3.2), and leaves sums-of-products asymmetric.

### B. Named inline

The best spelling found that needs no new keyword and fixes the one-line comma problem is the parenthesised `DECLARE` body, which the GIVETH spec recorded as the clean attachment form:

```l4
DECLARE Plot HAS
    `the owner` IS A STRING
    `tenure`    IS A (Tenure IS ONE OF Owner, Tenant, Lodger)
```

The alternatives are worse: `IS A Tenure, ONE OF …` collides with the comma that separates fields; `IS A Tenure WHICH IS ONE OF …` reads better but reserves a new word (`WHICH` is not a keyword today, `Lexer.hs`); `… AKA Tenure` after the list reads as an alias of the last constructor.
**Desugars to** option A exactly, with the author's name.
**Costs.** It saves `DECLARE` and a newline, which is GIVETH finding 1 unchanged.
It hides a type declaration inside a record, so `grep 'DECLARE Tenure'` no longer finds every type, and a reader who meets `GIVEN t IS A Tenure` in a rule has to know to look in the fields of `Plot`.
Multi-line, the parentheses must close after the last constructor, which reads badly.
**Benefit.** It serves all 532 enums whose one structural home is a field, because rules can name the type.

### C. Anonymous inline, compiler-named

```l4
DECLARE Plot HAS
    `the owner` IS A STRING
    `tenure`    IS ONE OF Owner, Tenant, Lodger
```

**Desugars to**

```l4
DECLARE `Plot's tenure` IS ONE OF Owner, Tenant, Lodger
DECLARE Plot HAS
    `the owner` IS A STRING
    `tenure`    IS A `Plot's tenure`
```

The name is the record's name, `'s `, and the field's name, both exactly as written; for a payload field it is the enum's name, the constructor's name and the field's name (`` `Shape's Rect's corner` ``), because two enums may share a constructor (fact 3), and version 1's `<constructor>'s <field>` then collides (§6, finding 8).
**Costs.** A generated name exists, and it appears in error messages, in printed output from `l4 batch` and the REPL (fact 9), and in exporters that need an identifier (Catala, OpenFisca, DMN); §5 deals with each.
In this corpus's house style the name is ugly whenever the field starts with an article: `` `A periodical sum's the period` ``.
It serves only the 147; an enum that later gains a rule that names it must either be named by its generated name or be promoted to a `DECLARE`, and §3.2 says that is the common path (385 to 147).
**Benefit.** The options sit on the field they belong to, and the record reads as one declaration: 65 characters saved per candidate on average over version 1's 164 (the type name twice, `DECLARE` and `IS`), though what matters is locality and symmetry, not characters.

### D. A scoped nested type, `Plot.Tenure`

```l4
DECLARE Plot HAS
    `tenure` IS A Tenure, ONE OF Owner, Tenant, Lodger   -- some B spelling
GIVEN t IS A Plot.Tenure
```

The record becomes a namespace, the way a section already is (fact 5), and the type is named from outside by qualification, as in C++ (`Plot::Tenure`), Swift, Kotlin and C# (`Plot.Tenure`).
**Costs.** Everything B costs, plus a new scoping rule: a record name becomes a qualifier, and qualification by record has to be told apart from qualification by section, which uses the same dot.
**Benefit over B.** The qualified name tells the reader where to look, which answers B's discoverability cost.
It does not relieve any namespace pressure that matters: L4 has no type-name shortage (sections already scope types), and constructor collisions are already resolved by type (fact 3).

### E. The general case: inline records in fields as well

```l4
DECLARE Plot HAS
    `the owner` IS A STRING
    `address`   HAS street IS A STRING, postcode IS A STRING
```

Full sums-of-products symmetry.
**Rejected on the numbers**: 4 of 2,562 records are used once as one field's type and nowhere else (§3.2).
It also inherits every objection the GIVETH-results review made to anonymous records, and a record, unlike an enum, has a `WITH` construction site where its name is written by every caller.

### Ranking

By meaning and correctness first: **C, then A, then B, then D, then E**, and C over A is close.
C is the only option that writes "this field's value is one of these" on the field itself, and the only one that makes sums-of-products symmetric; it is correct in every consumer that reads only the checked module, and `l4 render` and the function schema read its provenance mark (§5.10, §5.11).
A is correct and free, and loses only locality and symmetry; it does not lose isomorphism, because C's generated name is no closer to the source (§3.4).
B adds a second declaration shape to save one keyword.
D adds a scoping rule for a namespace problem L4 does not have.
E has no corpus.

## 5. Option C worked through

### 5.1 Grammar, and the errors when it is written wrong

In `reqParam`, after the `IS`, the parser accepts either a type or `ONE OF` followed by a constructor list, parsed by the same `conDecl` a `DECLARE` uses.
The token `ONE` decides, and no type can start with it (fact 1), so the choice costs one token of lookahead and changes nothing that parses today.

**Where the inline body lives in the AST.** `MkTypedName` gains a field for the optional `ONE OF` body, placed in source order after the type slot and before `TYPICALLY`.
The type slot is filled by the desugarer, which knows the enclosing record and so can make the name; in the parsed tree it carries an empty `Anno`, which both printers render as nothing (the precedent is `OpaqueDecl`, `Syntax.hs:259-274`).
That touches the 62 `MkTypedName` patterns in 22 files, every one a compile error until it is handled, which is the same churn computed fields paid for their fifth field.
The alternative, a new `Type'` constructor, would let `ONE OF` parse in every type position and so reopen GIVETH by the back door; `InfVar`, the existing phase-restricted constructor, appears 112 times in 20 files, which is what that route costs.

**Errors.** Today every misuse is already loud ("unexpected ONE"); the work is to say why, at `ONE`.

| written                                                                            | message, in substance                                                                                                                       |
| ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `tenure IS A ONE OF …`                                                             | Write `IS ONE OF`, without `A`.                                                                                                             |
| `tenures IS A LIST OF ONE OF …`, `IS A MAYBE ONE OF …`                             | `ONE OF` can be the whole type of a field, not part of one. Declare the options with `DECLARE … IS ONE OF …` and write `LIST OF` that type. |
| `GIVEN tenure IS ONE OF …`, and the same in `GIVETH`, `ASSUME` or `DECLARE T IS …` | `ONE OF` can list a field's options inside `DECLARE … HAS`, not a rule's input or result. Declare the options with `DECLARE`.               |
| an inline `ONE OF` inside a payload field of an inline `ONE OF`                    | Declare the inner options with `DECLARE`; inline lists go one level deep.                                                                   |
| an inline `ONE OF` in a record that takes a type parameter                         | Declare the options with `DECLARE` (the lifted type would need the parameter).                                                              |
| a module that also declares `` `Plot's tenure` `` itself                           | The field's options are already called `` `Plot's tenure` ``; rename one.                                                                   |

**The one-line comma, which must be fixed rather than explained.**
In `DECLARE Plot HAS tenure IS ONE OF Owner, Tenant, area IS A NUMBER`, a parser that simply reuses `conDecl` reads `area` as a third constructor and then fails at the following `IS`, pointing at the wrong token.
A constructor is never followed by `IS`, so one more token of lookahead ends the list there (the comma has to be retried, not consumed).
The same lookahead the other way round, "a field name is always followed by `IS`", fixes fact 6, where `Circle` after a payload is read as a field.
That fix stands on its own, is a bug fix today, and should land first and separately.

### 5.2 Exact print and `prettyLayout`

**Exact print** is generic over each constructor's holes in order (`ToConcreteNodes`, `Annotation.hs:178-185`), so the new field prints correctly if and only if it is in source order; `exactprint identity` and the `.ep.golden` of a new `ok/` file guard it.
`ToSemTokens` walks the same holes; if it is missed, the constructors lose their highlighting, which is silent but cosmetic.

**`prettyLayout`** prints the checked module (fact 9), which is the lifted form:

```l4
DECLARE `Plot's tenure` IS ONE OF Owner, Tenant, Lodger
DECLARE Plot HAS
    `the owner` IS A STRING
    `tenure`    IS A `Plot's tenure`
```

That text re-parses (fact 4) and re-checks, and declares the same constructors with the same type name, so it evaluates the same; the round-trip properties of CLAUDE.md §3.2 (no inference-variable name, re-parses, re-type-checks) hold by construction.
It is not the author's layout, any more than computed fields are today.
The evaluation differential of CLAUDE.md §3.2.1 should still be run when this lands, because that is what CLAUDE.md requires of any change that reaches `L4.Print`.

### 5.3 `TYPICALLY`

```l4
    `tenure` IS ONE OF Owner, Tenant, Lodger TYPICALLY Owner
```

`TYPICALLY` follows the list; `reqParam` already parses it after the type, and a constructor list stops at a keyword.
HAIRCUT holds unchanged: the default must be a literal, a nullary constructor is one, and it is checked against the lifted type like any other default.
The function schema's `default` and the field's absence from `required` follow from the existing rule (`FunctionSchema.hs:219-226`).
For a multi-line list, `TYPICALLY` goes on its own line after the last constructor; that should parse, since `TYPICALLY` is not column-checked, but nothing is built and it is untested.

### 5.4 `@desc`, `@nlg` and `@ref`

A field's `@desc` stays on the field, where the function schema already prefers it to the type's (fact 10).
The lifted `DECLARE` gets a copy, so that Catala (`descOfDeclare`, `Catala/Lower.hs:2282`) and anything else that reads a declaration's description finds the same text.
`@nlg` goes on each constructor's line exactly as in a `DECLARE`; the annotation resolver needs a case for the inline list beside its `EnumDecl` case (`Parser/ResolveAnnotation.hs:463-469`).
If that case is forgotten I could not establish whether a stray `@nlg` is reported or silently lands on a neighbour, so it needs a test with a deliberately annotated constructor.
Only 2 of version 1's 164 candidates carry `@desc` or `@nlg` in their declaration.
An enum's own citation (69 of version 1's 164 have one) moves to the field: a comment or `@ref` above the field, in place of the one above the `DECLARE`.

### 5.5 Alternatives that carry fields (L7)

Allowed, because forbidding them would leave an arbitrary seam between a `DECLARE` and its inline twin:

```l4
    `holding` IS ONE OF
        Freehold
        Lease HAS
            `years` IS A NUMBER TYPICALLY 99
```

Under L7 = B the payload field behaves exactly as a record field, `TYPICALLY` included, and that does not change when the enum is inline.
On one line a payload-carrying alternative can only come last until the §5.1 lookahead lands, which is today's rule for `DECLARE` too.
A payload field may not itself be an inline `ONE OF` (§5.1): inline lists go one level deep.
Ten of version 1's 164 candidates have an alternative with fields (not recounted).

### 5.6 Field opening (R5)

Unchanged.
`recordFieldTable` reads field **names** only (`Desugar.hs:409-419`), so it is indifferent to how a field's type is written, and `tenure EQUALS Owner` inside a rule whose input is a `Plot` resolves `Owner` by type as it does today.
The new pass must run before `desugarComputedFields`, so that a computed field with an inline type (`` `status` IS ONE OF Active, Lapsed MEANS … ``) produces a synthetic `DECIDE` whose `GIVETH` already names the lifted type.

### 5.7 `CONSIDER` exhaustiveness

Unchanged: the checker sees an ordinary enum, and a `CONSIDER p's tenure` that misses `Lodger` gets the existing warning.
**Corrected 2026-10-14:** the warning names only the missing branch ("WHEN Lodger THEN", skeptic probe `inline-one-of-field/skeptic/p/q3-consider.l4`), not the type, so the generated name does not reach the reader here.

### 5.8 Sections and `IMPORT`

The lifted `DECLARE` goes into the record's own section, immediately before the record, so it has exactly the record's scope: section-local if the record is, `` Plots.`Plot's tenure` `` from another section (fact 5), and visible to an importing module as every top-level declaration is.
It should carry the field's source range, as the synthetic `DECIDE` of a computed field carries the field's annotation (`Desugar.hs:347-354`), so that go-to-definition and error locations point at the field.

### 5.9 Naming the type from a rule

`` GIVEN t IS A `Plot's tenure` `` works today with a hand-written declaration (fact 4) and will work with a lifted one, because the generated name is an ordinary identifier.
That should be allowed, not forbidden: forbidding it needs a special rule, and the name is as stable as the field.
The user page should still advise a `DECLARE` once a second place needs the type, because that is where §3.2 says most field-only enums end up, and a chosen name reads better than a generated one.

### 5.10 JSON schema and decoding

Recommended: an inline enum publishes **without** `x-l4-type`.
By the field's own documentation (fact 10), `x-l4-type` is the user-declared name of a node that came from a `DECLARE`, and this one did not.
That keeps the generated name out of every deployed schema, and makes a later promotion to a `DECLARE` additive (an `x-l4-type` appears) rather than a rename.
In the module-level schema, which keys enums by type name in `$defs` and points at them with `$ref` (`JsonSchema.hs:71`, `:109`), an inline enum should be written as an `enum` directly in its property, which is JSON Schema's native form.
Both need the lifted `DECLARE` to carry a provenance mark, which is the one place downstream must know where a declaration came from (the precedent is the `ComputedSelector` term kind, `Dmn/Lower.hs:1152-1165`).
If the mark is missed, the schema publishes `"x-l4-type": "Plot's tenure"`: not a wrong answer, but a silent leak.
The fallback, if that is judged not worth a mark, is to publish the generated name; it changes only when the record or the field is renamed, and both of those already change the published schema.
JSON decoding maps strings to constructors by name and does not change.

**Where the mark lives** (added 2026-10-14). The `ComputedSelector` precedent lives in `resolvedInfo`, and `Serialise Anno` keeps only `pmSynthetic` (`Syntax.hs:1817-1819` on origin/unstable `8c45e2a0a`).
The comment above `Extension` there says jl4-service no longer caches the checked module through that instance and nothing else uses it, so the mark can live in any field; the build confirms that against `jl4-service` before relying on it.
**Built** (2026-10-14): the mark is the field's own options slot, not a field of `Extension`, for a reason this paragraph did not foresee; see §9.1 item 3.

### 5.11 NLG, the ladder, and the exporters

The exporters read the checked module (fact 8), and the ladder takes a `Module Resolved` too (`Viz/Ladder.hs:86`), so they see an ordinary `DECLARE` and need no change to be correct.
The DMN exporter writes an `itemDefinition` whose `allowedValues` are the constructors (`Dmn/Emit.hs:170`), naming it through `sanitiseId` (`Dmn/Lower.hs:6930`); Catala writes a `declaration enumeration` named by `catUpper` of the type's text (`Catala/Lower.hs:2282-2284`); docassemble writes `datatype: radio` with the constructors as choices (`Docassemble/IR.hs:117`, `Emit.hs:226-233`), which is already per field; OpenFisca writes `class <name>(Enum)` (`OpenFisca/Emit.hs:48`).
Each receives a type name with an apostrophe and a space in it, as 69 existing type names already do.
Run by the skeptic on a hand-lifted probe (2026-10-14): Catala gives `PlotSTenure`; DMN gives `name="Plot_s_tenure" label="Plot's tenure"`; docassemble asks per field and never shows the type name; Blawx gives `plot_s_tenure`; OpenFisca fails for an unrelated reason, lifted or not.
`l4 nlg` and the ladder print no type names.

**`l4 render` does show the generated name**, and is the one consumer that must change: on the lifted probe it prints "Plot's tenure means one of Owner, Tenant, or Lodger." as a defined term, "tenure — Plot's tenure" under the record, and "the plot's tenure is Tenant" in the provisions, so a defined term and a projection phrase sit side by side.
The build makes `Export/Document.hs` read the provenance mark, list the options under the field ("tenure — one of Owner, Tenant, or Lodger"), and print no defined term for the lifted type, pinned by a render golden.
As built, that holds for a record's stored fields only (§9.1 item 8).

**The precedent has the same hole today.** `l4 render --include-unused jl4/examples/ok/computed-fields.l4` lists `name`, `birth year` and `as at year` under `Person` and drops `age`, `adult`, `minor` and `category` (re-run 2026-10-14 on `~/.local/bin/l4`), because the "computed as" branch in `Export/Document.hs` cannot fire on a desugared record and `isComputedSelector` hides the selector by a name test.
That is a separate defect, and this build does not fix it.

### 5.12 Constructor-name collisions

Inline constructors join the module's constructor namespace exactly as declared ones do; inlining a list adds no collision that its `DECLARE` did not already have.
Resolution is by type (fact 3), and for a field's options the type is nearly always known: `Plot WITH tenure IS Owner`, `CONSIDER p's tenure`, `p's tenure EQUALS Owner`.
A bare use with no type context is the existing loud error, and it will read better than it does today: p6 shows the current message saying "of type Tenure" for both of two section-local `Tenure`s, where the generated names would differ.
The risk to watch is behavioural: an easy inline form may encourage many small lists with generic constructors (`Yes`, `No`, `Unknown`), which raises how often a bare use is ambiguous.

### 5.13 What a first-time reader sees

`` `tenure` IS ONE OF Owner, Tenant, Lodger `` uses the three words they learned for `DECLARE … IS ONE OF`, in the place where they expect the field's type.
They will stumble in three places, and the user page has to meet each:
trying the same thing in a `GIVEN`, which gets the §5.1 message;
meeting `` `Plot's tenure` `` for the first time in an error message, which the page must explain;
and wanting a rule to take the options as an input, for which the page shows both routes (§5.9).
The page goes under `doc/reference/` with a `doc/SUMMARY.md` link in the shipping PR (CLAUDE.md §6), and is written for the audience in `doc/STYLE.md`.

## 6. The seven GIVETH findings, in field position

1. **"A one-line `DECLARE` already exists, so the benefit is one keyword and one newline."**
   Conceded for B, which saves exactly that.
   Does not transfer to C, which removes the type name at both of its sites and the `DECLARE … IS` (65 characters per candidate on average), and puts the options on the field; it does not remove an invented name (§3.4).
   The size of the prize is still small: 147 sites.
2. **"Sharing disqualifies"; 1 of 162 qualified.**
   Holds in kind and differs in size.
   147 of 2,988 enums qualify (4.9%), and the 385 that also appear in a rule's signature are disqualified for C exactly as the GIVETH review predicted.
3. **"The type must be module-visible anyway, so the change is layout, not semantics."**
   Conceded for B.
   Mostly conceded for C: the constructors must be module-visible to be used at all, so C encapsulates nothing a caller can feel.
   What it removes is a type name from the namespace and from the page, which is layout with one consequence: a rule can depend on the type only by writing the generated name.
4. **"`@desc` parity is unsolved."**
   Does not transfer.
   Field position has its own slot, the field's `@desc`, which the schema already prefers (fact 10), and constructors keep their `@nlg` lines; what remains is resolver work (§5.4).
5. **"Two ways to say one thing."**
   Conceded, permanently.
   The mitigation is only that both ways use the same words, `IS ONE OF`.
6. **"A synthetic name leaks into the public API through `x-l4-type`."**
   Answered by not publishing it (§5.10), and weaker even if published: the name is built from two names that are already the API (the record's `x-l4-type` and the property key), so it changes only when the API already does.
   In GIVETH position there was no such pair to build it from.
7. **"C++ bans types in return and parameter types."**
   Does not transfer, and the same compiler shows why.
   C++ allows a named enum as a class member, scoped to the class and named from outside as `Plot::Tenure` (`inline-one-of-field/probes/member.cc`, clang++ -std=c++20), and an unnamed one, named by its place as `decltype(Plot::tenure)` (`inline-one-of-field/probes/unnamed.cc`), which is option C; while it rejects the GIVETH case: "'E' cannot be defined in the result type of a function" (`inline-one-of-field/probes/ret.cc`).
   C allows it too, but the tag and the enumerators leak to file scope (`inline-one-of-field/probes/member.c`), so a second struct's `OWNER` is "redefinition of enumerator" (`inline-one-of-field/probes/clash.c`).
   The language the review cited draws its line exactly between GIVETH position and field position.
8. **GIVETH-MULTIPLE: no naming scheme is "simultaneously stable, collision-free and readable"** (`specs/proposals/GIVETH-MULTIPLE-RESULTS-SPEC.md:11`). Added 2026-10-14; version 1 answered only the seven GIVETH-INLINE findings.
   It partly re-bites.
   Stable: yes, the name changes only when the record, enum, constructor or field is renamed, and each of those already changes the API.
   Collision-free: version 1's payload rule was not. Two enums may share a constructor (fact 3), so `Holding`'s `Lease HAS term …` and `Interest`'s `Lease HAS term …` both lifted to `` `Lease's term` ``, a loud "There are multiple definitions for the identifier `Lease's term`" at a name the author never wrote (skeptic probes `inline-one-of-field/skeptic/p/q4-sharedpayload.l4` and `q5-sharedpayload-ok.l4` beside it, re-run 2026-10-14).
   This version names a payload enum `<enum>'s <constructor>'s <field>`, and reports any remaining clash, such as a hand-written `` DECLARE `Plot's tenure` `` beside an inline `tenure` on `Plot`, at the field, naming the generated type.
   Readable: no, in this corpus's house style (§3.4), which is why the page advises a `DECLARE` wherever the name will be read.

## 7. Recommendation, and the case for the status quo

**Recommended: C, scoped as follows.**

- `ONE OF` may be the whole type of a record field or of a constructor's payload field, and nowhere else: not under `LIST OF` or `MAYBE`, not in `GIVEN`, `GIVETH`, `ASSUME` or a synonym, not inside another inline list, not in a record with a type parameter.
- Alternatives may carry fields (L7), and the field may carry `TYPICALLY` (HAIRCUT) and `MEANS`.
- The type is named `` `<record>'s <field>` `` (or `` `<enum>'s <constructor>'s <field>` `` for a payload field), the parts exactly as written, with no article stripping and no plural rule; a clash with an existing name is reported at the field. A new desugaring pass, run before `desugarComputedFields`, lifts it into an ordinary `DECLARE` immediately before the record, in its section, with the field's source range, its `@desc`, and a provenance mark.
- The function schema publishes it with no `x-l4-type`; the module schema writes the `enum` inline; `l4 render` lists the options under the field and prints no defined term for it (§5.11).
- The one-line lookahead fix (§5.1, fact 6) lands first and separately.
- A `doc/reference/` page lands in the same PR.

**Cost, stated beside it:** a parser case, a new field on `TypedName` and its 62 patterns, a desugaring pass, a provenance mark read by two schema writers, an annotation-resolver case, a semantic-token case, error messages, goldens, a user page, and a second spelling forever, for about 4.9% of today's enums.

**What would have to be true for A to win.** Any one of these would settle it for the status quo, and the first two are matters of weight that are Meng's to judge rather than facts I can measure.

1. **One declaration shape is worth more than isomorphism.**
   Under A every type has a `DECLARE <name>` line, so a grep always finds it, for a person or a model orienting in an unfamiliar encoding.
   C keeps that for every named type, but adds types that have no such line.
2. **Inline enums would mostly be a passing state.**
   For every enum whose only home is a field, 2.6 more are also named by a rule (§3.2).
   This is a snapshot, not a history, but if authors inline first and promote later, most uses of C end in a refactor that renames the type in error messages and in the Catala, OpenFisca and DMN outputs, churn that A never has.
3. **The encoders would not use it.**
   73 of the 147 candidates sit in directories named for October 2026 encoding runs (`naive-2026-10`, `legalese-2026-10-*`), so the population that would use C is largely whatever the encoding skill and its pipeline write.
   If they are not taught it, the feature is a dead spelling.
4. **A consumer depends on an enum's `x-l4-type`.**
   The chat-side reader is outside this repository (fact 10).
   If it keys rendering or decoding on an enum's type name, §5.10's omission breaks it, and the fallback publishes a generated name.
5. **`GIVEN` is the real question.**
   964 enums are referenced only once, in one `GIVEN`: nearly six times the field candidates, in the same `name IS type` shape.
   If Meng wants inline `ONE OF` there too, field position alone builds half a feature and should wait for one ruling that covers both.
   If not, a first-time reader who learns it in a field will try it in a `GIVEN` and meet an error.

Against those: C is the only option that writes a field's options on the field, and the only one that makes L4's sums-of-products symmetric in the direction Meng asked about; and by lifting before type checking it is correct in every consumer that reads only the checked module, with the function schema and `l4 render` reading the provenance mark (§5.10, §5.11).
My ranking is C over A, narrowly, on symmetry and locality, with the cost above; if Meng weighs 1 or 2 more heavily than isomorphism, A is the right answer and nothing is lost by keeping it.
B is not worth its spelling, D solves a namespace problem L4 does not have, and E has no corpus.

## 8. What I could not check

- ~~**Nothing was built** when this note was written~~: built on 2026-10-14 on the local branch `feat/inline-one-of` (§9.1).
  The grammar, the lookahead fix, the multi-line `TYPICALLY` layout and every error message in §5.1 now run, each pinned by a test: `jl4/examples/ok/one-line-payload-comma.l4`, `jl4/examples/ok/inline-one-of*.l4`, and one `jl4/examples/not-ok/tc/inline-one-of-*.l4` per row of the §5.1 table.
- **The census is a text heuristic.**
  It follows importer-relative imports within one directory only; it does not follow chains of type synonyms, transitive re-exports, or imports resolved through `JL4_LIBRARY_PATH` or the project root, and it does not see enums declared in libraries outside the two corpora.
  Its positive control passes and a hand check of eight candidates and five near-misses found no error, but that bounds the error rather than ruling it out.
- **Source texts exist for only 24 of version 1's 164 candidates** (and 242 of 2,988 enums), so the "invented name" figure rests on a small sample.
- **The citation comparison** (§3.4) matches comments and `@ref` near each declaration by pattern; it does not know which provision a comment means.
- **What the chat client does with `x-l4-type`** for an enum (fact 10).
  Partly checked by the build: the renderer in this repository, `ts-shared/jl4-client-rpc/render-l4-value.ts`, renders an enum's string value from the schema's `enum` list (`formatString`) and reads `x-l4-type` only for an object (`formatObject`), where a missing one still renders a constructor-wrapped value as the constructor.
  A client outside this repository was not checked.
- ~~How NLG and the ladder print a type name, and the wording of the non-exhaustive `CONSIDER` warning~~: checked by the skeptic on 2026-10-14 (§5.7, §5.11).
- **Whether every exporter accepts a type name containing an apostrophe**: the skeptic ran five on one hand-lifted probe (§5.11), and the build ran the same five on an inline field and on its hand-lifted twin, with byte-identical output from each (§9.1); a corpus-wide run has not been done.
- **The census's positive control has no case of a byte-identical module in two directories**, which is the case that produced version 1's error (§3.1). A control for it is owed.
- **Whether an `@nlg` left unclaimed is reported**, and whether `@ref` attaches to a field (§5.4).
  The build settled the case that mattered: an `@nlg` on an inline option's line attaches to that option, one line or several (`jl4/examples/ok/inline-one-of.l4` and its `.nlg.golden`).
  Whether a stray `@nlg` is reported was not looked at.
- **Kotlin, OCaml, C#, Catala and docassemble** could not be run here; their entries in §2 rest on their documentation as quoted.
  No official Kotlin example shows a nested `enum class` named from outside as `Plot.Tenure`; that follows from the specification's "nested classifier type … available under the path PD.ND".

## 9. Skeptic round 1, 2026-10-14: what changed

One fresh Opus skeptic read version 1 against the code and both corpora at the named SHAs. Verdict: **weakens**. Its full reply is `inline-one-of-field/skeptic/reply.md`; the lead re-ran the census at the SHAs (147, 2,424 / 87, 81 / 65 / 1, median 4: reproduced), the `q4` and `q5` probes, the lifted probe's `l4 render`, the `computed-fields.l4` render, and read `Serialise Anno` on origin/unstable.

1. **The ranking rested on isomorphism, and the note's own scripts undercut it.** The generated name is built from names the encoder also chose, and for 54 of 147 the type name already equals the field name. _Took:_ all of it. §0, §3.4, option A and C, the ranking and §7 now rest C on symmetry and locality; the readability figures are printed in §3.4. _Not taken:_ stripping articles or applying an English plural rule to the generated name, because a predictable name beats a prettier one.
2. **The lift precedent is not correct by construction.** `l4 render` already drops every computed field, and the `ComputedSelector` mark lives where `Serialise Anno` does not keep it. _Took:_ `Export/Document.hs` becomes a consumer of the mark, pinned by a render golden (§5.11); where the mark lives is now stated (§5.10). _Not taken:_ fixing the computed-field render drop in this build; it is a separate, pre-existing defect.
3. **`<constructor>'s <field>` is not collision-free**, which brings back part of GIVETH-MULTIPLE's naming finding. _Took:_ payload enums are named `<enum>'s <constructor>'s <field>`, a remaining clash is reported at the field, and the finding is §6 item 8.

Fact-check corrections taken: the census figures (§3.1–3.3, §6, §7), the il-07 attribution, 78 lines vs 69 names (fact 4), and §5.7's wording claim. The memory note that repeated version 1's figures was corrected the same day.

### 9.1 What the build changed, 2026-10-14

Option C is built on the local branch `feat/inline-one-of`, cut from origin/unstable `8c45e2a0a`; nothing is pushed.
The `file:line` citations above are to the integration tree named in the header, not to this branch.
Where the build departed from or added to the note, it is listed here, each labelled assumed, not ruled, unless it is a fact found while building.

1. **The comma fix landed first and alone, field side only** (smucclaw/l4-ide#1045).
   A comma between fields counts as a field separator only when a name and `IS` follow it (`L4.Parser.fieldComma`), which fixes fact 6.
   The other direction, a comma between inline options that is followed by a field, has no surface before inline options exist, so it landed with them (`optionComma`), together with the multi-line form of the same test: a line that is a field ends the options.
2. **Which errors are parse errors.**
   The first four rows of the §5.1 table are parse errors raised at `ONE`, by one guard per place a type is read (`TypeSite`, `oneOfGuard`); the parameterised-record row and the clash row are type-check errors, so the rest of the module is still checked.
   `MAYBE ONE OF` needed a second guard after a whole type, because `MAYBE` reads as a complete type with no arguments and the `ONE` is met only once the type is over.
   Assumed, not ruled.
3. **Where the mark lives.**
   The note asked for a provenance mark on the lifted `DECLARE`.
   It lives on the field instead: a field whose options slot (the new fourth field of `MkTypedName`) is `Just` has a lifted type, and after checking that slot holds the lifted declaration's own checked constructors (`L4.Syntax.inlineOptionsTypes`, Note [Inline ONE OF on a field]).
   It is not a field of `Extension`, because an atomId is a hash of `show` of a term whose annotations are all emptied, and `show` of an `Extension` lists every field, so a new field would move every atomId a deployed service has handed out (the reason `Refs` is a newtype, 2026-10-13).
   The `Serialise Anno` question did not arise: the slot is ordinary data, and `jl4-service` compiles stored sources afresh and imports no `Codec.Serialise` (checked on this branch, `DeploymentLoader.hs`).
   Fact, found while building.
4. **The checked field keeps its options.**
   The note said only that the type slot is filled by the desugarer.
   After checking, the field's options slot holds the lifted declaration's checked constructors, carrying the source annotations, and the lifted `DECLARE` is token-free, so semantic tokens and hover meet the options where the author wrote them (`jl4/examples/lsp/semantic-tokens/inline-one-of.l4`, `jl4/examples/lsp/hover/inline-one-of-hover.l4`).
   The type the field refers to has an empty annotation: a range-carrying hole on it emptied the whole checked phase's semantic tokens, because the token walk reached a `Name` with a hole and no child to fill it.
   Assumed, not ruled.
5. **Where going to the definition lands.**
   The lifted `DECLARE` carries the field's range, as §5.8 asked, which is also how the checker finds it again; the generated name carries the range of the field's `ONE OF`, so going to the definition of `` `Plot's tenure` `` from a rule lands on the `ONE OF` (`jl4-core/test/InlineOptionsSpec.hs`).
   Hover on `ONE OF`, or on the type's name in a `GIVEN`, shows `TYPE`; hover on an option shows `` `Plot's tenure` ``, and on the field `` FUNCTION FROM Plot TO `Plot's tenure` `` with the field's `@desc`.
   Assumed, not ruled.
6. **What counts as a clash.**
   §6 item 8 reports "any remaining clash" with an existing name.
   Built: a type of the same name that is as near to the field as the lifted one (the same section-proximity choice name resolution makes) is reported once, at the field, naming the generated type and where the other is declared, and the field takes the lifted type regardless.
   A same-named type in another section is not reported, because the lifted one is the nearer and is what resolution picks.
   One in an imported module is reported, as for any same-named type, because an import is as near as the module's own declarations.
   **Corrected in review round 1** (finding 4): this item first said an imported one was not reported either.
   Assumed, not ruled.
7. **`x-l4-type` is left out wherever the lifted type is published**, including a rule's input that names it (`` GIVEN t IS A `Plot's tenure` ``), not only the field's property.
   The in-repository renderer does not read an enum's `x-l4-type` (§8).
   Assumed, not ruled.
8. **`l4 render` hides only the type lifted from a record's stored field**, whose options it lists under the field.
   The type lifted from a field of a constructor, or from a computed field (`` `status` IS ONE OF Active, Lapsed MEANS … ``), stays an ordinary defined term under its generated name ("Holding's Lease's term means one of Short or Long."), because render shows neither a constructor's fields nor a computed field, and hiding the type left the options nowhere in the document.
   **Revised in review round 1** (finding 2): the build first hid every lifted type, and found a computed field's by matching its lifted `DECLARE` to the field's synthetic `DECIDE`; that matching is gone.
   The schemas are not affected: they do publish a constructor's fields, and treat a type lifted from one exactly as one lifted from a record's field; a computed field is never an input.
   Assumed, not ruled.
9. **Exporters, run on an inline field and on its hand-lifted twin** (one record, one `@export`): DMN, Catala, docassemble and Blawx wrote byte-identical output for the two, and OpenFisca refused both with the same message ("unbound reference `Owner`"), the unrelated failure §5.11 records.
   DMN names the type `Plot_s_tenure` with label "Plot's tenure", Catala `PlotSTenure`, Blawx `plot_s_tenure`; docassemble asks for the field and never shows it.
   `l4 nlg` printed the same text for both.
   `l4 render` differs, as intended: the twin prints "Plot's tenure means one of Owner, Tenant, or Lodger." and "tenure — Plot's tenure", the inline form only "tenure — one of Owner, Tenant, or Lodger".
   The ladder was not run.
10. **Not built:** inline options in a record with a type parameter (refused, as §7 scopes it), in `GIVEN`, and inline records (option E).

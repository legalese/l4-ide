# Negation as Failure Library

Negation-as-failure (NAF) combinators over `MAYBE BOOLEAN`, in the style of Prolog's `\+`, with no new language machinery. Import it into L4 files with `IMPORT` `` `negation-as-failure` `` (the name needs backticks because of the hyphens).

### Location

[jl4-core/libraries/negation-as-failure.l4](https://github.com/legalese/l4-ide/blob/main/jl4-core/libraries/negation-as-failure.l4)

### The three epistemic states

A `MAYBE BOOLEAN` distinguishes three epistemic states, which lets L4 express
negation as failure without any special operator:

| Value        | Reading                                 |
| ------------ | --------------------------------------- |
| `JUST TRUE`  | proven true                             |
| `JUST FALSE` | proven false                            |
| `NOTHING`    | no proof either way (the open question) |

The closed-world assumption -- "absence of proof is failure" -- is exactly
`fromMaybe FALSE`, which this library names `holds`. Its complement is `naf`, and
its open-world dual (defaulting the open question the other way) is `presumed`.

### Functions

| Function     | Signature              | Definition          | `JUST TRUE` | `JUST FALSE` | `NOTHING` |
| ------------ | ---------------------- | -------------------- | ----------- | ------------ | --------- |
| `holds p`    | `MAYBE BOOLEAN → BOOLEAN` | `fromMaybe FALSE p` | `TRUE`      | `FALSE`      | `FALSE`   |
| `naf p`      | `MAYBE BOOLEAN → BOOLEAN` | `NOT (holds p)`     | `FALSE`     | `TRUE`       | `TRUE`    |
| `presumed p` | `MAYBE BOOLEAN → BOOLEAN` | `fromMaybe TRUE p`  | `TRUE`      | `FALSE`      | `TRUE`    |

`naf` succeeds on everything not provably true -- both the refuted (`JUST FALSE`)
and the unknown (`NOTHING`) cases -- mirroring Prolog's `\+`. Choosing the default
is the closed-world / open-world switch: `holds` reads silence as failure (an
obligation left undischarged), while `presumed` reads silence as permission.

```l4
#EVAL holds NOTHING       -- FALSE  (no proof => fails, closed-world)
#EVAL naf NOTHING         -- TRUE   (unprovable => negation succeeds)
#EVAL presumed NOTHING    -- TRUE   (no prohibition => permitted, open-world)
```

### Natural-language rendering

Each combinator carries an `@nlg` annotation, so both the library's own generated
documentation and any rule that calls it (without its own `@nlg` override) read as
plain English:

```l4
GIVEN `filed on time` IS A MAYBE BOOLEAN
GIVETH A BOOLEAN
`in breach` `filed on time` MEANS naf `filed on time`
```

renders as "In breach if filed on time has not been proven true." -- suitable for
citizen-facing wizards and audit-grade explanations, not just source code.

### Worked example

For a runnable demo -- including a legal breach-vs-permission example and an
optional Kleene three-valued lift (`kand` / `kor` / `knot`) that propagates
"unknown" through the connectives -- see
[negation-as-failure-examples.l4](https://github.com/legalese/l4-ide/blob/main/jl4/experiments/negation-as-failure-examples.l4).

**See [negation-as-failure.l4](https://github.com/legalese/l4-ide/blob/main/jl4-core/libraries/negation-as-failure.l4) source for the full library.**

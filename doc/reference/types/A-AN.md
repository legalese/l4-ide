# Type Articles: A, AN

Type articles are small keywords that improve readability in type declarations and expressions. They are syntactically optional but recommended for clarity.

## Keywords

- **A** - Singular article for types
- **AN** - Singular article before vowel sounds

## A / AN

Used in type annotations to improve readability.

### Syntax

```l4
GIVEN name IS A Type
GIVEN name IS AN Type
ASSUME name IS A Type

§ `A section`
    GIVEN name IS A Type
```

### Examples

**Example file:** [articles-example.l4](a-an-example.l4)

```l4
-- "A" before consonant sounds
ASSUME age IS A NUMBER
ASSUME name IS A STRING
GIVEN x IS A NUMBER

-- "AN" before vowel sounds
ASSUME account IS AN Account
GIVEN obj IS AN Object
```

A rule is told some facts about the case in front of it (its **"inputs"**).
`ASSUME` is deprecated as the way to declare one (ruled 2026-09-04) and still
works; a fact supplied afresh for each case now goes in a
[`GIVEN` under its section's heading](../syntax/section-given.md) — a
**"section `GIVEN`"** — where the articles read exactly the same way.

### Rules

- Use **A** before consonant sounds: `A NUMBER`, `A STRING`, `A BOOLEAN`
- Use **AN** before vowel sounds: `AN Account`, `AN Integer`
- Both are syntactically equivalent — the distinction is for readability only

### Note

Field access in L4 uses the genitive (`'s`) syntax:

```l4
DECLARE Person HAS
  name IS A STRING
  age IS A NUMBER

ASSUME john IS A Person

-- Access fields with genitive
DECIDE johnsName IS john's name
DECIDE johnsAge IS john's age
```

See [Syntax: Genitive](../syntax/genitive-example.l4) for details.

## Related Keywords

- **[IS](../syntax/README.md)** - Type assertions
- **[DECLARE](DECLARE.md)** - Type declarations
- **[GIVEN](../functions/GIVEN.md)** - The inputs of a rule

## See Also

- **[Types Reference](../types/README.md)** - Type system documentation

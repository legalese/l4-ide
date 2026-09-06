# `WITH` — supplying arguments by name

Most calls in L4 give their arguments in order:

```l4
GIVEN principal IS A NUMBER
      rate      IS A NUMBER
GIVETH A NUMBER
`interest on` principal `at` rate MEANS principal TIMES rate

#EVAL `interest on` 1000 `at` 0.05        -- 50
```

`WITH` gives them by name instead, in any order:

```l4
#EVAL `interest on` WITH rate IS 0.05, principal IS 1000      -- 50
```

Both spellings call the same definition and mean the same thing. Naming the
arguments is worth the extra words when a call has several inputs of the same
type, or when the reader of the rule would otherwise have to count positions to
know which number is which.

## One style per call

**A call is either entirely positional or entirely named.** There is no mixed
form. Writing a positional argument and then a `WITH` is a parse error:

```l4
#EVAL `interest on` 1000 WITH rate IS 0.05
--                       ^^^^ unexpected WITH
```

The same function may be called positionally at one site and by name at
another. The rule is about a single call, not about the definition.

## Supplying a section `GIVEN`

A [section `GIVEN`](../syntax/section-given.md) declares a name once for a whole
section, and every rule that reads it takes it as an input without saying so.
`WITH` is how a caller supplies one:

```l4
§ `Rates`
    GIVEN `the rate` IS A NUMBER

GIVETH A NUMBER
doubled MEANS `the rate` TIMES 2

GIVETH A NUMBER
quadrupled MEANS doubled TIMES 2

#EVAL doubled     WITH `the rate` IS 5        -- 10
#EVAL quadrupled  WITH `the rate` IS 5        -- 20
```

`quadrupled` never mentions `the rate`. It reads it through `doubled`, so
supplying it at `quadrupled` reaches `doubled` too. This is the one way a section `GIVEN`
is supplied, and it works the same at three kinds of site: a
directive, an ordinary call inside another rule, and a helper's call to a
helper.

A section `GIVEN` can be supplied at a call **only if the rule being called reads it**, directly or
through anything it calls. Naming one it does not read is an error, because
there would be nowhere for the value to go:

```
This call supplies

  `the rate`

but `unrelated` does not read it -- not in its own
body, and not through anything it calls. There is nowhere for the value to
go, so the override would do nothing.
```

### Overriding for part of a rule

Because a `WITH` supplies the input to that call and everything under it, it
is also how a rule asks a question under a different assumption:

```l4
GIVETH A NUMBER
`under the strict reading` MEANS quadrupled WITH `the rate` IS 10
```

Everything `quadrupled` reaches sees `10`. Everywhere else in the module the
input is unchanged. `LET` does not do this: a `LET` binds a name for the
expression it encloses and never reaches inside a definition that expression
calls.

### Naming one input does not mean naming them all

A `WITH` names only what it is overriding. Every other section `GIVEN` the rule reads
keeps flowing from wherever it was already coming from — the enclosing rule's
own supply, a default, or the request at the entry point.

The rule's own inputs are a different matter: because a call is all-named or
all-positional, a site that names a section `GIVEN` must also name every one of the rule's own
inputs.

```l4
GIVEN n IS A NUMBER
GIVETH A NUMBER
bump n MEANS n TIMES `the rate`

#EVAL bump WITH n IS 3, `the rate` IS 5        -- 15
```

## Limits

- **`WITH` binds loosely.** A named argument runs to the next comma or to the
  end of the line, so `#ASSERT f WITH a IS 3 EQUALS 4` parses as
  `a IS (3 EQUALS 4)`. Put the comparison outside, or parenthesise the value.
- **A misspelt name is an error**, and stays one: if the name is neither a
  input of the rule being called, nor a section `GIVEN` it reads, you are told it
  could not find a definition for it.
- **A `WITH` that names a input the rule reads under two same-spelled
  inputs is an error**, when the name is neither of them. There is no way to
  tell which was meant; rename one of them, or hoist them to a common section
  heading if they are one thing.
- **A rule's own defaulted parameter cannot yet be omitted at a named site.**
  `TYPICALLY` on a _section_ input is honoured when nobody supplies it (see
  [TYPICALLY](../types/TYPICALLY.md)); on a rule's own `GIVEN` the checker still
  asks for the input.

## Example

Every call on this page, in one file you can run:

[with-example.l4](with-example.l4)

## See also

- [The section `GIVEN`](../syntax/section-given.md) — declaring an input once
  for a whole section
- [`GIVEN`](GIVEN.md) — a signature for one definition
- [`LET`](LET.md) and [`WHERE`](WHERE.md) — local definitions, which do not
  reach into the rules a definition calls
- [`TYPICALLY`](../types/TYPICALLY.md) — a default for an input nobody supplies

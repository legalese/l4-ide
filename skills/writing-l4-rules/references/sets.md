# Sets: `SET OF a`

Prelude-provided (after `IMPORT prelude`). Backed by `LIST OF a`; order and duplicates are
irrelevant to all observers. Motivation: legal _and_ is type-ambiguous — "residents of NY
**and** NJ" is a **union of people**; "cruel **and** unusual" is a **conjunction of
conditions**. L4 splits the two by **spelling**: term-level union is written `UNION`; `AND`
is boolean conjunction only. (Until 2026-07-28 the prelude overloaded `AND`/`OR` on sets to
mean union; the overloads were removed — SET-OPERATORS-SPEC §16. **Always write `UNION`**:
it is correct in every tree, before and after the removal. The typechecking blow-up that
forced the removal has since been fixed, so whether the overloads ever return is now a
semantic question rather than a performance one — `doc/reference/libraries/sets.md` carries
the current account.)

## Vocabulary

```l4
`nyers` MEANS setFromList (LIST "alice", "bob")     -- dedups; the normal constructor
x `is in` s            -- membership
p `is subset of` q
p `set equals` q       -- extensional equality; ALWAYS use this, never bare EQUALS
p UNION q              -- bare word, works today
p INTERSECT q          -- bare word
p `LESS` q             -- MUST be backticked: bare LESS is the LESS THAN keyword
p WITHOUT q            -- bare alias for `LESS`
setSize s / setToList s / emptySet
```

## Overloads (type-dispatched magic names)

- `p PLUS q` = union, `p MINUS q` = difference — **bare AND precedence-correct** (they ride
  the arithmetic table): `a PLUS b MINUS c` needs no parens. But sets are a join
  semilattice, not a group: `(A PLUS B) MINUS B ≠ A`.
- `p AND q` / `p OR q` on sets = **type error since 2026-07-28** (on older trees they
  resolve to union). Write `UNION` — never generate `AND`/`OR` between sets.
- `p EQUALS q` = **compile-time ambiguity error, on purpose** ("multiple definitions for
  `__EQUALS__`"). Structural equality is order-sensitive and silently wrong for sets, so L4
  refuses to guess. Write `` `set equals` ``.

## Gotchas (things an LLM will get wrong)

1. **Never write bare `EQUALS` between sets** — it errors. `` `set equals` `` instead.
2. **`LESS` needs backticks** at definition and call sites; or use `WITHOUT`.
3. **Word operators have no precedence** — parenthesize `A UNION (B INTERSECT C)`.
   Only `PLUS`/`MINUS` chains work unparenthesized.
4. **The quotient is one level deep.** Inner sets (`SET OF SET OF a`) and sets wrapped in
   records/PAIR/LIST/MAYBE compare **structurally**: `{{1,2}} ∩ {{2,1}} = ∅`, and two
   records with `set equals` fields can be `EQUALS`-unequal, silently. Compare set-valued
   record fields field-wise with `` `set equals` ``.
5. **Field name is `elements`** (`s's elements`), not `contents` (that's `Dictionary`).
6. Two construction idioms, equivalent for 2+ elements: `setFromList (LIST x, y, z)` and
   the variadic `SET OF x, y, z`. Two boundary traps: (a) `SET OF` needs 2+ args —
   `SET OF "carol"` is a TYPE ERROR (one arg is read as the contents list); use
   `setFromList (LIST "carol")` for a singleton. (b) A single list arg is literal:
   `SET OF LIST 1, 2` = `{1, 2}` (the list IS the contents), not a set containing a list.
7. Deontic fence: a `SET OF Party` in the party position of an obligation has **no defined
   distribution semantics** yet (joint? several? each?). Do not write it expecting meaning.

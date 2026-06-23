## Prelude Libarary

The prelude can be imported into every L4 program with `IMPORT prelude` and provides foundational functions for working with lists, Maybe types, Booleans, and more.

### Location

[jl4-core/libraries/prelude.l4](https://github.com/legalese/l4-ide/blob/main/jl4-core/libraries/prelude.l4)

### Key Functions

#### List Functions

**Construction and Deconstruction:**

- `null` - Check if list is empty
- `reverse` - Reverse a list
- `replicate` - Create list of n copies
- `range` - Generate numeric range

**Transformation:**

- `map` - Apply function to each element
- `filter` - Keep elements matching predicate
- `count` - Count number of elements in a list
- `take` - First n elements
- `drop` - All but first n elements
- `takeWhile` / `dropWhile` - Conditional take/drop

**Combination:**

- `append` - Concatenate two lists
- `concat` - Flatten list of lists
- `zip` / `zipWith` - Combine two lists
- `partition` - Split by predicate

**Aggregation:**

- `foldr` / `foldl` - Fold (reduce) a list
- `sum` - Sum of numbers
- `product` - Product of numbers
- `maximum` / `minimum` - Largest/smallest element
- `and` / `or` - Logical aggregation
- `all` / `any` - Check if all/any satisfy predicate

**Searching:**

- `elem` - Check if element is in list
- `at` - Get element at index
- `lookup` - Find value by key in association list

**Sorting:**

- `sort` - Sort numbers
- `sortBy` - Sort with custom comparator
- `insertBy` - Insert maintaining order

**Uniqueness:**

- `nub` / `nubBy` - Remove duplicates
- `delete` / `deleteBy` - Remove element

#### Maybe Functions

- `isJust` / `isNothing` - Check Maybe status
- `fromMaybe` - Extract with default
- `maybe` - Fold over Maybe
- `orElse` - Alternative Maybe
- `mapMaybe` - Filter map
- `catMaybes` - Extract all JUST values
- `asum` / `firstJust` - First successful Maybe
- `maybeToList` / `listToMaybe` - Convert between Maybe and List
- `holds` - Negation-as-failure grounding for `MAYBE BOOLEAN`: `NOTHING` defaults to `FALSE` (closed-world)
- `naf` - Negation as failure: succeeds when a proposition is not provably true
- `presumed` - Open-world dual of `holds`: `NOTHING` defaults to `TRUE` ("not forbidden ⇒ permitted")

#### Negation as Failure (`MAYBE BOOLEAN`)

A `MAYBE BOOLEAN` distinguishes three epistemic states, which lets L4 express
negation as failure in the style of Prolog without any special operator:

| Value        | Reading                                 |
| ------------ | --------------------------------------- |
| `JUST TRUE`  | proven true                             |
| `JUST FALSE` | proven false                            |
| `NOTHING`    | no proof either way (the open question) |

The closed-world assumption -- "absence of proof is failure" -- is exactly
`fromMaybe FALSE`, which the prelude names `holds`. Its complement is `naf`, and
its open-world dual (defaulting the open question the other way) is `presumed`:

| Combinator   | Definition          | `JUST TRUE` | `JUST FALSE` | `NOTHING` |
| ------------ | ------------------- | ----------- | ------------ | --------- |
| `holds p`    | `fromMaybe FALSE p` | `TRUE`      | `FALSE`      | `FALSE`   |
| `naf p`      | `NOT (holds p)`     | `FALSE`     | `TRUE`       | `TRUE`    |
| `presumed p` | `fromMaybe TRUE p`  | `TRUE`      | `FALSE`      | `TRUE`    |

`naf` succeeds on everything not provably true -- both the refuted (`JUST FALSE`)
and the unknown (`NOTHING`) cases -- mirroring Prolog's `\+`. Choosing the default
is the closed-world / open-world switch: `holds` reads silence as failure (an
obligation left undischarged), while `presumed` reads silence as permission.

```l4
#EVAL holds NOTHING       -- FALSE  (no proof => fails, closed-world)
#EVAL naf NOTHING         -- TRUE   (unprovable => negation succeeds)
#EVAL presumed NOTHING    -- TRUE   (no prohibition => permitted, open-world)
```

For a runnable worked example -- including an optional Kleene three-valued lift
(`kand` / `kor` / `knot`) that propagates "unknown" through the connectives -- see
[negation-as-failure.l4](https://github.com/legalese/l4-ide/blob/main/jl4/experiments/negation-as-failure.l4).

#### Either Functions

- `either` - Fold over Either

#### Pair Functions

- `pmap` / `mapSnd` - Map over second element
- `fmap` / `mapPairs` - Map over list of pairs

#### Dictionary Functions

**Construction:**

- `emptyDict` - Create empty dictionary
- `singleton` / `singleToDict` - Single key-value entry
- `pairToDict` - From pair
- `listToDict` / `fromList` - From association list
- `fromListGrouped` - Group values by key

**Query:**

- `dictLookup` - Find value by key
- `dictMember` / `dictNotMember` - Check key existence
- `dictFindWithDefault` - Lookup with default
- `dictKeys` - All keys
- `dictElems` - All values
- `dictToList` - Convert to association list
- `dictSize` - Number of entries
- `dictIsEmpty` - Check if empty

**Modification:**

- `dictInsert` - Add or update entry
- `dictInsertWith` - Insert with combining function
- `dictDelete` - Remove entry
- `dictAdjust` - Modify value at key
- `dictUpdate` - Modify or delete

**Combination:**

- `dictUnion` - Merge dictionaries
- `dictUnionWith` - Merge with combining function

**Higher-Order:**

- `mapDict` - Map over values
- `dictMapWithKey` - Map with key access
- `filterDict` - Filter by value predicate
- `dictFilterWithKey` - Filter by key-value predicate
- `foldrDict` / `foldlDict` - Fold over values
- `dictFoldrWithKey` / `dictFoldlWithKey` - Fold with keys

**Grouping:**

- `insertValue` - Insert into grouped pairs
- `groupPairs` - Group flat pairs by key

#### Utility Functions

- `id` - Identity function
- `const` - Constant function
- `even` / `odd` - Number parity
- `max` / `min` - Maximum/minimum of two values
- `TBD` - Polymorphic placeholder

### Example: Using Prelude Functions

[prelude-example.l4](prelude-example.l4)

**See [prelude.l4](https://github.com/legalese/l4-ide/blob/main/jl4-core/libraries/prelude.l4) source for all functions.**

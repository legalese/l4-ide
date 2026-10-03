# Specification: Runtime Input State Model

**Status:** PARTLY BUILT, IN A DIFFERENT SHAPE (re-audited 2026-10-04 on `feat/typically-w10`, which stacks W2 to W7 of `TYPICALLY-ONE-BEHAVIOUR-SPEC.md` on `unstable`; those are not merged into `unstable`, by the local refs of that day).
This spec depends on `TYPICALLY`, which is operational (`TYPICALLY-DEFAULTS-SPEC.md`, status header).
**What exists is the four cells, not the types and the API this spec sketches.**
The cells are decided in one function, `L4.Presumption.fillDecision` (`jl4-core/src/L4/Presumption.hs`, W2 and W3): an input or a field is `Absent` (the key is not there), `SuppliedNull` (not known) or `Supplied v`, and whether it has a default is a separate argument.
On the wire a missing key is `Left`, `null` is `Right Nothing` ("I don't know": never the default, an error naming the fact at the boundary), `{}` is read as `null` (`FnUncertain`, `jl4-service/src/Backend/Api.hs`), and a value is `Right (Just v)`.
`TYPICALLY-ONE-BEHAVIOUR-SPEC.md` §5 (T3) is the current statement of that table and §4.1 says how it is built.
The ladder keeps the `Left` cell as its own map, `ViewSpec.defaults`, beneath the user's answers, with `respectDefaults` to withdraw the presumptions (`ts-shared/ladder-core/src/types.ts`).
**Not built:** `WithDefault`, `InputState`, `L4.Runtime.InputState` and `initSession` (no `*.hs`, `*.ts`, `*.svelte`, `*.cabal` or `*.yaml` file in the tree mentions `InputState`, `WithDefault`, `initSession`, `NotProvided` or `explicitUnknown` as a word; searched 2026-10-04, and the one hit for this spec's `SessionState` is an unrelated type in `ts-shared/legalese-agent`); the `{"_notProvided": true}` marker, the `explicitUnknowns` list and the `inputResolution` response of "API Design" (the service answers with `presumed`, the inputs that took their default and were read, in place of `inputResolution`); and the resolution to three-valued logic (`TriBool`, "Integration with Three-Valued Logic": no `.hs` file mentions it; an unknown input stops the case, refused by name at the boundary, and on the service's wrapper path a missing boolean is an assumed term that stops the answer only if the rules read it; `UNKNOWN-EVALUATION-SPEC.md` specifies three-valued evaluation, and its own status header, 2026-10-01, says not built).
The fourth state of the summary, "not applicable", is not modelled.
`initializeInputState` evaluates "a literal"; a default is now a literal or an expression (`TYPICALLY-ONE-BEHAVIOUR-SPEC.md` §4.3).
**The body below is the December 2025 design, kept for its reasoning, and is not a description of the tree.**
**Related:** `TYPICALLY-DEFAULTS-SPEC.md` (compile-time defaults), `BOOLEAN-MINIMIZATION-SPEC.md` (partial evaluation), `doc/default-values.md` (conceptual background; deleted in `a3f56bdc7`, so the file is not in the tree)

> **⚠️ IMPLEMENTATION STATUS: PARTLY BUILT, SEE THE STATUS ABOVE**
>
> `TYPICALLY` is operational (`TYPICALLY-DEFAULTS-SPEC.md`), and what of this model has been built is above.
> The specification below remains a design document.

## Executive Summary

Interactive applications (chatbots, web forms, decision services) need to track **four distinct states** for each input parameter:

1. **Explicit value** - User provided a concrete answer
2. **Explicit unknown** - User said "I don't know"
3. **Not yet asked** - No user input yet (may use TYPICALLY default)
4. **Not applicable** - Question doesn't apply in this context

This spec defines the `Either (Maybe a) (Maybe a)` runtime representation and how it integrates with TYPICALLY defaults from compile-time.

## Motivation

### The Problem

Consider a chatbot collecting information for an alcohol purchase decision:

```
Chatbot: Are you married?
```

The user might:

1. Say "Yes" → we know they're married
2. Say "No" → we know they're unmarried
3. Say "I don't know" / "I'd rather not say" → explicit uncertainty
4. Not answer yet (chatbot hasn't asked) → no input

These are **four different states**, but a simple `Maybe Bool` only gives us two (value or nothing).

### Why It Matters

| State                    | With `Maybe Bool` | What Should Happen                         |
| ------------------------ | ----------------- | ------------------------------------------ |
| User says "Yes"          | `Just True` ✓     | Use `True`                                 |
| User says "No"           | `Just False` ✓    | Use `False`                                |
| User says "I don't know" | `Nothing` ✗       | Propagate as Unknown in three-valued logic |
| Not yet asked            | `Nothing` ✗       | Use TYPICALLY default if available         |

With `Maybe Bool`, we can't distinguish "I don't know" from "not asked". This matters because:

- "Not asked" → use TYPICALLY default → may resolve the decision
- "I don't know" → truly Unknown → may require asking other questions

## The Four-State Model

### Type Definition

```haskell
-- | Runtime state for a single input parameter
--
-- Left branch: No user input yet
--   Left Nothing      = No user input, no compile-time default
--   Left (Just v)     = No user input, has TYPICALLY default of v
--
-- Right branch: User has provided input
--   Right Nothing     = User explicitly said "I don't know"
--   Right (Just v)    = User explicitly provided value v
--
type WithDefault a = Either (Maybe a) (Maybe a)
```

### State Diagram

```
                    ┌─────────────────────────────────────┐
                    │         WithDefault a               │
                    └─────────────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │                               │
              Left (Maybe a)                  Right (Maybe a)
           "No user input yet"              "User has responded"
                    │                               │
            ┌───────┴───────┐               ┌───────┴───────┐
            │               │               │               │
      Left Nothing    Left (Just v)   Right Nothing   Right (Just v)
      "No default"    "TYPICALLY v"   "I don't know"  "Explicit v"
```

### State Transitions

```
Initial state (from L4 compile):
  - Has TYPICALLY → Left (Just defaultValue)
  - No TYPICALLY  → Left Nothing

User provides input:
  - User says value v    → Right (Just v)
  - User says "I don't know" → Right Nothing

User clears input (resets to default):
  - Back to Left branch with original default
```

### Resolution to Three-Valued Logic

When evaluating, resolve `WithDefault Bool` to `TriBool`:

```haskell
resolve :: WithDefault Bool -> TriBool
resolve (Right (Just True))  = TTrue      -- User said true
resolve (Right (Just False)) = TFalse     -- User said false
resolve (Right Nothing)      = TUnknown   -- User said "I don't know"
resolve (Left (Just True))   = TTrue      -- Using TYPICALLY TRUE
resolve (Left (Just False))  = TFalse     -- Using TYPICALLY FALSE
resolve (Left Nothing)       = TUnknown   -- No input, no default
```

## Integration with TYPICALLY

### Compile-Time → Runtime

When loading a function for interactive use:

```haskell
-- From TYPICALLY-DEFAULTS-SPEC: compile-time defaults
getDefaults :: Decide Resolved -> Map Text (Expr Resolved)

-- Initialize runtime state from compile-time defaults
initializeInputState :: Map Text (Expr Resolved) -> Map Text (WithDefault Value)
initializeInputState defaults = Map.mapWithKey toInitialState allParams
  where
    toInitialState name _ = case Map.lookup name defaults of
      Just expr -> Left (Just (evalLiteral expr))  -- Has TYPICALLY
      Nothing   -> Left Nothing                     -- No TYPICALLY
```

### Example

```l4
GIVEN
  age IS A NUMBER
  married IS A BOOLEAN TYPICALLY FALSE
  has_approval IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE foo IF ...
```

Initial runtime state:

```haskell
{ "age"          -> Left Nothing        -- No default, not asked
, "married"      -> Left (Just False)   -- TYPICALLY FALSE, not asked
, "has_approval" -> Left Nothing        -- No default, not asked
}
```

After user says age=30:

```haskell
{ "age"          -> Right (Just 30)     -- User provided
, "married"      -> Left (Just False)   -- Still using default
, "has_approval" -> Left Nothing        -- Still not asked
}
```

After user says "I don't know" for married:

```haskell
{ "age"          -> Right (Just 30)     -- User provided
, "married"      -> Right Nothing       -- User said "I don't know"
, "has_approval" -> Left Nothing        -- Still not asked
}
```

## API Design

### Decision Service Request

```json
{
  "arguments": {
    "age": 30,
    "married": null,
    "has_approval": { "_notProvided": true }
  }
}
```

Interpretation:

- `"age": 30` → `Right (Just 30)` - explicit value
- `"married": null` → `Right Nothing` - explicit "I don't know"
- `"has_approval": { "_notProvided": true }` → `Left _` - use default
- Field omitted entirely → `Left _` - use default

### Alternative: Simpler API (Recommended for MVP)

For simpler integration, use field presence:

```json
{
  "arguments": {
    "age": 30
  },
  "explicitUnknowns": ["married"]
}
```

- Present in `arguments` → `Right (Just value)`
- Present in `explicitUnknowns` → `Right Nothing`
- Absent from both → `Left _` (use TYPICALLY if available)

### Response: Tracking What Was Used

```json
{
  "result": true,
  "inputResolution": {
    "age": { "value": 30, "source": "explicit" },
    "married": { "value": false, "source": "typically", "default": false },
    "has_approval": {
      "value": null,
      "source": "unknown",
      "reason": "no input, no default"
    }
  }
}
```

## Implementation

### Core Types

```haskell
module L4.Runtime.InputState where

import Data.Map (Map)

-- | The four states for a runtime input
data InputState a
  = NotProvided (Maybe a)   -- Left branch: (Maybe default)
  | Provided (Maybe a)      -- Right branch: (Maybe explicit value)
  deriving (Eq, Show, Functor)

-- | Equivalent to Either (Maybe a) (Maybe a), but with clearer names
type WithDefault a = InputState a

-- | Smart constructors
notAsked :: InputState a
notAsked = NotProvided Nothing

withDefault :: a -> InputState a
withDefault v = NotProvided (Just v)

explicit :: a -> InputState a
explicit v = Provided (Just v)

explicitUnknown :: InputState a
explicitUnknown = Provided Nothing

-- | Check if user has provided any input
hasUserInput :: InputState a -> Bool
hasUserInput (Provided _)    = True
hasUserInput (NotProvided _) = False

-- | Get the effective value (if determinable)
effectiveValue :: InputState a -> Maybe a
effectiveValue (Provided (Just v))    = Just v   -- Explicit value
effectiveValue (Provided Nothing)     = Nothing  -- "I don't know"
effectiveValue (NotProvided (Just v)) = Just v   -- Using default
effectiveValue (NotProvided Nothing)  = Nothing  -- No input, no default

-- | Get the source of the value
data ValueSource = Explicit | Default | Unknown
  deriving (Eq, Show)

valueSource :: InputState a -> ValueSource
valueSource (Provided (Just _))    = Explicit
valueSource (Provided Nothing)     = Unknown  -- User said "I don't know"
valueSource (NotProvided (Just _)) = Default
valueSource (NotProvided Nothing)  = Unknown  -- No input, no default
```

### Integration with Three-Valued Logic

```haskell
-- | Convert InputState Bool to TriBool for evaluation
toTriBool :: InputState Bool -> TriBool
toTriBool (Provided (Just True))    = TTrue
toTriBool (Provided (Just False))   = TFalse
toTriBool (Provided Nothing)        = TUnknown  -- "I don't know"
toTriBool (NotProvided (Just True)) = TTrue     -- TYPICALLY TRUE
toTriBool (NotProvided (Just False))= TFalse    -- TYPICALLY FALSE
toTriBool (NotProvided Nothing)     = TUnknown  -- No input, no default
```

### Form/Chatbot State Management

```haskell
-- | State for an interactive session
data SessionState = SessionState
  { ssInputs    :: Map Text (InputState Value)
  , ssDefaults  :: Map Text Value  -- From TYPICALLY (immutable)
  , ssAsked     :: Set Text        -- Questions we've asked
  }

-- | Initialize from compiled function
initSession :: Decide Resolved -> SessionState
initSession decide = SessionState
  { ssInputs   = Map.map NotProvided (getDefaults decide)
  , ssDefaults = getDefaults decide
  , ssAsked    = Set.empty
  }

-- | Record user's answer
recordAnswer :: Text -> Maybe Value -> SessionState -> SessionState
recordAnswer param maybeVal ss = ss
  { ssInputs = Map.insert param (Provided maybeVal) (ssInputs ss)
  , ssAsked  = Set.insert param (ssAsked ss)
  }

-- | Reset a parameter to its default
resetToDefault :: Text -> SessionState -> SessionState
resetToDefault param ss = ss
  { ssInputs = Map.insert param
      (NotProvided (Map.lookup param (ssDefaults ss)))
      (ssInputs ss)
  }
```

## Test Cases

### Unit Tests: State Transitions

```haskell
describe "InputState" $ do
  describe "construction" $ do
    it "notAsked has no value" $
      effectiveValue (notAsked :: InputState Bool) `shouldBe` Nothing

    it "withDefault has default value" $
      effectiveValue (withDefault True) `shouldBe` Just True

    it "explicit has explicit value" $
      effectiveValue (explicit False) `shouldBe` Just False

    it "explicitUnknown has no value" $
      effectiveValue (explicitUnknown :: InputState Bool) `shouldBe` Nothing

  describe "valueSource" $ do
    it "explicit value is Explicit" $
      valueSource (explicit True) `shouldBe` Explicit

    it "default value is Default" $
      valueSource (withDefault True) `shouldBe` Default

    it "explicit unknown is Unknown" $
      valueSource (explicitUnknown :: InputState Bool) `shouldBe` Unknown

    it "not asked without default is Unknown" $
      valueSource (notAsked :: InputState Bool) `shouldBe` Unknown

  describe "hasUserInput" $ do
    it "Provided _ has user input" $ do
      hasUserInput (explicit True) `shouldBe` True
      hasUserInput explicitUnknown `shouldBe` True

    it "NotProvided _ has no user input" $ do
      hasUserInput (notAsked :: InputState Bool) `shouldBe` False
      hasUserInput (withDefault True) `shouldBe` False
```

### Unit Tests: Three-Valued Resolution

```haskell
describe "toTriBool" $ do
  it "explicit True -> TTrue" $
    toTriBool (explicit True) `shouldBe` TTrue

  it "explicit False -> TFalse" $
    toTriBool (explicit False) `shouldBe` TFalse

  it "explicit unknown -> TUnknown" $
    toTriBool explicitUnknown `shouldBe` TUnknown

  it "default True -> TTrue" $
    toTriBool (withDefault True) `shouldBe` TTrue

  it "default False -> TFalse" $
    toTriBool (withDefault False) `shouldBe` TFalse

  it "not asked, no default -> TUnknown" $
    toTriBool notAsked `shouldBe` TUnknown
```

### Integration Tests: Session Management

```haskell
describe "SessionState" $ do
  let func = parseAndCheck [l4|
    GIVEN
      x IS A BOOLEAN TYPICALLY TRUE
      y IS A BOOLEAN
    GIVETH A BOOLEAN
    DECIDE foo IF x AND y
    |]

  it "initializes with TYPICALLY defaults" $ do
    let ss = initSession func
    ssInputs ss ! "x" `shouldBe` NotProvided (Just True)
    ssInputs ss ! "y" `shouldBe` NotProvided Nothing

  it "records explicit answer" $ do
    let ss = initSession func
        ss' = recordAnswer "y" (Just (VBool False)) ss
    ssInputs ss' ! "y" `shouldBe` Provided (Just (VBool False))

  it "records 'I don't know'" $ do
    let ss = initSession func
        ss' = recordAnswer "x" Nothing ss
    ssInputs ss' ! "x" `shouldBe` Provided Nothing  -- Overrides default!

  it "resets to default" $ do
    let ss = initSession func
        ss' = recordAnswer "x" (Just (VBool False)) ss
        ss'' = resetToDefault "x" ss'
    ssInputs ss'' ! "x" `shouldBe` NotProvided (Just True)
```

### Integration Tests: API

```haskell
describe "API input parsing" $ do
  it "present value -> Provided (Just v)" $ do
    parseInput "{\"x\": true}" `shouldBe`
      Map.singleton "x" (Provided (Just True))

  it "null value -> Provided Nothing (I don't know)" $ do
    parseInput "{\"x\": null}" `shouldBe`
      Map.singleton "x" (Provided Nothing)

  it "absent field -> NotProvided" $ do
    parseInput "{}" `shouldBe` Map.empty
    -- Absent fields get NotProvided with default during resolution
```

## Edge Cases

### 1. Numeric "I Don't Know"

For non-boolean types, `null` still means "I don't know":

```json
{ "age": null }
```

_User doesn't know their age_

This resolves to `Provided Nothing` regardless of type.

### 2. Nested Records

For nested records like `Person.address.country`:

```json
{
  "person": {
    "address": {
      "country": null // "I don't know the country"
    }
  }
}
```

Each level can independently be:

- Provided with value
- Provided as unknown (null)
- Not provided (use default)

### 3. Lists and Collections

For list inputs, `null` means "I don't know if there's a list":

```json
{ "items": null }      // Don't know
{ "items": [] }        // Explicitly empty list
{ "items": [1, 2, 3] } // Explicit list
```

### 4. Resetting vs. Not Asking

UI should distinguish:

- "Clear my answer" → reset to `NotProvided` (use default)
- "I don't know" → set to `Provided Nothing`

```haskell
clearAnswer :: Text -> SessionState -> SessionState
clearAnswer = resetToDefault  -- Back to NotProvided

answerUnknown :: Text -> SessionState -> SessionState
answerUnknown param = recordAnswer param Nothing  -- Provided Nothing
```

## Relationship to Other Specs

### TYPICALLY-DEFAULTS-SPEC.md

That spec defines **compile-time** defaults. This spec defines how those defaults are **used at runtime**.

```
Compile-time (TYPICALLY):
  "married IS A BOOLEAN TYPICALLY FALSE"
       ↓
  AST: TypedName { tnTypically = Just (Lit False) }
       ↓
Runtime (this spec):
  Initial state: NotProvided (Just False)
       ↓
  After user input: Provided (Just True) or Provided Nothing
```

### BOOLEAN-MINIMIZATION-SPEC.md

Partial evaluation uses `InputState` to determine:

- Which parameters are resolved (have effective values)
- Which parameters need to be asked
- Which parameters are explicitly unknown (can't be resolved by asking)

```haskell
-- For partial evaluation
needsQuestion :: InputState a -> Bool
needsQuestion (NotProvided Nothing) = True   -- No default, not asked
needsQuestion _                     = False  -- Has value or user responded

isExplicitlyUnknown :: InputState a -> Bool
isExplicitlyUnknown (Provided Nothing) = True
isExplicitlyUnknown _                  = False
```

## References

- `doc/default-values.md`: Original conceptual design with `Either (Maybe a) (Maybe a)`
- `TYPICALLY-DEFAULTS-SPEC.md`: Compile-time TYPICALLY keyword
- `BOOLEAN-MINIMIZATION-SPEC.md`: Partial evaluation with unknowns
- [Kleene's three-valued logic](https://en.wikipedia.org/wiki/Three-valued_logic#Kleene_and_Priest_logics)

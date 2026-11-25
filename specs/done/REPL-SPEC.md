# Specification: L4 REPL (Read-Eval-Print Loop)

**Status:** 🚧 In Progress (Phase 1-2 complete, Phase 3 :type + IMPORT done)  
**Issue:** TBD  
**Author:** Claude (with Mengwong)  
**Created:** 2025-06-12  
**Last Updated:** 2025-12-10

## Implementation Status

### Completed (Phase 1 MVP + Phase 2 enhancements)

- ✅ `jl4-repl` package created in `jl4-repl/`
- ✅ Basic REPL loop with `haskeline`
- ✅ `:quit`, `:help`, `:load`, `:reload` commands
- ✅ File loading via command-line argument
- ✅ Expression evaluation using existing infrastructure
- ✅ Uses unique virtual filenames per evaluation (fixes Shake caching)
- ✅ Bare expression evaluation (e.g., `1 + 2`)
- ✅ `#EVAL` directive support
- ✅ `#ASSERT` directive support (with pass/fail reporting)
- ✅ Results displayed using `prettyLayout`
- ✅ Reduced logging verbosity (default: only warnings/errors)
- ✅ `-v/--verbose` flag for debug output
- ✅ Helpful message for `#CHECK` (type-checking only, not evaluation)
- ✅ `:type` / `:t` command for type inference (uses `#CHECK` directive internally)
- ✅ `:import` / `:i` and `IMPORT <lib>` for session imports
- ✅ Directive filtering on file load (comments out `#EVAL`/`#ASSERT` to prevent auto-execution)

### Working Demo

```bash
# Build and run (no stderr spam!)
cabal build jl4-repl
cabal run jl4-repl -- ./jl4-core/libraries/math.l4

# Example session:
jl4> 1 + 2
3
jl4> EULER
2.718281828459045
jl4> #ASSERT 2 EQUALS 2
True (assertion passed)
jl4> #ASSERT 2 EQUALS 3
False (assertion failed)
jl4> #CHECK 2 + 3
#CHECK is for type-checking only (reports inferred type in IDE). Use #ASSERT for runtime checks.
jl4> :help
Available commands:
  :help, :h       Show this help
  :quit, :q       Exit the REPL
  :load <file>    Load an L4 file
  :l <file>       Short for :load
  :reload, :r     Reload the current file
  ...
jl4> :quit
Goodbye!
```

### Known Issues

- Multi-line input not handled
- Tab completion not implemented
- Session-defined bindings not yet supported

### Next Steps (Phase 3)

- Add session-defined bindings (`DECIDE foo IS 42` at prompt)
- Tab completion for names in scope
- Multi-line input handling

## Executive Summary

We propose adding an interactive REPL to the L4 toolchain. The REPL keeps loaded modules in memory, allowing fast iteration on expressions without the overhead of reloading imports on every evaluation. This fills a gap between the batch CLI (`jl4-cli`) and the full IDE experience (VS Code + LSP).

## Motivation

### Current Pain Points

| Interaction Mode | Startup Cost               | Use Case                |
| ---------------- | -------------------------- | ----------------------- |
| `jl4-cli`        | High (reloads all imports) | Batch processing, CI    |
| LSP/IDE          | Medium (initial load)      | Full editing experience |
| Decision Service | High (per-request)         | API endpoints           |

**Problem**: When iterating on L4 expressions—testing a function with different inputs, exploring type behavior, or debugging—the overhead of reloading standard libraries on every invocation creates friction.

### The Opportunity

The LSP already maintains a memory-resident `IdeState` with a `ShakeDatabase` that caches parsed/typechecked modules. A REPL can reuse this architecture to provide:

1. **Fast iteration**: Load libraries once, evaluate many expressions
2. **Interactive exploration**: Try expressions, see results immediately
3. **Learning aid**: Newcomers can experiment without writing full `.l4` files
4. **Debugging**: Isolate and test subexpressions from larger programs

### Target Users

- **L4 developers**: Testing functions during development
- **Legal engineers**: Exploring computation results with different inputs
- **Learners**: Understanding L4 semantics interactively
- **LLM integration**: Providing a fast eval endpoint for AI agents

## Design Goals

1. **Fast startup for loaded context** - After initial load, expression eval should be <100ms
2. **Familiar UX** - Follow conventions from GHCi, Python REPL, etc.
3. **Minimal new code** - Reuse existing parser, typechecker, evaluator
4. **Error resilience** - Bad input shouldn't crash the session
5. **Scriptable** - Support piped input for automation

## Proposed Interface

### Basic Usage

```bash
# Start REPL with standard library
$ jl4-repl
Loading prelude... done (1.2s)
jl4> 2 + 3
5

jl4> "hello" <> " " <> "world"
"hello world"

# Start with a specific file (and its imports)
$ jl4-repl examples/insurance.l4
Loading prelude... done
Loading examples/insurance.l4... done (0.3s)
jl4> premium GIVEN age IS 30 AND smoker IS FALSE
1200.00
```

### Expression Syntax

The REPL accepts:

1. **Bare expressions** (most common):

   ```
   jl4> 2 + 3
   jl4> foo GIVEN x IS 42
   jl4> SOME 5
   ```

2. **Explicit #EVAL** (for consistency with .l4 files):

   ```
   jl4> #EVAL 2 + 3
   jl4> #EVALTRACE factorial 5
   ```

3. **Multi-line input** (using `# ` continuation, matching directive syntax):

   ```
   jl4> someComplexExpression
   # > AND anotherPart
   # > OR finalPart
   120
   ```

4. **Top-level definitions** (session-local):

   ```
   jl4> DECIDE myDouble x IS x * 2
   Defined: myDouble :: NUMBER -> NUMBER

   jl4> myDouble 21
   42
   ```

5. **Pasted program text** (mixed definitions and directives):

   ```
   jl4> DECIDE triple x IS x * 3
   Defined: triple :: NUMBER -> NUMBER

   jl4> #EVAL triple 10
   30

   jl4> #CHECK triple 7 EQUALS 21
   PASS: triple 7 EQUALS 21
   ```

### Multi-Line Input Handling

L4 expressions and definitions often span multiple lines. The REPL must handle this gracefully, especially for pasted content where newlines shouldn't trigger premature submission.

**The problem:**

```l4
-- This is common L4 code that spans multiple lines:
#EVAL computePremium
# GIVEN age IS 30
# AND smoker IS FALSE
# AND coverage IS 100000

-- Or definitions:
GIVEN n IS A NUMBER
GIVETH A NUMBER
DECIDE factorial IS
  IF n EQUALS 0
  THEN 1
  ELSE n * factorial (n - 1)
```

When pasted into a REPL, each newline would normally trigger evaluation, breaking the input.

**Solution: Multi-mode input handling**

The REPL uses multiple strategies to handle multi-line input:

#### 1. Paste Detection (Primary)

Modern terminal UI frameworks distinguish between keyboard input and paste operations at the event level. This is more reliable than escape-sequence parsing.

**Framework options for Haskell:**

| Framework         | Paste Support        | Notes                                   |
| ----------------- | -------------------- | --------------------------------------- |
| `haskeline`       | Bracketed paste mode | Escape-sequence based, widely supported |
| `brick`           | `EvPaste` event type | Direct paste detection via vty          |
| `vty` (low-level) | `EvPaste ByteString` | Raw paste events                        |
| Custom (via FFI)  | Platform-specific    | macOS/Linux clipboard APIs              |

**Recommended: `brick` or `vty`**

The `vty` library (which `brick` builds on) provides direct paste event detection:

```haskell
import Graphics.Vty

handleEvent :: Event -> ReplState -> IO ReplState
handleEvent event state = case event of
  -- Paste arrives as a single event with all content
  EvPaste bytes -> do
    let text = decodeUtf8 bytes
    processPastedContent state text

  -- Regular key press
  EvKey KEnter [] ->
    submitCurrentLine state

  EvKey (KChar c) [] ->
    appendChar state c

  _ -> pure state

-- Pasted content is processed as a unit, not line-by-line
processPastedContent :: ReplState -> Text -> IO ReplState
processPastedContent state pastedText = do
  let blocks = splitIntoLogicalBlocks pastedText
  foldM processBlock state blocks
```

**Alternative: `haskeline` with bracketed paste**

If using `haskeline` (simpler but less control), enable bracketed paste mode:

```haskell
import System.Console.Haskeline

settings :: Settings IO
settings = defaultSettings
  { historyFile = Just "~/.jl4_history"
  , autoAddHistory = True
  }

-- haskeline handles bracketed paste internally when supported
-- Multi-line paste arrives as single getInputLine result
```

**Why this matters:**

| Input Method            | What Happens                                         |
| ----------------------- | ---------------------------------------------------- |
| Type `foo` + Enter      | `EvKey KEnter` → submit "foo" immediately            |
| Paste `foo\nbar\nbaz`   | `EvPaste "foo\nbar\nbaz"` → process as unit          |
| Type `foo`, paste `bar` | `EvKey` × 3, then `EvPaste "bar"` → correct handling |

This means:

- **Typed newlines** = submit immediately
- **Pasted newlines** = soft line breaks within a block

#### 2. Continuation Detection (Interactive)

For interactive (non-pasted) input, the REPL detects incomplete expressions and prompts for continuation:

**Incomplete indicators:**

- Unclosed brackets: `(`, `[`, `{`
- Trailing operators: `AND`, `OR`, `+`, etc.
- Continuation marker: line starting with `# `
- Indented continuation (for definitions)

```
jl4> computePremium GIVEN age IS 30
...>   AND smoker IS FALSE
...>   AND coverage IS 100000
1500.00
```

The `...>` prompt indicates the REPL is waiting for more input.

```haskell
data InputState
  = Complete Text                    -- Ready to evaluate
  | Incomplete Text ContinuationReason  -- Need more input

data ContinuationReason
  = UnclosedBracket Char             -- ( [ {
  | TrailingOperator Text            -- AND, OR, +, etc.
  | ContinuationMarker               -- Line starts with #
  | IndentedBlock                    -- Definition with indented body
  | ExplicitContinuation             -- User typed :{

detectIncomplete :: Text -> InputState
detectIncomplete input =
  case (hasUnclosedBrackets input, hasTrailingOperator input, endsWithContinuation input) of
    (Just c, _, _)     -> Incomplete input (UnclosedBracket c)
    (_, Just op, _)    -> Incomplete input (TrailingOperator op)
    (_, _, True)       -> Incomplete input ContinuationMarker
    _ | looksLikeIncompleteDefinition input -> Incomplete input IndentedBlock
    _                  -> Complete input
```

#### 3. Explicit Multi-Line Mode (GHCi-style)

For complex cases, support explicit multi-line delimiters:

```
jl4> :{
...> GIVEN n IS A NUMBER
...> GIVETH A NUMBER
...> DECIDE factorial IS
...>   IF n EQUALS 0
...>   THEN 1
...>   ELSE n * factorial (n - 1)
...> :}
Defined: factorial :: NUMBER -> NUMBER
```

#### 4. Block Separation for Pasted Content

When processing pasted content with multiple logical blocks, use blank lines as separators:

```
-- Pasted content (all at once):
DECIDE foo IS 42

#EVAL foo + 1

DECIDE bar IS foo * 2

#CHECK bar EQUALS 84
```

This is processed as four separate blocks:

1. Definition of `foo`
2. Evaluation of `foo + 1`
3. Definition of `bar`
4. Check of `bar EQUALS 84`

```haskell
-- Split pasted content into blocks
splitOnBlankLines :: Text -> [Text]
splitOnBlankLines =
  filter (not . Text.null . Text.strip)
  . Text.splitOn "\n\n"

-- Process blocks sequentially, accumulating state
processBlocks :: ReplState -> [Text] -> IO (ReplState, [Text])
processBlocks state [] = pure (state, [])
processBlocks state (block:rest) = do
  (output, state') <- processBlock state block
  (state'', outputs) <- processBlocks state' rest
  pure (state'', output : outputs)
```

#### Summary: Input Mode Decision Tree

```
Terminal Event
    │
    ├─ EvPaste event? (Cmd-V / Ctrl-V)
    │   └─ YES → Process entire paste as unit
    │            Split on blank lines into blocks
    │            Process each block sequentially
    │
    ├─ EvKey KEnter? (keyboard Enter)
    │   │
    │   ├─ Current input starts with ":{"?
    │   │   └─ YES → Accumulate until ":}", then process
    │   │
    │   ├─ Current input incomplete?
    │   │   ├─ Unclosed bracket → Show "...>" prompt, accumulate
    │   │   ├─ Trailing operator → Show "...>" prompt, accumulate
    │   │   ├─ Next line starts with "# " → Append, continue
    │   │   └─ Indented (for defs) → Show "...>" prompt, accumulate
    │   │
    │   └─ Complete expression
    │       └─ Process immediately
    │
    └─ EvKey (KChar c)? (regular typing)
        └─ Append to input buffer, update display
```

**Key insight:** The distinction between "paste" and "type Enter" is made at the **event level**, not by timing heuristics or escape sequences. Modern terminal libraries provide this directly.

**Cross-platform note:** This event-based approach works consistently across:

- macOS Terminal, iTerm2
- Linux (GNOME Terminal, Konsole, Alacritty)
- Windows Terminal, ConEmu
- tmux, screen (with proper passthrough)

**Implementation note:** For Haskell, `brick`/`vty` provide the cleanest event model. For a Go implementation (e.g., if integrating with Charm's Bubble Tea ecosystem), `tea.Msg` includes `tea.PasteMsg` for this purpose. The architecture should abstract over the event source so the core REPL logic is framework-agnostic.

### Input Preprocessing

The REPL uses a preprocessing step to determine input type, allowing users to paste code directly from `.l4` files without modification. This is critical for copy-paste workflows between editor and REPL.

**Classification logic:**

```
Input                          → Classification      → Action
─────────────────────────────────────────────────────────────────
":"                            → REPL command        → dispatch to command handler
"#EVAL <expr>"                 → Eval directive      → evaluate <expr>, show result
"#EVALTRACE <expr>"            → Trace directive     → evaluate with trace output
"#CHECK <expr>"                → Check directive     → evaluate, show PASS/FAIL
"#ASSERT <expr>"               → Assert directive    → evaluate, error if FALSE
"#CONTRACT ..."                → Contract directive  → run contract simulation
"DECIDE ..." / "MEANS ..."     → Definition          → add to session bindings
"ASSUME ..."                   → Assumption          → add to session context
"DECLARE ..."                  → Type declaration    → add type to session
"GIVEN ... DECIDE ..."         → Function definition → add to session bindings
<anything else>                → Bare expression     → wrap in implicit #EVAL
```

**Examples of equivalence:**

| REPL input                          | Treated as               |
| ----------------------------------- | ------------------------ |
| `2 + 3`                             | `#EVAL 2 + 3`            |
| `#EVAL 2 + 3`                       | `#EVAL 2 + 3`            |
| `foo GIVEN x IS 5`                  | `#EVAL foo GIVEN x IS 5` |
| `#CHECK foo GIVEN x IS 5 EQUALS 10` | (check directive)        |
| `DECIDE bar IS 42`                  | (session definition)     |

**Preprocessing function:**

```haskell
data ReplInput
  = ReplCommand Text [Text]                    -- :cmd args
  | ReplDirective (Directive Name)             -- #EVAL, #CHECK, etc.
  | ReplDefinition (Section Name)              -- DECIDE, ASSUME, DECLARE
  | ReplBareExpr (Expr Name)                   -- implicit eval

classifyInput :: Text -> Either ParseError ReplInput
classifyInput input
  | ":" `Text.isPrefixOf` stripped = parseCommand stripped
  | startsWithDirective input      = ReplDirective <$> parseDirective input
  | startsWithDefinition input     = ReplDefinition <$> parseSection input
  | otherwise                      = ReplBareExpr <$> parseExpr input
  where
    stripped = Text.strip input

startsWithDirective :: Text -> Bool
startsWithDirective t = any (`Text.isPrefixOf` Text.toUpper (Text.strip t))
  ["#EVAL", "#EVALTRACE", "#CHECK", "#ASSERT", "#CONTRACT"]

startsWithDefinition :: Text -> Bool
startsWithDefinition t = any (`Text.isPrefixOf` Text.toUpper (Text.strip t))
  ["DECIDE", "MEANS", "ASSUME", "DECLARE", "GIVEN"]
```

**Handling directive families:**

The `#EVAL` family of directives are "both program text and expressions" - they appear in `.l4` files but their purpose is evaluation. The REPL treats them uniformly:

| Directive           | REPL behavior                                      |
| ------------------- | -------------------------------------------------- |
| `#EVAL <expr>`      | Evaluate `<expr>`, print result                    |
| `#EVALTRACE <expr>` | Evaluate with step-by-step trace                   |
| `#CHECK <expr>`     | Evaluate, print `PASS` if truthy, `FAIL` if falsy  |
| `#ASSERT <expr>`    | Evaluate, silent if truthy, error message if falsy |

This means you can copy an entire block from a `.l4` file:

```l4
-- Paste this whole block into the REPL:
DECIDE factorial n IS
  IF n EQUALS 0
  THEN 1
  ELSE n * factorial (n - 1)

#EVAL factorial 5
#CHECK factorial 5 EQUALS 120
```

And the REPL processes each piece appropriately:

```
jl4> DECIDE factorial n IS
   >   IF n EQUALS 0
   >   THEN 1
   >   ELSE n * factorial (n - 1)
Defined: factorial :: NUMBER -> NUMBER

jl4> #EVAL factorial 5
120

jl4> #CHECK factorial 5 EQUALS 120
PASS: factorial 5 EQUALS 120
```

### REPL Commands

Commands start with `:` (colon) to distinguish from L4 expressions:

| Command         | Short | Description                                |
| --------------- | ----- | ------------------------------------------ |
| `:help`         | `:h`  | Show help                                  |
| `:quit`         | `:q`  | Exit REPL                                  |
| `:load <file>`  | `:l`  | Load a file into context                   |
| `:reload`       | `:r`  | Reload all loaded files                    |
| `:type <expr>`  | `:t`  | Show type of expression (don't evaluate)   |
| `:info <name>`  | `:i`  | Show definition/type of a name             |
| `:env`          | `:e`  | List names in scope                        |
| `:clear`        |       | Clear session-defined bindings             |
| `:reset`        |       | Reset to initial state (reload everything) |
| `:set <option>` |       | Set REPL options                           |
| `:trace`        |       | Toggle evaluation tracing                  |

Example session:

```
jl4> :load examples/insurance.l4
Loading examples/insurance.l4... done

jl4> :type premium
premium :: { age: NUMBER, smoker: BOOLEAN } -> NUMBER

jl4> :info premium
GIVEN age IS A NUMBER
      smoker IS A BOOLEAN
GIVETH A NUMBER
DECIDE premium IS
  IF smoker
  THEN baseRate * 1.5
  ELSE baseRate
  WHERE baseRate IS 1000 + (age * 10)

jl4> :env
-- From prelude:
(+), (-), (*), (/), ...
-- From examples/insurance.l4:
premium, baseRate, ...
-- Session-defined:
(none)
```

### Options

```
jl4> :set trace on       -- Show evaluation steps
jl4> :set showtype on    -- Show type with each result
jl4> :set prompt ">>> "  -- Change prompt
```

## Technical Architecture

### Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              jl4-repl                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────┐    ┌──────────────────┐    ┌────────────────────────┐ │
│  │  Haskeline  │───▶│   Preprocessor   │───▶│      Dispatcher        │ │
│  │  (readline) │    │   (classifyInput)│    │                        │ │
│  └─────────────┘    └──────────────────┘    └───────────┬────────────┘ │
│                              │                          │              │
│                              ▼                          ▼              │
│               ┌──────────────────────────┐   ┌───────────────────────┐│
│               │    Input Classification   │   │   Handler Dispatch    ││
│               │                          │   │                       ││
│               │  ":"       → ReplCmd     │   │  ReplCmd  → cmdHandler││
│               │  "#EVAL"   → Directive   │   │  Directive→ evalDir   ││
│               │  "DECIDE"  → Definition  │   │  Definition→ addDef   ││
│               │  <other>   → BareExpr    │   │  BareExpr → evalExpr  ││
│               └──────────────────────────┘   └───────────────────────┘│
│                                                         │              │
│  ┌──────────────────────────────────────────────────────┴────────────┐│
│  │                         REPL State                                 ││
│  │  • IdeState (ShakeDatabase with cached modules)                   ││
│  │  • Session bindings (user-defined in this session)                ││
│  │  • Session types (DECLARE'd types)                                ││
│  │  • Loaded files list                                              ││
│  │  • Options (trace, showtype, etc.)                                ││
│  └────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       Existing Infrastructure                            │
├─────────────────────────────────────────────────────────────────────────┤
│  LSP/Core/Shake.hs    │  L4/Parser.hs       │  L4/TypeCheck.hs         │
│  (IdeState, actions)  │  (singleLineExpr,   │  (runCheck)              │
│                       │   directive, section)│                          │
├───────────────────────┼─────────────────────┼──────────────────────────┤
│  L4/EvaluateLazy.hs                         │  L4/ExactPrint.hs        │
│  (execEvalExprInContextOfModule)            │  (result display)        │
└─────────────────────────────────────────────────────────────────────────┘
```

### Key Data Structures

```haskell
-- New module: L4/Repl/Types.hs

data ReplState = ReplState
  { ideState        :: IdeState            -- From LSP.Core.Shake
  , loadedFiles     :: [NormalizedFilePath]
  , sessionBindings :: [(Name, Expr Resolved, Type' Resolved)]
  , sessionTypes    :: [(Name, Type' Resolved)]  -- DECLARE'd types
  , options         :: ReplOptions
  , evalConfig      :: EvalConfig
  }

data ReplOptions = ReplOptions
  { showTrace  :: Bool
  , showType   :: Bool
  , prompt     :: Text
  }

-- Result of preprocessing: what kind of input did we receive?
data ReplInput
  = ReplCommand ReplCmd              -- :help, :load, etc.
  | ReplDirective (Directive Name)   -- #EVAL, #CHECK, #ASSERT, etc.
  | ReplDefinition (Section Name)    -- DECIDE, ASSUME, DECLARE
  | ReplBareExpr (Expr Name)         -- anything else → implicit #EVAL

-- REPL-specific commands (colon-prefixed)
data ReplCmd
  = CmdTypeOf (Expr Name)            -- :type <expr>
  | CmdInfo RawName                  -- :info <name>
  | CmdLoad FilePath                 -- :load <file>
  | CmdReload                        -- :reload
  | CmdEnv                           -- :env
  | CmdClear                         -- :clear
  | CmdReset                         -- :reset
  | CmdSet Text Text                 -- :set <option> <value>
  | CmdHelp                          -- :help
  | CmdQuit                          -- :quit
```

### Core Functions

```haskell
-- Main entry point
runRepl :: ReplOptions -> [FilePath] -> IO ()
runRepl opts initialFiles = do
  state <- initReplState opts initialFiles
  runInputT defaultSettings (replLoop state)

-- Initialize with files
initReplState :: ReplOptions -> [FilePath] -> IO ReplState
initReplState opts files = do
  evalConfig <- resolveEvalConfig Nothing
  ide <- oneshotIdeState recorder "." (jl4Rules evalConfig "." recorder)
  forM_ files (loadFile ide)
  pure ReplState { ideState = ide, loadedFiles = files, ... }

-- Main loop
replLoop :: ReplState -> InputT IO ()
replLoop state = do
  minput <- getInputLine (Text.unpack state.options.prompt)
  case minput of
    Nothing -> pure ()  -- EOF
    Just input -> do
      result <- liftIO $ processInput state (Text.pack input)
      case result of
        QuitRepl -> pure ()
        ContinueRepl output state' -> do
          unless (Text.null output) $ outputStrLn (Text.unpack output)
          replLoop state'
        ReplError err -> do
          outputStrLn (renderError err)
          replLoop state  -- Continue with unchanged state

-- Process a single input line using preprocessing
processInput :: ReplState -> Text -> IO ReplResult
processInput state input
  | Text.null (Text.strip input) = pure $ ContinueRepl "" state
  | otherwise = case classifyInput input of
      Left parseErr -> pure $ ReplError (ParseError parseErr)
      Right replInput -> dispatch state replInput

-- Dispatch based on input classification
dispatch :: ReplState -> ReplInput -> IO ReplResult
dispatch state = \case
  ReplCommand cmd      -> handleCommand state cmd
  ReplDirective dir    -> handleDirective state dir
  ReplDefinition sec   -> handleDefinition state sec
  ReplBareExpr expr    -> handleBareExpr state expr

-- Handle REPL commands (:help, :load, etc.)
handleCommand :: ReplState -> ReplCmd -> IO ReplResult
handleCommand state = \case
  CmdQuit         -> pure QuitRepl
  CmdHelp         -> pure $ ContinueRepl helpText state
  CmdLoad fp      -> loadFileCmd state fp
  CmdReload       -> reloadCmd state
  CmdTypeOf expr  -> typeOfCmd state expr
  CmdInfo name    -> infoCmd state name
  CmdEnv          -> envCmd state
  CmdClear        -> pure $ ContinueRepl "Session cleared." state { sessionBindings = [] }
  CmdReset        -> resetCmd state
  CmdSet opt val  -> setOptionCmd state opt val

-- Handle directives (#EVAL, #CHECK, etc.)
handleDirective :: ReplState -> Directive Name -> IO ReplResult
handleDirective state dir = runExceptT do
  ctx <- getMergedContext state
  case dir of
    LazyEval _ expr      -> evalAndShow state ctx expr False
    LazyEvalTrace _ expr -> evalAndShow state ctx expr True
    Check _ expr         -> checkExpr state ctx expr
    Assert _ expr        -> assertExpr state ctx expr
    Contract _ _ _ _     -> contractCmd state dir

-- Handle definitions (DECIDE, ASSUME, DECLARE)
handleDefinition :: ReplState -> Section Name -> IO ReplResult
handleDefinition state section = runExceptT do
  ctx <- getMergedContext state
  (resolved, info) <- typecheckSectionInContext ctx section
  let state' = addToSession state resolved info
      output = formatDefinitionAdded resolved info
  pure $ ContinueRepl output state'

-- Handle bare expressions (implicit #EVAL)
handleBareExpr :: ReplState -> Expr Name -> IO ReplResult
handleBareExpr state expr =
  handleDirective state (LazyEval emptyAnno expr)
```

### Expression Evaluation Pipeline

The unified evaluation pipeline handles both bare expressions and directives:

```haskell
-- Evaluate an expression and format the result
evalAndShow :: ReplState -> Context -> Expr Name -> Bool -> ExceptT ReplError IO ReplResult
evalAndShow state ctx expr showTrace = do
  -- 1. Typecheck expression in context
  (resolvedExpr, exprType) <- typecheckExprInContext ctx expr

  -- 2. Evaluate (with optional trace)
  let config = state.evalConfig { evalTrace = showTrace }
  result <- evaluateExpr config ctx resolvedExpr

  -- 3. Format output
  let output = renderResult result
      typeAnnotation = if state.options.showType
                       then " :: " <> renderType exprType
                       else ""
      traceOutput = if showTrace then renderTrace result else ""
  pure $ ContinueRepl (traceOutput <> output <> typeAnnotation) state

-- Check expression (for #CHECK directive)
checkExpr :: ReplState -> Context -> Expr Name -> ExceptT ReplError IO ReplResult
checkExpr state ctx expr = do
  (resolvedExpr, _) <- typecheckExprInContext ctx expr
  result <- evaluateExpr state.evalConfig ctx resolvedExpr
  let passed = isTruthy result
      status = if passed then "PASS" else "FAIL"
      output = status <> ": " <> renderExpr expr
  pure $ ContinueRepl output state

-- Assert expression (for #ASSERT directive)
assertExpr :: ReplState -> Context -> Expr Name -> ExceptT ReplError IO ReplResult
assertExpr state ctx expr = do
  (resolvedExpr, _) <- typecheckExprInContext ctx expr
  result <- evaluateExpr state.evalConfig ctx resolvedExpr
  if isTruthy result
    then pure $ ContinueRepl "" state  -- Silent on success
    else pure $ ReplError (AssertionFailed expr result)
```

### New Parser Entry Point

The REPL needs a unified parser that can handle all input types. The preprocessing happens at the text level, then delegates to existing parsers:

```haskell
-- L4/Repl/Parser.hs (new module)

-- | Classify and parse REPL input into the appropriate form.
-- This is the main entry point for REPL input processing.
classifyAndParse :: NormalizedUri -> Text -> Either (NonEmpty PError) ReplInput
classifyAndParse uri input
  | ":" `Text.isPrefixOf` stripped = ReplCommand <$> parseReplCommand stripped
  | otherwise = do
      tokens <- execLexer uri input
      classifyFromTokens uri input tokens
  where
    stripped = Text.strip input

-- | After lexing, look at the first token to determine input type.
classifyFromTokens :: NormalizedUri -> Text -> [PosToken] -> Either (NonEmpty PError) ReplInput
classifyFromTokens uri input tokens = case firstSignificantToken tokens of
  Just (TDirectives _) -> ReplDirective <$> runParser uri input tokens directive
  Just TKDecide        -> ReplDefinition <$> runParser uri input tokens section
  Just TKMeans         -> ReplDefinition <$> runParser uri input tokens section
  Just TKAssume        -> ReplDefinition <$> runParser uri input tokens section
  Just TKDeclare       -> ReplDefinition <$> runParser uri input tokens section
  Just TKGiven         -> ReplDefinition <$> runParser uri input tokens section  -- GIVEN ... DECIDE
  _                    -> ReplBareExpr <$> runParser uri input tokens (singleLineExpr <* eof)

firstSignificantToken :: [PosToken] -> Maybe Token
firstSignificantToken = listToMaybe . filter (not . isWhitespace) . map (.payload)

-- | Parse REPL commands (colon-prefixed)
parseReplCommand :: Text -> Either (NonEmpty PError) ReplCmd
parseReplCommand input = case Text.words (Text.drop 1 input) of  -- drop the ':'
  ["help"]      -> Right CmdHelp
  ["h"]         -> Right CmdHelp
  ["quit"]      -> Right CmdQuit
  ["q"]         -> Right CmdQuit
  ["load", fp]  -> Right (CmdLoad (Text.unpack fp))
  ["l", fp]     -> Right (CmdLoad (Text.unpack fp))
  ["reload"]    -> Right CmdReload
  ["r"]         -> Right CmdReload
  ["env"]       -> Right CmdEnv
  ["e"]         -> Right CmdEnv
  ["clear"]     -> Right CmdClear
  ["reset"]     -> Right CmdReset
  ("type":rest) -> CmdTypeOf <$> parseExprFromWords rest
  ("t":rest)    -> CmdTypeOf <$> parseExprFromWords rest
  ("info":rest) -> Right (CmdInfo (Text.unwords rest))
  ("i":rest)    -> Right (CmdInfo (Text.unwords rest))
  ("set":rest)  -> parseSetCommand rest
  other         -> Left (singleError $ "Unknown command: " <> Text.unwords other)
```

**Key insight**: By lexing first, we can peek at the first token to determine input type without backtracking. This reuses the existing lexer infrastructure.

### Typechecking Expressions in Context

Currently, `L4/TypeCheck.hs` typechecks entire modules. We need a function to typecheck a single expression given an existing context:

```haskell
-- L4/TypeCheck.hs (addition)

-- | Typecheck a standalone expression in an existing environment.
typecheckExprInContext
  :: NormalizedUri
  -> Environment
  -> EntityInfo
  -> Substitution
  -> Expr Name
  -> Either [CheckErrorWithContext] (Expr Resolved, Type' Resolved)
typecheckExprInContext uri env entityInfo subst expr = do
  let checkEnv = mkInitialCheckEnv uri env entityInfo
      checkState = mkInitialCheckState subst
  case runCheck (inferExpr expr) checkEnv checkState of
    [] -> Left [internalError "No typecheck result"]
    ((With errs result, _) : _)
      | any isError errs -> Left errs
      | otherwise -> Right result
```

### Session-Defined Bindings

When the user defines something in the REPL:

```
jl4> DECIDE double x IS x * 2
```

We need to:

1. Parse as a `Decide` declaration
2. Typecheck in current context
3. Add to session bindings (not persisted to any file)
4. Make available for subsequent expressions

```haskell
processDefinition :: ReplState -> Text -> IO (Either ReplError (Text, ReplState))
processDefinition state input = runExceptT do
  decide <- parseDecide input
  ctx <- getMergedContext state.ideState state.loadedFiles

  -- Typecheck the definition
  (resolvedDecide, defType) <- typecheckDecideInContext ctx decide

  -- Add to session
  let name = decideName resolvedDecide
      binding = (name, decideBody resolvedDecide, defType)
      state' = state { sessionBindings = binding : state.sessionBindings }

  pure ("Defined: " <> renderName name <> " :: " <> renderType defType, state')
```

## Implementation Plan

### Phase 1: Minimal Viable REPL (MVP)

**Goal**: Basic expression evaluation with loaded modules.

**Tasks**:

1. Create `jl4-repl` package in cabal
2. Add `haskeline` dependency
3. Implement basic REPL loop (no commands except `:quit`)
4. Implement `parseReplExpr`
5. Implement `typecheckExprInContext`
6. Wire up evaluation using existing `execEvalExprInContextOfModule`
7. Basic error display

**Acceptance criteria**:

```bash
$ jl4-repl
jl4> 2 + 3
5
jl4> :q
$
```

**Estimated effort**: 2-3 days

### Phase 2: File Loading

**Goal**: Load `.l4` files and evaluate in their context.

**Tasks**:

1. Implement `:load` command
2. Implement `:reload` command
3. Handle import resolution
4. Show loading progress

**Acceptance criteria**:

```bash
$ jl4-repl
jl4> :load examples/insurance.l4
Loading examples/insurance.l4... done
jl4> premium GIVEN age IS 30
...
```

**Estimated effort**: 1-2 days

### Phase 3: Commands

**Goal**: Full command set for exploration.

**Tasks**:

1. `:type` - type query without evaluation
2. `:info` - show definition
3. `:env` - list bindings
4. `:help` - show help text
5. `:set` - configuration options

**Estimated effort**: 2 days

### Phase 4: Session Definitions

**Goal**: Define bindings during REPL session.

**Tasks**:

1. Parse `DECIDE`/`MEANS` at REPL prompt
2. Add to session context
3. `:clear` to reset session bindings
4. Handle shadowing correctly

**Estimated effort**: 2 days

### Phase 5: Polish

**Goal**: Production-quality UX.

**Tasks**:

1. Tab completion (names in scope)
2. History (persistent across sessions)
3. Syntax highlighting (if terminal supports)
4. Better error messages with suggestions
5. Multi-line input handling
6. `--fixed-now` flag for deterministic testing

**Estimated effort**: 3-4 days

## Edge Cases & Error Handling

### Parse Errors

```
jl4> 2 + + 3
Parse error at column 5: unexpected '+'
       2 + + 3
           ^
jl4>
```

The session continues; bad input doesn't crash.

### Type Errors

```
jl4> 2 + "hello"
Type error: Cannot unify NUMBER with STRING
  Expected: NUMBER
  Actual:   STRING
  In expression: 2 + "hello"
jl4>
```

### Evaluation Errors

```
jl4> 1 / 0
Evaluation error: Division by zero
jl4>
```

### Undefined Names

```
jl4> foo
Error: 'foo' is not in scope
  Did you mean: floor, for?
  Hint: Use :load <file> to load definitions
jl4>
```

### File Not Found

```
jl4> :load nonexistent.l4
Error: File not found: nonexistent.l4
jl4>
```

### Import Cycles (Handled by existing infrastructure)

```
jl4> :load cyclic.l4
Error: Import cycle detected: cyclic.l4 -> other.l4 -> cyclic.l4
jl4>
```

## Alternative Designs Considered

### A. Mode flag on jl4-cli

```bash
$ jl4-cli --repl file.l4
```

**Pros**: No new executable, simpler packaging  
**Cons**: Muddies the CLI's purpose (batch vs interactive)

**Decision**: Separate executable is cleaner, follows GHC/GHCi precedent.

### B. Integration into LSP

Have the LSP expose a REPL endpoint that editors can connect to.

**Pros**: Reuses all LSP infrastructure directly  
**Cons**: Requires editor support, not usable standalone

**Decision**: Standalone REPL is more versatile; can add LSP integration later.

### C. Web-based REPL

A browser-based interface like Try Haskell.

**Pros**: No installation required, great for learning  
**Cons**: Significant additional work, different infrastructure

**Decision**: Out of scope for initial implementation; could build on this foundation later.

## Future Extensions

1. **Persistent history** - Save/load REPL history across sessions
2. **Session save/load** - Export session definitions to `.l4` file
3. **Debugger integration** - Step through evaluation
4. **Notebook mode** - Literate REPL sessions (like Jupyter)
5. **Remote REPL** - Connect to a running decision service
6. **WASM build** - Run in browser via wasm-compiled evaluator

## Security Considerations

- The REPL should respect the same security constraints as `jl4-cli`
- No network access from evaluated expressions (unless explicitly enabled)
- File system access limited to loading `.l4` files
- Consider sandboxing options for untrusted input

## Testing Strategy

1. **Unit tests** for `parseReplExpr` and `typecheckExprInContext`
2. **Golden tests** for REPL sessions (input/output pairs)
3. **Integration tests** for file loading
4. **Property tests** for expression parsing (roundtrip: parse → print → parse)

Example golden test:

```
# test/repl/basic.session
> 2 + 3
5
> "hello" <> " world"
"hello world"
> :type 2 + 3
NUMBER
> :q
```

## Dependencies

**Terminal UI options** (choose one):

| Library         | Level  | Paste Detection  | Notes                                                                                                  |
| --------------- | ------ | ---------------- | ------------------------------------------------------------------------------------------------------ |
| `repline`       | High   | Via haskeline    | **Recommended.** GHCi-style REPL wrapper. Built-in command parsing, tab completion, multiline support. |
| `haskeline`     | Medium | Bracketed paste  | Standard choice. More boilerplate but more control.                                                    |
| `brick` + `vty` | Low    | `EvPaste` events | Full TUI framework. Overkill for simple REPL, but best paste detection.                                |

**Recommendation: `repline`**

`repline` is purpose-built for GHCi-style REPLs and provides:

- Built-in `:command` parsing
- Tab completion (word, prefix, file, stateful)
- Multiline input with customizable banners
- MTL composability (works with `StateT`, `ReaderT`, etc.)
- Less boilerplate than raw haskeline

```haskell
-- Example repline usage
type Repl a = HaskelineT (StateT ReplState IO) a

repl :: Repl ()
repl = evalRepl
  (const $ pure "jl4> ")     -- Prompt
  cmd                         -- Command handler
  options                     -- :commands
  (Just ':')                  -- Command prefix
  (Just "multiline")          -- Multiline mode
  (Word completer)            -- Tab completion
  ini                         -- Initializer
  final                       -- Finalizer

options :: Options Repl
options =
  [ ("help",    help)
  , ("load",    load)
  , ("type",    typeOf)
  , ("quit",    abort)
  ]
```

**For advanced paste handling**, consider `brick`/`vty` which provide `EvPaste` events at the terminal level. This could be a Phase 5 enhancement if `repline`'s paste handling proves insufficient.

**Existing dependencies** (already available):

- `megaparsec` - Parsing
- `mtl` - Monad transformers
- `prettyprinter` - Output formatting

## File Structure

```
jl4-repl/
├── jl4-repl.cabal
├── app/
│   └── Main.hs              -- Entry point, option parsing
└── src/
    └── L4/
        └── Repl/
            ├── Types.hs     -- ReplState, ReplInput, ReplCmd, etc.
            ├── Loop.hs      -- Main REPL loop, dispatch
            ├── Commands.hs  -- :load, :type, etc. handlers
            ├── Eval.hs      -- Expression/directive evaluation
            └── Parser.hs    -- classifyAndParse, command parsing

# Additions to existing packages:
jl4-core/src/L4/
└── TypeCheck.hs             -- Add typecheckExprInContext, typecheckSectionInContext
```

## Open Questions

1. **Should `:load` replace or augment the current context?**

   - GHCi uses replace semantics by default
   - Could offer both: `:load` replaces, `:add` augments

2. **How to handle name collisions between session and file bindings?**

   - Session shadows file? File shadows session? Error?

3. **Should we support `:browse` for listing module contents?**

   - Useful for exploration, but adds complexity

4. **Multi-line input: use `# >` continuation or detect incomplete expressions?**

   - `# >` is consistent with L4's existing directive continuation syntax
   - Auto-detection is more user-friendly but harder to implement correctly

5. **Should the REPL auto-reload files when they change on disk?**
   - Nice for development, but could be surprising
   - Could be an option: `:set autoreload on`
   - Not answered; what the REPL does as of 2026-11-25 (smucclaw/l4-ide#1099), decided by Claude 2026-11-25, pending Meng's review:
     `:load`, `:reload` and `:reset` read again from disk every file the REPL has read: the loaded file, every module it imports, directly or not, and every module `:import` added.
     A line reads no file the REPL has read again: it answers from what was read until the next of the three, so there is no auto-reload.
     A file that one of the three could not read is dropped from the store, and the next line that needs it looks for it on disk again.
     `:reset` re-reads in the same store as `:reload`; it does not start a new store.
     Before #1099 the three read the loaded file again but put it back in the store under the version it had, 0, so nothing built from its old text was built again; a module it imports, or one `:import` added, was never read again (`syncStoreWithDisk` in `jl4-repl/app/Main.hs` says why).
     Only a fresh REPL sees a module added where `IMPORT` looks before the one in use, such as a `lib.l4` put in the `JL4_LIBRARY_PATH` folder while the importer's own `lib.l4` is in use: the store's copy of a module is tier 0 of resolution.
   - A file that is not there, decided by Claude 2026-11-25, pending Meng's review (smucclaw/l4-ide#1099):
     `:load` or `:l` of a file that is not there replies `Error: there is no file <path>` and keeps the file loaded before.
     A loaded file deleted since it was loaded is reported the same way at `:reload` and `:reset` (`Error reloading: there is no file <path>`), and a file named at start-up that is not there gets `Error loading file: there is no file <path>`.
     In each case the REPL goes on, and a line that does not need the file still answers.
     Each of these used to end the session: start-up, `:load`, `:reload` and `:reset` read the file with nothing to catch a failure.

## References

- [GHCi User Guide](https://downloads.haskell.org/ghc/latest/docs/users_guide/ghci.html)
- [Python REPL](https://docs.python.org/3/tutorial/interpreter.html)
- [Haskeline library](https://hackage.haskell.org/package/haskeline)
- Existing L4 infrastructure: `LSP.L4.Oneshot`, `L4.EvaluateLazy`

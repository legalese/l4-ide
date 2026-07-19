-- | Basic tests for the L4 MLIR compiler.
--
-- Tests the MLIR IR construction and emission (no external toolchain needed).
-- Integration tests that require mlir-opt / wasmtime are separate.
module Main (main) where

import qualified Data.Text as Text
import System.Exit (exitFailure, exitSuccess)

import qualified Data.Text as T

import L4.MLIR.IR
import L4.MLIR.Emit (renderMLIR)
import L4.MLIR.Dialect.Func
import L4.MLIR.Dialect.Arith
import L4.MLIR.Dialect.SCF
import L4.MLIR.Runtime.Builtins (builtinDeclarations)
import L4.MLIR.Lower (lowerProgramWithInfo, lowerProgramWithDiagnostics)
import L4.MLIR.Schema (bundleExports, applyDiagnostics, encodeBundle)

import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text.Encoding as TE

import L4.API.VirtualFS (checkWithImports, checkWithImportsAndUri, emptyVFS, vfsFromList)
import L4.Import.Resolution (TypeCheckWithDepsResult(..), ResolvedImport(..))
import L4.TypeCheck (applyFinalSubstitution)
import L4.TypeCheck.Types (CheckResult(..), EntityInfo)

-- | 'L4.Import.Resolution.typecheckWithDependencies' leaves the main
-- module's @entityInfo@ un-substituted (it applies the substitution
-- only to imported modules), so test consumers like
-- 'enrichReturnTypes' would see 'InfVar' rather than the resolved
-- 'TyApp' for a @MEANS@-binding's inferred return type. The
-- production pipeline (LSP rules) substitutes via
-- 'applyFinalSubstitution' — mirror that here.
substitutedEntityInfo :: TypeCheckWithDepsResult -> EntityInfo
substitutedEntityInfo r =
  applyFinalSubstitution r.tcdSubstitution r.tcdUri r.tcdEntityInfo

main :: IO ()
main = do
  results <- sequence
    [ test "type emission"                     testTypeEmission
    , test "simple function"                   testSimpleFunction
    , test "if-then-else"                      testIfThenElse
    , test "builtin declarations"              testBuiltins
    , test "arithmetic ops"                    testArithOps
    , test "@export ASSUMEs become args"       testExportAssumePromotion
    , test "internal callers fill via extern"  testInternalCallFillsAssumes
    , test "schema picks up imported DECLAREs" testSchemaUsesImportedDeclares
    , test "deontic contract baked into schema" testDeonticSchemaBaked
    , test "plain fn stays supported"          testPlainFunctionSupported
    , test "state graph baked into schema"     testStateGraphBaked
    , test "no state graph for plain fn"       testNoStateGraphForPlainFn
    , test "traceMeta pretty-print baked"      testTraceMetaBaked
    , test "<fn>$trace symbol emitted"         testTraceSymbolEmitted
    , test "traceMeta nodes populated"         testTraceMetaNodes
    , test "AND/OR/NOT marked special"         testTraceSpecialMarkers
    , test "fnValue node + enter_fn/exit_fn"   testTraceFnValueAndContext
    , test "NOT-range disambiguation"          testTraceNotRangeDisambiguation
    , test "returnType enriched from EntityInfo" testReturnTypeEnrichedFromEntityInfo
    , test "bare-head param typed from EntityInfo" testBareHeadParamTyped
    , test "string CONSIDER emits __l4_str_eq" testStringPatternStrEq
    , test "EITHER CONSIDER → supported dispatch" testEitherConsiderSupported
    , test "user LEFT/RIGHT enum → supported:false" testUserEitherShadowUnsupported
    , test "enum-with-data return → supported:false" testDataEnumReturnUnsupported
    , test "EXACTLY CONSIDER → supported:false"  testPatExprUnsupported
    , test "overload collision → supported:false" testOverloadCollisionUnsupported
    , test "same-arity overloads → distinct symbols" testOverloadSameArityDispatch
    , test "local WHERE helpers → distinct symbols"  testLocalHelperDistinctSymbols
    , test "unsupported helper → caller unsupported" testDiagnosticPropagatesToCaller
    , test "NUMBER == (InfoMap miss) → __l4_rat_cmp" testNumberCmpInfoMapMiss
    , test "STRING == (InfoMap miss) → __l4_str_eq"  testStringEqInfoMapMiss
    , test "STRING ordered < → __l4_str_cmp"         testStringOrderedStrCmp
    , test "tyvar-return cmp → supported:false"      testUnresolvableCmpUnsupported
    , test "helper-result NUMBER cmp → __l4_rat_cmp" testHelperResultNumberCmp
    , test "WHERE-local vs constant → __l4_rat_cmp"  testWhereLocalVsConstantCmp
    , test "helper-result STRING == → __l4_str_eq"   testHelperResultStringEq
    , test "deontic unextractable contract → supported:false" testDeonticUnextractableRefused
    , test "deontic PROVIDED guard → supported:false" testDeonticProvidedRefused
    , test "deontic computed deadline → supported:false" testDeonticComputedDeadlineRefused
    , test "deontic literal deadline → supported:true" testDeonticLiteralDeadlineSupported
    ]
  if and results
    then do
      putStrLn $ "\nAll " <> show (length results) <> " tests passed."
      exitSuccess
    else do
      putStrLn $ "\nFailed: " <> show (length (filter not results)) <> " of " <> show (length results)
      exitFailure

test :: String -> IO Bool -> IO Bool
test name action = do
  putStr $ "  " <> name <> "... "
  result <- action
  putStrLn $ if result then "ok" else "FAIL"
  pure result

-- | Test that MLIR types render correctly.
testTypeEmission :: IO Bool
testTypeEmission = do
  let mlir = renderMLIR $ MLIRModule
        { moduleOps = [funcFunc "test_types"
            [(0, FloatType 64), (1, IntegerType 1), (2, PointerType)]
            [FloatType 64]
            (Region [Block 0
              [(0, FloatType 64), (1, IntegerType 1), (2, PointerType)]
              [funcReturn [SSAValue 0] [FloatType 64]]])]
        }
  -- Check that the output contains expected type strings
  pure $ Text.isInfixOf "f64" mlir
      && Text.isInfixOf "i1" mlir
      && Text.isInfixOf "!llvm.ptr" mlir

-- | Test a simple function definition.
testSimpleFunction :: IO Bool
testSimpleFunction = do
  let mlir = renderMLIR $ MLIRModule
        { moduleOps =
            [ funcFunc "add_numbers"
                [(0, FloatType 64), (1, FloatType 64)]
                [FloatType 64]
                (Region [Block 0
                  [(0, FloatType 64), (1, FloatType 64)]
                  [ arithAddf 2 (SSAValue 0) (SSAValue 1)
                  , funcReturn [SSAValue 2] [FloatType 64]
                  ]])
            ]
        }
  pure $ Text.isInfixOf "func.func @add_numbers" mlir
      && Text.isInfixOf "arith.addf" mlir
      && Text.isInfixOf "func.return" mlir

-- | Test if-then-else lowering via scf.if.
testIfThenElse :: IO Bool
testIfThenElse = do
  let thenRegion = Region [Block 0 []
        [ arithConstantFloat 10 42.0
        , scfYield [SSAValue 10] [FloatType 64]
        ]]
      elseRegion = Region [Block 0 []
        [ arithConstantFloat 11 0.0
        , scfYield [SSAValue 11] [FloatType 64]
        ]]
      mlir = renderMLIR $ MLIRModule
        { moduleOps =
            [ funcFunc "conditional"
                [(0, IntegerType 1)]
                [FloatType 64]
                (Region [Block 0
                  [(0, IntegerType 1)]
                  [ scfIf [1] (SSAValue 0) thenRegion elseRegion [FloatType 64]
                  , funcReturn [SSAValue 1] [FloatType 64]
                  ]])
            ]
        }
  pure $ Text.isInfixOf "scf.if" mlir
      && Text.isInfixOf "scf.yield" mlir

-- | Test that builtin runtime declarations generate valid MLIR.
testBuiltins :: IO Bool
testBuiltins = do
  let mlir = renderMLIR $ MLIRModule { moduleOps = builtinDeclarations }
  pure $ Text.isInfixOf "__l4_pow" mlir
      && Text.isInfixOf "__l4_str_concat" mlir
      && Text.isInfixOf "__l4_alloc" mlir

-- | Test arithmetic operation generation.
testArithOps :: IO Bool
testArithOps = do
  let mlir = renderMLIR $ MLIRModule
        { moduleOps =
            [ funcFunc "math_ops"
                [(0, FloatType 64), (1, FloatType 64)]
                [FloatType 64]
                (Region [Block 0
                  [(0, FloatType 64), (1, FloatType 64)]
                  [ arithAddf 2 (SSAValue 0) (SSAValue 1)
                  , arithSubf 3 (SSAValue 2) (SSAValue 1)
                  , arithMulf 4 (SSAValue 3) (SSAValue 0)
                  , arithDivf 5 (SSAValue 4) (SSAValue 1)
                  , arithCmpf 6 OGT (SSAValue 5) (SSAValue 0)
                  , funcReturn [SSAValue 5] [FloatType 64]
                  ]])
            ]
        }
  pure $ Text.isInfixOf "arith.addf" mlir
      && Text.isInfixOf "arith.subf" mlir
      && Text.isInfixOf "arith.mulf" mlir
      && Text.isInfixOf "arith.divf" mlir

-- | Lower an L4 source string to MLIR text, going through the real
-- typecheck + lowering pipeline. The SUBSTITUTED entityInfo is threaded
-- in (mirroring the production pipeline), so the lowering's bundle-wide
-- 'funcL4Types' map sees resolved types for MEANS-binding constants.
lowerSource :: T.Text -> Either [T.Text] T.Text
lowerSource src =
  case checkWithImports emptyVFS src of
    Left errs -> Left errs
    Right r -> Right (renderMLIR (lowerProgramWithInfo r.tcdInfoMap (substitutedEntityInfo r) r.tcdModule []))

-- | Lower a source and render its schema JSON *with* per-function
-- lowering diagnostics applied (the @supported@ / @unsupportedReason@
-- flags). Mirrors what 'L4.MLIR.Pipeline' does.
schemaWithDiagnostics :: T.Text -> Either [T.Text] T.Text
schemaWithDiagnostics src =
  case checkWithImports emptyVFS src of
    Left errs -> Left errs
    Right r ->
      let (_mlir, diags) = lowerProgramWithDiagnostics r.tcdInfoMap (substitutedEntityInfo r) r.tcdModule []
          bundle = applyDiagnostics diags (bundleExports "test.wasm" "test" r.tcdInfoMap (substitutedEntityInfo r) r.tcdModule [])
      in Right (TE.decodeUtf8 (LBS.toStrict (encodeBundle bundle)))

-- | M6: a DEONTIC function is now SUPPORTED — the runtime handles
-- the contract via a JS interpreter that walks the schema's
-- @deonticContract@ tree. The schema must (a) mark it @supported:
-- true@, (b) carry the regulative AST as @deonticContract@ so the
-- runtime can walk it, and (c) flag @isDeontic: true@ so callers
-- know to send @startTime@ + @events@.
testDeonticSchemaBaked :: IO Bool
testDeonticSchemaBaked = do
  let src = T.unlines
        [ "DECLARE Party IS ONE OF `alice`"
        , "DECLARE Action IS ONE OF `pay`"
        , ""
        , "@export Demo obligation"
        , "GIVETH A DEONTIC OF Party, Action"
        , "`demo` MEANS"
        , "    PARTY `alice`"
        , "    MUST `pay`"
        , "    WITHIN 10"
        , "    HENCE FULFILLED"
        ]
  case schemaWithDiagnostics src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right json -> do
      let checks :: [(String, Bool)]
          checks =
            [ ("isDeontic",    T.isInfixOf "\"isDeontic\":true" json)
            , ("supported",    T.isInfixOf "\"supported\":true" json)
            , ("deonticContract key", T.isInfixOf "\"deonticContract\":" json)
            , ("OBLIGATION kind",     T.isInfixOf "\"kind\":\"OBLIGATION\"" json)
            , ("MUST modal",          T.isInfixOf "\"modal\":\"MUST\"" json)
            , ("deadline string",     T.isInfixOf "\"deadline\":\"10\"" json)
            , ("party serialized",    T.isInfixOf "\"party\":" json)
            , ("action serialized",   T.isInfixOf "\"action\":" json)
            , ("FULFILLED kind",      T.isInfixOf "\"kind\":\"FULFILLED\"" json)
            ]
      let failures = [name | (name, ok) <- checks, not ok]
      case failures of
        [] -> pure True
        _  -> do
          putStrLn $ "\n    failing checks: " <> show failures
          putStrLn $ "    json: " <> T.unpack (T.take 600 json)
          pure False

-- | Ledger #8: a DEONTIC function whose regulative body we CANNOT reduce
-- to a 'deonticContract' tree (here the IF guard is a helper-call
-- application @`ready` s@, which 'exprToGuard' does not represent) must
-- refuse LOUDLY at schema-build time: @supported: false@, a reason that
-- names the DEONTIC-extraction gap, and NO @deonticContract@ key. Without
-- the guard the export would ship @supported: true@ with a null contract —
-- the runtime's null-contract guard would then throw at evaluate time, and
-- if the (separate) lowering diagnostic on the helper were ever fixed the
-- export would silently claim to be evaluable when it is not. This mirrors
-- @ceo-performance-award@'s @Eligible Service Requirement@.
testDeonticUnextractableRefused :: IO Bool
testDeonticUnextractableRefused = do
  let src = T.unlines
        [ "DECLARE Party IS ONE OF `alice`"
        , "DECLARE Action IS ONE OF `pay`"
        , "DECLARE State HAS `flag` IS A BOOLEAN"
        , ""
        , "GIVEN `s` IS A State"
        , "GIVETH A BOOLEAN"
        , "`ready` MEANS `s`'s `flag`"
        , ""
        , "@export Demo obligation"
        , "GIVEN `s` IS A State"
        , "GIVETH A DEONTIC OF Party, Action"
        , "`demo` MEANS"
        , "    IF   `ready` `s`"
        , "    THEN PARTY `alice`"
        , "         MUST `pay`"
        , "         WITHIN 10"
        , "         HENCE FULFILLED"
        , "    ELSE FULFILLED"
        ]
  case schemaWithDiagnostics src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right json -> do
      let checks :: [(String, Bool)]
          checks =
            [ ("isDeontic",            T.isInfixOf "\"isDeontic\":true" json)
            , ("supported:false",      T.isInfixOf "\"supported\":false" json)
            , ("reason names DEONTIC", T.isInfixOf "DEONTIC contract could not be extracted" json)
            , ("no deonticContract",   not (T.isInfixOf "\"deonticContract\":" json))
            ]
      let failures = [name | (name, ok) <- checks, not ok]
      case failures of
        [] -> pure True
        _  -> do
          putStrLn $ "\n    failing checks: " <> show failures
          putStrLn $ "    json: " <> T.unpack (T.take 700 json)
          pure False

-- | An action carrying a PROVIDED guard cannot be interpreted by the
-- WASM runtime (it never evaluates the guard, so it would silently drop
-- it and answer as if the guard were always true). Extraction must fail
-- closed → @supported:false@, routing to the jl4-service fallback.
testDeonticProvidedRefused :: IO Bool
testDeonticProvidedRefused = do
  let src = T.unlines
        [ "DECLARE Party IS ONE OF `alice`"
        , "DECLARE Action IS ONE OF `pay`"
        , ""
        , "@export Provided demo"
        , "GIVEN `allowed` IS A BOOLEAN"
        , "GIVETH A DEONTIC OF Party, Action"
        , "`demo` MEANS"
        , "    PARTY `alice`"
        , "    MUST `pay` PROVIDED `allowed`"
        , "    WITHIN 10"
        , "    HENCE FULFILLED"
        , "    LEST BREACH"
        ]
  assertDeonticRefused src

-- | A non-literal (computed / aliased) deadline pretty-prints to a
-- non-numeric string; the runtime's @Number(deadline)@ turns it into NaN
-- so no obligation ever lapses (FULFILLED where the reference says
-- BREACH). Extraction must fail closed → @supported:false@.
testDeonticComputedDeadlineRefused :: IO Bool
testDeonticComputedDeadlineRefused = do
  let src = T.unlines
        [ "DECLARE Party IS ONE OF `the borrower`"
        , "DECLARE `Repay Action` IS ONE OF `repay loan`"
        , ""
        , "`Deadline Days` MEANS 7 PLUS 7"
        , ""
        , "@export Computed deadline demo"
        , "GIVETH A DEONTIC Party `Repay Action`"
        , "`repayment` MEANS"
        , "    PARTY `the borrower`"
        , "    MUST `repay loan`"
        , "    WITHIN `Deadline Days`"
        , "    HENCE FULFILLED"
        , "    LEST BREACH BY `the borrower` BECAUSE \"late\""
        ]
  assertDeonticRefused src

-- | Positive control: a plain obligation with a literal numeric deadline
-- and no PROVIDED guard extracts cleanly and stays @supported:true@ with
-- a @deonticContract@ tree. Guards against the fail-closed logic
-- over-refusing the shipped-corpus shape.
testDeonticLiteralDeadlineSupported :: IO Bool
testDeonticLiteralDeadlineSupported = do
  let src = T.unlines
        [ "DECLARE Party IS ONE OF `alice`"
        , "DECLARE Action IS ONE OF `pay`"
        , ""
        , "@export Plain demo"
        , "GIVETH A DEONTIC OF Party, Action"
        , "`demo` MEANS"
        , "    PARTY `alice`"
        , "    MUST `pay`"
        , "    WITHIN 10"
        , "    HENCE FULFILLED"
        , "    LEST BREACH"
        ]
  case schemaWithDiagnostics src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right json -> do
      let checks :: [(String, Bool)]
          checks =
            [ ("isDeontic",         T.isInfixOf "\"isDeontic\":true" json)
            , ("supported:true",    T.isInfixOf "\"supported\":true" json)
            , ("has deonticContract", T.isInfixOf "\"deonticContract\":" json)
            ]
      let failures = [name | (name, ok) <- checks, not ok]
      case failures of
        [] -> pure True
        _  -> do
          putStrLn $ "\n    failing checks: " <> show failures
          putStrLn $ "    json: " <> T.unpack (T.take 700 json)
          pure False

-- | Shared assertion: a DEONTIC export whose contract cannot be
-- faithfully extracted must be @supported:false@ with the DEONTIC
-- refusal reason and no @deonticContract@ tree.
assertDeonticRefused :: T.Text -> IO Bool
assertDeonticRefused src =
  case schemaWithDiagnostics src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right json -> do
      let checks :: [(String, Bool)]
          checks =
            [ ("isDeontic",            T.isInfixOf "\"isDeontic\":true" json)
            , ("supported:false",      T.isInfixOf "\"supported\":false" json)
            , ("reason names DEONTIC", T.isInfixOf "DEONTIC contract could not be extracted" json)
            , ("no deonticContract",   not (T.isInfixOf "\"deonticContract\":" json))
            ]
      let failures = [name | (name, ok) <- checks, not ok]
      case failures of
        [] -> pure True
        _  -> do
          putStrLn $ "\n    failing checks: " <> show failures
          putStrLn $ "    json: " <> T.unpack (T.take 700 json)
          pure False

-- | A plain decidable function lowers cleanly, so it must stay
-- @supported: true@ and emit no unsupported flag. (M1a negative control)
testPlainFunctionSupported :: IO Bool
testPlainFunctionSupported = do
  let src = T.unlines
        [ "@export Adult check"
        , "GIVEN `age` IS A NUMBER"
        , "GIVETH A BOOLEAN"
        , "DECIDE `is_adult` IF `age` >= 18"
        ]
  case schemaWithDiagnostics src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right json ->
      pure $ T.isInfixOf "\"supported\":true" json
          && not (T.isInfixOf "\"supported\":false" json)

-- | A top-level regulative function yields a precomputed state graph in
-- the schema, with Graphviz DOT rendered at compile time by the same
-- pure function jl4-service uses. (M3)
testStateGraphBaked :: IO Bool
testStateGraphBaked = do
  let src = T.unlines
        [ "DECLARE Party IS ONE OF `alice`"
        , "DECLARE Action IS ONE OF `pay`"
        , ""
        , "@export Demo obligation"
        , "GIVETH A DEONTIC OF Party, Action"
        , "`demo` MEANS"
        , "    PARTY `alice`"
        , "    MUST `pay`"
        , "    WITHIN 10"
        , "    HENCE FULFILLED"
        ]
  case checkWithImports emptyVFS src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right r -> do
      let bundle = bundleExports "test.wasm" "test" r.tcdInfoMap (substitutedEntityInfo r) r.tcdModule []
          json = TE.decodeUtf8 (LBS.toStrict (encodeBundle bundle))
      pure $ T.isInfixOf "\"stateGraphs\"" json
          && T.isInfixOf "\"name\":\"demo\"" json
          && T.isInfixOf "digraph" json

-- | M5 slice 2A: every exported function's schema entry carries a
-- @traceMeta@ block with the function name, body, and parameter
-- references pre-rendered via 'L4.Print.prettyLayout' — the exact
-- strings jl4-service's interpreter uses inside @Reasoning.exampleCode@.
-- The runtime consumes these to synthesise a trace tree at request time
-- without re-implementing the pretty-printer in JavaScript.
testTraceMetaBaked :: IO Bool
testTraceMetaBaked = do
  let src = T.unlines
        [ "@export Is eligible check"
        , "GIVEN `years of service` IS A NUMBER"
        , "GIVETH A BOOLEAN"
        , "DECIDE `is eligible` IF `years of service` >= 3"
        ]
  case checkWithImports emptyVFS src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right r -> do
      let bundle = bundleExports "test.wasm" "test" r.tcdInfoMap (substitutedEntityInfo r) r.tcdModule []
          json = TE.decodeUtf8 (LBS.toStrict (encodeBundle bundle))
      -- The backticked function name (matches jl4-service's prettyLayout
      -- of the AppForm head): a multi-word name is wrapped in backticks.
      let okFnName = T.isInfixOf "\"fnName\":\"`is eligible`\"" json
      -- The body comes out as `<lhs> AT LEAST <rhs>` after prelude
      -- operator rendering. Spot-check that the source-level operator
      -- name and the backticked parameter reference appear; full byte
      -- equality is what the parity harness's trace sub-matrix tracks
      -- downstream as later slices land.
      let okBody = T.isInfixOf "AT LEAST" json
                && T.isInfixOf "`years of service`" json
      let okParams = T.isInfixOf "\"params\":[\"years of service\"]" json
      pure (okFnName && okBody && okParams)

-- | M5 slice 2C: every export carries a @traceMeta.nodes@ array with
-- one 'TraceNode' per traceable subexpression — pre-rendered via
-- 'L4.Print.prettyLayout' and tagged with a 'resultKind' the runtime
-- uses to render @Result: …@ lines. The walk skips 'Lit' and zero-arg
-- @App@ (the 'Var' pattern), mirroring jl4-service's
-- @simplifyEvalTrace@ pruning.
testTraceMetaNodes :: IO Bool
testTraceMetaNodes = do
  -- An IF body with a numeric arithmetic branch — that gives us three
  -- traceable subexpressions: the IfThenElse itself, the Geq guard, and
  -- the Plus body. Skipped: the Lit 0 / Lit 1 / Lit 2 (Lit) and the
  -- Var 'age' references (zero-arg App).
  let src = T.unlines
        [ "@export Bonus point"
        , "GIVEN `age` IS A NUMBER"
        , "GIVETH A NUMBER"
        , "DECIDE `bonus` IS IF `age` >= 18 THEN `age` PLUS 1 ELSE 0"
        ]
  case checkWithImports emptyVFS src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right r -> do
      let bundle = bundleExports "test.wasm" "test" r.tcdInfoMap (substitutedEntityInfo r) r.tcdModule []
          json = TE.decodeUtf8 (LBS.toStrict (encodeBundle bundle))
      -- IfThenElse → kind 0 (NUMBER, via InfoMap on the whole expression).
      -- Geq → kind 1 (BOOLEAN). Plus → kind 0.
      let okIf  = T.isInfixOf "\"id\":0" json && T.isInfixOf "IF " json
          okGeq = T.isInfixOf "AT LEAST" json
                && T.isInfixOf "\"resultKind\":1" json
          okAdd = T.isInfixOf "PLUS" json
                && T.isInfixOf "\"resultKind\":0" json
      pure (okIf && okGeq && okAdd)

-- | M5 slice 2B: every lowered Decide gets a second @func.func@ named
-- @<fn>$trace@ that brackets the body with per-subexpression
-- @__l4_trace_enter(id)@ / @__l4_trace_exit(boxed, kind)@. The runtime
-- calls into this when the request asks for @?trace=full@; the untraced
-- @<fn>@ stays the fast path.
testTraceSymbolEmitted :: IO Bool
testTraceSymbolEmitted = do
  let src = T.unlines
        [ "@export Adult check"
        , "GIVEN `age` IS A NUMBER"
        , "GIVETH A BOOLEAN"
        , "DECIDE `is_adult` IF `age` >= 18"
        ]
  case lowerSource src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right mlir ->
      -- Both symbols must exist, and the trace clone must contain the
      -- runtime calls. The trace exit's kind byte for BOOLEAN is 1.0.
      pure $ T.isInfixOf "func.func @is_adult(" mlir
          && T.isInfixOf "func.func @is_adult$trace(" mlir
          && T.isInfixOf "@__l4_trace_enter" mlir
          && T.isInfixOf "@__l4_trace_exit"  mlir

-- | M5 slice 4A: AND/OR (and direct App "__AND__"/"__OR__") nodes get
-- a @"special"@ marker in the schema so the runtime knows to append a
-- synthetic IF sub-tree and apply short-circuit filtering. This is the
-- mechanism that flips `is-eligible` to byte-identical.
testTraceSpecialMarkers :: IO Bool
testTraceSpecialMarkers = do
  let src = T.unlines
        [ "@export Both"
        , "GIVEN `age` IS A NUMBER"
        , "GIVETH A BOOLEAN"
        , "DECIDE `ok` IS `age` >= 18 AND `age` <= 65"
        ]
  case schemaWithDiagnostics src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right json ->
      pure $ T.isInfixOf "\"special\":\"AND\"" json

-- | An @MEANS@ / @DECIDE … IS@ binding without an explicit @GIVETH@
-- must still surface a concrete 'returnType' in the schema; otherwise
-- the runtime unmarshals NUMBER results as raw f64 (rational handles)
-- and a call like @squared 1@ comes back as @5e-324@ rather than @1@.
-- 'bundleExports' threads the typechecker's 'EntityInfo' so
-- 'enrichReturnTypes' can fill in the missing GIVETH.
testReturnTypeEnrichedFromEntityInfo :: IO Bool
testReturnTypeEnrichedFromEntityInfo = do
  let src = T.unlines
        [ "@export default Cube of a number"
        , "GIVEN n IS A NUMBER"
        , "cubed n MEANS n * n * n"
        ]
  case schemaWithDiagnostics src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right json -> do
      let ok = T.isInfixOf "\"returnType\":\"NUMBER\"" json
      if ok then pure ()
            else putStrLn $ "\n    missing NUMBER returnType. got:\n    " <> T.unpack json
      pure ok

-- | M5 slice 4T: a @NOT P@ expression and its inner @P@ may collapse
-- into the same 'SrcRange' at parse time. The rangeMap is now keyed by
-- '(SrcRange, exprDisambiguator)', so both get distinct trace nodes
-- and the wrapper can look up each by its own AST shape. Verify the
-- schema has BOTH a NOT-tagged node AND a separate PROJ-tagged node
-- for an expression like @NOT req's flag@.
testTraceNotRangeDisambiguation :: IO Bool
testTraceNotRangeDisambiguation = do
  let src = T.unlines
        [ "DECLARE LoanRequest HAS"
        , "    `flag` IS A BOOLEAN"
        , ""
        , "@export Check"
        , "GIVEN req IS A LoanRequest"
        , "GIVETH A BOOLEAN"
        , "DECIDE `ok` IS NOT req's `flag`"
        ]
  case schemaWithDiagnostics src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right json ->
      -- The NOT subtree must exist as one node; the inner PROJ subtree
      -- as another. If the rangeMap collapsed them, the PROJ node would
      -- be missing from the schema (its 'tnSpecial' would be absent).
      pure $ T.isInfixOf "\"special\":\"NOT\"" json
          && T.isInfixOf "\"special\":\"PROJ\"" json

-- | M5 slice 4A: every `<fn>$trace` clone calls @__l4_trace_enter_fn@
-- (with the fn's wasm symbol) at entry and @__l4_trace_exit_fn@ at
-- return, AND emits a fn-value @__l4_trace_enter/exit@ pair so the
-- runtime sees [fn-value, body] frames per call. Without this, nested
-- calls would resolve node IDs against the WRONG function's metadata.
testTraceFnValueAndContext :: IO Bool
testTraceFnValueAndContext = do
  let src = T.unlines
        [ "@export Adult check"
        , "GIVEN `age` IS A NUMBER"
        , "GIVETH A BOOLEAN"
        , "DECIDE `is_adult` IF `age` >= 18"
        ]
  case lowerSource src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right mlir ->
      pure $ T.isInfixOf "func.func @is_adult$trace(" mlir
          && T.isInfixOf "@__l4_trace_enter_fn" mlir
          && T.isInfixOf "@__l4_trace_exit_fn"  mlir

-- | A plain (non-regulative) function has no state graph, so the schema
-- carries an empty stateGraphs array. (M3 negative control)
testNoStateGraphForPlainFn :: IO Bool
testNoStateGraphForPlainFn = do
  let src = T.unlines
        [ "@export Adult check"
        , "GIVEN `age` IS A NUMBER"
        , "GIVETH A BOOLEAN"
        , "DECIDE `is_adult` IF `age` >= 18"
        ]
  case checkWithImports emptyVFS src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right r -> do
      let bundle = bundleExports "test.wasm" "test" r.tcdInfoMap (substitutedEntityInfo r) r.tcdModule []
          json = TE.decodeUtf8 (LBS.toStrict (encodeBundle bundle))
      pure $ T.isInfixOf "\"stateGraphs\":[]" json

-- | Verify that an @export-decorated DECIDE with a referenced ASSUME
-- emits a function whose argument count matches GIVEN + ASSUME.
testExportAssumePromotion :: IO Bool
testExportAssumePromotion = do
  let src = T.unlines
        [ "ASSUME `age` IS A NUMBER"
        , ""
        , "@export Check adult status"
        , "GIVEN `threshold` IS A NUMBER"
        , "GIVETH A BOOLEAN"
        , "DECIDE `is_adult` IF `age` >= `threshold`"
        ]
  case lowerSource src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right mlir ->
      -- Exported function must take two f64 args (threshold + age).
      pure $ T.isInfixOf "func.func @is_adult(%0: f64, %1: f64)" mlir
          || T.isInfixOf "func.func @is_adult(%arg0: f64, %arg1: f64)" mlir

-- | When an internal (non-@export) function calls an @export function
-- that has ASSUME-derived args, the call site should invoke the ASSUME's
-- extern to fill the extra arg rather than pass too few.
testInternalCallFillsAssumes :: IO Bool
testInternalCallFillsAssumes = do
  let src = T.unlines
        [ "ASSUME `age` IS A NUMBER"
        , ""
        , "@export Core rule"
        , "GIVEN `threshold` IS A NUMBER"
        , "GIVETH A BOOLEAN"
        , "DECIDE `is_adult` IF `age` >= `threshold`"
        , ""
        , "GIVETH A BOOLEAN"
        , "DECIDE `adult_at_18` IF `is_adult` OF 18"
        ]
  case lowerSource src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right mlir ->
      -- adult_at_18 must call the @age extern AND call is_adult with two args.
      pure $ T.isInfixOf "func.call @age()" mlir
          && T.isInfixOf "func.call @is_adult" mlir
      && Text.isInfixOf "arith.cmpf" mlir

-- | When the @export-ed function's parameter type is DECLAREd in an
-- IMPORTed module (not in the main file), the schema must still expand
-- the record's fields. Regression test for the ASEAN Cosmetic Directive
-- case where Information.l4 imports Declarations.l4 and the schema came
-- out as bare {"type":"object"}.
testSchemaUsesImportedDeclares :: IO Bool
testSchemaUsesImportedDeclares = do
  let declarations = T.unlines
        [ "DECLARE Widget HAS"
        , "    `serial`  IS A STRING"
        , "    `weight`  IS A NUMBER"
        ]
      info = T.unlines
        [ "IMPORT declarations"
        , ""
        , "@export Inspect a widget"
        , "GIVEN w IS A Widget"
        , "GIVETH A BOOLEAN"
        , "DECIDE `widget ok` IS w's weight > 0"
        ]
      vfs = vfsFromList [("declarations", declarations)]
  case checkWithImportsAndUri vfs "info" info of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right tc -> do
      let mainMod = tc.tcdModule
          depMods = map (\ri -> ri.riTypeChecked.program) tc.tcdResolvedImports
          bundle  = bundleExports "info.wasm" "test" tc.tcdInfoMap (substitutedEntityInfo tc) mainMod depMods
          json    = TE.decodeUtf8 (LBS.toStrict (encodeBundle bundle))
      -- The two field names must appear in the schema — they only show
      -- up if the imported DECLARE was reachable from typeToParameter.
      let ok = T.isInfixOf "\"serial\"" json
            && T.isInfixOf "\"weight\"" json
            && T.isInfixOf "\"propertyOrder\"" json
      unless ok $
        putStrLn $ "\n    schema missing imported fields. got:\n    " <> T.unpack json
      pure ok
  where
    unless b act = if b then pure () else act

-- | A CONSIDER on a STRING with string-literal WHEN patterns must
-- compile each branch test to a @__l4_str_eq@ runtime call (content
-- equality), not an unconditional always-match. Regression test: the
-- @PatLit String@ case used to return @trueI1@, so the first WHEN
-- branch always matched regardless of the scrutinee. Mirrors the
-- @jl4/examples/ok/consider-primitives.l4@ @`classify string`@ fixture
-- but inlined so no IMPORT is needed.
testStringPatternStrEq :: IO Bool
testStringPatternStrEq = do
  let src = T.unlines
        [ "@export Classify a string"
        , "GIVEN s IS A STRING"
        , "GIVETH A NUMBER"
        , "`classify string` MEANS"
        , "  CONSIDER s"
        , "    WHEN \"a\" THEN 1"
        , "    WHEN \"b\" THEN 2"
        , "    OTHERWISE 0"
        ]
  case lowerSource src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right mlir -> do
      let ok = T.isInfixOf "@__l4_str_eq" mlir
      unless ok $
        putStrLn "\n    expected a __l4_str_eq call for the string-literal patterns"
      pure ok
  where
    unless b act = if b then pure () else act

-- | A CONSIDER over the EITHER builtin (payload-carrying LEFT / RIGHT
-- constructor patterns) must compile @supported:true@ and lower to a
-- real tag dispatch — NOT refuse with "could not be resolved to an enum
-- tag". EITHER a b is a payload-CARRYING ADT (like MAYBE), represented
-- as a 2-slot [tag, payload] record: LEFT tagged 0.0, RIGHT tagged 1.0,
-- payload in slot 1. This is the ledger #10 fix; the four orchestrator
-- helpers (isViolation/getConfidence/getAllTests/extractText) used to
-- refuse on exactly these patterns.
--
-- The source both CONSTRUCTS the EITHER (via a helper that returns
-- @RIGHT n@ / @LEFT "neg"@) and DESTRUCTURES it, so it exercises the
-- construction path (@__l4_alloc@ 2-slot record) and the pattern path
-- (@scf.if@ tag dispatch + payload bind) together.
testEitherConsiderSupported :: IO Bool
testEitherConsiderSupported = do
  let src = T.unlines
        [ "GIVEN n IS A NUMBER"
        , "GIVETH AN EITHER STRING NUMBER"
        , "`classify` MEANS"
        , "  IF n GREATER THAN 0 THEN RIGHT n ELSE LEFT \"neg\""
        , ""
        , "@export Either dispatch"
        , "GIVEN n IS A NUMBER"
        , "GIVETH A NUMBER"
        , "`either dispatch` MEANS"
        , "  CONSIDER `classify` n"
        , "    WHEN RIGHT v THEN v TIMES 2"
        , "    WHEN LEFT s THEN 0 MINUS STRINGLENGTH s"
        ]
  case (lowerSource src, schemaWithDiagnostics src) of
    (Left errs, _) -> do
      putStrLn $ "\n    typecheck/lower failed: " <> show errs
      pure False
    (_, Left errs) -> do
      putStrLn $ "\n    schema failed: " <> show errs
      pure False
    (Right mlir, Right json) -> do
      let noRefuse = not (T.isInfixOf "could not be resolved to an enum tag" json)
          supported = T.isInfixOf "\"supported\":true" json
          dispatched = T.isInfixOf "scf.if" mlir
          constructed = T.isInfixOf "__l4_alloc" mlir
          ok = noRefuse && supported && dispatched && constructed
      unless ok $ do
        putStrLn "\n    expected supported:true EITHER dispatch (no enum-tag refusal)."
        putStrLn $ "    noRefuse=" <> show noRefuse <> " supported=" <> show supported
          <> " scf.if=" <> show dispatched <> " __l4_alloc=" <> show constructed
        putStrLn $ "    json: " <> T.unpack (T.take 400 json)
      pure ok
  where
    unless b act = if b then pure () else act

-- | Regression guard for the ledger #10 shadow refutation. A user DECLAREs
-- an @ONE OF@ enum whose constructors are named LEFT / RIGHT and CARRY a
-- payload (@RIGHT HAS rv IS A NUMBER@ / @LEFT HAS lv IS A NUMBER@), then
-- destructures it in a CONSIDER. The builtin-EITHER lowering must NOT
-- intercept these by constructor NAME: the user enum is a different type
-- from the prelude EITHER, its constructor is lowered as a bare tag with no
-- payload slot, and reading slot 1 as if it were EITHER's [tag, payload]
-- record yields a SILENT WRONG answer (jl4-service: rev-dispatch(5)=1005;
-- the buggy WASM returned -995 at supported:true — the cardinal sin).
--
-- The fix gives user-declared constructors priority over the builtin string
-- cases (via 'isUserConstructor'), and — because construction discards the
-- payload of an enum-with-data / record constructor — REFUSES to destructure
-- one. So the export must ship @supported:false@ (→ the proxy routes to the
-- reference evaluator, which returns the correct answer) rather than compute.
testUserEitherShadowUnsupported :: IO Bool
testUserEitherShadowUnsupported = do
  let src = T.unlines
        [ "IMPORT prelude"
        , ""
        , "DECLARE Rev IS ONE OF"
        , "  RIGHT HAS rv IS A NUMBER"
        , "  LEFT  HAS lv IS A NUMBER"
        , ""
        , "GIVEN n IS A NUMBER"
        , "GIVETH A Rev"
        , "`mk rev` MEANS"
        , "  IF n GREATER THAN 0 THEN RIGHT n ELSE LEFT n"
        , ""
        , "@export rev dispatch"
        , "GIVEN n IS A NUMBER"
        , "GIVETH A NUMBER"
        , "`rev dispatch` MEANS"
        , "  CONSIDER `mk rev` n"
        , "    WHEN LEFT  a THEN a MINUS 1000"
        , "    WHEN RIGHT b THEN b PLUS 1000"
        ]
  case schemaWithDiagnostics src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right json -> do
      let ok = T.isInfixOf "\"supported\":false" json
            && T.isInfixOf "payload-carrying user constructor" json
      unless ok $
        putStrLn $ "\n    expected supported:false for the user LEFT/RIGHT enum. got:\n    "
          <> T.unpack (T.take 700 json)
      pure ok
  where
    unless b act = if b then pure () else act

-- | Fail-closed guard for the enum-with-data ABI-return silent-wrong. An
-- @\@export@ whose GIVETH return type is a payload-carrying enum
-- (@ONE OF … HAS …@) cannot be marshalled across the f64 ABI: construction
-- lowers a constructor like @RIGHT n@ to a BARE enum tag (the payload is
-- discarded), so the WASM return carries only the tag while jl4-service
-- returns the full @{"RIGHT":{"rv":n}}@ value — a SILENT WRONG at
-- @supported:true@ (@mk rev 5@ → WASM @0@ vs service @{"RIGHT":{"rv":5}}@).
-- The export must therefore ship @supported:false@ so the proxy routes it to
-- the reference evaluator. This is name-independent (not a LEFT/RIGHT
-- artefact); nullary enums and records marshal faithfully and stay supported.
testDataEnumReturnUnsupported :: IO Bool
testDataEnumReturnUnsupported = do
  let src = T.unlines
        [ "IMPORT prelude"
        , ""
        , "DECLARE Res IS ONE OF"
        , "  FOO HAS fv IS A NUMBER"
        , "  BAR HAS bv IS A NUMBER"
        , ""
        , "@export make res"
        , "GIVEN n IS A NUMBER"
        , "GIVETH A Res"
        , "`make res` MEANS"
        , "  IF n GREATER THAN 0 THEN FOO n ELSE BAR n"
        ]
  case schemaWithDiagnostics src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right json -> do
      let ok = T.isInfixOf "\"supported\":false" json
            && T.isInfixOf "enum-with-data type" json
      unless ok $
        putStrLn $ "\n    expected supported:false for the enum-with-data return. got:\n    "
          <> T.unpack (T.take 700 json)
      pure ok
  where
    unless b act = if b then pure () else act

-- | A CONSIDER whose WHEN guard is a computed expression (@EXACTLY
-- <expr>@, parsed to 'PatExpr') cannot be evaluated as a guard by the
-- WASM backend. It used to always-match (return @trueI1@) and ship as
-- @supported:true@; now the enclosing function must be flagged
-- @supported:false@ so the proxy routes it to a fallback evaluator.
testPatExprUnsupported :: IO Bool
testPatExprUnsupported = do
  let src = T.unlines
        [ "@export Compute"
        , "GIVEN n IS A NUMBER"
        , "GIVETH A NUMBER"
        , "`compute` MEANS"
        , "  CONSIDER n"
        , "    WHEN EXACTLY 3 THEN 6"
        , "    OTHERWISE 0"
        ]
  case schemaWithDiagnostics src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right json -> do
      let ok = T.isInfixOf "\"supported\":false" json
            && T.isInfixOf "computed-expression pattern" json
      unless ok $
        putStrLn $ "\n    expected supported:false for the EXACTLY pattern. got:\n    "
          <> T.unpack (T.take 600 json)
      pure ok
  where
    unless b act = if b then pure () else act

-- | Two genuinely-different top-level definitions that share a name AND
-- an arity (ad-hoc overloads distinguished only by parameter type — the
-- real case is @daydate@'s four arity-1 @Date@ overloads) mangle to one
-- WASM symbol. The dedup post-pass silently keeps only the FIRST body;
-- we now detect the collision during lowering and flag the export
-- @supported:false@ instead of silently dispatching to the wrong body.
-- A third definition at a DIFFERENT arity forces name mangling on, so
-- the arity-1 pair actually collides on @blend__$1@.
testOverloadCollisionUnsupported :: IO Bool
testOverloadCollisionUnsupported = do
  let src = T.unlines
        [ "@export Blend"
        , "GIVEN x IS A NUMBER"
        , "GIVETH A NUMBER"
        , "`blend` MEANS x PLUS 1"
        , ""
        , "GIVEN s IS A STRING"
        , "GIVETH A NUMBER"
        , "`blend` MEANS 2"
        , ""
        , "GIVEN x IS A NUMBER"
        , "      y IS A NUMBER"
        , "GIVETH A NUMBER"
        , "`blend` MEANS x PLUS y"
        ]
  case schemaWithDiagnostics src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right json -> do
      let ok = T.isInfixOf "\"supported\":false" json
            && T.isInfixOf "overload collision" json
      unless ok $
        putStrLn $ "\n    expected supported:false for the colliding overload. got:\n    "
          <> T.unpack (T.take 700 json)
      pure ok
  where
    unless b act = if b then pure () else act

-- | Two NON-exported helpers sharing a name AND arity but differing in argument
-- type (NUMBER vs STRING) must lower to DISTINCT WASM symbols so each call site
-- dispatches to the right body — the same-arity-overload fix. (Contrast
-- 'testOverloadCollisionUnsupported', where the colliding overload is @export'd
-- and so stays API-ambiguous → supported:false.) Without the fix both bodies
-- collapse to one @blend@ symbol and the dedup drops one.
testOverloadSameArityDispatch :: IO Bool
testOverloadSameArityDispatch = do
  let src = T.unlines
        [ "GIVEN x IS A NUMBER"
        , "GIVETH A NUMBER"
        , "`blend` MEANS x PLUS 1"
        , ""
        , "GIVEN s IS A STRING"
        , "GIVETH A NUMBER"
        , "`blend` MEANS 2"
        , ""
        , "@export Use both overloads"
        , "GIVEN n IS A NUMBER"
        , "      t IS A STRING"
        , "GIVETH A NUMBER"
        , "`use both` MEANS (`blend` n) PLUS (`blend` t)"
        ]
  case lowerSource src of
    Left errs -> do
      putStrLn $ "\n    typecheck/lower failed: " <> show errs
      pure False
    Right mlir -> do
      -- Both overload bodies must survive, under distinct disambiguated symbols.
      let ok = T.isInfixOf "blend__ov0" mlir && T.isInfixOf "blend__ov1" mlir
      unless' ok $
        putStrLn $ "\n    expected distinct blend__ov0/blend__ov1 symbols. got:\n    "
          <> T.unpack (T.take 700 mlir)
      pure ok
  where
    unless' b act = if b then pure () else act

-- | A bare-head DECIDE (@DECIDE factorial x IS …@, no GIVEN) must get its
-- param type from the typechecker's inferred Fun type ('enrichParamTypes'),
-- not default to @{"type":"object"}@. The object default made 'marshalArg'
-- treat the JSON number as a struct → pointer 0.0 → which, read as a
-- rational-pool handle, aliased the interned literal 0 — so factorial
-- returned 1 for EVERY input while claiming supported:true. The last of the
-- parity hunt's silent wrong answers (ledger #9 in PARITY-HUNT-LOG.md).
testBareHeadParamTyped :: IO Bool
testBareHeadParamTyped = do
  let src = T.unlines
        [ "@export default Factorial of a number"
        , "DECIDE factorial x IS"
        , "  IF x EQUALS 0"
        , "  THEN 1"
        , "  ELSE x * factorial (x - 1)"
        ]
  case schemaWithDiagnostics src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right json -> do
      let ok = T.isInfixOf "\"x\":{\"type\":\"number\"}" json
            && not (T.isInfixOf "\"x\":{\"type\":\"object\"}" json)
      unless' ok $
        putStrLn $ "\n    expected bare-head param x typed number via EntityInfo. got:\n    "
          <> T.unpack (T.take 700 json)
      pure ok
  where
    unless' b act = if b then pure () else act

-- | Two DIFFERENT functions, each with its own recursive WHERE helper that
-- happens to share the name @go@ AND its arity, must lower to DISTINCT WASM
-- symbols. Local helper names are scoped in L4 but flat once lambda-lifted,
-- so before the fix both lifted to the bare symbol @go@ and the arity-only
-- mangle collapsed them into ONE body — whichever won. This is not
-- hypothetical: @prelude@ defines ten separate @go@ helpers, and @count@'s
-- won, so @sum [2,3,4]@ returned 3 (the LENGTH) and @product [2,3,4]@
-- returned 4. Here @adder@'s @go@ sums and @multiplier@'s @go@ multiplies;
-- if they collapse, one of the two bodies is silently gone.
testLocalHelperDistinctSymbols :: IO Bool
testLocalHelperDistinctSymbols = do
  let src = T.unlines
        [ "@export Sum a list"
        , "GIVEN xs IS A LIST OF NUMBER"
        , "GIVETH A NUMBER"
        , "`adder` MEANS go 0 xs"
        , "  WHERE"
        , "    go acc l MEANS"
        , "      CONSIDER l"
        , "      WHEN EMPTY THEN acc"
        , "      WHEN x FOLLOWED BY rest THEN go (acc PLUS x) rest"
        , ""
        , "@export Multiply a list"
        , "GIVEN xs IS A LIST OF NUMBER"
        , "GIVETH A NUMBER"
        , "`multiplier` MEANS go 1 xs"
        , "  WHERE"
        , "    go acc l MEANS"
        , "      CONSIDER l"
        , "      WHEN EMPTY THEN acc"
        , "      WHEN x FOLLOWED BY rest THEN go (acc TIMES x) rest"
        ]
  case lowerSource src of
    Left errs -> do
      putStrLn $ "\n    typecheck/lower failed: " <> show errs
      pure False
    Right mlir -> do
      -- Each lifted helper gets its own numbered symbol, so BOTH the adding
      -- body (__l4_rat_add) and the multiplying body (__l4_rat_mul) survive.
      let ok = T.isInfixOf "go__loc0" mlir
            && T.isInfixOf "go__loc1" mlir
            && T.isInfixOf "__l4_rat_add" mlir
            && T.isInfixOf "__l4_rat_mul" mlir
      unless' ok $
        putStrLn $ "\n    expected distinct go__loc0/go__loc1 helpers keeping both\n\
                   \    the add and the mul body. got:\n    "
          <> T.unpack (T.take 700 mlir)
      pure ok
  where
    unless' b act = if b then pure () else act

-- | An exported function that transitively calls an unsupported HELPER must
-- itself be marked @supported: false@ — call-graph diagnostic propagation.
--
-- 'markUnsupported' keys a diagnostic on the *enclosing* function, but
-- 'applyDiagnostics' only downgrades entries in @bundleExports@. A helper is
-- not an export, so without propagation the export stayed @supported: true@
-- and the proxy ran a WASM module that cannot evaluate it — the helper's
-- fail-closed FALSE surfaced as a silently WRONG answer instead of a refusal.
--
-- Here @risky@ uses an @EXACTLY@ computed pattern (unsupported by the WASM
-- backend; see 'testPatExprUnsupported'), and the exported @gate@ only
-- reaches it through @middle@, so the diagnostic must travel two hops up
-- the call graph. (Ordered STRING comparison used to be the vehicle here,
-- but it now compiles through @__l4_str_cmp@ — ledger #7 — so this test
-- switched to a construct that still legitimately refuses.)
testDiagnosticPropagatesToCaller :: IO Bool
testDiagnosticPropagatesToCaller = do
  let src = T.unlines
        [ "GIVEN a IS A NUMBER"
        , "GIVETH A NUMBER"
        , "`risky` MEANS"
        , "  CONSIDER a"
        , "    WHEN EXACTLY 3 THEN 6"
        , "    OTHERWISE 0"
        , ""
        , "GIVEN a IS A NUMBER"
        , "GIVETH A NUMBER"
        , "`middle` MEANS `risky` a"
        , ""
        , "@export Gate"
        , "GIVEN a IS A NUMBER"
        , "GIVETH A NUMBER"
        , "`gate` MEANS `middle` a"
        ]
  case schemaWithDiagnostics src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right json -> do
      let ok = T.isInfixOf "\"supported\":false" json
            && T.isInfixOf "depends on" json
      unless' ok $
        putStrLn $ "\n    expected the export to inherit its helper's diagnostic. got:\n    "
          <> T.unpack (T.take 700 json)
      pure ok
  where
    unless' b act = if b then pure () else act

-- | Regression for the @lowerCmp@ rational-handle bug. The 'InfoMap' we
-- read is not run through the final substitution, so 'typeOfExpr' returns
-- @Just (InfVar …)@ for a bare NUMBER @Var@ — neither NUMBER nor STRING.
-- The fix must NOT let that 'InfVar' short-circuit the resolution: it
-- falls through to 'bindingL4Types', recovers the param's NUMBER type, and
-- routes the comparison through @__l4_rat_cmp@. A NUMBER is a rational-pool
-- /handle/, so a raw @arith.cmpf@ on it would compare handle bit-patterns
-- and almost always yield the wrong boolean. (Equality is used here so the
-- arithmetic-shape fallback can't rescue it — only the type resolution can.)
testNumberCmpInfoMapMiss :: IO Bool
testNumberCmpInfoMapMiss = do
  let src = T.unlines
        [ "@export Compare"
        , "GIVEN a IS A NUMBER"
        , "      b IS A NUMBER"
        , "GIVETH A BOOLEAN"
        , "`g` MEANS a EQUALS b"
        ]
  case lowerSource src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right mlir -> do
      let ok = T.isInfixOf "@__l4_rat_cmp" mlir
            && not (bareCmpf mlir)
      unless ok $
        putStrLn "\n    expected __l4_rat_cmp (not a raw arith.cmpf on handles)"
      pure ok
  where
    unless b act = if b then pure () else act

-- | Regression for the STRING half of the same bug. A STRING is a
-- string-pool /pointer/; equality must go through @__l4_str_eq@ (content
-- equality). Before the fix, 'typeOfExpr' returned @Just (InfVar …)@ for
-- the STRING params and the old @isStringExpr@ (which trusted that @Just@
-- and had no 'bindingL4Types' fallback) reported "not a string", so
-- @a EQUALS b@ lowered to @arith.cmpf oeq@ on the two pointer
-- bit-patterns — wrong for equal-content strings interned at different
-- addresses. The fix recovers STRING from 'bindingL4Types' and emits
-- @__l4_str_eq@.
testStringEqInfoMapMiss :: IO Bool
testStringEqInfoMapMiss = do
  let src = T.unlines
        [ "@export Compare"
        , "GIVEN a IS A STRING"
        , "      b IS A STRING"
        , "GIVETH A BOOLEAN"
        , "`g` MEANS a EQUALS b"
        ]
  case lowerSource src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right mlir -> do
      let ok = T.isInfixOf "@__l4_str_eq" mlir
            && not (bareCmpf mlir)
      unless ok $
        putStrLn "\n    expected __l4_str_eq (not a raw arith.cmpf on string pointers)"
      pure ok
  where
    unless b act = if b then pure () else act

-- | Ordered comparison on STRING (@<@) lowers through @__l4_str_cmp@
-- (content ordering, lexicographic by Unicode code point to match
-- jl4-core's Data.Text Ord). The runtime returns -1.0\/0.0\/1.0 and the
-- source predicate is re-applied against 0.0 — exactly like the NUMBER
-- path uses @__l4_rat_cmp@. There must be NO bare @arith.cmpf@ on the raw
-- string-pool pointers (that would order addresses, not contents).
testStringOrderedStrCmp :: IO Bool
testStringOrderedStrCmp = do
  let src = T.unlines
        [ "@export Compare"
        , "GIVEN a IS A STRING"
        , "      b IS A STRING"
        , "GIVETH A BOOLEAN"
        , "`g` MEANS a LESS THAN b"
        ]
  case lowerSource src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right mlir -> do
      let ok = T.isInfixOf "@__l4_str_cmp" mlir
            && not (bareCmpf mlir)
      unless ok $
        putStrLn $ "\n    expected __l4_str_cmp (not a raw arith.cmpf on string pointers). got:\n    "
          <> T.unpack (T.take 700 mlir)
      pure ok
  where
    unless b act = if b then pure () else act

-- | When neither operand's type can be resolved by any source, the
-- compiler must fail loud rather than emit a raw @arith.cmpf@ on values
-- that might be pool handles or pointers. Since the bundle-wide
-- 'funcL4Types' map landed, a MONOMORPHIC helper's call result classifies
-- by its checked return type (see 'testHelperResultStringEq'), so the
-- unresolvable case needs a POLYMORPHIC helper: @echo : Forall a. a -> a@
-- has a type-variable return slot, which is syntactically a nullary
-- 'TyApp' — trusting it as a raw-f64 comparison key would emit an
-- @arith.cmpf@ on string-pool pointers at THIS instantiation. The
-- conservative 'classifyGroundType' must refuse it, and the export is
-- flagged @supported:false@. (This is the tyvar-hazard guard, tested
-- directly.)
testUnresolvableCmpUnsupported :: IO Bool
testUnresolvableCmpUnsupported = do
  let src = T.unlines
        [ "GIVEN a IS A TYPE"
        , "      x IS AN a"
        , "GIVETH AN a"
        , "`echo` MEANS x"
        , ""
        , "@export Compare"
        , "GIVEN a IS A STRING"
        , "      b IS A STRING"
        , "GIVETH A BOOLEAN"
        , "`g` MEANS (`echo` OF a) EQUALS (`echo` OF b)"
        ]
  case schemaWithDiagnostics src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right json -> do
      let ok = T.isInfixOf "\"supported\":false" json
            && T.isInfixOf "could not be resolved" json
      unless ok $
        putStrLn $ "\n    expected supported:false for the unresolvable comparison. got:\n    "
          <> T.unpack (T.take 700 json)
      pure ok
  where
    unless b act = if b then pure () else act

-- | Ledger #6 — a comparison whose operands are helper CALL RESULTS.
-- 'funcSigs' only records MLIR types (all f64 under the uniform ABI), so
-- this used to be unclassifiable and refused. The bundle-wide
-- 'funcL4Types' map recovers the callee's checked NUMBER return type, and
-- the comparison routes through @__l4_rat_cmp@ — never a raw @arith.cmpf@
-- on the two rational-pool handles. Both operands are calls, so no
-- literal or param can rescue the classification: this exercises the
-- entity-map path itself.
testHelperResultNumberCmp :: IO Bool
testHelperResultNumberCmp = do
  let src = T.unlines
        [ "GIVEN x IS A NUMBER"
        , "GIVETH A NUMBER"
        , "`double` MEANS x TIMES 2"
        , ""
        , "@export Compare helper results"
        , "GIVEN a IS A NUMBER"
        , "      b IS A NUMBER"
        , "GIVETH A BOOLEAN"
        , "`g` MEANS (`double` OF a) GREATER THAN (`double` OF b)"
        ]
  case lowerSource src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right mlir -> do
      let ok = T.isInfixOf "@__l4_rat_cmp" mlir
            && not (bareCmpf mlir)
      unless ok $
        putStrLn "\n    expected __l4_rat_cmp for helper-result NUMBER comparison"
      pure ok
  where
    unless b act = if b then pure () else act

-- | The daydate @is weekend@ shape that kept @is-a-weekday@ refusing
-- (ledger #6): a zero-arg WHERE local bound to a helper call, compared
-- against a zero-arg top-level MEANS constant. Neither side is a literal
-- or a typed param — the local has no recorded source type and the
-- constant has no GIVETH — so classification must come from the entity
-- map (the constant's INFERRED NUMBER type, and/or the local's), routing
-- the comparison through @__l4_rat_cmp@.
testWhereLocalVsConstantCmp :: IO Bool
testWhereLocalVsConstantCmp = do
  let src = T.unlines
        [ "`saturday` MEANS 6"
        , ""
        , "GIVEN days IS A NUMBER"
        , "GIVETH A NUMBER"
        , "`weekday of` MEANS days MODULO 7"
        , ""
        , "@export Is it saturday"
        , "GIVEN days IS A NUMBER"
        , "GIVETH A BOOLEAN"
        , "`probe` MEANS w EQUALS saturday"
        , "  WHERE"
        , "    w MEANS `weekday of` days"
        ]
  case lowerSource src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right mlir -> do
      let ok = T.isInfixOf "@__l4_rat_cmp" mlir
            && not (bareCmpf mlir)
      unless ok $
        putStrLn "\n    expected __l4_rat_cmp for WHERE-local vs zero-arg constant"
      pure ok
  where
    unless b act = if b then pure () else act

-- | The monomorphic sibling of 'testUnresolvableCmpUnsupported' — and its
-- pre-'funcL4Types' fixture, verbatim. A STRING-returning helper's call
-- result now classifies via the entity map, so equality on two such
-- results compiles through @__l4_str_eq@ (content equality) instead of
-- refusing — and crucially not through a raw @arith.cmpf@ on the two
-- string-pool pointers.
testHelperResultStringEq :: IO Bool
testHelperResultStringEq = do
  let src = T.unlines
        [ "GIVEN x IS A STRING"
        , "GIVETH A STRING"
        , "`echo` MEANS x"
        , ""
        , "@export Compare"
        , "GIVEN a IS A STRING"
        , "      b IS A STRING"
        , "GIVETH A BOOLEAN"
        , "`g` MEANS (`echo` OF a) EQUALS (`echo` OF b)"
        ]
  case lowerSource src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right mlir -> do
      let ok = T.isInfixOf "@__l4_str_eq" mlir
            && not (bareCmpf mlir)
      unless ok $
        putStrLn "\n    expected __l4_str_eq for helper-result STRING equality"
      pure ok
  where
    unless b act = if b then pure () else act

-- | True when the MLIR contains a raw @arith.cmpf@ that is NOT part of a
-- type-guaranteed comparison path (@__l4_rat_cmp@, @__l4_str_eq@ and
-- @__l4_str_cmp@ all legitimately follow up with an @arith.cmpf@ against a
-- constant to turn their f64 result into an @i1@). Used to assert the
-- rational-handle / string-pointer bug is gone.
bareCmpf :: T.Text -> Bool
bareCmpf mlir =
  T.isInfixOf "arith.cmpf" mlir
    && not (T.isInfixOf "@__l4_rat_cmp" mlir)
    && not (T.isInfixOf "@__l4_str_eq" mlir)
    && not (T.isInfixOf "@__l4_str_cmp" mlir)

-- | Basic tests for the L4 MLIR compiler.
--
-- Tests the MLIR IR construction and emission (no external toolchain needed).
-- Integration tests that require mlir-opt / wasmtime are separate.
module Main (main) where

import qualified Data.Text as Text
import System.Exit (ExitCode (..), exitFailure, exitSuccess)
import System.Directory (findExecutable)
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (proc, readCreateProcessWithExitCode)

import qualified Data.Text as T

import L4.MLIR.IR
import L4.MLIR.Emit (renderMLIR)
import L4.MLIR.Dialect.Func
import L4.MLIR.Dialect.Arith
import L4.MLIR.Dialect.SCF
import L4.MLIR.Runtime.Builtins (builtinDeclarations)
import L4.MLIR.Lower (lowerProgramWithInfo, lowerProgramWithDiagnostics)
import L4.MLIR.Schema (bundleExports, applyDiagnostics, encodeBundle, FunctionExport)

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Aeson.Key
import qualified Data.Aeson.KeyMap as Aeson.KeyMap

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

-- | A party and an action whose names need backticks in L4 source are baked
-- into the schema as their PLAIN names, as bare strings a runtime that predates
-- the tag reads correctly, with @partyKind@ \/ @actionKind@ = @"name"@ beside
-- them so the runtime can backtick them again in the trace's source text.
-- jl4-service spells them plain in an answer (@Backend.Jl4.partyText@ \/
-- @actionText@). They used to be baked as source, backticks included. An action
-- that carries a value stays rule source, with no kind key.
testDeonticNamesPlain :: IO Bool
testDeonticNamesPlain = do
  let src = T.unlines
        [ "DECLARE Party IS ONE OF `the seller`"
        , "DECLARE Action IS ONE OF `deliver the goods`"
        , ""
        , "@export Demo obligation"
        , "GIVETH A DEONTIC OF Party, Action"
        , "`demo` MEANS"
        , "    PARTY `the seller`"
        , "    MUST `deliver the goods`"
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
            [ ("party is a plain string",  T.isInfixOf "\"party\":\"the seller\"" json)
            , ("action is a plain string", T.isInfixOf "\"action\":\"deliver the goods\"" json)
            , ("party is tagged a name",   T.isInfixOf "\"partyKind\":\"name\"" json)
            , ("action is tagged a name",  T.isInfixOf "\"actionKind\":\"name\"" json)
            ]
      let failures = [name | (name, ok) <- checks, not ok]
      case failures of
        [] -> pure True
        _  -> do
          putStrLn $ "\n    failing checks: " <> show failures
          putStrLn $ "    json: " <> T.unpack (T.take 600 json)
          pure False

-- | The party of an explicit @BREACH BY@ is baked as its PLAIN name, as
-- jl4-service answers it, not as rule source with backticks: @lest.by@ is
-- @the borrower@, and the BECAUSE text stays the rule source it is.
testDeonticBreachByPlain :: IO Bool
testDeonticBreachByPlain = do
  let src = T.unlines
        [ "DECLARE Party IS ONE OF `the borrower`"
        , "DECLARE Action IS ONE OF `repay loan`"
        , ""
        , "@export Demo obligation"
        , "GIVETH A DEONTIC OF Party, Action"
        , "`demo` MEANS"
        , "    PARTY `the borrower`"
        , "    MUST `repay loan`"
        , "    WITHIN 30"
        , "    HENCE FULFILLED"
        , "    LEST BREACH BY `the borrower` BECAUSE \"not repaid\""
        ]
  case schemaWithDiagnostics src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right json -> do
      let checks :: [(String, Bool)]
          checks =
            [ ("by is a plain name",    T.isInfixOf "\"by\":\"the borrower\"" json)
            , ("by is tagged a name",   T.isInfixOf "\"byKind\":\"name\"" json)
            , ("because is rule source", T.isInfixOf "\"because\":\"\\\"not repaid\\\"\"" json)
            ]
      let failures = [name | (name, ok) <- checks, not ok]
      case failures of
        [] -> pure True
        _  -> do
          putStrLn $ "\n    failing checks: " <> show failures
          putStrLn $ "    json: " <> T.unpack (T.take 600 json)
          pure False

-- | The tag of a @BREACH BY@ party survives a read and a write of the bundle,
-- and a bundle without it (compiled before the key existed) reads as it always
-- did: the party is source, and is written back without the key.
testDeonticBreachByRoundTrip :: IO Bool
testDeonticBreachByRoundTrip = do
  let src = T.unlines
        [ "DECLARE Party IS ONE OF `the borrower`"
        , "DECLARE Action IS ONE OF `repay loan`"
        , ""
        , "@export Demo obligation"
        , "GIVETH A DEONTIC OF Party, Action"
        , "`demo` MEANS"
        , "    PARTY `the borrower`"
        , "    MUST `repay loan`"
        , "    WITHIN 30"
        , "    HENCE FULFILLED"
        , "    LEST BREACH BY `the borrower` BECAUSE \"not repaid\""
        ]
      stripKey k v = case v of
        Aeson.Object o -> Aeson.Object (Aeson.KeyMap.map (stripKey k) (Aeson.KeyMap.delete (Aeson.Key.fromText k) o))
        Aeson.Array a  -> Aeson.Array (fmap (stripKey k) a)
        other          -> other
      rewrite :: Aeson.Value -> Either String T.Text
      rewrite v = do
        fe <- case v of
          Aeson.Object o | Just (Aeson.Object fns) <- Aeson.KeyMap.lookup "functions" o
                         , Just f <- Aeson.KeyMap.lookup "demo" fns -> Right f
          _ -> Left "no function demo in the bundle"
        fx <- either (Left . ("decode: " <>)) Right (decodeExport (Aeson.encode fe))
        pure (TE.decodeUtf8 (LBS.toStrict (Aeson.encode fx)))
      decodeExport :: LBS.ByteString -> Either String FunctionExport
      decodeExport = Aeson.eitherDecode
  case schemaWithDiagnostics src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right json ->
      case Aeson.eitherDecode (LBS.fromStrict (TE.encodeUtf8 json)) of
        Left err -> putStrLn ("\n    bundle is not JSON: " <> err) >> pure False
        Right v -> case (rewrite v, rewrite (stripKey "byKind" v)) of
          (Right kept, Right older) -> do
            let checks :: [(String, Bool)]
                checks =
                  [ ("the tag survives a round trip",      T.isInfixOf "\"byKind\":\"name\"" kept)
                  , ("the party is still the plain name",  T.isInfixOf "\"by\":\"the borrower\"" kept)
                  , ("an older bundle reads without it",   T.isInfixOf "\"by\":\"the borrower\"" older)
                  , ("and is written back without it",     not (T.isInfixOf "byKind" older))
                  ]
                failures = [name | (name, ok) <- checks, not ok]
            if null failures then pure True else do
              putStrLn $ "\n    failing checks: " <> show failures
              pure False
          (a, b) -> putStrLn ("\n    " <> show (either id (const "ok") a, either id (const "ok") b)) >> pure False

-- | An action that carries a value is not a name: it is baked as the rule
-- source it is, as @Backend.Jl4.actionText@ prints it, with no @actionKind@;
-- only a bare name is baked plain and tagged.
testDeonticValueActionIsSource :: IO Bool
testDeonticValueActionIsSource = do
  let src = T.unlines
        [ "DECLARE Party IS ONE OF Alice"
        , "DECLARE Action IS ONE OF say HAS text IS A STRING"
        , ""
        , "@export Demo obligation"
        , "GIVETH A DEONTIC OF Party, Action"
        , "`demo` MEANS"
        , "    PARTY Alice"
        , "    MUST say \"pay\""
        , "    WITHIN 10"
        , "    HENCE FULFILLED"
        ]
  case schemaWithDiagnostics src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right json -> do
      let want = "\"action\":\"say \\\"pay\\\"\""
      if T.isInfixOf want json && not (T.isInfixOf "\"actionKind\"" json)
        then pure True
        else do
          putStrLn $ "\n    expected " <> T.unpack want
          putStrLn $ "    json: " <> T.unpack (T.take 600 json)
          pure False

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
    , test "deontic party/action names are plain, tagged" testDeonticNamesPlain
    , test "deontic value-carrying action stays source" testDeonticValueActionIsSource
    , test "deontic BREACH BY party is plain" testDeonticBreachByPlain
    , test "deontic BREACH BY tag round-trips" testDeonticBreachByRoundTrip
    , test "plain fn stays supported"          testPlainFunctionSupported
    , test "REFUSE marks the export unsupported" testRefuseUnsupported
    , test "jl4-mlir run declines an unsupported export" testRunDeclinesUnsupported
    , test "deontic REFUSE after HENCE is unsupported" $
        testDeonticRefuse False ["MUST `pay`", "WITHIN 10", "HENCE REFUSE \"after payment\""]
    , test "deontic REFUSE after LEST is unsupported" $
        testDeonticRefuse False ["MUST `pay`", "WITHIN 10", "LEST REFUSE \"after a miss\""]
    , test "deontic REFUSE in a HENCE branch is unsupported" $
        testDeonticRefuse False ["MUST `pay`", "WITHIN 10", "HENCE IF `late` THEN REFUSE \"late payment\" ELSE FULFILLED"]
    , test "deontic HENCE branch with no REFUSE stays supported" $
        testDeonticRefuse True ["MUST `pay`", "WITHIN 10", "HENCE IF `late` THEN BREACH ELSE FULFILLED"]
    , test "deontic REFUSE in PROVIDED is unsupported" $
        testDeonticRefuse False ["MUST `pay` PROVIDED REFUSE \"no guard modelled\"", "WITHIN 10"]
    , test "deontic REFUSE in WITHIN is unsupported" $
        testDeonticRefuse False ["MUST `pay`", "WITHIN REFUSE \"no deadline modelled\""]
    , test "REFUSE in a called definition is unsupported" $
        testExportMark refuseMark [] (feeInYear oldFeeRefuses "`the old fee`")
    , test "a called definition with no REFUSE stays supported" $
        testExportMark Nothing [] (feeInYear oldFeeIsFifty "`the old fee`")
    , test "REFUSE two calls away is unsupported" $
        testExportMark refuseMark []
          (feeInYear (oldFeeRefuses <> ["", "GIVEN y IS A NUMBER", "GIVETH A NUMBER", "`the old fee in year` y MEANS `the old fee`"])
                     "`the old fee in year` y")
    , test "REFUSE in the second of two called definitions is unsupported" $
        testExportMark refuseMark []
          (feeInYear (firstFeeIsFifty <> [""] <> oldFeeRefuses) "`the first fee` PLUS `the old fee`")
    , test "REFUSE in the first of two called definitions is unsupported" $
        testExportMark refuseMark []
          (feeInYear (oldFeeRefuses <> [""] <> firstFeeIsFifty) "`the first fee` PLUS `the old fee`")
    , test "REFUSE in a definition called WITH named inputs is unsupported" $
        testExportMark refuseMark []
          (feeInYear ["GIVEN n IS A NUMBER", "GIVETH A NUMBER", "`the old fee for` n MEANS REFUSE \"fees before 2000 are not encoded\""]
                     "`the old fee for` WITH n IS y")
    , test "REFUSE in a computed field the export reads is unsupported" $
        testExportMark refuseMark [] adultFieldRefuses
    , test "REFUSE in a WHERE definition is unsupported" $
        testExportMark refuseMark []
          (feeInYear [] "`the old fee`" <> ["  WHERE", "    `the old fee` MEANS REFUSE \"fees before 2000 are not encoded\""])
    , test "REFUSE in a LET in the export's body is unsupported" $
        testExportMark refuseMark []
          (feeInYear [] "LET x MEANS REFUSE \"fees before 2000 are not encoded\" IN x PLUS 1")
    , test "REFUSE in the last clause of a clause group is unsupported" $
        testExportMark refuseMark []
          (feeInYear (oldFeeClauses "50" "REFUSE \"other years are not encoded\"") "`the old fee` y")
    , test "REFUSE in the first clause of a clause group is unsupported" $
        testExportMark refuseMark []
          (feeInYear (oldFeeClauses "REFUSE \"year zero is not encoded\"" "50") "`the old fee` y")
    , test "a clause group with no REFUSE stays supported" $
        testExportMark Nothing []
          (feeInYear (oldFeeClauses "50" "60") "`the old fee` y")
    , test "REFUSE in a definition called by its AKA name is unsupported" $
        testExportMark refuseMark []
          (feeInYear ["GIVETH A NUMBER", "`the old fee` AKA `the fee before 2000` MEANS REFUSE \"fees before 2000 are not encoded\""]
                     "`the fee before 2000`")
    , test "REFUSE reached through mutual recursion is unsupported" $
        testExportMark refuseMark [] parityRefusesBelowZero
    , test "a recursive definition with no REFUSE stays supported" $
        testExportMark Nothing [] factorialExport
    , test "REFUSE in a definition named by HENCE is unsupported" $
        testExportMark refuseMark [] (deonticHenceNamed ["REFUSE \"what follows payment is not modelled\""])
    , test "a definition named by HENCE with no REFUSE stays supported" $
        testExportMark Nothing [] (deonticHenceNamed ["FULFILLED"])
    , test "REFUSE in an imported definition is unsupported" $
        testExportMark refuseMark [("fees", T.unlines oldFeeRefuses)]
          ("IMPORT fees" : "" : feeInYear [] "`the old fee`")
    , test "an imported definition with no REFUSE stays supported" $
        testExportMark Nothing [("fees", T.unlines oldFeeIsFifty)]
          ("IMPORT fees" : "" : feeInYear [] "`the old fee`")
    , test "REFUSE two imports away, through a module imported twice, is unsupported" $
        testExportMark refuseMark importDiamond
          ("IMPORT older" : "IMPORT newer" : "" : feeInYear [] "`the old fee in year` y")
    , test "REFUSE beside another unsupported construct names both reasons" $
        testExportMark (Just (refuseReason <> "; lambda / higher-order function not supported by the WASM backend")) []
          [ "IMPORT prelude"
          , ""
          , "@export Mixed"
          , "GIVEN n IS A NUMBER"
          , "GIVETH A NUMBER"
          , "`mixed` n MEANS"
          , "    IF n > 0"
          , "    THEN sum (map (GIVEN x YIELD x PLUS 1) (LIST n))"
          , "    ELSE REFUSE \"not modelled\""
          ]
    , test "state graph baked into schema"     testStateGraphBaked
    , test "no state graph for plain fn"       testNoStateGraphForPlainFn
    , test "traceMeta pretty-print baked"      testTraceMetaBaked
    , test "<fn>$trace symbol emitted"         testTraceSymbolEmitted
    , test "traceMeta nodes populated"         testTraceMetaNodes
    , test "AND/OR/NOT marked special"         testTraceSpecialMarkers
    , test "fnValue node + enter_fn/exit_fn"   testTraceFnValueAndContext
    , test "NOT-range disambiguation"          testTraceNotRangeDisambiguation
    , test "returnType enriched from EntityInfo" testReturnTypeEnrichedFromEntityInfo
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
-- typecheck + lowering pipeline.
lowerSource :: T.Text -> Either [T.Text] T.Text
lowerSource src =
  case checkWithImports emptyVFS src of
    Left errs -> Left errs
    Right r -> Right (renderMLIR (lowerProgramWithInfo r.tcdInfoMap r.tcdModule []))

-- | Lower a source and render its schema JSON *with* per-function
-- lowering diagnostics applied (the @supported@ / @unsupportedReason@
-- flags). Mirrors what 'L4.MLIR.Pipeline' does.
schemaWithDiagnostics :: T.Text -> Either [T.Text] T.Text
schemaWithDiagnostics src =
  case checkWithImports emptyVFS src of
    Left errs -> Left errs
    Right r ->
      let (_mlir, diags) = lowerProgramWithDiagnostics r.tcdInfoMap r.tcdModule []
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

-- | REFUSE has no WASM image: the compiled module has no way to stop with a
-- reason, and lowering it to a value would answer where the program declined.
-- So an export that contains one in its body is marked @supported: false@,
-- and the WASM backend does not run it ('testRunDeclinesUnsupported').
testRefuseUnsupported :: IO Bool
testRefuseUnsupported = do
  let src = T.unlines
        [ "@export Direct refusal"
        , "GIVEN `age` IS A NUMBER"
        , "GIVETH A NUMBER"
        , "`direct` `age` MEANS IF `age` >= 18 THEN 1 ELSE REFUSE \"not modelled\""
        ]
  case schemaWithDiagnostics src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right json -> do
      let ok = T.isInfixOf "\"supported\":false" json
            && T.isInfixOf "REFUSE" json
            && not (T.isInfixOf "\"supported\":true" json)
      if ok then pure () else putStrLn $ "\n    json: " <> T.unpack (T.take 500 json)
      pure ok

-- | A REFUSE anywhere in a DEONTIC export's body marks the export
-- @supported: false@, wherever in the obligation it sits. The lowering does not
-- enter a regulative body, and the runtime walks the schema's
-- @deonticContract@, which holds no refusal: a HENCE or LEST it cannot read
-- is left out and reads as FULFILLED or BREACH, PROVIDED is not carried, and
-- WITHIN is carried as printed text and read as a number. Each would answer
-- where the program refuses.
--
-- The clauses follow @PARTY `alice`@ in a rule that takes a BOOLEAN @late@.
-- With @wantSupported@ the case is the control: the same shape with no
-- REFUSE stays supported.
testDeonticRefuse :: Bool -> [T.Text] -> IO Bool
testDeonticRefuse wantSupported clauses = do
  let src = T.unlines $
        [ "DECLARE Party IS ONE OF `alice`"
        , "DECLARE Action IS ONE OF `pay`"
        , ""
        , "@export Demo obligation"
        , "GIVEN `late` IS A BOOLEAN"
        , "GIVETH A DEONTIC OF Party, Action"
        , "`demo` `late` MEANS"
        , "    PARTY `alice`"
        ]
        <> map ("    " <>) clauses
  case schemaWithDiagnostics src of
    Left errs -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    Right json -> do
      let refused = T.isInfixOf "\"supported\":false" json
            && T.isInfixOf "\"unsupportedReason\":\"REFUSE is not supported by the WASM backend\"" json
            && not (T.isInfixOf "\"supported\":true" json)
          supported = T.isInfixOf "\"supported\":true" json
            && not (T.isInfixOf "\"supported\":false" json)
          ok = if wantSupported then supported else refused
      if ok then pure () else putStrLn $ "\n    json: " <> T.unpack (T.take 800 json)
      pure ok

-- | @jl4-mlir run@ does not run an export the schema marks
-- @supported: false@. It names the schema's reason on stderr, prints no
-- answer, and exits 1, before it reads the request or the @.wasm@; so the
-- schema alone is the fixture. The control is a supported export in the same
-- schema: the CLI goes on to read its request, and stops at the malformed one.
--
-- The binary is @JL4_MLIR_BIN@ if set, else the @jl4-mlir@ that @cabal test@
-- puts on PATH (@build-tool-depends@). Not finding one fails the test.
testRunDeclinesUnsupported :: IO Bool
testRunDeclinesUnsupported = do
  let src = T.unlines
        [ "@export Direct refusal"
        , "GIVEN `age` IS A NUMBER"
        , "GIVETH A NUMBER"
        , "`direct` `age` MEANS IF `age` >= 18 THEN 1 ELSE REFUSE \"not modelled\""
        , ""
        , "@export Adult check"
        , "GIVEN `age` IS A NUMBER"
        , "GIVETH A BOOLEAN"
        , "DECIDE `adult` IF `age` >= 18"
        ]
  fromEnv <- lookupEnv "JL4_MLIR_BIN"
  onPath <- findExecutable "jl4-mlir"
  case (maybe onPath Just fromEnv, schemaWithDiagnostics src) of
    (Nothing, _) -> do
      putStrLn "\n    no jl4-mlir binary: set JL4_MLIR_BIN or run under cabal test"
      pure False
    (_, Left errs) -> do
      putStrLn $ "\n    typecheck failed: " <> show errs
      pure False
    (Just bin, Right json) -> withSystemTempDirectory "jl4-mlir-run" \dir -> do
      writeFile (dir </> "test.schema.json") (T.unpack json)
      let run fn input =
            readCreateProcessWithExitCode
              (proc bin ["run", dir </> "test.wasm", "-f", fn]) input
          declineText = "direct is not evaluated by the WASM backend: " <> T.unpack refuseReason
      (code, out, err) <- run "direct" "{\"arguments\": {\"age\": 3}}"
      (ctlCode, _, ctlErr) <- run "adult" "not json"
      let checks :: [(String, Bool)]
          checks =
            [ ("exits 1", code == ExitFailure 1)
            , ("prints no answer", null out)
            , ("names the schema's reason", declineText `isPrefixOfS` err)
            , ("sends the caller to jl4-service", "Evaluate it with jl4-service." `isInfixOfS` err)
            , ("stops at the decline", lines err == [declineText <> ". Evaluate it with jl4-service."])
            , ("control: a supported export is not declined", not ("not evaluated by the WASM backend" `isInfixOfS` ctlErr))
            , ("control: a supported export reaches its request", "Invalid JSON request" `isInfixOfS` ctlErr && ctlCode /= ExitSuccess)
            ]
          failures = [name | (name, ok) <- checks, not ok]
      if null failures
        then pure True
        else do
          putStrLn $ "\n    failing checks: " <> show failures
          putStrLn $ "    exit: " <> show code <> "; stdout: " <> show out <> "; stderr: " <> show err
          putStrLn $ "    control stderr: " <> show ctlErr
          pure False
  where
    isPrefixOfS a b = T.pack a `T.isPrefixOf` T.pack b
    isInfixOfS a b = T.pack a `T.isInfixOf` T.pack b

-- | The reason the schema gives an export from which evaluation may reach a
-- REFUSE.
refuseReason :: T.Text
refuseReason = "REFUSE is not supported by the WASM backend"

-- | The mark an export that may reach a REFUSE gets, and no other.
refuseMark :: Maybe T.Text
refuseMark = Just refuseReason

-- | The schema's mark on a module's one export is the one expected:
-- 'Nothing' for @supported: true@, @Just reason@ for @supported: false@ with
-- exactly that reason. The module may import the given modules (name and
-- source), and the lowering and the schema both receive every module it
-- imports, directly or not, as 'L4.MLIR.Pipeline' passes them.
--
-- A REFUSE reached through a name is the house style, one named definition
-- per refusal, so these cases follow names: through calls, a WHERE, a LET,
-- an AKA, recursion, a regulative rule's HENCE, and imports.
testExportMark :: Maybe T.Text -> [(T.Text, T.Text)] -> [T.Text] -> IO Bool
testExportMark want imports srcLines =
  case checkWithImportsAndUri (vfsFromList imports) "main" (T.unlines srcLines) of
    Left errs -> do
      putStrLn $ "\n    the module did not check: " <> show errs
      pure False
    Right r
      | not r.tcdSuccess -> do
          putStrLn $ "\n    the module has type errors: " <> show (length r.tcdErrors)
          pure False
      | otherwise -> do
          let deps = map (\ri -> ri.riTypeChecked.program) r.tcdResolvedImports
              (_mlir, diags) = lowerProgramWithDiagnostics r.tcdInfoMap r.tcdModule deps
              bundle = applyDiagnostics diags
                (bundleExports "test.wasm" "test" r.tcdInfoMap (substitutedEntityInfo r) r.tcdModule deps)
              json = TE.decodeUtf8 (LBS.toStrict (encodeBundle bundle))
          case theExportMark json of
            Left err -> do
              putStrLn $ "\n    " <> err
              pure False
            Right (ok, reason) -> do
              let got = if ok then Nothing else Just (maybe "" id reason)
                  good = got == want && (not ok || reason == Nothing)
              if good then pure () else
                putStrLn $ "\n    wanted " <> show want <> ", got supported=" <> show ok <> " reason=" <> show reason
              pure good

-- | The @supported@ flag and the @unsupportedReason@ of a schema's one export.
theExportMark :: T.Text -> Either String (Bool, Maybe T.Text)
theExportMark json = case Aeson.decodeStrict (TE.encodeUtf8 json) of
  Just (Aeson.Object top)
    | Just (Aeson.Object fns) <- Aeson.KeyMap.lookup "functions" top
    , [Aeson.Object f] <- Aeson.KeyMap.elems fns
    , Just (Aeson.Bool ok) <- Aeson.KeyMap.lookup "supported" f ->
        Right (ok, case Aeson.KeyMap.lookup "unsupportedReason" f of
                     Just (Aeson.String reason) -> Just reason
                     _ -> Nothing)
  _ -> Left ("expected a schema with one export, got: " <> T.unpack (T.take 400 json))

-- | A module with the given definitions, then an export that answers 100
-- from the year 2000 and otherwise the given expression.
feeInYear :: [T.Text] -> T.Text -> [T.Text]
feeInYear defs before2000 =
  defs <>
  [ ""
  , "@export The fee in a year"
  , "GIVEN y IS A NUMBER"
  , "GIVETH A NUMBER"
  , "`the fee in year` y MEANS"
  , "    IF y >= 2000"
  , "    THEN 100"
  , "    ELSE " <> before2000
  ]

-- | A named refusal, one definition per reason.
oldFeeRefuses :: [T.Text]
oldFeeRefuses =
  [ "GIVETH A NUMBER"
  , "`the old fee` MEANS REFUSE \"fees before 2000 are not encoded\""
  ]

-- | A clause group of two clauses, for year 0 and for any other year. The
-- parser compiles a group into one definition whose later clauses sit in a
-- LET definition inside its body, so a REFUSE in the last clause is one
-- written in a LET.
oldFeeClauses :: T.Text -> T.Text -> [T.Text]
oldFeeClauses yearZero otherYears =
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A NUMBER"
  , "DECIDE `the old fee` 0 IS " <> yearZero
  , "DECIDE `the old fee` n IS " <> otherYears
  ]

-- | The control: the same name, with a value.
oldFeeIsFifty :: [T.Text]
oldFeeIsFifty =
  [ "GIVETH A NUMBER"
  , "`the old fee` MEANS 50"
  ]

-- | A second called definition, with a value. The two sibling cases put it
-- before and after the refusal in the source, because the walk reads the
-- names a body holds in the order of their Uniques, which need not be the
-- order they are written in, and a walk that read only the first of them
-- would pass one of the two orders.
firstFeeIsFifty :: [T.Text]
firstFeeIsFifty =
  [ "GIVETH A NUMBER"
  , "`the first fee` MEANS 50"
  ]

-- | An export that reads a computed field, whose MEANS refuses for a minor.
adultFieldRefuses :: [T.Text]
adultFieldRefuses =
  [ "DECLARE Person HAS"
  , "    `age`   IS A NUMBER"
  , "    `adult` IS A BOOLEAN"
  , "        MEANS IF `age` >= 18 THEN TRUE ELSE REFUSE \"minors are not modelled\""
  , ""
  , "@export Whether a person is an adult"
  , "GIVEN p IS A Person"
  , "GIVETH A BOOLEAN"
  , "`is adult` p MEANS p's `adult`"
  ]

-- | @base@ holds the refusal, @older@ and @newer@ each import it, and the
-- main module imports both and calls @older@.
importDiamond :: [(T.Text, T.Text)]
importDiamond =
  [ ("base", T.unlines oldFeeRefuses)
  , ("older", T.unlines
      [ "IMPORT base"
      , ""
      , "GIVEN y IS A NUMBER"
      , "GIVETH A NUMBER"
      , "`the old fee in year` y MEANS `the old fee`"
      ])
  , ("newer", T.unlines
      [ "IMPORT base"
      , ""
      , "GIVETH A NUMBER"
      , "`the new fee` MEANS 100"
      ])
  ]

-- | Two definitions that call each other; the second refuses below zero.
parityRefusesBelowZero :: [T.Text]
parityRefusesBelowZero =
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`is even` n MEANS IF n EQUALS 0 THEN TRUE ELSE `is odd` (n - 1)"
  , ""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`is odd` n MEANS"
  , "    IF n < 0 THEN REFUSE \"negative numbers are not modelled\""
  , "    ELSE IF n EQUALS 0 THEN FALSE ELSE `is even` (n - 1)"
  , ""
  , "@export Parity"
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`parity` n MEANS `is even` n"
  ]

-- | The control for recursion: a definition that calls itself, with no
-- REFUSE anywhere, so the walk has to end without finding one.
factorialExport :: [T.Text]
factorialExport =
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A NUMBER"
  , "`factorial` n MEANS IF n <= 0 THEN 1 ELSE n * `factorial` (n - 1)"
  , ""
  , "@export The factorial"
  , "GIVEN n IS A NUMBER"
  , "GIVETH A NUMBER"
  , "`the factorial of` n MEANS `factorial` n"
  ]

-- | A deontic export whose HENCE names a definition with the given body.
deonticHenceNamed :: [T.Text] -> [T.Text]
deonticHenceNamed body =
  [ "DECLARE Party IS ONE OF `alice`"
  , "DECLARE Action IS ONE OF `pay`"
  , ""
  , "GIVETH A DEONTIC OF Party, Action"
  , "`what follows payment` MEANS"
  ]
  <> map ("    " <>) body <>
  [ ""
  , "@export Demo obligation"
  , "GIVETH A DEONTIC OF Party, Action"
  , "`demo` MEANS"
  , "    PARTY `alice`"
  , "    MUST `pay`"
  , "    WITHIN 10"
  , "    HENCE `what follows payment`"
  ]

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

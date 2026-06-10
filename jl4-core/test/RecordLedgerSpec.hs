{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | M1 surface-WRITE tests: @RECORD@ / @COMMIT@ / @ATTEST@ end-to-end.
--
-- These prove the whole write path — parse, typecheck, eval, ledger append —
-- for the new 'Record' AST node:
--
--   (a) @RECORD \`x\` IS 273.15@ parses to a 'Record' node (isOfficial = False);
--   (b) it type-checks (the cell is a STRING path; the whole expression has the
--       type of the written value, so it can chain in a HENCE continuation);
--   (c) it evaluates to 273.15 (the written value is returned);
--   (d) the ledger afterwards contains @Assign ["x"] 273.15 _@, observed via the
--       'currentLedger' test seam after a forward-eval of the resolved node.
--
-- A @COMMIT@ variant asserts that the official/own distinction is recorded
-- (faithfully stored on the node as isOfficial = True and surfaced in the
-- provenance source as "COMMIT", ready for the M4 own/official ledger split).
module RecordLedgerSpec (spec) where

import qualified Data.Map.Strict as Map

import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Syntax
  ( Directive (..)
  , Expr (..)
  , Module (..)
  , Resolved
  , Section (..)
  , TopDecl (..)
  )
import L4.Evaluate.Ledger
  ( LedgerEvent (..)
  , Provenance (..)
  , snapshot
  )
import L4.Evaluate.ValueLazy (NF (..), Value (..), WHNF)
import L4.EvaluateLazy
  ( EvalDirectiveResult (..)
  , EvalDirectiveValue (..)
  , currentLedger
  , evalExprForLedger
  , execEvalModuleWithEnv
  , resolveEvalConfig
  , runEvalAction
  )
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.TracePolicy (apiDefaultPolicy)

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

-- A fixed time keeps evaluation deterministic.
fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

-- | Collect every directive body expression from a typechecked module,
-- recursing into nested sections.
directiveExprs :: Module Resolved -> [Expr Resolved]
directiveExprs (MkModule _ _ sec) = goSection sec
  where
    goSection (MkSection _ _ _ decls) = concatMap goDecl decls
    goDecl (Directive _ (LazyEval _ e))      = [e]
    goDecl (Directive _ (LazyEvalTrace _ e)) = [e]
    goDecl (Section _ s)                     = goSection s
    goDecl _                                 = []

-- | The single 'Record' node we expect from a one-directive module.
theRecord :: Module Resolved -> Maybe (Expr Resolved, Expr Resolved, Bool)
theRecord m = case directiveExprs m of
  [Record _ cell val isOfficial] -> Just (cell, val, isOfficial)
  _                              -> Nothing

-- 'WHNF'/'NF' have no 'Eq' (they carry IORef thunks), so we compare via Show.
showVal :: WHNF -> String
showVal = show

spec :: Spec
spec = describe "M1 surface WRITE (RECORD / COMMIT / ATTEST)" $ do
  cfg <- runIO (resolveEvalConfig (Just fixedNow) apiDefaultPolicy)

  let src isOfficialKw =
        (if isOfficialKw then "#EVAL COMMIT `x` IS 273.15\n"
                         else "#EVAL RECORD `x` IS 273.15\n")
      vfs = vfsFromList []

  describe "RECORD (own ledger)" $ do
    it "(b) type-checks, and (a) parses to a Record node with isOfficial = False" $
      case checkWithImports vfs (src False) of
        Left errs -> expectationFailure ("expected a clean typecheck, got: " <> show errs)
        Right r ->
          case theRecord r.tcdModule of
            Nothing -> expectationFailure "expected exactly one Record directive node"
            Just (_cell, _val, isOfficial) -> isOfficial `shouldBe` False

    it "(c) evaluates to 273.15 (the written value is returned)" $
      case checkWithImports vfs (src False) of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r -> do
          (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
          case results of
            [res] -> case res.result of
              Reduction (Right (MkNF (ValNumber n))) -> n `shouldBe` (5463 / 20)  -- 273.15
              other -> expectationFailure ("expected 273.15, got: " <> show other)
            _ -> expectationFailure ("expected exactly one directive result, got " <> show (length results))

    it "(d) appends Assign [\"x\"] 273.15 to the ledger (source = RECORD), via the seam" $
      case checkWithImports vfs (src False) of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r ->
          case directiveExprs r.tcdModule of
            [recordExpr] -> do
              res <- runEvalAction cfg (evalExprForLedger recordExpr >> currentLedger)
              case res of
                Left e -> expectationFailure ("unexpected Eval exception: " <> show e)
                Right ledger -> do
                  let snap = snapshot ledger
                  Map.size snap `shouldBe` 1
                  fmap showVal (Map.lookup ["x"] snap) `shouldBe` Just (showVal (ValNumber (5463 / 20)))
                  map provSource (provenances ledger) `shouldBe` ["RECORD"]
            other -> expectationFailure ("expected one Record directive, got " <> show (length other))

  describe "COMMIT (official record) records the own/official distinction" $ do
    it "parses to a Record node with isOfficial = True" $
      case checkWithImports vfs (src True) of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r ->
          case theRecord r.tcdModule of
            Nothing -> expectationFailure "expected one Record node"
            Just (_cell, _val, isOfficial) -> isOfficial `shouldBe` True

    it "records source = COMMIT in the ledger provenance, via the seam" $
      case checkWithImports vfs (src True) of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r ->
          case directiveExprs r.tcdModule of
            [recordExpr] -> do
              res <- runEvalAction cfg (evalExprForLedger recordExpr >> currentLedger)
              case res of
                Left e -> expectationFailure ("unexpected Eval exception: " <> show e)
                Right ledger ->
                  map provSource (provenances ledger) `shouldBe` ["COMMIT"]
            other -> expectationFailure ("expected one Record directive, got " <> show (length other))
  where
    provenances ledger = [ p | Assign _ _ p <- foldr (:) [] ledger ]
    provSource p = p.source

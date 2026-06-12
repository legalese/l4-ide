{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | M1 surface-WRITE and M1.5 surface-READ tests for the event-sourced ledger.
--
-- The WRITE half (@RECORD@ / @COMMIT@ / @ATTEST@ → the 'Record' AST node)
-- proves the whole write path — parse, typecheck, eval, ledger append:
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
--
-- The READ half (@RECALL@ → the 'ReadCell' AST node) proves the read path
-- end-to-end (M1.5):
--
--   (1) after @RECORD \`x\` IS 273.15@, @RECALL \`x\`@ evaluates to @JUST 273.15@;
--   (2) @RECALL \`missing\`@ evaluates to @NOTHING@;
--   (3) ISOLATION: a @RECALL@ evaluated in a FRESH directive/ledger, after a
--       write in a SEPARATE directive, returns @NOTHING@ — proving that
--       'withFreshLedger' still isolates per-directive (the M0 invariant).
--
-- Tests (1) and (2) drive the write and the read through the 'evalExprForLedger'
-- seam in ONE 'runEvalAction' (sharing one 'EvalState'/ledger, so no
-- 'withFreshLedger' wipes between them). Test (3) drives both directives through
-- 'execEvalModuleWithEnv', which wraps every directive in 'withFreshLedger'.
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
  , getUnique
  )
import L4.Evaluate.Ledger
  ( LedgerEvent (..)
  , LedgerStore (..)
  , Provenance (..)
  , snapshot
  )
import L4.Evaluate.ValueLazy (NF (..), Value (..), WHNF)
import L4.EvaluateLazy
  ( EvalDirectiveResult (..)
  , EvalDirectiveValue (..)
  , currentLedger
  , currentStore
  , evalExprForLedger
  , execEvalModuleWithEnv
  , resolveEvalConfig
  , runEvalAction
  )
import L4.EvaluateLazy.Machine (emptyEnvironment)
import qualified L4.TypeCheck as TypeCheck
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
  [Record _ cell val isOfficial _mHence] -> Just (cell, val, isOfficial)
  _                                       -> Nothing

-- 'WHNF'/'NF' have no 'Eq' (they carry IORef thunks), so we compare via Show.
showVal :: WHNF -> String
showVal = show

-- | Is this WHNF a @JUST _@ (the prelude MAYBE constructor)?
isJustWHNF :: WHNF -> Bool
isJustWHNF (ValConstructor r [_]) = getUnique r == TypeCheck.justUnique
isJustWHNF _                      = False

-- | Is this WHNF a @NOTHING@ (the prelude MAYBE constructor)?
isNothingWHNF :: WHNF -> Bool
isNothingWHNF (ValConstructor r []) = getUnique r == TypeCheck.nothingUnique
isNothingWHNF _                     = False

-- | Is this fully-forced NF a @NOTHING@?
isNothingNF :: NF -> Bool
isNothingNF (MkNF (ValConstructor r [])) = getUnique r == TypeCheck.nothingUnique
isNothingNF _                            = False

spec :: Spec
spec = describe "STATE-AS-LEDGER: RECORD/COMMIT/ATTEST (M1 write) + RECALL (M1.5 read)" $ do
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

    it "records source = COMMIT in the OFFICIAL ledger provenance, via the seam (M4 routing)" $
      case checkWithImports vfs (src True) of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r ->
          case directiveExprs r.tcdModule of
            [recordExpr] -> do
              res <- runEvalAction cfg (evalExprForLedger recordExpr >> currentStore)
              case res of
                Left e -> expectationFailure ("unexpected Eval exception: " <> show e)
                Right store -> do
                  -- M4: a COMMIT routes to the official record, not an own ledger.
                  map provSource (provenances store.officialLedger) `shouldBe` ["COMMIT"]
                  -- and nothing landed in any own ledger.
                  null store.ownLedgers `shouldBe` True
            other -> expectationFailure ("expected one Record directive, got " <> show (length other))

  describe "RECALL (M1.5 read): MAYBE-typed cell read" $ do
    -- One module, two directives: the WRITE then the READ. We collect both
    -- resolved exprs and choose how to sequence them depending on the test.
    let writeThenReadSrc = "#EVAL RECORD `x` IS 273.15\n#EVAL RECALL `x`\n"
        readMissingSrc   = "#EVAL RECALL `missing`\n"

    it "parses RECALL to a ReadCell node and type-checks (cell : STRING ⇒ MAYBE a)" $
      case checkWithImports vfs readMissingSrc of
        Left errs -> expectationFailure ("expected a clean typecheck, got: " <> show errs)
        Right r ->
          case directiveExprs r.tcdModule of
            [ReadCell _ _cell] -> pure ()
            other -> expectationFailure ("expected exactly one ReadCell directive, got: " <> show (length other))

    it "(1) after RECORD `x` IS 273.15, RECALL `x` evaluates to JUST 273.15 (shared ledger, via the seam)" $
      case checkWithImports vfs writeThenReadSrc of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r ->
          case directiveExprs r.tcdModule of
            [writeExpr, readExpr] -> do
              -- Both run in ONE runEvalAction => one EvalState => one ledger.
              -- The read MUST see the prior write (no withFreshLedger between).
              res <- runEvalAction cfg $ do
                _ <- evalExprForLedger writeExpr        -- RECORD `x` IS 273.15
                readWHNF <- evalExprForLedger readExpr  -- RECALL `x`
                ledger <- currentLedger
                pure (readWHNF, ledger)
              case res of
                Left e -> expectationFailure ("unexpected Eval exception: " <> show e)
                Right (readWHNF, ledger) -> do
                  -- the read is JUST _ ...
                  isJustWHNF readWHNF `shouldBe` True
                  -- ... and the value it wraps is the 273.15 that was written
                  -- (the JUST payload is the very WHNF stored in the ledger).
                  let snap = snapshot ledger
                  fmap showVal (Map.lookup ["x"] snap)
                    `shouldBe` Just (showVal (ValNumber (5463 / 20)))
            other -> expectationFailure ("expected a write + a read directive, got " <> show (length other))

    it "(2) RECALL `missing` evaluates to NOTHING (never written, via the seam)" $
      case checkWithImports vfs readMissingSrc of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r ->
          case directiveExprs r.tcdModule of
            [readExpr] -> do
              res <- runEvalAction cfg (evalExprForLedger readExpr)
              case res of
                Left e -> expectationFailure ("unexpected Eval exception: " <> show e)
                Right readWHNF -> isNothingWHNF readWHNF `shouldBe` True
            other -> expectationFailure ("expected one RECALL directive, got " <> show (length other))

    it "(3) ISOLATION: RECALL in a FRESH directive does NOT see a RECORD from an earlier directive (withFreshLedger)" $
      -- Two #EVAL directives in one module. execEvalModuleWithEnv runs each
      -- through nfDirective => withFreshLedger, so the read directive starts
      -- from an EMPTY ledger and must return NOTHING despite the prior write.
      case checkWithImports vfs writeThenReadSrc of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r -> do
          (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
          case results of
            [writeRes, readRes] -> do
              -- the write directive still returns its written value ...
              case writeRes.result of
                Reduction (Right (MkNF (ValNumber n))) -> n `shouldBe` (5463 / 20)
                other -> expectationFailure ("write directive: expected 273.15, got " <> show other)
              -- ... but the read directive, isolated, sees NOTHING.
              case readRes.result of
                Reduction (Right nfVal) ->
                  isNothingNF nfVal `shouldBe` True
                other -> expectationFailure ("read directive: expected NOTHING, got " <> show other)
            _ -> expectationFailure ("expected exactly two directive results, got " <> show (length results))
  where
    provenances ledger = [ p | Assign _ _ p <- foldr (:) [] ledger ]
    provSource p = p.source

{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | STATE-AS-LEDGER x T6: ledger effects inside a thunk force must poison the
-- 'WHNFWhen' (context-fingerprinted) cache.
--
-- T6 caches a context-dependent force as @WHNFWhen fp v@ and RE-FORCES the
-- thunk whenever the current temporal context no longer matches @fp@. That
-- deterministic-replay premise breaks when the force also touched the ledger:
--
--   * a re-forced RECORD\/COMMIT\/ATTEST APPENDS its event again — a
--     double-write observable via @RECALL ALL@ and the per-directive ledger;
--   * a re-forced (or fingerprint-served) RECALL can observe a DIFFERENT
--     ledger than the first force did, so two uses of ONE shared binding
--     disagree within one directive (sharing violation).
--
-- The fix: any ledger op during a force sets the 'crLedgerOps' poison bit in
-- the span's 'CtxReads'; the @UpdateThunk@ arm of 'backward' then installs a
-- plain 'WHNF' (snapshot at first force, write fires exactly once) instead of
-- a 'WHNFWhen'. This is precisely the semantics a ledger-touching thunk
-- WITHOUT temporal reads already has (see the control test below), and the
-- within-directive analogue of the cross-directive CAF isolation that
-- 'forEachDirectiveFreshHeap' provides.
--
-- These tests are deliberately INTRA-directive: the cross-directive
-- @temporal-thunk-leak-*@ goldens are masked by the fresh-heap-per-directive
-- rebuild, which re-thunks top-level CAFs between directives.
module LedgerThunkCacheSpec (spec) where

import qualified Data.Map.Strict as Map
import qualified Data.Text as Text

import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Evaluate.Ledger
  ( Ledger
  , LedgerEvent (..)
  , LedgerStore (..)
  , anonymousParty
  )
import L4.EvaluateLazy
  ( EvalDirectiveResult (..)
  , EvalDirectiveValue (..)
  , execEvalModuleWithEnv
  , resolveEvalConfig
  )
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.Print (prettyLayout)
import L4.TracePolicy (apiDefaultPolicy)

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

-- A fixed time keeps evaluation deterministic.
fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

-- | Typecheck a one-module source and run all its directives.
runDirectives :: Text.Text -> IO [EvalDirectiveResult]
runDirectives src = do
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  case checkWithImports (vfsFromList []) src of
    Left errs -> do
      expectationFailure ("typecheck failed: " <> show errs)
      pure []
    Right r -> do
      (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
      pure results

-- | The cell 'Path's recorded in a single ledger, oldest-first.
cellsOf :: Ledger -> [[Text.Text]]
cellsOf led = [ p | Assign p _ _ <- foldr (:) [] led ]

-- | Render the directive's reduction for structural comparison.
renderedResult :: EvalDirectiveResult -> Text.Text
renderedResult res = case res.result of
  Reduction (Right nf) -> prettyLayout nf
  other                -> Text.pack (show other)

-- | A shared top-level binding whose force BOTH writes the ledger (RECORD)
-- and reads the temporal context (TODAY). Used twice in ONE #EVAL, the
-- second time under a different temporal context than the first force.
doubleWriteSrc :: Text.Text
doubleWriteSrc = Text.unlines
  [ "TIMEZONE IS \"Etc/UTC\""
  , ""
  , "`stamped write` MEANS (RECORD `x` IS 100) PLUS DATE_SERIAL TODAY"
  , ""
  , "#EVAL (`EVAL AS OF SYSTEM TIME` (DATE_SERIAL (DATE_FROM_DMY 1 1 2020)) `stamped write`) MINUS `stamped write`"
  ]

-- | A shared top-level binding whose force RECALLs a cell and reads the
-- temporal context, used before AND after a RECORD to the same cell in ONE
-- #EVAL (list elements normalize left-to-right).
recallCoherenceSrc :: Text.Text
recallCoherenceSrc = Text.unlines
  [ "TIMEZONE IS \"Etc/UTC\""
  , ""
  , "`recall or today` MEANS"
  , "  CONSIDER RECALL `x`"
  , "  WHEN JUST v THEN v"
  , "  WHEN NOTHING THEN DATE_SERIAL TODAY"
  , ""
  , "#EVAL LIST (`EVAL AS OF SYSTEM TIME` (DATE_SERIAL (DATE_FROM_DMY 1 1 2020)) `recall or today`), (RECORD `x` IS 7), `recall or today`"
  ]

-- | CONTROL: the same shape as 'recallCoherenceSrc' but with NO temporal read
-- in the thunk. Pins the baseline semantics the poison bit must match: a
-- ledger-touching force snapshots at first force (plain WHNF). This also
-- guards against "fixing" the double-write by never caching ledger-touching
-- forces at all (which would re-run the RECALL here and yield 7).
recallControlSrc :: Text.Text
recallControlSrc = Text.unlines
  [ "`recall or zero` MEANS"
  , "  CONSIDER RECALL `x`"
  , "  WHEN JUST v THEN v"
  , "  WHEN NOTHING THEN 0"
  , ""
  , "#EVAL LIST (`EVAL AS OF SYSTEM TIME` (DATE_SERIAL (DATE_FROM_DMY 1 1 2020)) `recall or zero`), (RECORD `x` IS 7), `recall or zero`"
  ]

spec :: Spec
spec = describe "STATE-AS-LEDGER x T6: ledger ops poison the WHNFWhen cache (intra-directive)" $ do

  describe "a RECORD inside a temporally-fingerprinted thunk fires exactly once" $ do
    it "one #EVAL forcing the shared thunk under two temporal contexts appends ONE Assign, not two" $ do
      [res] <- runDirectives doubleWriteSrc
      let store = res.ledger
      -- THE guard: exactly one write. Pre-fix the ambient use re-forced the
      -- WHNFWhen-cached thunk (fingerprint mismatch) and appended a second
      -- `x` Assign.
      cellsOf (Map.findWithDefault mempty anonymousParty store.ownLedgers)
        `shouldBe` [["x"]]
      -- Sharing: both uses of the shared binding are the SAME first-force
      -- value, so the difference is 0. (Pre-fix: override-value MINUS
      -- recomputed-ambient-value, a nonzero clock-dependent number.)
      renderedResult res `shouldBe` "0"

  describe "a RECALL inside a temporally-fingerprinted thunk is coherent within one directive" $ do
    it "both uses of the shared binding observe the FIRST force's ledger snapshot" $ do
      [res] <- runDirectives recallCoherenceSrc
      -- 737789 = DATE_SERIAL (2020-01-01), the override under which the
      -- binding was first forced (cell `x` not yet written). Pre-fix the
      -- third element re-forced under the ambient context and read the
      -- meanwhile-written 7 — one shared binding, two different values.
      renderedResult res `shouldBe` "LIST 737789, 7, 737789"
      -- exactly the one explicit RECORD, no extras
      cellsOf (Map.findWithDefault mempty anonymousParty res.ledger.ownLedgers)
        `shouldBe` [["x"]]

    it "CONTROL (no temporal read): a ledger-touching thunk already snapshots at first force" $ do
      [res] <- runDirectives recallControlSrc
      renderedResult res `shouldBe` "LIST 0, 7, 0"
      cellsOf (Map.findWithDefault mempty anonymousParty res.ledger.ownLedgers)
        `shouldBe` [["x"]]

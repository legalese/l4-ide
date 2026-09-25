{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Regression: a #TRACE event list is a SET of timestamped facts and must be
-- processed in AT (time) order, not in authored list order.
--
-- THE BUG (pre stable-sort-by-AT fix). #TRACE events were consumed in LIST
-- order, never sorted by AT. In a RAND/ROR, both strands step the SAME
-- list-ordered stream, and a strand's deadline check compares the
-- NEXT-IN-LIST event — which may belong to a SIBLING strand — against THIS
-- strand's deadline. So when a later-timestamped sibling event is LISTED
-- BEFORE a strand's own earlier event, the strand's MUST wrongly takes its
-- LEST branch, its HENCE continuation (here a RECORD) is never reached, and
-- the effect is silently DROPPED — the ledger comes back EMPTY.
--
-- THE FIX (Machine.contractToEvalDirective). STABLE-sort the authored WITH
-- event list by AT (nondecreasing) at the single point where the stream is
-- built and handed to residuation, so it uniformly governs all RAND/ROR
-- strands. After the fix the events are processed note\@10 then x\@60, the
-- recorder's MUST is discharged in time, its HENCE RECORD fires, and the
-- ledger contains `flag`.
--
-- This test is LOAD-BEARING: on pre-fix code (no sort) the ledger is empty and
-- the assertion below fails; the sort is what makes it pass.
module TraceOrderingSpec (spec) where

import qualified Data.Map.Strict as Map
import qualified Data.Text as Text

import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Evaluate.Ledger
  ( LedgerEvent (..)
  , LedgerStore (..)
  )
import L4.EvaluateLazy
  ( EvalDirectiveResult (..)
  , execEvalModuleWithEnv
  , resolveEvalConfig
  )
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.TracePolicy (apiDefaultPolicy)

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

-- A fixed time keeps evaluation deterministic.
fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2025 1 1) (secondsToDiffTime 0)

-- | Typecheck a one-module source and run all its directives, returning the
-- per-directive results (each carrying its captured 'LedgerStore').
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

-- | The cell 'Path's recorded across all of a store's ledgers (own + official).
allCells :: LedgerStore -> [[Text.Text]]
allCells store =
  let fromLedger led = [ p | Assign p _ _ <- foldr (:) [] led ]
  in  concatMap fromLedger (Map.elems store.ownLedgers)
        <> fromLedger store.officialLedger

-- | The DECISIVE repro. A RAND of two MUSTs sharing one event stream, with the
-- WITH list authored NON-MONOTONICALLY: the sibling strand's later event
-- (x AT 60) is listed BEFORE the recorder strand's own earlier event
-- (note AT 10). The recorder MUST note WITHIN 30 HENCE RECORD `flag`.
-- In AT order (note\@10, x\@60) the recorder is discharged in time and the
-- RECORD fires; in the buggy LIST order the recorder sees x\@60 first, 60 > 30,
-- takes its LEST branch, and the RECORD is dropped.
nonMonotonicRandSrc :: Text.Text
nonMonotonicRandSrc = Text.unlines
  [ "IMPORT prelude"
  , "DECLARE Actor IS ONE OF P, Q"
  , "DECLARE Action IS ONE OF note, x"
  , "GIVETH A DEONTIC Actor Action"
  , "recorder MEANS PARTY P MUST note WITHIN 30 HENCE RECORD `flag` IS TRUE HENCE FULFILLED LEST FULFILLED"
  , "GIVETH A DEONTIC Actor Action"
  , "agreement MEANS ( PARTY Q MUST x WITHIN 100 HENCE FULFILLED ) RAND recorder"
  , "#TRACE agreement AT 0 WITH"
  , "    PARTY Q DOES x AT 60"
  , "    PARTY P DOES note AT 10"
  ]

spec :: Spec
spec = describe "TRACE ordering: a #TRACE event list is processed in AT order, not list order" $ do

  describe "a RAND over a NON-MONOTONIC trace still records the effect (stable-sort-by-AT)" $ do
    it "records `flag` even though the sibling's later event is listed before the recorder's earlier event" $ do
      [res] <- runDirectives nonMonotonicRandSrc
      -- LOAD-BEARING: without the AT sort the recorder takes its LEST branch on
      -- the sibling's stamp (60 > 30), its HENCE RECORD never fires, and this
      -- list is empty. With the sort the RECORD survives.
      allCells res.ledger `shouldBe` [["flag"]]

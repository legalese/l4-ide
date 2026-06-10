-- | M0 ledger-substrate tests.
--
-- These exercise the event-sourced ledger end-to-end THROUGH the 'Eval' monad
-- (via the 'runEvalAction' test seam), not just the pure data model: we append
-- 'Assign' events with 'tellEvent', read the log back with 'currentLedger', and
-- assert that 'snapshot' / 'readCell' project it correctly — including
-- last-write-wins and the empty-ledger base case.
module LedgerSubstrateSpec (spec) where

import qualified Data.Map.Strict as Map

import L4.Evaluate.Ledger
  ( Ledger
  , LedgerEvent (..)
  , Provenance (..)
  , readCell
  , snapshot
  )
import L4.Evaluate.ValueLazy (Value (..), WHNF)
import L4.EvaluateLazy
  ( Eval
  , currentLedger
  , resolveEvalConfig
  , runEvalAction
  , tellEvent
  )
import L4.TracePolicy (apiDefaultPolicy)

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

-- A fixed time keeps 'runEvalAction' deterministic.
fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

prov :: Provenance
prov = MkProvenance { party = "tester", source = "LedgerSubstrateSpec", position = Nothing }

-- 273.15 K = 0 degrees Celsius. 'ValNumber' needs no 'Reference', so it is a
-- valid 'WHNF' (= 'Value Reference') for any element type.
celsiusZero :: WHNF
celsiusZero = ValNumber 273.15

absoluteZero :: WHNF
absoluteZero = ValNumber 0

-- 'WHNF' has no 'Eq' instance (it contains 'IORef' thunks via 'Reference'), so
-- we compare values via their derived 'Show'. The literal numbers we store
-- contain no 'Reference', so their 'Show' is total and stable.
showVal :: WHNF -> String
showVal = show

spec :: Spec
spec = describe "M0 ledger substrate (event-sourced)" $ do
  cfg <- runIO (resolveEvalConfig (Just fixedNow) apiDefaultPolicy)

  -- Run an 'Eval' action through the monad, failing the test on an exception.
  let run :: Eval Ledger -> IO Ledger
      run action = do
        r <- runEvalAction cfg action
        case r of
          Left e  -> do
            expectationFailure ("unexpected Eval exception: " <> show e)
            error "unreachable"
          Right a -> pure a

  it "records an Assign and reads it back through the Eval monad" $ do
    ledger <- run (tellEvent (Assign ["x"] celsiusZero prov) >> currentLedger)
    let snap = snapshot ledger
    fmap showVal (Map.lookup ["x"] snap) `shouldBe` Just (showVal celsiusZero)
    fmap showVal (readCell ["x"] ledger) `shouldBe` Just (showVal celsiusZero)
    Map.size snap `shouldBe` 1

  it "last write wins for two Assigns to the same path" $ do
    ledger <- run $ do
      tellEvent (Assign ["temp"] celsiusZero prov)   -- first write
      tellEvent (Assign ["temp"] absoluteZero prov)  -- second write to SAME path
      currentLedger
    -- the projection must reflect the SECOND (newest) write
    fmap showVal (readCell ["temp"] ledger) `shouldBe` Just (showVal absoluteZero)
    Map.size (snapshot ledger) `shouldBe` 1

  it "keeps distinct paths distinct" $ do
    ledger <- run $ do
      tellEvent (Assign ["a"] celsiusZero prov)
      tellEvent (Assign ["b"] absoluteZero prov)
      currentLedger
    let snap = snapshot ledger
    Map.size snap `shouldBe` 2
    fmap showVal (readCell ["a"] ledger) `shouldBe` Just (showVal celsiusZero)
    fmap showVal (readCell ["b"] ledger) `shouldBe` Just (showVal absoluteZero)

  it "a freshly-initialized ledger is empty" $ do
    ledger <- run currentLedger
    Map.size (snapshot ledger) `shouldBe` 0
    fmap showVal (readCell ["anything"] ledger) `shouldBe` Nothing

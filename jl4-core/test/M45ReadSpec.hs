{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | M4.5 tests for cross-party and official-record RECALL reads.
--
-- M1.5 gave @RECALL <cell>@ — a read of the CURRENT acting party's OWN ledger.
-- M4.5 adds two qualified read forms (mirroring the M4 write routing):
--
--   * @RECALL <party>'s <cell>@  reads ANOTHER party's OWN ledger (the party is
--     name-resolved and keyed via 'partyKeyWHNF', so a read matches a write);
--   * @RECALL OFFICIAL's <cell>@ reads the shared OFFICIAL record (the
--     COMMIT/ATTEST target).
--
-- The default @RECALL <cell>@ is unchanged (the current party's own ledger).
--
-- Because reads are party-relative, the only faithful way to exercise the
-- routing is inside a REAL regulative program where the acting party is set by
-- the deontic state machine (top-level @#EVAL@s have no party and are isolated
-- per-directive by 'withFreshLedger'). So — exactly like 'M4PartyLedgerSpec' —
-- we run a multi-party @#TRACE@ through 'execEvalModuleWithEnv' and inspect the
-- per-directive 'LedgerStore' it captures.
--
-- The trick that makes a READ observable: a RECALL is RECORDed/COMMITted into a
-- fresh cell, so its @JUST v@/@NOTHING@ result lands in the ledger as the cell's
-- value, where the test can read it back out. (A bare RECALL value is otherwise
-- consumed by the deontic chain.)
--
-- Coverage:
--   (a) Alice RECORDs `x`; Bob reads it cross-party (@RECALL Alice's `x`@ -> JUST)
--       AND Alice's own bare @RECALL `x`@ inside her step also sees it.
--   (b) @RECALL OFFICIAL's `oc`@ is JUST after a COMMIT of `oc`; reading an
--       un-committed cell from the official record is NOTHING.
--   (c) @RECALL Bob's `x`@ where Bob recorded nothing is NOTHING.
--   (d) the default bare @RECALL `x`@ reads the CURRENT party's own ledger
--       (M1.5 regression): Alice's bare read of her own `x` is JUST.
--   (e) ISOLATION: a cell that lives only in an OWN ledger is invisible to an
--       official read, and a cell that lives only in the OFFICIAL record is
--       invisible to a cross-party own read.
module M45ReadSpec (spec) where

import qualified Data.Map.Strict as Map
import qualified Data.Text as Text

import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Evaluate.Ledger
  ( Ledger
  , LedgerEvent (..)
  , LedgerStore (..)
  )
import L4.Evaluate.ValueLazy (Value (..), WHNF)
import L4.EvaluateLazy
  ( EvalDirectiveResult (..)
  , execEvalModuleWithEnv
  , resolveEvalConfig
  )
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.Syntax (getUnique)
import qualified L4.TypeCheck as TypeCheck
import L4.TracePolicy (apiDefaultPolicy)

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

-- A fixed time keeps evaluation deterministic.
fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

-- | Typecheck a one-module source and run all its directives.
runDirectives :: Text.Text -> IO [EvalDirectiveResult]
runDirectives source = do
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  case checkWithImports (vfsFromList []) source of
    Left errs -> do
      expectationFailure ("typecheck failed: " <> show errs)
      pure []
    Right r -> do
      (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
      pure results

-- | Look up the latest WHNF value recorded for a cell path in a ledger
-- (last-write-wins, newest-last list).
cellValue :: [Text.Text] -> Ledger -> Maybe WHNF
cellValue path led =
  case [ v | Assign p v _ <- foldr (:) [] led, p == path ] of
    [] -> Nothing
    vs -> Just (last vs)

isJustWHNF :: WHNF -> Bool
isJustWHNF (ValConstructor r [_]) = getUnique r == TypeCheck.justUnique
isJustWHNF _                      = False

isNothingWHNF :: WHNF -> Bool
isNothingWHNF (ValConstructor r []) = getUnique r == TypeCheck.nothingUnique
isNothingWHNF _                     = False

-- | A two-party regulative program that records, reads-back, commits, and
-- official-reads, stashing each RECALL's result into a cell we can inspect.
--
-- Step 1 (Alice): RECORD `x` IS 273.15, then RECORD `aliceBareReadback` IS
--   (RECALL `x`)            -- Alice's OWN bare read of her own cell -> JUST (d)
-- Step 2 (Bob):   RECORD `bobReadsAlice` IS (RECALL Alice's `x`)   -- (a) JUST
--                 RECORD `bobReadsBobX`  IS (RECALL Bob's `x`)      -- (c) NOTHING
--                 RECORD `bobReadsOffX`  IS (RECALL OFFICIAL's `x`) -- (e) NOTHING (x is OWN only)
-- Step 3 (Carol): COMMIT `oc` IS 99, then
--                 COMMIT `carolReadsOff` IS (RECALL OFFICIAL's `oc`) -- (b) JUST
--                 COMMIT `carolReadsAliceOc` IS (RECALL Alice's `oc`) -- (e) NOTHING (oc is OFFICIAL only)
--
-- Each RECORD/COMMIT but the last in a step carries a HENCE so the recorded
-- value is DATA (the M5 event-free step); the last in each step's chain carries
-- the next obligation (or FULFILLED) so the chain type-checks.
src :: Text.Text
src = Text.unlines
  [ "DECLARE Person IS ONE OF Alice, Bob, Carol"
  , "DECLARE Action IS ONE OF act"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "scenario MEANS"
  , "  PARTY Alice"
  , "  MUST act"
  , "  WITHIN 100"
  , "  HENCE RECORD `x` IS 273.15"
  , "        HENCE RECORD `aliceBareReadback` IS (RECALL `x`)"
  , "              HENCE PARTY Bob"
  , "                    MUST act"
  , "                    WITHIN 100"
  , "                    HENCE RECORD `bobReadsAlice` IS (RECALL Alice's `x`)"
  , "                          HENCE RECORD `bobReadsBobX` IS (RECALL Bob's `x`)"
  , "                                HENCE RECORD `bobReadsOffX` IS (RECALL OFFICIAL's `x`)"
  , "                                      HENCE PARTY Carol"
  , "                                            MUST act"
  , "                                            WITHIN 100"
  , "                                            HENCE COMMIT `oc` IS 99"
  , "                                                  HENCE COMMIT `carolReadsOff` IS (RECALL OFFICIAL's `oc`)"
  , "                                                        HENCE COMMIT `carolReadsAliceOc` IS (RECALL Alice's `oc`)"
  , "                                                              HENCE COMMIT `done` IS FULFILLED"
  , ""
  , "#TRACE scenario AT 0 WITH"
  , "  PARTY Alice DOES act AT 1"
  , "  PARTY Bob DOES act AT 2"
  , "  PARTY Carol DOES act AT 3"
  ]

spec :: Spec
spec = describe "STATE-AS-LEDGER M4.5: cross-party + official RECALL reads" $ do
  -- Run the scenario once; every case inspects the resulting store.
  let withStore k = do
        [res] <- runDirectives src
        k (res.ledger)
      aliceLedger store = Map.findWithDefault mempty "Alice" store.ownLedgers
      bobLedger store   = Map.findWithDefault mempty "Bob"   store.ownLedgers

  describe "(d) the default bare RECALL reads the current party's own ledger (M1.5)" $
    it "Alice's bare RECALL `x` (inside her own step) is JUST" $
      withStore $ \store ->
        case cellValue ["aliceBareReadback"] (aliceLedger store) of
          Just v  -> isJustWHNF v `shouldBe` True
          Nothing -> expectationFailure "expected `aliceBareReadback` in Alice's own ledger"

  describe "(a) cross-party read of a recorded cell" $
    it "Bob's RECALL Alice's `x` is JUST (he reads Alice's own ledger)" $
      withStore $ \store ->
        case cellValue ["bobReadsAlice"] (bobLedger store) of
          Just v  -> isJustWHNF v `shouldBe` True
          Nothing -> expectationFailure "expected `bobReadsAlice` in Bob's own ledger"

  describe "(c) cross-party read of a party that recorded nothing" $
    it "Bob's RECALL Bob's `x` is NOTHING (Bob never recorded `x`)" $
      withStore $ \store ->
        case cellValue ["bobReadsBobX"] (bobLedger store) of
          Just v  -> isNothingWHNF v `shouldBe` True
          Nothing -> expectationFailure "expected `bobReadsBobX` in Bob's own ledger"

  describe "(b) official read after COMMIT (JUST)" $
    it "Carol's RECALL OFFICIAL's `oc` is JUST (she COMMITted `oc` first)" $
      withStore $ \store ->
        case cellValue ["carolReadsOff"] store.officialLedger of
          Just v  -> isJustWHNF v `shouldBe` True
          Nothing -> expectationFailure "expected `carolReadsOff` in the official record"

  describe "(e) isolation: own and official ledgers do not bleed into each other" $ do
    it "RECALL OFFICIAL's `x` is NOTHING (`x` lives only in own ledgers)" $
      withStore $ \store ->
        case cellValue ["bobReadsOffX"] (bobLedger store) of
          Just v  -> isNothingWHNF v `shouldBe` True
          Nothing -> expectationFailure "expected `bobReadsOffX` in Bob's own ledger"

    it "RECALL Alice's `oc` is NOTHING (`oc` lives only in the official record)" $
      withStore $ \store ->
        case cellValue ["carolReadsAliceOc"] store.officialLedger of
          Just v  -> isNothingWHNF v `shouldBe` True
          Nothing -> expectationFailure "expected `carolReadsAliceOc` in the official record"

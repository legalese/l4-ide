{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Machine-level tests for bitemporal stamping and context-sensitive RECALL
-- (smucclaw/l4-ide#914 §2A/§2B) — the wiring between the temporal context and
-- the ledger substrate, which the pure 'BitemporalSubstrateSpec' cannot see.
--
-- What is asserted where:
--
--   * STAMPS, directly on the captured per-directive 'LedgerStore':
--     - a plain @RECORD@ stamps @txTime = the root eval clock@ and
--       @vtFrom = Nothing@ (contemporaneous);
--     - a @RECORD@ inside @EVAL UNDER VALID TIME d@ stamps @vtFrom = Just d@;
--     - a @RECORD@ inside @EVAL AS OF SYSTEM TIME t@ STILL stamps the root
--       clock — the tx-immunity audit invariant: that clause scopes reads,
--       never writes;
--     - both clauses nested: vt from the valid-time clause, tx untouched.
--   * READS, via the M4.5 readback trick (a RECALL's JUST\/NOTHING result is
--     RECORDed into a fresh cell inside a @#TRACE@ chain, where the test can
--     inspect it): bare RECALL sees the write; a valid-time point before the
--     write's effective valid-from is NOTHING; a valid-time point at\/after
--     it is JUST; an AS-OF bound before the write's tx is NOTHING.
--
-- Payload-level selection between multiple valid-time regimes (7-vs-9) is
-- covered by 'BitemporalSubstrateSpec' (pure fold) and the
-- @jl4/examples/ok/ledger/bitemporal-*.l4@ goldens (end-to-end printing).
module BitemporalRecallSpec (spec) where

import qualified Data.Map.Strict as Map
import qualified Data.Text as Text

import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Evaluate.Ledger
  ( Ledger
  , LedgerEvent (..)
  , LedgerStore (..)
  , Provenance (..)
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

import Data.Time (Day, UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

-- A fixed time keeps evaluation deterministic. This is the ROOT eval clock:
-- every txTime stamped during these runs must equal it, regardless of any
-- EVAL AS OF SYSTEM TIME override in scope at the write.
fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

d :: Integer -> Int -> Int -> Day
d = fromGregorian

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

-- | All provenances for a cell path, oldest-first.
provsFor :: [Text.Text] -> Ledger -> [Provenance]
provsFor path led = [ pv | Assign p _ pv <- foldr (:) [] led, p == path ]

-- | Latest recorded value for a cell path (last-write-wins).
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

-- A top-level #EVAL has no acting party: its writes land in the anonymous own
-- ledger (key "").
anonLedger :: LedgerStore -> Ledger
anonLedger store = Map.findWithDefault mempty "" store.ownLedgers

spec :: Spec
spec = describe "bitemporal stamping + context-sensitive RECALL (#914 §2A/§2B)" $ do

  describe "STAMPS (one directive per case; each captures its own LedgerStore)" $ do

    it "a plain RECORD is contemporaneous: txTime = root clock, vtFrom = Nothing" $ do
      [res] <- runDirectives "#EVAL RECORD `plain` IS 1\n"
      case provsFor ["plain"] (anonLedger res.ledger) of
        [pv] -> do
          pv.txTime `shouldBe` fixedNow
          pv.vtFrom `shouldBe` Nothing
        other -> expectationFailure ("expected one Assign, got " <> show (length other))

    it "RECORD inside EVAL UNDER VALID TIME stamps the asserted valid-from" $ do
      [res] <- runDirectives
        "#EVAL `EVAL UNDER VALID TIME` (DATE_FROM_DMY 1 1 2023) (RECORD `dated` IS 7)\n"
      case provsFor ["dated"] (anonLedger res.ledger) of
        [pv] -> do
          pv.txTime `shouldBe` fixedNow
          pv.vtFrom `shouldBe` Just (d 2023 1 1)
        other -> expectationFailure ("expected one Assign, got " <> show (length other))

    it "tx-IMMUNITY: RECORD inside EVAL AS OF SYSTEM TIME still stamps the root clock" $ do
      [res] <- runDirectives
        "#EVAL `EVAL AS OF SYSTEM TIME` (DATE_FROM_DMY 1 1 2020) (RECORD `immune` IS 2)\n"
      case provsFor ["immune"] (anonLedger res.ledger) of
        [pv] -> do
          -- the audit invariant: AS OF scopes reads, never writes
          pv.txTime `shouldBe` fixedNow
          pv.vtFrom `shouldBe` Nothing
        other -> expectationFailure ("expected one Assign, got " <> show (length other))

    it "nested clauses: vt from the valid-time clause, tx still the root clock" $ do
      [res] <- runDirectives
        "#EVAL `EVAL AS OF SYSTEM TIME` (DATE_FROM_DMY 1 1 2020) (`EVAL UNDER VALID TIME` (DATE_FROM_DMY 5 5 2021) (RECORD `both` IS 3))\n"
      case provsFor ["both"] (anonLedger res.ledger) of
        [pv] -> do
          pv.txTime `shouldBe` fixedNow
          pv.vtFrom `shouldBe` Just (d 2021 5 5)
        other -> expectationFailure ("expected one Assign, got " <> show (length other))

    it "the clause scope CLOSES before a sibling write: only the wrapped RECORD is dated" $ do
      -- The valid-time clause wraps only the VALUE of the outer RECORD; by the
      -- time the outer write itself fires, the override has been restored.
      [res] <- runDirectives
        "#EVAL RECORD `outer` IS (`EVAL UNDER VALID TIME` (DATE_FROM_DMY 1 1 2023) (RECORD `inner` IS 7))\n"
      case (provsFor ["inner"] (anonLedger res.ledger), provsFor ["outer"] (anonLedger res.ledger)) of
        ([inner], [outer]) -> do
          inner.vtFrom `shouldBe` Just (d 2023 1 1)
          outer.vtFrom `shouldBe` Nothing
          outer.txTime `shouldBe` fixedNow
        (inners, outers) -> expectationFailure
          ("expected one Assign each, got " <> show (length inners, length outers))

  describe "READS (context-scoped RECALL inside a #TRACE, via the readback trick)" $ do
    -- Alice records `x` (contemporaneous: effective valid-from = the root
    -- clock's day, 2026-01-01), then reads it back under various contexts.
    let src = Text.unlines
          [ "DECLARE Person IS ONE OF Alice"
          , "DECLARE Action IS ONE OF act"
          , ""
          , "GIVETH DEONTIC Person Action"
          , "scenario MEANS"
          , "  PARTY Alice"
          , "  MUST act"
          , "  WITHIN 100"
          , "  HENCE RECORD `x` IS 7"
          , "        HENCE RECORD `rbBare` IS (RECALL `x`)"
          , "              HENCE RECORD `rbCovered` IS (`EVAL UNDER VALID TIME` (DATE_FROM_DMY 1 6 2026) (RECALL `x`))"
          , "                    HENCE RECORD `rbEarly` IS (`EVAL UNDER VALID TIME` (DATE_FROM_DMY 1 6 2022) (RECALL `x`))"
          , "                          HENCE RECORD `rbAsOfPast` IS (`EVAL AS OF SYSTEM TIME` (DATE_FROM_DMY 1 1 2020) (RECALL `x`))"
          , "                                HENCE COMMIT `done` IS FULFILLED"
          , ""
          , "#TRACE scenario AT 0 WITH"
          , "  PARTY Alice DOES act AT 1"
          ]
        withStore k = do
          [res] <- runDirectives src
          k (Map.findWithDefault mempty "Alice" res.ledger.ownLedgers)
        readback name expect led =
          case cellValue [name] led of
            Just v  -> expect v `shouldBe` True
            Nothing -> expectationFailure ("expected `" <> Text.unpack name <> "` in Alice's ledger")

    it "bare RECALL sees the write (unchanged semantics)" $
      withStore (readback "rbBare" isJustWHNF)

    it "a valid-time point covering the write's effective valid-from is JUST" $
      withStore (readback "rbCovered" isJustWHNF)

    it "a valid-time point BEFORE the facts is a principled NOTHING" $
      withStore (readback "rbEarly" isNothingWHNF)

    it "an AS-OF bound before the write's transaction time is NOTHING" $
      withStore (readback "rbAsOfPast" isNothingWHNF)

  describe "SHARED THUNKS answer per temporal scope (adversarial-review regression)" $ do
    -- The critical finding from the pre-PR review: a SHARED binding
    -- containing RECALL, forced first under one scope, must NOT serve that
    -- scope's answer to a later use under a different scope. Post-fix a
    -- read-only ledger force is WHNFWhen-cached on its observed axes
    -- (crLedgerRead does not poison), so the bare use below re-forces.
    let sharedSrc = Text.unlines
          [ "DECLARE Person IS ONE OF Alice"
          , "DECLARE Action IS ONE OF act"
          , ""
          , "`shared read` MEANS RECALL `x`"
          , ""
          , "GIVETH DEONTIC Person Action"
          , "scenario MEANS"
          , "  PARTY Alice"
          , "  MUST act"
          , "  WITHIN 100"
          , "  HENCE RECORD `x` IS 7"
          , "        HENCE RECORD `rbScoped` IS (`EVAL UNDER VALID TIME` (DATE_FROM_DMY 1 6 2022) `shared read`)"
          , "              HENCE RECORD `rbBareShared` IS `shared read`"
          , "                    HENCE COMMIT `done` IS FULFILLED"
          , ""
          , "#TRACE scenario AT 0 WITH"
          , "  PARTY Alice DOES act AT 1"
          ]
        withSharedStore k = do
          [res] <- runDirectives sharedSrc
          k (Map.findWithDefault mempty "Alice" res.ledger.ownLedgers)
        readbackShared name expect led =
          case cellValue [name] led of
            Just v  -> expect v `shouldBe` True
            Nothing -> expectationFailure ("expected `" <> Text.unpack name <> "` in Alice's ledger")

    it "the scoped use (before the facts) is NOTHING" $
      withSharedStore (readbackShared "rbScoped" isNothingWHNF)

    it "the bare use of the SAME shared binding re-forces and is JUST (not the cached NOTHING)" $
      withSharedStore (readbackShared "rbBareShared" isJustWHNF)

{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | M4 (FINAL) tests for the event-sourced ledger: per-party own ledgers + a
-- shared official record, with the acting party threaded into a RECORD/COMMIT
-- fired inside a deontic HENCE/LEST continuation.
--
-- M1/M1.5/M2 proved the write/read paths and surfacing for TOP-LEVEL
-- (party-less) writes. M4 adds the routing that only a REGULATIVE context can
-- exercise: when a @RECORD@ fires inside the HENCE of @PARTY Alice MUST …@, the
-- matched party (Alice) is in scope and the write must land in /Alice's own/
-- ledger with @party=Alice@; a @COMMIT@ fired inside @PARTY Bob MUST …@ must
-- land in the /shared official record/ with @party=Bob@.
--
-- We drive a real obligation against an event trace through
-- 'execEvalModuleWithEnv' (a @#TRACE@ directive), then inspect the per-directive
-- 'LedgerStore' that 'EvalDirectiveResult' now carries:
--
--   (a) PER-PARTY ROUTING. A two-party rule — Alice MUST deliver HENCE RECORD …
--       (whose recorded value is itself Bob's nested obligation, the only way to
--       chain a write before a further obligation without the M5 sequencing
--       syntax) — routes Alice's RECORD to @ownLedgers["Alice"]@ with
--       @party=Alice@, and routes Bob's nested COMMIT to the @officialLedger@
--       with @party=Bob@. The rendered output shows a @Ledger (Alice):@ block
--       and an @Official record:@ block.
--
--   (b) D5 (keep-on-breach, the REAL breach test M2 lacked). A MUST whose HENCE
--       RECORDs a value and then imposes a second MUST that is never discharged
--       BREACHES ('ValBreached'). The pre-breach RECORD's 'Assign' must STILL be
--       present in Alice's own ledger — the audit trail of a failed execution,
--       exactly the burden monad's MaybeT-outside-Writer guarantee.
module M4PartyLedgerSpec (spec) where

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
import L4.Evaluate.ValueLazy (NF (..), Value (..))
import L4.EvaluateLazy
  ( EvalDirectiveResult (..)
  , EvalDirectiveValue (..)
  , execEvalModuleWithEnv
  , prettyEvalDirectiveResult
  , resolveEvalConfig
  )
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.TracePolicy (apiDefaultPolicy)

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

-- A fixed time keeps evaluation deterministic.
fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

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

-- | The cell 'Path's recorded in a single ledger, oldest-first.
cellsOf :: Ledger -> [[Text.Text]]
cellsOf led = [ p | Assign p _ _ <- foldr (:) [] led ]

-- | The (cell, party) provenance pairs in a single ledger.
cellParties :: Ledger -> [([Text.Text], Text.Text)]
cellParties led = [ (p, prov.party) | Assign p _ prov <- foldr (:) [] led ]

-- | A two-party regulative rule. Alice MUST deliver; on delivery she RECORDs a
-- cell whose value is Bob's nested obligation (the chain-a-write-before-an-
-- obligation idiom). On Bob's payment his HENCE COMMITs to the official record.
twoPartySrc :: Text.Text
twoPartySrc = Text.unlines
  [ "DECLARE Person IS ONE OF Alice, Bob"
  , "DECLARE Action IS ONE OF"
  , "  deliver"
  , "  pay HAS amount IS A NUMBER"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "twoParties MEANS"
  , "  PARTY Alice"
  , "  MUST deliver"
  , "  WITHIN 10"
  , "  HENCE"
  , "    RECORD `delivery done` IS"
  , "      (PARTY Bob"
  , "       MUST pay 50"
  , "       WITHIN 10"
  , "       HENCE COMMIT `total paid` IS FULFILLED)"
  , ""
  , "#TRACE twoParties AT 0 WITH"
  , "  PARTY Alice DOES deliver AT 2"
  , "  PARTY Bob DOES pay 50 AT 4"
  ]

-- | A real-breach rule (D5). Alice MUST deliver; on delivery she RECORDs a cell
-- whose value is a SECOND obligation (Alice MUST report within 5) that is never
-- discharged, so the whole rule BREACHES once the clock passes the deadline.
breachSrc :: Text.Text
breachSrc = Text.unlines
  [ "DECLARE Person IS ONE OF Alice, Bob"
  , "DECLARE Action IS ONE OF"
  , "  deliver"
  , "  report"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "recordThenBreach MEANS"
  , "  PARTY Alice"
  , "  MUST deliver"
  , "  WITHIN 10"
  , "  HENCE"
  , "    RECORD `delivery recorded` IS"
  , "      (PARTY Alice"
  , "       MUST report"
  , "       WITHIN 5)"
  , ""
  , "#TRACE recordThenBreach AT 0 WITH"
  , "  PARTY Alice DOES deliver AT 2"
  , "  (`WAIT UNTIL` 100)"
  ]

-- | Is this fully-forced normal form a 'ValBreached'?
isBreachedNF :: NF -> Bool
isBreachedNF (MkNF (ValBreached _)) = True
isBreachedNF _                      = False

spec :: Spec
spec = describe "STATE-AS-LEDGER M4: per-party ledgers + official record (R1)" $ do

  describe "(a) per-party / official routing in a regulative event trace" $ do
    it "Alice's RECORD lands in her OWN ledger (party=Alice); Bob's COMMIT lands in the OFFICIAL record (party=Bob)" $ do
      [res] <- runDirectives twoPartySrc
      let store = res.ledger

      -- Alice has an own ledger; Bob (who only COMMITs) does not.
      Map.keys store.ownLedgers `shouldBe` ["Alice"]

      -- Alice's own ledger holds exactly the `delivery done` RECORD, stamped Alice.
      cellParties (store.ownLedgers Map.! "Alice")
        `shouldBe` [(["delivery done"], "Alice")]

      -- The official record holds exactly Bob's `total paid` COMMIT, stamped Bob.
      cellParties store.officialLedger
        `shouldBe` [(["total paid"], "Bob")]

    it "renders a Ledger (Alice): block and an Official record: block" $ do
      [res] <- runDirectives twoPartySrc
      let rendered = prettyEvalDirectiveResult res
      rendered `shouldSatisfy` Text.isInfixOf "Ledger (Alice):"
      rendered `shouldSatisfy` Text.isInfixOf "RECORD `delivery done`"
      rendered `shouldSatisfy` Text.isInfixOf "party=Alice"
      rendered `shouldSatisfy` Text.isInfixOf "Official record:"
      rendered `shouldSatisfy` Text.isInfixOf "COMMIT `total paid`"
      rendered `shouldSatisfy` Text.isInfixOf "party=Bob"

  describe "(b) D5: a RECORD before a real ValBreached survives in the party's own ledger" $ do
    it "the rule BREACHES, and the pre-breach Assign is still in Alice's own ledger" $ do
      [res] <- runDirectives breachSrc

      -- The directive's value is a real breach (deadline missed on the second MUST).
      case res.result of
        Reduction (Right nf) -> isBreachedNF nf `shouldBe` True
        other                -> expectationFailure ("expected a ValBreached reduction, got " <> show other)

      -- ... and the pre-breach RECORD survives in Alice's own ledger (keep-on-breach).
      let store = res.ledger
      Map.keys store.ownLedgers `shouldBe` ["Alice"]
      cellsOf (store.ownLedgers Map.! "Alice") `shouldBe` [["delivery recorded"]]
      -- nothing was committed to the official record on this failed run.
      cellsOf store.officialLedger `shouldBe` []

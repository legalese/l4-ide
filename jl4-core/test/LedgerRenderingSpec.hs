{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | M2 surfacing + provenance tests for the event-sourced ledger.
--
-- M1/M1.5 (RecordLedgerSpec) proved the write/read paths and that an 'Assign'
-- lands in the ledger. M2 makes those writes USER-VISIBLE and the provenance
-- REAL. This spec asserts the two M2 deliverables end-to-end, through the
-- real module-evaluation path ('execEvalModuleWithEnv', which wraps each
-- directive in 'withFreshLedger' and captures the per-directive ledger onto
-- 'EvalDirectiveResult.ledger'):
--
--   (1) SURFACING. The rendered directive output
--       ('prettyEvalDirectiveResult') of @#EVAL RECORD \`x\` IS 273.15@
--       CONTAINS a labelled @Ledger:@ section with the row for @x@ tagged
--       @source=RECORD@ — the primary user-visible deliverable.
--
--   (2) PROVENANCE. The captured 'Provenance' on that 'Assign' carries a real
--       @source@ ("RECORD" / "COMMIT") and a real @position@ (the ISO-8601
--       evaluation timestamp from 'evalTime') — no longer the M1 placeholders.
--       (party is intentionally empty in M2; see the spec's openIssues.)
--
--   (3) NO CLUTTER. A directive that only READS (or evaluates an ordinary
--       expression) renders NO @Ledger:@ section — reads are not ledger events.
--
--   (4) COMMIT. A @COMMIT@ write surfaces with the @COMMIT@ verb and
--       @source=COMMIT@.
--
--   (5) D5 (keep-on-breach, by construction). 'tellEvent' is an append and
--       the per-directive ledger is captured AFTER evaluation, so a value
--       RECORDed before any later failure still appears in the rendered
--       ledger. We assert the captured ledger row survives alongside a result
--       even when the directive's overall value is something else (here the
--       write is sequenced before a read in one LIST directive — the write's
--       Assign is present in the rendered ledger regardless of what the
--       directive ultimately reduces to).
module LedgerRenderingSpec (spec) where

import qualified Data.Text as Text

import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import qualified Data.Map.Strict as Map

import L4.Evaluate.Ledger (LedgerEvent (..), LedgerStore (..), Provenance (..))
import L4.EvaluateLazy
  ( EvalDirectiveResult (..)
  , execEvalModuleWithEnv
  , prettyEvalDirectiveResult
  , resolveEvalConfig
  )
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.TracePolicy (apiDefaultPolicy)

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

-- A fixed time keeps the rendered provenance timestamp deterministic.
fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

fixedNowIso :: Text.Text
fixedNowIso = "2026-01-01T00:00:00Z"

-- | Typecheck a one-module source and run all its directives, returning the
-- per-directive results (each carrying its captured ledger). Fails the test on
-- a typecheck error.
runDirectives :: UTCTime -> Text.Text -> IO [EvalDirectiveResult]
runDirectives now src = do
  cfg <- resolveEvalConfig (Just now) apiDefaultPolicy
  case checkWithImports (vfsFromList []) src of
    Left errs -> do
      expectationFailure ("typecheck failed: " <> show errs)
      pure []
    Right r -> do
      (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
      pure results

-- | The 'Assign' provenances in a directive's captured store, across every
-- party's own ledger and the official record (M4: 'ledger' is now a
-- 'LedgerStore'). Each ledger is a 'DList', which is 'Foldable'; @foldr (:) []@
-- materialises it oldest-first.
ledgerProvenances :: EvalDirectiveResult -> [Provenance]
ledgerProvenances res =
  [ p
  | led <- Map.elems res.ledger.ownLedgers <> [res.ledger.officialLedger]
  , Assign _ _ p <- foldr (:) [] led
  ]

spec :: Spec
spec = describe "STATE-AS-LEDGER M2: ledger surfacing + real provenance" $ do

  describe "(1) SURFACING: RECORD writes appear in the rendered directive output" $ do
    it "the rendered output contains a Ledger: section with the row for `x` (source=RECORD)" $ do
      [res] <- runDirectives fixedNow "#EVAL RECORD `x` IS 273.15\n"
      let rendered = prettyEvalDirectiveResult res
      rendered `shouldSatisfy` Text.isInfixOf "Ledger:"
      rendered `shouldSatisfy` Text.isInfixOf "RECORD `x` IS 273.15"
      rendered `shouldSatisfy` Text.isInfixOf "source=RECORD"
      -- the written value is still the directive's result
      rendered `shouldSatisfy` Text.isInfixOf "273.15"

  describe "(2) PROVENANCE: source + timestamp are real (no longer placeholders)" $ do
    it "captures source = RECORD and a real ISO-8601 position from evalTime" $ do
      [res] <- runDirectives fixedNow "#EVAL RECORD `x` IS 273.15\n"
      case ledgerProvenances res of
        [p] -> do
          p.source `shouldBe` "RECORD"
          p.position `shouldBe` Just fixedNowIso
          -- party is intentionally empty in M2 (see openIssues)
          p.party `shouldBe` ""
        other -> expectationFailure ("expected exactly one Assign provenance, got " <> show (length other))

    it "the rendered provenance brackets show source=RECORD and at=<timestamp>" $ do
      [res] <- runDirectives fixedNow "#EVAL RECORD `x` IS 273.15\n"
      let rendered = prettyEvalDirectiveResult res
      rendered `shouldSatisfy` Text.isInfixOf ("at=" <> fixedNowIso)
      -- party is empty, so no party= field is emitted
      rendered `shouldNotSatisfy` Text.isInfixOf "party="

  describe "(3) NO CLUTTER: pure reads / ordinary expressions emit no Ledger section" $ do
    it "RECALL of a never-written cell renders no Ledger: section" $ do
      [res] <- runDirectives fixedNow "#EVAL RECALL `nope`\n"
      let rendered = prettyEvalDirectiveResult res
      rendered `shouldNotSatisfy` Text.isInfixOf "Ledger:"
      ledgerProvenances res `shouldBe` []

    it "an ordinary arithmetic directive renders no Ledger: section" $ do
      [res] <- runDirectives fixedNow "#EVAL 1 + 1\n"
      prettyEvalDirectiveResult res `shouldNotSatisfy` Text.isInfixOf "Ledger:"

  describe "(4) COMMIT surfaces with the COMMIT verb and source=COMMIT" $ do
    it "COMMIT `rate` IS 4.25 renders COMMIT ... and source=COMMIT" $ do
      [res] <- runDirectives fixedNow "#EVAL COMMIT `rate` IS 4.25\n"
      let rendered = prettyEvalDirectiveResult res
      rendered `shouldSatisfy` Text.isInfixOf "COMMIT `rate` IS 4.25"
      rendered `shouldSatisfy` Text.isInfixOf "source=COMMIT"
      map (.source) (ledgerProvenances res) `shouldBe` ["COMMIT"]

  describe "(5) D5 (keep-on-breach by construction): a write sequenced before a later step survives" $ do
    it "a RECORD sequenced before a RECALL in one directive still appears in the rendered ledger" $ do
      -- LIST (write), (read) — the write's Assign is appended and the ledger is
      -- captured after the whole directive, so the Assign is present regardless
      -- of what the directive reduces to (the append is never rolled back).
      [res] <- runDirectives fixedNow
                 "#EVAL LIST (RECORD `x` IS 273.15), (fromMaybe 0 (RECALL `x`))\n"
      let rendered = prettyEvalDirectiveResult res
      rendered `shouldSatisfy` Text.isInfixOf "RECORD `x` IS 273.15"
      map (.source) (ledgerProvenances res) `shouldBe` ["RECORD"]

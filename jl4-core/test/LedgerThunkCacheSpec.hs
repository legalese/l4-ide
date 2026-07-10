{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | STATE-AS-LEDGER x T6: ledger effects inside a thunk force and the
-- 'WHNFWhen' (context-fingerprinted) cache — the split-poison design
-- (smucclaw\/l4-ide#914).
--
-- T6 caches a context-dependent force as @WHNFWhen fp v@ and RE-FORCES the
-- thunk whenever the current temporal context no longer matches @fp@. Ledger
-- effects interact with that premise asymmetrically:
--
--   * a re-forced RECORD\/COMMIT\/ATTEST APPENDS its event again — a
--     double-write observable via @RECALL ALL@ and the per-directive ledger.
--     WRITES therefore poison the cache ('crLedgerWrite'): a write-containing
--     force installs a plain 'WHNF' (snapshot at first force, the write
--     fires exactly once).
--   * a RECALL's result depends on the ambient temporal axes (#914 §2B), so
--     READS are 'WHNFWhen'-cached on the axes 'finishRead' observes
--     ('crLedgerRead'): SNAPSHOT PER TEMPORAL SCOPE. Under an unchanged
--     context the first-force value is re-served (the fingerprint does not
--     track the ledger, so later writes stay invisible to the shared thunk
--     — the pre-bitemporal snapshot semantics, per scope); under a DIFFERENT
--     context the thunk re-forces against the current ledger, so each scope
--     gets its own scope-correct answer.
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

-- | A shared top-level binding whose force RECALLs a cell, used first under
-- an AS OF override and then bare, with a RECORD to the same cell in between
-- (ONE #EVAL; list elements normalize left-to-right). Post-#914 the two uses
-- are DIFFERENT temporal scopes, so the second use re-forces and reads the
-- current ledger.
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

-- | CONTROL (contract #914 §4): the same shape but with NO clause anywhere —
-- both uses of the shared binding run under the one ambient scope, so the
-- fingerprint matches and the first-force snapshot is re-served: clause-free
-- programs keep the exact pre-bitemporal sharing semantics (the meanwhile-
-- written 7 stays invisible to the shared thunk). This guards against
-- "fixing" scope-sensitivity by never caching ledger reads at all (which
-- would re-run the RECALL here and yield 7).
recallControlSrc :: Text.Text
recallControlSrc = Text.unlines
  [ "`recall or zero` MEANS"
  , "  CONSIDER RECALL `x`"
  , "  WHEN JUST v THEN v"
  , "  WHEN NOTHING THEN 0"
  , ""
  , "#EVAL LIST `recall or zero`, (RECORD `x` IS 7), `recall or zero`"
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

  describe "a shared RECALL thunk snapshots PER TEMPORAL SCOPE (#914 §2B)" $ do
    it "a use under a different scope re-forces against the current ledger" $ do
      [res] <- runDirectives recallCoherenceSrc
      -- 737789 = DATE_SERIAL (2020-01-01), the override under which the
      -- binding was first forced (cell `x` not yet written -> TODAY under
      -- the override). The bare third use is a DIFFERENT scope: the axis
      -- fingerprint mismatches, the thunk re-forces, and the read sees the
      -- meanwhile-written 7 — the scope-correct answer mandated by #914
      -- (pre-#914 this snapshotted per directive: LIST 737789, 7, 737789).
      renderedResult res `shouldBe` "LIST 737789, 7, 7"
      -- exactly the one explicit RECORD, no extras (re-forcing a READ-only
      -- thunk appends nothing)
      cellsOf (Map.findWithDefault mempty anonymousParty res.ledger.ownLedgers)
        `shouldBe` [["x"]]

    it "CONTROL (clause-free, contract §4): same scope -> the first-force snapshot is re-served" $ do
      [res] <- runDirectives recallControlSrc
      renderedResult res `shouldBe` "LIST 0, 7, 0"
      cellsOf (Map.findWithDefault mempty anonymousParty res.ledger.ownLedgers)
        `shouldBe` [["x"]]

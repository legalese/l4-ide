{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | M5 tests for the event-sourced ledger: deontic sequencing of state effects.
--
-- M1–M4 made @RECORD@/@COMMIT@/@ATTEST@ a value-expression (it evaluated to its
-- written value). M5 gives the write an OPTIONAL @HENCE@ continuation, turning it
-- into a first-class /event-free deontic step/ in a @HENCE@ chain:
--
-- >  PARTY Alice MUST deliver
-- >  HENCE RECORD `delivery done` IS <data>     -- fires tellEvent, consumes NO event
-- >  HENCE PARTY Bob MUST pay 50
-- >  HENCE COMMIT `total paid` IS FULFILLED
--
-- The correspondence is monadic do-notation: @p HENCE RECORD x IS v HENCE q@
-- ≡ @do { p; tell (x ↦ v); q }@. The write fires during the forward-eval of the
-- 'Record' node — exactly when 'continueWithFollowup' forwards to it — and then
-- becomes the continuation by forwarding @[time, events]@ to its @HENCE@, instead
-- of returning the written value.
--
-- We drive real obligations against event traces through 'execEvalModuleWithEnv'
-- (a @#TRACE@ directive) and inspect the per-directive 'LedgerStore':
--
--   (a) THE CORE SHAPE. @Alice MUST deliver HENCE RECORD `x` IS <DATA> HENCE
--       Bob MUST pay 50 HENCE COMMIT `y` IS FULFILLED@. Over a trace where both
--       act: @x@ lands in /Alice's own/ ledger holding the DATA (not an
--       obligation — the M4 hack is gone), @y@ lands in the /official record/
--       (Bob), party routing correct, the directive FULFILLs.
--
--   (b) IDEMPOTENCY (redteam #2, the sharp one). A chained @RECORD `a` HENCE
--       RECORD `b` HENCE q@ where @q@'s event scrutiny BACKTRACKS over multiple
--       non-matching events before matching a later one. EXACTLY ONE @Assign@ for
--       @a@ and ONE for @b@ — the writes must not re-fire as @q@ retries events.
--
--   (c) EVENT-FREE (redteam #4). A @MUST@ placed AFTER a @RECORD@ in the chain
--       still consumes its event: a SINGLE-event trace satisfies it, proving the
--       @RECORD@ step consumed no event.
--
--   (d) D5 (keep-on-breach) WITH A RECORD STEP. @MUST deliver HENCE RECORD `r`
--       HENCE MUST report@ where the second @MUST@ breaches: the pre-step
--       @Assign@ for @r@ SURVIVES in the party's own ledger (append + no
--       rollback), and the directive is a real 'ValBreached'.
module M5DeonticSequencingSpec (spec) where

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

-- | The (cell, party) provenance pairs in a single ledger, oldest-first.
cellParties :: Ledger -> [([Text.Text], Text.Text)]
cellParties led = [ (p, prov.party) | Assign p _ prov <- foldr (:) [] led ]

-- | The (cell, shown-value) pairs in a single ledger, oldest-first. Proves the
-- recorded value is the DATA, not a smuggled obligation/continuation.
cellValues :: Ledger -> [([Text.Text], String)]
cellValues led = [ (p, show v) | Assign p v _ <- foldr (:) [] led ]

-- | Is this fully-forced normal form a 'ValBreached'?
isBreachedNF :: NF -> Bool
isBreachedNF (MkNF (ValBreached _)) = True
isBreachedNF _                      = False

-- (a) The core M5 shape: a write step in the middle of a two-party chain, whose
-- recorded value is honest DATA (273), with a later COMMIT to the official
-- record. This is the M4 test's intent WITHOUT the M5 hack of cramming the
-- continuation into the recorded value.
coreSrc :: Text.Text
coreSrc = Text.unlines
  [ "DECLARE Person IS ONE OF Alice, Bob"
  , "DECLARE Action IS ONE OF"
  , "  deliver"
  , "  pay HAS amount IS A NUMBER"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "coreChain MEANS"
  , "  PARTY Alice"
  , "  MUST deliver"
  , "  WITHIN 10"
  , "  HENCE RECORD `delivery done` IS 273"
  , "        HENCE PARTY Bob"
  , "              MUST pay 50"
  , "              WITHIN 10"
  , "              HENCE COMMIT `total paid` IS FULFILLED"
  , ""
  , "#TRACE coreChain AT 0 WITH"
  , "  PARTY Alice DOES deliver AT 2"
  , "  PARTY Bob DOES pay 50 AT 4"
  ]

-- (b) Idempotency under event backtracking. Two chained RECORDs precede an
-- obligation @q@ (Alice MUST target) whose scrutiny must SKIP two non-matching
-- Bob events before matching @Alice DOES target AT 8@. The RECORDs fire BEFORE
-- @q@ is even applied to the event stream, so the ScrutinizeEvents backtracking
-- inside @q@ cannot re-fire them: exactly one Assign each.
idempotencySrc :: Text.Text
idempotencySrc = Text.unlines
  [ "DECLARE Person IS ONE OF Alice, Bob"
  , "DECLARE Action IS ONE OF"
  , "  trigger"
  , "  noise"
  , "  target"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "idemChain MEANS"
  , "  PARTY Alice"
  , "  MUST trigger"
  , "  WITHIN 100"
  , "  HENCE RECORD `a` IS 1"
  , "        HENCE RECORD `b` IS 2"
  , "              HENCE PARTY Alice"
  , "                    MUST target"
  , "                    WITHIN 100"
  , ""
  , "#TRACE idemChain AT 0 WITH"
  , "  PARTY Alice DOES trigger AT 2"
  , "  PARTY Bob DOES noise AT 4"
  , "  PARTY Bob DOES noise AT 6"
  , "  PARTY Alice DOES target AT 8"
  ]

-- (c) Event-free: a RECORD at the head of the chain, then a single MUST. With a
-- one-event trace, the MUST still finds its event — proving the RECORD step
-- consumed nothing. (A top-level RECORD has no enclosing party, so it routes to
-- the anonymous own ledger, keyed "".)
eventFreeSrc :: Text.Text
eventFreeSrc = Text.unlines
  [ "DECLARE Person IS ONE OF Alice, Bob"
  , "DECLARE Action IS ONE OF"
  , "  target"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "eventFreeChain MEANS"
  , "  RECORD `pre` IS 99"
  , "  HENCE PARTY Alice"
  , "        MUST target"
  , "        WITHIN 100"
  , ""
  , "#TRACE eventFreeChain AT 0 WITH"
  , "  PARTY Alice DOES target AT 5"
  ]

-- (d) D5 with a RECORD step then a downstream breach. Alice MUST deliver; on
-- delivery a RECORD fires, then a SECOND MUST (report within 5) that is never
-- discharged, so the chain BREACHES. The pre-step Assign survives.
d5Src :: Text.Text
d5Src = Text.unlines
  [ "DECLARE Person IS ONE OF Alice, Bob"
  , "DECLARE Action IS ONE OF"
  , "  deliver"
  , "  report"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "d5Chain MEANS"
  , "  PARTY Alice"
  , "  MUST deliver"
  , "  WITHIN 10"
  , "  HENCE RECORD `delivery recorded` IS 273"
  , "        HENCE PARTY Alice"
  , "              MUST report"
  , "              WITHIN 5"
  , ""
  , "#TRACE d5Chain AT 0 WITH"
  , "  PARTY Alice DOES deliver AT 2"
  , "  (`WAIT UNTIL` 100)"
  ]

spec :: Spec
spec = describe "STATE-AS-LEDGER M5: deontic sequencing of state effects (p HENCE RECORD HENCE q)" $ do

  describe "(a) RECORD/COMMIT as event-free steps in a HENCE chain" $ do
    it "the directive FULFILLs over a trace where both parties act" $ do
      [res] <- runDirectives coreSrc
      case res.result of
        Reduction (Right nf) -> do
          isBreachedNF nf `shouldBe` False
          prettyEvalDirectiveResult res `shouldSatisfy` Text.isInfixOf "FULFILLED"
        other -> expectationFailure ("expected a FULFILLED reduction, got " <> show other)

    it "Alice's RECORD lands in her OWN ledger, holding the DATA (273), stamped Alice" $ do
      [res] <- runDirectives coreSrc
      let store = res.ledger
      Map.keys store.ownLedgers `shouldBe` ["Alice"]
      cellParties (store.ownLedgers Map.! "Alice")
        `shouldBe` [(["delivery done"], "Alice")]
      -- The recorded value is the DATA 273 (a ValNumber), NOT an obligation:
      -- the M5 sequencing removed the M4 hack of recording the continuation.
      cellValues (store.ownLedgers Map.! "Alice")
        `shouldSatisfy` (\vs -> case vs of
          [(["delivery done"], shown)] ->
            ("273" `Text.isInfixOf` Text.pack shown)
              && not ("Obligation" `Text.isInfixOf` Text.pack shown)
          _ -> False)

    it "Bob's COMMIT lands in the OFFICIAL record, stamped Bob" $ do
      [res] <- runDirectives coreSrc
      let store = res.ledger
      cellParties store.officialLedger
        `shouldBe` [(["total paid"], "Bob")]

    it "renders a Ledger (Alice): block and an Official record: block" $ do
      [res] <- runDirectives coreSrc
      let rendered = prettyEvalDirectiveResult res
      rendered `shouldSatisfy` Text.isInfixOf "Ledger (Alice):"
      rendered `shouldSatisfy` Text.isInfixOf "RECORD `delivery done` IS 273"
      rendered `shouldSatisfy` Text.isInfixOf "party=Alice"
      rendered `shouldSatisfy` Text.isInfixOf "Official record:"
      rendered `shouldSatisfy` Text.isInfixOf "COMMIT `total paid`"
      rendered `shouldSatisfy` Text.isInfixOf "party=Bob"

  describe "(b) IDEMPOTENCY: chained writes fire EXACTLY ONCE under event backtracking" $ do
    it "RECORD `a` HENCE RECORD `b` HENCE q (q backtracks over 2 events) yields exactly one Assign each" $ do
      [res] <- runDirectives idempotencySrc
      let store = res.ledger
      -- Both writes are Alice's; q's scrutiny skipping noise events must NOT
      -- re-fire them. Exactly one `a` and one `b`, in order — no duplicates.
      Map.keys store.ownLedgers `shouldBe` ["Alice"]
      cellsOf (store.ownLedgers Map.! "Alice")
        `shouldBe` [["a"], ["b"]]
      -- And the directive FULFILLs (q eventually matched the later target event).
      case res.result of
        Reduction (Right nf) -> do
          isBreachedNF nf `shouldBe` False
          prettyEvalDirectiveResult res `shouldSatisfy` Text.isInfixOf "FULFILLED"
        other -> expectationFailure ("expected FULFILLED, got " <> show other)

  describe "(c) EVENT-FREE: a MUST after a RECORD still consumes its own event" $ do
    it "a single-event trace satisfies the MUST placed after the RECORD" $ do
      [res] <- runDirectives eventFreeSrc
      -- If the RECORD had consumed the lone event, the MUST would have breached.
      case res.result of
        Reduction (Right nf) -> do
          isBreachedNF nf `shouldBe` False
          prettyEvalDirectiveResult res `shouldSatisfy` Text.isInfixOf "FULFILLED"
        other -> expectationFailure ("expected FULFILLED, got " <> show other)
      -- The RECORD fired exactly once (top-level: anonymous "" own ledger).
      let store = res.ledger
      cellsOf (store.ownLedgers Map.! "") `shouldBe` [["pre"]]

  describe "(d) D5: a RECORD step before a downstream breach survives" $ do
    it "the chain BREACHES, and the pre-step Assign is still in Alice's own ledger" $ do
      [res] <- runDirectives d5Src
      case res.result of
        Reduction (Right nf) -> isBreachedNF nf `shouldBe` True
        other               -> expectationFailure ("expected a ValBreached reduction, got " <> show other)
      let store = res.ledger
      Map.keys store.ownLedgers `shouldBe` ["Alice"]
      cellsOf (store.ownLedgers Map.! "Alice") `shouldBe` [["delivery recorded"]]
      -- nothing was committed to the official record on this failed run.
      cellsOf store.officialLedger `shouldBe` []

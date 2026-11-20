{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
-- | smucclaw/l4-ide#1075: the machine's counted budgets, which stop a
-- directive that opens obligations without end or applies functions without
-- end, and the opt-in time and allocation limits on one directive. A stop
-- is that directive's result; the next directive still runs.
--
-- The limits below are set small, through 'EvalConfig', so that each case
-- runs in well under a second. The defaults are 'maximumOpenObligations' and
-- 'maximumClosureApplications'.
module BudgetSpec (spec) where

import qualified Data.Text as Text
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import System.Timeout (timeout)
import Test.Hspec

import L4.API.VirtualFS (checkWithImports, vfsFromList)
import L4.EvaluateLazy
import L4.EvaluateLazy.Exceptions (Budget (..), EvalException (..), UserEvalException (..))
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import L4.TracePolicy (apiDefaultPolicy)

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

-- | What a directive came to, reduced to what these cases compare.
data Outcome
  = Over Text.Text Int (Maybe Int)   -- ^ the budget, its limit, and the line of its site
  | Answered
  | OtherError Text.Text
  deriving stock (Eq, Show)

runWith :: (EvalConfig -> EvalConfig) -> Text.Text -> IO [Outcome]
runWith tweak src = do
  r <- case checkWithImports (vfsFromList []) src of
    Left errs -> fail ("typecheck failed: " <> show errs)
    Right r   -> pure r
  cfg <- tweak <$> resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  -- every case ends well inside this; a limit that never fired would hang
  mres <- timeout 60_000_000 (execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule)
  case mres of
    Nothing           -> fail "the module did not finish within 60 s: a limit did not fire"
    Just (_, results) -> pure (map (outcome . (.result)) results)
  where
    outcome = \ case
      Reduction (ReducedErrored e) -> errored e
      Assertion (Errored e)        -> errored e
      _                            -> Answered
    errored = \ case
      UserEvalException (OverBudget b) -> budget b
      e -> OtherError (Text.unlines (prettyEvalException e))
    budget = \ case
      OpenObligations n site     -> Over "obligations" n (lineOf site)
      ClosureApplications n site -> Over "applications" n (lineOf site)
      TimeLimit n                -> Over "time" n Nothing
      MemoryLimit n              -> Over "memory" n Nothing
    lineOf = fmap (\ s -> s.start.line)

limits :: Maybe Int -> Maybe Int -> EvalConfig -> EvalConfig
limits open applied cfg = cfg {maxOpenObligations = open, maxClosureApplications = applied}

-- | #1075's rule: each LEST hands on to two obligations, one of which leads
-- back, so what is open doubles every two time units.
runaway :: Int -> Text.Text
runaway t = Text.unlines
  [ "DECLARE Person IS ONE OF Alice, Bob, Carol"
  , "DECLARE Action IS ONE OF deliver, smoke"
  , ""
  , "w1 MEANS PARTY Carol MUST deliver WITHIN 2 LEST (w3 ROR w1)"
  , "w3 MEANS PARTY Alice MAY smoke WITHIN 2 LEST (w1 RAND w3)"
  , ""
  , "#TRACE w1 AT 0 WITH"
  , "  (`WAIT UNTIL` " <> tshow t <> ")"
  , ""
  , "#EVAL 1 PLUS 1"
  ]

tshow :: Show a => a -> Text.Text
tshow = Text.pack . show

-- | A module of rules over one party type and three actions, then one #TRACE.
deontic :: [Text.Text] -> Text.Text -> [Text.Text] -> Text.Text
deontic rules start events = Text.unlines $
  [ "DECLARE Person IS ONE OF Alice, Bob"
  , "DECLARE Action IS ONE OF deliver, pay, smoke"
  , "" ]
  <> rules
  <> [ "", "#TRACE " <> start <> " AT 0 WITH" ]
  <> map ("  " <>) events

spec :: Spec
spec = describe "the machine's budgets (smucclaw/l4-ide#1075)" $ do
  describe "obligations open at once" $ do
    it "stops #1075's rule at the limit, names the rule, and still answers the next directive" $
      -- the arming that goes over is w3's, on line 5
      runWith (limits (Just 1000) Nothing) (runaway 60)
        `shouldReturn` [Over "obligations" 1000 (Just 5), Answered]

    it "lets #1075's rule run where it opens fewer than the default limit" $
      runWith id (runaway 22) `shouldReturn` [Answered, Answered]

    -- The counter is armings less closes. A close it missed would make the
    -- count grow with the trace, so each chain below runs under a limit of
    -- what it holds open at once, over a long trace: a missed close stops
    -- it within two periods.
    it "counts one open for a rent rule that re-arms itself, however long its trace" $
      runWith (limits (Just 1) Nothing)
        (deontic ["rent MEANS PARTY Alice MUST deliver WITHIN 30 HENCE rent"] "rent"
          ["PARTY Alice DOES deliver AT " <> tshow (20 * k) | k <- [1 .. 2000 :: Int]])
        `shouldReturn` [Answered]

    it "counts one open for a LEST chain that re-arms itself on every missed window" $
      runWith (limits (Just 1) Nothing)
        (deontic ["late MEANS PARTY Alice MUST deliver WITHIN 1 LEST late"] "late"
          ["PARTY Alice DOES deliver AT 1000"])
        `shouldReturn` [Answered]

    it "counts one open for a MUST NOT kept window after window" $
      runWith (limits (Just 1) Nothing)
        (deontic ["quiet MEANS PARTY Alice MUST NOT smoke WITHIN 10 HENCE quiet"] "quiet"
          ["(`WAIT UNTIL` 1000)"])
        `shouldReturn` [Answered]

    it "counts a breach with no LEST as closed" $
      -- Bob's side breaches with no LEST every period, and Alice's hands on
      -- to the next (measured: peak 3 at 5, 50 and 500 periods)
      runWith (limits (Just 3) Nothing)
        (deontic
          ["period MEANS (PARTY Bob MUST pay WITHIN 5) ROR (PARTY Alice MUST deliver WITHIN 5 HENCE period)"]
          "period"
          ["PARTY Alice DOES deliver AT " <> tshow (3 * k) | k <- [1 .. 500 :: Int]])
        `shouldReturn` [Answered]

    it "counts both operands of a RAND run in step, and no more" $
      runWith (limits (Just 2) Nothing)
        (deontic
          [ "rentA MEANS PARTY Alice MUST deliver WITHIN 30 HENCE rentA"
          , "rentB MEANS PARTY Bob MUST pay WITHIN 30 HENCE rentB"
          , "both MEANS rentA RAND rentB" ]
          "both"
          (concat [ ["PARTY Alice DOES deliver AT " <> tshow (20 * k), "PARTY Bob DOES pay AT " <> tshow (20 * k)]
                  | k <- [1 .. 1000 :: Int] ]))
        `shouldReturn` [Answered]

  describe "a residual thrown away is no longer open" $ do
    -- Note [What the open count counts]. Each shape below throws away an
    -- obligation that is still waiting, once a round, and runs for 1,000
    -- rounds under a limit of 10. Before the machine closed what it threw
    -- away, each one stopped at the limit within ten rounds.
    let rounds = [1 .. 1000 :: Int]
        waitUntil t = "  (`WAIT UNTIL` " <> tshow t <> ")"
        ticking rule = Text.unlines
          [ "DECLARE Person IS ONE OF Alice, Bob, Carol"
          , "DECLARE Action IS ONE OF never, tick"
          , ""
          , rule
          , ""
          , "#TRACE x AT 0 WITH"
          , waitUntil (1000 :: Int)
          ]
        tenants rule events = Text.unlines $
          [ "DECLARE Actor IS ONE OF Tenant HAS name IS A STRING"
          , "DECLARE Action IS ONE OF Sign HAS signer IS AN Actor"
          , "alice MEANS Tenant OF \"Alice\""
          , "bob MEANS Tenant OF \"Bob\""
          , "carol MEANS Tenant OF \"Carol\""
          , "pair MEANS LIST alice, carol"
          , "trio MEANS LIST alice, bob, carol"
          , "GIVEN t IS AN Actor GIVETH A NUMBER"
          , "allowed t MEANS IF t EQUALS carol THEN 5 ELSE 1000000"
          , ""
          , rule
          , ""
          , "#TRACE r AT 0 WITH"
          ] <> events
    it "closes the waiting side of an RAND breached on its left" $
      runWith (limits (Just 10) Nothing)
        (ticking "x MEANS ((PARTY Alice MUST never WITHIN 1) RAND (PARTY Bob MUST never)) ROR (PARTY Carol MUST tick WITHIN 1 LEST x)")
        `shouldReturn` [Answered]

    it "closes the waiting side of an RAND breached on its right" $
      runWith (limits (Just 10) Nothing)
        (ticking "x MEANS ((PARTY Bob MUST never) RAND (PARTY Alice MUST never WITHIN 1)) ROR (PARTY Carol MUST tick WITHIN 1 LEST x)")
        `shouldReturn` [Answered]

    it "closes the waiting side of an ROR fulfilled on its right" $
      -- Bob's MUST NOT is kept at once, so the inner ROR is fulfilled while
      -- his MUST still waits
      runWith (limits (Just 10) Nothing)
        (ticking "x MEANS (((PARTY Bob MUST never) ROR (PARTY Bob MUST NOT never WITHIN 0)) RAND (PARTY Alice MUST never WITHIN 0)) ROR (PARTY Carol MUST tick WITHIN 1 LEST x)")
        `shouldReturn` [Answered]

    it "closes the members still waiting when a barrier fails and goes to its LEST" $
      runWith (limits (Just 10) Nothing)
        (tenants "r MEANS EVERY Tenant t IN pair MUST Sign t WITHIN allowed t ONCE ALL HAVE HENCE FULFILLED LEST r"
          [ waitUntil (6 * k) | k <- rounds ])
        `shouldReturn` [Answered]

    it "closes the members still waiting when a barrier with no LEST fails" $
      runWith (limits (Just 10) Nothing)
        (tenants "r MEANS (EVERY Tenant t IN pair MUST Sign t WITHIN allowed t ONCE ALL HAVE HENCE FULFILLED) ROR (PARTY bob MUST Sign bob WITHIN 6 LEST r)"
          [ waitUntil (6000 :: Int) ])
        `shouldReturn` [Answered]

    it "closes the members still waiting when a MAY member lapses" $
      runWith (limits (Just 10) Nothing)
        (tenants "r MEANS ((EVERY Tenant t IN pair MAY Sign t WITHIN allowed t ONCE ALL HAVE HENCE FULFILLED) RAND (PARTY bob MUST Sign bob WITHIN 0)) ROR (PARTY bob MUST Sign bob WITHIN 6 LEST r)"
          [ waitUntil (6000 :: Int) ])
        `shouldReturn` [Answered]

    it "closes the members still waiting when one member breaks a MUST NOT barrier" $
      runWith (limits (Just 10) Nothing)
        (tenants "r MEANS EVERY Tenant t IN trio SHANT Sign t WITHIN 1000000 ONCE ALL HAVE HENCE FULFILLED LEST r"
          [ "  PARTY alice DOES Sign alice AT " <> tshow k | k <- rounds ])
        `shouldReturn` [Answered]

    it "still stops an ROR that doubles what it keeps waiting" $
      -- an ROR runs its left operand to the end of the events before its
      -- right one, so one or two obligations meet events at any moment while
      -- the waiting residuals double: what it keeps is what is counted
      runWith (limits (Just 1000) Nothing)
        (ticking "x MEANS (PARTY Bob MUST never) ROR (PARTY Carol MUST tick WITHIN 1 LEST (x ROR x))")
        `shouldReturn` [Over "obligations" 1000 (Just 4)]

  describe "function applications" $ do
    let loop = Text.unlines
          [ "GIVEN n IS A NUMBER GIVETH A NUMBER"
          , "f n MEANS f (n PLUS 1)"
          , ""
          , "#EVAL f 0"
          , ""
          , "#EVAL 1 PLUS 1"
          ]
        countdown = Text.unlines
          [ "GIVEN n IS A NUMBER GIVETH A NUMBER"
          , "total n MEANS IF n EQUALS 0 THEN 0 ELSE n PLUS total (n MINUS 1)"
          , ""
          , "#EVAL total 6000"
          , ""
          , "#EVAL total 6000"
          ]
    it "stops a function that calls itself with new inputs, names it, and still answers the next directive" $
      runWith (limits Nothing (Just 10000)) loop
        `shouldReturn` [Over "applications" 10000 (Just 2), Answered]

    it "counts each directive afresh" $
      -- 6,001 applications each, under a limit of 10,000: together they
      -- would be over it
      runWith (limits Nothing (Just 10000)) countdown `shouldReturn` [Answered, Answered]

  describe "the opt-in limits on one directive" $ do
    -- reads n on every call, so it holds no more memory as it runs
    let loop = Text.unlines
          [ "GIVEN n IS A NUMBER GIVETH A NUMBER"
          , "f n MEANS IF n EQUALS 0 THEN 0 ELSE f (n MINUS 2)"
          , ""
          , "#EVAL f 5"
          , ""
          , "#EVAL 1 PLUS 1"
          ]
    it "stops a directive past its wall-clock limit and still answers the next one" $
      runWith (\ c -> (limits Nothing Nothing c) {directiveSeconds = Just 1}) loop
        `shouldReturn` [Over "time" 1 Nothing, Answered]

    it "stops a directive past its allocation limit and still answers the next one" $
      runWith (\ c -> (limits Nothing Nothing c) {directiveMegabytes = Just 50}) loop
        `shouldReturn` [Over "memory" 50 Nothing, Answered]

    it "measures from the start of each directive, so generous limits stop nothing" $
      -- the clock and the allocation counter are read from the directive's
      -- start: measured from anywhere earlier, the first reading would stop it
      runWith (\ c -> c {directiveSeconds = Just 3600, directiveMegabytes = Just 100000})
        (Text.unlines
          [ "GIVEN n IS A NUMBER GIVETH A NUMBER"
          , "total n MEANS IF n EQUALS 0 THEN 0 ELSE n PLUS total (n MINUS 1)"
          , ""
          , "#EVAL total 20000"
          , ""
          , "#EVAL total 20000"
          ])
        `shouldReturn` [Answered, Answered]

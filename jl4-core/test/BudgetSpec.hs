{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
-- | smucclaw/l4-ide#1075: the machine's counted budgets, which stop a
-- directive that opens obligations without end or applies functions without
-- end, and the opt-in time and allocation limits. A counted stop is that
-- directive's result, and the next directive still runs; a time or memory
-- stop ends the run, and the directives after it are not evaluated (ruling
-- L2 of the Recursion Limits bench).
--
-- The counts below are set small, through 'EvalConfig', so that each case
-- under one runs in well under a second; a case under the time limit takes
-- the second that limit allows. The shared configuration sets none;
-- 'withCountedBudgets' sets 'maximumOpenObligations' and
-- 'maximumClosureApplications', which every @l4@ command that evaluates,
-- the REPL and the editor evaluate under.
module BudgetSpec (spec) where

import Data.Maybe (isJust)
import qualified Data.Text as Text
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import System.Timeout (timeout)
import Test.Hspec

import L4.API.VirtualFS (checkWithImports, vfsFromList)
import L4.EvaluateLazy
import L4.EvaluateLazy.Exceptions (Budget (..), BudgetSite (..), EvalException (..), UserEvalException (..), maximumClosureApplications, maximumOpenObligations)
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.TracePolicy (apiDefaultPolicy, fullTracePolicy, replDefaultPolicy)

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

-- | What a directive came to, reduced to what these cases compare.
data Outcome
  = Over Text.Text Int (Maybe Int)   -- ^ the budget, its limit, and the line of its site
  | NotRun Text.Text                 -- ^ not evaluated: an earlier directive stopped the run on this limit
  | Answered
  | OtherError Text.Text
  deriving stock (Eq, Show)

runWith :: (EvalConfig -> EvalConfig) -> Text.Text -> IO [Outcome]
runWith tweak src = map (outcome . (.result)) <$> resultsWith tweak src
  where
    outcome = \ case
      Reduction (ReducedErrored e) -> errored e
      Assertion (Errored e)        -> errored e
      _                            -> Answered
    errored = \ case
      UserEvalException (OverBudget b)     -> budget b
      UserEvalException (NotEvaluated b _) -> NotRun (name b)
      e -> OtherError (Text.unlines (prettyEvalException e))
    budget b = case b of
      OpenObligations n site     -> Over (name b) n (lineOf site.siteRange)
      JoinedBreaches n site      -> Over (name b) n (lineOf site.siteRange)
      ClosureApplications n site -> Over (name b) n (lineOf site.siteRange)
      TimeLimit n                -> Over (name b) n Nothing
      MemoryLimit n              -> Over (name b) n Nothing
    name = \ case
      OpenObligations {}     -> "obligations"
      JoinedBreaches {}      -> "breaches"
      ClosureApplications {} -> "steps"
      TimeLimit {}           -> "time"
      MemoryLimit {}         -> "memory"
    lineOf = fmap (\ s -> s.start.line)

-- | The name of the definition each counted stop names, for the directives
-- that went over a counted budget.
rulesNamed :: (EvalConfig -> EvalConfig) -> Text.Text -> IO [Maybe Text.Text]
rulesNamed tweak src = concatMap named <$> resultsWith tweak src
  where
    named r = case r.result of
      Reduction (ReducedErrored (UserEvalException (OverBudget b))) -> site b
      Assertion (Errored (UserEvalException (OverBudget b)))        -> site b
      _                                                             -> []
    site = \ case
      OpenObligations _ s     -> [s.siteRule]
      JoinedBreaches _ s      -> [s.siteRule]
      ClosureApplications _ s -> [s.siteRule]
      _                       -> []

resultsWith :: (EvalConfig -> EvalConfig) -> Text.Text -> IO [EvalDirectiveResult]
resultsWith tweak src = do
  r <- case checkWithImports (vfsFromList []) src of
    Left errs -> fail ("typecheck failed: " <> show errs)
    Right r   -> pure r
  cfg <- tweak <$> resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  -- every case ends well inside this; a limit that never fired would hang
  mres <- timeout 60_000_000 (execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule)
  case mres of
    Nothing           -> fail "the module did not finish within 60 s: a limit did not fire"
    Just (_, results) -> pure results

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
  , "  (WAITUNTIL " <> tshow t <> ")"
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
  -- A trace holds about 10 KB per step, so the REPL, which collected one for
  -- every line and showed none of them, ran out of memory where `l4 run` did
  -- not (measured 2026-11-21: 10.6 GB against 55 MB at 1,000,000 steps).
  describe "the REPL keeps a trace only where it shows one (decided by Claude 2026-11-21, pending Meng's review)" $ do
    let src = Text.unlines ["#EVAL 1 PLUS 1", "#EVALTRACE 1 PLUS 1"]
        traced policy = do
          r <- case checkWithImports (vfsFromList []) src of
            Left errs -> fail ("typecheck failed: " <> show errs)
            Right r   -> pure r
          cfg <- resolveEvalConfig (Just fixedNow) policy
          (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
          pure [ isJust res.trace | res <- results ]
    it "collects none for a plain line, which the REPL runs as an #EVAL, and one for a :trace line, an #EVALTRACE" $
      traced (replDefaultPolicy defaultGraphVizOptions) `shouldReturn` [False, True]
    it "a control: the policy that traces everything collects both" $
      traced (fullTracePolicy defaultGraphVizOptions) `shouldReturn` [True, True]

  describe "where they are on (ruling L2)" $ do
    it "the shared configuration sets no count, so jl4-service evaluates as it did" $ do
      cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
      safe <- resolveEvalConfigWithSafeMode (Just fixedNow) apiDefaultPolicy True
      [ (c.maxOpenObligations, c.maxClosureApplications, c.directiveSeconds, c.directiveMegabytes) | c <- [cfg, safe] ]
        `shouldBe` replicate 2 (Nothing, Nothing, Nothing, Nothing)

    it "withCountedBudgets, which every l4 command that evaluates, the REPL and the editor apply, sets both counts, and no time or memory limit" $ do
      cfg <- withCountedBudgets <$> resolveEvalConfig (Just fixedNow) apiDefaultPolicy
      (cfg.maxOpenObligations, cfg.maxClosureApplications, cfg.directiveSeconds, cfg.directiveMegabytes)
        `shouldBe` (Just maximumOpenObligations, Just maximumClosureApplications, Nothing, Nothing)

  describe "obligations open at once" $ do
    it "stops #1075's rule at the limit, names the rule, and still answers the next directive" $
      -- the arming that goes over is w3's, on line 5
      runWith (limits (Just 1000) Nothing) (runaway 60)
        `shouldReturn` [Over "obligations" 1000 (Just 5), Answered]

    it "names the definition the obligation that went over is in" $
      rulesNamed (limits (Just 1000) Nothing) (runaway 60) `shouldReturn` [Just "w3"]

    it "lets #1075's rule run where it opens fewer than the default limit" $
      runWith withCountedBudgets (runaway 22) `shouldReturn` [Answered, Answered]

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
          ["(WAITUNTIL 1000)"])
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
        waitUntil t = "  (WAITUNTIL " <> tshow t <> ")"
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
        `shouldReturn` [Over "steps" 10000 (Just 2), Answered]

    it "names the function" $
      rulesNamed (limits Nothing (Just 10000)) loop `shouldReturn` [Just "f"]

    it "names a function whose head carries @nlg text, without the text" $
      rulesNamed (limits Nothing (Just 10000)) (Text.unlines
        [ "GIVEN n IS A NUMBER"
        , "GIVETH A NUMBER"
        , "DECIDE countDown @nlg counting down"
        , "  IS IF n EQUALS 0 THEN 0 ELSE countDown (n - 2)"
        , ""
        , "#EVAL countDown 5"
        ]) `shouldReturn` [Just "countDown"]

    it "names a function written as clauses, whose generated body has no place" $
      rulesNamed (limits Nothing (Just 10000)) (Text.unlines
        [ "@nlg counting down %n%"
        , "GIVEN n IS A NUMBER"
        , "GIVETH A NUMBER"
        , "DECIDE countDown 0 IS 0"
        , "DECIDE countDown n IS countDown (n - 2)"
        , ""
        , "#EVAL countDown 5"
        ]) `shouldReturn` [Just "countDown"]

    it "names the function, not a field's selector, when each round reads a record field" $
      rulesNamed (limits Nothing (Just 10000)) (Text.unlines
        [ "DECLARE Box HAS count IS A NUMBER"
        , ""
        , "GIVEN b IS A Box"
        , "GIVETH A NUMBER"
        , "spin b MEANS spin (Box WITH count IS b's count PLUS 1)"
        , ""
        , "#EVAL spin (Box WITH count IS 1)"
        ]) `shouldReturn` [Just "spin"]

    it "counts each directive afresh" $
      -- 6,001 applications each, under a limit of 10,000: together they
      -- would be over it
      runWith (limits Nothing (Just 10000)) countdown `shouldReturn` [Answered, Answered]

  describe "failures joined into one breach (L2's numbers, ruled by Meng 2026-11-21: bounded by the open number)" $ do
    -- A shared BREACH joined with itself doubles its list at each level with
    -- one failure built and no obligation open, so only the join's own check
    -- stops it. d_i is on line 2i + 3. A barrier's join gathers one failure
    -- per member, and its members are all armed at once, so the open count
    -- stops it first: its check is a guard, with no case here (see
    -- 'barrierFinish').
    let doubling base n = Text.unlines $
          [ "DECLARE Actor IS ONE OF P, Q"
          , "DECLARE Action IS ONE OF x, y"
          , "" ]
          <> concat
               [ [ "GIVETH A DEONTIC Actor Action"
                 , "d" <> tshow i <> " MEANS " <> (if i == 1 then base else "d" <> tshow (i - 1) <> " RAND d" <> tshow (i - 1)) ]
               | i <- [1 .. n :: Int] ]
          <> [ "", "#TRACE d" <> tshow n <> " AT 0 WITH", "  (WAITUNTIL 5)", "", "#EVAL 1 PLUS 1" ]
        breached = "BREACH BY P BECAUSE \"late\""
    it "stops the join that would gather more failures than the limit, names its rule, and still answers the next directive" $
      -- d11 joins 512 and 512
      runWith (limits (Just 1000) Nothing) (doubling breached 12)
        `shouldReturn` [Over "breaches" 1000 (Just 25), Answered]

    it "names the definition the join is in" $
      rulesNamed (limits (Just 1000) Nothing) (doubling breached 12)
        `shouldReturn` [Just "d11"]

    it "lets a join up to the limit through" $
      -- d11 gathers 1,024, the most this module makes
      runWith (limits (Just 1024) Nothing) (doubling breached 11)
        `shouldReturn` [Answered, Answered]

    it "counts a level, not a total: a join of two each round for 1,000 rounds passes a limit of 10" $
      runWith (limits (Just 10) Nothing) (Text.unlines
        [ "DECLARE Person IS ONE OF Alice, Bob, Carol"
        , "DECLARE Action IS ONE OF never, tick"
        , ""
        , "x MEANS ((PARTY Alice MUST never WITHIN 1) RAND (PARTY Bob MUST never WITHIN 1)) ROR (PARTY Carol MUST tick WITHIN 1 LEST x)"
        , ""
        , "#TRACE x AT 0 WITH"
        , "  (WAITUNTIL 1000)" ])
        `shouldReturn` [Answered]

  describe "work: function applications and deontic hand-offs in one total (L2's numbers, ruled by Meng 2026-11-21)" $ do
    -- A shared FULFILLED joined with itself: 65,535 hand-offs at 16 levels,
    -- and one function applied in all, so the applications alone never stop it.
    let fulfilled n = Text.unlines $
          [ "DECLARE Actor IS ONE OF P, Q"
          , "DECLARE Action IS ONE OF x, y"
          , "" ]
          <> concat
               [ [ "GIVETH A DEONTIC Actor Action"
                 , "d" <> tshow i <> " MEANS " <> (if i == 1 then "FULFILLED" else "d" <> tshow (i - 1) <> " RAND d" <> tshow (i - 1)) ]
               | i <- [1 .. n :: Int] ]
          <> [ "", "#TRACE d" <> tshow n <> " AT 0 WITH", "  (WAITUNTIL 5)", "", "#EVAL 1 PLUS 1" ]
        overWork = \ case
          [Over "steps" 10_000 (Just _), Answered] -> True
          _                                                -> False
    it "stops a HENCE-free chain of hand-offs that applies no function, and still answers the next directive" $
      runWith (limits Nothing (Just 10_000)) (fulfilled 16) >>= (`shouldSatisfy` overWork)

    it "lets the same chain finish with no limit on work" $
      runWith (limits Nothing Nothing) (fulfilled 16)
        `shouldReturn` [Answered, Answered]

  describe "a stop while what is evaluated waits on an input not yet known" $ do
    -- @x@ is unknown, so the right of the AND is evaluated only in case @x@
    -- turns out TRUE; an error there is reported as needing @x@. A budget is
    -- not: it is an error on the directive, and a time or memory one still
    -- stops the run (ruling L2)
    let speculative = Text.unlines
          [ "ASSUME x IS A BOOLEAN"
          , "GIVEN n IS A NUMBER GIVETH A BOOLEAN"
          , "loop n MEANS loop (n PLUS 1)"
          , ""
          , "#EVAL x AND loop 0"
          , ""
          , "#EVAL 1 PLUS 1"
          ]
    it "reports a count's hit as the count's, not as needing the input" $
      runWith (limits Nothing (Just 10000)) speculative
        `shouldReturn` [Over "steps" 10000 (Just 3), Answered]

    it "stops the run on a memory hit" $
      runWith (\ c -> (limits Nothing Nothing c) {directiveMegabytes = Just 1}) speculative
        `shouldReturn` [Over "memory" 1 Nothing, NotRun "memory"]

  describe "the opt-in time and memory limits, which stop the run" $ do
    -- reads n on every call, so it holds no more memory as it runs
    let loop = Text.unlines
          [ "GIVEN n IS A NUMBER GIVETH A NUMBER"
          , "f n MEANS IF n EQUALS 0 THEN 0 ELSE f (n MINUS 2)"
          , ""
          , "#EVAL f 5"
          , ""
          , "#EVAL 1 PLUS 1"
          , ""
          , "#ASSERT TRUE"
          ]
        early = Text.unlines
          [ "#EVAL 1 PLUS 1"
          , ""
          , "GIVEN n IS A NUMBER GIVETH A NUMBER"
          , "f n MEANS IF n EQUALS 0 THEN 0 ELSE f (n MINUS 2)"
          , ""
          , "#EVAL f 5"
          ]
    it "stops the run at a directive past its wall-clock limit: nothing after it is evaluated" $
      runWith (\ c -> (limits Nothing Nothing c) {directiveSeconds = Just 1}) loop
        `shouldReturn` [Over "time" 1 Nothing, NotRun "time", NotRun "time"]

    it "stops the run at a directive past its allocation limit: nothing after it is evaluated" $
      runWith (\ c -> (limits Nothing Nothing c) {directiveMegabytes = Just 50}) loop
        `shouldReturn` [Over "memory" 50 Nothing, NotRun "memory", NotRun "memory"]

    it "keeps what the directives before the stop answered" $
      runWith (\ c -> (limits Nothing Nothing c) {directiveSeconds = Just 1}) early
        `shouldReturn` [Answered, Over "time" 1 Nothing]

    it "lets the directives after a counted stop answer, under a time limit too" $
      -- a counted stop is not a time or memory stop, whatever else is set
      runWith (\ c -> (limits Nothing (Just 10000) c) {directiveSeconds = Just 3600})
        (Text.unlines ["GIVEN n IS A NUMBER GIVETH A NUMBER", "f n MEANS f (n PLUS 1)", "", "#EVAL f 0", "", "#EVAL 1 PLUS 1"])
        `shouldReturn` [Over "steps" 10000 (Just 2), Answered]

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

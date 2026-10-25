{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | @l4 explore@'s own mechanisms (REGULATIVE-LOWERING-SPEC.md §4, WP1), each
-- on a contract cut down to show it alone. The dinner-race fixtures and
-- their counts are pinned in @jl4/tests/LtsExplore.hs@; these are the
-- decisions those fixtures do not isolate:
--
--   1. a variable that is the whole action is enumerated from the
--      contract's action type, a constructor with a @NUMBER@ field is
--      refused BY NAME while its siblings are explored, and an act that
--      changes nothing is a self-loop;
--   2. the tick past a deadline reaches @FULFILLED@, a state with nothing
--      left to do gets one @terminal@ self-loop, and the clock bound turns
--      the tick into a count instead of an edge;
--   3. a variable that is an operand is enumerated from its constructor's
--      field type, through a record, and a constructor refused INSIDE a
--      field is named as itself, not as the record it sits in;
--   4. a cell read only by @RECALL@ keeps its latest entry, one read by
--      @RECALL ALL@ its whole history (which here never closes, so the depth
--      bound stops it, and says so); a cell nothing reads is dropped and
--      named; a cell kept by request ('keepCells') splits states it did not;
--   5. a top-level rule with no inputs that reads a ledger keeps its first
--      answer for the rest of the run, so two positions with the same
--      residual and ledger but different first answers behave differently,
--      and are two states;
--   6. the in-process checker (WP2, "L4.Lts.Explore.Check"): the verdicts
--      of each class on a contract whose only way wrong is a missed
--      deadline, so the counterexample is a tick; the printed #TRACE run
--      as source; a source replay that disagrees caught; unknown when the
--      exploration is incomplete or a cell is in two ledgers; and the
--      properties refused by name.
module LtsExploreSpec (spec) where

import qualified Data.Text as Text

import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Evaluate.Ledger (emptyStore)
import L4.EvaluateLazy (EvalDirectiveResult (..), execEvalModuleWithDeonticLog, resolveEvalConfig)
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.Lts.Explore
import L4.Lts.Explore.Check
import L4.Lts.WhatIf (Rig (..))
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import L4.TracePolicy (apiDefaultPolicy)

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

import L4.Print (prettyLayout)

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

-- | Explore the named rule from 0, with these options and kept cells.
exploreSrc :: Text.Text -> Text.Text -> ExploreOptions -> [(Text.Text, Bool)] -> IO Graph
exploreSrc src name opts keep = do
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  r <- case checkWithImports (vfsFromList []) src of
    Left errs -> fail ("typecheck failed: " <> show errs)
    Right r -> pure r
  let rig = MkRig {rigConfig = cfg, rigEntityInfo = r.tcdEntityInfo, rigEnv = emptyEnvironment, rigModule = r.tcdModule}
      sites = keepCells keep (readSitesOf r.tcdModule [])
  start <- either (fail . Text.unpack) pure (startNamed r.tcdModule name 0)
  explore opts sites rig start >>= either (fail . Text.unpack) pure

-- | Explore the named rule from 0 and check these properties on it, the
-- cells they read kept; with a source replay, or none.
checkSrc :: Text.Text -> Text.Text -> ExploreOptions -> Maybe SourceReplay -> [Request] -> IO (Graph, [CheckResult])
checkSrc src name opts msource requests = do
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  r <- case checkWithImports (vfsFromList []) src of
    Left errs -> fail ("typecheck failed: " <> show errs)
    Right r -> pure r
  let rig = MkRig {rigConfig = cfg, rigEntityInfo = r.tcdEntityInfo, rigEnv = emptyEnvironment, rigModule = r.tcdModule}
  props <- either (fail . Text.unpack) pure (traverse (resolveProperty r.tcdEntityInfo [r.tcdModule]) requests)
  let sites = keepCells (propertyCells props) (readSitesOf r.tcdModule [])
  start <- either (fail . Text.unpack) pure (startNamed r.tcdModule name 0)
  g <- explore opts sites rig start >>= either (fail . Text.unpack) pure
  (rs, _) <- checkGraph opts rig msource g props
  pure (g, rs)

-- | Resolve one property against a source, for the refusals.
resolveIn :: Text.Text -> Request -> IO (Either Text.Text ())
resolveIn src rq = case checkWithImports (vfsFromList []) src of
  Left errs -> fail ("typecheck failed: " <> show errs)
  Right r -> pure (() <$ resolveProperty r.tcdEntityInfo [r.tcdModule] rq)

-- | The source replay the CLI does, done here with no files: the trace
-- text appended to the source, the whole run, and the ledger of the one
-- directive below the source's own lines.
sourceReplayOf :: Text.Text -> SourceReplay
sourceReplayOf src trace = do
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  case checkWithImports (vfsFromList []) (src <> "\n" <> trace) of
    Left errs -> pure (Left ("did not type-check: " <> Text.pack (show errs)))
    Right r -> do
      (_, results) <- execEvalModuleWithDeonticLog cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
      let below = length (Text.lines src)
      pure case [ l | (MkEvalDirectiveResult {range = Just MkSrcRange {start = MkSrcPos {line = n}}, ledger = l}, _) <- results, n > below ] of
        [l] -> Right l
        ls -> Left ("gave " <> Text.pack (show (length ls)) <> " results below the source")

verdicts :: [CheckResult] -> [Text.Text]
verdicts = map (verdictWord . (.crVerdict))

pathOf :: CheckResult -> Maybe Path
pathOf r = case r.crVerdict of
  Violated _ mp -> mp
  Reached p -> Just p
  Unknown _ mp -> mp
  Holds _ -> Nothing

reasonOf :: CheckResult -> Text.Text
reasonOf r = case r.crVerdict of
  Violated why _ -> why
  Unknown why _ -> why
  Holds why -> why
  Reached _ -> "reached"

ask :: PropertyKind -> Text.Text -> Request
ask k n = MkRequest k n Nothing

counts :: Graph -> (Int, Int)
counts g = (g.gCoverage.cvStates, g.gCoverage.cvTransitions)

labels :: Graph -> [(Int, Text.Text, Int)]
labels g = [ (t.tnFrom, t.tnLabel, t.tnTo) | t <- g.gTransitions ]

-- 1. and 2.
machineSrc :: Text.Text
machineSrc = Text.unlines
  [ "DECLARE Who IS ONE OF W"
  , "DECLARE Move IS ONE OF"
  , "    tap HAS hard IS A BOOLEAN"
  , "    pay HAS amount IS A NUMBER"
  , "    stop"
  , ""
  , "GIVETH A DEONTIC Who Move"
  , "`machine` MEANS"
  , "    PARTY W"
  , "    MAY   act"
  , "    WITHIN 10"
  , "    HENCE CONSIDER act"
  , "          WHEN tap h THEN `machine`"
  , "          WHEN pay n THEN `machine`"
  , "          WHEN stop  THEN FULFILLED"
  ]

-- 3.
ordersSrc :: Text.Text
ordersSrc = Text.unlines
  [ "DECLARE Who IS ONE OF W"
  , "DECLARE Size IS ONE OF small, large, custom HAS width IS A NUMBER"
  , "DECLARE Order HAS size IS A Size, rush IS A BOOLEAN"
  , "DECLARE Move IS ONE OF"
  , "    place HAS order IS AN Order"
  , "    quote HAS price IS A NUMBER"
  , "    cancel"
  , ""
  , "GIVETH A DEONTIC Who Move"
  , "`a placing` MEANS PARTY W MAY place o WITHIN 10 HENCE FULFILLED"
  , ""
  , "GIVETH A DEONTIC Who Move"
  , "`a quote` MEANS PARTY W MAY quote p WITHIN 10 HENCE FULFILLED"
  ]

-- 4. The guard reads `light` by RECALL (or RECALL ALL); `log` is only
--    ever written.
switchSrc :: Text.Text -> Text.Text -> Text.Text
switchSrc recall inputType = Text.unlines
  [ "DECLARE Who IS ONE OF W"
  , "DECLARE Move IS ONE OF flip, flop"
  , ""
  , "GIVEN light IS " <> inputType
  , "GIVETH A BOOLEAN"
  , "`ready` MEANS TRUE"
  , ""
  , "GIVETH A DEONTIC Who Move"
  , "`switch` MEANS"
  , "    PARTY W"
  , "    MAY   act PROVIDED `ready` (" <> recall <> " W's `light`)"
  , "    WITHIN 0 OF 10"
  , "    HENCE CONSIDER act"
  , "          WHEN flip THEN RECORD `light` IS TRUE  HENCE RECORD `log` IS 1 HENCE `switch`"
  , "          WHEN flop THEN RECORD `light` IS FALSE HENCE `switch`"
  ]

-- 5. `noted` is asked by peek's guard only. Asked before note's COMMIT it
--    answers NOTHING for the rest of the run and peek stays allowed; asked
--    after, it answers JUST TRUE and peek is passed over. note then peek,
--    and peek then note, reach the same residual and the same ledger.
cachedSrc :: Text.Text
cachedSrc = Text.unlines
  [ "DECLARE Who IS ONE OF W"
  , "DECLARE Move IS ONE OF note, peek"
  , ""
  , "`noted` MEANS RECALL OFFICIAL's `x`"
  , ""
  , "GIVEN m IS A Move"
  , "      n IS A MAYBE BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`allowed` MEANS"
  , "    CONSIDER m"
  , "    WHEN note THEN TRUE"
  , "    WHEN peek THEN `unnoted` n"
  , ""
  , "GIVEN n IS A MAYBE BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`unnoted` MEANS"
  , "    CONSIDER n"
  , "    WHEN NOTHING THEN TRUE"
  , "    WHEN JUST b THEN FALSE"
  , ""
  , "GIVETH A DEONTIC Who Move"
  , "`c` MEANS"
  , "    PARTY W"
  , "    MAY   act PROVIDED `allowed` act `noted`"
  , "    WITHIN 0 OF 10"
  , "    HENCE CONSIDER act"
  , "          WHEN note THEN COMMIT `x` IS TRUE HENCE `c`"
  , "          WHEN peek THEN `c`"
  ]

-- 6. `go` is owed by 10; missing it COMMITs `missed`. The properties read
--    `missed` as its latest entry.
lateSrc :: Text.Text -> Text.Text
lateSrc onGo = Text.unlines
  [ "DECLARE Who IS ONE OF W"
  , "DECLARE Move IS ONE OF go"
  , ""
  , "GIVEN missed IS A MAYBE BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`nothing missed` MEANS"
  , "    CONSIDER missed"
  , "    WHEN NOTHING THEN TRUE"
  , "    WHEN JUST b THEN FALSE"
  , ""
  , "GIVEN missed IS A MAYBE BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`something missed` MEANS NOT (`nothing missed` missed)"
  , ""
  , "GIVEN missed IS A MAYBE BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`missed falsely` MEANS"
  , "    CONSIDER missed"
  , "    WHEN NOTHING THEN FALSE"
  , "    WHEN JUST b THEN NOT b"
  , ""
  , "GIVEN missed IS A MAYBE BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`never missed falsely` MEANS NOT (`missed falsely` missed)"
  , ""
  , "GIVEN missed IS A MAYBE BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`reads itself` MEANS"
  , "    CONSIDER (RECALL OFFICIAL's `missed`)"
  , "    WHEN NOTHING THEN TRUE"
  , "    WHEN JUST b THEN FALSE"
  , ""
  , "GIVEN missed IS A MAYBE BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`reads through another` MEANS `reads itself` missed"
  , ""
  , "GIVETH A BOOLEAN"
  , "`no inputs` MEANS TRUE"
  , ""
  , "GIVEN m IS A Move"
  , "GIVETH A BOOLEAN"
  , "`a move` MEANS TRUE"
  , ""
  , "GIVEN missed IS A MAYBE BOOLEAN"
  , "GIVETH A NUMBER"
  , "`a number` MEANS 1"
  , ""
  , "GIVETH A DEONTIC Who Move"
  , "`late` MEANS"
  , "    PARTY W"
  , "    MUST  go"
  , "    WITHIN 10"
  , "    HENCE " <> onGo
  , "    LEST  COMMIT `missed` IS TRUE HENCE FULFILLED"
  ]

spec :: Spec
spec = describe "l4 explore" do
  describe "1. a whole-action variable is enumerated; a NUMBER constructor is refused by name" do
    it "explores tap TRUE, tap FALSE and stop, refuses pay naming its field, and is not complete" do
      g <- exploreSrc machineSrc "machine" defaultExploreOptions []
      counts g `shouldBe` (2, 5)
      labels g `shouldBe`
        [ (0, "PARTY W DOES tap OF TRUE", 0)
        , (0, "PARTY W DOES tap OF FALSE", 0)
        , (0, "PARTY W DOES stop", 1)
        , (0, "time passes the deadline 10 (WAIT UNTIL 11)", 1)
        , (1, "terminal", 1)
        ]
      case g.gCoverage.cvRefused of
        [r] -> do
          (r.rfVariable, r.rfType, r.rfWhole, r.rfConstructor) `shouldBe` ("act", "Move", True, Just "pay")
          r.rfReason `shouldBe` "its field `amount` is a NUMBER, and a NUMBER has no finite set of values"
        other -> expectationFailure ("expected one refusal, got " <> show other)
      coverageComplete g.gCoverage `shouldBe` False
      coverageLine g.gCoverage `shouldSatisfy` Text.isInfixOf "REFUSED 1: `act` of type Move, constructor `pay`"

  describe "2. ticks, terminal states and the clock bound" do
    it "the FULFILLED state is terminal, with one self-loop, and is marked so" do
      g <- exploreSrc machineSrc "machine" defaultExploreOptions []
      [ s.snId | s <- g.gStates, s.snTerminal ] `shouldBe` [1]
      [ t | t <- g.gTransitions, t.tnKind == EdgeTerminal ] `shouldBe` [MkTransition 1 "terminal" 1 EdgeTerminal]
    it "--until 10 does not take the tick to 11, counts it, and still ends at FULFILLED by stop" do
      g <- exploreSrc machineSrc "machine" defaultExploreOptions {eoUntil = Just 10} []
      counts g `shouldBe` (2, 4)
      g.gCoverage.cvBeyondClock `shouldBe` 1
      [ t | t <- g.gTransitions, t.tnKind == EdgeTick ] `shouldBe` []

  describe "3. an operand variable is enumerated from its field type" do
    it "lists the four Orders whose size is not custom, and names custom as the constructor refused" do
      g <- exploreSrc ordersSrc "a placing" defaultExploreOptions []
      counts g `shouldBe` (2, 6)
      [ l | (_, l, _) <- labels g, "place" `Text.isInfixOf` l ] `shouldBe`
        [ "PARTY W DOES place OF (Order OF small, TRUE)"
        , "PARTY W DOES place OF (Order OF small, FALSE)"
        , "PARTY W DOES place OF (Order OF large, TRUE)"
        , "PARTY W DOES place OF (Order OF large, FALSE)"
        ]
      case g.gCoverage.cvRefused of
        [r] -> do
          (r.rfVariable, r.rfType, r.rfWhole, r.rfConstructor) `shouldBe` ("o", "Order", False, Just "custom")
          r.rfReason `shouldBe` "it sits in `size` of `Order`, and its field `width` is a NUMBER, and a NUMBER has no finite set of values"
        other -> expectationFailure ("expected one refusal, got " <> show other)
    it "refuses an operand that is itself a NUMBER, naming the action's constructor, and explores nothing in its place" do
      g <- exploreSrc ordersSrc "a quote" defaultExploreOptions []
      [ l | (_, l, _) <- labels g, "quote" `Text.isInfixOf` l ] `shouldBe` []
      case g.gCoverage.cvRefused of
        [r] -> (r.rfVariable, r.rfType, r.rfWhole, r.rfConstructor) `shouldBe` ("p", "NUMBER", False, Just "quote")
        other -> expectationFailure ("expected one refusal, got " <> show other)

  describe "4. the ledger in the state" do
    it "a cell read by RECALL keeps its latest entry: three positions and their FULFILLED twins; the write-only cell is named" do
      g <- exploreSrc (switchSrc "RECALL" "A MAYBE BOOLEAN") "switch" defaultExploreOptions []
      counts g `shouldBe` (6, 12)
      coverageComplete g.gCoverage `shouldBe` True
      g.gCoverage.cvDropped `shouldBe` [("W", "log")]
      [ (c.lcCell, c.lcKeep, c.lcValues) | s <- take 3 g.gStates, c <- s.snLedger ] `shouldBe`
        [ ("light", KeptLatest, ["TRUE"]), ("light", KeptLatest, ["FALSE"]) ]
    it "a cell read by RECALL ALL keeps its whole history, which never closes here: the depth bound stops it and says so" do
      g <- exploreSrc (switchSrc "RECALL ALL" "A LIST OF BOOLEAN") "switch" defaultExploreOptions {eoMaxDepth = 3} []
      -- depth 3 holds 12 states: 8 still switching, which the bound cut,
      -- and 4 FULFILLED ones, which have nothing to cut and are terminal
      g.gCoverage.cvStops `shouldBe` [StopDepth 3 8]
      length [ () | s <- g.gStates, s.snDepth == 3, s.snTerminal ] `shouldBe` 4
      coverageComplete g.gCoverage `shouldBe` False
      coverageLine g.gCoverage `shouldSatisfy` Text.isInfixOf "frontier NOT exhausted: 8 states at the depth bound 3 not expanded"
    it "a cell kept by request is no longer dropped, and splits the states it tells apart" do
      g <- exploreSrc (switchSrc "RECALL" "A MAYBE BOOLEAN") "switch" defaultExploreOptions [("log", False)]
      counts g `shouldBe` (8, 16)
      g.gCoverage.cvDropped `shouldBe` []

  describe "5. a ledger-reading rule with no inputs keeps its first answer, and the state keeps it too" do
    it "note-then-peek and peek-then-note reach one residual and one ledger, and are two states" do
      g <- exploreSrc cachedSrc "c" defaultExploreOptions {eoUntil = Just 10} []
      -- s0 the outset; s1 note (never asked); s2 peek (NOTHING); s3 peek
      -- then note (NOTHING). From s1 peek is passed over, from s3 it is
      -- taken: merged, they would be one state with two behaviours
      counts g `shouldBe` (4, 7)
      g.gCoverage.cvPassedOver `shouldBe` 1
      length [ () | s <- g.gStates, [ c.lcValues | c <- s.snLedger ] == [["TRUE"]] ] `shouldBe` 2

  describe "6. the in-process checker" do
    let late = lateSrc "FULFILLED"
    it "answers each class: the counterexample is the tick past the deadline, printed as a runnable #TRACE" do
      (g, rs) <- checkSrc late "late" defaultExploreOptions (Just (sourceReplayOf late))
        [ ask Always "nothing missed", ask Reachable "something missed", ask Reachable "missed falsely"
        , ask Stays "nothing missed", ask Always "never missed falsely", ask Eventually "something missed" ]
      counts g `shouldBe` (3, 4)
      verdicts rs `shouldBe` ["violated", "holds", "violated", "violated", "holds", "unknown"]
      [always, _, unreachable, stays, _, liveness] <- pure rs
      reasonOf unreachable `shouldBe` "no state of the 3 states explored satisfies it"
      reasonOf liveness `shouldBe` livenessUnknown
      case pathOf always of
        Nothing -> expectationFailure "no counterexample"
        Just p -> traceText g.gStart "c" p.ptEvents `shouldBe` Text.unlines
          [ "-- c", "#TRACE late AT 0 WITH", "    (`WAIT UNTIL` OF 11)" ]
      -- the step leaves the outset: its path is the tick alone
      fmap (\ p -> (p.ptState, p.ptStep, length p.ptEvents)) (pathOf stays) `shouldBe` Just (0, True, 1)
      reasonOf stays `shouldSatisfy` Text.isInfixOf "it holds at the outset, and the first event takes it away"

    it "the printed #TRACE, run as source, leaves `missed` as the replay did" do
      (g, rs) <- checkSrc late "late" defaultExploreOptions Nothing [ask Always "nothing missed"]
      [r] <- pure rs
      p <- maybe (fail "no counterexample") pure (pathOf r)
      sourceReplayOf late (traceText g.gStart "c" p.ptEvents) >>= \ case
        Left why -> expectationFailure (Text.unpack why)
        Right store -> decisionArgsText store `shouldReturn` ["JUST OF TRUE"]

    it "a source replay that disagrees with the in-process one is caught: unknown, the path kept, not printed as a counterexample" do
      (_, rs) <- checkSrc late "late" defaultExploreOptions (Just (\ _ -> pure (Right emptyStore))) [ask Always "nothing missed"]
      [r] <- pure rs
      verdicts rs `shouldBe` ["unknown"]
      reasonOf r `shouldSatisfy` Text.isInfixOf "the printed #TRACE, run as source, gives the property NOTHING where the replay gives it JUST OF TRUE"
      fmap (length . (.ptEvents)) (pathOf r) `shouldBe` Just 1

    it "holds becomes unknown when the exploration is incomplete; a violation found is still one, here at the outset" do
      (_, rs) <- checkSrc late "late" defaultExploreOptions {eoMaxDepth = 0} (Just (sourceReplayOf late))
        [ask Always "nothing missed", ask Reachable "something missed", ask Always "something missed"]
      verdicts rs `shouldBe` ["unknown", "unknown", "violated"]
      [incomplete, _, outset] <- pure rs
      reasonOf incomplete `shouldSatisfy` Text.isInfixOf "the exploration was not complete"
      fmap (length . (.ptEvents)) (pathOf outset) `shouldBe` Just 0

    it "a cell found in two ledgers across the states is not guessed between: unknown" do
      let twoLedgers = lateSrc "RECORD `missed` IS FALSE HENCE FULFILLED"
      (_, rs) <- checkSrc twoLedgers "late" defaultExploreOptions Nothing [ask Always "nothing missed"]
      [r] <- pure rs
      verdicts rs `shouldBe` ["unknown"]
      reasonOf r `shouldSatisfy` Text.isInfixOf "is in more than one ledger across the states explored (W's, OFFICIAL's)"

    it "refuses, by name, a property that could not mean the same at every state" do
      let refusal rq = resolveIn late rq >>= either pure (const (fail "not refused"))
      refusal (ask Always "reads itself") >>= (`shouldSatisfy` Text.isInfixOf "reads a ledger itself")
      refusal (ask Always "reads through another") >>= (`shouldSatisfy` Text.isInfixOf "reads a ledger itself")
      refusal (ask Always "no inputs") >>= (`shouldSatisfy` Text.isInfixOf "takes no inputs")
      refusal (ask Always "a move") >>= (`shouldSatisfy` Text.isInfixOf "the input `m` of `a move` is a Move")
      refusal (ask Always "a number") >>= (`shouldSatisfy` Text.isInfixOf "gives a NUMBER, not a BOOLEAN")
      refusal (ask Always "no such rule") >>= (`shouldSatisfy` Text.isInfixOf "no rule named `no such rule`")
      refusal (MkRequest Always "nothing missed" (Just "something missed")) >>= (`shouldSatisfy` Text.isInfixOf "is for an eventually property")
      resolveIn late (ask Always "`nothing missed`") `shouldReturn` Right ()
  where
    decisionArgsText store = do
      r <- either (fail . show) pure (checkWithImports (vfsFromList []) (lateSrc "FULFILLED"))
      d <- either (fail . Text.unpack) (pure . (.prDecision)) (resolveProperty r.tcdEntityInfo [r.tcdModule] (ask Always "nothing missed"))
      either (fail . Text.unpack) (pure . map prettyLayout) =<< decisionArgs d store

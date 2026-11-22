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
--      properties refused by name;
--   7. the cells a run keeps for its observers (§4.1, ruled 2026-10-26):
--      an input named for a cell nothing writes is listed for refusal, and
--      the cells an emitted model keeps are those of every property-shaped
--      rule that some write names;
--   8. the instants an act is tried at (smucclaw/l4-ide#1081): the graph
--      holds every position the evaluator reaches, up to the time
--      abstraction, checked against an enumeration of every act sequence at
--      every whole instant; only whole instants are tried; a cut is named
--      as untried, never "nothing untried".
module LtsExploreSpec (spec) where

import Data.List (nub, sort)
import Data.Maybe (isJust)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Control.Monad (forM)

import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Evaluate.Ledger (emptyStore)
import L4.EvaluateLazy (EvalDirectiveResult (..), execEvalModuleWithDeonticLog, resolveEvalConfig)
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.Lts.Explore
import L4.Lts.Explore.Check
import L4.Lts.WhatIf
  ( Candidate (..), CandidateKind (..), Hypothetical (..), Outcome (..), Position (..), Rig (..), Verdict (..)
  , candidatesOf, hypotheticalExpr, position, tryCandidateFrom )
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
  , "GIVEN missed IS A LIST OF BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`a list of misses` MEANS TRUE"
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

-- 6. As 'lateSrc', with no rule that RECALLs `missed`.
lateNoRecall :: Text.Text
lateNoRecall = Text.unlines
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
  , "GIVETH A DEONTIC Who Move"
  , "`late` MEANS"
  , "    PARTY W"
  , "    MUST  go"
  , "    WITHIN 10"
  , "    HENCE FULFILLED"
  , "    LEST  COMMIT `missed` IS TRUE HENCE FULFILLED"
  ]

-- | Explore `late` keeping only what the module's own RECALLs read, NOT the
-- property's cells, and check one always-property on it: what a caller of
-- the library that skipped 'propertyCells' gets.
uncheckedSrc :: Text.Text -> Text.Text -> IO (Graph, [CheckResult])
uncheckedSrc src name = do
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  r <- either (fail . show) pure (checkWithImports (vfsFromList []) src)
  let rig = MkRig {rigConfig = cfg, rigEntityInfo = r.tcdEntityInfo, rigEnv = emptyEnvironment, rigModule = r.tcdModule}
  p <- either (fail . Text.unpack) pure (resolveProperty r.tcdEntityInfo [r.tcdModule] (ask Always name))
  start <- either (fail . Text.unpack) pure (startNamed r.tcdModule "late" 0)
  g <- explore defaultExploreOptions (readSitesOf r.tcdModule []) rig start >>= either (fail . Text.unpack) pure
  (rs, _) <- checkGraph defaultExploreOptions rig Nothing g [p]
  pure (g, rs)

-- 8. Two deadlines, and an act that starts a third. Where the act falls
--    decides how the third orders against the second: `a` at 2, on the
--    default numbers, puts b's deadline (2 + 5) on top of Q's (7).
clocksSrc :: Int -> Int -> Int -> Text.Text
clocksSrc a b c = Text.unlines
  [ "DECLARE Person IS ONE OF P, Q"
  , "DECLARE Action IS ONE OF a, b, c"
  , ""
  , "GIVETH A DEONTIC Person Action"
  , "`clocks` MEANS"
  , "    (PARTY P MUST a WITHIN " <> n a
  , "       HENCE (PARTY P MUST b WITHIN " <> n b <> " HENCE FULFILLED LEST BREACH BY P)"
  , "       LEST BREACH BY P)"
  , "    RAND"
  , "    (PARTY Q MUST c WITHIN " <> n c <> " HENCE FULFILLED LEST BREACH BY Q)"
  ]
  where n = Text.pack . show

-- | A window that opens at 3 and closes at 5 (smucclaw/l4-ide#1081, X3).
windowSrc :: Text.Text
windowSrc = Text.unlines
  [ "DECLARE Person IS ONE OF Ben"
  , "DECLARE Action IS ONE OF ship"
  , ""
  , "GIVETH A DEONTIC Person Action"
  , "`deal` MEANS"
  , "    PARTY Ben"
  , "    MUST  ship"
  , "    AFTER 3"
  , "    WITHIN 2"
  , "    HENCE FULFILLED"
  , "    LEST  BREACH BY Ben"
  ]

-- | A window that opens at 3 and never closes.
openSrc :: Text.Text
openSrc = Text.unlines
  [ "DECLARE Person IS ONE OF Ben"
  , "DECLARE Action IS ONE OF ship"
  , ""
  , "GIVETH A DEONTIC Person Action"
  , "`deal` MEANS"
  , "    PARTY Ben"
  , "    MAY   ship"
  , "    AFTER 3"
  , "    HENCE FULFILLED"
  ]

-- | Two deadlines a unit apart: the tick past the first must not be a
-- fraction, and must not reveal the second.
adjacentSrc :: Text.Text
adjacentSrc = Text.unlines
  [ "DECLARE Person IS ONE OF P, Q"
  , "DECLARE Action IS ONE OF a, c"
  , ""
  , "GIVETH A DEONTIC Person Action"
  , "`adjacent` MEANS"
  , "    (PARTY P MUST a WITHIN 3 HENCE FULFILLED LEST BREACH BY P)"
  , "    RAND"
  , "    (PARTY Q MUST c WITHIN 4 HENCE FULFILLED LEST BREACH BY Q)"
  ]

-- | A deadline that is not a whole number of the contract's time unit.
halfSrc :: Text.Text
halfSrc = Text.unlines
  [ "DECLARE Person IS ONE OF P"
  , "DECLARE Action IS ONE OF a"
  , ""
  , "GIVETH A DEONTIC Person Action"
  , "`half` MEANS PARTY P MUST a WITHIN 2.5 HENCE FULFILLED LEST BREACH BY P"
  ]

-- | The review of the first pass found these. A chain: an act that starts a
-- deadline (Q, 2 days) which becomes the limit of the next act (u, which
-- starts V, 1 day), beside a fixed deadline (R at 4). `u` at 3 puts V on R,
-- and it is reachable only if `a` was done at 1 or later, so `a` at 1 is a
-- boundary no tie of `a`'s own offset names.
roomSrc :: Text.Text
roomSrc = Text.unlines
  [ "DECLARE Person IS ONE OF P, Q, R, U, V"
  , "DECLARE Action IS ONE OF a, b, r, u, v"
  , ""
  , "GIVETH A DEONTIC Person Action"
  , "`room` MEANS"
  , "        (PARTY R MUST r WITHIN 4 HENCE FULFILLED LEST BREACH BY R)"
  , "  RAND  (PARTY P MUST a WITHIN 100 HENCE (PARTY Q MUST b WITHIN 2 HENCE FULFILLED LEST BREACH BY Q) LEST BREACH BY P)"
  , "  RAND  (PARTY U MUST u WITHIN 100 HENCE (PARTY V MUST v WITHIN 1 HENCE FULFILLED LEST BREACH BY V) LEST BREACH BY U)"
  ]

-- | A deadline that is fixed in absolute time and only the successor holds
-- (an anchor on the arming of the outset): Q's is at 3, S's at 7, whichever
-- instant `a` is done at, so `a` at 3 and at 7 are boundaries.
anchoredSrc :: Text.Text
anchoredSrc = Text.unlines
  [ "DECLARE Person IS ONE OF P, Q, S"
  , "DECLARE Action IS ONE OF a, b, s"
  , ""
  , "GIVETH A DEONTIC Person Action"
  , "`anchored` MEANS"
  , "  PARTY P MUST a WITHIN 10"
  , "    HENCE (     (PARTY Q MUST b WITHIN 3 OF THE ARMING HENCE FULFILLED LEST BREACH BY Q)"
  , "           RAND (PARTY S MUST s WITHIN 7 OF THE ARMING HENCE FULFILLED LEST BREACH BY S))"
  , "    LEST BREACH BY P"
  ]

-- | Two fixed deadlines and an offset (the review's cascade): a fixed deadline
-- plus an offset is one instant, not a cascade of them.
cascadeSrc :: Int -> Text.Text
cascadeSrc k = Text.unlines
  [ "DECLARE Person IS ONE OF P, Q, R, S"
  , "DECLARE Action IS ONE OF a, b, r, s"
  , ""
  , "GIVETH A DEONTIC Person Action"
  , "`cascade` MEANS"
  , "        (PARTY R MUST r WITHIN " <> n (20 * k) <> " HENCE FULFILLED LEST BREACH BY R)"
  , "  RAND  (PARTY S MUST s WITHIN " <> n (25 * k) <> " HENCE FULFILLED LEST BREACH BY S)"
  , "  RAND  (PARTY P MUST a WITHIN 1000 HENCE (PARTY Q MUST b WITHIN " <> n (10 * k) <> " HENCE FULFILLED LEST BREACH BY Q) LEST BREACH BY P)"
  ]
  where n = Text.pack . show

-- | The rig, the read sites and the start 'exploreSrc' builds, kept.
setupSrc :: Text.Text -> Text.Text -> IO (Rig, ReadSites, Start)
setupSrc src name = do
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  r <- case checkWithImports (vfsFromList []) src of
    Left errs -> fail ("typecheck failed: " <> show errs)
    Right r -> pure r
  let rig = MkRig {rigConfig = cfg, rigEntityInfo = r.tcdEntityInfo, rigEnv = emptyEnvironment, rigModule = r.tcdModule}
  start <- either (fail . Text.unpack) pure (startNamed r.tcdModule name 0)
  pure (rig, readSitesOf r.tcdModule [], start)

-- | What the instants scheme is held to, and not the scheme itself: every
-- position the evaluator reaches in at most @depth@ events when each act the
-- contract offers is tried at EVERY whole instant from the clock to the
-- earliest live deadline (to the clock plus @horizon@ when none is live), and
-- each deadline is ticked past. It does not call 'instantsFor'. Its answer is
-- the positions' time-abstract signatures ('timeSignature') and their keys
-- ('keyText'). A position reached again under the same key is expanded once,
-- which is the explorer's own merge and not what is under test.
enumerated :: Explorer -> Int -> Integer -> IO (Set.Set Text.Text, Set.Set Text.Text)
enumerated ex depth horizon = do
  let (rig0, tr0) = rigFor ex []
  pos0 <- position rig0 tr0 >>= maybe (fail "the outset gave no position") pure
  go (0 :: Int) [([], pos0)] Set.empty Set.empty
  where
    go d frontier seen sigs
      | null frontier = pure (sigs, seen)
      | otherwise = do
          keyed <- forM frontier \ (ev, pos) -> do
            k <- keyText ex pos
            sg <- timeSignature ex pos
            pure (k, sg, ev, pos)
          let fresh = firstByKey seen keyed
              seen' = seen <> Set.fromList [ k | (k, _, _, _) <- fresh ]
              sigs' = sigs <> Set.fromList [ sg | (_, sg, _, _) <- keyed ]
          if d >= depth
            then pure (sigs', seen')
            else do
              next <- concat <$> forM fresh \ (_, _, ev, pos) -> successors ev pos
              go (d + 1) next seen' sigs'
    firstByKey _ [] = []
    firstByKey seen (x@(k, _, _, _) : xs)
      | Set.member k seen = firstByKey seen xs
      | otherwise = x : firstByKey (Set.insert k seen) xs
    successors ev pos = do
      let (rig, tr) = rigFor ex ev
          c = pos.posClock
      cands <- candidatesOf rig tr pos
      deadlines <- liveDeadlines ex pos
      let ahead = [ d | (_, Just (Right d)) <- deadlines, d >= c ]
          limit = if null ahead then c + fromInteger horizon else minimum ahead
          try cand = do
            (outcome, mpos) <- tryCandidateFrom rig tr pos cand
            pure case (outcome.ocVerdict, cand.cdHypothetical, mpos) of
              (Untried _, _, _)    -> []
              (PassedOver _, _, _) -> []
              (_, Right hyp, Just pos') | isJust pos'.posResidual -> [(ev <> [hypotheticalExpr hyp], pos')]
              _ -> []
      concat <$> forM cands \ cand -> case (cand.cdKind, cand.cdHypothetical) of
        (ActBy _, Right act@Act {}) ->
          concat <$> forM [ceiling c .. floor limit :: Integer] \ t ->
            try cand {cdHypothetical = Right act {hyAt = fromInteger t}}
        (TickPast _ _, Right (Tick _)) -> try cand
        _ -> pure []

-- | The graph's states, each replayed from its own path, as the signatures
-- and the keys 'enumerated' gives its positions.
graphViews :: Explorer -> Graph -> IO (Set.Set Text.Text, Set.Set Text.Text)
graphViews ex g = do
  views <- forM g.gStates \ s -> do
    let (rig, tr) = rigFor ex s.snPath
    pos <- position rig tr >>= maybe (fail "a state's path gave no position") pure
    (,) <$> timeSignature ex pos <*> keyText ex pos
  pure (Set.fromList (map fst views), Set.fromList (map snd views))

hasFraction :: Text.Text -> Bool
hasFraction t = or [ isDigit' a && b == '.' && isDigit' c | (a, b, c) <- zip3 s (drop 1 s) (drop 2 s) ]
  where
    s = Text.unpack t
    isDigit' ch = ch >= '0' && ch <= '9'

-- | Every text a graph shows: labels, residuals and the events of paths.
graphTexts :: Graph -> [Text.Text]
graphTexts g = [ t.tnLabel | t <- g.gTransitions ]
  <> [ s.snResidual | s <- g.gStates ]
  <> concat [ s.snEvents | s <- g.gStates ]

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
        , (0, "time passes the deadline 10 (WAITUNTIL 11)", 1)
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
          [ "-- c", "#TRACE late AT 0 WITH", "    (WAITUNTIL OF 11)" ]
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

    it "a state explored without the property's cell kept is not labelled: unknown, never a guess from the first position" do
      -- nothing RECALLs `missed` and nothing keeps it: `go` (nothing missed)
      -- and the tick (missed) reach one FULFILLED state, first by `go`, so
      -- labelled from that position the property would hold
      (g, rs) <- uncheckedSrc lateNoRecall "nothing missed"
      counts g `shouldBe` (2, 3)
      [res] <- pure rs
      verdicts rs `shouldBe` ["unknown"]
      reasonOf res `shouldSatisfy` Text.isInfixOf "the cell `missed` was not kept in the state, so positions merged"

    it "nor when the cell was kept as its latest entry and the input reads its whole history" do
      (_, rs) <- uncheckedSrc late "a list of misses"
      [res] <- pure rs
      verdicts rs `shouldBe` ["unknown"]
      reasonOf res `shouldSatisfy` Text.isInfixOf "the cell `missed` was not kept in the state whole, only its latest entry"

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

  describe "7. the cells a run keeps for its observers (§4.1)" do
    let typoSrc = lateSrc "FULFILLED" <> Text.unlines
          [ ""
          , "GIVEN misssed IS A MAYBE BOOLEAN"
          , "GIVETH A BOOLEAN"
          , "`a typo` MEANS TRUE"
          ]
        modulesOf = do
          r <- either (fail . show) pure (checkWithImports (vfsFromList []) typoSrc)
          pure (r, \ n -> either (fail . Text.unpack) pure (resolveProperty r.tcdEntityInfo [r.tcdModule] (ask Always n)))

    it "lists an input named for a cell nothing writes, once, and neither a written cell nor an exempted one" do
      (_, propOf) <- modulesOf
      typo <- propOf "a typo"
      fine <- propOf "nothing missed"
      unwrittenInputs [] [typo, fine, typo] `shouldBe` [("always `a typo`", "misssed")]
      unwrittenInputs ["misssed"] [typo, fine] `shouldBe` []
      -- an exemption lifts the cell it names and no other
      unwrittenInputs ["missed"] [typo, fine] `shouldBe` [("always `a typo`", "misssed")]

    it "keeps, for an emitted model, the written cells of every property-shaped rule, and passes over the rest" do
      (r, _) <- modulesOf
      -- `missed` is written; `misssed` is not, so it is not kept; `m` is a
      -- Move, `no inputs` has none and `reads itself` reads a ledger, so
      -- none of those is a property
      sort (nub (allPropertyCells r.tcdEntityInfo [r.tcdModule])) `shouldBe` [("missed", False), ("missed", True)]
  describe "8. the instants an act is tried at (#1081)" do
    let regions = defaultExploreOptions
        grid1 = defaultExploreOptions {eoTime = Grid 1}
        -- every position the evaluator reaches, up to the time abstraction,
        -- is in the graph
        holdsEvery name src opts until' depth horizon = it name do
          (rig, sites, start) <- setupSrc src (contractOf src)
          let o = opts {eoUntil = until'}
          ex <- newExplorer o sites rig start
          g <- explore o sites rig start >>= either (fail . Text.unpack) pure
          (wantSigs, wantKeys) <- enumerated ex depth horizon
          (haveSigs, haveKeys) <- graphViews ex g
          case o.eoTime of
            Regions -> Set.toList (wantSigs `Set.difference` haveSigs) `shouldBe` []
            Grid _  -> Set.toList (wantKeys `Set.difference` haveKeys) `shouldBe` []
        contractOf src
          | "`clocks`" `Text.isInfixOf` src = "clocks"
          | "`adjacent`" `Text.isInfixOf` src = "adjacent"
          | "`half`" `Text.isInfixOf` src = "half"
          | "`room`" `Text.isInfixOf` src = "room"
          | "`anchored`" `Text.isInfixOf` src = "anchored"
          | otherwise = "deal"
        clocks = clocksSrc 3 5 7
        wide = clocksSrc 8 10 15
        -- the whole-instant pairs of the position in which the two
        -- deadlines fall together
        together g = [ s.snId | s <- g.gStates, "MUST b WITHIN 5 HENCE" `Text.isInfixOf` s.snResidual, "MUST c WITHIN 5 HENCE" `Text.isInfixOf` s.snResidual ]

    describe "regions: the graph holds every position the evaluator reaches, up to the time abstraction" do
      holdsEvery "two clocks, where the act that starts b meets Q's deadline at 2" clocks regions Nothing 3 3
      holdsEvery "two clocks with wide gaps, so the scheme does not try every instant" wide regions Nothing 2 3
      holdsEvery "a window that opens at 3 and closes at 5" windowSrc regions Nothing 2 3
      holdsEvery "a window that opens at 3 and never closes, bounded at 10" openSrc regions (Just 10) 1 10
      -- the review of the first pass (2026-11-22)
      holdsEvery "with --chains: a tie that a LATER act's offset puts in reach (u at 3 puts V on R, and only if a was done at 1 or later)" roomSrc regions {eoChains = True} Nothing 2 3
      holdsEvery "deadlines that are fixed in absolute time and that only the successor holds (OF THE ARMING)" anchoredSrc regions Nothing 2 3

    describe "a tie through a chain of acts is searched only on request, and never silently left out" do
      it "without --chains the position is left out, and the coverage line says which act and that --chains tries it" do
        g <- exploreSrc roomSrc "room" regions []
        coverageComplete g.gCoverage `shouldBe` False
        coverageLine g.gCoverage `shouldSatisfy` Text.isInfixOf "ties through chains of acts"
        coverageLine g.gCoverage `shouldSatisfy` Text.isInfixOf "--chains tries them"
      it "with --chains it is searched, and nothing is left out" do
        g <- exploreSrc roomSrc "room" regions {eoChains = True} []
        coverageComplete g.gCoverage `shouldBe` True
      it "a contract with no chain says nothing about chains" do
        g <- exploreSrc clocks "clocks" regions []
        coverageComplete g.gCoverage `shouldBe` True
        coverageLine g.gCoverage `shouldSatisfy` (not . Text.isInfixOf "chains")

    describe "the instants one act is tried at do not snowball" do
      it "two fixed deadlines and one offset: the whole graph of the review's cascade (20, 25 and 10) is small" do
        g <- exploreSrc (cascadeSrc 1) "cascade" regions []
        g.gCoverage.cvStates `shouldSatisfy` (< 200)
        coverageComplete g.gCoverage `shouldBe` True
      it "the same at ten times the size is no larger in instants, and not cut at the cap" do
        g <- exploreSrc (cascadeSrc 10) "cascade" regions []
        coverageComplete g.gCoverage `shouldBe` True
        g.gCoverage.cvInstants.isInstants `shouldSatisfy` (< 400)

    describe "--grid 1: the graph holds every position the evaluator reaches" do
      holdsEvery "two clocks" clocks grid1 Nothing 3 3
      holdsEvery "a window that opens at 3 and closes at 5" windowSrc grid1 Nothing 2 3
      holdsEvery "a window that opens at 3 and never closes, bounded at 10" openSrc grid1 (Just 10) 1 10

    describe "the position in which both deadlines fall together" do
      it "is in the graph by regions" do
        g <- exploreSrc clocks "clocks" regions []
        together g `shouldSatisfy` (not . null)
      it "is in the graph on a grid of 1" do
        g <- exploreSrc clocks "clocks" grid1 []
        together g `shouldSatisfy` (not . null)

    describe "only whole instants" do
      it "regions: no label, residual or event holds a fraction" do
        g <- exploreSrc clocks "clocks" regions []
        filter hasFraction (graphTexts g) `shouldBe` []
      it "a grid of 1: no label, residual or event holds a fraction" do
        g <- exploreSrc clocks "clocks" grid1 []
        filter hasFraction (graphTexts g) `shouldBe` []
      it "the tick past a deadline is one unit past it, even when the next deadline is one unit further" do
        g <- exploreSrc adjacentSrc "adjacent" regions []
        [ l | (_, l, _) <- labels g, "time passes" `Text.isInfixOf` l ] `shouldSatisfy` elem "time passes the deadline 3 (WAITUNTIL 4)"
        filter hasFraction (graphTexts g) `shouldBe` []

    describe "a window that opens later" do
      it "--grid 1 reaches FULFILLED by ship inside the window" do
        g <- exploreSrc windowSrc "deal" grid1 []
        [ l | (_, l, _) <- labels g ] `shouldSatisfy` elem "PARTY Ben DOES ship"
      it "regions and --grid 1 with a bound reach FULFILLED when the window never closes" do
        gr <- exploreSrc openSrc "deal" regions {eoUntil = Just 10} []
        gg <- exploreSrc openSrc "deal" grid1 {eoUntil = Just 10} []
        [ l | (_, l, _) <- labels gr ] `shouldSatisfy` elem "PARTY Ben DOES ship"
        [ l | (_, l, _) <- labels gg ] `shouldSatisfy` elem "PARTY Ben DOES ship"

    describe "what is not tried is named, never 'nothing untried'" do
      it "--grid 1 with no deadline and no bound says so and is not complete" do
        g <- exploreSrc openSrc "deal" grid1 []
        coverageComplete g.gCoverage `shouldBe` False
        coverageLine g.gCoverage `shouldSatisfy` Text.isInfixOf "no deadline and no --until"
        coverageLine g.gCoverage `shouldSatisfy` (not . Text.isInfixOf "nothing untried")
      it "a deadline that is not a whole number: the instants it needs are untried, and counted" do
        g <- exploreSrc halfSrc "half" regions []
        coverageComplete g.gCoverage `shouldBe` False
        coverageLine g.gCoverage `shouldSatisfy` Text.isInfixOf "not a whole number"
        filter hasFraction [ l | t <- g.gTransitions, let l = t.tnLabel, "DOES" `Text.isInfixOf` l ] `shouldBe` []
      it "--grid 2 on a deadline that is not a multiple of 2 says so" do
        g <- exploreSrc clocks "clocks" regions {eoTime = Grid 2} []
        coverageComplete g.gCoverage `shouldBe` False
        coverageLine g.gCoverage `shouldSatisfy` Text.isInfixOf "off the grid of 2"
      it "a cap on the instants cuts, and says how many" do
        g <- exploreSrc (clocksSrc 3 5 700) "clocks" grid1 {eoMaxInstants = 2} []
        coverageComplete g.gCoverage `shouldBe` False
        coverageLine g.gCoverage `shouldSatisfy` Text.isInfixOf "cap"
      it "a run with nothing cut says 'nothing untried' and how many instants it tried" do
        g <- exploreSrc clocks "clocks" regions []
        coverageComplete g.gCoverage `shouldBe` True
        coverageLine g.gCoverage `shouldSatisfy` Text.isInfixOf "nothing untried"
        coverageLine g.gCoverage `shouldSatisfy` Text.isInfixOf "instants:"

  where
    decisionArgsText store = do
      r <- either (fail . show) pure (checkWithImports (vfsFromList []) (lateSrc "FULFILLED"))
      d <- either (fail . Text.unpack) (pure . (.prDecision)) (resolveProperty r.tcdEntityInfo [r.tcdModule] (ask Always "nothing missed"))
      either (fail . Text.unpack) (pure . map prettyLayout) =<< decisionArgs d store

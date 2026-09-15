{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | Junction extraction for regulative @RAND@ \/ @ROR@, and the wording of the
-- @LEST@ arm.
--
-- Before junctions existed, @extractExpr@ handled the two operators with
-- identical code, so @a RAND b@ and @a ROR b@ produced byte-identical graphs.
-- These tests pin the distinction down at both ends: in the IR, and in the DOT
-- a reader actually looks at.
--
-- The @LEST@ tests are the same shape of regression one modal down: every
-- explicit @LEST@ edge used to be captioned with the literal word
-- @\"timeout\"@ whatever the modal, which on a prohibition says the opposite of
-- what the rule says (smucclaw\/l4-ide#927). Nothing asserted an edge caption
-- before, so nothing caught it.
module StateGraphSpec (spec) where

import Test.Hspec
import Data.Text (Text)
import qualified Data.Text as Text

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.EvaluateLazy (execEvalModuleWithDeonticLog, resolveEvalConfig)
import L4.EvaluateLazy.DeonticStep (DeonticStep (..), NormKey (..))
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.Import.Resolution (TypeCheckWithDepsResult(..))
import L4.Parser.SrcSpan (SrcRange)
import L4.StateGraph
import L4.StateGraph.Dot (StateGraphOptions (..), defaultStateGraphOptions, stateGraphToDot)
import L4.Syntax (DeonticModal(..))
import L4.TracePolicy (apiDefaultPolicy)

--------------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------------

-- | Declarations every fixture needs.
preamble :: [Text]
preamble =
  [ "DECLARE Person IS ONE OF Alice, Bob, Carol"
  , "DECLARE Action IS ONE OF"
  , "  pay"
  , "  deliver"
  , "  notify"
  , ""
  ]

-- | Type-check a fixture body and extract its first state graph.
graphFor :: [Text] -> Either [Text] StateGraph
graphFor body =
  case checkWithImports emptyVFS (Text.unlines (preamble <> body)) of
    Left errs -> Left errs
    Right r   -> case extractStateGraphs r.tcdModule of
      (sg:_) -> Right sg
      []     -> Left ["no state graph was extracted"]

-- | Two concurrent obligations.
randSrc :: [Text]
randSrc =
  [ "GIVETH DEONTIC Person Action"
  , "`split` MEANS"
  , "      (PARTY Alice MUST pay WITHIN 3)"
  , "  RAND (PARTY Bob MUST deliver WITHIN 5)"
  ]

-- | The same two obligations as a choice. Differs from 'randSrc' in exactly
-- one token, which is the point.
rorSrc :: [Text]
rorSrc =
  [ "GIVETH DEONTIC Person Action"
  , "`split` MEANS"
  , "      (PARTY Alice MUST pay WITHIN 3)"
  , "  ROR  (PARTY Bob MUST deliver WITHIN 5)"
  ]

-- | An associative three-way chain.
rand3Src :: [Text]
rand3Src =
  [ "GIVETH DEONTIC Person Action"
  , "`split` MEANS"
  , "      (PARTY Alice MUST pay WITHIN 3)"
  , "  RAND (PARTY Bob MUST deliver WITHIN 5)"
  , "  RAND (PARTY Carol MUST notify WITHIN 7)"
  ]

-- | A choice nested inside a conjunction: Alice pays, and separately one of
-- Bob or Carol acts.
mixedSrc :: [Text]
mixedSrc =
  [ "GIVETH DEONTIC Person Action"
  , "`split` MEANS"
  , "      (PARTY Alice MUST pay WITHIN 3)"
  , "  RAND ((PARTY Bob MUST deliver WITHIN 5) ROR (PARTY Carol MUST notify WITHIN 7))"
  ]

-- | A plain HENCE chain: no junction anywhere.
linearSrc :: [Text]
linearSrc =
  [ "GIVETH DEONTIC Person Action"
  , "`chain` MEANS"
  , "  PARTY Alice"
  , "  MUST pay"
  , "  WITHIN 3"
  , "  HENCE"
  , "    PARTY Bob"
  , "    MUST deliver"
  , "    WITHIN 5"
  ]

-- | One obligation with a deadline and an explicit @LEST@, parameterised by
-- the modal keyword. The three instances below differ in exactly that one
-- token, so any difference in the extracted graph is attributable to the modal
-- and to nothing else.
explicitLestSrc :: Text -> [Text]
explicitLestSrc modal =
  [ "GIVETH DEONTIC Person Action"
  , "`rule` MEANS"
  , "  PARTY Alice"
  , "  " <> modal <> " notify"
  , "  WITHIN 30"
  , "  LEST BREACH"
  ]

-- | The same, with no @WITHIN@ at all: there is a @LEST@ arm but no deadline
-- for it to be the expiry of.
noDeadlineLestSrc :: Text -> [Text]
noDeadlineLestSrc modal =
  [ "GIVETH DEONTIC Person Action"
  , "`rule` MEANS"
  , "  PARTY Alice"
  , "  " <> modal <> " notify"
  , "  LEST BREACH"
  ]

-- | The same, with the @LEST@ omitted, so the extractor supplies the default.
-- These two paths were already modal-aware; they are the control that says the
-- fix did not level the wording in the other direction.
defaultLestSrc :: Text -> [Text]
defaultLestSrc modal =
  [ "GIVETH DEONTIC Person Action"
  , "`rule` MEANS"
  , "  PARTY Alice"
  , "  " <> modal <> " notify"
  , "  WITHIN 30"
  ]

-- | Default @LEST@ /and/ no @WITHIN@ — the fourth cell of the two-by-two, and
-- the one that no test covered while it drove most of the churn in the
-- checked-in diagrams (@marriagecontract@, the @Spouse*@ vows,
-- @careinsicknessandhealth@, @supportinallcircumstances@).
bareSrc :: Text -> [Text]
bareSrc modal =
  [ "GIVETH DEONTIC Person Action"
  , "`rule` MEANS"
  , "  PARTY Alice"
  , "  " <> modal <> " notify"
  ]

-- | A prohibition whose @LEST@ is a reparation obligation rather than a
-- terminal: the nested-target arm of the extractor, and the one that reaches
-- the checked-in @noSmokingWithConsequences@ diagram. The inner @MUST@ then
-- supplies a genuine timeout in the same graph.
shantChainSrc :: [Text]
shantChainSrc =
  [ "GIVETH DEONTIC Person Action"
  , "`rule` MEANS"
  , "  PARTY Alice"
  , "  SHANT notify"
  , "  WITHIN 30"
  , "  LEST"
  , "    PARTY Bob"
  , "    MUST pay"
  , "    WITHIN 10"
  ]

-- | A quantified obligation under each join. They differ in exactly one line
-- — the join line — which is the point: until 2026-09-15 'extractDeonton'
-- never read @Deonton.join@, so the two extracted to the same graph and the
-- BPMN lowered from them was byte-identical.
barrierSrc, forkSrc :: [Text]
barrierSrc = quantifiedSrc "ONCE ALL HAVE"
forkSrc    = quantifiedSrc "UPON EACH"

quantifiedSrc :: Text -> [Text]
quantifiedSrc joinLine =
  [ "GIVETH DEONTIC Person Action"
  , "`group` MEANS"
  , "  EVERY p"
  , "    MUST pay"
  , "    WITHIN 3"
  , "    " <> joinLine
  , "    HENCE FULFILLED"
  , "    LEST BREACH"
  ]

-- | The join line carries a @WITHIN@ of its own, beside the act's.
bothDeadlinesSrc :: [Text]
bothDeadlinesSrc = quantifiedSrc "ONCE ALL HAVE WITHIN 30"

-- | The ONLY deadline in the rule is on the join line. The evaluator expires
-- each member on it (@memberDue@ in L4.EvaluateLazy.Machine), so the @LEST@
-- arm is reachable and must not be captioned as though nothing could take it.
joinOnlyDeadlineSrc :: [Text]
joinOnlyDeadlineSrc =
  [ "GIVETH DEONTIC Person Action"
  , "`group` MEANS"
  , "  EVERY p"
  , "    MUST pay"
  , "    ONCE ALL HAVE WITHIN 30"
  , "    HENCE FULFILLED"
  , "    LEST BREACH"
  ]

-- | A permission under each join, with a continuation that is a real
-- obligation. Under the barrier a lapsed member means the join never fires
-- and the rule ends FULFILLED with nothing following (Machine.hs, Barrier1's
-- last arm); under the fork each member carries the continuation, so a
-- lapsed member's arm goes where HENCE goes. The graph has to say so, or the
-- BPMN lowered from it draws the chair's duty to publish a resolution that
-- did not pass — measured 2026-09-15.
mayBarrierSrc, mayForkSrc :: [Text]
mayBarrierSrc = maySrc "ONCE ALL HAVE"
mayForkSrc    = maySrc "UPON EACH"

maySrc :: Text -> [Text]
maySrc joinLine =
  [ "GIVETH DEONTIC Person Action"
  , "`group` MEANS"
  , "  EVERY p"
  , "    MAY pay"
  , "    WITHIN 3"
  , "    " <> joinLine
  , "    HENCE (PARTY Bob MUST deliver WITHIN 5)"
  ]

-- | A quantified obligation with no continuation, and so no join line.
noJoinSrc :: [Text]
noJoinSrc =
  [ "GIVETH DEONTIC Person Action"
  , "`group` MEANS"
  , "  EVERY p"
  , "    MUST pay"
  , "    WITHIN 3"
  ]

-- | Two obligations and a @#TRACE@ that discharges both, so the evaluator
-- logs a step for each. The chain's shape is @DeonticStepSpec@'s first
-- fixture; what is tested here is the join between that log and this graph.
keyedSrc :: [Text]
keyedSrc =
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MUST deliver WITHIN 10"
  , "  HENCE PARTY Bob MUST pay WITHIN 10"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Alice DOES deliver AT 2"
  , "  PARTY Bob DOES pay AT 4"
  ]

-- | A rule whose @HENCE@ names another rule of the module. Until 2026-09-16
-- this drew an arrow into a dead-end state called @next@; the named rule's
-- own graph existed, but nothing connected the two.
namedHenceSrc :: [Text]
namedHenceSrc =
  [ "GIVETH DEONTIC Person Action"
  , "`the receipt` MEANS"
  , "  PARTY Bob MUST notify WITHIN 5"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "`the rent` MEANS"
  , "  PARTY Alice MUST pay WITHIN 7"
  , "  HENCE `the receipt`"
  ]

-- | Two arms into the same named rule — the @HENCE@ and the @LEST@ of two
-- different obligations. One state, two arrows in.
sharedTargetSrc :: [Text]
sharedTargetSrc =
  [ "GIVETH DEONTIC Person Action"
  , "`the receipt` MEANS"
  , "  PARTY Bob MUST notify WITHIN 5"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "`the rent` MEANS"
  , "  PARTY Alice MUST pay WITHIN 7"
  , "  HENCE `the receipt`"
  , "  LEST (PARTY Carol MUST deliver WITHIN 3 HENCE `the receipt`)"
  ]

-- | The same named rule from two branches of one @RAND@, and once more from
-- the @LEST@ of an obligation above the junction. The branches are two
-- instances; the @LEST@ is an exclusive outcome of one obligation and
-- shares with its @HENCE@, which is the junction.
twiceSrc :: [Text]
twiceSrc =
  [ "GIVETH DEONTIC Person Action"
  , "`the receipt` MEANS"
  , "  PARTY Bob MUST notify WITHIN 5"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "`the rent` MEANS"
  , "  PARTY Alice MUST pay WITHIN 7"
  , "  HENCE (`the receipt` RAND `the receipt`)"
  , "  LEST `the receipt`"
  ]

-- | Two rules that continue into each other: a loop through a named rule,
-- which no single rule's self-reference could produce.
mutualSrc :: [Text]
mutualSrc =
  [ "GIVETH DEONTIC Person Action"
  , "`ping` MEANS"
  , "  PARTY Alice MUST pay WITHIN 3"
  , "  HENCE `pong`"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "`pong` MEANS"
  , "  PARTY Bob MUST deliver WITHIN 5"
  , "  HENCE `ping`"
  ]

-- | A rule whose only outcome is its own renewal, by @LEST@. Before
-- 2026-09-16 that arm was captioned with a literal @\"timeout\"@ carrying
-- no modal, the one caption the #927 fix did not reach.
lestSelfSrc :: [Text]
lestSelfSrc =
  [ "GIVETH DEONTIC Person Action"
  , "`nag` MEANS"
  , "  PARTY Alice SHANT notify WITHIN 3"
  , "  LEST `nag`"
  ]

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- | Every regulative rule's graph, not only the first.
graphsFor :: [Text] -> Either [Text] [StateGraph]
graphsFor body =
  case checkWithImports emptyVFS (Text.unlines (preamble <> body)) of
    Left errs -> Left errs
    Right r   -> Right (extractStateGraphs r.tcdModule)

-- | The named graph.
graphNamed :: Text -> [Text] -> Either [Text] StateGraph
graphNamed nm body = do
  gs <- graphsFor body
  case [ g | g <- gs, g.sgName == nm ] of
    (g:_) -> Right g
    []    -> Left ["no state graph named " <> nm]

withGraph :: Either [Text] StateGraph -> (StateGraph -> Expectation) -> Expectation
withGraph eg k = case eg of
  Left errs -> expectationFailure ("fixture failed to check: " <> show errs)
  Right sg  -> k sg

-- | The sites the evaluator logs for a fixture's first directive, in step
-- order, and the sites the extractor puts on that fixture's obligation
-- edges.
loggedSites :: [Text] -> IO [Maybe SrcRange]
loggedSites body = do
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  case checkWithImports emptyVFS (Text.unlines (preamble <> body)) of
    Left errs -> do
      expectationFailure ("fixture failed to check: " <> show errs)
      pure []
    Right r -> do
      (_, results) <- execEvalModuleWithDeonticLog cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
      pure [ k.nkSite | (_, steps) <- take 1 results, s <- steps, Just k <- [s.dsNorm] ]
 where
  fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)


-- | Every state that is a junction, as (name, kind).
junctions :: StateGraph -> [(Text, FanKind)]
junctions sg = [ (s.stateName, s.stateFan) | s <- sg.sgStates, s.stateFan /= Linear ]

-- | Transitions leaving a given state.
outOf :: StateGraph -> StateId -> [Transition]
outOf sg sid = [ t | t <- sg.sgTransitions, t.transFrom == sid ]

-- | The name of a state by id.
nameOf :: StateGraph -> StateId -> Text
nameOf sg sid =
  case [ s.stateName | s <- sg.sgStates, s.stateId == sid ] of
    (n:_) -> n
    []    -> "<missing>"

-- | Names of the branch entry states a junction leads to.
branchNames :: StateGraph -> StateId -> [Text]
branchNames sg sid = map (nameOf sg . (.transTo)) (outOf sg sid)

dotFor :: StateGraph -> Text
dotFor = stateGraphToDot defaultStateGraphOptions

-- | The captions on a graph's LEST edges, in source order.
lestCaptions :: [Text] -> Either [Text] [Text]
lestCaptions src =
  fmap (map (.transLabel.labelAction) . lestEdges) (graphFor src)

-- | The modals those same edges carry.
lestModals :: [Text] -> Either [Text] [Maybe DeonticModal]
lestModals src =
  fmap (map (.transLabel.labelModal) . lestEdges) (graphFor src)

lestEdges :: StateGraph -> [Transition]
lestEdges sg = [ t | t <- sg.sgTransitions, t.transType == LestTransition ]

henceEdges :: StateGraph -> [Transition]
henceEdges sg = [ t | t <- sg.sgTransitions, t.transType == HenceTransition ]

-- | The quantifier carried by each HENCE edge, in source order.
quantifiers :: [Text] -> Either [Text] [Maybe Quantifier]
quantifiers src =
  fmap (map (.transLabel.labelQuantifier) . henceEdges) (graphFor src)

-- | The single HENCE edge of a one-obligation rule, or a failure naming why.
theHenceEdge :: [Text] -> (Transition -> Expectation) -> Expectation
theHenceEdge src k = case graphFor src of
  Left errs -> expectationFailure (show errs)
  Right sg -> case henceEdges sg of
    [t] -> k t
    ts  -> expectationFailure ("expected one HENCE edge, got " <> show (length ts))

--------------------------------------------------------------------------------
-- Spec
--------------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "the join line of an EVERY" $ do
    it "carries the barrier on the HENCE edge, structurally" $
      quantifiers barrierSrc
        `shouldBe` Right [Just (MkQuantifier "p" Nothing (Just (MkJoinLabel (Barrier "ALL HAVE") Nothing)))]

    it "carries the fork on the HENCE edge, structurally" $
      quantifiers forkSrc
        `shouldBe` Right [Just (MkQuantifier "p" Nothing (Just (MkJoinLabel Fork Nothing)))]

    it "gives the barrier and the fork different graphs" $ do
      length (filter id (zipWith (/=) barrierSrc forkSrc)) `shouldBe` 1
      graphFor barrierSrc `shouldNotBe` graphFor forkSrc

    it "leaves a PARTY rule's edges without a quantifier" $
      quantifiers linearSrc `shouldBe` Right [Nothing, Nothing]

    it "records an EVERY with no continuation as quantified but unjoined" $
      quantifiers noJoinSrc `shouldBe` Right [Just (MkQuantifier "p" Nothing Nothing)]

    it "keeps the join line's WITHIN apart from the act's" $
      theHenceEdge bothDeadlinesSrc \t -> do
        t.transLabel.labelDeadline `shouldBe` Just "3"
        (t.transLabel.labelQuantifier >>= (.quantJoin) >>= (.joinDeadline)) `shouldBe` Just "30"
        memberDeadline t.transLabel `shouldBe` Just "3"

    it "expires a member on the join line's WITHIN when the act has none" $
      theHenceEdge joinOnlyDeadlineSrc \t -> do
        t.transLabel.labelDeadline `shouldBe` Nothing
        memberDeadline t.transLabel `shouldBe` Just "30"

    it "sends a permission's lapse to Fulfilled under a barrier, and draws none under a fork" $ do
      -- The barrier's lapse arm is a LEST edge to the Fulfilled terminal,
      -- captioned as a lapse; the fork keeps the single-party shape, where
      -- the lapse is not drawn here and L4.Bpmn.Lower routes it where HENCE
      -- goes.
      case graphFor mayBarrierSrc of
        Left errs -> expectationFailure (show errs)
        Right sg -> case [ t | t <- lestEdges sg, t.transFrom == sg.sgInitialState ] of
          [t] -> do
            t.transLabel.labelAction `shouldBe` "lapses"
            nameOf sg t.transTo `shouldBe` "Fulfilled"
          ts -> expectationFailure ("expected one LEST edge out of the initial state, got " <> show (length ts))
      case graphFor mayForkSrc of
        Left errs -> expectationFailure (show errs)
        Right sg -> [ t | t <- lestEdges sg, t.transFrom == sg.sgInitialState ] `shouldBe` []

    -- 'noDeadlineLestSrc', below, is the control: with no WITHIN anywhere the
    -- caption IS 'noTriggerWording'. Here there is one, on the join line, and
    -- reading only the act's used to say the arm could not be taken.
    it "captions that rule's LEST arm as a timeout, not as unreachable" $
      lestCaptions joinOnlyDeadlineSrc `shouldBe` Right ["timeout"]

    describe "in the DOT a reader looks at" $ do
      let dotOf src = either (const "") dotFor (graphFor src)
      it "writes the barrier's join line under the obligation" $
        dotOf barrierSrc `shouldSatisfy` Text.isInfixOf "ONCE ALL HAVE"
      it "writes the fork's" $
        dotOf forkSrc `shouldSatisfy` Text.isInfixOf "UPON EACH"
      it "and the join line's own WITHIN" $
        dotOf bothDeadlinesSrc `shouldSatisfy` Text.isInfixOf "ONCE ALL HAVE WITHIN 30"
      it "renders the barrier and the fork to different DOT" $
        dotOf barrierSrc `shouldNotBe` dotOf forkSrc

  describe "junction extraction" $ do
    it "marks the fan point of a RAND as AllOf" $ do
      fmap junctions (graphFor randSrc) `shouldBe` Right [("initial", AllOf)]

    it "marks the fan point of a ROR as OneOf" $ do
      fmap junctions (graphFor rorSrc) `shouldBe` Right [("initial", OneOf)]

    it "gives RAND and ROR different graphs" $ do
      -- The regression this whole feature exists for: the two used to be
      -- byte-identical, so no consumer could tell a conjunction from a choice.
      let randG = graphFor randSrc
          rorG  = graphFor rorSrc
      randG `shouldSatisfy` isRight
      randG `shouldNotBe` rorG

    it "leaves an ordinary HENCE chain free of junctions" $ do
      fmap junctions (graphFor linearSrc) `shouldBe` Right []

  describe "junction shape" $ do
    it "gives the junction exactly one out-edge per branch" $ do
      case graphFor randSrc of
        Left errs -> expectationFailure (show errs)
        Right sg  -> do
          length (outOf sg sg.sgInitialState) `shouldBe` 2
          branchNames sg sg.sgInitialState
            `shouldBe` ["Alice must pay", "Bob must deliver"]

    it "makes branch edges unlabelled control flow, not obligations" $ do
      case graphFor randSrc of
        Left errs -> expectationFailure (show errs)
        Right sg  -> do
          map (.transType) (outOf sg sg.sgInitialState)
            `shouldBe` [DefaultTransition, DefaultTransition]
          map (.transLabel.labelAction) (outOf sg sg.sgInitialState)
            `shouldBe` ["", ""]

    it "flattens an associative RAND chain into one three-way junction" $ do
      case graphFor rand3Src of
        Left errs -> expectationFailure (show errs)
        Right sg  -> do
          junctions sg `shouldBe` [("initial", AllOf)]
          branchNames sg sg.sgInitialState
            `shouldBe` ["Alice must pay", "Bob must deliver", "Carol must notify"]

    it "keeps a ROR nested inside a RAND distinct from its parent" $ do
      case graphFor mixedSrc of
        Left errs -> expectationFailure (show errs)
        Right sg  -> do
          -- Outer junction first (it is the initial state), inner one second.
          map snd (junctions sg) `shouldBe` [AllOf, OneOf]
          lookup "initial" (junctions sg) `shouldBe` Just AllOf
          lookup "one of" (junctions sg) `shouldBe` Just OneOf
          branchNames sg sg.sgInitialState `shouldBe` ["Alice must pay", "one of"]

  describe "DOT rendering" $ do
    it "labels a RAND junction ALL OF and nothing else" $ do
      case fmap dotFor (graphFor randSrc) of
        Left errs -> expectationFailure (show errs)
        Right dot -> do
          dot `shouldSatisfy` Text.isInfixOf "ALL OF"
          dot `shouldNotSatisfy` Text.isInfixOf "ONE OF"

    it "labels a ROR junction ONE OF and nothing else" $ do
      case fmap dotFor (graphFor rorSrc) of
        Left errs -> expectationFailure (show errs)
        Right dot -> do
          dot `shouldSatisfy` Text.isInfixOf "ONE OF"
          dot `shouldNotSatisfy` Text.isInfixOf "ALL OF"

    it "draws junctions as diamonds" $ do
      case fmap dotFor (graphFor randSrc) of
        Left errs -> expectationFailure (show errs)
        Right dot -> dot `shouldSatisfy` Text.isInfixOf "shape=diamond"

    it "draws no diamond for a plain HENCE chain" $ do
      case fmap dotFor (graphFor linearSrc) of
        Left errs -> expectationFailure (show errs)
        Right dot -> dot `shouldNotSatisfy` Text.isInfixOf "shape=diamond"

    it "renders RAND and ROR to different DOT" $ do
      fmap dotFor (graphFor randSrc) `shouldNotBe` fmap dotFor (graphFor rorSrc)

  -- What takes the LEST arm is not the same event for every modal, so the word
  -- on that edge cannot be the same either. Ground truth is
  -- L4.EvaluateLazy.Machine (Contract5 CheckTiming / Contract10
  -- ScrutinizeActions) and the LEST table in doc/reference/regulative/README.md,
  -- which agree: MUST/DO reach it by the deadline passing, MAY by the
  -- permission going unexercised, SHANT by the prohibited act being PERFORMED.
  describe "LEST edge captions" $ do
    it "calls an obligation's LEST arm a timeout, because it is one" $
      lestCaptions (explicitLestSrc "MUST") `shouldBe` Right ["timeout"]

    it "calls a permission's LEST arm a lapse, since not exercising one is no failure" $
      lestCaptions (explicitLestSrc "MAY") `shouldBe` Right ["lapses"]

    -- The regression. This edge is taken when Alice DOES notify; for a
    -- prohibition it is the deadline passing that means compliance. Calling it
    -- a timeout told the reader the exact opposite of the rule.
    it "calls a prohibition's LEST arm a violation, never a timeout" $ do
      lestCaptions (explicitLestSrc "SHANT") `shouldBe` Right ["violation"]

    it "calls a DO's LEST arm a timeout, the same as a MUST's" $
      -- DO reaches LEST by the clock too (README's LEST table gives it its own
      -- row), and it is the one modal with no default arm to fall back on.
      lestCaptions (explicitLestSrc "DO") `shouldBe` Right ["timeout"]

    it "differs from the obligation in exactly the one token the sources do" $ do
      -- The zipWith is over the fixtures and so cannot fail from a code change;
      -- it is here to keep the LAST line honest, which can. If someone edits
      -- one fixture and not the other, the inequality below stops being
      -- attributable to the modal, and this catches that.
      let differing a b = length (filter id (zipWith (/=) a b))
      differing (explicitLestSrc "MUST") (explicitLestSrc "SHANT") `shouldBe` 1
      differing (explicitLestSrc "MUST") (explicitLestSrc "MAY") `shouldBe` 1
      length (explicitLestSrc "MUST") `shouldBe` length (explicitLestSrc "SHANT")
      lestCaptions (explicitLestSrc "MUST")
        `shouldNotBe` lestCaptions (explicitLestSrc "SHANT")
      lestCaptions (explicitLestSrc "MUST")
        `shouldNotBe` lestCaptions (explicitLestSrc "MAY")

    -- Without this a consumer holding only the LEST edge — which is what
    -- L4.Bpmn.Lower would be doing if a state ever had no HENCE edge — cannot
    -- tell a missed deadline from a breached prohibition.
    it "carries the modal on the edge, not just in the choice of word" $ do
      lestModals (explicitLestSrc "MUST") `shouldBe` Right [Just DMust]
      lestModals (explicitLestSrc "MAY") `shouldBe` Right [Just DMay]
      lestModals (explicitLestSrc "SHANT") `shouldBe` Right [Just DMustNot]

    -- The other direction of the same mistake, and the sharper half of it. A
    -- rule with no WITHIN has no timeout, so "timeout" asserts a deadline the
    -- drafter did not write; but for MUST/DO/MAY it has no LEST TRIGGER either,
    -- so "not performed" — the first attempt at this row — asserted a
    -- transition the runtime never makes. Measured with jl4:exe:l4 run:
    --
    --   PARTY Alice MUST pay LEST (PARTY Bob MUST refund WITHIN 5)
    --   #TRACE ... AT 0 WITH (`WAIT UNTIL` 1000)
    --     ==> the ORIGINAL obligation, as a residual. Bob's refund never
    --         becomes current. Adding WITHIN 30 to the same rule yields
    --         "PARTY Bob MUST refund WITHIN 5", i.e. the arm taken.
    --
    -- Machine.hs says why: Contract4's `Left Nothing` branch skips the timing
    -- step, so Contract5 — the only frame that consults `lest` on expiry —
    -- never runs. The README's LEST table agrees, defining every non-SHANT
    -- trigger as the deadline passing.
    describe "where the rule set no deadline" $ do
      it "names the absence rather than an event, for an obligation" $
        lestCaptions (noDeadlineLestSrc "MUST") `shouldBe` Right [noTriggerWording]

      it "and for a permission, whose lapse is just as temporal" $
        lestCaptions (noDeadlineLestSrc "MAY") `shouldBe` Right [noTriggerWording]

      it "and for a DO" $
        lestCaptions (noDeadlineLestSrc "DO") `shouldBe` Right [noTriggerWording]

      -- SHANT is the exception, and it is an exception on the merits: its
      -- trigger is the act, not the clock. Measured, `SHANT smoke LEST …` with
      -- no WITHIN still hands control to the LEST arm the moment Alice smokes.
      it "but still says violation for a prohibition, whose trigger is not the clock" $
        lestCaptions (noDeadlineLestSrc "SHANT") `shouldBe` Right ["violation"]

      it "claims no deadline anywhere in the DOT either" $
        case fmap dotFor (graphFor (noDeadlineLestSrc "MUST")) of
          Left errs -> expectationFailure (show errs)
          Right dot -> dot `shouldNotSatisfy` Text.isInfixOf "timeout"

    describe "the defaults, which were already modal-aware" $ do
      it "still defaults an obligation to a timeout into Breach" $
        lestCaptions (defaultLestSrc "MUST") `shouldBe` Right ["timeout"]

      it "still defaults a prohibition to a violation into Breach" $
        lestCaptions (defaultLestSrc "SHANT") `shouldBe` Right ["violation"]

      it "still draws no LEST arm at all for a bare permission" $
        lestCaptions (defaultLestSrc "MAY") `shouldBe` Right []

      -- DO is documented as requiring an explicit LEST, and the extractor used
      -- to believe the documentation and draw nothing — leaving a rule whose
      -- only drawn outcome was Fulfilled. The evaluator disagrees: measured,
      -- `PARTY Alice DO pay WITHIN 5` run to (`WAIT UNTIL` 100) yields DEONTIC
      -- BREACHED. Contract5 lumps DDo in with DMust.
      it "now draws the breach a bare DO reaches by the clock" $
        lestCaptions (defaultLestSrc "DO") `shouldBe` Right ["timeout"]

      -- Default LEST *and* no WITHIN: the cell nothing covered, and the one
      -- that re-captioned twelve of the fifteen checked-in diagrams. The old
      -- code wrote the literal "timeout" here whatever the deadline.
      it "names no trigger when the LEST was defaulted and there is no WITHIN" $ do
        lestCaptions (bareSrc "MUST") `shouldBe` Right [noTriggerWording]
        lestCaptions (bareSrc "DO") `shouldBe` Right [noTriggerWording]
        lestCaptions (bareSrc "SHANT") `shouldBe` Right ["violation"]
        lestCaptions (bareSrc "MAY") `shouldBe` Right []

    -- L4.Bpmn.Lower reads the obligation's modal off `henceOf sid <|> lestOf
    -- sid`. Before this change the second alternative always yielded Nothing,
    -- because a LEST edge carried no modal; it now yields Just, so what keeps
    -- Lower's behaviour unchanged is no longer the label but the invariant that
    -- every state with a LEST edge also has a HENCE edge — extractDeonton adds
    -- one on all five paths, including the defaulted one. That invariant was
    -- asserted nowhere. It is asserted here.
    it "gives every state with a LEST edge a HENCE edge too, so Lower still reads the modal off HENCE" $ do
      let hasBoth src = case graphFor src of
            Left errs -> Left (show errs)
            Right sg ->
              Right
                [ ( sid
                  , any (\h -> h.transFrom == sid && h.transType == HenceTransition) sg.sgTransitions
                  )
                | t <- sg.sgTransitions
                , t.transType == LestTransition
                , let sid = t.transFrom
                ]
          allBoth src = fmap (all snd) (hasBoth src)
      mapM_
        (\src -> allBoth src `shouldBe` Right True)
        [ explicitLestSrc "MUST"
        , explicitLestSrc "MAY"
        , explicitLestSrc "SHANT"
        , noDeadlineLestSrc "MUST"
        , bareSrc "MUST"
        , bareSrc "SHANT"
        , shantChainSrc
        ]

    it "keeps a prohibition's own arm apart from its reparation's" $
      -- The outer SHANT is breached by acting; the inner MUST it repairs to is
      -- breached by the clock. One graph, both words, and this is the shape
      -- that used to print "timeout" twice.
      lestCaptions shantChainSrc `shouldBe` Right ["violation", "timeout"]

  describe "LEST captions in the DOT a reader looks at" $ do
    it "draws the prohibition's word and not the obligation's" $
      case fmap dotFor (graphFor (explicitLestSrc "SHANT")) of
        Left errs -> expectationFailure (show errs)
        Right dot -> do
          dot `shouldSatisfy` Text.isInfixOf "label=violation"
          dot `shouldNotSatisfy` Text.isInfixOf "label=timeout"

    -- The caption names what became of the obligation; it is not a second
    -- restatement of it. Threading the modal through the IR must not put
    -- "SHANT violation" on an edge.
    it "does not prefix the modal onto a caption that has no party" $
      case fmap dotFor (graphFor (explicitLestSrc "SHANT")) of
        Left errs -> expectationFailure (show errs)
        Right dot -> do
          dot `shouldNotSatisfy` Text.isInfixOf "SHANT violation"
          -- and the obligation's own edge still says the whole rule
          dot `shouldSatisfy` Text.isInfixOf "Alice SHANT notify [30]"

  describe "B1: the correlation key (LTS-VISUALISER §3.4)" $ do
    it "puts the RAction's range on both arms of an obligation, and none on a branch edge" $
      withGraph (graphFor keyedSrc) \sg -> do
        let obligations = [ t | t <- sg.sgTransitions, t.transType /= DefaultTransition ]
        length obligations `shouldBe` 4
        mapM_ (\t -> t.transLabel.labelSite `shouldSatisfy` isJust') obligations
        -- The HENCE and LEST edges leaving one state share the site.
        let arms sid = [ t.transLabel.labelSite | t <- outOf sg sid ]
        arms sg.sgInitialState `shouldSatisfy` allSame
        -- and the two obligations have different sites
        [ t.transLabel.labelSite | t <- henceEdges sg ] `shouldSatisfy` distinct
      -- A junction's branch edge has no obligation behind it.
    it "leaves a junction's branch edges without a site" $
      withGraph (graphFor randSrc) \sg ->
        [ t.transLabel.labelSite | t <- outOf sg sg.sgInitialState ] `shouldBe` [Nothing, Nothing]

    it "is the SAME range the evaluator logs for the obligation (nkSite)" $ do
      -- The log's first directive is the #TRACE; its steps are Alice's
      -- delivery then Bob's payment, and each step's key carries the range
      -- of the RAction it was armed from. The graph's HENCE edges, in
      -- extraction order, are the same two obligations.
      sites <- loggedSites keyedSrc
      withGraph (graphFor keyedSrc) \sg -> do
        let drawn = [ t.transLabel.labelSite | t <- henceEdges sg ]
        length sites `shouldBe` 2
        sites `shouldBe` drawn
        -- and not by accident of both being Nothing
        mapM_ (`shouldSatisfy` isJust') sites

  describe "B2: an arm into a named rule (LTS-VISUALISER §3.4)" $ do
    it "draws the named rule's states inside the caller's graph" $
      withGraph (graphNamed "the rent" namedHenceSrc) \sg -> do
        map (.stateName) sg.sgStates `shouldBe` ["initial", "the receipt", "Fulfilled", "Breach"]
        -- Alice's HENCE lands on the receipt's state, and Bob's obligation
        -- leaves it.
        [ nameOf sg t.transTo | t <- henceEdges sg ] `shouldBe` ["the receipt", "Fulfilled"]
        map (.transLabel.labelParty) (henceEdges sg) `shouldBe` [Just "Alice", Just "Bob"]

    it "no longer mints a state called next" $
      withGraph (graphNamed "the rent" namedHenceSrc) \sg ->
        map (.stateName) sg.sgStates `shouldNotSatisfy` elem "next"

    it "gives the named rule a graph of its own as well" $
      fmap (map (.sgName)) (graphsFor namedHenceSrc) `shouldBe` Right ["the receipt", "the rent"]

    it "reuses the state when a second arm names the same rule" $
      withGraph (graphNamed "the rent" sharedTargetSrc) \sg -> do
        let receipts = [ s.stateId | s <- sg.sgStates, s.stateName == "the receipt" ]
        length receipts `shouldBe` 1
        length [ t | t <- sg.sgTransitions, t.transTo `elem` receipts ] `shouldBe` 2
        -- and Bob's obligation is extracted once, not once per arm
        length [ t | t <- henceEdges sg, t.transLabel.labelParty == Just "Bob" ] `shouldBe` 1

    it "draws a rule once per RAND branch that names it, and shares it with an exclusive arm" $
      -- The memo is scoped to the path: what a branch adds it gives back, so
      -- the second branch draws its own `the receipt`; the LEST, extracted
      -- after the HENCE and outside both branches, finds neither and draws a
      -- third. Three instances, three states; Bob's obligation three times.
      withGraph (graphNamed "the rent" twiceSrc) \sg -> do
        length [ s | s <- sg.sgStates, s.stateName == "the receipt" ] `shouldBe` 3
        length [ t | t <- henceEdges sg, t.transLabel.labelParty == Just "Bob" ] `shouldBe` 3

    it "closes a loop through another rule as a back-edge to the start" $
      withGraph (graphNamed "ping" mutualSrc) \sg -> do
        map (.stateName) sg.sgStates `shouldBe` ["initial", "pong", "Breach"]
        [ (nameOf sg t.transFrom, nameOf sg t.transTo) | t <- henceEdges sg ]
          `shouldBe` [("initial", "pong"), ("pong", "initial")]
        -- No Fulfilled at all: neither rule ever ends well, and the graph
        -- says so rather than inventing a sink.
        [ s | s <- sg.sgStates, s.stateType == TerminalFulfilled ] `shouldBe` []

    it "captions a LEST back into the rule's own name like any other LEST arm" $
      -- The old special case said "timeout" of a prohibition.
      lestCaptions lestSelfSrc `shouldBe` Right ["violation"]

  describe "the dominators annotation on the DOT (LTS-VISUALISER §1.1c)" $ do
    it "changes nothing when off" $
      withGraph (graphFor linearSrc) \sg ->
        stateGraphToDot defaultStateGraphOptions { showDominators = False } sg
          `shouldBe` dotFor sg

    it "draws the acts on every path to a terminal heavy, and says which" $
      withGraph (graphFor linearSrc) \sg -> do
        let dot = stateGraphToDot defaultStateGraphOptions { showDominators = True } sg
        dotFor sg `shouldNotSatisfy` Text.isInfixOf "penwidth"
        dot `shouldSatisfy` Text.isInfixOf "on every path to FULFILLED"
        -- Both obligations of the chain are needed to fulfil; neither
        -- timeout is needed to breach (two routes), so no edge says BREACH.
        Text.count "penwidth=3" dot `shouldBe` 2
        dot `shouldNotSatisfy` Text.isInfixOf "on every path to BREACH"

    it "names both terminals on one line when an act is on every path to both" $
      -- A permission with no LEST draws only its HENCE (the lapse route is
      -- the extractor's known gap), so Alice's edge is the only way out of
      -- the start: on every path to both endings.
      withGraph (graphFor bothWaysSrc) \sg -> do
        let dot = stateGraphToDot defaultStateGraphOptions { showDominators = True } sg
        dot `shouldSatisfy` Text.isInfixOf "on every path to FULFILLED and to BREACH"
        Text.count "penwidth=3" dot `shouldBe` 3

    it "leaves a RAND's branch edges unmarked, as the list leaves them unnamed" $
      -- Both obligations are on every path to FULFILLED and the list names
      -- exactly those two. The junction's two branch edges are on every
      -- path too, in the sequential view, but a party does not do a branch
      -- edge: the list drops them and so must the picture. Until 2026-09-16
      -- the first branch edge was drawn heavy and captioned, and the second
      -- was not.
      withGraph (graphFor randSrc) \sg -> do
        let dot = stateGraphToDot defaultStateGraphOptions { showDominators = True } sg
        Text.count "penwidth=3" dot `shouldBe` 2
        Text.count "on every path to FULFILLED" dot `shouldBe` 2
        dot `shouldNotSatisfy` Text.isInfixOf "[label=\"on every path"
        dot `shouldNotSatisfy` Text.isInfixOf "[label=\"\\non every path"

    it "does not change the unmarked edges' attributes" $
      withGraph (graphFor linearSrc) \sg -> do
        let marked = stateGraphToDot defaultStateGraphOptions { showDominators = True } sg
            timeoutEdge from =
              from <> " -> 3 [label=timeout\n           ,color=\"#dc3545\"\n           ,style=dashed];"
        -- The two timeouts dominate nothing, and their three lines are
        -- exactly the default output's: the annotation only ADDS, to the
        -- edges it marks.
        dotFor sg `shouldSatisfy` Text.isInfixOf (timeoutEdge "0")
        marked `shouldSatisfy` Text.isInfixOf (timeoutEdge "0")
        marked `shouldSatisfy` Text.isInfixOf (timeoutEdge "1")
 where
  isJust' = maybe False (const True)
  allSame xs = case xs of
    [] -> True
    (x:rest) -> all (== x) rest
  distinct xs = length xs == length (dedupe xs)
  dedupe = foldr (\x acc -> if x `elem` acc then acc else x : acc) []
  -- A chain whose first edge is the only way out of the start.
  bothWaysSrc =
    [ "GIVETH DEONTIC Person Action"
    , "`both ways` MEANS"
    , "  PARTY Alice MAY pay"
    , "  HENCE (PARTY Bob MUST deliver WITHIN 5)"
    ]

isRight :: Either a b -> Bool
isRight = either (const False) (const True)


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

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Import.Resolution (TypeCheckWithDepsResult(..))
import L4.StateGraph
import L4.Syntax (DeonticModal(..))

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

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- Spec
--------------------------------------------------------------------------------

spec :: Spec
spec = do
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

isRight :: Either a b -> Bool
isRight = either (const False) (const True)


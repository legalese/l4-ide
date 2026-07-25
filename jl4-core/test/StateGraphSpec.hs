{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | Junction extraction for regulative @RAND@ \/ @ROR@.
--
-- Before junctions existed, @extractExpr@ handled the two operators with
-- identical code, so @a RAND b@ and @a ROR b@ produced byte-identical graphs.
-- These tests pin the distinction down at both ends: in the IR, and in the DOT
-- a reader actually looks at.
module StateGraphSpec (spec) where

import Test.Hspec
import Data.Text (Text)
import qualified Data.Text as Text

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Import.Resolution (TypeCheckWithDepsResult(..))
import L4.StateGraph

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

isRight :: Either a b -> Bool
isRight = either (const False) (const True)


{-# LANGUAGE QuasiQuotes #-}

-- | Unit tests for the query plan computation.
-- Tests both the jl4-service path (buildDecisionQueryCacheFromCompiled + queryPlan)
-- and the LSP path (buildQueryPlanCache / queryPlanFromLadder).
module QueryPlanSpec (spec) where

import Test.Hspec

import qualified Data.Map.Strict as Map
import Data.String.Interpolate (i)
import Data.Text (Text)
import Control.Monad.Trans.Except (runExceptT)

import Backend.Jl4 (CompiledModule (..), precompileModule)
import qualified Backend.DecisionQueryPlan as Service
import Backend.Api (FnArguments (..), FnLiteral (..))

import qualified LSP.L4.Viz.Ladder as LadderViz
import qualified LSP.L4.Viz.QueryPlan as LspQP
import qualified LSP.L4.Viz.VizExpr as VizExpr
import qualified L4.Decision.QueryPlan as QP
import qualified Language.LSP.Protocol.Types as LSP

import L4.Syntax (RawName (..))


-- ----------------------------------------------------------------------------
-- Test L4 sources
-- ----------------------------------------------------------------------------

simpleAndL4 :: Text
simpleAndL4 = [i|
GIVEN a IS A BOOLEAN
      b IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `simple and` IF a AND b
|]

simpleOrL4 :: Text
simpleOrL4 = [i|
GIVEN a IS A BOOLEAN
      b IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `simple or` IF a OR b
|]

nestedL4 :: Text
nestedL4 = [i|
GIVEN a IS A BOOLEAN
      b IS A BOOLEAN
      c IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `nested` IF (a AND b) OR c
|]

notL4 :: Text
notL4 = [i|
GIVEN a IS A BOOLEAN
      b IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `with not` IF NOT a AND b
|]

threeWayAndL4 :: Text
threeWayAndL4 = [i|
GIVEN walks IS A BOOLEAN
      eats  IS A BOOLEAN
      drinks IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE compute_qualifies IF walks AND eats AND drinks
|]

-- | A rule that reaches a refusal through a rule of no inputs (R7).
refusingL4 :: Text
refusingL4 = [i|
GIVETH A BOOLEAN
`not modelled` MEANS REFUSE "the other conditions are not modelled"

GIVEN adult IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE eligible IF adult AND `not modelled`
|]


-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

-- | Compile L4 source and return the CompiledModule.
compile :: Text -> Text -> IO CompiledModule
compile fnName source = do
  result <- precompileModule (show fnName <> ".l4") source Map.empty (NormalName fnName)
  case result of
    Left err -> fail ("Compilation failed: " <> show err)
    Right cm -> pure cm

-- | Build a jl4-service CachedDecisionQuery from source.
serviceCache :: Text -> Text -> IO Service.CachedDecisionQuery
serviceCache fnName source = do
  cm <- compile fnName source
  result <- runExceptT $ Service.buildDecisionQueryCacheFromCompiled fnName cm source
  case result of
    Left err -> fail ("buildDecisionQueryCacheFromCompiled failed: " <> show err)
    Right c -> pure c

-- | Build an LSP CachedDecisionQuery + helpers from source.
lspCache :: Text -> Text -> IO (VizExpr.RenderAsLadderInfo, LadderViz.VizState, Map.Map Int Text)
lspCache fnName source = do
  cm <- compile fnName source
  let verDocId = LSP.VersionedTextDocumentIdentifier
        { _uri = LSP.filePathToUri (show fnName <> ".l4")
        , _version = 1
        }
      vizCfg = LadderViz.mkVizConfig verDocId cm.compiledModule Map.empty True
  case LadderViz.doVisualize cm.compiledDecide vizCfg of
    Left err -> fail ("doVisualize failed: " <> show (LadderViz.prettyPrintVizError err))
    Right (info, state) -> do
      let params = LspQP.buildParamsByUnique info
      pure (info, state, params)

-- | Run a jl4-service query plan.
svcQP :: Service.CachedDecisionQuery -> [(Text, Bool)] -> Service.QueryPlanResponse
svcQP cache bindings =
  Service.queryPlan "test" cache FnArguments
    { fnEvalBackend = Nothing
    , fnArguments = Map.fromList [(k, Just (FnLitBool v)) | (k, v) <- bindings]
    , startTime = Nothing
    , events = Nothing
    }

-- | Run an LSP query plan.
lspQP :: Text -> Map.Map Int Text -> VizExpr.RenderAsLadderInfo -> LadderViz.VizState -> [(Text, Bool)] -> QP.QueryPlanResponse
lspQP = LspQP.queryPlanFromLadder


-- ----------------------------------------------------------------------------
-- Tests
-- ----------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "jl4-service query plan" serviceTests
  describe "LSP query plan" lspTests
  describe "service and LSP paths agree" agreementTests


serviceTests :: Spec
serviceTests = do
  describe "AND" do
    it "undetermined with no bindings" do
      c <- serviceCache "simple and" simpleAndL4
      let r = svcQP c []
      r.determined `shouldBe` Nothing
      length r.stillNeeded `shouldSatisfy` (> 0)

    it "determined False on short-circuit" do
      c <- serviceCache "simple and" simpleAndL4
      let r = svcQP c [("a", False)]
      r.determined `shouldBe` Just False

    it "undetermined when one True" do
      c <- serviceCache "simple and" simpleAndL4
      let r = svcQP c [("a", True)]
      r.determined `shouldBe` Nothing

    it "determined True when all True" do
      c <- serviceCache "simple and" simpleAndL4
      let r = svcQP c [("a", True), ("b", True)]
      r.determined `shouldBe` Just True
      r.stillNeeded `shouldBe` []

  describe "OR" do
    it "determined True on short-circuit" do
      c <- serviceCache "simple or" simpleOrL4
      let r = svcQP c [("a", True)]
      r.determined `shouldBe` Just True

    it "undetermined when one False" do
      c <- serviceCache "simple or" simpleOrL4
      let r = svcQP c [("a", False)]
      r.determined `shouldBe` Nothing

    it "determined False when all False" do
      c <- serviceCache "simple or" simpleOrL4
      let r = svcQP c [("a", False), ("b", False)]
      r.determined `shouldBe` Just False

  describe "(a AND b) OR c" do
    it "determined True when c is True" do
      c <- serviceCache "nested" nestedL4
      let r = svcQP c [("c", True)]
      r.determined `shouldBe` Just True

    it "determined True when a and b are True" do
      c <- serviceCache "nested" nestedL4
      let r = svcQP c [("a", True), ("b", True)]
      r.determined `shouldBe` Just True

    it "determined False when a is False and c is False" do
      c <- serviceCache "nested" nestedL4
      let r = svcQP c [("a", False), ("c", False)]
      r.determined `shouldBe` Just False

    it "undetermined when only a is True" do
      c <- serviceCache "nested" nestedL4
      let r = svcQP c [("a", True)]
      r.determined `shouldBe` Nothing

  describe "NOT a AND b" do
    it "undetermined with no bindings" do
      c <- serviceCache "with not" notL4
      let r = svcQP c []
      r.determined `shouldBe` Nothing
      length r.stillNeeded `shouldSatisfy` (> 0)

    it "determined when both bound" do
      c <- serviceCache "with not" notL4
      let r = svcQP c [("a", False), ("b", True)]
      r.determined `shouldBe` Just True

  describe "elicitation" do
    it "returns asks when no bindings" do
      c <- serviceCache "compute_qualifies" threeWayAndL4
      let r = svcQP c []
      length r.asks `shouldSatisfy` (> 0)

    it "fewer asks when some bindings known" do
      c <- serviceCache "compute_qualifies" threeWayAndL4
      let rNone = svcQP c []
          rPartial = svcQP c [("walks", True)]
      length rPartial.asks `shouldSatisfy` (<= length rNone.asks)

  -- A refusal is reached where evaluation reaches it, and the rule that refuses
  -- is never asked: evaluation takes no answer for it.
  describe "a refusal" do
    it "is reached where evaluation reaches it, and the refusing rule is never asked" do
      c <- serviceCache "eligible" refusingL4
      let ask = svcQP c []
          refused = svcQP c [("adult", True)]
          fails = svcQP c [("adult", False)]
      map (.label) ask.stillNeeded `shouldBe` ["adult"]
      ask.refusal `shouldBe` Nothing
      refused.determined `shouldBe` Nothing
      refused.stillNeeded `shouldBe` []
      fmap (.reasons) refused.refusal `shouldBe` Just ["the other conditions are not modelled"]
      fails.determined `shouldBe` Just False
      fails.refusal `shouldBe` Nothing

    it "an answer for the rule that refuses changes nothing" do
      c <- serviceCache "eligible" refusingL4
      let r = svcQP c [("adult", True), ("not modelled", True)]
      r.determined `shouldBe` Nothing
      fmap (.reasons) r.refusal `shouldBe` Just ["the other conditions are not modelled"]


lspTests :: Spec
lspTests = do
  describe "AND" do
    it "undetermined with no bindings" do
      (info, state, params) <- lspCache "simple and" simpleAndL4
      let r = lspQP "simple and" params info state []
      r.determined `shouldBe` Nothing
      length r.stillNeeded `shouldSatisfy` (> 0)

    it "determined False on short-circuit" do
      (info, state, params) <- lspCache "simple and" simpleAndL4
      let r = lspQP "simple and" params info state [("a", False)]
      r.determined `shouldBe` Just False

    it "determined True when all True" do
      (info, state, params) <- lspCache "simple and" simpleAndL4
      let r = lspQP "simple and" params info state [("a", True), ("b", True)]
      r.determined `shouldBe` Just True
      r.stillNeeded `shouldBe` []

  describe "OR" do
    it "determined True on short-circuit" do
      (info, state, params) <- lspCache "simple or" simpleOrL4
      let r = lspQP "simple or" params info state [("a", True)]
      r.determined `shouldBe` Just True

    it "determined False when all False" do
      (info, state, params) <- lspCache "simple or" simpleOrL4
      let r = lspQP "simple or" params info state [("a", False), ("b", False)]
      r.determined `shouldBe` Just False

  -- The editor's wizard plans from the same ladder state the service does, so it
  -- reaches a refusal where evaluation does too, and never asks the rule that
  -- refuses.
  describe "a refusal" do
    it "is reached where evaluation reaches it, and the refusing rule is never asked" do
      (info, state, params) <- lspCache "eligible" refusingL4
      let ask = lspQP "eligible" params info state []
          refused = lspQP "eligible" params info state [("adult", True)]
          fails = lspQP "eligible" params info state [("adult", False)]
      map (.label) ask.stillNeeded `shouldBe` ["adult"]
      refused.determined `shouldBe` Nothing
      fmap (.reasons) refused.refusal `shouldBe` Just ["the other conditions are not modelled"]
      fails.determined `shouldBe` Just False
      fails.refusal `shouldBe` Nothing


agreementTests :: Spec
agreementTests = do
  let testAgreement name fnName source bindings = do
        it (name <> " with " <> show bindings) do
          sCache <- serviceCache fnName source
          (info, state, params) <- lspCache fnName source
          let sResp = svcQP sCache bindings
              lResp = lspQP fnName params info state bindings
          sResp.determined `shouldBe` lResp.determined
          fmap (.reasons) sResp.refusal `shouldBe` fmap (.reasons) lResp.refusal

  describe "simple AND" do
    testAgreement "no bindings" "simple and" simpleAndL4 []
    testAgreement "a=True" "simple and" simpleAndL4 [("a", True)]
    testAgreement "a=False" "simple and" simpleAndL4 [("a", False)]
    testAgreement "both True" "simple and" simpleAndL4 [("a", True), ("b", True)]

  describe "nested" do
    testAgreement "c=True" "nested" nestedL4 [("c", True)]
    testAgreement "a=False,c=False" "nested" nestedL4 [("a", False), ("c", False)]
    testAgreement "a=True" "nested" nestedL4 [("a", True)]

  describe "a refusal" do
    testAgreement "no bindings" "eligible" refusingL4 []
    testAgreement "adult=True" "eligible" refusingL4 [("adult", True)]
    testAgreement "adult=False" "eligible" refusingL4 [("adult", False)]

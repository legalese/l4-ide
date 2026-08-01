{-# LANGUAGE QuasiQuotes #-}

-- | Unit tests for the query plan computation.
-- Tests both the jl4-service path (buildDecisionQueryCacheFromCompiled + queryPlan)
-- and the LSP path (buildQueryPlanCache / queryPlanFromLadder).
module QueryPlanSpec (spec) where

import Test.Hspec

import Data.Either (isLeft, isRight)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.String.Interpolate (i)
import Data.Text (Text)
import qualified Data.Text as Text
import Control.Monad.Trans.Except (runExceptT)
import Servant (ServerError (..))

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

-- `presumed` is declared FIRST but is a rebuttable presumption (TYPICALLY FALSE)
-- inside an OR, so it is the LEAST informative question and must be asked LAST.
-- Without the TYPICALLY prior it would tie the others and lead by source order.
presumedOrL4 :: Text
presumedOrL4 = [i|
GIVEN presumed IS A BOOLEAN TYPICALLY FALSE
      a IS A BOOLEAN
      b IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE d IF presumed OR a OR b
|]

-- Same structure, no TYPICALLY: the prior-free baseline ranks by source order,
-- so `presumed` leads.
plainOrL4 :: Text
plainOrL4 = [i|
GIVEN presumed IS A BOOLEAN
      a IS A BOOLEAN
      b IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE d IF presumed OR a OR b
|]

-- A rule with the shape of a real one: a scope, a requirement, and a seam between
-- them. Both sides are compound, so the support assertions below are about more than
-- one atom apiece.
impliesL4 :: Text
impliesL4 = [i|
GIVEN upper IS A BOOLEAN
      side IS A BOOLEAN
      glazed IS A BOOLEAN
      shut IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE compliant IF
  (upper AND side) IMPLIES (glazed AND shut)
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

-- | Build a jl4-service CachedDecisionQuery from source, under the shipped
-- default ladder node budget.
serviceCache :: Text -> Text -> IO Service.CachedDecisionQuery
serviceCache = serviceCacheWithBudget defaultLadderNodeBudget

-- | The default of 'Options.maxLadderNodes', repeated here rather than imported
-- so a change to the shipped default shows up as a failure in this suite rather
-- than silently moving what these tests exercise.
defaultLadderNodeBudget :: Int
defaultLadderNodeBudget = 10000

serviceCacheWithBudget :: Int -> Text -> Text -> IO Service.CachedDecisionQuery
serviceCacheWithBudget budget fnName source = do
  cm <- compile fnName source
  result <- runExceptT $ Service.buildDecisionQueryCacheFromCompiled budget fnName cm source
  case result of
    Left err -> fail ("buildDecisionQueryCacheFromCompiled failed: " <> show err)
    Right c -> pure c

-- | Like 'serviceCacheWithBudget' but returns the 'ServerError' instead of
-- failing on it.
serviceCacheEither :: Int -> Text -> Text -> IO (Either ServerError Service.CachedDecisionQuery)
serviceCacheEither budget fnName source = do
  cm <- compile fnName source
  runExceptT $ Service.buildDecisionQueryCacheFromCompiled budget fnName cm source

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
  describe "TYPICALLY question ordering (end-to-end)" typicallyOrderingTests
  describe "ladder node budget" ladderBudgetTests


-- | The ladder is built by distributing OR over AND to reach a normal form, so
-- its size is exponential in the width of a disjunction of conjunctions —
-- @(x0 AND x1) OR (x2 AND x3) OR …@ over 2n variables becomes 2^n clauses. Both
-- @\/query-plan@ and @\/ladder@ serialize the whole thing into their response,
-- and @\/ladder@ is an unauthenticated, CORS-open, prefetchable GET, so the
-- budget is the only thing standing between a 40-line L4 file and a response
-- that streams tens of megabytes for minutes while holding a concurrency slot.
--
-- Measured on the service before the budget existed: 8 variables → 12 KB,
-- 16 → 366 KB, 32 → still streaming past 36 MB after five minutes.
--
-- The budget bounds the RESPONSE. It does not bound the build — 'doVisualize'
-- has already materialised the normal form by the time the budget can be
-- consulted — which is why @evalTimeout@ guards the build separately in
-- 'DataPlane.requireDecisionQueryCache'. IntegrationSpec pins that half.
ladderBudgetTests :: Spec
ladderBudgetTests = do
  it "refuses a ladder past the budget, and says so" do
    result <- serviceCacheEither defaultLadderNodeBudget "blowup" (dnfBlowupL4 32)
    case result of
      Right _ -> expectationFailure
        "expected the 32-variable DNF blow-up to be refused under the default budget"
      Left err -> do
        errHTTPCode err `shouldBe` 400
        show (errBody err) `shouldSatisfy` ("nodes" `List.isInfixOf`)

  it "lets an ordinary decision through untouched" do
    -- The guard must not be a tax on real models: eight variables is already a
    -- big diagram and must still build.
    cache <- serviceCacheWithBudget defaultLadderNodeBudget "blowup" (dnfBlowupL4 8)
    (svcQP cache []).determined `shouldBe` Nothing

  it "the budget is a threshold, not a constant refusal" do
    -- Same source, two budgets, two answers — so the number is doing the work.
    tight <- serviceCacheEither 4 "blowup" (dnfBlowupL4 8)
    isLeft tight `shouldBe` True
    loose <- serviceCacheEither defaultLadderNodeBudget "blowup" (dnfBlowupL4 8)
    isRight loose `shouldBe` True

-- | @(x0 AND x1) OR (x2 AND x3) OR …@ over @n@ boolean parameters.
dnfBlowupL4 :: Int -> Text
dnfBlowupL4 n =
  Text.unlines $
    [ "GIVEN " <> Text.intercalate "\n      " [param k <> " IS A BOOLEAN" | k <- [0 .. n - 1]]
    , "GIVETH A BOOLEAN"
    , "DECIDE blowup IF "
        <> Text.intercalate " OR "
             [ "(" <> param k <> " AND " <> param (k + 1) <> ")" | k <- [0, 2 .. n - 2] ]
    ]
 where
  param k = "x" <> Text.pack (show (k :: Int))


-- | End-to-end check that boolean TYPICALLY defaults flow all the way through
-- the real pipeline (source -> typecheck -> visualize -> query plan) and demote
-- rebuttable presumptions in the ask-order. Exercises H1 (the viz `typically`
-- field) + the priors extraction + the info-gain ranking on BOTH the service and
-- LSP paths.
typicallyOrderingTests :: Spec
typicallyOrderingTests = do
  let rankedLabels r = map (\qa -> qa.label) r.ranked

  describe "presumed OR a OR b" do
    it "service: TYPICALLY FALSE presumption sinks to the end of the ask-order" do
      c <- serviceCache "d" presumedOrL4
      -- presumed (0.1 in an OR) is least informative -> last, despite leading
      -- the source order.
      rankedLabels (svcQP c []) `shouldBe` ["a", "b", "presumed"]

    it "service: without TYPICALLY, prior-free order follows source order" do
      c <- serviceCache "d" plainOrL4
      rankedLabels (svcQP c []) `shouldBe` ["presumed", "a", "b"]

    it "LSP: TYPICALLY FALSE presumption sinks to the end of the ask-order" do
      (info, state, params) <- lspCache "d" presumedOrL4
      map (\qa -> qa.label) (lspQP "d" params info state []).ranked
        `shouldBe` ["a", "b", "presumed"]

    it "service and LSP agree on the ranked order" do
      sCache <- serviceCache "d" presumedOrL4
      (info, state, params) <- lspCache "d" presumedOrL4
      let sLabels = rankedLabels (svcQP sCache [])
          lLabels = map (\qa -> qa.label) (lspQP "d" params info state []).ranked
      sLabels `shouldBe` lLabels


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

  -- The VERDICT, end to end from L4 source (DESIGN §25.7). `determined` is the
  -- function's truth value and stays correct throughout; what these pin is that it is
  -- NOT the thing to show a user, and that the planner now knows the difference.
  describe "IMPLIES — the wizard must not report a vacuous TRUE as compliance" do
    it "scope FALSE: the function is TRUE, and the verdict is NOT Complies" do
      c <- serviceCache "compliant" impliesL4
      let r = svcQP c [("upper", False)]
      -- This is the bug, in one line: `NOT (upper AND side) OR ...` is TRUE, and a UI
      -- switching on `determined` would print "complies" for a ground-floor window the
      -- rule never reached.
      r.determined `shouldBe` Just True
      r.verdict `shouldBe` QP.NotApplicable
      -- and having settled that the rule does not reach this case, it stops asking
      -- about a requirement the window will never be measured against
      r.stillNeeded `shouldBe` []

    it "scope TRUE, requirement TRUE: Complies" do
      c <- serviceCache "compliant" impliesL4
      let r = svcQP c [("upper", True), ("side", True), ("glazed", True), ("shut", True)]
      r.determined `shouldBe` Just True
      r.verdict `shouldBe` QP.Complies
      r.stillNeeded `shouldBe` []

    it "scope TRUE, requirement FALSE: InBreach" do
      c <- serviceCache "compliant" impliesL4
      let r = svcQP c [("upper", True), ("side", True), ("shut", False)]
      r.determined `shouldBe` Just False
      r.verdict `shouldBe` QP.InBreach
      r.stillNeeded `shouldBe` []

    it "scope TRUE, requirement not yet asked: Undetermined, and it asks" do
      c <- serviceCache "compliant" impliesL4
      let r = svcQP c [("upper", True), ("side", True)]
      r.determined `shouldBe` Nothing
      r.verdict `shouldBe` QP.Undetermined
      map (.label) r.stillNeeded `shouldMatchList` ["glazed", "shut"]

    -- THE ONE THAT COST THE SHORT-CIRCUIT. The requirement is met, so the function is
    -- settled TRUE and the classical planner had nothing left to ask — it would stop
    -- here and report "complies". But we do not yet know whether the rule reached this
    -- window at all, and "A.3 does not apply to you" and "you comply with A.3" go on
    -- different pieces of paper. So the interview continues, and it continues on the
    -- SCOPE.
    it "requirement TRUE but scope unknown: the function is settled and the verdict is NOT" do
      c <- serviceCache "compliant" impliesL4
      let r = svcQP c [("glazed", True), ("shut", True)]
      r.determined `shouldBe` Just True
      r.verdict `shouldBe` QP.Undetermined
      map (.label) r.stillNeeded `shouldMatchList` ["upper", "side"]
      length r.asks `shouldSatisfy` (> 0)

    it "and answering the scope then settles it — either way, in the right word" do
      c <- serviceCache "compliant" impliesL4
      let na = svcQP c [("glazed", True), ("shut", True), ("upper", False)]
          ok = svcQP c [("glazed", True), ("shut", True), ("upper", True), ("side", True)]
      -- same `determined` for both; different verdicts. That is the whole finding.
      na.determined `shouldBe` Just True
      ok.determined `shouldBe` Just True
      na.verdict `shouldBe` QP.NotApplicable
      ok.verdict `shouldBe` QP.Complies

    it "a plain rule with no seam still reports Holds/Fails, not Complies" do
      c <- serviceCache "simple and" simpleAndL4
      let held = svcQP c [("a", True), ("b", True)]
          failed = svcQP c [("a", False)]
          open = svcQP c []
      held.verdict `shouldBe` QP.Holds
      failed.verdict `shouldBe` QP.Fails
      open.verdict `shouldBe` QP.Undetermined


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

  -- The LSP path feeds the in-editor ladder, which draws the two lamps. If it and the
  -- picture disagreed about a case, the same user would be told two different things by
  -- two panes of the same window.
  describe "IMPLIES" do
    it "vacuous scope: TRUE function, NotApplicable verdict" do
      (info, state, params) <- lspCache "compliant" impliesL4
      let r = lspQP "compliant" params info state [("upper", False)]
      r.determined `shouldBe` Just True
      r.verdict `shouldBe` QP.NotApplicable

    it "requirement met, scope unknown: keeps asking the scope" do
      (info, state, params) <- lspCache "compliant" impliesL4
      let r = lspQP "compliant" params info state [("glazed", True), ("shut", True)]
      r.determined `shouldBe` Just True
      r.verdict `shouldBe` QP.Undetermined
      map (.label) r.stillNeeded `shouldMatchList` ["upper", "side"]

    it "in breach" do
      (info, state, params) <- lspCache "compliant" impliesL4
      let r = lspQP "compliant" params info state [("upper", True), ("side", True), ("shut", False)]
      r.verdict `shouldBe` QP.InBreach


agreementTests :: Spec
agreementTests = do
  let testAgreement name fnName source bindings = do
        it (name <> " with " <> show bindings) do
          sCache <- serviceCache fnName source
          (info, state, params) <- lspCache fnName source
          let sResp = svcQP sCache bindings
              lResp = lspQP fnName params info state bindings
          sResp.determined `shouldBe` lResp.determined
          sResp.verdict `shouldBe` lResp.verdict

  describe "simple AND" do
    testAgreement "no bindings" "simple and" simpleAndL4 []
    testAgreement "a=True" "simple and" simpleAndL4 [("a", True)]
    testAgreement "a=False" "simple and" simpleAndL4 [("a", False)]
    testAgreement "both True" "simple and" simpleAndL4 [("a", True), ("b", True)]

  describe "nested" do
    testAgreement "c=True" "nested" nestedL4 [("c", True)]
    testAgreement "a=False,c=False" "nested" nestedL4 [("a", False), ("c", False)]
    testAgreement "a=True" "nested" nestedL4 [("a", True)]

  describe "IMPLIES" do
    testAgreement "no bindings" "compliant" impliesL4 []
    testAgreement "vacuous" "compliant" impliesL4 [("upper", False)]
    testAgreement "complies" "compliant" impliesL4 [("upper", True), ("side", True), ("glazed", True), ("shut", True)]
    testAgreement "in breach" "compliant" impliesL4 [("upper", True), ("side", True), ("shut", False)]
    testAgreement "requirement met, scope open" "compliant" impliesL4 [("glazed", True), ("shut", True)]

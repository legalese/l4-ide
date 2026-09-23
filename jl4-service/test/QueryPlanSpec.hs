{-# LANGUAGE QuasiQuotes #-}

-- | Unit tests for the query plan computation.
-- Tests both the jl4-service path (buildDecisionQueryCacheFromCompiled + queryPlan)
-- and the LSP path (buildQueryPlanCache / queryPlanFromLadder).
module QueryPlanSpec (spec) where

import Test.Hspec

import Data.Either (isLeft, isRight)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
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
import qualified TestData as TD


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

-- | Two syntactically identical compound leaves in one decision.
--
-- @n GREATER THAN 5@ is not a bare boolean binder, so each occurrence goes through
-- 'L4.Viz.Ladder.leafFromExpr', which mints a FRESH unique per occurrence — unlike
-- a bare @Ref@, which reuses the resolved name's unique and so is shared. Both
-- occurrences carry the same label and the same input-ref closure, so
-- 'L4.Viz.Ladder.generateAtomId' gives them the SAME atomId. One question, two BDD
-- variables: the shape 'atomIdentityTests' exists to pin.
--
-- The decision is arranged so that answering that one question DETERMINES the
-- outcome, but only if both variables are bound: @n > 5@ false refutes both
-- disjuncts, while binding only one leaves @(n > 5) AND q@ live. So "did the
-- binding reach every twin" is observable as a decision value, not just as a
-- map's cardinality.
twinLeavesL4 :: Text
twinLeavesL4 = [i|
GIVEN n IS A NUMBER
      p IS A BOOLEAN
      q IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE twins IF (n GREATER THAN 5 AND p) OR (n GREATER THAN 5 AND q)
|]

-- | A boolean function applied to boolean arguments, which 'L4.Viz.Ladder'
-- renders as an @App@ node WITH rendered children.
--
-- The children are ladder leaves but not BDD variables — 'vizExprToBoolExpr'
-- turns the whole @App@ into one @BVar@ and does not descend — so they are
-- absent from @varLabelByUnique@ and therefore from the atomId map. They are the
-- case that decides what the annotation's fallback must be.
appOfBooleansL4 :: Text
appOfBooleansL4 = [i|
GIVEN x IS A BOOLEAN
      y IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `both of` x y IF x AND y

GIVEN a IS A BOOLEAN
      b IS A BOOLEAN
      c IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `app leaf` IF (`both of` a b) OR c
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
svcQP = svcQPNamed "test"

-- | Run a jl4-service query plan under a given function name.
--
-- The name is not decoration: it is the first component of every atomId
-- ('L4.Viz.Ladder.generateAtomId'), so any test that compares atomIds across
-- surfaces must pass the name the ladder was built under. 'DataPlane' does this
-- by construction — @requireDecisionQueryCache@ and @queryPlan@ are handed the
-- same @fnName@ — which 'svcQP' (fixed at @"test"@) does not model.
svcQPNamed :: Text -> Service.CachedDecisionQuery -> [(Text, Bool)] -> Service.QueryPlanResponse
svcQPNamed name cache bindings =
  Service.queryPlan name cache FnArguments
    { fnEvalBackend = Nothing
    , fnArguments = Map.fromList [(k, Just (FnLitBool v)) | (k, v) <- bindings]
    , startTime = Nothing
    , events = Nothing
    }

-- | Run an LSP query plan.
lspQP :: Text -> Map.Map Int Text -> VizExpr.RenderAsLadderInfo -> LadderViz.VizState -> [(Text, Bool)] -> QP.QueryPlanResponse
lspQP = LspQP.queryPlanFromLadder

-- | Every @atomId@ carried by a leaf of the ladder, in traversal order and with
-- duplicates KEPT — the duplicates are the point in 'atomIdentityTests'.
ladderAtomIdsOf :: VizExpr.RenderAsLadderInfo -> [Text]
ladderAtomIdsOf info = go info.funDecl.body
 where
  go :: VizExpr.IRExpr -> [Text]
  go = \case
    VizExpr.And _ xs -> concatMap go xs
    VizExpr.Or _ xs -> concatMap go xs
    VizExpr.Not _ x -> go x
    VizExpr.Implies _ scope requirement _ -> go scope <> go requirement
    VizExpr.UBoolVar _ _ _ _ aid _ -> [aid]
    VizExpr.App _ _ args aid -> aid : concatMap go args
    VizExpr.TrueE{} -> []
    VizExpr.FalseE{} -> []
    VizExpr.InertE{} -> []

-- | A UUID in the 8-4-4-4-12 shape 'L4.Crypto.UUID5' emits.
looksLikeUuid :: Text -> Bool
looksLikeUuid t =
  map Text.length (Text.splitOn "-" t) == [8, 4, 4, 4, 12]
    && Text.all (\ch -> ch == '-' || (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f')) t

-- | An atomId that more than one distinct atom @unique@ answers to, if there is one.
twinAtomIdOf :: [QP.QueryAtom] -> Maybe Text
twinAtomIdOf atoms =
  Maybe.listToMaybe
    [ aid
    | (aid, us) <- Map.toList grouped
    , length (List.nub us) > 1
    ]
 where
  grouped = Map.fromListWith (<>) [(a.atomId, [a.unique]) | a <- atoms]


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
  describe "atom identity" atomIdentityTests
  describe "atom identity, across shapes" atomIdentityShapeTests


-- | Atom identity: one bug wearing two faces.
--
-- FACE 1 (upstream smucclaw/l4-ide#935). The ladder and the query plan minted
-- atomIds in two different namespaces, so a client that keyed its bindings by the
-- ladder's atomIds — the natural thing for a ladder-embedded wizard — got a 200
-- and a silent no-op. Measured on a live service against the Reg CF bundle
-- before the fix.
--
-- FACE 2. 'L4.Decision.QueryPlan.queryPlan' inverted its @unique -> atomId@ map
-- with @Map.fromList@, which is last-wins. Twin atoms — two occurrences of one
-- compound leaf, which share an atomId by construction because 'generateAtomId'
-- is a function of (function, label, refs) — collapsed to whichever unique came
-- last, so answering that question bound one occurrence and left the other
-- unknown forever.
--
-- Both faces are about the SAME invariant, which is what these tests state
-- directly: an atomId names a question, a question may have more than one
-- occurrence, and answering it must reach every occurrence on every surface.
atomIdentityTests :: Spec
atomIdentityTests = do
  it "the ladder's atomIds are the query plan's atomIds (smucclaw/l4-ide#935)" do
    cache <- serviceCache "compute_qualifies" threeWayAndL4
    let plan = svcQPNamed "compute_qualifies" cache []
        ladderIds = List.sort (List.nub (ladderAtomIdsOf cache.ladderInfo))
        planIds = List.sort (List.nub [a.atomId | a <- plan.ranked])
    ladderIds `shouldSatisfy` (not . null)
    planIds `shouldSatisfy` (not . null)
    ladderIds `shouldBe` planIds

  it "impactByAtomId is keyed in the ladder's namespace, so a client can join them" do
    cache <- serviceCache "compute_qualifies" threeWayAndL4
    let plan = svcQPNamed "compute_qualifies" cache []
        ladderIds = List.nub (ladderAtomIdsOf cache.ladderInfo)
        impactIds = Map.keys plan.impactByAtomId
    impactIds `shouldSatisfy` (not . null)
    filter (`notElem` ladderIds) impactIds `shouldBe` []

  it "the twin fixture really does mint one atomId for two atoms" do
    -- Guards the two tests below: if a future change to leafFromExpr or to
    -- L4.Transform.simplify stops producing twins, they would pass vacuously.
    cache <- serviceCache "twins" twinLeavesL4
    let ids = ladderAtomIdsOf cache.ladderInfo
        dupes = [a | (a : _ : _) <- List.group (List.sort ids)]
    dupes `shouldSatisfy` (not . null)
    twinAtomIdOf (svcQPNamed "twins" cache []).ranked `shouldSatisfy` Maybe.isJust

  it "binding a twin by the query plan's own atomId binds EVERY occurrence" do
    -- Isolates face 2: the key here is already in the plan's namespace, so the
    -- only thing that can lose it is the last-wins inversion.
    cache <- serviceCache "twins" twinLeavesL4
    twinId <- case twinAtomIdOf (svcQPNamed "twins" cache []).ranked of
      Nothing -> fail "no twin atomId in the plan's own namespace"
      Just t -> pure t
    -- `n > 5` false refutes both disjuncts. Reaching only one twin leaves the
    -- other disjunct live and the decision undetermined.
    (svcQPNamed "twins" cache [(twinId, False)]).determined `shouldBe` Just False

  it "binding a twin by the LADDER's atomId binds EVERY occurrence" do
    -- The two faces composed: this is what the wizard actually does.
    cache <- serviceCache "twins" twinLeavesL4
    let ids = ladderAtomIdsOf cache.ladderInfo
    twinId <- case [a | (a : _ : _) <- List.group (List.sort ids)] of
      [] -> fail "the ladder carries no duplicated atomId"
      (t : _) -> pure t
    (svcQPNamed "twins" cache [(twinId, False)]).determined `shouldBe` Just False

  it "annotation never downgrades a leaf's atomId to a bare unique" do
    -- The children of an App are ladder leaves but NOT BDD variables, so they are
    -- absent from the atomId map. A fallback of `show unique` would replace a
    -- UUID with a decimal — an id that is neither stable across recompiles nor
    -- distinguishable from the `unique` binding key, on the leaves a reader is
    -- most likely to click. The fallback keeps whatever the visualiser minted.
    cache <- serviceCache "app leaf" appOfBooleansL4
    let ids = ladderAtomIdsOf cache.ladderInfo
    ids `shouldSatisfy` (not . null)
    filter (not . looksLikeUuid) ids `shouldBe` []

  it "LSP and service paths agree on atom identity" do
    -- jl4-lsp already reconciled the two namespaces with
    -- annotateLadderWithAtomIds; jl4-service must land in the same place, or the
    -- IDE and the deployed service disagree about what a question is called.
    cache <- serviceCache "compute_qualifies" threeWayAndL4
    (info, vizState, params) <- lspCache "compute_qualifies" threeWayAndL4
    let annotated = LspQP.annotateLadderWithAtomIds info vizState
        lspIds = List.sort (List.nub (ladderAtomIdsOf annotated))
        svcIds = List.sort (List.nub (ladderAtomIdsOf cache.ladderInfo))
        lspPlanIds =
          List.sort (List.nub [a.atomId | a <- (lspQP "compute_qualifies" params info vizState []).ranked])
    svcIds `shouldBe` lspIds
    svcIds `shouldBe` lspPlanIds


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


-- ----------------------------------------------------------------------------
-- Atom identity, across shapes
-- ----------------------------------------------------------------------------

-- | Record projections. Every ref carries a @path@, and the two atomId minters
-- render a path differently at the root — the visualiser as a numeric
-- @rootUnique@, the planner as the parameter's LABEL — so this is the shape where
-- the two namespaces are furthest apart before reconciliation.
projectionsL4 :: Text
projectionsL4 = [i|
DECLARE Person HAS
    age IS A NUMBER
    citizen IS A BOOLEAN
    resident IS A BOOLEAN

GIVEN p IS A Person
GIVETH A BOOLEAN
DECIDE eligible IF p's citizen AND p's resident AND p's age GREATER THAN 18
|]

-- | A decision over @WHERE@-defined sub-decisions. 'L4.Viz.Ladder.varLeaf'
-- expands a local @MEANS@ through 'lookupLocalDecideBody', so the leaves that
-- reach the planner are the expansion's, not the names the drafter wrote — and
-- the expansion duplicates @a@, which makes a twin out of ordinary drafting
-- rather than out of a fixture built to produce one.
whereDefinedL4 :: Text
whereDefinedL4 = [i|
GIVEN a IS A BOOLEAN
      b IS A BOOLEAN
      c IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE outer IF `left side` OR (`right side` AND c)
 WHERE
    `left side` MEANS a AND b

    `right side` MEANS a OR b
|]

-- | One predicate applied twice to DIFFERENT arguments. The two applications must
-- NOT be twins: an atomId is a hash of the rendered call, so @`both of` a b@ and
-- @`both of` b a@ are two questions, not one.
repeatedCallsL4 :: Text
repeatedCallsL4 = [i|
GIVEN x IS A BOOLEAN
      y IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `both of` x y IF x AND y

GIVEN a IS A BOOLEAN
      b IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `repeated calls` IF (`both of` a b) OR (`both of` b a)
|]

-- | The mirror of 'repeatedCallsL4': the SAME call written twice, which must be
-- one question over several occurrences.
sameCallTwiceL4 :: Text
sameCallTwiceL4 = [i|
GIVEN x IS A BOOLEAN
      y IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `both of` x y IF x AND y

GIVEN a IS A BOOLEAN
      b IS A BOOLEAN
      c IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `same call twice` IF (`both of` a b AND c) OR (`both of` a b AND NOT c)
|]

-- | A twin that straddles the @IMPLIES@ seam. The seam is handed to the planner
-- INTACT (see 'LSP.L4.Viz.QueryPlan.vizExprToBoolExpr'), so scope and requirement
-- are separate roots; a question asked on both sides must still be one question.
impliesTwinL4 :: Text
impliesTwinL4 = [i|
GIVEN n IS A NUMBER
      p IS A BOOLEAN
GIVETH A BOOLEAN
DECIDE `implies twin` IF (n GREATER THAN 5) IMPLIES ((n GREATER THAN 5) AND p)
|]

-- | The one atomId invariant that holds for EVERY shape, in the direction a client
-- consumes it: everything the planner names must be findable on the picture.
--
-- The converse does NOT hold and is not asserted — see
-- 'appChildrenAreNotPlanAtoms'.
planIdsAreOnTheLadder :: String -> Text -> Text -> Spec
planIdsAreOnTheLadder nm fnName src = it ("plan ids are all on the ladder: " <> nm) do
  cache <- serviceCache fnName src
  let plan = svcQPNamed fnName cache []
      ladderIds = List.nub (ladderAtomIdsOf cache.ladderInfo)
      planIds = List.nub [a.atomId | a <- plan.ranked]
  planIds `shouldSatisfy` (not . null)
  filter (`notElem` ladderIds) planIds `shouldBe` []
  filter (`notElem` ladderIds) (Map.keys plan.impactByAtomId) `shouldBe` []

-- | Face 2 stated as a property rather than as one fixture: for EVERY atomId the
-- plan reports, binding that atomId must take every @unique@ answering to it out
-- of the decision's support. Under the old last-wins inversion this fails on any
-- shape with a twin — measured red on three of the ten shapes below.
bindsEveryOccurrence :: String -> Text -> Text -> Spec
bindsEveryOccurrence nm fnName src = it ("binding an atomId reaches every occurrence: " <> nm) do
  cache <- serviceCache fnName src
  let plan0 = svcQPNamed fnName cache []
      groups = Map.toList (Map.fromListWith (<>) [(a.atomId, [a.unique]) | a <- plan0.ranked])
  groups `shouldSatisfy` (not . null)
  let leftovers =
        [ (aid, b, us, [s.unique | s <- planB.stillNeeded, s.unique `elem` us])
        | (aid, us0) <- groups
        , let us = List.nub us0
        , b <- [True, False]
        , let planB = svcQPNamed fnName cache [(aid, b)]
        , any (\s -> s.unique `elem` us) planB.stillNeeded
        ]
  leftovers `shouldBe` []

atomIdentityShapeTests :: Spec
atomIdentityShapeTests = do
  planIdsAreOnTheLadder "record projections" "eligible" projectionsL4
  planIdsAreOnTheLadder "WHERE-defined decides" "outer" whereDefinedL4
  planIdsAreOnTheLadder "repeated calls, different arguments" "repeated calls" repeatedCallsL4
  planIdsAreOnTheLadder "the same call twice" "same call twice" sameCallTwiceL4
  planIdsAreOnTheLadder "a twin across the IMPLIES seam" "implies twin" impliesTwinL4
  planIdsAreOnTheLadder "an App over booleans" "app leaf" appOfBooleansL4
  planIdsAreOnTheLadder "WHERE + App, the shape of a real rule" "vermin_and_rodent" TD.rodentAndVerminJL4

  bindsEveryOccurrence "record projections" "eligible" projectionsL4
  bindsEveryOccurrence "WHERE-defined decides" "outer" whereDefinedL4
  bindsEveryOccurrence "repeated calls, different arguments" "repeated calls" repeatedCallsL4
  bindsEveryOccurrence "the same call twice" "same call twice" sameCallTwiceL4
  bindsEveryOccurrence "a twin across the IMPLIES seam" "implies twin" impliesTwinL4
  bindsEveryOccurrence "an App over booleans" "app leaf" appOfBooleansL4
  bindsEveryOccurrence "WHERE + App, the shape of a real rule" "vermin_and_rodent" TD.rodentAndVerminJL4
  bindsEveryOccurrence "the twin fixture" "twins" twinLeavesL4
  bindsEveryOccurrence "a flat conjunction" "compute_qualifies" threeWayAndL4
  bindsEveryOccurrence "an IMPLIES rule" "compliant" impliesL4

  it "one predicate applied to different arguments is two questions, not one" do
    cache <- serviceCache "repeated calls" repeatedCallsL4
    let plan = svcQPNamed "repeated calls" cache []
    length (List.nub [a.atomId | a <- plan.ranked]) `shouldBe` 2

  it "the same call written twice is ONE question" do
    cache <- serviceCache "same call twice" sameCallTwiceL4
    twinAtomIdOf (svcQPNamed "same call twice" cache []).ranked `shouldSatisfy` Maybe.isJust

  -- The bound on the claim above, stated so it cannot quietly widen. An @App@'s
  -- boolean ARGUMENTS are drawn on the ladder (the visualiser renders them, and
  -- `l4-ladder-visualizer` turns them into child nodes) but they are not BDD
  -- variables: 'vizExprToBoolExpr' compiles the whole application to one @BVar@
  -- and does not descend. So they are not in the atomId map, are not plan atoms,
  -- and are not answerable — before this change or after it. They keep the
  -- visualiser's UUID, which is what makes them distinguishable from an atom
  -- rather than colliding with the decimal `unique` binding key.
  it "an App's boolean arguments are ladder leaves but NOT plan atoms" do
    cache <- serviceCache "app leaf" appOfBooleansL4
    let plan = svcQPNamed "app leaf" cache []
        ladderIds = List.nub (ladderAtomIdsOf cache.ladderInfo)
        planIds = List.nub [a.atomId | a <- plan.ranked]
        ladderOnly = filter (`notElem` planIds) ladderIds
    -- Two arguments, `a` and `b`, drawn under the App and absent from the plan.
    length ladderOnly `shouldBe` 2
    -- They are still UUIDs, not bare uniques: the fallback must not downgrade.
    filter (not . looksLikeUuid) ladderOnly `shouldBe` []

  -- The only atomIds committed anywhere in this repo are the four in
  -- `ts-shared/ladder-core/test/fixtures/may-purchase-alcohol.viz.json`, a viz
  -- payload captured from a live jl4-lsp. They are the ANNOTATED ids, so this
  -- change must leave them exactly where they are; if it ever moves them, the TS
  -- consumer test breaks in a repo that this suite cannot see.
  it "the atomIds committed in the ladder-core TS fixture are unmoved" do
    src <- Text.pack <$> readFile "../jl4/examples/ok/typically-basic.l4"
    (info, vizState, _params) <- lspCache "may purchase alcohol" src
    let annotated = List.sort (List.nub (ladderAtomIdsOf (LspQP.annotateLadderWithAtomIds info vizState)))
    annotated
      `shouldBe` [ "6326bf0e-555f-51cc-8c60-8f958d7825c5"
                 , "a5cd464e-b7c1-5e50-9afd-6965842b9386"
                 , "e5ac8240-0124-50f5-a0be-b3fdd4cee33b"
                 , "f94522fa-cdea-5274-944d-99fdb5ba24c8"
                 ]

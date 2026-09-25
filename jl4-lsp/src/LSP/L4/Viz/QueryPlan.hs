{-# LANGUAGE LambdaCase #-}

module LSP.L4.Viz.QueryPlan (
  buildQueryPlanCache,
  buildParamsByUnique,
  annotateLadderWithAtomIds,
  annotateLadderWithAtomIdsUsing,
  queryPlanFromLadder,
  vizExprToBoolExpr,
) where

import Base
import Data.IntMap.Lazy (IntMap)
import Data.IntSet (IntSet)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import qualified L4.Decision.BooleanDecisionQuery as BDQ
import qualified L4.Decision.QueryPlan as QP

import qualified LSP.L4.Viz.Ladder as LadderViz
import qualified LSP.L4.Viz.VizExpr as VizExpr

-- | Extract parameter labels keyed by unique from a RenderAsLadderInfo.
buildParamsByUnique :: VizExpr.RenderAsLadderInfo -> Map Int Text
buildParamsByUnique ladderInfo =
  Map.fromList
    [ (p.unique, p.label)
    | p <- ladderInfo.funDecl.params
    ]

-- | Rewrite every leaf's @atomId@ into the query plan's namespace, deriving that
-- namespace from the ladder itself.
--
-- Convenience wrapper over 'annotateLadderWithAtomIdsUsing' for callers that do
-- not already hold a compiled cache; it pays for a fresh BDD compile. A caller
-- that has one — jl4-service does — should call the @Using@ form and hand over
-- the function name it will later run the plan under, since the name is the
-- first component of every atomId and taking it from the diagram instead is an
-- assumption, not a fact.
annotateLadderWithAtomIds ::
  VizExpr.RenderAsLadderInfo ->
  LadderViz.VizState ->
  VizExpr.RenderAsLadderInfo
annotateLadderWithAtomIds ladderInfo vizState =
  annotateLadderWithAtomIdsUsing
    (QP.atomIdByUnique ladderInfo.funDecl.fnName.label (buildParamsByUnique ladderInfo) cache)
    ladderInfo
 where
  cache = buildQueryPlanCache ladderInfo vizState

-- | Rewrite every leaf's @atomId@ using a precomputed @unique -> atomId@ map.
--
-- WHY THIS EXISTS AT ALL. The ladder and the query plan both mint atomIds as a
-- UUID5 over @"fn|label|refs=…"@, but they disagree on how a ref renders:
-- 'L4.Viz.Ladder.generateAtomId' writes each ref as its numeric @rootUnique@
-- over the atom's DIRECT refs, while 'QP.atomIdByUnique' writes it as the ref's
-- LABEL over the TRANSITIVE closure. They therefore differ for every atom with a
-- non-empty ref set — which is every ordinary leaf.
--
-- The query plan's rendering is the one to keep, and not merely because it came
-- second: a @unique@ is a compilation artefact that moves when an unrelated
-- declaration is added to the file, so a numeric-ref atomId is not stable across
-- recompiles, and an id whose whole job is to survive a redeploy must be.
--
-- Reconciling here rather than in 'generateAtomId' is deliberate: the visualiser
-- runs before the dependency closure exists, so it cannot compute this id, only
-- be corrected with it.
annotateLadderWithAtomIdsUsing ::
  Map Int Text ->
  VizExpr.RenderAsLadderInfo ->
  VizExpr.RenderAsLadderInfo
annotateLadderWithAtomIdsUsing atomIds ladderInfo =
  let
    annotateExpr :: VizExpr.IRExpr -> VizExpr.IRExpr
    annotateExpr = \case
      VizExpr.And uid xs ->
        VizExpr.And uid (map annotateExpr xs)
      VizExpr.Or uid xs ->
        VizExpr.Or uid (map annotateExpr xs)
      VizExpr.Not uid x ->
        VizExpr.Not uid (annotateExpr x)
      VizExpr.Implies uid scope requirement seam ->
        VizExpr.Implies uid (annotateExpr scope) (annotateExpr requirement) seam
      VizExpr.TrueE uid nm ->
        VizExpr.TrueE uid nm
      VizExpr.FalseE uid nm ->
        VizExpr.FalseE uid nm
      VizExpr.UBoolVar uid nm val canInline oldAtomId typically ->
        VizExpr.UBoolVar uid nm val canInline (reAtom nm.unique oldAtomId) typically
      VizExpr.App uid nm args oldAtomId ->
        VizExpr.App uid nm (map annotateExpr args) (reAtom nm.unique oldAtomId)
      VizExpr.InertE uid txt ctx ->
        VizExpr.InertE uid txt ctx  -- Inert elements pass through unchanged

    -- | Not every ladder leaf is a BDD variable, so not every leaf has an entry
    -- here. The children of an @App@ are the standing case: 'vizExprToBoolExpr'
    -- turns the whole application into ONE variable and does not descend, so its
    -- arguments never reach @varLabelByUnique@ and never get a plan-side id.
    --
    -- Such a leaf keeps the id the visualiser gave it. This used to fall back to
    -- @show unique@, which was wrong twice over: it threw away a perfectly good
    -- UUID for a decimal that is not stable across recompiles, and it made the
    -- leaf's @atomId@ collide with the OTHER thing @query-plan@ accepts as a
    -- binding key — a @unique@ written as a decimal string. So the leaves a
    -- reader is most likely to click were the ones whose id could silently mean
    -- someone else's atom.
    reAtom :: Int -> Text -> Text
    reAtom u old = Map.findWithDefault old u atomIds
   in
    ladderInfo
      { VizExpr.funDecl =
          ladderInfo.funDecl
            { VizExpr.body = annotateExpr ladderInfo.funDecl.body
            }
      }

buildQueryPlanCache :: VizExpr.RenderAsLadderInfo -> LadderViz.VizState -> QP.CachedDecisionQuery
buildQueryPlanCache ladderInfo vizState =
  let
    (boolExpr, labels, order) = vizExprToBoolExpr ladderInfo.funDecl.body
    compiled = BDQ.compileDecisionQuery order boolExpr
    deps :: IntMap IntSet
    deps = LadderViz.getAtomDeps vizState
    inputRefs = LadderViz.getAtomInputRefs vizState
   in
    QP.CachedDecisionQuery
      { varLabelByUnique = labels
      , varDepsByUnique = deps
      , varInputRefsByUnique =
          fmap
            (Set.map (\ref -> QP.MkInputRef ref.rootUnique ref.path))
            inputRefs
      , compiled
      , priorsByUnique = VizExpr.boolPriorsFromBody ladderInfo.funDecl.body
      }

queryPlanFromLadder ::
  Text ->
  -- | Parameter labels keyed by unique.
  Map Int Text ->
  VizExpr.RenderAsLadderInfo ->
  LadderViz.VizState ->
  [(Text, Bool)] ->
  QP.QueryPlanResponse
queryPlanFromLadder funName paramsByUnique ladderInfo vizState flattenedLabelBindings =
  QP.queryPlan funName paramsByUnique (buildQueryPlanCache ladderInfo vizState) flattenedLabelBindings

vizExprToBoolExpr ::
  VizExpr.IRExpr ->
  (BDQ.BoolExpr Int, Map Int Text, [Int])
vizExprToBoolExpr expr =
  let (e, labels, order0) = go expr
   in (e, labels, List.nub order0)
 where
  go :: VizExpr.IRExpr -> (BDQ.BoolExpr Int, Map Int Text, [Int])
  go = \case
    VizExpr.TrueE _ _ -> (BDQ.BTrue, mempty, [])
    VizExpr.FalseE _ _ -> (BDQ.BFalse, mempty, [])
    VizExpr.UBoolVar _ nm _ _ _ _ ->
      let u = nm.unique
       in (BDQ.BVar u, Map.singleton u nm.label, [u])
    VizExpr.App _ nm _args _ ->
      let u = nm.unique
       in (BDQ.BVar u, Map.singleton u nm.label, [u])
    VizExpr.Not _ x ->
      let (ex, m, o) = go x
       in (BDQ.BNot ex, m, o)
    -- Hand the seam to the planner INTACT. It will still compile it classically into
    -- the diagram — to settle whether the rule holds, `NOT scope OR requirement` is
    -- exactly the proposition — but it also keeps the two sides as roots of their own,
    -- which is the only way to tell a vacuous TRUE from a compliant one and so the only
    -- way to report a verdict rather than a bare truth value (DESIGN §25.3).
    --
    -- Flattening it here, as we used to, threw that away before the planner ever saw
    -- it: same value, different ink, and the ink is what the user reads.
    VizExpr.Implies _ scope requirement _seam ->
      let (ep, mp, op) = go scope
          (eq, mq, oq) = go requirement
       in (BDQ.BImplies ep eq, mp <> mq, op <> oq)
    VizExpr.And _ xs ->
      let (es, ms, os) = unzip3 (map go xs)
       in (BDQ.BAnd es, mconcat ms, mconcat os)
    VizExpr.Or _ xs ->
      let (es, ms, os) = unzip3 (map go xs)
       in (BDQ.BOr es, mconcat ms, mconcat os)
    -- Inert elements evaluate to identity for their context: AND→True, OR→False
    VizExpr.InertE _ _ VizExpr.InertAnd -> (BDQ.BTrue, mempty, [])
    VizExpr.InertE _ _ VizExpr.InertOr -> (BDQ.BFalse, mempty, [])

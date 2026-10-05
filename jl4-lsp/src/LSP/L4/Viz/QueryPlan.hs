{-# LANGUAGE LambdaCase #-}

module LSP.L4.Viz.QueryPlan (
  buildQueryPlanCache,
  buildParamsByUnique,
  annotateLadderWithAtomIds,
  annotateLadderWithAtomIdsUsing,
  ladderAtomIds,
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
    (ladderAtomIds ladderInfo.funDecl.fnName.label (buildParamsByUnique ladderInfo) cache ladderInfo.funDecl.body)
    ladderInfo
 where
  cache = buildQueryPlanCache ladderInfo vizState

-- | The plan-side atomId of EVERY leaf on the wire, not only of the plan's
-- variables (WHERE-INLINING-SPEC §10).
--
-- 'QP.atomIdByUnique' names the leaves the planner sees: 'vizExprToBoolExpr'
-- makes a whole call ONE variable and descends neither into an 'VizExpr.App's
-- arguments nor into a call's @expansion@. Left there, those leaves would keep
-- the visualiser's numeric-ref ids — a second namespace on the same wire, so a
-- click on the inlined copy of a proposition could not find the direct one.
--
-- So the other leaves are named by the same function, over the same dependency
-- closure ('QP.atomIdsOfLabels'). A plan variable keeps exactly the id it had
-- (the union is left-biased), so nothing the planner answers with moves; and an
-- inlined leaf that IS a plan variable — the caller's own @a@, inlined from
-- @limb a b@ — carries the variable's unique and so gets the variable's id.
--
-- The other leaves' refs render against the PLAN's labels, not with the other
-- leaves' labels added to them. Adding them once made a ref to the module's rule
-- @the season is open@ render by label inside an expansion and by unique at the
-- top, so the call @limb OF the season is open, a@ had one atomId drawn directly
-- and another drawn inside @wrap a@'s expansion (measured 2026-10-05).
ladderAtomIds ::
  -- | The function name the plan runs under.
  Text ->
  -- | Parameter labels keyed by unique.
  Map Int Text ->
  QP.CachedDecisionQuery ->
  VizExpr.IRExpr ->
  Map Int Text
ladderAtomIds funName paramsByUnique cache body =
  Map.union planIds otherIds
 where
  planIds = QP.atomIdByUnique funName paramsByUnique cache
  others =
    Map.fromList
      [ (u, l)
      | (u, l) <- wireLeaves body
      , not (Map.member u cache.varLabelByUnique)
      ]
  otherIds = QP.atomIdsOfLabels funName paramsByUnique cache others

-- | Every leaf that carries an atomId, with its label: through an 'VizExpr.App's
-- arguments and through every expansion.
wireLeaves :: VizExpr.IRExpr -> [(Int, Text)]
wireLeaves = \case
  VizExpr.And _ xs -> concatMap wireLeaves xs
  VizExpr.Or _ xs -> concatMap wireLeaves xs
  VizExpr.Not _ x -> wireLeaves x
  VizExpr.Implies _ p q _ -> wireLeaves p <> wireLeaves q
  VizExpr.UBoolVar _ nm _ _ _ _ x -> (nm.unique, nm.label) : foldMap wireLeaves x
  VizExpr.App _ nm args _ x -> (nm.unique, nm.label) : concatMap wireLeaves args <> foldMap wireLeaves x
  VizExpr.TrueE{} -> []
  VizExpr.FalseE{} -> []
  VizExpr.InertE{} -> []

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
      -- Into expansions too: an inlined leaf is a leaf on the wire like any other.
      VizExpr.UBoolVar uid nm val canInline oldAtomId typically expansion ->
        VizExpr.UBoolVar uid nm val canInline (reAtom nm.unique oldAtomId) typically (fmap annotateExpr expansion)
      VizExpr.App uid nm args oldAtomId expansion ->
        VizExpr.App uid nm (map annotateExpr args) (reAtom nm.unique oldAtomId) (fmap annotateExpr expansion)
      VizExpr.InertE uid txt ctx ->
        VizExpr.InertE uid txt ctx  -- Inert elements pass through unchanged

    -- | Not every ladder leaf is a BDD variable, so a map built by
    -- 'QP.atomIdByUnique' alone has no entry for some leaves. The children of an
    -- @App@ and the leaves of an expansion are the standing case:
    -- 'vizExprToBoolExpr' turns the whole application into ONE variable and does
    -- not descend. 'ladderAtomIds' covers them, and both jl4-lsp and jl4-service
    -- pass its map; a caller that passes a plan-only map does not.
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
    VizExpr.UBoolVar _ nm _ _ _ _ _ ->
      let u = nm.unique
       in (BDQ.BVar u, Map.singleton u nm.label, [u])
    -- A call is ONE variable to the planner; its expansion is a picture of what
    -- the variable means, not more variables.
    VizExpr.App _ nm _args _ _ ->
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

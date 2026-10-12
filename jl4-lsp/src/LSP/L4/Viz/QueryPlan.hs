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
import qualified Data.IntMap.Lazy as IntMap
import Data.IntSet (IntSet)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import qualified L4.Decision.BooleanDecisionQuery as BDQ
import qualified L4.Decision.QueryPlan as QP
import L4.Viz.AtomKey (atomIdOfKey)

import qualified LSP.L4.Viz.Ladder as LadderViz
import qualified LSP.L4.Viz.VizExpr as VizExpr

-- | Extract parameter labels keyed by unique from a RenderAsLadderInfo.
buildParamsByUnique :: VizExpr.RenderAsLadderInfo -> Map Int Text
buildParamsByUnique ladderInfo =
  Map.fromList
    [ (p.unique, p.label)
    | p <- ladderInfo.funDecl.params
    ]

-- | Stamp every leaf's @atomId@ from the keys the ladder recorded, under the
-- diagram's own function name.
--
-- The ladder already names its atoms this way ('LadderViz.getLeafKeys'), so for
-- a diagram drawn under its own name this changes nothing. It is kept for
-- callers that hold a diagram and a state that may have come apart; a caller
-- that serves the function under some other name — jl4-service does — should
-- call the @Using@ form with 'ladderAtomIds' under THAT name, since the name is
-- the first component of every atomId.
annotateLadderWithAtomIds ::
  VizExpr.RenderAsLadderInfo ->
  LadderViz.VizState ->
  VizExpr.RenderAsLadderInfo
annotateLadderWithAtomIds ladderInfo vizState =
  annotateLadderWithAtomIdsUsing
    (Map.fromList
      [ (u, atomIdOfKey ladderInfo.funDecl.fnName.label key)
      | (u, key) <- IntMap.toList (LadderViz.getLeafKeys vizState)
      ])
    ladderInfo

-- | The atomId of EVERY leaf on the wire, not only of the plan's variables
-- (WHERE-INLINING-SPEC §10): an App's arguments and the leaves of a call's
-- expansion are leaves too, though the planner does not see them as variables.
--
-- Each is the hash of the leaf's C1 term key (R3, "L4.Viz.AtomKey"), recorded
-- by the ladder while it drew, so a leaf inside an expansion is keyed in the
-- caller's context: the @a@ inlined from @limb a b@ IS the caller's @a@, and
-- gets its id because it is the same term, not because it carries the same
-- unique.
ladderAtomIds ::
  -- | The function name the plan runs under.
  Text ->
  QP.CachedDecisionQuery ->
  Map Int Text
ladderAtomIds = QP.leafAtomIds

-- | Rewrite every leaf's @atomId@ using a precomputed @unique -> atomId@ map.
--
-- History. The ladder and the query plan once minted atomIds by two different
-- hashes of a leaf's printed label and input refs, and disagreed on every
-- ordinary leaf (smucclaw/l4-ide#935); this function was the reconciliation.
-- Both now name an atom by the hash of its term's C1 key, recorded once by the
-- ladder (R3), so what is left for this to do is restamp a diagram under a
-- different function name ('ladderAtomIds').
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
    -- Such a leaf keeps the id the ladder gave it, which is already the hash of
    -- its term under the diagram's own name. This used to fall back to
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
      , leafKeyByUnique = LadderViz.getLeafKeys vizState
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

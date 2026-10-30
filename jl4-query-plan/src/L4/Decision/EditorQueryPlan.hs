-- | The web editor's query planner: a pure function from L4 source to the
-- JSON answer the browser shows, which jl4-wasm exports to JavaScript.
--
-- It bridges jl4-core's visualization pipeline with this package's query
-- planning.
module L4.Decision.EditorQueryPlan (l4QueryPlan) where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Aeson.Key
import qualified Data.Aeson.KeyMap as Aeson.KeyMap
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Lazy as LazyText
import qualified Data.Text.Lazy.Encoding as LazyText
import Data.Text.Encoding (encodeUtf8)

import L4.API.VirtualFS (checkWithImports, emptyVFS, ResolvedImport(..), TypeCheckWithDepsResult(..))
import L4.Refusal (planDecline)
import L4.TypeCheck (severity)
import L4.TypeCheck.Types (CheckResult (..), Severity (..))
import qualified L4.Viz.Ladder as Ladder
import qualified L4.Viz.VizExpr as VizExpr
import qualified L4.Decision.BooleanDecisionQuery as BDQ
import qualified L4.Decision.QueryPlan as QP
import L4.Decision.QueryPlan (CachedDecisionQuery(..))

-- | Compute a query plan given L4 source, function name, and boolean bindings (as JSON).
--
-- Returns JSON-encoded QueryPlanResponse; for a rule that may refuse to
-- answer, the decline ('L4.Refusal.PlanDecline'), whose @error@ says why;
-- or a JSON error object.
l4QueryPlan :: Text.Text -> Text.Text -> Text.Text -> Text.Text -> Text.Text
l4QueryPlan source uriText functionName bindingsJson =
  case checkWithImports emptyVFS source of
    Left errors ->
      encodeJson $ Aeson.object ["error" Aeson..= Text.intercalate "; " errors]
    Right result ->
      -- Only an SError-severity diagnostic is a type check error; a #CHECK
      -- info or a warning (exhaustiveness, for example) is not.
      if any ((== SError) . severity) result.tcdErrors
        then encodeJson $ Aeson.object ["error" Aeson..= ("Type check error" :: Text.Text)]
        else
          -- A rule that may refuse to answer gets no plan. The decline, read
          -- from what the rule and the definitions it calls are written to
          -- do, through every module it imports, is the answer, before any
          -- ladder is drawn.
          case Ladder.findDecideByName result.tcdModule functionName
                 >>= planDecline (result.tcdModule : map (\ri -> ri.riTypeChecked.program) result.tcdResolvedImports) of
           Just declined -> encodeJson declined
           Nothing ->
            case Ladder.visualizeByNameWithState result.tcdUri uriText 1 result.tcdModule result.tcdSubstitution True functionName of
            Left _ ->
              encodeJson $ Aeson.object ["error" Aeson..= ("Function not found or not visualizable" :: Text.Text)]
            Right (ladderInfo, vizState) ->
              let -- Build CachedDecisionQuery from viz results
                  (boolExpr, labels, order) = vizExprToBoolExpr ladderInfo.funDecl.body
                  compiled = BDQ.compileDecisionQuery order boolExpr
                  deps = Ladder.getAtomDeps vizState
                  inputRefs = Ladder.getAtomInputRefs vizState
                  cache = QP.CachedDecisionQuery
                    { varLabelByUnique = labels
                    , varDepsByUnique = deps
                    , varInputRefsByUnique =
                        fmap (Set.map (\ref -> QP.MkInputRef ref.rootUnique ref.path)) inputRefs
                    , compiled = compiled
                    }

                  -- Parse bindings from JSON
                  paramsByUnique = Map.fromList
                    [ (p.unique, p.label)
                    | p <- ladderInfo.funDecl.params
                    ]

                  flatBindings :: [(Text.Text, Bool)]
                  flatBindings = case Aeson.decodeStrict' (encodeUtf8 bindingsJson) of
                    Just (Aeson.Object obj) ->
                      [ (Aeson.Key.toText k, v)
                      | (k, Aeson.Bool v) <- Aeson.KeyMap.toList obj
                      ]
                    _ -> []

                  result' = QP.queryPlan functionName paramsByUnique cache flatBindings
              in encodeJson result'


-- | Convert a jl4-core VizExpr.IRExpr to a BoolExpr for BDD compilation.
vizExprToBoolExpr ::
  VizExpr.IRExpr ->
  (BDQ.BoolExpr Int, Map.Map Int Text.Text, [Int])
vizExprToBoolExpr expr =
  let (e, labels, order0) = go expr
   in (e, labels, List.nub order0)
 where
  go :: VizExpr.IRExpr -> (BDQ.BoolExpr Int, Map.Map Int Text.Text, [Int])
  go = \case
    VizExpr.TrueE _ _ -> (BDQ.BTrue, mempty, [])
    VizExpr.FalseE _ _ -> (BDQ.BFalse, mempty, [])
    VizExpr.UBoolVar _ nm _ _ _ ->
      let u = nm.unique
       in (BDQ.BVar u, Map.singleton u nm.label, [u])
    VizExpr.App _ nm _args _ ->
      let u = nm.unique
       in (BDQ.BVar u, Map.singleton u nm.label, [u])
    VizExpr.Not _ x ->
      let (ex, m, o) = go x
       in (BDQ.BNot ex, m, o)
    VizExpr.And _ xs ->
      let (es, ms, os) = unzip3 (map go xs)
       in (BDQ.BAnd es, mconcat ms, mconcat os)
    VizExpr.Or _ xs ->
      let (es, ms, os) = unzip3 (map go xs)
       in (BDQ.BOr es, mconcat ms, mconcat os)
    VizExpr.InertE _ _ VizExpr.InertAnd -> (BDQ.BTrue, mempty, [])
    VizExpr.InertE _ _ VizExpr.InertOr -> (BDQ.BFalse, mempty, [])


-- | Encode a value to JSON text.
encodeJson :: Aeson.ToJSON a => a -> Text.Text
encodeJson = LazyText.toStrict . LazyText.decodeUtf8 . Aeson.encode

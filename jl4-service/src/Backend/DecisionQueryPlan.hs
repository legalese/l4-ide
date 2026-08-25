{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ViewPatterns #-}

module Backend.DecisionQueryPlan (
  CachedDecisionQuery (..),
  decisionQueryCacheKey,
  buildDecisionQueryCacheFromCompiled,
  orderAsksForElicitation,
  QueryAtom (..),
  QueryOutcome (..),
  QueryImpact (..),
  QueryInput (..),
  QueryAsk (..),
  QueryPlanResponse (..),
  queryPlan,
) where

import Base
import qualified L4.Decision.BooleanDecisionQuery as BDQ
import L4.FunctionSchema (Parameter (..), Parameters (..), parametersFromDecideWithErrors)
import Backend.Jl4 (CompiledModule (..))
import Data.Aeson (FromJSON, ToJSON, (.=), object)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.Char as Char
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Ord (Down (..))
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import Text.Read (readMaybe)
import Servant (ServerError (..), err400)

import qualified Data.UUID as UUID
import qualified Data.UUID.V5 as UUIDV5

import qualified LSP.L4.Viz.Ladder as LadderViz
import qualified LSP.L4.Viz.VizExpr as VizExpr
import LSP.L4.Viz.QueryPlan (annotateLadderWithAtomIdsUsing, vizExprToBoolExpr)
import qualified Language.LSP.Protocol.Types as LSP

import Backend.Api (FnArguments (..), FnLiteral (..))
import qualified L4.Decision.QueryPlan as QP
import L4.Decision.QueryPlan (QueryAtom (..), QueryImpact (..), QueryInput (..), QueryOutcome (..))

data CachedDecisionQuery = CachedDecisionQuery
  { cacheKey :: !Text
  , ladderInfo :: !VizExpr.RenderAsLadderInfo
  , core :: !QP.CachedDecisionQuery
  , paramSchema :: !Parameters
  }

data QueryAsk = QueryAsk
  { container :: !Text
  , key :: !(Maybe Text)
  , path :: ![Text]
  , label :: !Text
  , score :: !Double
  , atoms :: ![QueryAtom]
  }
  deriving stock (Show, Generic)
  deriving anyclass (FromJSON)

-- | Strip backticks from L4 quoted identifiers when serializing to JSON.
-- Backticks are L4's syntax for allowing spaces in identifiers, but in JSON
-- we already have double quotes for string keys, so backticks shouldn't leak through.
stripBackticks :: Text -> Text
stripBackticks t = fromMaybe t $ Text.stripPrefix "`" t >>= Text.stripSuffix "`"

instance ToJSON QueryAsk where
  toJSON qa = object
    [ "container" .= stripBackticks qa.container
    , "key" .= qa.key
    , "path" .= qa.path
    , "label" .= stripBackticks qa.label
    , "score" .= qa.score
    , "atoms" .= qa.atoms
    ]

data PathSortKey
  = KSField !Int !Text
  | KSIndex !Int
  | KSWildcard
  | KSUnknown !Text
  deriving stock (Show, Eq, Ord)

orderAsksForElicitation :: Parameters -> [QueryAsk] -> [QueryAsk]
orderAsksForElicitation params =
  let
    rootSchemaFor :: QueryAsk -> Maybe Parameter
    rootSchemaFor a = Map.lookup a.container params.parameterMap

    fieldOrderIndex :: Parameter -> Map Text Int
    fieldOrderIndex p =
      let
        props = Map.keys (fromMaybe Map.empty p.parameterProperties)
        ord = fromMaybe (List.sort props) p.parameterPropertyOrder
       in Map.fromList (zip ord [0 ..])

    consumePropertyWithKey :: Map Text Parameter -> [Text] -> Maybe (Text, Parameter, [Text])
    consumePropertyWithKey props segs =
      let
        n = length segs
        tryLen k =
          let key0 = Text.intercalate "." (take k segs)
           in (\p1 -> (key0, p1, drop k segs)) <$> Map.lookup key0 props
       in
        listToMaybe (mapMaybe tryLen [n, n - 1 .. 1])

    pathSortKeyFromSchema :: Parameter -> [Text] -> [PathSortKey]
    pathSortKeyFromSchema p0 = go p0
     where
      go p segs =
        case segs of
          [] -> []
          (seg : rest) ->
            case p.parameterItems of
              Just items ->
                case seg of
                  "*" -> KSWildcard : go items rest
                  "[]" -> KSWildcard : go items rest
                  _ | Text.all Char.isDigit seg ->
                        case readMaybe (Text.unpack seg) of
                          Just idx -> KSIndex idx : go items rest
                          Nothing -> KSUnknown seg : go items rest
                  _ -> KSUnknown seg : go items rest
              Nothing ->
                case p.parameterProperties of
                  Just props ->
                    case consumePropertyWithKey props segs of
                      Nothing -> KSUnknown seg : go p rest
                      Just (fieldKey, p1, rest') ->
                        let
                          idx =
                            Map.findWithDefault maxBound fieldKey (fieldOrderIndex p)
                         in KSField idx fieldKey : go p1 rest'
                  Nothing -> KSUnknown seg : go p rest

    pathSortKey :: QueryAsk -> [PathSortKey]
    pathSortKey a =
      case rootSchemaFor a of
        Nothing -> map KSUnknown a.path
        Just root -> pathSortKeyFromSchema root a.path

    sortKey a = (Down a.score, a.container, pathSortKey a, a.label)
   in
    List.sortOn sortKey

decisionQueryCacheKey :: Text -> Text -> Text
decisionQueryCacheKey funName sourceText =
  let
    canonical =
      Text.intercalate
        "\n\n"
        [ "function=" <> funName
        , "source=" <> sourceText
        ]
  in UUID.toText (UUIDV5.generateNamed UUIDV5.namespaceURL (BS.unpack (Text.encodeUtf8 canonical)))

-- | Build the decision query cache from an already-compiled module.
-- Uses the pre-compiled AST and resolved module directly, avoiding re-typechecking.
--
-- The first argument is the ladder node budget (see
-- 'Options.Options.maxLadderNodes'). A ladder is drawn in AND\/OR normal form,
-- and 'L4.Transform.simplify' reaches that form by distributing OR over AND, so
-- the ladder for @(a AND b) OR (c AND d) OR …@ over 2n variables has 2^n
-- clauses. Everything downstream — the BDD compile below, and the JSON body
-- both @query-plan@ and @ladder@ hand back — is linear or worse in that, so
-- this is the place to refuse: after the visualization (which is what knows the
-- real shape) and before anything that has to traverse it.
--
-- What this does NOT do is bound the visualization itself. 'LadderViz.doVisualize'
-- materialises the whole normal form before returning, so by the time the
-- budget can be consulted the expensive thing has already happened; 32
-- variables take about half a second, 64 do not finish. Bounding that is the
-- caller's job — see the @evalTimeout@ in
-- 'DataPlane.requireDecisionQueryCache'. The two limits are separate because
-- they bound separate things: the timeout bounds a one-time build, the budget
-- bounds a response that is re-serialized on every request.
buildDecisionQueryCacheFromCompiled ::
  (MonadError ServerError m) =>
  Int ->
  Text ->
  CompiledModule ->
  Text ->
  m CachedDecisionQuery
buildDecisionQueryCacheFromCompiled nodeBudget funName compiled sourceText = do
  let resolvedModule = compiled.compiledModule
      decide = compiled.compiledDecide
      fileName = Text.unpack funName <> ".l4"
      verDocId = mkVerDocId fileName
      -- The module is already fully resolved; an empty substitution is sufficient.
      vizCfg = LadderViz.mkVizConfig verDocId resolvedModule Map.empty True

  (ladderInfo, vizState) <- case LadderViz.doVisualize decide vizCfg of
    Left e -> throwError err400 {errBody = Aeson.encode $ object ["error" .= LadderViz.prettyPrintVizError e]}
    Right x -> pure x

  when (exceedsNodeBudget nodeBudget ladderInfo.funDecl.body) $
    throwError err400
      { errBody = Aeson.encode $ object
          [ "error" .=
              ( "The ladder diagram for `" <> funName <> "` has more than "
                  <> Text.pack (show nodeBudget)
                  <> " nodes, which is past the limit this service will build or serve. \
                     \Reaching the AND/OR normal form a ladder draws is exponential in the \
                     \width of a disjunction of conjunctions, so a decision written as \
                     \`(a AND b) OR (c AND d) OR ...` over many variables expands past any \
                     \size a reader could take in. Split the decision into named \
                     \sub-decisions, or raise JL4_MAX_LADDER_NODES."
                :: Text )
          ]
      }

  let (boolExpr, labels, order) = vizExprToBoolExpr ladderInfo.funDecl.body
      bddCompiled = BDQ.compileDecisionQuery order boolExpr
      deps = LadderViz.getAtomDeps vizState
      inputRefs = LadderViz.getAtomInputRefs vizState

      core =
        QP.CachedDecisionQuery
          { varLabelByUnique = labels
          , varDepsByUnique = deps
          , varInputRefsByUnique =
              fmap
                (Set.map (\ref -> QP.MkInputRef ref.rootUnique ref.path))
                inputRefs
          , compiled = bddCompiled
          , priorsByUnique = VizExpr.boolPriorsFromBody ladderInfo.funDecl.body
          }

      -- Put the ladder's leaves into the SAME atomId namespace the query plan
      -- will answer in (upstream smucclaw/l4-ide#935).
      --
      -- Before this, the two surfaces minted different ids for the same atom, so
      -- a client that fetched the diagram and then posted answers keyed by its
      -- atomIds — the natural thing for a ladder-embedded wizard, and what the
      -- Reg CF wizard does — got a 200 and a silent no-op: no 4xx, no warning,
      -- verdict unchanged. jl4-lsp had reconciled them since the beginning by
      -- calling annotateLadderWithAtomIds before serving the ladder; the service
      -- never had, so the IDE and the deployed service disagreed about what a
      -- question was called.
      --
      -- The atomId map is derived from @funName@ — the name this deployment
      -- serves the function under, and the same one 'queryPlan' will be handed —
      -- rather than from the diagram's own @fnName@ label, so the two cannot
      -- drift apart if a function is ever registered under something other than
      -- its DECIDE name. @paramsByUnique@ is read off the ladder's params, which
      -- the annotation does not touch, so it stays valid afterwards.
      paramsByUnique = Map.fromList [(p.unique, p.label) | p <- ladderInfo.funDecl.params]
      joinableLadder =
        annotateLadderWithAtomIdsUsing (QP.atomIdByUnique funName paramsByUnique core) ladderInfo

  pure
    CachedDecisionQuery
      { cacheKey = decisionQueryCacheKey funName sourceText
      , ladderInfo = joinableLadder
      , core
      , paramSchema = parametersFromDecideWithErrors resolvedModule decide []
      }

-- | Does this ladder body have more than @budget@ nodes?
--
-- Fuel-limited: it stops the moment the budget is blown, so the answer costs
-- @O(budget)@ and never @O(size)@. That does not make the oversized ladder
-- cheap — 'LadderViz.doVisualize' has already built it, which is the expensive
-- part, and is why @evalTimeout@ exists alongside this — but it does keep the
-- guard itself from becoming a second traversal of the very thing it is
-- refusing, and it keeps the guard honest if the visualizer is ever made lazier.
--
-- An explicit worklist rather than a fold, so nothing forces the (potentially
-- enormous) argument list of a wide @Or@ beyond the element being counted.
exceedsNodeBudget :: Int -> VizExpr.IRExpr -> Bool
exceedsNodeBudget budget root = go budget [root]
 where
  go :: Int -> [VizExpr.IRExpr] -> Bool
  go fuel _ | fuel <= 0 = True
  go _    []            = False
  go fuel (e : rest)    = go (fuel - 1) (children e <> rest)

  children :: VizExpr.IRExpr -> [VizExpr.IRExpr]
  children = \case
    VizExpr.And _ args            -> args
    VizExpr.Or _ args             -> args
    VizExpr.Not _ negand          -> [negand]
    VizExpr.Implies _ scope req _ -> [scope, req]
    VizExpr.App _ _ args _        -> args
    VizExpr.UBoolVar{}            -> []
    VizExpr.TrueE{}               -> []
    VizExpr.FalseE{}              -> []
    VizExpr.InertE{}              -> []

mkVerDocId :: FilePath -> LSP.VersionedTextDocumentIdentifier
mkVerDocId fileName =
  LSP.VersionedTextDocumentIdentifier
    { _uri = LSP.filePathToUri fileName
    , _version = 1
    }


data QueryPlanResponse = QueryPlanResponse
  { determined :: !(Maybe Bool)
  -- ^ The FUNCTION's truth value. Correct, and NOT a verdict — see 'verdict'.
  , verdict :: !QP.Verdict
  -- ^ What may be shown to a user. Clients should switch on THIS: for a rule stated as
  -- a seam, @Complies@ and @NotApplicable@ are both @determined = true@ (DESIGN §25.3).
  , stillNeeded :: ![QueryAtom]
  , ranked :: ![QueryAtom]
  , inputs :: ![QueryInput]
  , asks :: ![QueryAsk]
  , impact :: !(Map Int QueryImpact)
  , impactByAtomId :: !(Map Text QueryImpact)
  , note :: !Text
  , ladder :: !(Maybe VizExpr.RenderAsLadderInfo)
  }
  deriving stock (Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

queryPlan :: Text -> CachedDecisionQuery -> FnArguments -> QueryPlanResponse
queryPlan name cached args =
  let
    paramsByUnique :: Map Int Text
    paramsByUnique =
      Map.fromList [(p.unique, p.label) | p <- cached.ladderInfo.funDecl.params]

    flattenBoolBindings :: Text -> FnLiteral -> [(Text, Bool)]
    flattenBoolBindings prefix = \case
      FnLitBool b -> [(prefix, b)]
      FnArray xs ->
        concat
          [ flattenBoolBindings (prefix <> "." <> Text.pack (show (idx :: Int))) v
          | (idx, v) <- zip [0 ..] xs
          ]
      FnObject kvs ->
        concat
          [ flattenBoolBindings (prefix <> "." <> k) v
          | (k, v) <- kvs
          ]
      _ -> []

    flattenedLabelBindings :: [(Text, Bool)]
    flattenedLabelBindings =
      concat
        [ case mv of
            Nothing -> []
            Just v -> flattenBoolBindings k v
        | (k, mv) <- Map.toList args.fnArguments
        ]
    QP.QueryPlanResponse{determined, verdict, stillNeeded, ranked, inputs, asks = asksRanked, impact, impactByAtomId, note} =
      QP.queryPlan name paramsByUnique cached.core flattenedLabelBindings

    asksEnriched =
      [ QueryAsk
          { container = a.container
          , key = a.key
          , path = a.path
          , label = a.label
          , score = a.score
          , atoms = a.atoms
          }
      | a <- asksRanked
      ]
    asksOrdered = orderAsksForElicitation cached.paramSchema asksEnriched
   in
    QueryPlanResponse
      { determined
      , verdict
      , stillNeeded
      , ranked
      , inputs
      , asks = asksOrdered
      , impact
      , impactByAtomId
      , note
      , ladder = Just cached.ladderInfo
      }

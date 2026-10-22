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
  QueryRefusal (..),
  QueryPlanResponse (..),
  queryPlan,
) where

import Base
import qualified L4.Decision.BooleanDecisionQuery as BDQ
import L4.FunctionSchema (Parameter (..), Parameters (..), parametersFromDecideWithErrors)
import Backend.Jl4 (CompiledModule (..))
import qualified L4.Refusal as Refusal
import Data.Aeson (FromJSON, ToJSON, (.=), object)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.Char as Char
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Ord (Down (..))
import qualified Data.IntMap.Lazy as IntMap
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import Text.Read (readMaybe)
import Servant (ServerError (..), err400)

import qualified Data.UUID as UUID
import qualified Data.UUID.V5 as UUIDV5

import qualified LSP.L4.Viz.Ladder as LadderViz
import qualified LSP.L4.Viz.VizExpr as VizExpr
import LSP.L4.Viz.QueryPlan (vizExprToBoolExpr)
import qualified Language.LSP.Protocol.Types as LSP

import Backend.Api (FnArguments (..), FnLiteral (..))
import qualified L4.Decision.QueryPlan as QP
import L4.Decision.QueryPlan (QueryAtom (..), QueryImpact (..), QueryInput (..), QueryOutcome (..), QueryRefusal (..))

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
buildDecisionQueryCacheFromCompiled ::
  (MonadError ServerError m) =>
  Text ->
  CompiledModule ->
  Text ->
  m CachedDecisionQuery
buildDecisionQueryCacheFromCompiled funName compiled sourceText = do
  let resolvedModule = compiled.compiledModule
      decide = compiled.compiledDecide
      fileName = Text.unpack funName <> ".l4"
      verDocId = mkVerDocId fileName
      -- The module is already fully resolved; an empty substitution is sufficient.
      draw cfg =
        case LadderViz.doVisualize decide cfg of
          Left e -> throwError err400 {errBody = Aeson.encode $ object ["error" .= LadderViz.prettyPrintVizError e]}
          Right x -> pure x
      vizConfig = LadderViz.mkVizConfig verDocId resolvedModule Map.empty

  -- A rule that holds a refusal is drawn again as written. Simplifying distributes
  -- OR over AND, which keeps every leaf but can change which refusal evaluation,
  -- reading left to right, reaches first (R7). Drawn as written, an IMPLIES or an
  -- IF is one leaf that names only the inputs directly under it, and hides a
  -- refusal inside it, so each is spelled out as the AND, OR and NOT it stands
  -- for. Every other ladder is the simplified one, as before.
  simplified <- draw (vizConfig True)
  let holdsRefusal st =
        not (IntMap.null (LadderViz.getRefusingAtoms st)) || not (null (LadderViz.getUnreadableRefusals st))
  (ladderInfo, vizState) <-
    if holdsRefusal (snd simplified)
      then draw (LadderViz.spellingOut (vizConfig False))
      else pure simplified

  -- A refusal the plan cannot read: in an arm of a CONSIDER, in a comparison, or in
  -- a call, say, where whether it is reached turns on the data, so no order of the
  -- questions is right for it. The plan answers that, and does not guess.
  for_ (Refusal.unreadableRefusalError (LadderViz.getUnreadableRefusals vizState)) \msg ->
    throwError err400 {errBody = Aeson.encode $ object ["error" .= msg]}

  let (boolExpr, labels, order) = vizExprToBoolExpr ladderInfo.funDecl.body
      -- A leaf evaluation can only refuse at is not a question (R7).
      refusals = LadderViz.getRefusingAtoms vizState
      bddCompiled = BDQ.compileDecisionQuery order (BDQ.refusing (Set.fromList (IntMap.keys refusals)) boolExpr)
      deps = LadderViz.getAtomDeps vizState
      inputRefs = LadderViz.getAtomInputRefs vizState

  pure
    CachedDecisionQuery
      { cacheKey = decisionQueryCacheKey funName sourceText
      , ladderInfo
      , core =
          QP.CachedDecisionQuery
            { varLabelByUnique = labels
            , varDepsByUnique = deps
            , varInputRefsByUnique =
                fmap
                  (Set.map (\ref -> QP.MkInputRef ref.rootUnique ref.path))
                  inputRefs
            , compiled = bddCompiled
            , refusalsByUnique = refusals
            }
      , paramSchema = parametersFromDecideWithErrors resolvedModule decide []
      }

mkVerDocId :: FilePath -> LSP.VersionedTextDocumentIdentifier
mkVerDocId fileName =
  LSP.VersionedTextDocumentIdentifier
    { _uri = LSP.filePathToUri fileName
    , _version = 1
    }


data QueryPlanResponse = QueryPlanResponse
  { determined :: !(Maybe Bool)
  , stillNeeded :: ![QueryAtom]
  , ranked :: ![QueryAtom]
  , inputs :: ![QueryInput]
  , asks :: ![QueryAsk]
  , impact :: !(Map Int QueryImpact)
  , impactByAtomId :: !(Map Text QueryImpact)
  , note :: !Text
  , refusal :: !(Maybe QueryRefusal)
  -- ^ Where evaluation of this case is sure to refuse (R7): why, with the reason
  -- @/evaluation@ gives. @null@ everywhere else.
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
    QP.QueryPlanResponse{determined, stillNeeded, ranked, inputs, asks = asksRanked, impact, impactByAtomId, note, refusal} =
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
      , stillNeeded
      , ranked
      , inputs
      , asks = asksOrdered
      , impact
      , impactByAtomId
      , note
      , refusal
      , ladder = Just cached.ladderInfo
      }

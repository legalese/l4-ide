{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module L4.Decision.QueryPlan (
  InputRef (..),
  CachedDecisionQuery (..),
  QueryAtom (..),
  QueryOutcome (..),
  QueryImpact (..),
  QueryInput (..),
  QueryAsk (..),
  QueryPlanResponse (..),
  BDQ.Verdict (..),
  atomIdByUnique,
  queryPlan,
) where

import Base
import qualified L4.Decision.BooleanDecisionQuery as BDQ
import Control.Applicative ((<|>))
import Data.Aeson (FromJSON, ToJSON, (.=), object)
import qualified Data.Aeson as Aeson
import qualified Data.IntMap.Lazy as IntMap
import Data.IntMap.Lazy (IntMap)
import qualified Data.IntSet as IntSet
import Data.IntSet (IntSet)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Data.Set as Set
import Data.Ord (Down (..))
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import Text.Read (readMaybe)

import qualified L4.Crypto.UUID5 as UUID5

inputRefsClosureByUnique :: CachedDecisionQuery -> IntMap (Set InputRef)
inputRefsClosureByUnique cached =
  let
    depMap :: IntMap IntSet
    depMap = cached.varDepsByUnique

    directRefs :: IntMap (Set InputRef)
    directRefs = cached.varInputRefsByUnique

    allUniques :: [Int]
    allUniques =
      Set.toList $
        Set.fromList (Map.keys cached.varLabelByUnique)
          <> Set.fromList (IntMap.keys depMap)
          <> Set.fromList (IntMap.keys directRefs)
          <> Set.fromList (concatMap IntSet.toList (IntMap.elems depMap))

    go :: IntMap (Set InputRef) -> IntSet -> Int -> (Set InputRef, IntMap (Set InputRef))
    go memo visiting u =
      case IntMap.lookup u memo of
        Just s -> (s, memo)
        Nothing ->
          let
            base = IntMap.findWithDefault Set.empty u directRefs
           in
            if IntSet.member u visiting
              then (base, IntMap.insert u base memo)
              else
                let
                  visiting' = IntSet.insert u visiting
                  deps = IntSet.toList (IntMap.findWithDefault IntSet.empty u depMap)
                  (depSets, memo') =
                    List.foldl'
                      ( \(acc, memo0) d ->
                          let (childRefs, memo1) = go memo0 visiting' d
                           in (childRefs : acc, memo1)
                      )
                      ([], memo)
                      deps
                  refs = Set.unions (base : depSets)
                 in
                  (refs, IntMap.insert u refs memo')
   in
    List.foldl'
      (\memo u -> snd (go memo IntSet.empty u))
      IntMap.empty
      allUniques

data InputRef = MkInputRef
  { rootUnique :: !Int
  , path :: ![Text]
  }
  deriving stock (Show, Read, Ord, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data CachedDecisionQuery = CachedDecisionQuery
  { varLabelByUnique :: !(Map Int Text)
  , varDepsByUnique :: !(IntMap IntSet)
  , varInputRefsByUnique :: !(IntMap (Set InputRef))
  , compiled :: !(BDQ.CompiledDecisionQuery Int)
  , priorsByUnique :: !(Map Int Double)
    -- ^ Per-atom prior @P(atom = TRUE)@ from boolean @TYPICALLY@ defaults, keyed
    -- by atom unique. Absent atoms are prior-free (0.5). Feeds the info-gain
    -- question ordering; built once from the ladder's @typically@ fields.
  }

data QueryAtom = QueryAtom
  { unique :: !Int
  , atomId :: !Text
  , label :: !Text
  , inputRefs :: ![InputRef]
  }
  deriving stock (Show, Read, Ord, Eq, Generic)
  deriving anyclass (FromJSON)

-- | Strip backticks from L4 quoted identifiers when serializing to JSON.
-- Backticks are L4's syntax for allowing spaces in identifiers, but in JSON
-- we already have double quotes for string keys, so backticks shouldn't leak through.
stripBackticks :: Text -> Text
stripBackticks t = fromMaybe t $ Text.stripPrefix "`" t >>= Text.stripSuffix "`"

instance ToJSON QueryAtom where
  toJSON qa = object
    [ "unique" .= qa.unique
    , "atomId" .= qa.atomId
    , "label" .= stripBackticks qa.label
    , "inputRefs" .= qa.inputRefs
    ]

data QueryOutcome = QueryOutcome
  { determined :: !(Maybe Bool)
  -- ^ The FUNCTION's truth value. Correct, and NOT a verdict.
  , verdict :: !BDQ.Verdict
  -- ^ What may be shown to a user. Switch on this, not on 'determined'.
  , support :: ![QueryAtom]
  }
  deriving stock (Show, Read, Ord, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data QueryImpact = QueryImpact
  { ifTrue :: !QueryOutcome
  , ifFalse :: !QueryOutcome
  }
  deriving stock (Show, Read, Ord, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data QueryInput = QueryInput
  { inputUnique :: !Int
  , inputLabel :: !Text
  , score :: !Double
  , atoms :: ![QueryAtom]
  }
  deriving stock (Show, Read, Ord, Eq, Generic)
  deriving anyclass (FromJSON)

instance ToJSON QueryInput where
  toJSON qi = object
    [ "inputUnique" .= qi.inputUnique
    , "inputLabel" .= stripBackticks qi.inputLabel
    , "score" .= qi.score
    , "atoms" .= qi.atoms
    ]

data QueryAsk = QueryAsk
  { container :: !Text
  , key :: !(Maybe Text)
  , path :: ![Text]
  , label :: !Text
  , score :: !Double
  , atoms :: ![QueryAtom]
  }
  deriving stock (Show, Read, Ord, Eq, Generic)
  deriving anyclass (FromJSON)

instance ToJSON QueryAsk where
  toJSON qa = object
    [ "container" .= stripBackticks qa.container
    , "key" .= qa.key
    , "path" .= qa.path
    , "label" .= stripBackticks qa.label
    , "score" .= qa.score
    , "atoms" .= qa.atoms
    ]

data QueryPlanResponse = QueryPlanResponse
  { determined :: !(Maybe Bool)
  -- ^ The FUNCTION's truth value: what @NOT scope OR requirement@ comes to. Correct,
  -- and NOT something to show a user — see 'verdict'.
  , verdict :: !BDQ.Verdict
  -- ^ What may be TOLD to a user, and the field a wizard should switch on. For a rule
  -- stated as a seam, 'BDQ.Complies' and 'BDQ.NotApplicable' are BOTH
  -- @determined = Just True@, so a UI that reads 'determined' alone will sooner or
  -- later tell someone they complied with a rule that never reached them (§25.3).
  , stillNeeded :: ![QueryAtom]
  -- ^ Atoms still worth asking about — computed against the VERDICT, so it can be
  -- non-empty even when 'determined' is settled (see 'BDQ.supportIdxOf').
  , ranked :: ![QueryAtom]
  , inputs :: ![QueryInput]
  , asks :: ![QueryAsk]
  , impact :: !(Map Int QueryImpact)
  , impactByAtomId :: !(Map Text QueryImpact)
  , note :: !Text
  }
  deriving stock (Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

atomIdByUnique ::
  Text ->
  -- | Parameter labels keyed by unique.
  Map Int Text ->
  CachedDecisionQuery ->
  Map Int Text
atomIdByUnique name paramsByUnique cached =
  let
    refsByUnique :: IntMap (Set InputRef)
    refsByUnique = inputRefsClosureByUnique cached

    renderInputRef :: InputRef -> Text
    renderInputRef ref =
      let
        rootLbl =
          Maybe.fromMaybe
            (Text.pack (show ref.rootUnique))
            ( Map.lookup ref.rootUnique paramsByUnique
                <|> Map.lookup ref.rootUnique cached.varLabelByUnique
            )
        pathTxt =
          case ref.path of
            [] -> ""
            xs -> "." <> Text.intercalate "." xs
       in rootLbl <> pathTxt

    stableAtomId :: Int -> Text -> Text
    stableAtomId u lbl =
      let
        refs =
          List.sort
            [ renderInputRef ref
            | ref <- Set.toList (IntMap.findWithDefault Set.empty u refsByUnique)
            ]
        canonical =
          Text.intercalate
            "|"
            ( [name, lbl]
                <> ["refs=" <> Text.intercalate ";" refs | not (null refs)]
            )
       in UUID5.toText (UUID5.generateNamed UUID5.namespaceURL (Text.encodeUtf8 canonical))
   in
    Map.fromList
      [ (u, stableAtomId u lbl)
      | (u, lbl) <- Map.toList cached.varLabelByUnique
      ]

queryPlan ::
  Text ->
  -- | Parameter labels keyed by unique.
  Map Int Text ->
  CachedDecisionQuery ->
  -- | Flattened boolean bindings keyed by label (including dotted keys), plus optionally `unique` (decimal) or `atomId`.
  [(Text, Bool)] ->
  QueryPlanResponse
queryPlan name paramsByUnique cached flattenedLabelBindings =
  let
    refsByUnique :: IntMap (Set InputRef)
    refsByUnique = inputRefsClosureByUnique cached

    paramUniqueByLabel :: Map Text Int
    paramUniqueByLabel =
      Map.fromList
        [ (lbl, u)
        | (u, lbl) <- Map.toList paramsByUnique
        ]

    atomIdByUniqueMap :: Map Int Text
    atomIdByUniqueMap = atomIdByUnique name paramsByUnique cached

    -- | The inverse of 'atomIdByUniqueMap', kept ONE-TO-MANY on purpose.
    --
    -- An atomId is a hash of (function, label, input refs) — it names a
    -- QUESTION, not an occurrence. Two occurrences of one compound leaf get
    -- fresh @unique@s from 'L4.Viz.Ladder.leafFromExpr' but identical labels and
    -- identical ref closures, so they are twins under one atomId: one question,
    -- two BDD variables.
    --
    -- This used to be a @Map.fromList@, which is last-wins. A user who answered
    -- that question bound exactly one twin and the other stayed unknown forever
    -- — so a decision that the answer settles outright stayed Undetermined, and
    -- the wizard kept asking a question it had already been told the answer to.
    -- Keeping the whole list is what makes answering a question reach every
    -- occurrence of it.
    uniquesByAtomId :: Map Text [Int]
    uniquesByAtomId =
      Map.fromListWith (<>)
        [ (aid, [u])
        | (u, aid) <- Map.toList atomIdByUniqueMap
        ]

    parseUniqueKey t = readMaybe (Text.unpack t) :: Maybe Int

    parseProjectionLabel :: Text -> Maybe (Text, Text)
    parseProjectionLabel lbl = do
      (container0, rest0) <- Text.breakOn "'s " lbl & \case
        (c, r) | not (Text.null r) -> Just (c, Text.drop 3 r)
        _ -> Nothing
      let field = stripBackticks (Text.strip rest0)
      guard (not (Text.null (Text.strip container0)))
      guard (not (Text.null field))
      pure (Text.strip container0, field)

    answeredAskKeys :: Set (Text, [Text])
    answeredAskKeys =
      Set.fromList $
        concat
          [ case Text.breakOn "." k of
              (containerLabel, rest)
                | Text.null rest -> [(containerLabel, [])]
                | otherwise ->
                    let
                      raw = Text.drop 1 rest
                      singletonPath = [raw]
                      segmentedPath = filter (not . Text.null) (Text.splitOn "." raw)
                     in if singletonPath == segmentedPath
                          then [(containerLabel, singletonPath)]
                          else [(containerLabel, singletonPath), (containerLabel, segmentedPath)]
          | (k, _b) <- flattenedLabelBindings
          ]

    leafUniquesByInputRef :: Map InputRef [Int]
    leafUniquesByInputRef =
      Map.fromListWith (<>)
        [ (ref, [u])
        | (u, refs) <- IntMap.toList refsByUnique
        , [ref] <- [Set.toList refs]
        ]

    candidateInputRefsForKey :: Text -> [InputRef]
    candidateInputRefsForKey k =
      case Text.breakOn "." k of
        (containerLabel, rest) ->
          case Map.lookup containerLabel paramUniqueByLabel of
            Nothing -> []
            Just rootUnique ->
              if Text.null rest
                then [MkInputRef rootUnique []]
                else
                  let
                    raw = Text.drop 1 rest
                    singletonRef = MkInputRef rootUnique [raw]
                    segmented =
                      let segs = filter (not . Text.null) (Text.splitOn "." raw)
                       in MkInputRef rootUnique segs
                   in if singletonRef == segmented then [singletonRef] else [singletonRef, segmented]

    labelToUniques0 :: Map Text [Int]
    labelToUniques0 =
      Map.fromListWith (<>)
        [ (lbl, [u])
        | (u, lbl) <- Map.toList cached.varLabelByUnique
        ]

    projectionLabelToUniques :: Map Text [Int]
    projectionLabelToUniques =
      Map.fromListWith (<>)
        [ (container <> "." <> field, [u])
        | (u, lbl) <- Map.toList cached.varLabelByUnique
        , Just (container, field) <- [parseProjectionLabel lbl]
        ]

    labelToUniques :: Map Text [Int]
    labelToUniques =
      labelToUniques0 <> projectionLabelToUniques

    keyToLeafUniques :: Text -> [Int]
    keyToLeafUniques k =
      List.nub $
        concat
          [ Map.findWithDefault [] ref leafUniquesByInputRef
          | ref <- candidateInputRefsForKey k
          ]

    -- | Try matching a binding key with and without backticks (for spaces in identifiers).
    -- Internal labels may have backticks for L4 pretty-printing, but JSON bindings shouldn't.
    tryMatchKey :: Text -> Maybe [Int]
    tryMatchKey k =
      Map.lookup k labelToUniques
        <|> Map.lookup ("`" <> k <> "`") labelToUniques  -- Try with backticks if key has spaces
        <|> (pure <$> parseUniqueKey k)
        <|> Map.lookup k uniquesByAtomId

    -- Apply boolean bindings to atoms by:
    -- - exact label match (including dotted keys)
    -- - label with backticks added (for identifiers containing spaces)
    -- - `unique` as decimal string
    -- - atomId (stable UUIDv5)
    -- - for record parameters, treat `i.someField = true/false` as binding any leaf atom that depends solely on that input ref.
    knownBindings :: Map Int Bool
    knownBindings =
      Map.fromList $
        concat
          [ [ (u, b)
            | u <- Maybe.fromMaybe [] (tryMatchKey k)
            ]
              <> [ (u, b) | u <- keyToLeafUniques k ]
          | (k, b) <- flattenedLabelBindings
          ]

    res = BDQ.queryDecision cached.compiled cached.priorsByUnique knownBindings

    atomOf :: Int -> QueryAtom
    atomOf u =
      QueryAtom
        { unique = u
        , atomId = Map.findWithDefault (Text.pack (show u)) u atomIdByUniqueMap
        , label = Map.findWithDefault (Text.pack (show u)) u cached.varLabelByUnique
        , inputRefs = Set.toList (IntMap.findWithDefault Set.empty u refsByUnique)
        }

    atomsOfSet :: Set Int -> [QueryAtom]
    atomsOfSet s = map atomOf (Set.toList s)

    -- Information gain (bits) about the outcome from asking this atom, under the
    -- TYPICALLY priors. Subsumes the old hand-rolled "+2 if it determines the
    -- outcome, plus normalized support-shrink" proxy: a determining atom drives a
    -- branch to a terminal, so its entropy is 0 and its gain is maximal.
    impactScoreFor :: Int -> Double
    impactScoreFor atomUniq = Map.findWithDefault 0 atomUniq res.scores

    impactJson :: Map Int QueryImpact
    impactJson =
      Map.map
        ( \vi ->
            QueryImpact
              { ifTrue = QueryOutcome vi.ifTrue.determined vi.ifTrue.verdict (atomsOfSet vi.ifTrue.support)
              , ifFalse = QueryOutcome vi.ifFalse.determined vi.ifFalse.verdict (atomsOfSet vi.ifFalse.support)
              }
        )
        res.impact

    -- | Impact keyed by atomId, i.e. BY QUESTION.
    --
    -- For the ordinary case — one atomId, one unique — this is exactly the
    -- per-variable impact 'BDQ.queryDecision' already computed, unchanged.
    --
    -- For a twin group it cannot be, and using either twin's entry would be a
    -- lie in the direction that matters: a binding keyed by this atomId now
    -- reaches EVERY twin (see 'uniquesByAtomId'), so the honest answer to "what
    -- happens if I answer this question true" is the outcome with all of the
    -- group's variables set, not one of them. Answering a question is one move,
    -- and its impact must be the impact of that move.
    --
    -- Costs two extra BDD restrictions per group of size > 1 and nothing at all
    -- otherwise, so single-atom models keep both their old numbers and their old
    -- runtime. An entry is emitted only for a group at least one of whose
    -- members the decision still turns on — for a singleton that is exactly the
    -- old @Map.member u impactJson@ guard, so a model without twins keeps the
    -- same keys and the same values it had before.
    impactOfGroup :: [Int] -> Maybe QueryImpact
    impactOfGroup us =
      case us of
        [] -> Nothing
        [u] -> Map.lookup u impactJson
        _ | not (any (`Map.member` impactJson) us) -> Nothing
        _ ->
          let
            outcomeWith :: Bool -> QueryOutcome
            outcomeWith b =
              let r =
                    BDQ.queryDecision
                      cached.compiled
                      cached.priorsByUnique
                      (knownBindings <> Map.fromList [(u, b) | u <- us])
               in QueryOutcome r.determined r.verdict (atomsOfSet r.support)
           in Just (QueryImpact (outcomeWith True) (outcomeWith False))

    impactByAtomIdJson :: Map Text QueryImpact
    impactByAtomIdJson =
      Map.fromList
        [ (aid, imp)
        | (aid, us) <- Map.toList uniquesByAtomId
        , Just imp <- [impactOfGroup (List.nub us)]
        ]

    atomParamDeps :: Int -> [Int]
    atomParamDeps atomUniq =
      List.nub $
        [ ref.rootUnique
        | ref <- Set.toList (IntMap.findWithDefault Set.empty atomUniq refsByUnique)
        , Map.member ref.rootUnique paramsByUnique
        ]

    stillNeededAtoms :: [QueryAtom]
    stillNeededAtoms = atomsOfSet res.support

    inputAtoms :: [(Int, [QueryAtom])]
    inputAtoms =
      [ (pUniq, [a | a <- stillNeededAtoms, pUniq `elem` atomParamDeps a.unique])
      | (pUniq, _lbl) <- Map.toList paramsByUnique
      ]

    inputScores :: [(Int, Double)]
    inputScores =
      [ ( pUniq
        , sum
            [ let deps = atomParamDeps a.unique
                  w = 1 / max 1 (fromIntegral (length deps))
               in w * (1 + impactScoreFor a.unique)
            | a <- as
            ]
        )
      | (pUniq, as) <- inputAtoms
      ]

    inputsRanked =
      [ QueryInput
          { inputUnique = pUniq
          , inputLabel = Map.findWithDefault (Text.pack (show pUniq)) pUniq paramsByUnique
          , score = sc
          , atoms = Map.findWithDefault [] pUniq (Map.fromList inputAtoms)
          }
      | (pUniq, sc) <-
          List.sortOn
            (\(u, sc0) -> (Down sc0, Map.findWithDefault "" u paramsByUnique))
            inputScores
      , sc > 0
      ]

    askKeyDepsForAtom :: Int -> Set (Text, [Text])
    askKeyDepsForAtom atomUniq =
      let
        refs =
          IntMap.findWithDefault Set.empty atomUniq refsByUnique
        fallback :: Maybe (Set (Text, [Text]))
        fallback = do
          lbl <- Map.lookup atomUniq cached.varLabelByUnique
          (c, f) <- parseProjectionLabel lbl
          let singletonPath = [f]
          let segmentedPath = filter (not . Text.null) (Text.splitOn "." f)
          pure $
            Set.fromList $
              if singletonPath == segmentedPath
                then [(c, singletonPath)]
                else [(c, singletonPath), (c, segmentedPath)]
       in
        Set.fromList
          [ (containerLabel, ref.path)
          | ref <- Set.toList refs
          , containerLabel <-
              Maybe.maybeToList
                ( Map.lookup ref.rootUnique paramsByUnique
                    <|> Map.lookup ref.rootUnique cached.varLabelByUnique
                )
          ]
          <> Maybe.fromMaybe Set.empty fallback

    askAtomsMap0 :: Map (Text, [Text]) [QueryAtom]
    askAtomsMap0 =
      Map.fromListWith (<>)
        [ (askKey, [a])
        | a <- stillNeededAtoms
        , askKey <- Set.toList (askKeyDepsForAtom a.unique)
        ]

    askAtomsMap :: Map (Text, [Text]) [QueryAtom]
    askAtomsMap =
      let
        containers = Set.fromList [c | ((c, _), _) <- Map.toList askAtomsMap0]
        atomsByUniques = fmap (Set.fromList . map (.unique)) askAtomsMap0
       in
        List.foldl'
          ( \m containerLabel ->
              let
                emptyKey = (containerLabel, [])
                otherKeys = [k | k@(_, (_ : _)) <- Map.keys m, fst k == containerLabel]
               in
                case Map.lookup emptyKey atomsByUniques of
                  Nothing -> m
                  Just emptyAtoms ->
                    if null otherKeys
                      then m
                      else
                        let otherAtoms =
                              Set.unions
                                [ Map.findWithDefault Set.empty k atomsByUniques
                                | k <- otherKeys
                                ]
                         in if emptyAtoms `Set.isSubsetOf` otherAtoms then Map.delete emptyKey m else m
          )
          askAtomsMap0
          (Set.toList containers)

    askDepsSize :: QueryAtom -> Double
    askDepsSize a =
      max 1 (fromIntegral (Set.size (askKeyDepsForAtom a.unique)))

    askScores :: Map (Text, [Text]) Double
    askScores =
      Map.mapWithKey
        (\_ atoms -> sum [(1 / askDepsSize a) * (1 + impactScoreFor a.unique) | a <- atoms])
        askAtomsMap

    asksRanked =
      [ QueryAsk
          { container = containerLabel
          , key =
              case pathSegments of
                [] -> Nothing
                xs -> Just (Text.intercalate "." xs)
          , path = pathSegments
          , label =
              case pathSegments of
                [] -> containerLabel
                xs -> containerLabel <> "." <> Text.intercalate "." xs
          , score = sc
          , atoms = Map.findWithDefault [] (containerLabel, pathSegments) askAtomsMap
          }
      | ((containerLabel, pathSegments), sc) <-
          List.sortOn
            (\((c, k), sc0) -> (Down sc0, c, k))
            (Map.toList askScores)
      , sc > 0
      , (containerLabel, pathSegments) `Set.notMember` answeredAskKeys
      ]

    noteTxt =
      "StillNeeded/ranked are boolean atoms from ladder visualization; these may be derived predicates rather than original user inputs. Bindings are matched by atom label (including dotted labels for nested fields), atom unique (as a decimal string), or atomId (a stable UUIDv5 derived from function name, atom label, and input refs). `inputs` ranks function parameters using a simple dependency-based heuristic."
        <> " `asks` ranks askable keys; for record parameters this includes projected field paths discovered via `Proj`."
        <> " Report `verdict`, not `determined`: when the rule is stated as a seam (`scope IMPLIES requirement`), `Complies` and `NotApplicable` are BOTH `determined = true`, and telling a user they complied with a rule that never reached them is a category error, not a rounding error."
   in
    QueryPlanResponse
      { determined = res.determined
      , verdict = res.verdict
      , stillNeeded = atomsOfSet res.support
      , ranked = map atomOf res.ranked
      , inputs = inputsRanked
      , asks = asksRanked
      , impact = impactJson
      , impactByAtomId = impactByAtomIdJson
      , note = noteTxt
      }

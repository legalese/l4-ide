{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}

module L4.Decision.BooleanDecisionQuery (
  BoolExpr (..),
  DecisionQueryResult (..),
  QueryOutcome (..),
  VarImpact (..),
  CompiledDecisionQuery (..),
  compileDecisionQuery,
  queryDecision,
) where

import Data.List (sortOn)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Ord (Down (..))
import Data.Set (Set)
import qualified Data.Set as Set

data BoolExpr v
  = BTrue
  | BFalse
  | BVar !v
  | BNot !(BoolExpr v)
  | BAnd ![BoolExpr v]
  | BOr ![BoolExpr v]
  deriving stock (Eq, Show)

type NodeId = Int

data Node
  = Terminal !Bool
  | Branch !Int !NodeId !NodeId
  deriving stock (Eq, Show)

data Op = OpAnd | OpOr
  deriving stock (Eq, Ord, Show)

data Bdd = Bdd
  { nodes :: Map NodeId Node
  , uniqueTable :: Map (Int, NodeId, NodeId) NodeId
  , nextId :: !NodeId
  , applyMemo :: Map (Op, NodeId, NodeId) NodeId
  , negMemo :: Map NodeId NodeId
  }
  deriving stock (Eq, Show)

emptyBdd :: Bdd
emptyBdd =
  Bdd
    { nodes = Map.fromList [(0, Terminal False), (1, Terminal True)]
    , uniqueTable = Map.empty
    , nextId = 2
    , applyMemo = Map.empty
    , negMemo = Map.empty
    }

isTerminal :: NodeId -> Bool
isTerminal n = n == 0 || n == 1

mk :: Int -> NodeId -> NodeId -> Bdd -> (NodeId, Bdd)
mk v lo hi bdd
  | lo == hi = (lo, bdd)
  | otherwise =
      case Map.lookup (v, lo, hi) bdd.uniqueTable of
        Just existing -> (existing, bdd)
        Nothing ->
          let nid = bdd.nextId
              nodes' = Map.insert nid (Branch v lo hi) bdd.nodes
              uniq' = Map.insert (v, lo, hi) nid bdd.uniqueTable
           in (nid, bdd {nodes = nodes', uniqueTable = uniq', nextId = nid + 1})

var :: Int -> Bdd -> (NodeId, Bdd)
var v = mk v 0 1

neg :: NodeId -> Bdd -> (NodeId, Bdd)
neg nid bdd =
  case Map.lookup nid bdd.negMemo of
    Just cached -> (cached, bdd)
    Nothing ->
      case Map.lookup nid bdd.nodes of
        Nothing -> error "Internal error: BDD node not found"
        Just (Terminal False) ->
          let bdd' = bdd {negMemo = Map.insert nid 1 bdd.negMemo}
           in (1, bdd')
        Just (Terminal True) ->
          let bdd' = bdd {negMemo = Map.insert nid 0 bdd.negMemo}
           in (0, bdd')
        Just (Branch v lo hi) ->
          let (nlo, bdd1) = neg lo bdd
              (nhi, bdd2) = neg hi bdd1
              (res, bdd3) = mk v nlo nhi bdd2
              bdd4 = bdd3 {negMemo = Map.insert nid res bdd3.negMemo}
           in (res, bdd4)

opEval :: Op -> Bool -> Bool -> Bool
opEval OpAnd a b = a && b
opEval OpOr a b = a || b

apply :: Op -> NodeId -> NodeId -> Bdd -> (NodeId, Bdd)
apply op a b bdd
  | a == b = (a, bdd)
  | isTerminal a && isTerminal b =
      case (bdd.nodes Map.! a, bdd.nodes Map.! b) of
        (Terminal av, Terminal bv) ->
          if opEval op av bv then (1, bdd) else (0, bdd)
        _ -> error "Internal error: terminal node id did not map to Terminal"
  | otherwise =
      case Map.lookup (op, a, b) bdd.applyMemo of
        Just cached -> (cached, bdd)
        Nothing ->
          let an = bdd.nodes Map.! a
              bn = bdd.nodes Map.! b
              aVar = case an of
                Branch v _ _ -> v
                Terminal _ -> maxBound :: Int
              bVar = case bn of
                Branch v _ _ -> v
                Terminal _ -> maxBound :: Int
              top = min aVar bVar
              (aLo, aHi) = case an of
                Branch v lo hi | v == top -> (lo, hi)
                _ -> (a, a)
              (bLo, bHi) = case bn of
                Branch v lo hi | v == top -> (lo, hi)
                _ -> (b, b)
              (loRes, bdd1) = apply op aLo bLo bdd
              (hiRes, bdd2) = apply op aHi bHi bdd1
              (res, bdd3) = mk top loRes hiRes bdd2
              bdd4 = bdd3 {applyMemo = Map.insert (op, a, b) res bdd3.applyMemo}
           in (res, bdd4)

restrictVar :: Int -> Bool -> NodeId -> Bdd -> (NodeId, Bdd)
restrictVar v val nid bdd =
  case bdd.nodes Map.! nid of
    Terminal _ -> (nid, bdd)
    Branch v' lo hi
      | v' == v -> if val then (hi, bdd) else (lo, bdd)
      | otherwise ->
          let (nlo, bdd1) = restrictVar v val lo bdd
              (nhi, bdd2) = restrictVar v val hi bdd1
           in mk v' nlo nhi bdd2

restrictMany :: Map Int Bool -> NodeId -> Bdd -> (NodeId, Bdd)
restrictMany bindings nid bdd =
  Map.foldlWithKey'
    (\(accId, accBdd) v val -> restrictVar v val accId accBdd)
    (nid, bdd)
    bindings

support :: NodeId -> Bdd -> Set Int
support root bdd = go Set.empty Set.empty root
 where
  go :: Set NodeId -> Set Int -> NodeId -> Set Int
  go seen vars nid
    | isTerminal nid = vars
    | nid `Set.member` seen = vars
    | otherwise =
        case bdd.nodes Map.! nid of
          Terminal _ -> vars
          Branch v lo hi ->
            let seen' = Set.insert nid seen
                vars' = Set.insert v vars
                vars'' = go seen' vars' lo
             in go seen' vars'' hi

determinedFromRoot :: NodeId -> Maybe Bool
determinedFromRoot 0 = Just False
determinedFromRoot 1 = Just True
determinedFromRoot _ = Nothing

-- | Binary entropy in bits; 0 at the deterministic ends. Mirror of
-- @binaryEntropy@ in @decision-query.ts@.
binaryEntropy :: Double -> Double
binaryEntropy p
  | p <= 0 || p >= 1 = 0
  | otherwise = negate p * logBase 2 p - (1 - p) * logBase 2 (1 - p)

-- | Probability that the function rooted at @root@ evaluates TRUE under an
-- independent model where BDD variable @v@ is true with weight @weights[v]@
-- (default 0.5). A model count in probability space; because it recurses only
-- on variables that actually appear, it is automatically correct for reduced
-- diagrams that skip variables. Memoized by node id. Mirror of @prob@ in
-- @robdd.ts@ (lines 171-186).
prob :: Bdd -> Map Int Double -> NodeId -> Double
prob bdd weights root = snd (go Map.empty root)
 where
  go :: Map NodeId Double -> NodeId -> (Map NodeId Double, Double)
  go memo nid
    | nid == 0 = (memo, 0)
    | nid == 1 = (memo, 1)
    | otherwise =
        case Map.lookup nid memo of
          Just cached -> (memo, cached)
          Nothing ->
            case bdd.nodes Map.! nid of
              Terminal b -> (memo, if b then 1 else 0)
              Branch v lo hi ->
                let (memo1, plo) = go memo lo
                    (memo2, phi) = go memo1 hi
                    w = Map.findWithDefault 0.5 v weights
                    res = (1 - w) * plo + w * phi
                 in (Map.insert nid res memo2, res)

data QueryOutcome v = QueryOutcome
  { determined :: Maybe Bool
  , support :: Set v
  }
  deriving stock (Eq, Show)

data VarImpact v = VarImpact
  { ifTrue :: QueryOutcome v
  , ifFalse :: QueryOutcome v
  }
  deriving stock (Eq, Show)

data DecisionQueryResult v = DecisionQueryResult
  { determined :: Maybe Bool
  , support :: Set v
  , ranked :: [v]
  , impact :: Map v (VarImpact v)
  , scores :: Map v Double
    -- ^ Information gain (bits) about the outcome per support variable; higher =
    -- ask sooner. Mirror of @scores@ in @decision-query.ts@.
  }
  deriving stock (Eq, Show)

data CompiledDecisionQuery v = CompiledDecisionQuery
  { varOrder :: [v]
  , vToIdx :: Map v Int
  , idxToV :: Map Int v
  , root :: NodeId
  , bdd :: Bdd
  }

compileDecisionQuery :: (Ord v) => [v] -> BoolExpr v -> CompiledDecisionQuery v
compileDecisionQuery order expr =
  let vToIdx = Map.fromList (zip order [0 ..])
      (root, bdd0) = compile vToIdx expr emptyBdd
   in CompiledDecisionQuery
        { varOrder = order
        , vToIdx
        , idxToV = Map.fromList (zip [0 ..] order)
        , root
        , bdd = bdd0
        }
 where
  compile :: (Ord v) => Map v Int -> BoolExpr v -> Bdd -> (NodeId, Bdd)
  compile vToIdx = \case
    BTrue -> \bdd -> (1, bdd)
    BFalse -> \bdd -> (0, bdd)
    BVar v ->
      case Map.lookup v vToIdx of
        Nothing -> error "Internal error: var not found in order"
        Just idx -> \bdd -> var idx bdd
    BNot e ->
      \bdd ->
        let (nid, bdd1) = compile vToIdx e bdd
         in neg nid bdd1
    BAnd es ->
      \bdd ->
        foldl
          (\(acc, bddAcc) e ->
            let (nid, bddE) = compile vToIdx e bddAcc
             in apply OpAnd acc nid bddE
          )
          (1, bdd)
          es
    BOr es ->
      \bdd ->
        foldl
          (\(acc, bddAcc) e ->
            let (nid, bddE) = compile vToIdx e bddAcc
             in apply OpOr acc nid bddE
          )
          (0, bdd)
          es

-- | Rank the still-unknown atoms by information gain about the outcome, given
-- the current bindings and per-atom priors @P(atom = TRUE)@ (default 0.5 when a
-- prior is absent). This subsumes the old "does answering it settle the
-- result?" heuristic — a variable that determines the outcome drives a branch to
-- a terminal so its entropy is 0, i.e. maximal gain — while also crediting a
-- variable that merely shrinks the remaining possibility space. Mirror of the
-- info-gain @rank@ in @decision-query.ts@ (lines 148-206). Ties break by variable
-- order for determinism.
queryDecision :: (Ord v) => CompiledDecisionQuery v -> Map v Double -> Map v Bool -> DecisionQueryResult v
queryDecision compiled priors bindings =
  let idxBindings =
        Map.fromList
          [ (idx, b)
          | (v, b) <- Map.toList bindings
          , Just idx <- [Map.lookup v compiled.vToIdx]
          ]
      (restrictedRoot, bdd1) = restrictMany idxBindings compiled.root compiled.bdd
      -- Priors re-keyed to BDD indices, exactly as robdd.ts's weightByIndex.
      weightByIndex =
        Map.fromList
          [ (idx, w)
          | (v, w) <- Map.toList priors
          , Just idx <- [Map.lookup v compiled.vToIdx]
          ]
      -- Current uncertainty about the outcome, in bits.
      priorEntropy = binaryEntropy (prob bdd1 weightByIndex restrictedRoot)
      supportIdx = support restrictedRoot bdd1
      supportVs =
        Set.fromList
          [ v
          | idx <- Set.toList supportIdx
          , Just v <- [Map.lookup idx compiled.idxToV]
          ]
      outcomeOf rid bdd =
        QueryOutcome
          { determined = determinedFromRoot rid
          , support =
              Set.fromList
                [ v
                | idx <- Set.toList (support rid bdd)
                , Just v <- [Map.lookup idx compiled.idxToV]
                ]
          }
      -- Per support variable, compute both its impact and its info-gain score
      -- from the same restriction (mirrors the single loop in decision-query.ts).
      perVar v =
        case Map.lookup v compiled.vToIdx of
          Nothing -> error "Internal error: var not found in order"
          Just idx ->
            let (ridT, bddT) = restrictVar idx True restrictedRoot bdd1
                (ridF, bddF) = restrictVar idx False restrictedRoot bdd1
                impactV =
                  VarImpact
                    { ifTrue = outcomeOf ridT bddT
                    , ifFalse = outcomeOf ridF bddF
                    }
                w = Map.findWithDefault 0.5 idx weightByIndex
                -- Expected posterior entropy after asking this variable, weighted
                -- by how likely each answer is; info gain = prior - expected.
                expectedPosterior =
                  w * binaryEntropy (prob bddT weightByIndex ridT)
                    + (1 - w) * binaryEntropy (prob bddF weightByIndex ridF)
             in (impactV, priorEntropy - expectedPosterior)
      perVarMap = Map.fromList [(v, perVar v) | v <- Set.toList supportVs]
      impactMap = fmap fst perVarMap
      scoresMap = fmap snd perVarMap
      level v = Map.findWithDefault 1000000 v compiled.vToIdx
      rankedVars =
        sortOn
          (\v -> (Down (Map.findWithDefault 0 v scoresMap), level v))
          (Set.toList supportVs)
   in DecisionQueryResult
        { determined = determinedFromRoot restrictedRoot
        , support = supportVs
        , ranked = rankedVars
        , impact = impactMap
        , scores = scoresMap
        }


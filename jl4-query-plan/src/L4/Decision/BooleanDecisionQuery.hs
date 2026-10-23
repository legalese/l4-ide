{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}

module L4.Decision.BooleanDecisionQuery (
  BoolExpr (..),
  refusing,
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
import Data.Set (Set)
import qualified Data.Set as Set

data BoolExpr v
  = BTrue
  | BFalse
  | BVar !v
  | BNot !(BoolExpr v)
  | BAnd ![BoolExpr v]
  | BOr ![BoolExpr v]
  | -- | A leaf that refuses whenever evaluation reaches it (ruling R7: a refusal
    -- is a throw at force, never a value, and cannot be caught). It is not a
    -- question: no answer to it is ever used, since evaluation does not take one,
    -- so it is no variable of the diagram. An expression that holds one is planned
    -- by evaluation's own order ('compileLazy'), for which @x AND r@ is FALSE
    -- when @x@ is but @r AND x@ refuses.
    BRefuse !v
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

data QueryOutcome v = QueryOutcome
  { determined :: Maybe Bool
  , support :: Set v
  , refusedAt :: Set v
  -- ^ Where evaluation is sure to refuse, the refusing leaves ('BRefuse') it can
  -- reach first; otherwise empty.
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
  , refusedAt :: Set v
  -- ^ Where evaluation is sure to refuse, the refusing leaves ('BRefuse') it can
  -- reach first; otherwise empty.
  , ranked :: [v]
  , impact :: Map v (VarImpact v)
  }
  deriving stock (Eq, Show)

data CompiledDecisionQuery v = CompiledDecisionQuery
  { varOrder :: [v]
  , vToIdx :: Map v Int
  , idxToV :: Map Int v
  , root :: NodeId
  , bdd :: Bdd
  , lazyRoot :: Maybe (Lazy v)
  -- ^ Present iff the expression holds a refusing leaf ('BRefuse'). Then the plan
  -- is read off this, not off 'root'; without one, 'root' is what it always was,
  -- and so is every plan.
  }

compileDecisionQuery :: (Ord v) => [v] -> BoolExpr v -> CompiledDecisionQuery v
compileDecisionQuery order expr =
  let vToIdx = Map.fromList (zip order [0 ..])
      (root, bdd0) = compile vToIdx expr emptyBdd
      (lazyRoot, bdd1)
        | hasRefusal expr = let (l, b) = compileLazy vToIdx expr bdd0 in (Just l, b)
        | otherwise = (Nothing, bdd0)
   in CompiledDecisionQuery
        { varOrder = order
        , vToIdx
        , idxToV = Map.fromList (zip [0 ..] order)
        , root
        , bdd = bdd1
        , lazyRoot
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
    -- Read as a variable here, so that 'root' stays well-formed; with a refusing
    -- leaf in it, an expression is planned from 'lazyRoot' instead.
    BRefuse v ->
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

-- | Make the leaves for these variables refusing leaves ('BRefuse').
refusing :: (Ord v) => Set v -> BoolExpr v -> BoolExpr v
refusing vs = go
 where
  go = \case
    BVar v | v `Set.member` vs -> BRefuse v
    BNot e -> BNot (go e)
    BAnd es -> BAnd (map go es)
    BOr es -> BOr (map go es)
    e -> e

hasRefusal :: BoolExpr v -> Bool
hasRefusal = \case
  BRefuse _ -> True
  BNot e -> hasRefusal e
  BAnd es -> any hasRefusal es
  BOr es -> any hasRefusal es
  _ -> False

-- | What evaluating an expression comes to, as diagrams over the variables that
-- can be asked: when it is TRUE, when it is FALSE, and, for each refusing leaf,
-- when evaluation reaches that leaf first and so refuses with its reason. The
-- three cover every case and do not overlap, so where neither 'onTrue' nor
-- 'onFalse' holds, evaluation refuses.
data Lazy v = Lazy
  { onTrue :: !NodeId
  , onFalse :: !NodeId
  , refusesAt :: !(Map v NodeId)
  }
  deriving stock (Eq, Show)

-- | Read an expression as evaluation reads it: left to right, stopping as soon
-- as the answer is known (@L4.EvaluateLazy.Machine.connectiveLeft@). So
-- @a AND b@ is FALSE wherever @a@ is, whatever @b@ would do, and refuses where
-- @a@ refuses, or @a@ is TRUE and @b@ refuses; @OR@ likewise. With no refusing
-- leaf this agrees with the classical diagram everywhere; with one, it is what
-- makes the plan and evaluation give the same answer in the order the rule is
-- written, which R7 records rather than removes.
compileLazy :: (Ord v) => Map v Int -> BoolExpr v -> Bdd -> (Lazy v, Bdd)
compileLazy vToIdx = \case
  BTrue -> \bdd -> (Lazy 1 0 Map.empty, bdd)
  BFalse -> \bdd -> (Lazy 0 1 Map.empty, bdd)
  BVar v ->
    case Map.lookup v vToIdx of
      Nothing -> error "Internal error: var not found in order"
      Just idx -> \bdd ->
        let (x, bdd1) = var idx bdd
            (nx, bdd2) = neg x bdd1
         in (Lazy x nx Map.empty, bdd2)
  BRefuse v -> \bdd -> (Lazy 0 0 (Map.singleton v 1), bdd)
  BNot e -> \bdd ->
    let (l, bdd1) = compileLazy vToIdx e bdd
     in (Lazy l.onFalse l.onTrue l.refusesAt, bdd1)
  BAnd es -> foldConnective lazyAnd (Lazy 1 0 Map.empty) es
  BOr es -> foldConnective lazyOr (Lazy 0 1 Map.empty) es
 where
  -- Right to left, so that each operand is read after the ones before it.
  foldConnective op unit es bdd0 =
    case reverse es of
      [] -> (unit, bdd0)
      lastE : earlier ->
        let (acc0, bdd1) = compileLazy vToIdx lastE bdd0
         in foldl
              (\(acc, bddAcc) e ->
                let (l, bddE) = compileLazy vToIdx e bddAcc
                 in op l acc bddE
              )
              (acc0, bdd1)
              earlier

-- | @a AND b@: TRUE where both are; FALSE where @a@ is, or @a@ is TRUE and @b@
-- FALSE; refusing where @a@ refuses, or @a@ is TRUE and @b@ refuses.
lazyAnd :: (Ord v) => Lazy v -> Lazy v -> Bdd -> (Lazy v, Bdd)
lazyAnd a b bdd0 =
  let (t, bdd1) = apply OpAnd a.onTrue b.onTrue bdd0
      (tf, bdd2) = apply OpAnd a.onTrue b.onFalse bdd1
      (f, bdd3) = apply OpOr a.onFalse tf bdd2
      (r, bdd4) = thenRefuses a.onTrue a.refusesAt b.refusesAt bdd3
   in (Lazy t f r, bdd4)

-- | @a OR b@: TRUE where @a@ is, or @a@ is FALSE and @b@ TRUE; FALSE where both
-- are; refusing where @a@ refuses, or @a@ is FALSE and @b@ refuses.
lazyOr :: (Ord v) => Lazy v -> Lazy v -> Bdd -> (Lazy v, Bdd)
lazyOr a b bdd0 =
  let (ft, bdd1) = apply OpAnd a.onFalse b.onTrue bdd0
      (t, bdd2) = apply OpOr a.onTrue ft bdd1
      (f, bdd3) = apply OpAnd a.onFalse b.onFalse bdd2
      (r, bdd4) = thenRefuses a.onFalse a.refusesAt b.refusesAt bdd3
   in (Lazy t f r, bdd4)

-- | The refusals of a connective: the left operand's, and the right operand's
-- where the left one lets evaluation go on (@goOn@).
thenRefuses :: (Ord v) => NodeId -> Map v NodeId -> Map v NodeId -> Bdd -> (Map v NodeId, Bdd)
thenRefuses goOn left right bdd0 =
  Map.foldlWithKey'
    ( \(acc, bddAcc) v r ->
        let (reached, bdd1) = apply OpAnd goOn r bddAcc
         in case Map.lookup v acc of
              Nothing -> (Map.insert v reached acc, bdd1)
              Just already ->
                let (both, bdd2) = apply OpOr already reached bdd1
                 in (Map.insert v both acc, bdd2)
    )
    (left, bdd0)
    right

restrictLazy :: Map Int Bool -> Lazy v -> Bdd -> (Lazy v, Bdd)
restrictLazy bindings l bdd0 =
  let (t, bdd1) = restrictMany bindings l.onTrue bdd0
      (f, bdd2) = restrictMany bindings l.onFalse bdd1
      (bdd3, rs) =
        Map.mapAccum
          (\bddAcc r -> let (r', b) = restrictMany bindings r bddAcc in (b, r'))
          bdd2
          l.refusesAt
   in (Lazy t f rs, bdd3)

lazyDetermined :: Lazy v -> Maybe Bool
lazyDetermined l
  | l.onTrue == 1 = Just True
  | l.onFalse == 1 = Just False
  | otherwise = Nothing

-- | Evaluation is sure to refuse: no answer to what is left makes it TRUE or FALSE.
lazyRefused :: Lazy v -> Bool
lazyRefused l = l.onTrue == 0 && l.onFalse == 0

-- | The variables still worth asking about: those the outcome still turns on.
-- None once evaluation is sure to refuse, since then both diagrams are empty.
lazySupportIdx :: Bdd -> Lazy v -> Set Int
lazySupportIdx bdd l = support l.onTrue bdd <> support l.onFalse bdd

-- | The refusing leaves evaluation can still reach first.
lazyRefusedAt :: Lazy v -> Set v
lazyRefusedAt l = Map.keysSet (Map.filter (/= 0) l.refusesAt)

queryDecision :: (Ord v) => CompiledDecisionQuery v -> Map v Bool -> DecisionQueryResult v
queryDecision compiled bindings = case compiled.lazyRoot of
  Just l -> queryDecisionLazy compiled l bindings
  Nothing -> queryDecisionClassical compiled bindings

queryDecisionClassical :: (Ord v) => CompiledDecisionQuery v -> Map v Bool -> DecisionQueryResult v
queryDecisionClassical compiled bindings =
  let idxBindings =
        Map.fromList
          [ (idx, b)
          | (v, b) <- Map.toList bindings
          , Just idx <- [Map.lookup v compiled.vToIdx]
          ]
      (restrictedRoot, bdd1) = restrictMany idxBindings compiled.root compiled.bdd
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
          , refusedAt = Set.empty
          }
      impactMap =
        Map.fromList
          [ ( v
            , case Map.lookup v compiled.vToIdx of
                Nothing -> error "Internal error: var not found in order"
                Just idx ->
                  let (ridT, bddT) = restrictVar idx True restrictedRoot bdd1
                      (ridF, bddF) = restrictVar idx False restrictedRoot bdd1
                   in VarImpact
                        { ifTrue = outcomeOf ridT bddT
                        , ifFalse = outcomeOf ridF bddF
                        }
            )
          | v <- Set.toList supportVs
          ]
      determinableCount v =
        case Map.lookup v impactMap of
          Nothing -> 0 :: Int
          Just vi ->
            fromEnum (vi.ifTrue.determined /= Nothing)
              + fromEnum (vi.ifFalse.determined /= Nothing)
      level v = Map.findWithDefault 1000000 v compiled.vToIdx
      rankedVars =
        sortOn
          (\v -> (-determinableCount v, level v))
          (Set.toList supportVs)
   in DecisionQueryResult
        { determined = determinedFromRoot restrictedRoot
        , support = supportVs
        , refusedAt = Set.empty
        , ranked = rankedVars
        , impact = impactMap
        }

-- | 'queryDecisionClassical', read lazily ('compileLazy'), for an expression that
-- holds a refusing leaf. The same shape, step for step; what differs is what the
-- diagrams say. A binding to a refusing leaf changes nothing, since evaluation
-- never takes one. An answer that leads to a refusal settles the plan as much as
-- one that leads to a value: nothing is left to ask.
queryDecisionLazy :: (Ord v) => CompiledDecisionQuery v -> Lazy v -> Map v Bool -> DecisionQueryResult v
queryDecisionLazy compiled lazyRoot bindings =
  let idxBindings =
        Map.fromList
          [ (idx, b)
          | (v, b) <- Map.toList bindings
          , Just idx <- [Map.lookup v compiled.vToIdx]
          ]
      (restricted, bdd1) = restrictLazy idxBindings lazyRoot compiled.bdd
      varsOf idxs =
        Set.fromList
          [ v
          | idx <- Set.toList idxs
          , Just v <- [Map.lookup idx compiled.idxToV]
          ]
      supportVs = varsOf (lazySupportIdx bdd1 restricted)
      refusedAtOf l
        | lazyRefused l = lazyRefusedAt l
        | otherwise = Set.empty
      outcomeOf bdd l =
        QueryOutcome
          { determined = lazyDetermined l
          , support = varsOf (lazySupportIdx bdd l)
          , refusedAt = refusedAtOf l
          }
      impactMap =
        Map.fromList
          [ ( v
            , case Map.lookup v compiled.vToIdx of
                Nothing -> error "Internal error: var not found in order"
                Just idx ->
                  let (lT, bddT) = restrictLazy (Map.singleton idx True) restricted bdd1
                      (lF, bddF) = restrictLazy (Map.singleton idx False) restricted bdd1
                   in VarImpact
                        { ifTrue = outcomeOf bddT lT
                        , ifFalse = outcomeOf bddF lF
                        }
            )
          | v <- Set.toList supportVs
          ]
      settledCount v =
        case Map.lookup v impactMap of
          Nothing -> 0 :: Int
          Just vi ->
            fromEnum (settled vi.ifTrue) + fromEnum (settled vi.ifFalse)
      settled o = o.determined /= Nothing || not (Set.null o.refusedAt)
      level v = Map.findWithDefault 1000000 v compiled.vToIdx
      rankedVars =
        sortOn
          (\v -> (-settledCount v, level v))
          (Set.toList supportVs)
   in DecisionQueryResult
        { determined = lazyDetermined restricted
        , support = supportVs
        , refusedAt = refusedAtOf restricted
        , ranked = rankedVars
        , impact = impactMap
        }


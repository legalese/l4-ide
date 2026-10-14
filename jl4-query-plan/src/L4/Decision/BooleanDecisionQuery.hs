{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedRecordDot #-}

module L4.Decision.BooleanDecisionQuery (
  BoolExpr (..),
  refusing,
  Verdict (..),
  DecisionQueryResult (..),
  QueryOutcome (..),
  VarImpact (..),
  CompiledDecisionQuery (..),
  compileDecisionQuery,
  queryDecision,
) where

import Data.Aeson (FromJSON, ToJSON)
import Data.List (sortOn)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Ord (Down (..))
import Data.Set (Set)
import qualified Data.Set as Set
import GHC.Generics (Generic)

data BoolExpr v
  = BTrue
  | BFalse
  | BVar !v
  | BNot !(BoolExpr v)
  | BAnd ![BoolExpr v]
  | BOr ![BoolExpr v]
  | -- | @scope@ IMPLIES @requirement@ — the seam (DESIGN §25).
    --
    -- It compiles into the BDD classically, as @NOT scope OR requirement@, and that
    -- is not a compromise: to settle whether the rule HOLDS, that is exactly the
    -- proposition. What the classical form cannot do is say WHY it holds — a window
    -- the rule never reached and a window that complies both make it TRUE. So we keep
    -- the two sides as roots of their own (see 'CompiledDecisionQuery'), and read the
    -- verdict off them directly. Same value; different ink (§25.3).
    BImplies !(BoolExpr v) !(BoolExpr v)
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

-- | The roots the planner tracks: the function itself, and — when the body is a seam
-- — its two sides, compiled into the SAME diagram so they share variable indices and
-- hash-consing. Restricting all three under one set of bindings is what lets us report
-- a verdict instead of a bare truth value.
data Roots = Roots
  { fnRoot :: !NodeId
  , seamRoots :: !(Maybe (NodeId, NodeId))
  -- ^ @(scope, requirement)@, present iff the body IS a seam. Only a top-level seam
  -- has a verdict to report: it is the rule's own scope/requirement split. A seam
  -- buried inside an @AND@ is just a subterm, and the ladder's translator never emits
  -- one anyway — it peels exactly the outermost implication (DESIGN §25a).
  }
  deriving stock (Eq, Show)

-- | What a wizard may TELL a user — as opposed to what the function evaluates to.
--
-- The two are not the same thing, and that is the whole point. 'determined' is the
-- function's truth value and remains exactly that; for a seam it CANNOT be turned into
-- a verdict, because a vacuous case and a compliant one both make @NOT scope OR
-- requirement@ TRUE. Reporting that TRUE as "complies" is the N/A-vs-complies category
-- error the ladder fixes with two lamps (DESIGN §25.3) — and this type is those two
-- lamps, in the wizard.
data Verdict
  = -- | Not settled. There are still questions worth asking.
    Undetermined
  | -- | No seam: the function is TRUE.
    Holds
  | -- | No seam: the function is FALSE.
    Fails
  | -- | The rule reached this case, and the requirement is met.
    Complies
  | -- | The rule reached this case, and the requirement is not met.
    InBreach
  | -- | The rule never reached this case. Note the function is TRUE here, and saying
    -- so ("yes, you're fine") is not the same as saying you complied: you were never
    -- asked to. Vacuity is a STATE, not a way of passing.
    NotApplicable
  deriving stock (Eq, Ord, Show, Read, Enum, Bounded, Generic)
  deriving anyclass (FromJSON, ToJSON)

-- | Read the verdict off the seam's two sides — the same two lamps 'lampsFor' lights
-- in @ladder-core@, and deliberately so: if the wizard and the picture disagreed about
-- a case, one of them would be lying to the same user.
verdictOf :: Roots -> Verdict
verdictOf rs = case rs.seamRoots of
  Nothing -> case determinedFromRoot rs.fnRoot of
    Just True -> Holds
    Just False -> Fails
    Nothing -> Undetermined
  Just (scopeRoot, reqRoot) -> case determinedFromRoot scopeRoot of
    Just False -> NotApplicable
    Just True -> case determinedFromRoot reqRoot of
      Just True -> Complies
      Just False -> InBreach
      Nothing -> Undetermined
    -- An UNKNOWN scope is undetermined even when the requirement is already met and
    -- the function is therefore settled TRUE. We would not know WHICH true it is, and
    -- "the rule does not reach you" and "you comply" go on different pieces of paper.
    Nothing -> Undetermined

-- | The atoms still worth asking about, as BDD indices.
--
-- This is where the seam changes the planner's behaviour, and it is the sharp edge of
-- the whole fix. The classical short-circuit — requirement TRUE, so the function is
-- TRUE, so stop — is valid only if you are computing a truth VALUE. If you are
-- computing a VERDICT it is wrong: a met requirement does not tell you whether the
-- rule bit, and the scope still does. So we take the support of the SIDES, not of the
-- function, and the interview continues until the verdict itself is settled.
--
-- It costs questions. That is the trade, made deliberately: a shorter interview that
-- ends in the wrong word is not a bargain.
supportIdxOf :: Bdd -> Roots -> Set Int
supportIdxOf bdd rs = case rs.seamRoots of
  Nothing -> support rs.fnRoot bdd
  Just (scopeRoot, reqRoot) ->
    support scopeRoot bdd
      <> if determinedFromRoot scopeRoot == Just False
        then -- N/A is settled. A requirement you will never be measured against is not
        -- worth a question, so the interview stops here rather than asking after a
        -- rule that has already been established not to reach you.
          Set.empty
        else support reqRoot bdd

-- | Uncertainty about the VERDICT, in bits.
--
-- With no seam this is just the binary entropy of the function, exactly as before. With
-- a seam, the requirement's uncertainty counts only to the extent the scope actually
-- bites — a requirement you will never be asked about carries no information about the
-- verdict — which is what puts scope questions ahead of requirement questions without
-- anyone having to hand-tune a heuristic to say so.
uncertainty :: Bdd -> Map Int Double -> Roots -> Double
uncertainty bdd weights rs = case rs.seamRoots of
  Nothing -> binaryEntropy (prob bdd weights rs.fnRoot)
  Just (scopeRoot, reqRoot) ->
    let pScope = prob bdd weights scopeRoot
     in binaryEntropy pScope + pScope * binaryEntropy (prob bdd weights reqRoot)

restrictRoots :: Map Int Bool -> Roots -> Bdd -> (Roots, Bdd)
restrictRoots bindings rs bdd =
  let (fnRoot', bdd1) = restrictMany bindings rs.fnRoot bdd
   in case rs.seamRoots of
        Nothing -> (Roots fnRoot' Nothing, bdd1)
        Just (scopeRoot, reqRoot) ->
          let (scopeRoot', bdd2) = restrictMany bindings scopeRoot bdd1
              (reqRoot', bdd3) = restrictMany bindings reqRoot bdd2
           in (Roots fnRoot' (Just (scopeRoot', reqRoot')), bdd3)

restrictRootsVar :: Int -> Bool -> Roots -> Bdd -> (Roots, Bdd)
restrictRootsVar v val = restrictRoots (Map.singleton v val)

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
  -- ^ The FUNCTION's truth value. Correct, and not a verdict — see 'Verdict'.
  , verdict :: Verdict
  -- ^ What may be said to a user. Switch on THIS, not on 'determined': for a seam,
  -- 'Complies' and 'NotApplicable' are both @determined = Just True@.
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
  -- ^ The FUNCTION's truth value. Correct, and not a verdict — see 'Verdict'.
  , verdict :: Verdict
  -- ^ What may be said to a user.
  , support :: Set v
  , refusedAt :: Set v
  -- ^ Where evaluation is sure to refuse, the refusing leaves ('BRefuse') it can
  -- reach first; otherwise empty.
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
  , roots :: Roots
  , bdd :: Bdd
  , lazyRoots :: Maybe (LazyRoots v)
  -- ^ Present iff the expression holds a refusing leaf ('BRefuse'). Then the plan
  -- is read off these, not off 'roots'; without one, 'roots' are what they always
  -- were, and so is every plan.
  }

compileDecisionQuery :: (Ord v) => [v] -> BoolExpr v -> CompiledDecisionQuery v
compileDecisionQuery order expr =
  let vToIdx = Map.fromList (zip order [0 ..])
      (fnRoot, bdd0) = compile vToIdx expr emptyBdd
      -- Compile the seam's two sides as roots of their own. Recompiling them is
      -- near-free — the diagram is hash-consed, so every node comes straight back out
      -- of the unique table — and it buys us the one thing `fnRoot` threw away.
      (seamRoots, bdd1) = case expr of
        BImplies scope requirement ->
          let (scopeRoot, bddS) = compile vToIdx scope bdd0
              (reqRoot, bddR) = compile vToIdx requirement bddS
           in (Just (scopeRoot, reqRoot), bddR)
        _ -> (Nothing, bdd0)
      (lazyRoots, bdd2)
        | hasRefusal expr =
            let (fnLazy, bddL) = compileLazy vToIdx expr bdd1
                (seamLazy, bddS) = case expr of
                  BImplies scope requirement ->
                    let (s, b1) = compileLazy vToIdx scope bddL
                        (r, b2) = compileLazy vToIdx requirement b1
                     in (Just (s, r), b2)
                  _ -> (Nothing, bddL)
             in (Just (LazyRoots fnLazy seamLazy), bddS)
        | otherwise = (Nothing, bdd1)
   in CompiledDecisionQuery
        { varOrder = order
        , vToIdx
        , idxToV = Map.fromList (zip [0 ..] order)
        , roots = Roots fnRoot seamRoots
        , bdd = bdd2
        , lazyRoots
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
    -- Read as a variable here, so that 'roots' stay well-formed; with a refusing
    -- leaf in it, an expression is planned from 'lazyRoots' instead.
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
    -- Truth-functionally exact, and shape-destroying — which is why the sides are also
    -- kept whole, above. A nested seam gets only this, and rightly: it has no verdict.
    BImplies scope requirement ->
      \bdd ->
        let (scopeId, bdd1) = compile vToIdx scope bdd
            (negScopeId, bdd2) = neg scopeId bdd1
            (reqId, bdd3) = compile vToIdx requirement bdd2
         in apply OpOr negScopeId reqId bdd3

-- | Make the leaves for these variables refusing leaves ('BRefuse').
refusing :: (Ord v) => Set v -> BoolExpr v -> BoolExpr v
refusing vs = go
 where
  go = \case
    BVar v | v `Set.member` vs -> BRefuse v
    BNot e -> BNot (go e)
    BAnd es -> BAnd (map go es)
    BOr es -> BOr (map go es)
    BImplies p q -> BImplies (go p) (go q)
    e -> e

hasRefusal :: BoolExpr v -> Bool
hasRefusal = \case
  BRefuse _ -> True
  BNot e -> hasRefusal e
  BAnd es -> any hasRefusal es
  BOr es -> any hasRefusal es
  BImplies p q -> hasRefusal p || hasRefusal q
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

-- | The lazy readings of the function and, for a seam, of its two sides
-- (see 'Roots').
data LazyRoots v = LazyRoots
  { fnLazy :: !(Lazy v)
  , seamLazy :: !(Maybe (Lazy v, Lazy v))
  }
  deriving stock (Eq, Show)

-- | Read an expression as evaluation reads it: left to right, stopping as soon
-- as the answer is known (@L4.EvaluateLazy.Machine.connectiveLeft@). So
-- @a AND b@ is FALSE wherever @a@ is, whatever @b@ would do, and refuses where
-- @a@ refuses, or @a@ is TRUE and @b@ refuses; @OR@ and @IMPLIES@ likewise. With
-- no refusing leaf this agrees with the classical diagram everywhere; with one,
-- it is what makes the plan and evaluation give the same answer in the order
-- the rule is written, which R7 records rather than removes.
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
  BImplies p q -> \bdd ->
    let (lp, bdd1) = compileLazy vToIdx p bdd
        (lq, bdd2) = compileLazy vToIdx q bdd1
     in lazyImplies lp lq bdd2
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

-- | @p IMPLIES q@: TRUE where @p@ is FALSE, or both are TRUE; FALSE where @p@ is
-- TRUE and @q@ FALSE; refusing where @p@ refuses, or @p@ is TRUE and @q@ refuses.
lazyImplies :: (Ord v) => Lazy v -> Lazy v -> Bdd -> (Lazy v, Bdd)
lazyImplies p q bdd0 =
  let (tt, bdd1) = apply OpAnd p.onTrue q.onTrue bdd0
      (t, bdd2) = apply OpOr p.onFalse tt bdd1
      (f, bdd3) = apply OpAnd p.onTrue q.onFalse bdd2
      (r, bdd4) = thenRefuses p.onTrue p.refusesAt q.refusesAt bdd3
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

restrictLazyRoots :: Map Int Bool -> LazyRoots v -> Bdd -> (LazyRoots v, Bdd)
restrictLazyRoots bindings lr bdd0 =
  let (fn', bdd1) = restrictLazy bindings lr.fnLazy bdd0
   in case lr.seamLazy of
        Nothing -> (LazyRoots fn' Nothing, bdd1)
        Just (s, r) ->
          let (s', bdd2) = restrictLazy bindings s bdd1
              (r', bdd3) = restrictLazy bindings r bdd2
           in (LazyRoots fn' (Just (s', r')), bdd3)

lazyDetermined :: Lazy v -> Maybe Bool
lazyDetermined l
  | l.onTrue == 1 = Just True
  | l.onFalse == 1 = Just False
  | otherwise = Nothing

lazyRefused :: Lazy v -> Bool
lazyRefused l = l.onTrue == 0 && l.onFalse == 0

-- | 'verdictOf', read lazily. Where evaluation is sure to refuse there is no
-- truth value to report, so the verdict is 'Undetermined', with nothing left to
-- ask, and 'refusedAt' says where. The function is asked first, since a seam can
-- refuse whichever way a scope still open comes out (@(x OR r) IMPLIES r@).
lazyVerdictOf :: LazyRoots v -> Verdict
lazyVerdictOf lr
  | lazyRefused lr.fnLazy = Undetermined
  | otherwise = case lr.seamLazy of
      Nothing -> case lazyDetermined lr.fnLazy of
        Just True -> Holds
        Just False -> Fails
        Nothing -> Undetermined
      Just (scope, requirement) -> case lazyDetermined scope of
        Just False -> NotApplicable
        Just True -> case lazyDetermined requirement of
          Just True -> Complies
          Just False -> InBreach
          Nothing -> Undetermined
        Nothing -> Undetermined

-- | The variables still worth asking about: those the outcome still turns on.
-- For a seam, the requirement's only while the scope can still be TRUE; none
-- once evaluation is sure to refuse.
lazySupportIdxOf :: Bdd -> LazyRoots v -> Set Int
lazySupportIdxOf bdd lr = case lr.seamLazy of
  _ | lazyRefused lr.fnLazy -> Set.empty
  Nothing -> sides lr.fnLazy
  Just (scope, requirement) ->
    sides scope
      <> if scope.onTrue == 0
        then Set.empty
        else sides requirement
 where
  sides l = support l.onTrue bdd <> support l.onFalse bdd

-- | The refusing leaves evaluation can still reach first.
lazyRefusedAt :: Lazy v -> Set v
lazyRefusedAt l = Map.keysSet (Map.filter (/= 0) l.refusesAt)

-- | 'uncertainty' over the three outcomes, TRUE, FALSE and a refusal. With no
-- chance of a refusal it is the binary entropy 'uncertainty' takes.
lazyUncertainty :: Bdd -> Map Int Double -> LazyRoots v -> Double
lazyUncertainty bdd weights lr = case lr.seamLazy of
  Nothing -> entropy3 lr.fnLazy
  Just (scope, requirement) ->
    entropy3 scope + prob bdd weights scope.onTrue * entropy3 requirement
 where
  entropy3 l =
    let pT = prob bdd weights l.onTrue
        pF = prob bdd weights l.onFalse
     in sum [negate p * logBase 2 p | p <- [pT, pF, 1 - pT - pF], p > 1e-12]

-- | Rank the still-unknown atoms by information gain about the outcome, given
-- the current bindings and per-atom priors @P(atom = TRUE)@ (default 0.5 when a
-- prior is absent). This subsumes the old "does answering it settle the
-- result?" heuristic — a variable that determines the outcome drives a branch to
-- a terminal so its entropy is 0, i.e. maximal gain — while also crediting a
-- variable that merely shrinks the remaining possibility space. Mirror of the
-- info-gain @rank@ in @decision-query.ts@ (lines 148-206). Ties break by variable
-- order for determinism.
queryDecision :: (Ord v) => CompiledDecisionQuery v -> Map v Double -> Map v Bool -> DecisionQueryResult v
queryDecision compiled priors bindings = case compiled.lazyRoots of
  Just lr -> queryDecisionLazy compiled lr priors bindings
  Nothing -> queryDecisionClassical compiled priors bindings

queryDecisionClassical :: (Ord v) => CompiledDecisionQuery v -> Map v Double -> Map v Bool -> DecisionQueryResult v
queryDecisionClassical compiled priors bindings =
  let idxBindings =
        Map.fromList
          [ (idx, b)
          | (v, b) <- Map.toList bindings
          , Just idx <- [Map.lookup v compiled.vToIdx]
          ]
      (restricted, bdd1) = restrictRoots idxBindings compiled.roots compiled.bdd
      -- Priors re-keyed to BDD indices, exactly as robdd.ts's weightByIndex.
      weightByIndex =
        Map.fromList
          [ (idx, w)
          | (v, w) <- Map.toList priors
          , Just idx <- [Map.lookup v compiled.vToIdx]
          ]
      -- Current uncertainty about the VERDICT, in bits.
      priorEntropy = uncertainty bdd1 weightByIndex restricted
      supportVs = varsOf (supportIdxOf bdd1 restricted)
      varsOf idxs =
        Set.fromList
          [ v
          | idx <- Set.toList idxs
          , Just v <- [Map.lookup idx compiled.idxToV]
          ]
      outcomeOf bdd rs =
        QueryOutcome
          { determined = determinedFromRoot rs.fnRoot
          , verdict = verdictOf rs
          , support = varsOf (supportIdxOf bdd rs)
          , refusedAt = Set.empty
          }
      -- Per support variable, compute both its impact and its info-gain score
      -- from the same restriction (mirrors the single loop in decision-query.ts).
      perVar v =
        case Map.lookup v compiled.vToIdx of
          Nothing -> error "Internal error: var not found in order"
          Just idx ->
            let (rsT, bddT) = restrictRootsVar idx True restricted bdd1
                (rsF, bddF) = restrictRootsVar idx False restricted bdd1
                impactV =
                  VarImpact
                    { ifTrue = outcomeOf bddT rsT
                    , ifFalse = outcomeOf bddF rsF
                    }
                w = Map.findWithDefault 0.5 idx weightByIndex
                -- Expected posterior entropy after asking this variable, weighted
                -- by how likely each answer is; info gain = prior - expected.
                expectedPosterior =
                  w * uncertainty bddT weightByIndex rsT
                    + (1 - w) * uncertainty bddF weightByIndex rsF
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
        { determined = determinedFromRoot restricted.fnRoot
        , verdict = verdictOf restricted
        , support = supportVs
        , refusedAt = Set.empty
        , ranked = rankedVars
        , impact = impactMap
        , scores = scoresMap
        }

-- | 'queryDecisionClassical', read lazily ('compileLazy'), for an expression
-- that holds a refusing leaf. The same shape, step for step; what differs is
-- what the diagrams say. A binding to a refusing leaf changes nothing, since
-- evaluation never takes one.
queryDecisionLazy :: (Ord v) => CompiledDecisionQuery v -> LazyRoots v -> Map v Double -> Map v Bool -> DecisionQueryResult v
queryDecisionLazy compiled lazyRoots priors bindings =
  let idxBindings =
        Map.fromList
          [ (idx, b)
          | (v, b) <- Map.toList bindings
          , Just idx <- [Map.lookup v compiled.vToIdx]
          ]
      (restricted, bdd1) = restrictLazyRoots idxBindings lazyRoots compiled.bdd
      weightByIndex =
        Map.fromList
          [ (idx, w)
          | (v, w) <- Map.toList priors
          , Just idx <- [Map.lookup v compiled.vToIdx]
          ]
      priorEntropy = lazyUncertainty bdd1 weightByIndex restricted
      supportVs = varsOf (lazySupportIdxOf bdd1 restricted)
      varsOf idxs =
        Set.fromList
          [ v
          | idx <- Set.toList idxs
          , Just v <- [Map.lookup idx compiled.idxToV]
          ]
      refusedAtOf lr
        | lazyRefused lr.fnLazy = lazyRefusedAt lr.fnLazy
        | otherwise = Set.empty
      outcomeOf bdd lr =
        QueryOutcome
          { determined = lazyDetermined lr.fnLazy
          , verdict = lazyVerdictOf lr
          , support = varsOf (lazySupportIdxOf bdd lr)
          , refusedAt = refusedAtOf lr
          }
      perVar v =
        case Map.lookup v compiled.vToIdx of
          Nothing -> error "Internal error: var not found in order"
          Just idx ->
            let (lrT, bddT) = restrictLazyRoots (Map.singleton idx True) restricted bdd1
                (lrF, bddF) = restrictLazyRoots (Map.singleton idx False) restricted bdd1
                impactV =
                  VarImpact
                    { ifTrue = outcomeOf bddT lrT
                    , ifFalse = outcomeOf bddF lrF
                    }
                w = Map.findWithDefault 0.5 idx weightByIndex
                expectedPosterior =
                  w * lazyUncertainty bddT weightByIndex lrT
                    + (1 - w) * lazyUncertainty bddF weightByIndex lrF
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
        { determined = lazyDetermined restricted.fnLazy
        , verdict = lazyVerdictOf restricted
        , support = supportVs
        , refusedAt = refusedAtOf restricted
        , ranked = rankedVars
        , impact = impactMap
        , scores = scoresMap
        }


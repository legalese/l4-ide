{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedRecordDot #-}

module L4.Decision.BooleanDecisionQuery (
  BoolExpr (..),
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
   in CompiledDecisionQuery
        { varOrder = order
        , vToIdx
        , idxToV = Map.fromList (zip [0 ..] order)
        , roots = Roots fnRoot seamRoots
        , bdd = bdd1
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
    -- Truth-functionally exact, and shape-destroying — which is why the sides are also
    -- kept whole, above. A nested seam gets only this, and rightly: it has no verdict.
    BImplies scope requirement ->
      \bdd ->
        let (scopeId, bdd1) = compile vToIdx scope bdd
            (negScopeId, bdd2) = neg scopeId bdd1
            (reqId, bdd3) = compile vToIdx requirement bdd2
         in apply OpOr negScopeId reqId bdd3

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
        , ranked = rankedVars
        , impact = impactMap
        , scores = scoresMap
        }


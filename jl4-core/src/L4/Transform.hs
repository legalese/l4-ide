-- Ad-hoc logical transformations of resolved expressions.
--
-- Ideally, these should take more type information into account.
--
module L4.Transform where

import L4.Annotation
import L4.Syntax

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Optics

simplify :: Expr Resolved -> Expr Resolved
simplify = cnf . nnf

nnf :: Expr Resolved -> Expr Resolved
nnf (Not _ e)         = neg (nnf e)
nnf (And _ e1 e2)     = And emptyAnno (nnf e1) (nnf e2)
nnf (Or _ e1 e2)      = Or emptyAnno (nnf e1) (nnf e2)
nnf (Implies _ e1 e2) = nnf (implies e1 e2)
nnf (Where ann e ds)  = Where ann (nnf e) ds
nnf e                 = e

cnf :: Expr Resolved -> Expr Resolved
cnf (And _ (And _ e1 e2) e3) = cnf (And emptyAnno e1 (And emptyAnno e2 e3))
cnf (And _ e1 e2)            = And emptyAnno (cnf e1) (cnf e2)
cnf (Or _ (Or _ e1 e2) e3)   = cnf (Or emptyAnno e1 (Or emptyAnno e2 e3))
cnf (Or _ e1 e2)             = distr (cnf e1) (cnf e2)
cnf (Implies _ e1 e2)        = cnf (implies e1 e2)
cnf (Where ann e ds)         = Where ann (cnf e) ds
cnf e                        = e

-- | Try to exploit distributivity laws.
distr :: Expr Resolved -> Expr Resolved -> Expr Resolved
distr (And _ e1 e2) e3 = And emptyAnno (distr e1 e3) (distr e2 e3)
distr e1 (And _ e2 e3) = And emptyAnno (distr e1 e2) (distr e1 e3)
distr e1 e2            = Or emptyAnno e1 e2

-- | Try to push down a negation.
neg :: Expr Resolved -> Expr Resolved
neg (Not _ e)         = e
neg (And _ e1 e2)     = Or emptyAnno (neg e1) (neg e2)
neg (Or _ e1 e2)      = And emptyAnno (neg e1) (neg e2)
neg (Implies _ e1 e2) = neg (implies e1 e2)
-- the following would be great, but we'd have to check the types
-- neg (Equals _ e1 e2)  = equivExpr e1 e2
-- neg (IfThenElse _ e1 e2 e3) = ...
neg (Where ann e ds)  = Where ann (neg e) ds
neg e                 = Not emptyAnno e

-- | Classically interpret implication.
implies :: Expr Resolved -> Expr Resolved -> Expr Resolved
implies e1 e2 = Or emptyAnno (Not emptyAnno e1) e2

-- | Classically interpret equivalence.
equiv :: Expr Resolved -> Expr Resolved -> Expr Resolved
equiv e1 e2 = And emptyAnno (implies e1 e2) (implies e2 e1)


-- ---------------------------------------------------------------------------
-- Referential transparency for the static analyses
-- ---------------------------------------------------------------------------

-- | Substitute zero-arity local @WHERE@ / @LET … IN@ bindings into the expression
-- that uses them, to a fixed point.
--
-- L4 /evaluates/ referentially transparently: @x WHERE x MEANS e@ and @e@ give the
-- same answer. The static analyses did not agree, because the ladder IR turns a
-- reference to a local binding into an opaque atom, and two atoms that happen to be
-- the same proposition are not known to be the same. So
--
-- > DECIDE flat   IF m AND NOT m                       -- 1 atom, [unsat]
-- > DECIDE hidden IF m AND NOT e WHERE e MEANS m        -- 2 atoms, no findings
--
-- reported differently, although @hidden@ is top-level, /is/ analysed, and means
-- exactly what @flat@ means. Running this pass first makes them the same expression,
-- after which the existing atom coalescing collapses the two occurrences and the
-- existing analysis finds the contradiction. No analysis logic changes.
--
-- See @specs/todo/WHERE-INLINING-SPEC.md@. Four things are deliberately left opaque —
-- bindings that take parameters (substituting under arguments is beta reduction, which
-- wants a capture-avoidance story), bindings that are recursive or mutually recursive
-- (substitution would not terminate), @ASSUME@ (there is no definiens), and anything
-- referenced with a non-empty argument list.
inlineLocalBindings :: Expr Resolved -> Expr Resolved
inlineLocalBindings = transformOf (gplate @(Expr Resolved)) step
  where
    -- `transformOf` is bottom-up, so an inner WHERE is already inlined by the time
    -- its enclosing one is considered.
    step :: Expr Resolved -> Expr Resolved
    step = \ case
      Where ann body ds -> rebuild (\ b ds' -> Where ann b ds') body ds
      LetIn ann ds body -> rebuild (\ b ds' -> LetIn ann ds' b) body ds
      e                 -> e

    rebuild
      :: (Expr Resolved -> [LocalDecl Resolved] -> Expr Resolved)
      -> Expr Resolved -> [LocalDecl Resolved] -> Expr Resolved
    rebuild mk body ds
      | Map.null usable = mk body ds
      | null survivors  = substRefs usable body
      | otherwise       = mk (substRefs usable body) survivors
      where
        cands     = Map.fromList [ p | Just p <- map candidate ds ]
        usable    = expandAll (Map.withoutKeys cands (selfReaching cands))
        survivors =
          [ d
          | d <- ds
          , maybe True (\ (u, _) -> not (Map.member u usable)) (candidate d)
          ]

    -- A local declaration that may be substituted: a DECIDE / MEANS taking no
    -- parameters. The empty parameter list is the arity guard, and it is
    -- load-bearing — the interactive `inlineExpr` in LSP.L4.Viz.Ladder documents
    -- itself as inlining "App of no args" but does not actually check, so it would
    -- replace `f x y` with f's bare definiens and drop the arguments.
    candidate :: LocalDecl Resolved -> Maybe (Unique, Expr Resolved)
    candidate = \ case
      LocalDecide _ (MkDecide _ _ (MkAppForm _ n [] _) rhs) -> Just (getUnique n, rhs)
      _                                                     -> Nothing

    -- Which candidates can reach themselves through the others: self-recursive and
    -- mutually recursive bindings, whose substitution would not terminate. Removing
    -- them leaves an acyclic reference graph, which is what lets `expandAll` stop.
    selfReaching :: Map.Map Unique (Expr Resolved) -> Set.Set Unique
    selfReaching m = Set.fromList [ u | u <- Map.keys m, u `Set.member` reachable u ]
      where
        edges u = maybe Set.empty (Set.intersection (Map.keysSet m) . refsIn) (Map.lookup u m)
        reachable = go Set.empty . Set.toList . edges
        go seen []       = seen
        go seen (u : us)
          | u `Set.member` seen = go seen us
          | otherwise           = go (Set.insert u seen) (Set.toList (edges u) ++ us)

    -- The uniques this expression refers to with an empty argument list.
    refsIn :: Expr Resolved -> Set.Set Unique
    refsIn = foldMapOf (cosmosOf (gplate @(Expr Resolved))) $ \ case
      App _ r [] -> Set.singleton (getUnique r)
      _          -> Set.empty

    -- Substitute candidates into each other until none refers to another. The graph
    -- is acyclic by construction, so each round strictly reduces the number of
    -- remaining candidate references and the iteration count is bounded.
    expandAll :: Map.Map Unique (Expr Resolved) -> Map.Map Unique (Expr Resolved)
    expandAll m0 = go (Map.size m0) m0
      where
        go n m
          | n <= (0 :: Int) = m
          | m' == m         = m
          | otherwise       = go (n - 1) m'
          where m' = Map.map (substRefs m) m

    -- Replace `App _ r []` by the definiens bound to r's unique.
    substRefs :: Map.Map Unique (Expr Resolved) -> Expr Resolved -> Expr Resolved
    substRefs m
      | Map.null m = id
      | otherwise  = transformOf (gplate @(Expr Resolved)) $ \ e -> case e of
          App _ r [] -> Map.findWithDefault e (getUnique r) m
          _          -> e

-- | 'inlineLocalBindings' over a decision's body, for consumers holding a 'Decide'.
inlineLocalBindingsInDecide :: Decide Resolved -> Decide Resolved
inlineLocalBindingsInDecide (MkDecide ann tysig appform body) =
  MkDecide ann tysig appform (inlineLocalBindings body)

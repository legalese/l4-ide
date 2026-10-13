-- Ad-hoc logical transformations of resolved expressions.
--
-- Ideally, these should take more type information into account.
--
module L4.Transform where

import L4.Annotation
import L4.Syntax

import Data.List (sort)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Optics

import Data.Maybe (isJust)
import Data.Text (Text)

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

-- | Substitute local @WHERE@ / @LET … IN@ bindings into the expression that uses
-- them, to a fixed point.
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
-- A binding that takes parameters is substituted too, by beta reduction: a call
-- whose argument count equals the binding's parameter count is replaced by the
-- binding's body with the arguments put in place of the parameters (see
-- 'unfoldOnce'). A reference at any other arity — the helper passed as a value, or
-- partially applied — is left alone, and so is the binding it needs.
--
-- See @specs/todo/WHERE-INLINING-SPEC.md@ (§5, and §9 for parameters). Three things
-- are deliberately left opaque — bindings that are recursive or mutually recursive
-- (substitution would not terminate), @ASSUME@ (there is no definiens), and a
-- binding that applies one of its own parameters as a function (see
-- 'unfoldableDecide').
inlineLocalBindings :: Expr Resolved -> Expr Resolved
inlineLocalBindings = inlineLocalBindingsWhere (const True) . inlineGeneratedLets

-- | 'inlineLocalBindings' for a consumer that draws or analyses what comes out
-- (@l4 verify@, a call's panel, the expand gesture).
--
-- The LETs a rule written as clauses generates are read first, as the
-- CONSIDER the clauses stand for ('inlineLetsForViz'), and only then is every
-- other local binding put in. The other order walks the clauses' shared
-- fall-through as a tree, once for every branch that reaches it, before
-- anything prunes it: a sixteen-row table of two enums took 18 s and 2.9 GB in
-- @l4 verify@, and twenty-five rows did not finish in 4 GiB, where its CONSIDER
-- written by hand takes a tenth of a second.
--
-- 'Nothing' when the expression holds clauses too long to read through
-- ('letInliningNodeBudget'), and what then is the caller's to say: the ladder
-- refuses a rule written as clauses, @l4 verify@ leaves a call to one as a box
-- it does not open, and the IDE does not offer to expand it. The raw expression
-- is no fallback: drawn as it is, it puts the clauses' LETs in a leaf whose key
-- reads them through, which does not finish. An expression with no clauses in
-- it is read exactly as 'inlineLocalBindings' reads it.
inlineLocalBindingsForDrawing :: Expr Resolved -> Maybe (Expr Resolved)
inlineLocalBindingsForDrawing e
  | not (hasGeneratedLets e) = Just (inlineLocalBindingsWhere (const True) e)
  | otherwise = case inlineLetsForViz e of
      Right asConsider -> Just (inlineLocalBindingsWhere (const True) asConsider)
      Left _      -> Nothing

-- | Do the clauses in this expression, if any, read through
-- ('inlineLocalBindingsForDrawing' would answer)? Only the clauses are read,
-- under the same bound, and nothing else is put in, so this costs no more than
-- 'letInliningNodeBudget' nodes.
clausesReadThrough :: Expr Resolved -> Bool
clausesReadThrough e = not (hasGeneratedLets e) || either (const False) (const True) (inlineLetsForViz e)

-- | Does this expression hold a LET the clause desugarer generated?
hasGeneratedLets :: Expr Resolved -> Bool
hasGeneratedLets = anyOf (cosmosOf (gplate @(Expr Resolved))) isGeneratedLet
  where
    isGeneratedLet = \ case
      LetIn _ ds@(_ : _) _ -> all generatedBinding ds
      _                    -> False
    generatedBinding = \ case
      LocalDecide _ (MkDecide a _ _ _) -> case view annPmSynthetic a of
        Just (PmFallthrough _) -> True
        Just (PmUnreachable _) -> True
        _                      -> False
      _ -> False

-- | Substitute the @LET@s the clause desugarer generates (the clauses not yet
-- tried, 'PmFallthrough') into the CONSIDERs that refer to them.
--
-- 'inlineLocalBindingsWhere' does this too, but does work on each @LET@ in
-- proportion to everything under it, and a group of @n@ clauses is @n@ nested
-- @LET@s, so it takes time quadratic in @n@: 30 s for 300 clauses. These
-- bindings are all of one shape (no parameters, used from the CONSIDERs of
-- their own body) and a plain substitution takes time linear in the size of
-- the body it goes into.
inlineGeneratedLets :: Expr Resolved -> Expr Resolved
inlineGeneratedLets = transformOf (gplate @(Expr Resolved)) \ case
  LetIn _ ds body
    | not (null ds), Just defs <- traverse generatedDef ds -> substitute defs body
  e -> e
  where
    generatedDef = \ case
      LocalDecide _ (MkDecide a _ (MkAppForm _ n [] _) rhs)
        | Just m <- view annPmSynthetic a, isLater m -> Just (getUnique n, rhs)
      _ -> Nothing
    isLater = \ case
      PmFallthrough _ -> True
      PmUnreachable _ -> True
      PmConsider{}    -> False
    substitute defs = transformOf (gplate @(Expr Resolved)) \ case
      App site r [] | Just rhs <- lookup (getUnique r) defs -> withTypeOfSite site rhs
      e -> e

-- | 'inlineLocalBindings', but only at the @WHERE@ \/ @LET@ nodes the predicate
-- accepts. Every other binding is left exactly as written.
inlineLocalBindingsWhere :: (Expr Resolved -> Bool) -> Expr Resolved -> Expr Resolved
inlineLocalBindingsWhere wanted = transformOf (gplate @(Expr Resolved)) step
  where
    -- `transformOf` is bottom-up, so an inner WHERE is already inlined by the time
    -- its enclosing one is considered.
    step :: Expr Resolved -> Expr Resolved
    step = \ case
      e@(Where ann body ds) | wanted e -> rebuild (\ b ds' -> Where ann b ds') body ds
      e@(LetIn ann ds body) | wanted e -> rebuild (\ b ds' -> LetIn ann ds' b) body ds
      e                 -> e

    rebuild
      :: (Expr Resolved -> [LocalDecl Resolved] -> Expr Resolved)
      -> Expr Resolved -> [LocalDecl Resolved] -> Expr Resolved
    rebuild mk body ds
      | Map.null usable = mk body ds
      | null survivors  = body'
      | otherwise       = mk body' survivors
      where
        cands  = Map.fromList [ p | LocalDecide _ d <- ds, Just p <- [unfoldableDecide d] ]
        usable = closeUnder (pruneRecursive cands)
        body'  = unfoldOnce usable body
        -- A usable binding is dropped only once nothing refers to it any more. For
        -- a zero-arity binding that is always, because every reference has arity
        -- zero; a parameterised one can still be referenced at another arity.
        survivors =
          [ d
          | d <- ds
          , case d of
              LocalDecide _ dec
                | Just (u, _) <- unfoldableDecide dec
                , Map.member u usable -> u `Set.member` stillReferenced
              _ -> True
          ]
        stillReferenced = grow (callees body' <> foldMap callees kept)
          where
            kept = [ e | LocalDecide _ dec <- ds
                       , Just (u, MkUnfoldable _ e) <- [unfoldableDecide dec]
                       , not (Map.member u usable) ]
                   ++ [ e | LocalDecide _ dec <- ds, Nothing <- [unfoldableDecide dec]
                          , MkDecide _ _ _ e <- [dec] ]
            grow seen =
              let more = foldMap (\ (MkUnfoldable _ e) -> callees e)
                                 (Map.restrictKeys usable seen)
                  seen' = seen <> more
               in if seen' == seen then seen else grow seen'

-- | Undo the clause desugaring for a consumer that draws the expression's
-- structure (the ladder, the query plan): the @LET@s that bind "the clauses not
-- yet tried" ('PmFallthrough') are substituted into the CONSIDERs that refer to
-- them, so that a BOOLEAN rule written as DECIDE clauses is the same expression
-- as the nested CONSIDER a drafter would have written by hand.
--
-- Only the @LET@s the desugarer generated are read through. A @LET@ the drafter
-- wrote is left exactly as written (it is one leaf of the ladder, as it was
-- before clauses were read through): reading it through copies its binding to
-- every place it is used, and a chain of @LET@s that each use the one before
-- twice grows past anything that can be drawn.
--
-- The generated CONSIDERs are then read with what their enclosing branches
-- already decided, so that a later clause does not ask again about an input an
-- earlier one has settled ('pruneGeneratedConsiders'), and the nested
-- CONSIDERs the desugarer generates for one input are joined into one, as a
-- drafter writes it: @CONSIDER c WHEN A THEN x OTHERWISE
-- CONSIDER c WHEN B THEN y@ is @CONSIDER c WHEN A THEN x WHEN B THEN y@ (the
-- first match wins in both). Only generated CONSIDERs on the same input are
-- joined; a nested CONSIDER the drafter wrote is left alone.
--
-- A group of several inputs refers to the same later clauses from more than one
-- branch, so inlining copies them. Pruning drops the copies whose answer the
-- branch around them already settles, but not the rest (behind a pattern that
-- binds a name, say), and a long group of many inputs could still copy those
-- exponentially. @Left n@ means the expression grew past
-- 'letInliningNodeBudget' (it had reached @n@), and the caller should not draw
-- it.
inlineLetsForViz :: Expr Resolved -> Either Int (Expr Resolved)
inlineLetsForViz e
  | genSize > letInliningNodeBudget = Left genSize
  | otherwise = Right (joinGeneratedConsiders generated)
  where
    generated = pruneGeneratedConsiders (inlineGeneratedLets e)
    -- Lazy on purpose: only the first budget + 1 nodes are built.
    genSize = length (take (letInliningNodeBudget + 1) (nodes generated))
    nodes x = x : concatMap nodes (toListOf (gplate @(Expr Resolved)) x)

-- | The size, in expression nodes, past which the generated @LET@s of a clause
-- group are not inlined for drawing. It bounds the work of drawing;
-- 'clauseGroupLadderBudget' is the limit on what is drawn.
letInliningNodeBudget :: Int
letInliningNodeBudget = 20000

-- | The most nodes a ladder may have when the rule was written as DECIDE
-- clauses. It bounds the drawing, not the work of planning what is drawn.
--
-- It was chosen from plans measured through jl4-service on 539cad5fd, before
-- 'pruneGeneratedConsiders', on randomly generated groups over three to six
-- BOOLEAN inputs: 128 nodes gave a 0.16 MB plan in 0.5 s, 271 nodes 2.1 MB in
-- 1.1 s, 811 nodes 29 MB in 3.9 s and 3441 nodes 325 MB in 20 s. With
-- eda1e3be5 merged in, 598 single-column rows (300 nodes) give a 23 MB plan in
-- about a second.
--
-- A plan's cost is not a function of the ladder's size. A table of an enum of
-- 20 values by a BOOLEAN input draws 61 nodes and took 11 to 21 s of CPU to plan
-- (11 and 18 s here, 21 s in review with the machine's load at 20), and of 24
-- values, 73 nodes and about four minutes (measured in review). The same rule
-- written by hand with the same patterns costs the same; with @b@ in place of
-- the pattern @TRUE@ it plans in 0.01 s, because its 20 leaves @b EQUALS TRUE@
-- share one atomId but not one unique, and the plan makes each a variable of
-- its own. This limit does not bound that.
--
-- On 708c40f72, before #626 and #629, naming the atoms (R3) also made large
-- ladders far slower whoever wrote the rule: @l4 verify@ on 200 @n EQUALS i@
-- disjuncts took 13 s, against 0.44 s with those merged in.
clauseGroupLadderBudget :: Int
clauseGroupLadderBudget = 300

-- | Was this rule written as DECIDE clauses? The parser records the clauses as
-- written on the decision it compiles them to ('annPmMatrix'), and that mark
-- stays on the decision whatever is later put into its body: a rule written by
-- hand that has a call to a clause group unfolded into it (the IDE's
-- @l4/inlineExprs@) is still a rule written by hand.
writtenAsClauses :: Decide Resolved -> Bool
writtenAsClauses (MkDecide ann _ _ _) = isJust (view annPmMatrix ann)

-- | Join a generated CONSIDER whose last branch is an OTHERWISE holding another
-- generated CONSIDER on the same input. Bottom-up, so a run of three joins.
joinGeneratedConsiders :: Expr Resolved -> Expr Resolved
joinGeneratedConsiders = transformOf (gplate @(Expr Resolved)) \ case
  Consider ann s brs
    | generated ann
    , Just (front, MkBranch _ (Otherwise _) (Consider ann' s' brs')) <- unsnoc' brs
    , generated ann'
    , sameInput s s' -> Consider ann s (front <> brs')
  e -> e
  where
    generated a = case view annPmSynthetic a of
      Just PmConsider{} -> True
      _                 -> False
    sameInput a b = case (a, b) of
      (App _ r [], App _ r' []) -> getUnique r == getUnique r'
      _                         -> False
    unsnoc' xs = case xs of
      [] -> Nothing
      _  -> Just (init xs, last xs)

-- | Drop what the enclosing generated branches make impossible.
--
-- The clause desugarer is a backtracking automaton: a clause that fails on a
-- later column falls through to the clauses after it, which test the earlier
-- columns again. Once 'inlineGeneratedLets' has put the fall-through in, the
-- branch @WHEN Red@ on @c@ holds a copy of every later clause, each of which
-- asks about @c@ again. Drawn as it stands, a two-column table of four rows had
-- 29 leaves where the CONSIDER a drafter writes for it has 6, and its impossible
-- limbs were findings for @l4 verify@.
--
-- So each generated CONSIDER on an input is read with what is already known
-- about that input: inside @WHEN p@, that it is @p@; after @WHEN p1 .. pn@, that
-- it is none of them. Only a constructor with no arguments, or a literal, is
-- known this way (the patterns 'L4.Viz.GuardedRows' can test for equality).
-- Under first-match, inside @WHEN p@ a generated CONSIDER on the same input
-- takes its arm for @p@ if it has one, and its OTHERWISE if not; an arm for a
-- value already excluded is never taken, and is dropped.
--
-- A WHEN whose pattern is a plain name (@DECIDE rule other a b IS a AND b@,
-- where @other@ is not the input's own name) always matches, so it is the
-- OTHERWISE, with the input put in for the name; the arms after it are never
-- tried. Any other pattern (one that binds, such as @JUST x@ or a list) is left
-- as it is, and what follows it is read without assuming it failed.
--
-- When no arm can be taken and there is no OTHERWISE, no clause matches: the
-- rule fails there. An OTHERWISE that can only lead there is dropped, which
-- fails the same way; a WHEN that can only lead there is kept, as written, since
-- dropping it would hand its value to the next arm.
--
-- Only CONSIDERs the desugarer generated are read this way. What is known is
-- forgotten inside anything that binds a name (a lambda, a LET, a WHERE), and is
-- only ever about an input written as a bare name.
pruneGeneratedConsiders :: Expr Resolved -> Expr Resolved
pruneGeneratedConsiders = total Map.empty
  where
    -- Never stuck: where pruning finds no arm can be taken, read the expression
    -- with nothing known instead, which keeps every arm.
    total :: Map.Map Unique Known -> Expr Resolved -> Expr Resolved
    total known e = case go known e of
      Just e' -> e'
      Nothing -> case go Map.empty e of
        Just e' -> e'
        Nothing -> e

    -- 'Nothing': no arm of this generated CONSIDER can be taken.
    go :: Map.Map Unique Known -> Expr Resolved -> Maybe (Expr Resolved)
    go known e = case e of
      Consider ann s brs
        | Just PmConsider{} <- view annPmSynthetic ann
        , App _ r [] <- s ->
            arms ann s (getUnique r) (Map.lookup (getUnique r) known) [] known brs
      Lam{}   -> Just (over (gplate @(Expr Resolved)) (total Map.empty) e)
      Where{} -> Just (over (gplate @(Expr Resolved)) (total Map.empty) e)
      LetIn{} -> Just (over (gplate @(Expr Resolved)) (total Map.empty) e)
      _       -> Just (over (gplate @(Expr Resolved)) (total known) e)

    -- Walk the arms of a generated CONSIDER on input @u@, about which @fact@ is
    -- known; @kept@ are the arms kept so far, in reverse.
    arms ann s u fact kept known = \ case
      [] -> finish ann s u fact kept known Nothing
      br@(MkBranch ba (When wa p) body) : rest -> case classify p of
        Ground k -> case fact of
          Just (Is k')
            | k /= k'    -> arms ann s u fact kept known rest
            | null kept  -> go known body
            | otherwise  -> Just (Consider ann s (reverse (MkBranch ba (When wa p) (total known body) : kept)))
          _
            | excluded k -> arms ann s u fact kept known rest
            | otherwise  ->
                arms ann s u (Just (IsNot (k : excludedKeys))) (MkBranch ba (When wa p) (total (Map.insert u (Is k) known) body) : kept) known rest
        Binds v -> finish ann s u fact kept known (Just (substParams [(getUnique v, s)] body))
        Uncertain mk -> case (fact, mk) of
          (Just (Is k'), Just k) | k /= k' -> arms ann s u fact kept known rest
          _ -> arms ann s u fact (over branchBody (total (withFact u fact known)) br : kept) known rest
      MkBranch _ (Otherwise _) body : _ -> finish ann s u fact kept known (Just body)
      where
        excludedKeys = case fact of
          Just (IsNot ks) -> ks
          _               -> []
        excluded k = k `elem` excludedKeys

    -- The arms are done. @other@ is what is left when none of them is taken.
    finish ann s u fact kept known other =
      let known' = withFact u fact known
       in case (kept, other) of
            ([], Nothing) -> Nothing
            ([], Just o)  -> go known' o
            (_, Nothing)  -> Just (Consider ann s (reverse kept))
            (_, Just o)   -> case go known' o of
              Nothing -> Just (Consider ann s (reverse kept))
              Just o' -> Just (Consider ann s (reverse (MkBranch emptyAnno (Otherwise emptyAnno) o' : kept)))

    withFact u fact known = maybe known (\ f -> Map.insert u f known) fact

    branchBody :: Lens' (Branch Resolved) (Expr Resolved)
    branchBody = lens (\ (MkBranch _ _ b) -> b) (\ (MkBranch a l _) b -> MkBranch a l b)

    classify :: Pattern Resolved -> PatternShape
    classify = \ case
      PatApp _ ctor []                  -> Ground (GroundCtor (getUnique ctor))
      PatApp _ ctor _                   -> Uncertain (Just (GroundCtor (getUnique ctor)))
      PatLit _ lit                      -> Ground (litKey lit)
      PatExpr _ (Lit _ lit)             -> Ground (litKey lit)
      -- EXACTLY a constructor: known only when the checker stamped the name a
      -- constructor, since a bare name here can as well be an input or a rule,
      -- which names no one value (two inputs can be equal).
      PatExpr _ (App _ r [])
        | isConstructorRef r            -> Ground (GroundCtor (getUnique r))
      PatVar _ v                        -> Binds v
      _                                 -> Uncertain Nothing

    litKey = \ case
      NumericLit _ x -> GroundNum x
      StringLit _ t  -> GroundStr t

    isConstructorRef r = case getActual r of
      MkName nameAnn _ -> case view annInfo nameAnn of
        Just (TypeInfo _ (Just Constructor)) -> True
        _                                    -> False

-- | What is known about an input inside a generated branch.
data Known = Is GroundKey | IsNot [GroundKey]

-- | A value a pattern can name exactly: a constructor with no arguments, or a
-- literal.
data GroundKey = GroundCtor Unique | GroundNum Rational | GroundStr Text
  deriving stock (Eq)

data PatternShape
  = Ground GroundKey
  | Binds Resolved
  -- ^ a plain name, which always matches
  | Uncertain (Maybe GroundKey)
  -- ^ anything else; the constructor it tests, if any

-- | A definition that a call can be unfolded into: its parameters, in order, and
-- its body.
data Unfoldable = MkUnfoldable [Unique] (Expr Resolved)
  deriving stock (Eq, Show)

-- | The unfoldable view of a @DECIDE@ / @MEANS@, keyed by the unique a call refers
-- to it by.
--
-- Refused when the body /applies/ one of its own parameters (a higher-order
-- helper, @GIVEN f IS A FUNCTION …@ called as @f x@): substituting an argument for
-- a parameter is then no longer plain replacement of a value, and this pass does
-- not attempt it.
unfoldableDecide :: Decide Resolved -> Maybe (Unique, Unfoldable)
unfoldableDecide (MkDecide _ _ (MkAppForm _ n args _) rhs)
  | anyOf (cosmosOf (gplate @(Expr Resolved))) appliesParam rhs = Nothing
  | otherwise = Just (getUnique n, MkUnfoldable (map getUnique args) rhs)
  where
    params = Set.fromList (map getUnique args)
    appliesParam = \ case
      App _ r (_ : _)  -> getUnique r `Set.member` params
      AppNamed _ r _ _ -> getUnique r `Set.member` params
      _                -> False

-- | The uniques an expression refers to as the head of an application, at any
-- arity. A bare variable is an application of arity zero, so it is included, and
-- so is the head of every named call, whether or not 'positionalCall' can read it.
callees :: Expr Resolved -> Set.Set Unique
callees = foldMapOf (cosmosOf (gplate @(Expr Resolved))) $ \ case
  App _ r _        -> Set.singleton (getUnique r)
  AppNamed _ r _ _ -> Set.singleton (getUnique r)
  Proj _ _ r       -> Set.singleton (getUnique r)
  _                -> Set.empty

-- | A call's head and its arguments in parameter order.
--
-- An 'App' is that already. A call with named arguments ('AppNamed') is read as
-- the positional call it stands for when the checker's order says its arguments
-- supply declared parameters @0 .. n-1@, each exactly once: @f WITH b IS y, a IS x@
-- is @f x y@. Every pass that unfolds a call reads it through this, so a rule
-- called by name is unfolded, counted and inlined exactly as one called
-- positionally (smucclaw/l4-ide#1033), and "L4.Viz.AtomKey" keys the two alike
-- through it too.
--
-- A projection, @e's f@, is the selector @f@ applied to @e@: that is what it
-- means, since the evaluator desugars it so (@L4.EvaluateLazy.Machine@, the
-- 'Proj' case), so a computed field read by projection is unfolded as one read
-- by its selector is. Without it, once smucclaw/l4-ide#1033's R3b keyed the two
-- spellings alike, @l4 verify@ read the field through only when the selector
-- spelling happened to come first (found by adversarial review).
--
-- 'Nothing' for anything else: a named call the checker has not ordered, and one
-- that supplies a section binder (a negative entry, 'implicitSupplyIndex'), whose
-- callee reads a name that is not among its parameters, so substituting for the
-- parameters alone would not be the call. 'Nothing' too for a call the checker
-- rejected but recovered from, whose order can still look like a permutation: an
-- argument name it could not resolve (a misspelling, a name given twice) is
-- 'OutOfScope' and was given some parameter's index, and a named call to a rule
-- that takes none has no arguments at all. The IDE draws modules with type errors
-- in them, while the author is typing, and such a call must stay a closed leaf
-- rather than open onto a meaning the checker refused (found by adversarial
-- review).
--
-- The test cannot see the callee's arity. Today every named call names every
-- parameter (the checker raises @IncompleteAppNamed@ otherwise), but if one may
-- omit a defaulted parameter (TYPICALLY-ONE-BEHAVIOUR-SPEC row W4), a call
-- supplying the first n of more parameters passes it. The unfolding passes stay
-- right, since each compares the argument count with the callee's parameters;
-- "L4.Viz.AtomKey" does not, and would key such a call as the shorter positional
-- call (found by adversarial review).
positionalCall :: Expr Resolved -> Maybe (Resolved, [Expr Resolved])
positionalCall = \ case
  App _ r args -> Just (r, args)
  Proj _ e r -> Just (r, [e])
  AppNamed _ r nes (Just order)
    | not (null nes)
    , not (any (\ (MkNamedExpr _ n _) -> isOutOfScope n) nes)
    , sort order == [0 .. length nes - 1] ->
        Just (r, [ x | i <- [0 .. length nes - 1], (MkNamedExpr _ _ x, j) <- zip nes order, j == i ])
  _ -> Nothing
  where
    isOutOfScope = \ case
      OutOfScope {} -> True
      _             -> False

-- | Remove the definitions that can reach themselves through the others:
-- self-recursive and mutually recursive ones, whose unfolding would not
-- terminate. What is left has an acyclic reference graph, which is what lets
-- 'closeUnder' and 'unfoldCalls' stop.
pruneRecursive :: Map.Map Unique Unfoldable -> Map.Map Unique Unfoldable
pruneRecursive m = Map.withoutKeys m (Set.fromList [ u | u <- Map.keys m, u `Set.member` reachable u ])
  where
    edges u = maybe Set.empty (\ (MkUnfoldable _ e) -> Set.intersection (Map.keysSet m) (callees e)) (Map.lookup u m)
    reachable = go Set.empty . Set.toList . edges
    go seen []       = seen
    go seen (u : us)
      | u `Set.member` seen = go seen us
      | otherwise           = go (Set.insert u seen) (Set.toList (edges u) ++ us)

-- | Unfold the definitions into each other until none calls another. The graph is
-- acyclic ('pruneRecursive'), so each round strictly reduces the number of
-- remaining calls and the iteration count is bounded.
closeUnder :: Map.Map Unique Unfoldable -> Map.Map Unique Unfoldable
closeUnder m0 = go (Map.size m0) m0
  where
    go n m
      | n <= (0 :: Int) = m
      | m' == m         = m
      | otherwise       = go (n - 1) m'
      where m' = Map.map (\ (MkUnfoldable ps e) -> MkUnfoldable ps (unfoldOnce m e)) m

-- | One round of beta reduction. Every call @App _ r args@ whose callee is in the
-- map /and whose argument count equals the callee's parameter count/ is replaced
-- by the callee's body with each argument put in place of its parameter. A call
-- with named arguments, or a projection, is read as its positional call first
-- ('positionalCall').
--
-- The arity check is the guard, and it is load-bearing: a reference at another
-- arity (a helper passed as a value) is not a call and is left alone.
--
-- Capture cannot happen. Names are resolved to 'Unique's before this runs, and a
-- parameter's unique belongs to its own definition, so an argument — built in the
-- caller's scope — cannot contain a parameter of the callee, and a binder inside
-- the callee's body cannot bind anything the argument refers to.
--
-- 'transformOf' is bottom-up and does not revisit what it returns, so a body
-- substituted here keeps its own calls for the next round.
unfoldOnce :: Map.Map Unique Unfoldable -> Expr Resolved -> Expr Resolved
unfoldOnce m
  | Map.null m = id
  | otherwise  = transformOf (gplate @(Expr Resolved)) $ \ e -> case positionalCall e of
      Just (r, args)
        | Just (MkUnfoldable ps body) <- Map.lookup (getUnique r) m
        , length args == length ps
        -> withTypeOfSite (getAnno e) (substParams (zip ps args) body)
      _ -> e

-- | A body put in place of a call has the type the call had. The call was
-- checked against what its context expects, so that type is resolved; the
-- body's own may still be an inference variable (a @LET x BE CONSIDER ...@ is
-- inferred), which a consumer that reads types with no substitution (the
-- ladder) cannot see through.
withTypeOfSite :: Anno -> Expr Resolved -> Expr Resolved
withTypeOfSite site e = case view annInfo site of
  Just (TypeInfo ty _) -> e & annoOf % annInfo ?~ TypeInfo ty Nothing
  _                    -> e

-- | How many call sites 'unfoldOnce' would replace in this expression.
unfoldableCallSites :: Map.Map Unique Unfoldable -> Expr Resolved -> Int
unfoldableCallSites m = lengthOf (cosmosOf (gplate @(Expr Resolved)) % filtered isSite)
  where
    isSite e = case positionalCall e of
      Just (r, args)
        | Just (MkUnfoldable ps _) <- Map.lookup (getUnique r) m -> length args == length ps
      _ -> False

-- | Put each argument in place of its parameter.
substParams :: [(Unique, Expr Resolved)] -> Expr Resolved -> Expr Resolved
substParams [] = id
substParams ps = transformOf (gplate @(Expr Resolved)) $ \ e -> case e of
  App _ r [] | Just a <- lookup (getUnique r) ps -> a
  _                                              -> e

-- | Unfold calls to named definitions into an expression, round by round, until
-- none is left — the whole-program counterpart of 'inlineLocalBindings', for a
-- consumer that holds the definitions of a module and its imports.
--
-- The map must already be 'pruneRecursive'd; the fuel below is a second guard,
-- not the first. @Left n@ means the expression grew past @budget@ nodes (it had
-- reached @n@) and the caller should analyse the rule without unfolding rather
-- than not at all. @Right (e, k)@ is the unfolded expression and the number of
-- call sites replaced, counted across rounds.
unfoldCalls :: Int -> Map.Map Unique Unfoldable -> Expr Resolved -> Either Int (Expr Resolved, Int)
unfoldCalls budget m = go (Map.size m + 1) 0
  where
    go :: Int -> Int -> Expr Resolved -> Either Int (Expr Resolved, Int)
    go fuel n e
      | k == 0 || fuel <= 0 = Right (e, n)
      | size > budget       = Left size
      | otherwise           = go (fuel - 1) (n + k) e'
      where
        k    = unfoldableCallSites m e
        e'   = unfoldOnce m e
        -- Counted lazily and cut off just past the budget, so an expression that
        -- has blown up costs O(budget) to refuse rather than O(size) to measure.
        size = length (take (budget + 1) (toListOf (cosmosOf (gplate @(Expr Resolved))) e'))

-- | 'inlineLocalBindings' over a decision's body, for consumers holding a 'Decide'.
inlineLocalBindingsInDecide :: Decide Resolved -> Decide Resolved
inlineLocalBindingsInDecide (MkDecide ann tysig appform body) =
  MkDecide ann tysig appform (inlineLocalBindings body)

-- Ad-hoc logical transformations of resolved expressions.
--
-- Ideally, these should take more type information into account.
--
module L4.Transform where

import L4.Annotation
import L4.Syntax

import qualified Data.Map.Strict as Map
import Data.Maybe (isJust)
import Data.Text (Text)
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

-- | Substitute the @LET@s the clause desugarer generates (the clauses not yet
-- tried, 'PmFallthrough') into the CONSIDERs that refer to them.
--
-- These bindings are all of one shape (no parameters, used from the CONSIDERs
-- of their own body), and a group of @n@ clauses is @n@ nested @LET@s, which a
-- plain substitution reads.
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

-- | A body put in place of a reference has the type the reference had. The
-- reference was checked against what its context expects, so that type is
-- resolved; the body's own may still be an inference variable, which a
-- consumer that reads types with no substitution (the ladder) cannot see
-- through.
withTypeOfSite :: Anno -> Expr Resolved -> Expr Resolved
withTypeOfSite site e = case view annInfo site of
  Just (TypeInfo ty _) -> e & annoOf % annInfo ?~ TypeInfo ty Nothing
  _                    -> e

-- | Put each expression in place of the name it is paired with.
substParams :: [(Unique, Expr Resolved)] -> Expr Resolved -> Expr Resolved
substParams [] = id
substParams ps = transformOf (gplate @(Expr Resolved)) $ \ e -> case e of
  App _ r [] | Just a <- lookup (getUnique r) ps -> a
  _                                              -> e

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
-- group are not read through for drawing, counted on the pruned CONSIDERs
-- before those on one input are joined. It bounds the size of the pruned
-- result, which pruning cannot always keep small: it cannot settle every copy
-- (behind a pattern that binds a name, say), and a long group of many inputs
-- could still copy those exponentially. The time pruning takes follows the size
-- it reaches before the count stops it, so refusing takes about as long as
-- drawing a group of this size: the as-built spec measures that, in its
-- "Bounds".
letInliningNodeBudget :: Int
letInliningNodeBudget = 20000

-- | The most boxes a ladder may have when the rule was written as DECIDE
-- clauses and the desugarer generated something to read through
-- ('holdsGeneratedNodes'). Here a CONSIDER is drawn as one box, so a group that
-- reads through to a CONSIDER is one box, however many rows it has. A group
-- whose first clause gives an input a new name reads through to that clause's
-- result instead, and is drawn as that, so it is refused when that comes to
-- more than this many boxes: in the editor when the ladder as drawn does, and
-- in the service's query plan when the simplified ladder does (the editor's
-- does not simplify). The limit is also kept as @unstable@ has it, for when a
-- CONSIDER is drawn as rows (legalese/l4-ide#137), which is where a group of
-- many rows can draw more boxes than anyone can read.
--
-- A group whose first clause names each of its inputs as the @GIVEN@ does, or
-- is @_@, is not limited. It has nothing to read through, so its ladder is
-- that of a rule written without clauses, which is not limited either, however
-- far simplifying grows it.
clauseGroupLadderBudget :: Int
clauseGroupLadderBudget = 300

-- | Was this rule written as DECIDE clauses? The parser records the clauses as
-- written on the decision it compiles them to ('annPmMatrix'), and that mark
-- stays on the decision whatever is later put into its body.
writtenAsClauses :: Decide Resolved -> Bool
writtenAsClauses (MkDecide ann _ _ _) = isJust (view annPmMatrix ann)

-- | Does this expression hold a node the clause desugarer generated: a CONSIDER
-- it compiled clauses to ('PmConsider'), or a LET that binds the clauses not
-- yet tried? Only then is there anything to read through, and only then do the
-- limits on reading clauses through apply.
--
-- A group whose first clause names each of its inputs as the @GIVEN@ does, or is
-- @_@, has no such node. The desugarer binds the clauses after that one only so
-- that they are checked, and the checker drops them from the tree
-- ('PmUnreachable'), so the body is that clause's result, as a rule written
-- without clauses would have it. A first clause that matches every input
-- through a new name is not that: it is a test of the input, generated, with
-- the clauses after it as the other answer, so it holds a node.
holdsGeneratedNodes :: Expr Resolved -> Bool
holdsGeneratedNodes e = here || any holdsGeneratedNodes (toListOf (gplate @(Expr Resolved)) e)
  where
    here = case e of
      Consider ann _ _ -> case view annPmSynthetic ann of
        Just PmConsider{} -> True
        _                 -> False
      LetIn _ ds _ -> any generatedDecl ds
      _            -> False
    generatedDecl = \ case
      LocalDecide _ (MkDecide a _ _ _) -> isJust (view annPmSynthetic a)
      _                                -> False

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
-- asks about @c@ again. Read as it stands, it is far larger than the CONSIDER
-- a drafter writes for the same table, and it prints differently, so it is
-- named differently too (a leaf's atomId hashes its printed text).
--
-- So each generated CONSIDER on an input is read with what is already known
-- about that input: inside @WHEN p@, that it is @p@; after @WHEN p1 .. pn@, that
-- it is none of them. Only a constructor with no arguments, or a literal, is
-- known this way (the patterns that test for one value).
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
--
-- A clause whose pattern is a new name stands for the input in everything after
-- it. That is a renaming carried down and applied where a name is read, and not
-- a rewrite of the clauses after it: those are the same later clauses reached by
-- more than one way, and a rewrite for each name a clause bound rebuilt them
-- once per name, which took a minute for a table of 24 clauses of optional
-- inputs taken apart with @JUST@ and given new names for the others.
pruneGeneratedConsiders :: Expr Resolved -> Expr Resolved
pruneGeneratedConsiders = total [] Map.empty
  where
    -- Never stuck: where pruning finds no arm can be taken, read the expression
    -- with nothing known instead, which keeps every arm.
    total :: Rename -> Map.Map Unique Known -> Expr Resolved -> Expr Resolved
    total rn known e = case go rn known e of
      Just e' -> e'
      Nothing -> case go rn Map.empty e of
        Just e' -> e'
        -- Not reached: with nothing known, the first arm of a generated CONSIDER
        -- is always kept (a literal or constructor arm stays, an arm that binds
        -- is the OTHERWISE), and 'matchOne' and 'matchLast' always write one. The
        -- old code's @e@ was already renamed; this one is not.
        Nothing -> e

    -- 'Nothing': no arm of this generated CONSIDER can be taken. @rn@ puts the
    -- input in for each name a clause bound to it; it is applied where a name
    -- is read, so that an expression is not rebuilt once for every name the
    -- clauses above it bound.
    go :: Rename -> Map.Map Unique Known -> Expr Resolved -> Maybe (Expr Resolved)
    go rn known e = case e of
      Consider ann s brs
        | Just PmConsider{} <- view annPmSynthetic ann
        , App _ r [] <- s ->
            arms rn ann s (getUnique r) (Map.lookup (getUnique r) known) [] known brs
      App _ r [] | Just a <- lookup (getUnique r) rn -> Just a
      Lam{}   -> Just (over (gplate @(Expr Resolved)) (total rn Map.empty) e)
      Where{} -> Just (over (gplate @(Expr Resolved)) (total rn Map.empty) e)
      LetIn{} -> Just (over (gplate @(Expr Resolved)) (total rn Map.empty) e)
      _       -> Just (over (gplate @(Expr Resolved)) (total rn known) e)

    -- Walk the arms of a generated CONSIDER on input @u@, about which @fact@ is
    -- known; @kept@ are the arms kept so far, in reverse.
    arms rn ann s u fact kept known = \ case
      [] -> finish ann s u fact kept known Nothing
      br@(MkBranch ba (When wa p) body) : rest -> case classify p of
        Ground k -> case fact of
          Just (Is k')
            | k /= k'    -> arms rn ann s u fact kept known rest
            | null kept  -> go rn known body
            | otherwise  -> Just (Consider ann s (reverse (MkBranch ba (When wa p) (total rn known body) : kept)))
          _
            | excluded k -> arms rn ann s u fact kept known rest
            | otherwise  ->
                arms rn ann s u (Just (IsNot (k : excludedKeys))) (MkBranch ba (When wa p) (total rn (Map.insert u (Is k) known) body) : kept) known rest
        Binds v -> finish ann s u fact kept known (Just ((getUnique v, s) : rn, body))
        Uncertain mk -> case (fact, mk) of
          (Just (Is k'), Just k) | k /= k' -> arms rn ann s u fact kept known rest
          _ -> arms rn ann s u fact (over branchBody (total rn (withFact u fact known)) (renamePattern rn br) : kept) known rest
      MkBranch _ (Otherwise _) body : _ -> finish ann s u fact kept known (Just (rn, body))
      where
        excludedKeys = case fact of
          Just (IsNot ks) -> ks
          _               -> []
        excluded k = k `elem` excludedKeys

    -- The arms are done. @other@ is what is left when none of them is taken,
    -- with the renaming that holds in it.
    finish ann s u fact kept known other =
      let known' = withFact u fact known
          read' (rn', o) = go rn' known' o
       in case (kept, other) of
            ([], Nothing) -> Nothing
            ([], Just ro) -> read' ro
            (_, Nothing)  -> Just (Consider ann s (reverse kept))
            (_, Just ro)  -> case read' ro of
              Nothing -> Just (Consider ann s (reverse kept))
              Just o' -> Just (Consider ann s (reverse (MkBranch emptyAnno (Otherwise emptyAnno) o' : kept)))

    withFact u fact known = maybe known (\ f -> Map.insert u f known) fact

    -- A pattern can name an input in an expression (@EXACTLY x@), which a name
    -- bound above it stands for.
    renamePattern :: Rename -> Branch Resolved -> Branch Resolved
    renamePattern [] br = br
    renamePattern rn (MkBranch ba (When wa p) b) =
      MkBranch ba (When wa (over (gplate @(Expr Resolved)) (transformOf (gplate @(Expr Resolved)) (renameName rn)) p)) b
    renamePattern _ br = br

    renameName :: Rename -> Expr Resolved -> Expr Resolved
    renameName rn = \ case
      App _ r [] | Just a <- lookup (getUnique r) rn -> a
      e -> e

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

-- | The input put in for each name that a clause above bound to it.
type Rename = [(Unique, Expr Resolved)]

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

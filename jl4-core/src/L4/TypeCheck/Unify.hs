module L4.TypeCheck.Unify where

import Base
import qualified Base.Map as Map
import L4.Syntax
import L4.TypeCheck.Types as X

-- | Wrapper for unify that fails at this point.
-- First argument is the expected type (pushed in), the second argument is the
-- given type (pulled out).
--
expect :: ExpectationContext -> Type' Resolved -> Type' Resolved -> Check ()
expect ec expected given = do
  b <- unify expected given
  unless b $ addError (TypeMismatch ec expected given)

tryExpandTypeSynonym :: Resolved -> [Type' Resolved] -> Check (Maybe (Type' Resolved))
tryExpandTypeSynonym r args = do
  ce <- getEntityInfo r
  case ce of
    Just (KnownType _kind params (Just t)) -> do
      let substitution = Map.fromList (zipWith (\ n t' -> (getUnique n, t')) params args)
      pure (Just (substituteType substitution t))
    _ -> pure Nothing

-- | Bound on the number of type synonym expansions along a single
-- recursion path of a unification. The fuel is passed DOWN through
-- constructor children (never reset mid-walk), so every unification
-- path is finite: an infinite path must expand synonyms infinitely
-- often — between expansions we only descend into finite type
-- structure — so it runs out of fuel.
--
-- That bounds the DEPTH of a path, not the WORK. A synonym whose body
-- mentions itself twice branches twice per expansion, and a cycle of
-- such synonyms costs 2^fuel before the fuel stops it. What keeps a
-- cycle from ever being expanded is the declaration-time checks, which
-- give every synonym in a cycle no body at all:
-- 'L4.Desugar.detectTypeSynonymCycles' over the spellings in the
-- source, and 'L4.TypeCheck.quarantineResolvedSynonymCycles' over the
-- resolved bodies, for what a spelling hides. Imports do not change
-- that: modules are acyclic, and an imported module's cyclic synonyms
-- were quarantined when that module was checked. The fuel's own job is
-- the acyclic case, a chain of synonyms so long that it is not worth
-- following; it is also the last line of defence for a cycle both
-- checks miss, which stops a linear one but not a branching one.
--
-- Legitimate programs spend one unit per nested synonym expansion along
-- one path, so the bound is generous. Running out is reported as
-- 'SynonymExpansionLimit', not as a mismatch of types.
--
synonymExpansionFuel :: Int
synonymExpansionFuel = 1000

-- We leave it somewhat vague how unify treats forall-types and TYPE.
-- In general, types should be instantiated prior to unification, and
-- kind-checking should not involve unification.
--
-- Unify proceeds in multiple layers.
--
-- First, we have to look through the substitution. Why? Because an
-- inference variable that was bound while unifying an earlier sibling
-- must be seen as what it was bound to by the later ones, and because
-- we have to prevent infinite types from arising (which are usually
-- unwanted, but more importantly even, can make the system loop very
-- easily). To detect cycles, we need to know the full set of inference
-- variables that occur in the target type once we try to bind an
-- inference variable.
--
-- Note that this must be done on every recursive descent into subterms,
-- not just once at the top: unifying earlier siblings extends the
-- substitution, and later siblings have to see those bindings. This is
-- why 'unifyBase' recurses via 'unifyFuel'. (Recursing without looking
-- again allowed an inference variable occurring twice in one type, as
-- in @PAIR OF a, a@ against @PAIR OF NUMBER, STRING@, to be silently
-- rebound — accepting ill-typed programs — and allowed cyclic
-- substitutions to be built, making 'applySubst' loop.)
--
-- What it does NOT have to do is substitute the whole subtree each time.
-- 'unifyFuel' resolves only the head ('walkHead'): the children are
-- resolved when the descent reaches them, and a variable that never
-- meets anything is never resolved at all. The whole type is
-- substituted only when an inference variable is about to be bound to
-- it ('bindChecked'), because the occurs check needs every variable it
-- reaches. Substituting at every descent made unification quadratic in
-- the depth of the type: checking a generic function used fifty times
-- at a type nested 400 deep took 15.3 s, and takes 1.9 s with only the
-- head walked.
--
-- Next, we have to expand type synonyms.
-- When do we want to expand a type synonym?
--
-- Basically whenever we have ruled out the inference variable cases,
-- because if we have one inference variable against a type synonym,
-- we can just bind directly.
--
-- So we check the inference variable cases first, and then try to
-- expand in 'expandAndUnify', and once we've established we cannot
-- expand, we handle the remaining cases in 'unifyBase'.
--
-- Before all of that, 'sameUnderSubstitution' short-circuits two types
-- that are structurally identical once the substitution is read
-- through, but only in the two places where that pays: the same
-- inference variable, which must not be bound to itself, and the same
-- type synonym applied to the same arguments. The second is what keeps
-- unification linear when both sides are the same synonym application:
-- expanding a synonym whose body mentions a parameter more than once
-- (or a chain of such synonyms) duplicates work exponentially if we
-- expand first and compare later. The short-circuit does not help when
-- the two sides are *different* spellings of the same
-- exponentially-large expansion (two acyclic towers of the same shape
-- under different names, say); that residual pathology is pre-existing
-- and is reachable by an acyclic tower, not only by a cycle.
--
-- It is not tried at other type constructors, because a comparison
-- walks to the first difference, and in a type nested on the left,
-- @P OF (P OF (... a ...), a), a@, the first difference is at the
-- bottom. Tried at every level of the descent it costs the square of
-- the depth: unifying such a type 16000 deep with its instance took 15
-- times as long as 4000 deep, where 4 times is linear. Descending
-- without it visits each node once. A synonym applied to a type nested
-- on the left is still compared as a whole at every synonym on the way
-- down.
--
unify :: Type' Resolved -> Type' Resolved -> Check Bool
unify = unifyFuel synonymExpansionFuel

unifyFuel :: Int -> Type' Resolved -> Type' Resolved -> Check Bool
unifyFuel fuel t1 t2 = do
  t1' <- walkHead t1
  t2' <- walkHead t2
  unify' fuel t1' t2'

-- | Read the substitution at the head of a type only: an inference
-- variable that has been bound is replaced by what it was bound to,
-- again and again, until the head is not a bound variable. Nothing
-- below the head is looked at.
--
walkHead :: Type' Resolved -> Check (Type' Resolved)
walkHead t = do
  s <- use #substitution
  pure (walkHeadIn s t)

walkHeadIn :: Substitution -> Type' Resolved -> Type' Resolved
walkHeadIn s t@(InfVar _ _ i) = maybe t (walkHeadIn s) (Map.lookup i s)
walkHeadIn _ t                = t

-- | Unify cases for inference variables, after the heads have been
-- walked. Prevent infinite types by performing the so-called "occurs
-- check".
--
unify' :: Int -> Type' Resolved -> Type' Resolved -> Check Bool
unify' fuel t1 t2 = do
  same <- sameUnderSubstitution t1 t2
  if same then pure True else go t1 t2
  where
    go (InfVar _ann1 _pre1 i1) t2' = bindChecked i1 t2'
    go t1' (InfVar _ann2 _pre2 i2) = bindChecked i2 t1'
    go t1' t2'                     = expandAndUnify fuel t1' t2'

-- | Whether two types, heads already walked, are the same type as the
-- substitution reads them, for the cases where answering is worth a
-- comparison that can reach the bottom of the types: the same inference
-- variable, and the same type synonym. A type constructor with no
-- arguments, which is most of the leaves, is the same as itself without
-- looking it up. Anything else is left to the descent, which finds the
-- same answer node by node.
--
sameUnderSubstitution :: Type' Resolved -> Type' Resolved -> Check Bool
sameUnderSubstitution t1 t2 = case (t1, t2) of
  (InfVar _ _ i1, InfVar _ _ i2) -> pure (i1 == i2)
  (TyApp _ n1 [], TyApp _ n2 [])
    | getUnique n1 == getUnique n2 -> pure True
  (TyApp _ n1 ts1, TyApp _ n2 ts2)
    | getUnique n1 == getUnique n2
    , length ts1 == length ts2 -> do
        synonym <- isExpandableSynonym n1
        if synonym
          then do
            s <- use #substitution
            pure (plainTypeEqUnder s t1 t2)
          else pure False
  _ -> pure False

-- | Whether a type name stands for another type, that is, whether
-- expanding it can do anything. A synonym in a cycle has no body, and
-- stands for nothing.
--
isExpandableSynonym :: Resolved -> Check Bool
isExpandableSynonym r = asks \ env -> case Map.lookup (getUnique r) env.entityInfo of
  Just (_, KnownType _ _ (Just _)) -> True
  _                                -> False

-- | Bind an unbound inference variable to a type, unless the variable
-- occurs in it. The type is substituted in full first: a variable that
-- the substitution maps to something mentioning @i@ is an occurrence of
-- @i@ too.
--
bindChecked :: Int -> Type' Resolved -> Check Bool
bindChecked i t = do
  t' <- applySubst t
  if i `elem` infVars t' then pure False else bind i t'

-- | Structural equality on types, ignoring annotations (and, for
-- function types, argument names — mirroring what 'unifyBase'
-- compares). Sound as a unification short-circuit: structurally
-- identical types unify without producing any new bindings.
--
plainTypeEq :: Type' Resolved -> Type' Resolved -> Bool
plainTypeEq = plainTypeEqUnder Map.empty

-- | 'plainTypeEq' on the types as the substitution reads them: a bound
-- inference variable is compared as what it was bound to, wherever it
-- sits. This answers what 'plainTypeEq' would answer after
-- 'applySubst', without building the substituted types.
--
plainTypeEqUnder :: Substitution -> Type' Resolved -> Type' Resolved -> Bool
plainTypeEqUnder s = eq
  where
    eq a b = eq' (walkHeadIn s a) (walkHeadIn s b)

    eq' (Type _) (Type _) = True
    eq' (TyApp _ n1 ts1) (TyApp _ n2 ts2) =
      getUnique n1 == getUnique n2
        && length ts1 == length ts2
        && and (zipWith eq ts1 ts2)
    eq' (Fun _ onts1 t1) (Fun _ onts2 t2) =
      length onts1 == length onts2
        && and (zipWith eq (optionallyNamedTypeType <$> onts1) (optionallyNamedTypeType <$> onts2))
        && eq t1 t2
    eq' (InfVar _ _ i1) (InfVar _ _ i2) = i1 == i2
    eq' _ _ = False

-- | Handles the cases where we've established we have no top-level
-- inference variables. Synonym expansion consumes fuel so that a
-- synonym chain too long to follow cannot make us loop; when fuel runs
-- out with a synonym still to expand, that is reported as
-- 'SynonymExpansionLimit' — the types are not known to differ, so no
-- mismatch is reported — and the types are taken as unified, because
-- the error already fails the module and a second one would only
-- repeat it.
--
expandAndUnify :: Int -> Type' Resolved -> Type' Resolved -> Check Bool
expandAndUnify fuel t1 t2 =
  tryExpand t1 (\ t1' -> unifyFuel (fuel - 1) t1' t2) $
  tryExpand t2 (\ t2' -> unifyFuel (fuel - 1) t1 t2') $
  unifyBase fuel t1 t2
  where
    -- Tries to expand the given type synonym. If expansion succeeds,
    -- applies the success continuation, otherwise the failure
    -- continuation.
    --
    tryExpand :: Type' Resolved -> (Type' Resolved -> Check Bool) -> Check Bool -> Check Bool
    tryExpand (TyApp _ann n ts)  kSuccess kFail = do
      mt' <- tryExpandTypeSynonym n ts
      case mt' of
        Just _ | fuel <= 0 -> True <$ addError (SynonymExpansionLimit synonymExpansionFuel n)
        Just t'            -> kSuccess t'
        Nothing            -> kFail
    tryExpand _                 _kSuccess kFail = kFail

-- | Handles the cases where we've established we have no top-level
-- type synonym application and no inference variables. Children
-- inherit the remaining fuel rather than a fresh budget — resetting
-- it here would let a recursive synonym nested under a constructor
-- (e.g. a synonym whose body wraps itself in PAIR) expand forever.
--
unifyBase :: Int -> Type' Resolved -> Type' Resolved -> Check Bool
unifyBase fuel (TyApp _ann1 n1 ts1) (TyApp _ann2 n2 ts2) = do
  -- both are type constructors or type variables
  r <- ensureSameRef n1 n2
  -- We should not need to check the same length because we've done kind checking.
  rs <- traverse (uncurry (unifyFuel fuel)) (zip ts1 ts2)
  pure (and (r : rs))
unifyBase fuel (Fun _ann1 onts1 t1) (Fun _ann2 onts2 t2)
  | length onts1 == length onts2 = do
    rs <- traverse (uncurry (unifyFuel fuel)) (zip (optionallyNamedTypeType <$> onts1) (optionallyNamedTypeType <$> onts2))
    r <- unifyFuel fuel t1 t2
    pure (and (r : rs))
unifyBase _fuel (Type _ann1) (Type _ann2) = pure True
unifyBase _fuel _t1 _t2 = pure False -- addError (UnificationError t1 t2)

infVars :: Type' Resolved -> [Int]
infVars (Type _)        = []
infVars (TyApp _ _ ts)  = concatMap infVars ts
infVars (Fun _ onts t)  = concatMap (infVars . optionallyNamedTypeType) onts ++ infVars t
infVars (Forall _ _ t)  = infVars t
infVars (InfVar _ _ i)  = [i]
-- infVars (ParenType _ t) = infVars t

-- | Precondition: @i@ is unbound in the current substitution, so the
-- 'Map.insert' never overwrites a live binding. This holds because the
-- variable being bound is the head of a type 'walkHead' has just
-- resolved (see 'unifyFuel'), and a head that is still an inference
-- variable after that is unbound.
--
bind :: Int -> Type' Resolved -> Check Bool
bind i t = do
  modifying' #substitution (Map.insert i t)
  pure True

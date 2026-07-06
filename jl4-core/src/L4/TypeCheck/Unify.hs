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
-- constructor children (never reset mid-walk), which yields a real
-- termination guarantee: an infinite unification path must expand
-- synonyms infinitely often — between expansions we only descend into
-- finite type structure — so it runs out of fuel and fails.
--
-- In-module synonym cycles are already rejected at declaration time;
-- the fuel makes termination independent of that check (a cycle can
-- still arrive via imports, and checking continues after decl-time
-- errors). Legitimate programs spend one unit per nested synonym
-- expansion along one path, so the bound is generous.
--
synonymExpansionFuel :: Int
synonymExpansionFuel = 1000

-- We leave it somewhat vague how unify treats forall-types and TYPE.
-- In general, types should be instantiated prior to unification, and
-- kind-checking should not involve unification.
--
-- Unify proceeds in multiple layers.
--
-- First, we have to substitute. Why? Because we have to prevent
-- infinite types from arising (which are usually unwanted, but more
-- importantly even, can make the system loop very easily). And in
-- order to detect cycles, we need to know the full set of inference
-- variables that occur in the target type once we try to bind an
-- inference variable. The easiest way to achieve this is to
-- substitute first.
--
-- Note that substitution must be (re-)applied on every recursive
-- descent into subterms, not just once at the top: unifying earlier
-- siblings extends the substitution, and later siblings have to see
-- those bindings. This is why 'unifyBase' recurses via 'unifyFuel'.
-- (Recursing without re-substituting allowed an inference variable
-- occurring twice in one type, as in @PAIR OF a, a@ against
-- @PAIR OF NUMBER, STRING@, to be silently rebound — accepting
-- ill-typed programs — and allowed cyclic substitutions to be built,
-- making 'applySubst' loop.)
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
-- Before all of that, 'plainTypeEq' short-circuits structurally
-- identical types. Besides being cheap, this is what keeps
-- unification linear when both sides are the same synonym
-- application: expanding a synonym whose body mentions a parameter
-- more than once (or a chain of such synonyms) duplicates work
-- exponentially if we expand first and compare later. The
-- short-circuit does not help when the two sides are *different*
-- spellings of the same exponentially-large expansion; that residual
-- pathology is pre-existing and only reachable by adversarial
-- synonym towers.
--
unify :: Type' Resolved -> Type' Resolved -> Check Bool
unify = unifyFuel synonymExpansionFuel

unifyFuel :: Int -> Type' Resolved -> Type' Resolved -> Check Bool
unifyFuel fuel t1 t2 = do
  t1' <- applySubst t1
  t2' <- applySubst t2
  unify' fuel t1' t2'

-- | Unify cases for inference variables, after substitution. Prevent
-- infinite types by performing the so-called "occurs check".
--
unify' :: Int -> Type' Resolved -> Type' Resolved -> Check Bool
unify' fuel t1 t2
  | plainTypeEq t1 t2    = pure True
  | otherwise            = go t1 t2
  where
    go (InfVar _ann1 _pre1 i1) t2'
      | i1 `elem` infVars t2' = pure False -- addError (OccursCheck t1 t2)
      | otherwise             = bind i1 t2'
    go t1' (InfVar _ann2 _pre2 i2)
      | i2 `elem` infVars t1' = pure False -- addError (OccursCheck t1 t2)
      | otherwise             = bind i2 t1'
    go t1' t2'                = expandAndUnify fuel t1' t2'

-- | Structural equality on types, ignoring annotations (and, for
-- function types, argument names — mirroring what 'unifyBase'
-- compares). Sound as a unification short-circuit: structurally
-- identical types unify without producing any new bindings.
--
plainTypeEq :: Type' Resolved -> Type' Resolved -> Bool
plainTypeEq (Type _) (Type _) = True
plainTypeEq (TyApp _ n1 ts1) (TyApp _ n2 ts2) =
  getUnique n1 == getUnique n2
    && length ts1 == length ts2
    && and (zipWith plainTypeEq ts1 ts2)
plainTypeEq (Fun _ onts1 t1) (Fun _ onts2 t2) =
  length onts1 == length onts2
    && and (zipWith plainTypeEq (optionallyNamedTypeType <$> onts1) (optionallyNamedTypeType <$> onts2))
    && plainTypeEq t1 t2
plainTypeEq (InfVar _ _ i1) (InfVar _ _ i2) = i1 == i2
plainTypeEq _ _ = False

-- | Handles the cases where we've established we have no top-level
-- inference variables. Synonym expansion consumes fuel so that
-- cyclic synonyms (which can evade declaration-time detection via
-- imports) cannot make us loop; when fuel runs out, we treat the
-- types as not unifiable.
--
expandAndUnify :: Int -> Type' Resolved -> Type' Resolved -> Check Bool
expandAndUnify fuel t1 t2
  | fuel <= 0 = pure False
  | otherwise =
      tryExpand t1 (\ t1' -> unify' (fuel - 1) t1' t2) $
      tryExpand t2 (\ t2' -> unify' (fuel - 1) t1 t2') $
      unifyBase fuel t1 t2
  where
    -- Tries to expand the given type synonym. If expansion succeeds,
    -- applies the success continuation, otherwise the failure
    -- continuation.
    --
    tryExpand :: Type' Resolved -> (Type' Resolved -> Check r) -> Check r -> Check r
    tryExpand (TyApp _ann n ts)  kSuccess kFail = do
      mt' <- tryExpandTypeSynonym n ts
      maybe kFail kSuccess mt'
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
-- 'Map.insert' never overwrites a live binding. This holds because every
-- type reaching the inference-variable cases has just been substituted
-- ('unifyFuel' substitutes at entry, and 'unifyBase' recurses via
-- 'unifyFuel'), so any inference variable still present is unbound.
--
bind :: Int -> Type' Resolved -> Check Bool
bind i t = do
  modifying' #substitution (Map.insert i t)
  pure True

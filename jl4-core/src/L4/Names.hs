module L4.Names where

import L4.Syntax

class HasName a where
  getName :: a -> Name

instance HasName Name where
  getName n = n

instance HasName Resolved where
  getName = getActual

instance HasName a => HasName (AppForm a) where
  getName (MkAppForm _ n _ _) = getName n

instance HasName a => HasName (ConDecl a) where
  getName (MkConDecl _ n _) = getName n

instance HasName a => HasName (TypedName a) where
  getName (MkTypedName _ann n _t _ _) = getName n

instance HasName a => HasName (OptionallyTypedName a) where
  getName (MkOptionallyTypedName _ann n _mt _) = getName n

-- ----------------------------------------------------------------------------
-- Section binders (the section-level GIVEN, R4)
-- ----------------------------------------------------------------------------

-- | The names a section's own @GIVEN@ binds; empty when the section has none.
sectionGivenNames :: HasName n => Maybe (GivenSig n) -> [RawName]
sectionGivenNames Nothing = []
sectionGivenNames (Just (MkGivenSig _ otns)) =
  [ rawName (getName otn) | otn <- otns ]

-- | Is this top-level declaration the /elaboration/ of one of the section-binder
-- names @ns@?
--
-- See the invariant documented in "L4.Desugar": in a desugared module every
-- section-@GIVEN@ parameter has exactly one 0-ary @ASSUME@ of the same name at
-- the head of that section's declaration list. Recognition is by name within
-- the declaring section, not by position — 'L4.Export.rewriteModuleAssumes'
-- substitutes a @DECIDE@ in place, so the prefix does not stay homogeneous.
--
-- A section that also spells out an @ASSUME@ of a name its own @GIVEN@ binds is
-- already a duplicate definition, so the name-based test has no reachable
-- false positive.
isSectionBinderElaboration :: HasName n => [RawName] -> TopDecl n -> Bool
isSectionBinderElaboration ns = \ case
  Assume _ (MkAssume _ _ (MkAppForm _ n [] _) _ _) -> rawName (getName n) `elem` ns
  _                                                -> False

-- | Keep only those section-@GIVEN@ parameters whose names are in @keep@;
-- 'Nothing' when nothing survives. Used to hold a section's @GIVEN@ and its
-- elaborations in step when a pass drops or replaces one of them.
filterGivenSigTo :: HasName n => [RawName] -> Maybe (GivenSig n) -> Maybe (GivenSig n)
filterGivenSigTo keep = \ case
  Nothing -> Nothing
  Just (MkGivenSig gann otns) ->
    case filter ((`elem` keep) . rawName . getName) otns of
      []    -> Nothing
      otns' -> Just (MkGivenSig gann otns')

-- | Drop every section-binder elaboration from a module, leaving each section's
-- own @GIVEN@ in place.
--
-- For consumers that render the module as a /document/ rather than execute it:
-- the elaborations exist so the checker and the evaluator see an @ASSUME@, and
-- a reader-facing rendering that showed them would grow a phantom @ASSUME@ line
-- under every heading whose source says @GIVEN@. Rendering the binder itself is
-- separate work and is not in this release.
stripSectionBinderElaborations :: HasName n => Module n -> Module n
stripSectionBinderElaborations (MkModule ann uri sect) = MkModule ann uri (goSection sect)
 where
  goSection (MkSection sann mn maka mgiven decls) =
    MkSection sann mn maka mgiven
      (map goTopDecl (filter (not . isSectionBinderElaboration (sectionGivenNames mgiven)) decls))
  goTopDecl = \ case
    Section a s -> Section a (goSection s)
    other       -> other

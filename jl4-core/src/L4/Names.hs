module L4.Names where

import Control.DeepSeq (NFData)
import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text)
import GHC.Generics (Generic)
import L4.Annotation (Anno_ (..), AnnoElement_ (..))
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

-- | One section binder, as the parsed module declares it.
--
-- Collected by 'L4.Desugar.collectSectionBinderDecls' and carried on
-- 'L4.TypeCheck.Types.CheckEnv' so that a @WITH@ site can be checked against
-- the type the BINDER was declared with rather than against whatever the
-- caller's scope happens to bind that spelling to (R-X2,
-- smucclaw\/l4-ide#956).
data SectionBinderDecl =
  MkSectionBinderDecl
    { sectionPath  :: ![NonEmpty Text]
    -- ^ The heading path this binder is declared at, spelled exactly the way
    -- 'L4.TypeCheck.withSectionStack' spells the reader-side
    -- @CheckEnv.sectionStack@ — outermost first, each level being the
    -- section's name followed by its @AKA@ aliases — so that
    -- 'L4.TypeCheck.Types.sectionProximity' can compare the two directly.
    -- Empty for a binder on an anonymous heading, which is what
    -- 'withSectionStack' does with one too.
    , binderName   :: !Name
    -- ^ The @GIVEN@-line occurrence, which is what a diagnostic should point at.
    , declaredType :: !(Maybe (Type' Name))
    -- ^ Unresolved, and deliberately so: this is read off the module before
    -- desugaring, and 'L4.TypeCheck.inferType' turns it into a
    -- @Type' Resolved@ at the point of use. See 'L4.TypeCheck.binderTypeFor'
    -- for why the resolved type cannot simply be looked up in the environment.
    }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (NFData)

-- | Is this top-level declaration the /elaboration/ of one of the section-binder
-- parameters named in @ns@ — the 0-ary @ASSUME@ that
-- 'L4.Desugar.elaborateSectionBinder' prepends for it?
--
-- Two tests, both required. The name: a section-@GIVEN@ parameter has exactly
-- one 0-ary @ASSUME@ of the same name at the head of that section's
-- declaration list, and recognition is by name within the declaring section
-- rather than by position, because 'L4.Export.rewriteModuleAssumes'
-- substitutes a @DECIDE@ in place, so the prefix does not stay homogeneous.
-- And the identity: the elaboration is built from a single range-hinted hole
-- and carries no concrete tokens ('isSynthesisedAnno'), whereas anything the
-- author wrote carries at least the keyword that introduced it.
--
-- The name alone is NOT enough. An earlier version of this comment claimed
-- that an author-written @ASSUME@ of a name its own section's @GIVEN@ binds
-- "is already a duplicate definition, so the name-based test has no reachable
-- false positive". Measured 2026-09-07 by seven independent refuters: false.
-- L4 resolves names by type, so @GIVEN x IS A NUMBER@ on the heading and
-- @ASSUME x IS A STRING@ in the body coexist in a file that checks clean, and
-- even at the same type nothing is reported until a use is ambiguous. The
-- name-only test took the author's @ASSUME@ for the checker's own, which
-- silenced its deprecation warning, dropped it from the re-printed module and
-- from rendered documents. @ok/assume-beside-section-given.l4@ pins the
-- repair.
isSectionBinderElaboration :: HasName n => [RawName] -> TopDecl n -> Bool
isSectionBinderElaboration ns = \ case
  Assume _ (MkAssume ann _ (MkAppForm _ n [] _) _ _) ->
    rawName (getName n) `elem` ns && isSynthesisedAnno ann
  _ -> False

-- | Did the checker synthesise this node, rather than the author write it?
-- Every parsed node carries at least one cluster of concrete tokens (the
-- keyword that introduced it); a node the compiler built for itself carries
-- holes only.
isSynthesisedAnno :: Anno_ t e -> Bool
isSynthesisedAnno ann = not (any isCsn ann.payload)
  where
    isCsn AnnoCsn {}  = True
    isCsn AnnoHole {} = False

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

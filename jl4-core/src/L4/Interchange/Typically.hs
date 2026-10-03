-- | Where a module writes @TYPICALLY@, and what each interchange backend owes
-- the reader for it.
--
-- __One rule, stated once__ (@specs\/todo\/TYPICALLY-ONE-BEHAVIOUR-SPEC.md@ §4,
-- ruling T5): @TYPICALLY d@ on a name means /when nothing supplies this name at
-- the point where a value must come from outside, use d/. A backend either maps
-- that onto the target's own mechanism, where the mechanism means the same
-- thing, or it says it did not. None may quietly substitute something else, and
-- none may quietly drop it.
--
-- This module is the shared half of that duty. It answers two questions that
-- every backend asked for itself, or did not ask:
--
-- 1. __Where is a default written?__ ('moduleDefaultSites', 'decideDefaultSites').
--    There are four places a @TYPICALLY@ can sit: a rule's own @GIVEN@, a
--    section @GIVEN@, a (deprecated) @ASSUME@, and a record field. They are four
--    different 'DefaultKind's because a target may honour one and not another —
--    OpenFisca can carry a record field's default and cannot carry a section
--    @GIVEN@ at all — and because a note that says "a @GIVEN@" about an
--    @ASSUME@ sends the reader to the wrong line.
-- 2. __What is the default?__ ('classifyDefault'). Today the checker accepts
--    only literals, so a default is a number, a string, @TRUE@\/@FALSE@, or a
--    nullary constructor. R8 rule 3 (W7 of the spec) widens that to expressions
--    on another branch. A backend that matches on 'DefaultValue' and has an arm
--    for 'DefComputed' therefore handles the widening without a change here; a
--    backend that only knows literals reaches its "cannot map" path, which is
--    the point of keeping the constructor.
--
-- The module deliberately builds no 'FidelityNote's of its own: each target says
-- something different about what it lost, and a note with the wrong "lost" line
-- is worse than none. It supplies the words for the /site/ and the /value/
-- ('describeSite', 'describeDefault'), which are the same everywhere.
module L4.Interchange.Typically
  ( -- * Where a default is written
    DefaultKind (..)
  , DefaultSite (..)
  , moduleDefaultSites
  , importedDefaultSites
  , decideDefaultSites
    -- * What the default is
  , DefaultValue (..)
  , classifyDefault
  , isLiteralDefault
    -- * Words for a note
  , describeSite
  , describeDefault
  ) where

import Base
import qualified Base.Set as Set
import qualified Base.Text as Text
import qualified Data.Map.Strict as Map
import Data.Ratio (denominator, numerator)
import System.FilePath (takeBaseName)

import L4.Annotation (rangeOf)
import L4.Export (decideBodiesFromModule, transitiveReferencedUniquesWith)
import L4.Names (isSectionBinderElaboration, sectionGivenNames)
import L4.Parser.SrcSpan (SrcRange)
import L4.Print (prettyLayout)
import L4.Syntax
import L4.TypeCheck.Environment (falseUnique, trueUnique)

-- | Which of the four places a @TYPICALLY@ was written.
data DefaultKind
  = DefaultOnRuleGiven
    -- ^ a rule's own @GIVEN@: @GIVEN rate IS A NUMBER TYPICALLY 3@ above a @DECIDE@
  | DefaultOnSectionGiven
    -- ^ a section @GIVEN@, indented under a @§@ heading
  | DefaultOnAssume
    -- ^ a written @ASSUME@ (deprecated). A section @GIVEN@'s elaboration is also
    -- an @ASSUME@ in the checked module; it is told apart by 'isSectionBinderElaboration'
    -- and reported as 'DefaultOnSectionGiven', so the note points at the line
    -- the author wrote.
  | DefaultOnRecordField
    -- ^ a @DECLARE@d record's field
  deriving stock (Eq, Ord, Show)

-- | One written @TYPICALLY@.
data DefaultSite = MkDefaultSite
  { kind    :: !DefaultKind
  , name    :: !Text
    -- ^ the L4 name of the binder or field, as written
  , owner   :: !(Maybe Text)
    -- ^ the rule a @GIVEN@ belongs to, or the record a field belongs to
  , unique  :: !Unique
    -- ^ the binder's own 'Unique', which is how a lowering that has already
    -- resolved names asks "is this one of mine?"
  , ownerUnique :: !(Maybe Unique)
    -- ^ the 'Unique' of 'owner': the rule's name for a @GIVEN@, the record
    -- type's for a field
  , value   :: !(Expr Resolved)
  , range   :: !(Maybe SrcRange)
  , origin  :: !(Maybe Text)
    -- ^ the imported module the default is written in (its file name without
    -- the extension), or 'Nothing' for the module being exported. A reader of a
    -- note needs to know the line is not in the file they exported.
  }
  deriving stock (Eq, Show)

-- | Every @TYPICALLY@ the module writes, in source order, in any section.
--
-- A rule's own @GIVEN@s come with their rule; a section @GIVEN@ comes from the
-- synthesised @ASSUME@ the checker elaborates it into (that node is the one
-- later passes resolve references to, and it carries the default).
moduleDefaultSites :: Module Resolved -> [DefaultSite]
moduleDefaultSites (MkModule _ _ section) = goSection section
 where
  goSection (MkSection _ _ _ mgiven decls) =
    let binders = sectionGivenNames mgiven
     in concatMap (goDecl binders) decls

  goDecl binders decl = case decl of
    Decide _ d -> ruleGivenSites d
    Assume _ a@(MkAssume _ _ (MkAppForm _ n _ _) _ (Just dflt)) ->
      [ MkDefaultSite
          { kind   = if isSectionBinderElaboration binders decl
                       then DefaultOnSectionGiven
                       else DefaultOnAssume
          , name   = resolvedText n
          , owner  = Nothing
          , unique = getUnique n
          , ownerUnique = Nothing
          , value  = dflt
          , range  = rangeOf a
          , origin = Nothing
          }
      ]
    Declare _ (MkDeclare _ _ (MkAppForm _ rec _ _) (RecordDecl _ _ fields)) ->
      [ MkDefaultSite
          { kind   = DefaultOnRecordField
          , name   = resolvedText fn
          , owner  = Just (resolvedText rec)
          , unique = getUnique fn
          , ownerUnique = Just (getUnique rec)
          , value  = dflt
          , range  = rangeOf tn
          , origin = Nothing
          }
      | tn@(MkTypedName _ fn _ (Just dflt) _) <- fields
      ]
    Section _ s -> goSection s
    _ -> []

-- | The defaults a decision's author wrote on its own @GIVEN@s.
ruleGivenSites :: Decide Resolved -> [DefaultSite]
ruleGivenSites (MkDecide _ (MkTypeSig _ (MkGivenSig _ names) _) (MkAppForm _ rule _ _) _) =
  [ MkDefaultSite
      { kind   = DefaultOnRuleGiven
      , name   = resolvedText n
      , owner  = Just (resolvedText rule)
      , unique = getUnique n
      , ownerUnique = Just (getUnique rule)
      , value  = dflt
      , range  = rangeOf otn
      , origin = Nothing
      }
  | otn@(MkOptionallyTypedName _ n _ (Just dflt)) <- names
  ]

-- | The @TYPICALLY@s written in the modules a module imports, for a backend that
-- has to report on a default it reads through an @IMPORT@.
--
-- A default written in an imported file is a default all the same: an export
-- that names the imported @ASSUME@ or reads the imported record's field loses
-- it exactly as it would lose a local one, and nothing in the exported file
-- shows that it was ever there. 'moduleDefaultSites' sees only the module it is
-- given, so a backend that collected sites from the root alone dropped these in
-- silence (the canon encoding @sg-isa.l4@ reads an imported field that is
-- @TYPICALLY TRUE@, and its DMN export said nothing).
--
-- Each site is tagged with the module it was written in ('origin'). A rule's own
-- @GIVEN@ in an imported module is left out on purpose: the exported rule only
-- reaches an imported rule by calling it, and a call supplies every argument, so
-- there is nothing for the default to do and nothing lost. Whether an imported
-- site is /read/ is the caller's question, because "read" means something
-- different to a lowering that emits a model (every name its bodies name) and
-- to one that draws a process.
--
-- Pass the closure of imports with each module once ('dedupModules' in the CLI).
importedDefaultSites :: [Module Resolved] -> [DefaultSite]
importedDefaultSites mods =
  [ s { origin = Just (moduleLabel m) }
  | m <- mods
  , s <- moduleDefaultSites m
  , s.kind /= DefaultOnRuleGiven
  ]

-- | A module's file name without its extension, which is what an @IMPORT@ names.
moduleLabel :: Module Resolved -> Text
moduleLabel (MkModule _ uri _) =
  Text.pack (takeBaseName (Text.unpack (fromNormalizedUri uri).getUri))

-- | The defaults a process drawn from one rule loses: the rule's own @GIVEN@s,
-- every section @GIVEN@ and @ASSUME@ its body reads, and the record fields of
-- the types it handles. A backend that exports one rule at a time (BPMN draws
-- one process, and a @HENCE@ into another rule is part of that process) reports
-- on this, and not on the whole module, so a default on an unrelated input does
-- not appear in a note about this rule.
--
-- __What counts, by site__
--
-- * A rule's own @GIVEN@: only the /drawn/ rule's. It is a process input, so the
--   source's presumption is what an instance that never set it should get. The
--   @GIVEN@ of a rule the drawn one reaches is not: whether it is reached by
--   @HENCE@ or called from a condition, the call supplies every argument
--   positionally, so the source never relies on that default in this process.
--   (What the process does lose there is the argument the @HENCE@ passes, which
--   BPMN does not draw and which has no note of its own: that is older than
--   @TYPICALLY@. A note about the default pointed the reader at the wrong loss,
--   and said the source presumed a value in a process where it supplied one.)
-- * A section @GIVEN@ or an @ASSUME@: when the rule's body reads it, directly or
--   through any rule it reaches, in this module or an imported one.
-- * A record field: when its record (or the sum type whose constructor carries
--   it) is one the rule handles, or when a body names the field. The rule
--   handles a type when it appears in the signature of the drawn rule or of any
--   rule it reaches, or in the type of an @ASSUME@ it reads, or is the type of a
--   field of such a type. Naming the field is not required: a helper may read it
--   by destructuring (@CONSIDER s WHEN Standing g y THEN g@), which names no
--   selector, and a condition is opaque text in the BPMN, so the process has lost
--   the default of every field of a record it handles.
--
-- The first argument is the modules the checked one imports. The call graph is
-- followed through their rules too: a condition that calls an imported helper
-- reads whatever the helper reads, and the imported file's @ASSUME@ is as lost
-- as a local one. An imported rule's own @GIVEN@ is never reported (see
-- 'importedDefaultSites').
decideDefaultSites :: [Module Resolved] -> Module Resolved -> Decide Resolved -> [DefaultSite]
decideDefaultSites imports modul self@(MkDecide _ _ (MkAppForm _ selfName _ _) body) =
  [ s | s <- moduleDefaultSites modul, wanted s ]
  <>
  [ s | s <- importedDefaultSites imports, wanted s ]
 where
  allModules = modul : imports

  -- The call graph across the whole import closure.
  readSet = transitiveReferencedUniquesWith
              (Map.unions (map decideBodiesFromModule allModules)) body

  wanted s = case s.kind of
    DefaultOnRuleGiven    -> s.ownerUnique == Just (getUnique selfName)
    DefaultOnSectionGiven -> Set.member s.unique readSet
    DefaultOnAssume       -> Set.member s.unique readSet
    DefaultOnRecordField  -> Set.member s.unique readSet || handled s

  handled s = maybe False (`Set.member` typesHandled) s.ownerUnique

  -- The drawn rule and every rule its body reaches.
  reachedRules = self :
    [ d
    | m <- allModules
    , d@(MkDecide _ _ (MkAppForm _ n _ _) _) <- moduleDecides m
    , getUnique n /= getUnique selfName
    , Set.member (getUnique n) readSet
    ]

  -- Every name in those signatures (binders and TYPICALLY expressions come with
  -- them, and are harmless: only a type's 'Unique' is ever looked up) and the
  -- type of each ASSUME the rule reads.
  seeds = Set.fromList $
       [ getUnique r | MkDecide _ sig _ _ <- reachedRules, r <- toList sig ]
    <> [ getUnique r
       | m <- allModules, (u, ty) <- moduleAssumeTypes m, Set.member u readSet, r <- toList ty ]

  -- ... and the types of the fields of any type already handled.
  fieldTypes = Map.fromListWith (<>) (concatMap moduleFieldTypes allModules)
  typesHandled = close seeds
  close seen =
    let more = Set.fromList
          [ getUnique r
          | t <- Set.toList seen
          , tys <- maybeToList (Map.lookup t fieldTypes)
          , ty <- tys
          , r <- toList ty ]
        seen' = Set.union seen more
     in if Set.size seen' == Set.size seen then seen else close seen'

-- | Every module-level @DECIDE@, in any section.
moduleDecides :: Module Resolved -> [Decide Resolved]
moduleDecides (MkModule _ _ section) = goSection section
 where
  goSection (MkSection _ _ _ _ decls) = concatMap goDecl decls
  goDecl = \case
    Decide _ d    -> [d]
    Section _ sub -> goSection sub
    _             -> []

-- | The 'Unique' and declared type of every @ASSUME@ (a section @GIVEN@'s
-- elaboration included) that has one.
moduleAssumeTypes :: Module Resolved -> [(Unique, Type' Resolved)]
moduleAssumeTypes (MkModule _ _ section) = goSection section
 where
  goSection (MkSection _ _ _ _ decls) = concatMap goDecl decls
  goDecl = \case
    Assume _ (MkAssume _ _ (MkAppForm _ n _ _) (Just ty) _) -> [(getUnique n, ty)]
    Section _ sub -> goSection sub
    _             -> []

-- | For each declared type, the types of its fields (a record's, or those of the
-- constructors of a sum type).
moduleFieldTypes :: Module Resolved -> [(Unique, [Type' Resolved])]
moduleFieldTypes (MkModule _ _ section) = goSection section
 where
  goSection (MkSection _ _ _ _ decls) = concatMap goDecl decls
  goDecl = \case
    Declare _ (MkDeclare _ _ (MkAppForm _ ty _ _) (RecordDecl _ _ fields)) ->
      [(getUnique ty, [ fty | MkTypedName _ _ fty _ _ <- fields ])]
    Declare _ (MkDeclare _ _ (MkAppForm _ ty _ _) (EnumDecl _ cons)) ->
      [(getUnique ty, [ fty | MkConDecl _ _ fields <- cons, MkTypedName _ _ fty _ _ <- fields ])]
    Section _ sub -> goSection sub
    _             -> []

-- | What a default is, as far as a backend needs to tell.
data DefaultValue
  = DefNumber Rational
  | DefString Text
  | DefBool Bool
  | DefConstructor Resolved
    -- ^ a nullary application: @NOTHING@ or a constructor of a user's enum, __by
    -- shape only__. A reference to another binder or to a definition, which R8
    -- rule 3 (W7) admits as a default, has exactly this shape, and nothing in the
    -- AST tells the two apart (the checker does, through its entity map). A
    -- backend whose behaviour depends on which one it has (OpenFisca maps an enum
    -- member and must lower a reference as the expression it is) has to check the
    -- constructor itself.
  | DefComputed (Expr Resolved)
    -- ^ anything else. The checker does not produce one today (R8 rule 3 is
    -- unbuilt), so a backend reaches this arm only on a module whose checker
    -- accepts expression defaults, or on an AST edited after checking.
  deriving stock (Eq, Show)

classifyDefault :: Expr Resolved -> DefaultValue
classifyDefault = \case
  Lit _ (NumericLit _ r) -> DefNumber r
  Lit _ (StringLit _ t)  -> DefString t
  App _ r []
    | getUnique r == trueUnique  -> DefBool True
    | getUnique r == falseUnique -> DefBool False
    | otherwise                  -> DefConstructor r
  e -> DefComputed e

isLiteralDefault :: DefaultValue -> Bool
isLiteralDefault = \case
  DefComputed _ -> False
  _             -> True

-- | "the GIVEN @rate@ of @scaled@", "the section GIVEN @rate@", "the ASSUME
-- @rate@", "the field @timeout@ of @Config@": the site as a reader would
-- point at it, with the imported module's name when it is not in the file they
-- exported.
describeSite :: DefaultSite -> Text
describeSite s = case s.kind of
  DefaultOnRuleGiven    -> "the GIVEN `" <> s.name <> "`" <> ofOwner <> inModule
  DefaultOnSectionGiven -> "the section GIVEN `" <> s.name <> "`" <> inModule
  DefaultOnAssume       -> "the ASSUME `" <> s.name <> "`" <> inModule
  DefaultOnRecordField  -> "the field `" <> s.name <> "`" <> ofOwner <> inModule
 where
  ofOwner = maybe "" (\o -> " of `" <> o <> "`") s.owner
  inModule = maybe "" (\m -> " (in the imported module `" <> m <> "`)") s.origin

-- | The value as source would spell it; an expression is printed, not
-- evaluated.
describeDefault :: DefaultValue -> Text
describeDefault = \case
  DefNumber r      -> renderRational r
  DefString t      -> "\"" <> t <> "\""
  DefBool b        -> if b then "TRUE" else "FALSE"
  DefConstructor c -> resolvedText c
  DefComputed e    -> Text.strip (prettyLayout e)

renderRational :: Rational -> Text
renderRational r
  | d == 1    = Text.pack (show n)
  | otherwise = case decimal of
      Just t  -> t
      Nothing -> Text.pack (show n) <> "/" <> Text.pack (show d)
 where
  n = numerator r
  d = denominator r
  -- A denominator with no prime factors but 2 and 5 terminates in base 10.
  decimal
    | strip5 (strip2 d) == 1 =
        let places = max (count 2 d) (count 5 d)
            scaled = abs n * 10 ^ places `div` d
            digits = Text.justifyRight (fromIntegral places + 1) '0' (Text.pack (show scaled))
            (whole, frac) = Text.splitAt (Text.length digits - fromIntegral places) digits
         in Just ((if n < 0 then "-" else "") <> whole <> "." <> frac)
    | otherwise = Nothing
  strip2 = strip 2
  strip5 = strip 5
  strip p x | x /= 0 && x `mod` p == 0 = strip p (x `div` p)
            | otherwise                = x
  count :: Integer -> Integer -> Integer
  count p x = go 0 x
    where go acc y | y /= 0 && y `mod` p == 0 = go (acc + 1) (y `div` p)
                   | otherwise                = acc

resolvedText :: Resolved -> Text
resolvedText = rawNameToText . rawName . getActual

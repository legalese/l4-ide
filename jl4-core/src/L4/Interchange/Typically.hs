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
import Data.Ratio (denominator, numerator)

import L4.Annotation (rangeOf)
import L4.Export (transitiveReferencedUniques)
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
      }
  | otn@(MkOptionallyTypedName _ n _ (Just dflt)) <- names
  ]

-- | The defaults a decision depends on: its own @GIVEN@s, the @GIVEN@s of every
-- rule it reaches by name, and every section @GIVEN@ and @ASSUME@ that its body
-- reads, directly or through anything it reaches. A backend that exports one
-- rule at a time (BPMN draws one process, and a @HENCE@ into another rule is
-- part of that process) reports on this, and not on the whole module, so a
-- default on an unrelated input does not appear in a note about this rule.
decideDefaultSites :: Module Resolved -> Decide Resolved -> [DefaultSite]
decideDefaultSites modul (MkDecide _ _ (MkAppForm _ self _ _) body) =
  [ s
  | s <- moduleDefaultSites modul
  , case s.kind of
      DefaultOnRuleGiven    -> maybe False (\o -> o == getUnique self || Set.member o readSet) s.ownerUnique
      DefaultOnSectionGiven -> Set.member s.unique readSet
      DefaultOnAssume       -> Set.member s.unique readSet
      DefaultOnRecordField  -> False
  ]
 where
  readSet = transitiveReferencedUniques modul body

-- | What a default is, as far as a backend needs to tell.
data DefaultValue
  = DefNumber Rational
  | DefString Text
  | DefBool Bool
  | DefConstructor Resolved
    -- ^ @NOTHING@ or a constructor of a user's enum
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
-- point at it.
describeSite :: DefaultSite -> Text
describeSite s = case s.kind of
  DefaultOnRuleGiven    -> "the GIVEN `" <> s.name <> "`" <> ofOwner
  DefaultOnSectionGiven -> "the section GIVEN `" <> s.name <> "`"
  DefaultOnAssume       -> "the ASSUME `" <> s.name <> "`"
  DefaultOnRecordField  -> "the field `" <> s.name <> "`" <> ofOwner
 where
  ofOwner = maybe "" (\o -> " of `" <> o <> "`") s.owner

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

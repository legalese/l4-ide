-- | The case rule for module names (smucclaw/l4-ide#1080).
--
-- A module is named by its file's name, and capital letters count:
-- @IMPORT dayDate@ does not load @daydate.l4@, on any computer and in any host.
-- Every resolver already compared names exactly — the embedded stdlib, the
-- in-memory files of the editor and of the web playground, jl4-service's
-- bundles — except the filesystem tiers of the CLI and the language server,
-- which asked the operating system whether a file exists, and a
-- case-insensitive disk (the macOS and Windows defaults) answers yes for any
-- capitalisation. See @specs/todo/LIBRARY-RESOLUTION-SHADOW-SPEC.md@ §11.
--
-- This module is the rule's single statement: which listed names count as the
-- asked one, which only differ from it in capitals, and the sentence that says
-- so. Each host supplies its own list of the names it can see; the comparison
-- and the wording are the same everywhere, so the CLI, the editor, the web
-- playground and jl4-service agree.
--
-- __Unicode limit, accepted (assumed (GM, 2026-11-21), for Meng's review).__
-- Names are compared with 'Text.toCaseFold' and no Unicode normalisation.
-- HFS+ stores a name decomposed (@café@ is listed as @cafe@ plus a combining
-- accent) while the source spells it composed, so a correctly spelled
-- non-ASCII import matches no listed entry exactly. 'classifyEntry' answers
-- 'NoEntry' for it rather than 'CaseVariantEntries', and the caller then keeps
-- the operating system's answer, as before. The cost: a non-ASCII name that
-- differs from its file in BOTH normalisation and capitals is still accepted
-- on such a disk. Closing that would need a normalisation library, which no
-- package here depends on.
--
-- __Full case folding, and what the sentences claim (assumed, not ruled).__
-- Names are matched with full case folding ('Text.toCaseFold': @ß@ folds to
-- @ss@, @ς@ to @σ@), because the default Mac disk ignores those differences
-- too. Measured 2026-11-21 on nye: on APFS (the internal disk), a folder
-- holding @straße.l4@ answers yes for @strasse.l4@, @STRASSE.l4@ and
-- @STRAẞE.l4@, and one holding @οδος.l4@ answers yes for @οδοσ.l4@ and
-- @ΟΔΟΣ.l4@; on HFS+ (an external volume) all five answer no. Matching by
-- capitals alone would let APFS load @straße.l4@ for @IMPORT strasse@. But
-- @strasse@ and @straße@ do not differ "only in capital letters", so the
-- sentences say that only when it is true ('differsOnlyInCapitals'), and
-- otherwise say that module names must match letter for letter.
module L4.Import.ModuleNameCase
  ( EntryMatch (..)
  , classifyEntry
  , caseVariants
  , differsOnlyInCapitals
  , caseVariantHint
  , selfImportHint
  , ownModuleDifference
  , selfImportAdvice
  ) where

import Data.Char (toLower, toUpper)
import Data.List (nub, sort)
import Data.Text (Text)
import qualified Data.Text as Text

-- | What one directory's listing says about one file name.
data EntryMatch
  = ExactEntry
    -- ^ an entry is spelled exactly as asked
  | CaseVariantEntries [FilePath]
    -- ^ no entry is spelled as asked, and these entries equal it under full case
    -- folding (sorted, each once): different capitals, or a difference such as
    -- @ß@ for @ss@ that a case-insensitive disk may also ignore
  | NoEntry
    -- ^ neither. This includes a name the disk lists in another Unicode
    -- normal form, which is not a case variant: see the module header.
  deriving stock (Eq, Show)

-- | Classify the file name @wanted@ against a directory's entries.
--
-- An exact entry wins even when variants sit beside it, as they can on a
-- case-sensitive disk (@Helper.l4@ and @helper.l4@ in one folder).
classifyEntry :: [FilePath] -> FilePath -> EntryMatch
classifyEntry listing wanted
  | wanted `elem` listing = ExactEntry
  | otherwise = case sort (nub [ e | e <- listing, folded e == folded wanted ]) of
      [] -> NoEntry
      vs -> CaseVariantEntries vs
  where
    folded = Text.toCaseFold . Text.pack

-- | The names among @known@ that equal @asked@ under full case folding (see the
-- module header), sorted, each once. @asked@ itself is never among them.
caseVariants :: Text -> [Text] -> [Text]
caseVariants asked known =
  sort (nub [ k | k <- known, k /= asked, Text.toCaseFold k == Text.toCaseFold asked ])

-- | Whether two names differ only in capital letters: the same length, and at
-- each position the same character or one that is the other's capital or small
-- form ('toUpper' or 'toLower', one character to one). @dayDate@ and @daydate@
-- do; @strasse@ and @straße@ do not, nor do @οδοσ@ and @οδος@ (two small
-- sigmas), though full case folding equates both pairs.
differsOnlyInCapitals :: Text -> Text -> Bool
differsOnlyInCapitals a b =
  Text.length a == Text.length b && all (uncurry twin) (Text.zip a b)
  where
    twin x y = x == y || toLower x == y || toLower y == x || toUpper x == y || toUpper y == x

-- | The line an unresolved @IMPORT@ gains when a module of nearly that name
-- exists: 'Nothing' when there is no such module. @known@ may be every name
-- the host can see; only the case variants of @asked@ among them are named.
-- The names are module names, never paths, so the sentence is the same on
-- every machine (a golden that captures it stays machine-independent).
--
-- The capitals wording is used only when every name offered differs from
-- @asked@ only in capitals; otherwise the sentence says names must match letter
-- for letter, which is true of both kinds.
--
-- Wording assumed, not ruled.
caseVariantHint :: Text -> [Text] -> Maybe Text
caseVariantHint asked known = case caseVariants asked known of
  [] -> Nothing
  [v] -> Just $
    reason [v] <> quoted asked <> " and " <> quoted v
      <> " are different names. Did you mean " <> quoted v <> "?"
  vs -> Just $
    reason vs <> quoted asked
      <> " is a different name from each of these. Did you mean one of: "
      <> Text.intercalate ", " (map quoted vs) <> "?"
  where
    quoted n = "`" <> n <> "`"
    reason vs
      | all (differsOnlyInCapitals asked) vs = "Capital letters count in a module name: "
      | otherwise = "Module names must match exactly, letter for letter: "

-- | The line an unresolved @IMPORT@ gains instead of 'caseVariantHint' when
-- the only near match is the importing file's own module: @Foo.l4@ that
-- writes @IMPORT foo@. Offering @Foo@ would tell the file to import itself,
-- and renaming the file to @foo.l4@ would make it do so, so the line says
-- what is true instead: the name is this file's own, with other capitals,
-- and a module cannot import itself (review finding A, as revised by GM on
-- 2026-11-21; wording assumed, not ruled). 'Nothing' when @own@ is not a near
-- match of @asked@.
--
-- The caller decides that @own@ is the file the IMPORT is written in, and
-- that no other near match exists; the sentence says "this file", so a host
-- whose message does not sit on that file must not use it.
selfImportHint :: Text -> Text -> Maybe Text
selfImportHint asked own
  | null (caseVariants asked [own]) = Nothing
  | otherwise = Just (ownModuleDifference asked own <> " " <> selfImportAdvice)

-- | @`foo` differs from `Foo`, the name of this file's own module, only in
-- its capitals.@, or, for a difference that is not only capitals (@strasse@
-- for @Straße@), "only in how its letters are written".
ownModuleDifference :: Text -> Text -> Text
ownModuleDifference asked own =
  "`" <> asked <> "` differs from `" <> own <> "`, the name of this file's own module, "
    <> (if differsOnlyInCapitals asked own then "only in its capitals." else "only in how its letters are written.")

-- | What to do when the near match of an IMPORT is the file it is written in.
selfImportAdvice :: Text
selfImportAdvice =
  "If you meant this file, remove the IMPORT: a module cannot import itself, and a file's own definitions need no IMPORT."

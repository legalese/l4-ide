module L4.Parser.MixfixRegistry
  ( MixfixHintRegistry (..)
  , emptyMixfixHintRegistry
  , registerMixfixInfo
  , buildMixfixHintRegistry
  , hasMixfixHints
  , isKnownMixfixKeyword
  , mixfixRulesWrittenAs
  , showMixfixPattern
  , showKeywords
  ) where

import Base
import qualified Base.Map as Map
import qualified Base.Set as Set
import qualified Base.Text as Text
import qualified Data.List as List
import L4.Mixfix
import L4.Syntax

data MixfixHintRegistry = MkMixfixHintRegistry
  { byFirstKeyword :: Map RawName [MixfixInfo]
  , keywordUniverse :: Set RawName
  }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (NFData)

-- | Entries are merged with 'List.union', which drops a later copy equal to an
-- earlier one. A module's registry includes its imports' registries, so
-- merging with '<>' kept one copy of each hint per import PATH
-- (smucclaw\/l4-ide#1008). A 'MixfixInfo' is its pattern, keywords and arity,
-- and nothing else about the definition, so a copy that is equal is a copy
-- that no reader can tell apart: 'mixfixRulesWrittenAs' lists the rules a run
-- of tokens is written like, and its callers take the first or ask whether
-- every one of them satisfies a test of the rule's value; the other readers
-- ask only 'keywordUniverse'.
instance Semigroup MixfixHintRegistry where
  MkMixfixHintRegistry m1 s1 <> MkMixfixHintRegistry m2 s2 =
    MkMixfixHintRegistry
      (Map.unionWith List.union m1 m2)
      (Set.union s1 s2)

instance Monoid MixfixHintRegistry where
  mempty = emptyMixfixHintRegistry

emptyMixfixHintRegistry :: MixfixHintRegistry
emptyMixfixHintRegistry =
  MkMixfixHintRegistry Map.empty Set.empty

registerMixfixInfo :: MixfixInfo -> MixfixHintRegistry
registerMixfixInfo info =
  case firstKeyword info of
    Nothing -> mempty
    Just kw ->
      MkMixfixHintRegistry
        (Map.singleton kw [info])
        (Set.fromList info.keywords)

hasMixfixHints :: MixfixHintRegistry -> Bool
hasMixfixHints hints = not (Set.null hints.keywordUniverse)

isKnownMixfixKeyword :: RawName -> MixfixHintRegistry -> Bool
isKnownMixfixKeyword kw hints =
  kw `Set.member` hints.keywordUniverse

-- | The mixfix rules in scope that a run of tokens is written in the form of.
--
-- Each token is its name when it is a bare name and 'Nothing' when it is
-- anything else (a literal, a bracket, a constructor applied to something). A
-- rule's form is its pattern: the run must be as long as the pattern, and
-- where the pattern has a keyword the run must hold that very name; where it
-- has an input the run may hold anything. So @Red `costs` 0@ is written in the
-- form of @c `costs` n@, and @Red `costs`@ and @Red `cost` 0@ are not.
--
-- The first argument holds the names that the definition being read has for its
-- own inputs. A run that holds one of them where the pattern has a keyword
-- holds an input there, not the rule's word, so it is no use of that rule:
-- @total plus y@, whose GIVEN names @plus@ and @y@, is a rule called @total@
-- with two inputs, and not a line written like @a `plus` b@.
mixfixRulesWrittenAs :: [RawName] -> [Maybe RawName] -> MixfixHintRegistry -> [MixfixInfo]
mixfixRulesWrittenAs inputs toks hints =
  [ info
  | infos <- Map.elems hints.byFirstKeyword
  , info <- infos
  , length info.pattern == length toks
  , and (zipWith slotHolds info.pattern toks)
  ]
  where
    slotHolds = \ case
      MixfixKeyword kw -> \ tok -> tok == Just kw && kw `notElem` inputs
      MixfixParam _    -> const True

-- | A rule's pattern as a drafter writes it, its inputs by the names its
-- definition gave them and its keywords in backticks: @c `costs` n@.
showMixfixPattern :: MixfixInfo -> Text
showMixfixPattern info = Text.unwords (map word info.pattern)
  where
    word = \ case
      MixfixKeyword kw -> "`" <> rawNameToText kw <> "`"
      MixfixParam n    -> rawNameToText n

showKeywords :: MixfixHintRegistry -> [Text]
showKeywords hints = map rawNameToText $ Set.toList hints.keywordUniverse

buildMixfixHintRegistry :: Module Name -> MixfixHintRegistry
buildMixfixHintRegistry =
  foldTopDecls gatherTop
  where
    gatherTop :: TopDecl Name -> MixfixHintRegistry
    gatherTop = \case
      Decide _ dec -> foldDecides gatherDecide dec
      Assume _ ass -> gatherAssume ass
      _ -> mempty

    gatherDecide :: Decide Name -> MixfixHintRegistry
    gatherDecide (MkDecide _ tysig appForm _) =
      maybe mempty registerMixfixInfo (extractMixfixInfo tysig appForm)

    gatherAssume :: Assume Name -> MixfixHintRegistry
    gatherAssume (MkAssume _ tysig appForm _) =
      maybe mempty registerMixfixInfo (extractMixfixInfo tysig appForm)

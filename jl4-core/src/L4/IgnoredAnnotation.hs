{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | The warning for an annotation line this version of L4 cannot use.
--
-- Such a line is lexed as trivia ('TIgnoredAnnotation'): the file loads, checks
-- and highlights as if the line were a comment. That is what lets a module
-- written for a newer L4 survive in an older one, instead of losing every
-- semantic token to a lexer failure. The same design is GHC's for an unknown
-- @{-# FOO #-}@ pragma ('-Wunrecognised-pragmas'): ignore it, and say so.
--
-- There are two reasons a line is ignored, and the warning says which:
--
--   * 'Unrecognised': the name is not one of 'knownAnnotationHeralds'. It may be
--     a misspelling of one (then the warning suggests it) or an annotation from
--     a newer version.
--   * 'Malformed': the name is known, but the line does not have the form it
--     needs. Only @\@lang@ can be, today (a bare @\@lang@, a tab where the space
--     goes, a language code that is not ASCII); the others accept every one of
--     those forms.
--
-- Saying so is this module. The lexer stays pure and keeps no list of
-- complaints; the warning is read off the finished token stream, as the
-- no-break-space lint is ("L4.SmartPunctuation"), and published by
-- @GetLexTokens@ so that @l4 check@ and the editor both get it.
module L4.IgnoredAnnotation
  ( IgnoredAnnotation (..)
  , Problem (..)
  , ignoredAnnotations
  , nearestKnownHerald
  , ignoredAnnotationMessage
  , renderIgnoredAnnotation
  ) where

import Base
import qualified Base.Text as Text

import L4.Lexer (PosToken (..), TSpaces (..), TokenType (..), computedPayload, knownAnnotationHeralds)
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import L4.Presumption (editDistance)

-- | One ignored annotation line in a token stream.
data IgnoredAnnotation = MkIgnoredAnnotation
  { range :: SrcRange
    -- ^ The whole annotation: its @\@name@ and the rest of its line, which it
    -- takes with it.
  , name :: Text
    -- ^ As written, without the @\@@.
  , problem :: Problem
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

data Problem
  = Unrecognised (Maybe Text)
    -- ^ No such annotation. The known one it is probably a misspelling of,
    -- without the @\@@, if there is one.
  | Malformed
    -- ^ A known annotation whose line does not have the form it needs.
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | Every ignored annotation in the tokens of a module, in source order.
ignoredAnnotations :: [PosToken] -> [IgnoredAnnotation]
ignoredAnnotations toks =
  [ MkIgnoredAnnotation t.range name problem
  | t <- toks
  , TSpaces (TIgnoredAnnotation name _rest) <- [computedPayload t]
  , let problem
          | name `elem` knownAnnotationHeralds = Malformed
          | otherwise = Unrecognised (nearestKnownHerald name)
  ]

-- | The known annotation an unknown name is close enough to be a misspelling
-- of, if there is one. Case is ignored (@\@Desc@ is a misspelling of @\@desc@),
-- and the allowance is one edit for a name of up to four letters, two for a
-- longer one, so that a short name is not matched to anything vaguely like it.
-- On a tie the earlier of 'knownAnnotationHeralds' wins.
nearestKnownHerald :: Text -> Maybe Text
nearestKnownHerald name =
  case sortOn snd [ (k, editDistance (Text.toLower name) k) | k <- knownAnnotationHeralds ] of
    (k, d) : _ | d <= allowance -> Just k
    _ -> Nothing
  where
    allowance = if Text.length name <= 4 then 1 else 2 :: Int

-- | What the warning says. Quoted on the errors reference page
-- (@doc/reference/errors/README.md@): whoever changes this owns that page.
ignoredAnnotationMessage :: IgnoredAnnotation -> Text
ignoredAnnotationMessage a = case a.problem of
  Unrecognised suggestion ->
    "Unknown annotation `@" <> a.name <> "`: this version of L4 does not know it, "
      <> "so it is ignored, along with the rest of its line. "
      <> case suggestion of
           Just k  -> "Did you mean `@" <> k <> "`?"
           Nothing -> "The annotations this version knows are "
                        <> Text.intercalate ", " [ "@" <> k | k <- knownAnnotationHeralds ]
                        <> "."
  Malformed ->
    "Malformed annotation `@" <> a.name <> "`: " <> expectedForm a.name
      <> ", so this line is ignored."

-- | An ignored line as @line:column: message@, for a tool that prints it under
-- a file name of its own ('l4 batch', the service).
renderIgnoredAnnotation :: IgnoredAnnotation -> Text
renderIgnoredAnnotation a =
  Text.pack (show a.range.start.line) <> ":" <> Text.pack (show a.range.start.column)
    <> ": " <> ignoredAnnotationMessage a

-- | What a known annotation needs, for the warning about a line that lacks it.
-- Only @\@lang@ can lack anything today ("UnknownAnnotationSpec" checks that no
-- other known annotation is refused when written bare), so the fallback is a
-- safety net and not a message anyone should see.
expectedForm :: Text -> Text
expectedForm = \case
  "lang" -> "it needs a language code after a space, such as `@lang en` (letters, digits and hyphens)"
  _      -> "it is not in a form this version of L4 reads"

-- | What the parser's annotation warnings ('Resolve.Warning') say, and where.
--
-- In jl4-core rather than in the language server, so that every surface that
-- checks a module reports them in the same words: the editor and @l4 check@
-- through the language server, and the web editor through 'L4.API.l4Check',
-- which has no language server under it.
module L4.Parser.AnnotationWarning
  ( annotationWarningCode
  , annotationWarningMessage
  , annotationWarningSpan
  ) where

import Base
import qualified Base.Text as Text

import L4.Annotation (HasSrcRange (..))
import L4.Lexer (LangTag (..))
import L4.Parser.ResolveAnnotation (NlgWithSpan, Warning (..), WithSpan (..))
import qualified L4.Parser.ResolveAnnotation as Resolve
import L4.Parser.SrcSpan
import qualified L4.Print as Print
import L4.Syntax

-- | The stable diagnostic code of an annotation warning. See
-- 'L4.TypeCheck.Types.checkErrorCode' for what a code promises. No wildcard, so
-- that a new warning has to be given a code.
annotationWarningCode :: Warning -> Text
annotationWarningCode = \ case
  NotAttached {}     -> "lint/annotation-not-attached"
  UnknownLocation {} -> "lint/annotation-without-location"
  EmptyNlg {}        -> "lint/empty-nlg"
  Ambiguous {}       -> "lint/ambiguous-nlg"
  LangOverridden {}  -> "lint/lang-overridden"
  LoneLangTag {}     -> "lint/lone-lang-tag"
  SpacedSlot {}      -> "lint/spaced-nlg-slot"
  RefUnattached {}   -> "lint/ref-not-attached"
  RefTrailing {}     -> "lint/ref-after-code"
  RefNoLocation {}   -> "lint/annotation-without-location"

annotationWarningMessage :: Warning -> Text
annotationWarningMessage = \ case
  NotAttached _ ->
    "Not attached to any valid syntax node."
  UnknownLocation nlg -> Text.unlines
    [ "The following NLG Annotation has no source location. This might be an internal compiler error."
    , "```"
    , Print.prettyLayout nlg
    , "```"
    ]
  EmptyNlg name _ ->
    "This @nlg annotation has no text, so it is ignored: "
      <> Print.prettyLayout name
      <> " would otherwise render as nothing at all, because an annotation replaces what it annotates."
  Ambiguous name mtag nlgs -> Text.unlines $
    ( case mtag of
        -- Every parsed annotation carries a language by the time it gets
        -- here: an untagged one is stamped with the module's `@lang`, or with
        -- `en`. So the hint has to cover BOTH shapes at once — it is wrong to
        -- say "tag these" to someone who already tagged them `:he` twice, and
        -- wrong to talk about `en` without saying where `en` came from.
        Just (MkLangTag tag) ->
          [ "More than one NLG annotation in language `" <> tag <> "` attached to: "
              <> Print.prettyLayout name
          , "An untagged @nlg counts as the module's language (@lang, or `en` by default), so two untagged ones collide here too. Renderings in different languages need different tags."
          ]
        -- Only an annotation we could not parse reaches here without one.
        Nothing ->
          [ "More than one NLG annotation attached to: " <> Print.prettyLayout name ]
    ) <>
    [ "The following annotations would be attached:"
    , ""
    ] <> [ "* `" <> Print.prettyLayout n.payload <> "`" | n <- nlgs]
  LangOverridden overriddenLine winningLine ->
    let langOf (MkLangTag tag) = tag
    in Text.unlines
      [ "This module declares two different languages with @lang: `" <> langOf overriddenLine.payload
          <> "` here and `" <> langOf winningLine.payload
          <> "` on line " <> Text.pack (show winningLine.range.start.line) <> "."
      , "L4 uses the last @lang in the file, so the module's language is `" <> langOf winningLine.payload
          <> "` and this line has no effect. Keep one @lang line."
      ]
  LoneLangTag name mrule nlg (Just (MkLangTag declared)) ->
    let tag = tagOf nlg
    in Text.unlines
      [ "`@nlg:" <> tag <> "` tags " <> wordingOf name mrule <> " as language `" <> tag
          <> "`, but it is " <> ownerOf name mrule <> "'s only wording and the module declares `@lang " <> declared
          <> "`: `" <> tag <> "` and `" <> declared <> "` differ only in case."
      , "Tags are compared exactly, so `" <> tag <> "` is not `" <> declared <> "`. Write `@nlg:" <> declared
          <> "`, or leave the tag off, since a wording with no tag is already in `" <> declared <> "`."
      ]
  LoneLangTag name mrule nlg Nothing ->
    let tag = tagOf nlg
    in Text.unlines
      [ "`@nlg:" <> tag <> "` tags " <> wordingOf name mrule <> " as language `" <> tag
          <> "`, but it is " <> ownerOf name mrule <> "'s only wording, and nothing else in the module makes `"
          <> tag <> "` a language: no `@lang " <> tag
          <> "` line declares it, and nothing has a wording in it beside one in another language."
      , "A tag tells apart wordings of one rule in different languages. If `" <> tag
          <> "` is the first word of the sentence, write `@nlg " <> tag
          <> " …` with no colon. If the wording is in `" <> tag <> "`, add `@lang " <> tag
          <> "`, or give " <> ownerOf name mrule <> " a wording in another language too."
      ]
  SpacedSlot written name ->
    Text.unlines
      [ "This wording has `" <> written.payload <> "`, with spaces inside the percent signs, so it prints as plain text."
      , "A slot is written `%" <> name <> "%`, with no spaces. For a percent sign meant literally, write `\\%`."
      ]
  RefUnattached r ->
    Resolve.refUnattachedMessage r.payload
  RefTrailing r code ->
    Resolve.refTrailingMessage r.payload code
  RefNoLocation ref ->
    Resolve.refNoLocationMessage ref
 where
  tagOf :: NlgWithSpan -> Text
  tagOf nlg = maybe "" (\ (MkLangTag t) -> t) (nlgLangTag nlg.payload)

  -- A wording written after an input in a rule's head is the rule's sentence,
  -- so the message names the rule, and says where the wording is.
  wordingOf :: Name -> Maybe Name -> Text
  wordingOf name = \ case
    Just rule -> "the sentence of " <> quoted rule <> ", written after its input " <> quoted name <> ","
    Nothing   -> "the wording on " <> quoted name

  ownerOf :: Name -> Maybe Name -> Text
  ownerOf name = quoted . fromMaybe name

  -- A name in backticks whether or not L4 needs them, so that two names in one
  -- sentence read alike.
  quoted :: Name -> Text
  quoted n = let t = Print.prettyLayout n in if "`" `Text.isPrefixOf` t then t else "`" <> t <> "`"

-- | Where a warning points, or 'Nothing' when it has no place in the source.
annotationWarningSpan :: Warning -> Maybe SrcSpan
annotationWarningSpan = \ case
  NotAttached nlg         -> Just nlg.range
  UnknownLocation _       -> Nothing
  EmptyNlg _ nlg          -> Just nlg.range
  Ambiguous name _ _      -> fromSrcRange <$> rangeOf name
  LangOverridden line _   -> Just line.range
  LoneLangTag _ _ nlg _   -> Just nlg.range
  SpacedSlot written _    -> Just written.range
  RefUnattached r         -> Just r.range
  RefTrailing r _         -> Just r.range
  RefNoLocation _         -> Nothing

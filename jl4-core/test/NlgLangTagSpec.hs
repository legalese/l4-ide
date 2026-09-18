{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | @\@nlg:he@ — the language tag on the heralded form.
--
-- __The invariant these tests exist for.__ An @\@nlg@ annotation is lexed
-- __twice, by two different lexers facing opposite ways__. The outer one
-- ('L4.Lexer.nlgAnnotation') captures the herald and the rest of the line into
-- a @TNlg@ token. The parser then discards that token, /rebuilds the source
-- text/ with 'toNlgAnno', and re-lexes the result with a second lexer
-- ('L4.Lexer.nlgTokenPayload') — and it is the __second__ lexer's tokens that
-- land in the AST and that exactprint re-emits.
--
-- So three things must agree about what a tag is: the outer lexer,
-- 'toNlgAnno', and the inner lexer. Nothing in the type system makes them.
-- They agree today because all three route through one 'L4.Lexer.langTag'
-- parser, which is a discipline, not a guarantee — the same discipline
-- @isNlgEscapable@ encodes, and which survived until someone wrote the literal
-- @\"\\\\%]\"@ four lines under a comment saying not to.
--
-- When they disagree it is __silent__. @mkPosTokens@ seeds the inner tokens'
-- positions by advancing over the reconstructed text, so a tag dropped in
-- reconstruction shifts every inner column by its width and reports
-- diagnostics at the wrong place, with nothing failing.
module NlgLangTagSpec (spec) where

import Base
import qualified Base.Text as Text

import L4.Lexer
  ( AnnoType (..)
  , LangTag (..)
  , TAnnotations (..)
  , TokenType (..)
  , computedPayload
  , execLexer
  , execNlgLexer
  , toNlgAnno
  )
import L4.Parser (PState (..), execParser, module')
import L4.Syntax (Nlg (..), NlgFragment (..))
import Test.Hspec
import Text.Megaparsec.Pos (initialPos)

specUri :: NormalizedUri
specUri = toNormalizedUri (Uri "file:///nlg-langtag-spec")

-- | Every @\@nlg@ annotation as the OUTER lexer sees it.
outerNlgs :: Text -> IO [(Maybe LangTag, Text, AnnoType)]
outerNlgs src =
  case execLexer specUri src of
    Left errs -> do
      expectationFailure $ "Lexer failed: " <> show errs
      error "unreachable"
    Right toks ->
      pure [ (m, t, ty) | tok <- toks, TAnnotations (TNlg m t ty) <- [computedPayload tok] ]

-- | Every @\@nlg@ herald as the INNER lexer sees it, given already-reconstructed
-- annotation text.
innerPrefixTags :: Text -> IO [Maybe LangTag]
innerPrefixTags txt =
  case execNlgLexer (initialPos "nlg") specUri txt of
    Left err -> do
      expectationFailure $ "Inner lexer failed: " <> show err
      error "unreachable"
    Right toks ->
      pure [ m | tok <- toks, TAnnotations (TNlgPrefix m) <- [computedPayload tok] ]

-- | Every annotation's text fragments, concatenated, in source order.
nlgProse :: Text -> IO [Text]
nlgProse src =
  case execParser (module' specUri) specUri src of
    Left errs -> do
      expectationFailure $ "Parser failed: " <> show errs
      error "unreachable"
    Right (_m, _warnings, pstate) ->
      pure (map proseOf (reverse pstate.nlgs))
 where
  proseOf = \ case
    MkParsedNlg _ frags   -> Text.concat [t | MkNlgText _ t <- frags]
    MkResolvedNlg _ frags -> Text.concat [t | MkNlgText _ t <- frags]
    MkInvalidNlg{}        -> "<invalid>"

decide :: Text -> Text
decide anno =
  "GIVEN a IS A NUMBER\nGIVETH A BOOLEAN\nDECIDE `p` " <> anno <> "\n  IF a > 5\n"

spec :: Spec
spec = describe "@nlg:xx language tag" $ do

  describe "the outer lexer" $ do
    it "captures the tag and leaves the body exactly as before" $ do
      outerNlgs (decide "@nlg:he the body") `shouldReturn`
        [(Just (MkLangTag "he"), " the body", LineAnno)]

    it "captures no tag when there is none, and the body is unchanged" $ do
      outerNlgs (decide "@nlg the body") `shouldReturn`
        [(Nothing, " the body", LineAnno)]

    it "leaves a colon that cannot begin a tag as ordinary annotation text" $ do
      -- `@nlg: see below` meant something before tags existed and must go on
      -- meaning it. The tag parser backtracks as a whole for this case.
      outerNlgs (decide "@nlg: see below") `shouldReturn`
        [(Nothing, ": see below", LineAnno)]

    it "accepts a subtagged tag, since validation is not the lexer's job" $ do
      outerNlgs (decide "@nlg:he-IL the body") `shouldReturn`
        [(Just (MkLangTag "he-IL"), " the body", LineAnno)]

  -- The pushmi-pullyu: two heads, one beast, and it only moves if they agree.
  describe "the outer lexer, toNlgAnno and the inner lexer agree" $
    for_ ["he", "en", "he-IL", "zh-Hant"] $ \ tag ->
      it ("round-trips @nlg:" <> Text.unpack tag) $ do
        let herald = "@nlg:" <> tag
        [(m, t, ty)] <- outerNlgs (decide (herald <> " the body"))

        -- (1) the outer lexer recovered the tag
        m `shouldBe` Just (MkLangTag tag)

        -- (2) reconstruction is byte-identical to the source slice. If this
        --     drifts, inner token POSITIONS drift with it, silently.
        let reconstructed = toNlgAnno m t ty
        reconstructed `shouldBe` herald <> " the body"

        -- (3) the inner lexer recovers the same tag from that reconstruction
        innerPrefixTags reconstructed `shouldReturn` [m]

  describe "the tag is metadata, not prose" $ do
    it "does not leak the tag into the rendered fragments" $ do
      prose <- nlgProse (decide "@nlg:he the body")
      Text.unpack (Text.concat prose) `shouldNotContain` ":he"

    it "renders the same prose tagged and untagged" $ do
      tagged   <- nlgProse (decide "@nlg:he the body")
      untagged <- nlgProse (decide "@nlg the body")
      tagged `shouldBe` untagged

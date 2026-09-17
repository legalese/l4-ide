{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
module RefAnnotationSpec (spec) where

import qualified Data.Text as Text

import Base
import L4.Annotation (getAnno)
import L4.Parser (execProgramParserWithHintPass)
import L4.Syntax
  ( Decide (..)
  , Expr (..)
  , Module (..)
  , Name
  , Section (..)
  , TopDecl (..)
  , annRef
  , getRef
  )
import Test.Hspec

-- | Parse a source snippet and return the @\@ref@ text (if any) attached to
-- the 'Module' node and to the first top-level declaration ('TopDecl').
moduleAndFirstDeclRefs :: Text -> IO (Maybe Text, Maybe Text)
moduleAndFirstDeclRefs src = do
  let uri = toNormalizedUri (Uri "file:///ref-annotation-spec-module")
  case execProgramParserWithHintPass uri src of
    Left errs -> do
      expectationFailure $ "Parser failed: " <> show errs
      error "unreachable"
    Right (m@(MkModule _ _ (MkSection _ _ _ _ decls)), _, _) -> do
      let moduleRef = fmap getRef (view annRef (getAnno m))
      firstDeclRef <- case decls of
        (d : _) -> pure $ fmap getRef (view annRef (getAnno d))
        []      -> do
          expectationFailure "Expected at least one top-level declaration"
          error "unreachable"
      pure (moduleRef, firstDeclRef)

-- | Parse a source snippet and return the bodies of every top-level @DECIDE@,
-- paired with the raw text of any @\@ref@ annotation attached to that body
-- expression (via its 'Anno'\'s 'Extension').
decideBodyRefs :: Text -> IO [(Expr Name, Maybe Text)]
decideBodyRefs = decideBodyRefs' "file:///ref-annotation-spec"

decideBodyRefs' :: String -> Text -> IO [(Expr Name, Maybe Text)]
decideBodyRefs' uriStr src = do
  let uri = toNormalizedUri (Uri (Text.pack uriStr))
  case execProgramParserWithHintPass uri src of
    Left errs -> do
      expectationFailure $ "Parser failed: " <> show errs
      error "unreachable"
    Right (MkModule _ _ (MkSection _ _ _ _ decls), _, _) ->
      pure
        [ (body, fmap getRef (view annRef (getAnno body)))
        | Decide _ (MkDecide _ _ _ body) <- decls
        ]

spec :: Spec
spec = describe "@ref annotations attach to arbitrary AST nodes" $ do
  it "attaches a @ref that precedes an expression to that expression node" $ do
    bodies <-
      decideBodyRefs
        "GIVEN x IS A NUMBER\nDECIDE doubled x IS\n  @ref https://example.com/section-1a\n  x * 2\n"
    case bodies of
      [(_, mRef)] ->
        case mRef of
          Just t -> t `shouldSatisfy` Text.isInfixOf "section-1a"
          Nothing ->
            expectationFailure "Expected a @ref attached to the DECIDE body expression"
      _ -> expectationFailure $ "Expected exactly one DECIDE, got: " <> show (length bodies)

  it "attaches distinct @refs to distinct expression bodies" $ do
    bodies <-
      decideBodyRefs $
        Text.unlines
          [ "GIVEN x IS A NUMBER"
          , "DECIDE doubled x IS"
          , "  @ref https://example.com/section-1a"
          , "  x * 2"
          , ""
          , "GIVEN n IS A NUMBER"
          , "DECIDE isPositive IF"
          , "  @ref https://example.com/section-2a"
          , "  n > 0"
          ]
    let refs = [ mRef | (_, mRef) <- bodies ]
    length refs `shouldBe` 2
    (refs !! 0 >>= \t -> if Text.isInfixOf "section-1a" t then Just () else Nothing)
      `shouldBe` Just ()
    (refs !! 1 >>= \t -> if Text.isInfixOf "section-2a" t then Just () else Nothing)
      `shouldBe` Just ()

  it "leaves the body ref empty when there is no @ref" $ do
    bodies <- decideBodyRefs "DECIDE answer IS 42\n"
    case bodies of
      [(_, mRef)] -> mRef `shouldBe` Nothing
      _ -> expectationFailure $ "Expected exactly one DECIDE, got: " <> show (length bodies)

  -- Regression: a @ref on the line ABOVE the first top-level declaration must
  -- attach to that declaration, NOT be greedily claimed by the enclosing
  -- Module/Section (which share the first declaration's start position because
  -- the leading @ref cluster is excluded from their visible range).
  it "attaches a leading @ref to the first declaration, not the Module" $ do
    (moduleRef, firstDeclRef) <-
      moduleAndFirstDeclRefs $
        Text.unlines
          [ "@ref https://example.com/section-leading"
          , "DECIDE answer IS 42"
          ]
    moduleRef `shouldBe` Nothing
    case firstDeclRef of
      Just t  -> t `shouldSatisfy` Text.isInfixOf "section-leading"
      Nothing ->
        expectationFailure "Expected the leading @ref to attach to the first declaration"

  -- The inline `<<…>>` form shares its lexer with `@nlg`'s `[…]` form only in
  -- the sense that both are "an annotation between heralds". They must NOT
  -- share an escape: `L4.Nlg.unescapeNlgText` runs on the NLG linearizer's path
  -- alone, so a backslash consumed on the ref path would be kept for ever and
  -- the pre-escape text would stop being writable.
  --
  -- Both cases below pass on `unstable` and both were broken, briefly, by a
  -- first cut of the `\%`/`\]` escape that let `refAnnotation` share the
  -- escaping body. Neither had a witness anywhere in the corpus or the specs,
  -- which is why they are here.
  -- An inline @ref attaches to the node that FOLLOWS it, so these put the
  -- annotation above the body rather than after it; trailing it would leave it
  -- unattached and the assertion would be about nothing.
  --
  -- `\>` escapes a right angle bracket (ruled 2026-09-17). Before that a
  -- literal `>>` inside a citation was unrepresentable, because the annotation
  -- terminated at the first one. The decode happens where the parser builds the
  -- 'Ref' node, NOT in the lexer: the token stays verbatim so exactprint
  -- re-emits the citation byte for byte.
  -- The expected values keep their `<<`/`>>`: 'getRef' hands back the
  -- annotation as the lexer captured it, delimiters and all, and every reader
  -- strips them itself ('L4.Docassemble.Lower.citationText' does, with
  -- stripPrefix/stripSuffix — checked, because a reader that split on the FIRST
  -- `>>` would mis-strip a citation that now legitimately contains one; none
  -- does).
  describe "the inline @ref form escapes its closing herald" $ do
    it "keeps a lone > as ordinary text rather than ending the annotation" $ do
      -- Unchanged by the escape, and it must stay that way: a `>` that does not
      -- complete the herald is ordinary text and always has been.
      bodies <-
        decideBodyRefs
          "GIVEN x IS A BOOLEAN\nDECIDE p IF\n  <<s.5 > s.3>>\n  x\n"
      case bodies of
        [(_, Just t)] -> t `shouldBe` "<<s.5 > s.3>>"
        _ -> expectationFailure $ "Expected one DECIDE carrying a @ref, got: " <> show (length bodies)

    it "carries a literal >> through an escaped herald, decoded for the reader" $ do
      bodies <-
        decideBodyRefs
          "GIVEN x IS A BOOLEAN\nDECIDE p IF\n  <<see s.5 \\>> onward>>\n  x\n"
      case bodies of
        [(_, Just t)] -> t `shouldBe` "<<see s.5 >> onward>>"
        _ -> expectationFailure $ "Expected one DECIDE carrying a @ref, got: " <> show (length bodies)

    it "leaves a backslash that cannot begin an escape as ordinary text" $ do
      -- `\q` is not an escape, so it stays two characters — the same rule the
      -- NLG side follows, and the reason the lexer consumes exactly the set the
      -- decoder honours.
      bodies <-
        decideBodyRefs
          "GIVEN x IS A BOOLEAN\nDECIDE p IF\n  <<see s.5\\q here>>\n  x\n"
      case bodies of
        [(_, Just t)] -> t `shouldBe` "<<see s.5\\q here>>"
        _ -> expectationFailure $ "Expected one DECIDE carrying a @ref, got: " <> show (length bodies)

    it "decodes an escaped backslash" $ do
      bodies <-
        decideBodyRefs
          "GIVEN x IS A BOOLEAN\nDECIDE p IF\n  <<see s.5 \\\\ here>>\n  x\n"
      case bodies of
        [(_, Just t)] -> t `shouldBe` "<<see s.5 \\ here>>"
        _ -> expectationFailure $ "Expected one DECIDE carrying a @ref, got: " <> show (length bodies)

    it "decodes in the LINE form too, where the herald is not special" $ do
      -- Nothing needs escaping on a line annotation — it runs to end of line —
      -- but the decode is applied at the Ref node, which both forms share, so
      -- the two spellings cannot disagree about what `\>` means.
      bodies <-
        decideBodyRefs
          "GIVEN x IS A BOOLEAN\nDECIDE p IF\n  @ref see s.5 \\> onward\n  x\n"
      case bodies of
        [(_, Just t)] -> t `shouldSatisfy` Text.isInfixOf "s.5 > onward"
        _ -> expectationFailure $ "Expected one DECIDE carrying a @ref, got: " <> show (length bodies)

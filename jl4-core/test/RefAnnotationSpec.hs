{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
module RefAnnotationSpec (spec) where

import qualified Data.Text as Text

import Base
import L4.Annotation (getAnno, rangeOf)
import L4.Parser (execProgramParserWithHintPass)
import L4.Parser.ResolveAnnotation (refWarningMessage)
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import L4.Syntax
  ( Anno
  , Decide (..)
  , Expr (..)
  , Module (..)
  , Name
  , Section (..)
  , TopDecl (..)
  , annPmSynthetic
  , annRef
  , annRefs
  , getRef
  , refCitation
  )
import Optics (gplate, toListOf)
import Test.Hspec

-- | The text of the ref nearest a node, if it holds any: what an exporter shows.
nearestRef :: Anno -> Maybe Text
nearestRef anno = getRef <$> view annRef anno

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
      let moduleRef = nearestRef (getAnno m)
      firstDeclRef <- case decls of
        (d : _) -> pure $ nearestRef (getAnno d)
        []      -> do
          expectationFailure "Expected at least one top-level declaration"
          error "unreachable"
      pure (moduleRef, firstDeclRef)

-- | For every @\@ref@ and the node that holds it: the line of that node (0 if
-- it has no range), whether the parser generated the node while compiling a
-- group of clauses ('annPmSynthetic'), and the last segment of the citation.
-- Sorted, because a traversal of the tree meets a clause group's parts in the
-- order of its fields and not of the source.
refHolderMarks :: Text -> IO [(Int, Bool, Text)]
refHolderMarks src = do
  let uri = toNormalizedUri (Uri "file:///ref-annotation-spec-marks")
      segment = Text.takeWhileEnd (/= '/') . refCitation
  case execProgramParserWithHintPass uri src of
    Left errs -> do
      expectationFailure $ "Parser failed: " <> show errs
      error "unreachable"
    Right (m, _, _) ->
      pure $ sort
        [ (maybe 0 (\ r -> r.start.line) (rangeOf a), isJust (view annPmSynthetic a), segment ref)
        | a <- toListOf (gplate @Anno) m
        , ref <- view annRefs a
        ]

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
        [ (body, nearestRef (getAnno body))
        | Decide _ (MkDecide _ _ _ body) <- decls
        ]

-- | Parse a source snippet and return, for each top-level declaration, the last
-- path segment of every @\@ref@ attached to it, in the order they are held;
-- and the message of every warning about where a @\@ref@ sits, in the order
-- reported.
declRefsAndMessages :: Text -> IO ([[Text]], [Text])
declRefsAndMessages src = do
  let uri = toNormalizedUri (Uri "file:///ref-annotation-spec-messages")
      segment = Text.takeWhileEnd (/= '/') . Text.strip . getRef
  case execProgramParserWithHintPass uri src of
    Left errs -> do
      expectationFailure $ "Parser failed: " <> show errs
      error "unreachable"
    Right (MkModule _ _ (MkSection _ _ _ _ decls), _, warnings) ->
      pure
        ( [ fmap segment (view annRefs (getAnno d)) | d <- decls ]
        , mapMaybe refWarningMessage warnings
        )

-- | The citation (as written) of every ref held by ANY node of the module, in
-- the order the traversal meets them.
heldRefs :: Text -> IO [Text]
heldRefs src = do
  let uri = toNormalizedUri (Uri "file:///ref-annotation-spec-held")
  case execProgramParserWithHintPass uri src of
    Left errs -> do
      expectationFailure $ "Parser failed: " <> show errs
      error "unreachable"
    Right (m, _, _) -> pure [ getRef r | a <- toListOf (gplate @Anno) m, r <- view annRefs a ]

-- | Parse a source snippet and return the last path segment of the ref NEAREST
-- each top-level declaration, if it holds any.
declNearestRefs :: Text -> IO [Maybe Text]
declNearestRefs src = do
  let uri = toNormalizedUri (Uri "file:///ref-annotation-spec-nearest")
      segment = Text.takeWhileEnd (/= '/') . Text.strip
  case execProgramParserWithHintPass uri src of
    Left errs -> do
      expectationFailure $ "Parser failed: " <> show errs
      error "unreachable"
    Right (MkModule _ _ (MkSection _ _ _ _ decls), _, _) ->
      pure [ segment <$> nearestRef (getAnno d) | d <- decls ]

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

  -- Every @ref that precedes a node is held by that node, in source order.
  -- (A node used to hold one, the nearest, and every other was reported as
  -- unattached, which was false: it had been outranked, not left without a
  -- node.) The pending refs are kept in the order they end, and each
  -- node claims those that precede it from the front of that list, so a
  -- mistake in keeping the order would show here: as a ref on the wrong node,
  -- or one reported that should have attached.
  it "keeps every @ref before a node, in source order, and reports only the one with nothing after it" $ do
    (attached, messages) <-
      declRefsAndMessages $
        Text.unlines
          [ "@ref https://example.com/one"
          , "@ref https://example.com/two"
          , "DECIDE a IS 1"
          , "@ref https://example.com/three"
          , "DECIDE b IS 2"
          , "@ref https://example.com/four"
          ]
    attached `shouldBe` [["one", "two"], ["three"]]
    messages `shouldBe` [endOfFile "https://example.com/four"]

  -- What a reader that shows one citation per node reads is the NEAREST ref,
  -- the one written last (card R1: in a stack the exporters show the nearest).
  it "gives a node's nearest ref as the last of those it holds" $ do
    nearest <-
      declNearestRefs $
        Text.unlines
          [ "@ref https://example.com/one"
          , "@ref https://example.com/two"
          , "DECIDE a IS 1"
          , "DECIDE b IS 2"
          ]
    nearest `shouldBe` [Just "two", Nothing]

  describe "a @ref with nothing after it" $ do
    it "says so, naming the citation" $ do
      (attached, messages) <-
        declRefsAndMessages "DECIDE a IS 1\n@ref https://example.com/last\n"
      attached `shouldBe` [[]]
      messages `shouldBe` [endOfFile "https://example.com/last"]

    it "names the citation without its herald, its trailing spaces or a carriage return" $ do
      (_, messages) <-
        declRefsAndMessages "DECIDE a IS 1\r\n@ref https://example.com/crlf   \r\n"
      messages `shouldBe` [endOfFile "https://example.com/crlf"]
      any (Text.any (== '\r')) messages `shouldBe` False

    it "names an inline citation without its angle brackets" $ do
      (_, messages) <- declRefsAndMessages "DECIDE a IS 1\n<<s.5 (1)>>\n"
      messages `shouldBe` [endOfFile "s.5 (1)"]

  describe "a @ref that follows code on its line" $ do
    -- A ref refers to what FOLLOWS it, so one written after code cannot cite
    -- that code; nor is it handed to the next construct, whose citation it
    -- would then silently become. It is attached to nothing (card R1, option A).
    it "warns, and is attached to nothing" $ do
      (attached, messages) <-
        declRefsAndMessages "DECIDE a IS 1 @ref https://example.com/cite\nDECIDE b IS 2\n"
      attached `shouldBe` [[], []]
      messages `shouldBe` [afterCode "https://example.com/cite" "DECIDE a IS 1"]
      heldRefs "DECIDE a IS 1 @ref https://example.com/cite\nDECIDE b IS 2\n" `shouldReturn` []

    it "warns once, and not also as having nothing after it, at the end of the file" $ do
      (_, messages) <-
        declRefsAndMessages "DECIDE a IS 1 @ref https://example.com/cite\n"
      messages `shouldBe` [afterCode "https://example.com/cite" "DECIDE a IS 1"]

    it "warns about an inline <<...>> at the end of a code line" $ do
      (_, messages) <-
        declRefsAndMessages "GIVEN x IS A BOOLEAN\nDECIDE p IF x <<s.5>>\n  AND TRUE\n"
      messages `shouldBe` [afterCode "s.5" "DECIDE p IF x"]
      heldRefs "GIVEN x IS A BOOLEAN\nDECIDE p IF x <<s.5>>\n  AND TRUE\n" `shouldReturn` []

    it "does not warn about an inline <<...>> in the middle of a line, which binds to the next word" $ do
      (_, messages) <-
        declRefsAndMessages "GIVEN x IS A BOOLEAN\nDECIDE p IF x AND <<s.5>> TRUE\n"
      messages `shouldBe` []
      heldRefs "GIVEN x IS A BOOLEAN\nDECIDE p IF x AND <<s.5>> TRUE\n" `shouldReturn` ["<<s.5>>"]

  describe "a @ref on a line of its own" $ do
    it "binds to the construct below it and draws no warning" $ do
      (attached, messages) <-
        declRefsAndMessages "@ref https://example.com/own\nDECIDE a IS 1\n\n-- a comment\nDECIDE b IS 2\n"
      attached `shouldBe` [["own"], []]
      messages `shouldBe` []

    it "still binds to the construct below it across a blank line and a comment" $ do
      (attached, messages) <-
        declRefsAndMessages "DECIDE a IS 1\n@ref https://example.com/far\n\n-- a comment\n\nDECIDE b IS 2\n"
      attached `shouldBe` [[], ["far"]]
      messages `shouldBe` []

    it "is held by the section heading below it, together with every other @ref above the heading" $ do
      (attached, messages) <-
        declRefsAndMessages $
          Text.unlines
            [ "@ref https://example.com/act"
            , "@ref https://example.com/part"
            , "§ `Part 1`"
            , "DECIDE a IS 1"
            ]
      attached `shouldBe` [["act", "part"]]
      messages `shouldBe` []

  -- A group of clauses is compiled to one definition: a CONSIDER on the first
  -- clause, and a local definition, with a range of its own, that holds the
  -- clauses after it and is written after the first clause's body. A ref
  -- inside the first clause, or above a later one, is held by the first node
  -- the drafter wrote after it, and never by that generated definition.
  describe "a @ref in a rule written as clauses" $ do
    it "is held by a node the drafter wrote" $ do
      holders <-
        refHolderMarks
          (Text.unlines
            [ "GIVEN n IS A NUMBER"
            , "GIVETH A STRING"
            , "@ref https://example.com/above-group"
            , "DECIDE `how many` 0 IS <<in-clause-1>> \"none\""
            , "@ref https://example.com/above-clause-2"
            , "DECIDE `how many` 1 IS \"one\""
            , "@ref https://example.com/above-clause-3"
            , "DECIDE `how many` other IS \"many\""
            ])
      holders
        `shouldBe` [ (4, False, "above-group")
                   , (4, False, "in-clause-1")
                   , (6, False, "above-clause-2")
                   , (8, False, "above-clause-3")
                   ]

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

-- | The message for a @\@ref@ with nothing after it. Quoted in
-- @doc/reference/syntax/README.md@, which is the page to change with it.
endOfFile :: Text -> Text
endOfFile citation =
  "This @ref (`" <> citation <> "`) is at the end of the file, so there is nothing after it to attach to."

-- | The message for a @\@ref@ that follows the given code on its line.
afterCode :: Text -> Text -> Text
afterCode citation code =
  "This @ref (`" <> citation <> "`) follows code on its line, but a @ref refers to what follows it, so this one is attached to nothing. Put it on the line above `" <> code <> "`."

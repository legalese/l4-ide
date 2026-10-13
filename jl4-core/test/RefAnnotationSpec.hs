{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
module RefAnnotationSpec (spec) where

import Control.Exception (evaluate)
import qualified Data.Text as Text
import System.CPUTime (getCPUTime)

import Base
import L4.Annotation (getAnno, rangeOf)
import L4.Parser (execProgramParser, execProgramParserWithHintPass)
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
  , annRef
  , annRefs
  , getRef
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
    Right (m@(MkModule _ _ (MkSection _ _ _ decls)), _, _) -> do
      let moduleRef = nearestRef (getAnno m)
      firstDeclRef <- case decls of
        (d : _) -> pure $ nearestRef (getAnno d)
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
    Right (MkModule _ _ (MkSection _ _ _ decls), _, _) ->
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
    Right (MkModule _ _ (MkSection _ _ _ decls), _, warnings) ->
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
    Right (MkModule _ _ (MkSection _ _ _ decls), _, _) ->
      pure [ segment <$> nearestRef (getAnno d) | d <- decls ]

-- | Where each ref lands: the line and column at which the node that holds it
-- starts, with the citation's last path segment, in the order the traversal
-- meets them. A ref that lands where the author put the node after it starts
-- at the position of that node's first token.
refPlacements :: Text -> IO [((Int, Int), Text)]
refPlacements src = do
  let uri = toNormalizedUri (Uri "file:///ref-annotation-spec-placements")
      segment = Text.takeWhileEnd (/= '/') . Text.strip . getRef
  case execProgramParserWithHintPass uri src of
    Left errs -> do
      expectationFailure $ "Parser failed: " <> show errs
      error "unreachable"
    Right (m, _, _) ->
      pure
        [ ((r.start.line, r.start.column), segment ref)
        | a <- toListOf (gplate @Anno) m
        , ref <- view annRefs a
        , Just r <- [rangeOf a]
        ]

-- | @attachesInLinearTime small large limit line@: parsing @large@ lines made
-- by @line@ (one definition each) takes less than @limit@ times the CPU time
-- of parsing @small@ lines. A ratio short of twice the limit is measured
-- again, up to twice, so that one pause does not fail it. The warnings are
-- forced as well as the definitions, because they depend on the last state of
-- every pass that attaches annotations to the tree: so each of them has run
-- to the end when the clock stops.
attachesInLinearTime :: Int -> Int -> Double -> (Int -> Text) -> Expectation
attachesInLinearTime smallSize largeSize limit line = do
  let file k = Text.unlines (map line [1 .. k])
      uri = toNormalizedUri (Uri "file:///ref-annotation-spec-timing")
      parse src =
        case execProgramParser uri src of
          Left errs -> do
            expectationFailure $ "Parser failed: " <> show errs
            error "unreachable"
          Right (MkModule _ _ (MkSection _ _ _ decls), warnings) -> do
            _ <- evaluate (length warnings)
            pure (length [ () | Decide _ _ <- decls ])
      timeParse k = do
        src <- evaluate (file k)
        _ <- evaluate (Text.length src)
        t0 <- getCPUTime
        n <- parse src
        t1 <- getCPUTime
        n `shouldBe` k
        pure (fromIntegral (t1 - t0) :: Double)
      fastest k tries = minimum <$> traverse (const (timeParse k)) [1 .. tries :: Int]
  small <- fastest smallSize 3
  let ratio large = large / max small 1.0e9
      settle tries = do
        r <- ratio <$> timeParse largeSize
        if r < limit || r >= 2 * limit || tries <= (1 :: Int) then pure r else min r <$> settle (tries - 1)
  r <- settle 3
  r `shouldSatisfy` (< limit)

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

  -- Every @ref that precedes a node is held by that node, in source order. The
  -- pending refs are kept in the order they end, and each node claims those
  -- that precede it from the front of that list, so a mistake in keeping the
  -- order would show here: as a ref on the wrong node, or one reported that
  -- should have attached.
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
  -- the one written last (ruled 2026-10-12: in a stack the exporters show the
  -- nearest).
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
    -- would then silently become. It is attached to nothing (ruled 2026-10-12).
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

  -- The node a ref lands on is the one that starts at the first token after
  -- it, whatever kind of node that is. Each case puts a ref on the line above
  -- a different kind of construct and reads where the node that holds it starts.
  describe "the node a @ref lands on" $ do
    it "is the operand after it, when the ref sits inside an expression" $ do
      refPlacements "DECIDE r IS 1 +\n  @ref https://example.com/operand\n  2\n"
        `shouldReturn` [((3, 3), "operand")]

    it "is the operand after it, inside the LEFT operand of an infix call" $ do
      -- The range of an infix call is its keyword and no more, so the call
      -- starts after its left operand, and used to claim the ref in it.
      refPlacements
        (Text.unlines
          [ "GIVEN a IS A NUMBER, b IS A NUMBER"
          , "GIVETH A NUMBER"
          , "a `plus` b MEANS a + b"
          , ""
          , "DECIDE r IS (1 +"
          , "  @ref https://example.com/two"
          , "  2) `plus` 3"
          ])
        `shouldReturn` [((7, 3), "two")]

    it "is the type after it" $ do
      refPlacements "GIVEN x IS A\n  @ref https://example.com/type\n  NUMBER\nDECIDE r IS x\n"
        `shouldReturn` [((3, 3), "type")]

    it "is the field after it" $ do
      refPlacements "DECLARE Person HAS\n  @ref https://example.com/field\n  name IS A STRING\n"
        `shouldReturn` [((3, 3), "field")]

    it "is the branch after it, in a CONSIDER" $ do
      refPlacements
        (Text.unlines
          [ "GIVEN n IS A NUMBER"
          , "GIVETH A NUMBER"
          , "DECIDE f n IS"
          , "  CONSIDER n"
          , "  @ref https://example.com/branch"
          , "  WHEN 0 THEN 1"
          , "  OTHERWISE 2"
          ])
        `shouldReturn` [((6, 3), "branch")]

  -- An @\@ref@ goes to the first node that starts at or after its end, and
  -- every node visited used to scan every ref not yet claimed, so a file with
  -- a citation on each of n definitions took time quadratic in n: 16,000 of
  -- them took 30 s to check, where the same definitions without citations
  -- took 2 s. With that scan, parsing 8,000 definitions took 44 to 45 times as
  -- long as 1,000 (four runs). Linear is 8 times, so this times 1,000 and
  -- 8,000 lines and fails above twice that.
  it "attaches @ref citations in time linear in their number" $
    attachesInLinearTime 1000 8000 16 \ i ->
      "@ref https://example.com/s" <> Text.pack (show i) <> "\nf" <> Text.pack (show i) <> " x MEANS " <> Text.pack (show i)

-- | The message for a @\@ref@ with nothing after it. Quoted in
-- @doc/reference/syntax/README.md@, which is the page to change with it.
endOfFile :: Text -> Text
endOfFile citation =
  "This @ref (`" <> citation <> "`) is at the end of the file, so there is nothing after it to attach to."

-- | The message for a @\@ref@ that follows the given code on its line.
afterCode :: Text -> Text -> Text
afterCode citation code =
  "This @ref (`" <> citation <> "`) follows code on its line, but a @ref refers to what follows it, so this one is attached to nothing. Put it on the line above `" <> code <> "`."

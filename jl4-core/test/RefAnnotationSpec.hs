{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
module RefAnnotationSpec (spec) where

import Control.Exception (evaluate)
import qualified Data.Text as Text
import System.CPUTime (getCPUTime)

import Base
import L4.Annotation (getAnno)
import L4.Parser (execProgramParser, execProgramParserWithHintPass)
import L4.Parser.ResolveAnnotation (Warning (..), WithSpan (..))
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
    Right (m@(MkModule _ _ (MkSection _ _ _ decls)), _, _) -> do
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
    Right (MkModule _ _ (MkSection _ _ _ decls), _, _) ->
      pure
        [ (body, fmap getRef (view annRef (getAnno body)))
        | Decide _ (MkDecide _ _ _ body) <- decls
        ]

-- | Parse a source snippet and return the last path segment of the @\@ref@
-- (if any) on each top-level declaration, and of each @\@ref@ reported as
-- not attached to anything, in the order reported.
declRefsAndUnattached :: Text -> IO ([Maybe Text], [Text])
declRefsAndUnattached src = do
  let uri = toNormalizedUri (Uri "file:///ref-annotation-spec-unattached")
      segment = Text.takeWhileEnd (/= '/') . Text.strip . getRef
  case execProgramParserWithHintPass uri src of
    Left errs -> do
      expectationFailure $ "Parser failed: " <> show errs
      error "unreachable"
    Right (MkModule _ _ (MkSection _ _ _ decls), _, warnings) ->
      pure
        ( [ fmap segment (view annRef (getAnno d)) | d <- decls ]
        , [ segment w.payload | RefUnattached w <- warnings ]
        )

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

  -- A node's 'Anno' carries one 'Ref'. When several precede the same node the
  -- nearest is attached and each of the others is reported, in source order;
  -- so is one with no node after it. The pending refs are kept in the order
  -- they end, and each node claims those that precede it from the front of
  -- that list, so a mistake in keeping the order would show here: as a ref on
  -- the wrong node, or one reported that should have attached.
  it "attaches the nearest of several @refs before a node, and reports the others" $ do
    (attached, unattached) <-
      declRefsAndUnattached $
        Text.unlines
          [ "@ref https://example.com/one"
          , "@ref https://example.com/two"
          , "DECIDE a IS 1"
          , "@ref https://example.com/three"
          , "DECIDE b IS 2"
          , "@ref https://example.com/four"
          ]
    attached `shouldBe` [Just "two", Just "three"]
    unattached `shouldBe` ["one", "four"]

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

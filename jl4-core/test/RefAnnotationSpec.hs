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

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
module UnifySpec (spec) where

import Test.Hspec
import Control.Exception (evaluate)
import System.Timeout (timeout)
import Data.Text (Text)
import qualified Data.Text as Text
import L4.API.VirtualFS
import L4.TypeCheck.Types (CheckError (..), CheckErrorWithContext (..))

-- | Run the type checker on a snippet under a watchdog: unification bugs
-- in this area historically caused nontermination, so a hang is reported
-- as a test failure instead of hanging the suite.
checks :: Text -> IO Bool
checks source = do
  mb <- timeout (30 * 1000000) (evaluate accepted)
  case mb of
    Nothing -> fail "type checker did not terminate within 30s"
    Just b -> pure b
  where
    accepted = case checkWithImports emptyVFS source of
      Left _errs -> False
      Right r -> r.tcdSuccess

spec :: Spec
spec = describe "Unification" $ do
  describe "sibling inference-variable rebinding (soundness)" $ do
    it "rejects PAIR OF a, a instantiated at two different types" $ do
      -- The pre-fix unifier let the second pair component silently rebind
      -- the inference variable already bound by the first, accepting this.
      ok <- checks $ Text.unlines
        [ "IMPORT prelude"
        , ""
        , "GIVEN a IS A TYPE"
        , "      p IS A PAIR OF a, a"
        , "GIVETH AN a"
        , "firstOf p MEANS"
        , "  CONSIDER p"
        , "  WHEN PAIR OF x, y THEN x"
        , ""
        , "GIVETH A NUMBER"
        , "n MEANS firstOf (PAIR OF \"hello\", 42)"
        ]
      ok `shouldBe` False

    it "accepts PAIR OF a, a at a consistent instantiation" $ do
      ok <- checks $ Text.unlines
        [ "IMPORT prelude"
        , ""
        , "GIVEN a IS A TYPE"
        , "      p IS A PAIR OF a, a"
        , "GIVETH AN a"
        , "firstOf p MEANS"
        , "  CONSIDER p"
        , "  WHEN PAIR OF x, y THEN x"
        , ""
        , "GIVETH A NUMBER"
        , "n MEANS firstOf (PAIR OF 41, 42)"
        ]
      ok `shouldBe` True

  describe "cyclic substitutions (termination)" $ do
    it "terminates and accepts swapped type arguments fed the same unknown" $ do
      -- Pre-fix this built the cyclic substitution a := b, b := a and
      -- looped forever in applySubst.
      ok <- checks $ Text.unlines
        [ "IMPORT prelude"
        , ""
        , "GIVEN a IS A TYPE"
        , "      b IS A TYPE"
        , "      p IS A PAIR OF a, b"
        , "      q IS A PAIR OF b, a"
        , "GIVETH A PAIR OF a, b"
        , "swappy p q MEANS p"
        , ""
        , "ASSUME mystery"
        , ""
        , "oops MEANS swappy mystery mystery"
        ]
      ok `shouldBe` True

  describe "type synonym cycles (termination)" $ do
    it "rejects a self-recursive type synonym" $ do
      ok <- checks $ Text.unlines
        [ "DECLARE Loop IS A Loop"
        , ""
        , "GIVETH A Loop"
        , "oops MEANS 42"
        ]
      ok `shouldBe` False

    it "rejects mutually recursive type synonyms" $ do
      ok <- checks $ Text.unlines
        [ "DECLARE Ping IS A Pong"
        , "DECLARE Pong IS A Ping"
        , ""
        , "GIVETH A Ping"
        , "oops MEANS 42"
        ]
      ok `shouldBe` False

    it "accepts a chain of non-cyclic synonyms" $ do
      ok <- checks $ Text.unlines
        [ "DECLARE Score IS A NUMBER"
        , "DECLARE Scores IS A LIST OF Score"
        , ""
        , "GIVETH A Scores"
        , "top MEANS LIST 1, 2"
        ]
      ok `shouldBe` True

    it "does not report a cycle when a synonym's parameter matches a sibling's name" $ do
      -- Name resolution rejects the shadowed reference as ambiguous, which
      -- is fine — but the cycle detector must not pile on with a spurious
      -- cycle: a synonym's own type parameters do not count as references
      -- to a like-named sibling synonym.
      let result = checkWithImports emptyVFS $ Text.unlines
            [ "DECLARE Score IS A NUMBER"
            , "DECLARE Tagged Score IS A LIST OF Score"
            , ""
            , "GIVETH A Tagged OF NUMBER"
            , "top MEANS LIST 1, 2"
            ]
      case result of
        Left errs -> fail ("unexpected pipeline failure: " <> show errs)
        Right r -> do
          r.tcdSuccess `shouldBe` False
          [e | MkCheckErrorWithContext e@(CyclicTypeSynonyms _) _ <- r.tcdErrors]
            `shouldBe` []

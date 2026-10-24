{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | Regression guard (specs/as-built/tc-soundness.md): ambiguous-but-well-typed
-- expressions under #ASSERT, #ASSERT REFUSED and TIMEZONE IS must surface as
-- 'AmbiguousTermError' diagnostics, exactly like #EVAL, instead of escaping
-- into 'runCheckUnique' and killing the process with
-- @error "internal error: expected unique result, got several"@.
--
-- This spec drives 'checkWithImports' directly (no CLI catch-all), so a
-- regression shows up as an 'ErrorCall' failing the test — the same failure
-- mode any library embedding of jl4-core would experience.
module DirectiveAmbiguitySpec (spec) where

import Test.Hspec
import Data.Text (Text)
import qualified Data.Text as Text

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Import.Resolution (TypeCheckWithDepsResult(..))
import L4.TypeCheck.Types (CheckErrorWithContext(..), CheckError(..))

-- | Run typecheck on a source snippet and return the 'AmbiguousTermError'
-- diagnostics that fired (or 'Left' on fatal failure). Before the fix, the
-- ambiguous cases never get this far: 'checkWithImports' throws 'ErrorCall'.
ambiguousTermErrors :: Text -> Either [Text] [CheckErrorWithContext]
ambiguousTermErrors source =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r -> Right
      [ e
      | e@MkCheckErrorWithContext{kind = AmbiguousTermError _ _} <- r.tcdErrors
      ]

-- | The 'OutOfScopeError' diagnostics a snippet raises. A source whose
-- directive keyword is not understood reads it as a name and reports it here,
-- so the cases that name a directive assert that nothing of the kind appears.
outOfScopeErrors :: Text -> Either [Text] [CheckErrorWithContext]
outOfScopeErrors source =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r -> Right
      [ e
      | e@MkCheckErrorWithContext{kind = OutOfScopeError _ _} <- r.tcdErrors
      ]

-- | Two definitions of @foo@ with the SAME type: no context can break the tie.
ambiguousFooDefs :: [Text]
ambiguousFooDefs =
  [ "ASSUME foo IS A FUNCTION FROM BOOLEAN TO BOOLEAN"
  , ""
  , "GIVEN p IS A BOOLEAN"
  , "DECIDE foo OF p"
  , "  IF p"
  ]

-- | Two definitions of @foo@ with DIFFERENT result types (BOOLEAN vs NUMBER):
-- a checked context (like #ASSERT's expected BOOLEAN) can disambiguate.
overloadedFooDefs :: [Text]
overloadedFooDefs =
  [ "ASSUME foo IS A FUNCTION FROM BOOLEAN TO BOOLEAN"
  , ""
  , "GIVEN p IS A BOOLEAN"
  , "DECIDE foo OF p"
  , "  IS 42"
  ]

spec :: Spec
spec = do
  describe "directive ambiguity is a diagnostic, not a crash" $ do
    it "#ASSERT on an ambiguous term reports AmbiguousTermError" $ do
      let src = Text.unlines $ ambiguousFooDefs ++ ["", "#ASSERT foo TRUE"]
      case ambiguousTermErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right ambs -> length ambs `shouldBe` 1

    it "TIMEZONE IS on an ambiguous term reports AmbiguousTermError" $ do
      let src = Text.unlines $ ambiguousFooDefs ++ ["", "TIMEZONE IS foo TRUE"]
      case ambiguousTermErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right ambs -> length ambs `shouldBe` 1

    it "TIMEZONE IS reports ambiguity even for differently-typed candidates" $ do
      -- inferExpr has no expected type, so BOTH candidates succeed and tie.
      let src = Text.unlines $ overloadedFooDefs ++ ["", "TIMEZONE IS foo TRUE"]
      case ambiguousTermErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right ambs -> length ambs `shouldBe` 1

    it "#ASSERT REFUSED on an ambiguous term reports AmbiguousTermError" $ do
      let src = Text.unlines $ ambiguousFooDefs ++ ["", "#ASSERT REFUSED foo TRUE"]
      case outOfScopeErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right oos -> oos `shouldBe` []
      case ambiguousTermErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right ambs -> length ambs `shouldBe` 1

    it "#ASSERT REFUSED reports ambiguity even for differently-typed candidates" $ do
      -- The expression of an #ASSERT REFUSED may have any type, so it is
      -- inferred with no expected type, and BOTH candidates succeed and tie.
      let src = Text.unlines $ overloadedFooDefs ++ ["", "#ASSERT REFUSED foo TRUE"]
      case outOfScopeErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right oos -> oos `shouldBe` []
      case ambiguousTermErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right ambs -> length ambs `shouldBe` 1

    it "control: #ASSERT still disambiguates by expected type (no error)" $ do
      -- The NUMBER-returning candidate fails the BOOLEAN check, leaving a
      -- unique success: type-directed disambiguation must keep working.
      let src = Text.unlines $ overloadedFooDefs ++ ["", "#ASSERT foo TRUE"]
      case ambiguousTermErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right ambs -> ambs `shouldBe` []

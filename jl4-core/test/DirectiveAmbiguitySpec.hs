{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | T4 regression guard: ambiguous-but-well-typed expressions under #ASSERT
-- and TIMEZONE IS must surface as 'AmbiguousTermError' diagnostics, exactly
-- like #EVAL, instead of escaping into 'runCheckUnique' and killing the
-- process with @error "internal error: expected unique result, got several"@.
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
-- diagnostics that fired (or 'Left' on fatal failure). Pre-T4-fix, the
-- ambiguous cases never get this far: 'checkWithImports' throws 'ErrorCall'.
ambiguousTermErrors :: Text -> Either [Text] [CheckErrorWithContext]
ambiguousTermErrors source =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r -> Right
      [ e
      | e@MkCheckErrorWithContext{kind = AmbiguousTermError _ _} <- r.tcdErrors
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
  describe "directive ambiguity is a diagnostic, not a crash (T4)" $ do
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

    it "control: #ASSERT still disambiguates by expected type (no error)" $ do
      -- The NUMBER-returning candidate fails the BOOLEAN check, leaving a
      -- unique success: type-directed disambiguation must keep working.
      let src = Text.unlines $ overloadedFooDefs ++ ["", "#ASSERT foo TRUE"]
      case ambiguousTermErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right ambs -> ambs `shouldBe` []

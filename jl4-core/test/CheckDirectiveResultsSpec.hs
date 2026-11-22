{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | The editor lists one result per @#CHECK@. Warnings sit beside the
-- @#CHECK@ answers among the diagnostics that do not block a check, and they
-- used to be listed with them: a module with one @#CHECK@ and three
-- @CONSIDER@s that miss a case sent four directive rows where it should send
-- one, so the Inspector panel could show a warning where a @#CHECK@'s type
-- belongs. 'checkDirectiveResults' is what the language server's two readers
-- of those diagnostics now go through.
module CheckDirectiveResultsSpec (spec) where

import Test.Hspec
import Data.Text (Text)
import qualified Data.Text as Text

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Import.Resolution (TypeCheckWithDepsResult(..))
import L4.Parser.SrcSpan (SrcPos(..), SrcRange(..))
import L4.TypeCheck.Types
  (CheckError(..), CheckErrorWithContext(..), Severity(..), checkDirectiveResults, severity)
import L4.Annotation (HasSrcRange(..))

-- | One @#CHECK@, on line 20, and three @CONSIDER@s that each miss a case.
source :: Text
source = Text.unlines
  [ "DECLARE Colour IS ONE OF Red, Green, Blue"
  , ""
  , "GIVEN c IS A Colour"
  , "GIVETH A NUMBER"
  , "DECIDE `first` IS"
  , "  CONSIDER c"
  , "  WHEN Red THEN 1"
  , ""
  , "GIVEN c IS A Colour"
  , "GIVETH A NUMBER"
  , "DECIDE `second` IS"
  , "  CONSIDER c"
  , "  WHEN Green THEN 2"
  , ""
  , "GIVEN c IS A Colour"
  , "GIVETH A NUMBER"
  , "DECIDE `third` IS"
  , "  CONSIDER c"
  , "  WHEN Blue THEN 3"
  , "#CHECK `first` OF Red"
  ]

nonBlocking :: [CheckErrorWithContext]
nonBlocking = case checkWithImports emptyVFS source of
  Left errs -> error ("the fixture failed to check: " <> show errs)
  Right r -> filter ((/= SError) . severity) r.tcdErrors

spec :: Spec
spec = describe "checkDirectiveResults" $ do
  it "the fixture has one #CHECK answer and three warnings beside it" $ do
    length [ () | MkCheckErrorWithContext CheckInfo {} _ <- nonBlocking ] `shouldBe` 1
    length [ () | MkCheckErrorWithContext CheckWarning {} _ <- nonBlocking ] `shouldBe` 3

  it "keeps the #CHECK answer and drops the warnings" $ do
    let results = checkDirectiveResults nonBlocking
    length results `shouldBe` 1
    [ line | Just (MkSrcRange (MkSrcPos line _) _ _ _) <- map rangeOf results ] `shouldBe` [20]

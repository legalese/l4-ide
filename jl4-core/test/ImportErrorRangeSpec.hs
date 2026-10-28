{-# LANGUAGE OverloadedStrings #-}

-- | The web editor's check ('l4Check') puts an import error on the @IMPORT@
-- that causes it, not at the start of the file.
module ImportErrorRangeSpec (spec) where


import qualified Base.Text as Text
import L4.API (l4Check)
import Test.Hspec

spec :: Spec
spec = describe "l4Check on an IMPORT that finds no module" $ do
  -- Lines in the JSON are 0-based: the IMPORT is on line 3.
  it "reports it on that IMPORT's line" $ do
    let diagnostics = l4Check "-- rules\n\nIMPORT prelude\nIMPORT zz_no_such_module\n\nx MEANS 1\n"
    diagnostics `shouldSatisfy` Text.isInfixOf "Module not found: zz_no_such_module"
    diagnostics `shouldSatisfy` Text.isInfixOf "\"line\":3"
    diagnostics `shouldNotSatisfy` Text.isInfixOf "\"line\":0"

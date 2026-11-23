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

  -- The case hint (smucclaw/l4-ide#1080) reaches the web editor too: its
  -- check comes through 'checkWithImportsLocated', which the merge of
  -- unstable into the #1080 branch routed through the names the hint needs.
  it "names the spelling when only the capitals differ, on that IMPORT's line" $ do
    let diagnostics = l4Check "-- rules\n\nIMPORT dayDate\n\nx MEANS 1\n"
    diagnostics `shouldSatisfy` Text.isInfixOf "Module not found: dayDate"
    diagnostics `shouldSatisfy` Text.isInfixOf "Did you mean `daydate`?"
    diagnostics `shouldSatisfy` Text.isInfixOf "\"line\":2"
    diagnostics `shouldNotSatisfy` Text.isInfixOf "\"line\":0"
    Text.count "\"severity\"" diagnostics `shouldBe` 1

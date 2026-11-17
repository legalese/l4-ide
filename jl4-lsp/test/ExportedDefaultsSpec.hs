{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | What the language server tells the deploy sidebar about an exported
-- function's defaults.
--
-- A default the schema publishes is a @default@ key beside the input. A default
-- it cannot publish, today the @TYPICALLY@ on an @ASSUME@ ('Export.honouredDefault'
-- drops it), leaves no key at all, which is indistinguishable from an input
-- that has no default. The sidebar must not show the second as the first, so
-- the summary names the inputs whose declared default the schema leaves out.
module ExportedDefaultsSpec (spec) where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Map.Strict as Map
import qualified Data.Text as T

import CheckSource (checkSource)
import qualified L4.Export as Export
import qualified L4.FunctionSchema as FSchema
import qualified LSP.L4.Inspector as Inspector
import LSP.L4.Rules (TypeCheckResult (..))

import Test.Hspec

-- | The summaries the language server sends the sidebar, as it sends them.
summaries :: TypeCheckResult -> [Inspector.ExportedFunctionSummary]
summaries tc =
  map (Inspector.exportedFunctionToSummary (FSchema.declaresFromModule tc.module'))
    (Export.enrichReturnTypes tc.entityInfo (Export.getExportedFunctions tc.module'))

summaryNamed :: T.Text -> TypeCheckResult -> Inspector.ExportedFunctionSummary
summaryNamed n tc = case filter (\s -> s.name == n) (summaries tc) of
  [s] -> s
  other -> error ("expected one export named " <> T.unpack n <> ", found " <> show (length other))

-- | A rule's own default is published; an ASSUME's is not, and is named.
withAssume :: T.Text
withAssume = T.unlines
  [ "ASSUME jurisdiction IS A STRING TYPICALLY \"SG\""
  , ""
  , "@export default eligible"
  , "GIVEN age IS A NUMBER TYPICALLY 18"
  , "GIVETH A BOOLEAN"
  , "DECIDE eligible IF age >= 18 AND jurisdiction EQUALS \"SG\""
  ]

withoutAssume :: T.Text
withoutAssume = T.unlines
  [ "@export default `the smaller of`"
  , "GIVEN a IS A NUMBER"
  , "      b IS A NUMBER TYPICALLY 0"
  , "GIVETH A NUMBER"
  , "DECIDE `the smaller of` IS IF a < b THEN a ELSE b"
  ]

spec :: Spec
spec = describe "the defaults the sidebar is told about" do
  it "names an ASSUME input whose TYPICALLY the schema cannot publish" do
    (_, tc) <- checkSource "exported-defaults-assume" withAssume
    (summaryNamed "eligible" tc).unpublishedDefaults `shouldBe` ["jurisdiction"]

  it "still publishes a rule's own default, and leaves the ASSUME input required with none" do
    (_, tc) <- checkSource "exported-defaults-assume-schema" withAssume
    let s = summaryNamed "eligible" tc
    fmap (.parameterDefault) (lookupParam "age" s) `shouldBe` Just (Just (Aeson.Number 18))
    fmap (.parameterDefault) (lookupParam "jurisdiction" s) `shouldBe` Just Nothing
    s.parameters.required `shouldContain` ["jurisdiction"]

  it "names nothing when every declared default is published" do
    (_, tc) <- checkSource "exported-defaults-none" withoutAssume
    let s = summaryNamed "the smaller of" tc
    s.unpublishedDefaults `shouldBe` []
    fmap (.parameterDefault) (lookupParam "b" s) `shouldBe` Just (Just (Aeson.Number 0))
    s.parameters.required `shouldBe` ["a"]

  it "puts the names in the JSON only when there are some" do
    (_, tcA) <- checkSource "exported-defaults-json-assume" withAssume
    (_, tcB) <- checkSource "exported-defaults-json-none" withoutAssume
    jsonKeys (summaryNamed "eligible" tcA) `shouldContain` ["unpublishedDefaults"]
    jsonKeys (summaryNamed "the smaller of" tcB) `shouldNotContain` ["unpublishedDefaults"]
 where
  lookupParam n s = Map.lookup n s.parameters.parameterMap
  jsonKeys s = case Aeson.toJSON s of
    Aeson.Object o -> map Key.toText (KeyMap.keys o)
    _ -> []

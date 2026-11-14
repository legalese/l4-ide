{-# LANGUAGE OverloadedStrings #-}

-- | The deployed schema and jl4-schema publish the same TYPICALLY default on a
-- top-level input and on an ASSUME the rule reads.
module DefaultsAgreeSpec (spec) where

import Test.Hspec

import Compiler (compileBundle)
import UnresolvedImportSpec (withLog)

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text

import Compatibility (detectBreakingChanges, ifaceFromSummary)
import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Export (getExportedFunctions)
import L4.FunctionSchema (Parameter (..), Parameters (..))
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.JsonSchema (emptyContext, generateJsonSchema)
import Types (DeploymentMetadata (..), FunctionSummary (..))

source :: Text
source = Text.unlines
  [ "ASSUME `applicable law` IS A STRING TYPICALLY \"Singapore\""
  , ""
  , "@export Whether a person may vote"
  , "GIVEN"
  , "  age     IS A NUMBER TYPICALLY 18"
  , "  married IS A BOOLEAN TYPICALLY FALSE"
  , "  plain   IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`may vote` age married plain MEANS"
  , "  age >= 18 AND `applicable law` EQUALS \"Singapore\" AND NOT married AND plain > 0"
  ]

-- | The deployed summary of the one exported function.
deployed :: IO FunctionSummary
deployed = do
  compiled <- withLog \logger -> compileBundle logger "defaults" (Map.singleton "rule.l4" source)
  case fst compiled of
    Left why -> fail (Text.unpack why)
    Right (_, meta) -> case meta.metaFunctions of
      [f] -> pure f
      fs -> fail ("expected one function, got " <> show (length fs))

-- | Each top-level input's @default@, as jl4-schema writes it.
schemaDefaults :: IO (Map.Map Text Aeson.Value)
schemaDefaults = do
  r <- either (fail . show) pure (checkWithImports emptyVFS source)
  e <- case getExportedFunctions r.tcdModule of
    e : _ -> pure e
    [] -> fail "no @export"
  case Aeson.toJSON (generateJsonSchema emptyContext e) of
    Aeson.Object o | Just (Aeson.Object props) <- KeyMap.lookup "properties" o ->
      pure $ Map.fromList
        [ (Key.toText k, d)
        | (k, Aeson.Object p) <- KeyMap.toList props
        , Just d <- [KeyMap.lookup "default" p]
        ]
    _ -> fail "jl4-schema wrote no properties"

spec :: Spec
spec = describe "TYPICALLY defaults, deployed and in jl4-schema" do
  it "publishes a top-level input's and an ASSUME's default, as jl4-schema does" do
    ps <- (.fsParameters) <$> deployed
    let service = Map.mapMaybe (.parameterDefault) ps.parameterMap
    expected <- schemaDefaults
    (Map.keys service, service) `shouldBe` (["age", "applicable law", "married"], expected)
  it "keeps an input with a default in the required list" do
    ps <- (.fsParameters) <$> deployed
    all (`elem` ps.required) ["age", "married", "plain", "applicable law"] `shouldBe` True
  it "finds nothing breaking in redeploying the same bundle" do
    f <- deployed
    g <- deployed
    detectBreakingChanges [ifaceFromSummary f] [ifaceFromSummary g] `shouldBe` []

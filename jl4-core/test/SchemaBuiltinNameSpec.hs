{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | Both schema generators decide from the resolved type, not from its name: a
-- type named like a builtin, declared here or imported, is that type.
module SchemaBuiltinNameSpec (spec) where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Aeson.Key as Key
import Test.Hspec

import L4.API.VirtualFS (checkWithImports, emptyVFS, vfsFromList)
import L4.Export (ExportedFunction(..), ExportedParam(..), getExportedFunctions)
import L4.FunctionSchema (Parameter(..), declaresFromModule, typeToParameter)
import L4.Import.Resolution (ResolvedImport(..), TypeCheckWithDepsResult(..))
import L4.JsonSchema (SchemaContext(..), emptyContext, generateJsonSchema)
import L4.TypeCheck.Types (CheckResult(..))

library :: Text
library = Text.unlines
  [ "DECLARE Text HAS body IS A NUMBER"
  , "DECLARE Time IS ONE OF Morning, Evening"
  ]

importing :: Text
importing = Text.unlines
  [ "IMPORT lib"
  , ""
  , "@export default uses types named like builtins"
  , "GIVEN t IS A Text"
  , "      tm IS A Time"
  , "      d IS A DATE"
  , "GIVETH A NUMBER"
  , "f t tm d MEANS t's body"
  ]

declaring :: Text
declaring = Text.unlines
  [ "DECLARE Text HAS body IS A NUMBER"
  , "DECLARE Date HAS day IS A NUMBER"
  , "DECLARE Time IS ONE OF Morning, Evening"
  , ""
  , "@export default uses types named like builtins"
  , "GIVEN t IS A Text"
  , "      da IS A Date"
  , "      tm IS A Time"
  , "      n IS A NUMBER"
  , "      s IS A STRING"
  , "      b IS A BOOLEAN"
  , "      d IS A DATE"
  , "      ti IS A TIME"
  , "      dt IS A DATETIME"
  , "GIVETH A NUMBER"
  , "f t da tm n s b d ti dt MEANS t's body"
  ]

checked :: [(Text, Text)] -> Text -> TypeCheckWithDepsResult
checked files source =
  case checkWithImports (if null files then emptyVFS else vfsFromList files) source of
    Left errs -> error (show errs)
    Right r -> r

export :: TypeCheckWithDepsResult -> ExportedFunction
export r = case getExportedFunctions r.tcdModule of
  e : _ -> e
  [] -> error "no @export"

-- | What the service does: it looks declarations up across the module and the
-- modules it imports (jl4-service Compiler.hs).
parameter :: TypeCheckWithDepsResult -> Text -> Parameter
parameter r name =
  case [ p.paramType | p <- (export r).exportParams, p.paramName == name ] of
    Just ty : _ -> typeToParameter declares Set.empty ty
    _ -> error ("no typed parameter " <> show name)
 where
  declares = Map.unions (declaresFromModule r.tcdModule : map (\i -> declaresFromModule i.riTypeChecked.program) r.tcdResolvedImports)

-- | What @jl4-schema@ writes for one input of the export.
jsonProperty :: TypeCheckWithDepsResult -> Text -> Aeson.Value
jsonProperty r name =
  case Aeson.toJSON (generateJsonSchema schemaContext (export r)) of
    Aeson.Object top
      | Just (Aeson.Object props) <- KeyMap.lookup "properties" top
      , Just v <- KeyMap.lookup (Key.fromText name) props -> v
    other -> error ("no property " <> show name <> " in " <> show other)
 where
  schemaContext = emptyContext { ctxDeclares = declaresFromModule r.tcdModule }

jsonType :: Text -> [(Aeson.Key, Aeson.Value)]
jsonType t = [("type", Aeson.String t)]

spec :: Spec
spec = describe "a type named like a builtin" $ do
  describe "L4.FunctionSchema (the service, the LSP, MLIR)" $ do
    it "a declared record is the record" $ do
      let p = parameter (checked [] declaring) "t"
      p.parameterType `shouldBe` "object"
      fmap Map.keys p.parameterProperties `shouldBe` Just ["body"]
      p.parameterFormat `shouldBe` Nothing

    it "a declared record named Date has no date format" $ do
      let p = parameter (checked [] declaring) "da"
      p.parameterType `shouldBe` "object"
      p.parameterFormat `shouldBe` Nothing

    it "a declared enum named Time lists its values" $ do
      let p = parameter (checked [] declaring) "tm"
      p.parameterFormat `shouldBe` Nothing
      p.parameterEnum `shouldBe` ["Morning", "Evening"]

    it "an imported record is the record" $ do
      let p = parameter (checked [("lib", library)] importing) "t"
      p.parameterType `shouldBe` "object"
      fmap Map.keys p.parameterProperties `shouldBe` Just ["body"]

    it "an imported enum named Time lists its values" $ do
      let p = parameter (checked [("lib", library)] importing) "tm"
      p.parameterFormat `shouldBe` Nothing
      p.parameterEnum `shouldBe` ["Morning", "Evening"]

    it "the builtins are still JSON primitives" $ do
      let r = checked [] declaring
          shape n = let p = parameter r n in (p.parameterType, p.parameterFormat)
      shape "n"  `shouldBe` ("number", Nothing)
      shape "s"  `shouldBe` ("string", Nothing)
      shape "b"  `shouldBe` ("boolean", Nothing)
      shape "d"  `shouldBe` ("string", Just "date")
      shape "ti" `shouldBe` ("string", Just "time")
      shape "dt" `shouldBe` ("string", Just "date-time")

  describe "L4.JsonSchema (jl4-schema)" $ do
    it "a declared type is a reference to its definition" $ do
      let r = checked [] declaring
      jsonProperty r "t"  `shouldBe` Aeson.object [("$ref", "#/$defs/Text")]
      jsonProperty r "da" `shouldBe` Aeson.object [("$ref", "#/$defs/Date")]
      jsonProperty r "tm" `shouldBe` Aeson.object [("$ref", "#/$defs/Time")]

    -- A dangling reference, because jl4-schema's context holds only the module's
    -- own declarations. That is a known limit; a false primitive would be worse.
    it "an imported type is a reference, never a primitive" $ do
      let r = checked [("lib", library)] importing
      jsonProperty r "t"  `shouldBe` Aeson.object [("$ref", "#/$defs/Text")]
      jsonProperty r "tm" `shouldBe` Aeson.object [("$ref", "#/$defs/Time")]

    it "the builtins are still JSON primitives" $ do
      let r = checked [] declaring
          withFormat f = Aeson.object [("format", Aeson.String f), ("type", "string")]
      jsonProperty r "n"  `shouldBe` Aeson.object (jsonType "number")
      jsonProperty r "s"  `shouldBe` Aeson.object (jsonType "string")
      jsonProperty r "b"  `shouldBe` Aeson.object (jsonType "boolean")
      jsonProperty r "d"  `shouldBe` withFormat "date"
      jsonProperty r "ti" `shouldBe` withFormat "time"
      jsonProperty r "dt" `shouldBe` withFormat "date-time"

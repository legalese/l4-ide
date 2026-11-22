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

-- | Record fields typed with a module's own one-argument @Optional@ and
-- @maybe@, and with the prelude's @MAYBE@. Only the last is the builtin.
optionals :: Text
optionals = Text.unlines
  [ "DECLARE Optional a IS ONE OF Absent, Present HAS value IS A a"
  , "DECLARE maybe a HAS v IS A a"
  , "DECLARE Holder HAS"
  , "  o IS AN Optional NUMBER"
  , "  m IS A MAYBE NUMBER"
  , "  w IS A maybe NUMBER"
  , ""
  , "@export default reads a holder"
  , "GIVEN h IS A Holder"
  , "GIVETH A NUMBER"
  , "f h MEANS 1"
  ]

-- | Synonyms for MAYBE, with and without an argument, and for LIST, as a
-- record field and as an input. The decoder expands each
-- ('L4.EvaluateLazy.Machine.expandTypeSynonyms'): `ok/schema-synonym-shapes.l4`
-- pins that it accepts null and omission for the first two.
synonyms :: Text
synonyms = Text.unlines
  [ "DECLARE Optional OF a IS A MAYBE a"
  , "DECLARE List OF a IS A LIST OF a"
  , "DECLARE OptNum IS A MAYBE NUMBER"
  , "DECLARE Holder HAS"
  , "  o IS AN Optional NUMBER"
  , "  p IS AN OptNum"
  , "  xs IS A List NUMBER"
  , "  n IS A NUMBER"
  , ""
  , "@export default reads a holder"
  , "GIVEN h IS A Holder"
  , "      extra IS AN Optional NUMBER"
  , "GIVETH A NUMBER"
  , "total h extra MEANS h's n"
  ]

-- | Synonyms for MAYBE twenty deep, without an argument and with one.
chain :: Text
chain = Text.unlines $
  [ "DECLARE S" <> n k <> " IS AN S" <> n (k + 1) | k <- [1 .. 19 :: Int] ]
  <> [ "DECLARE S20 IS A MAYBE NUMBER" ]
  <> [ "DECLARE A" <> n k <> " OF a IS AN A" <> n (k + 1) <> " a" | k <- [1 .. 19 :: Int] ]
  <> [ "DECLARE A20 OF a IS A MAYBE a"
     , "DECLARE Holder HAS"
     , "  s IS AN S1"
     , "  t IS AN A1 NUMBER"
     , "  n IS A NUMBER"
     , ""
     , "@export default reads a holder"
     , "GIVEN h IS A Holder"
     , "      x IS AN A1 NUMBER"
     , "      y IS AN S1"
     , "GIVETH A NUMBER"
     , "f h x y MEANS h's n"
     ]
 where
  n = Text.pack . show

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

-- | What @jl4-schema@ writes for a definition in @$defs@.
jsonDefinition :: TypeCheckWithDepsResult -> Text -> Aeson.Object
jsonDefinition r name =
  case Aeson.toJSON (generateJsonSchema schemaContext (export r)) of
    Aeson.Object top
      | Just (Aeson.Object defs) <- KeyMap.lookup "$defs" top
      , Just (Aeson.Object d) <- KeyMap.lookup (Key.fromText name) defs -> d
    other -> error ("no definition " <> show name <> " in " <> show other)
 where
  schemaContext = emptyContext { ctxDeclares = declaresFromModule r.tcdModule }

-- | Can a value that this schema describes be null? A reference is followed
-- into the definitions of the schema it is in.
nullable :: TypeCheckWithDepsResult -> Aeson.Value -> Bool
nullable r = \ case
  Aeson.Object o
    | Just (Aeson.Array opts) <- KeyMap.lookup "anyOf" o -> any (nullable r) opts
    | Just (Aeson.String "null") <- KeyMap.lookup "type" o -> True
    | Just (Aeson.String ref) <- KeyMap.lookup "$ref" o
    , Just name <- Text.stripPrefix "#/$defs/" ref -> nullable r (Aeson.Object (jsonDefinition r name))
  _ -> False

-- | The required fields of a definition, and the field schemas.
requiredAndFields :: TypeCheckWithDepsResult -> Text -> ([Text], Text -> Aeson.Value)
requiredAndFields r name =
  let d = jsonDefinition r name
      props = case KeyMap.lookup "properties" d of
        Just (Aeson.Object ps) -> ps
        _ -> error "no properties"
      required = case KeyMap.lookup "required" d of
        Just (Aeson.Array rs) -> [ t | Aeson.String t <- foldr (:) [] rs ]
        _ -> []
      field n = case KeyMap.lookup (Key.fromText n) props of
        Just v -> v
        Nothing -> error ("no field " <> show n)
   in (required, field)

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

  describe "a one-argument type named Optional or maybe is required unless it is MAYBE" $ do
    it "jl4-schema: required holds exactly the fields that cannot be null" $ do
      let d = jsonDefinition (checked [] optionals) "Holder"
          props = case KeyMap.lookup "properties" d of
            Just (Aeson.Object ps) -> ps
            _ -> error "no properties"
          required = case KeyMap.lookup "required" d of
            Just (Aeson.Array rs) -> [ t | Aeson.String t <- foldr (:) [] rs ]
            _ -> []
          field n = case KeyMap.lookup (Key.fromText n) props of
            Just v -> v
            Nothing -> error ("no field " <> show n)
      required `shouldBe` ["o", "w"]
      field "o" `shouldBe` Aeson.object [("$ref", "#/$defs/Optional")]
      field "w" `shouldBe` Aeson.object [("$ref", "#/$defs/maybe")]
      field "m" `shouldBe` Aeson.object [("anyOf", Aeson.toJSON [Aeson.object (jsonType "number"), Aeson.object (jsonType "null")])]
      [ n | n <- ["o", "m", "w"], not (nullable (checked [] optionals) (field n)) ] `shouldBe` required

    it "the service: required holds the same fields, and each is its declared type" $ do
      let p = parameter (checked [] optionals) "h"
          props = maybe (error "no properties") id p.parameterProperties
          field n = maybe (error ("no field " <> show n)) id (Map.lookup n props)
      p.parameterRequired `shouldBe` Just ["o", "w"]
      (field "o").parameterEnum `shouldBe` ["Absent", "Present"]
      fmap Map.keys (field "w").parameterProperties `shouldBe` Just ["v"]
      (field "m").parameterType `shouldBe` "number"

  describe "a synonym is decided by what it stands for, as the decoder does" $ do
    it "jl4-schema: a synonym for MAYBE is nullable and not required, and one for LIST is an array of its element" $ do
      let r = checked [] synonyms
          (required, field) = requiredAndFields r "Holder"
          number = Aeson.object (jsonType "number")
      required `shouldBe` ["xs", "n"]
      field "o" `shouldBe` Aeson.object [("anyOf", Aeson.toJSON [number, Aeson.object (jsonType "null")])]
      field "p" `shouldBe` Aeson.object [("$ref", "#/$defs/OptNum")]
      field "xs" `shouldBe` Aeson.object [("items", number), ("type", "array")]
      [ n | n <- ["o", "p", "xs", "n"], not (nullable r (field n)) ] `shouldBe` required
      jsonProperty r "extra" `shouldBe` Aeson.object [("anyOf", Aeson.toJSON [number, Aeson.object (jsonType "null")])]

    it "the service: the same fields are required, a synonym for MAYBE is its element, and one for LIST an array" $ do
      let r = checked [] synonyms
          p = parameter r "h"
          props = maybe (error "no properties") id p.parameterProperties
          field n = maybe (error ("no field " <> show n)) id (Map.lookup n props)
      p.parameterRequired `shouldBe` Just ["xs", "n"]
      (field "o").parameterType `shouldBe` "number"
      (field "p").parameterType `shouldBe` "number"
      (field "xs").parameterType `shouldBe` "array"
      fmap (.parameterType) (field "xs").parameterItems `shouldBe` Just "number"

    -- The service's `required` for its inputs, and jl4-schema's, come from here.
    it "an input typed with a synonym for MAYBE is not required" $ do
      [ (q.paramName, q.paramRequired) | q <- (export (checked [] synonyms)).exportParams ]
        `shouldBe` [("h", True), ("extra", False)]

    -- They used to stop after 16 steps.
    it "follows a chain of twenty synonyms to its end, in both generators and for inputs" $ do
      let r = checked [] chain
          (required, field) = requiredAndFields r "Holder"
          p = parameter r "h"
          props = maybe (error "no properties") id p.parameterProperties
          svc k = maybe (error ("no field " <> show k)) id (Map.lookup k props)
      required `shouldBe` ["n"]
      [ k | k <- ["s", "t", "n"], not (nullable r (field k)) ] `shouldBe` required
      p.parameterRequired `shouldBe` Just ["n"]
      ((svc "s").parameterType, (svc "t").parameterType) `shouldBe` ("number", "number")
      [ (q.paramName, q.paramRequired) | q <- (export r).exportParams ]
        `shouldBe` [("h", True), ("x", False), ("y", False)]

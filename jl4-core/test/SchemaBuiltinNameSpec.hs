{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | Both schema generators decide from the resolved type, not from its name: a
-- type named like a builtin, declared here or imported, is that type. Both
-- render the shape the export check gives it ('L4.Export.Shape.jsonShape').
module SchemaBuiltinNameSpec (spec) where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Aeson.Key as Key
import Test.Hspec

import L4.API.VirtualFS (checkWithImports, emptyVFS, vfsFromList)
import L4.Export (ExportedFunction(..), ExportedParam(..), getExportedFunctions)
import L4.Export.Shape (ShapeEnv, moduleDeclares, shapeEnvFromDeclares)
import L4.FunctionSchema (Parameter(..), typeToParameter)
import L4.Import.Resolution (ResolvedImport(..), TypeCheckWithDepsResult(..))
import L4.JsonSchema (JsonSchema, generateJsonSchema)
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

-- | Types the export check accepts that the generators used to describe on
-- their own: an EITHER, a type with parameters used at two types, and a
-- constructor that carries fields.
shapes :: Text
shapes = Text.unlines
  [ "DECLARE Box a HAS"
  , "  @desc What is in the box"
  , "  contents IS AN a"
  , "@desc A shape that carries its size"
  , "DECLARE Figure IS ONE OF Dot, Circle HAS radius IS A NUMBER"
  , ""
  , "@export default takes what the check accepts"
  , "GIVEN e IS AN EITHER STRING NUMBER"
  , "      nb IS A Box NUMBER"
  , "      sb IS A Box STRING"
  , "      f IS A Figure"
  , "GIVETH A NUMBER"
  , "g e nb sb f MEANS 1"
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

-- | What the export check reads types from: the declarations of the module and
-- of the modules it imports. Both generators render the shape it gives.
shapeEnv :: TypeCheckWithDepsResult -> ShapeEnv
shapeEnv r =
  shapeEnvFromDeclares
    (foldMap moduleDeclares (r.tcdModule : map (\i -> i.riTypeChecked.program) r.tcdResolvedImports))
    r.tcdEntityInfo

-- | What the service publishes for one input (jl4-service Compiler.hs).
parameter :: TypeCheckWithDepsResult -> Text -> Parameter
parameter r name =
  case [ p.paramType | p <- (export r).exportParams, p.paramName == name ] of
    Just ty : _ -> either (error . show) id (typeToParameter (shapeEnv r) ty)
    _ -> error ("no typed parameter " <> show name)

schema :: TypeCheckWithDepsResult -> JsonSchema
schema r = either (error . show) id (generateJsonSchema (shapeEnv r) (export r))

-- | What @jl4-schema@ writes for one input of the export.
jsonProperty :: TypeCheckWithDepsResult -> Text -> Aeson.Value
jsonProperty r name =
  case Aeson.toJSON (schema r) of
    Aeson.Object top
      | Just (Aeson.Object props) <- KeyMap.lookup "properties" top
      , Just v <- KeyMap.lookup (Key.fromText name) props -> v
    other -> error ("no property " <> show name <> " in " <> show other)

-- | What @jl4-schema@ writes for a definition in @$defs@.
jsonDefinition :: TypeCheckWithDepsResult -> Text -> Aeson.Object
jsonDefinition r name =
  case Aeson.toJSON (schema r) of
    Aeson.Object top
      | Just (Aeson.Object defs) <- KeyMap.lookup "$defs" top
      , Just (Aeson.Object d) <- KeyMap.lookup (Key.fromText name) defs -> d
    other -> error ("no definition " <> show name <> " in " <> show other)

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

    -- It used to be a dangling reference: jl4-schema read only the module's own
    -- declarations, where the export check reads the imported ones too.
    it "an imported type is a reference to its definition, never a primitive" $ do
      let r = checked [("lib", library)] importing
      jsonProperty r "t"  `shouldBe` Aeson.object [("$ref", "#/$defs/Text")]
      jsonProperty r "tm" `shouldBe` Aeson.object [("$ref", "#/$defs/Time")]
      KeyMap.lookup "properties" (jsonDefinition r "Text") `shouldBe` Just (Aeson.object [("body", Aeson.object (jsonType "number"))])
      KeyMap.lookup "enum" (jsonDefinition r "Time") `shouldBe` Just (Aeson.toJSON ["Morning", "Evening" :: Text])

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
      -- A type with parameters is named with what it is given: its fields are
      -- those of that type.
      field "o" `shouldBe` Aeson.object [("$ref", "#/$defs/Optional OF NUMBER")]
      field "w" `shouldBe` Aeson.object [("$ref", "#/$defs/maybe OF NUMBER")]
      KeyMap.lookup "properties" (jsonDefinition (checked [] optionals) "maybe OF NUMBER") `shouldBe` Just (Aeson.object [("v", Aeson.object (jsonType "number"))])
      field "m" `shouldBe` Aeson.object [("anyOf", Aeson.toJSON [Aeson.object (jsonType "number"), Aeson.object (jsonType "null")])]
      [ n | n <- ["o", "m", "w"], not (nullable (checked [] optionals) (field n)) ] `shouldBe` required

    it "the service: required holds the same fields, and each is its declared type" $ do
      let p = parameter (checked [] optionals) "h"
          props = maybe (error "no properties") id p.parameterProperties
          field n = maybe (error ("no field " <> show n)) id (Map.lookup n props)
      p.parameterRequired `shouldBe` Just ["o", "w"]
      -- a constructor with a field and one without: the names and the tagged
      -- constructor (HATBOX, MULLET)
      fmap (map (\m -> (m.parameterType, m.parameterEnum, fmap Map.keys m.parameterProperties))) (field "o").parameterOneOf
        `shouldBe` Just [("string", ["Absent"], Nothing), ("object", [], Just ["Present"])]
      fmap Map.keys (field "w").parameterProperties `shouldBe` Just ["v"]
      (field "m").parameterType `shouldBe` "number"

  describe "a synonym is decided by what it stands for, as the decoder does" $ do
    it "jl4-schema: a synonym for MAYBE is nullable and not required, and one for LIST is an array of its element" $ do
      let r = checked [] synonyms
          (required, field) = requiredAndFields r "Holder"
          number = Aeson.object (jsonType "number")
      required `shouldBe` ["xs", "n"]
      field "o" `shouldBe` Aeson.object [("anyOf", Aeson.toJSON [number, Aeson.object (jsonType "null")])]
      -- A synonym is written as what it stands for, as the check sees it.
      field "p" `shouldBe` Aeson.object [("anyOf", Aeson.toJSON [number, Aeson.object (jsonType "null")])]
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

  describe "both generators render the shape the export check gives a type" $ do
    -- jl4-schema wrote "$ref": "#/$defs/EITHER" with no $defs, and the service
    -- an object with nothing in it. Both now describe the form the encoder
    -- writes, {"LEFT":[v]} or {"RIGHT":[v]} (wire-form bench, card J3, option B,
    -- ruled 2026-10-15). A Parameter has no oneOf, so the service's says both
    -- keys may be there, and requires neither.
    it "an EITHER is LEFT or RIGHT, each an array of one side, with no dangling reference" $ do
      let r = checked [] shapes
          side key ty = Aeson.object
            [ ("properties", Aeson.object [(key, Aeson.object [("items", Aeson.object [("type", ty)]), ("type", "array")])])
            , ("required", Aeson.toJSON [key])
            , ("type", "object")
            ]
      jsonProperty r "e" `shouldBe` Aeson.object [("oneOf", Aeson.toJSON [side "LEFT" "string", side "RIGHT" "number"])]
      let p = parameter r "e"
          sideOf k = p.parameterProperties >>= Map.lookup k
      p.parameterType `shouldBe` "object"
      p.parameterRequired `shouldBe` Nothing
      fmap (.parameterType) (sideOf "LEFT") `shouldBe` Just "array"
      fmap (.parameterType) (sideOf "LEFT" >>= (.parameterItems)) `shouldBe` Just "string"
      fmap (.parameterType) (sideOf "RIGHT" >>= (.parameterItems)) `shouldBe` Just "number"

    it "a type with parameters has the fields of the type it is given, once for each" $ do
      let r = checked [] shapes
      jsonProperty r "nb" `shouldBe` Aeson.object [("$ref", "#/$defs/Box OF NUMBER")]
      jsonProperty r "sb" `shouldBe` Aeson.object [("$ref", "#/$defs/Box OF STRING")]
      KeyMap.lookup "properties" (jsonDefinition r "Box OF NUMBER")
        `shouldBe` Just (Aeson.object [("contents", Aeson.object [("description", " What is in the box"), ("type", "number")])])
      KeyMap.lookup "properties" (jsonDefinition r "Box OF STRING")
        `shouldBe` Just (Aeson.object [("contents", Aeson.object [("description", " What is in the box"), ("type", "string")])])
      let contents n = (parameter r n).parameterProperties >>= Map.lookup "contents"
      fmap (.parameterType) (contents "nb") `shouldBe` Just "number"
      fmap (.parameterType) (contents "sb") `shouldBe` Just "string"
      (parameter r "nb").parameterL4Type `shouldBe` Just "Box"

    it "a type that contains itself refers to its definition, and to none that is not there" $ do
      let r = checked [] (Text.unlines
            [ "DECLARE Tree HAS kids IS A LIST OF Tree"
            , "DECLARE Grows a HAS"
            , "  v IS AN a"
            , "  next IS A MAYBE (Grows OF (LIST OF a))"
            , ""
            , "@export default holds both"
            , "GIVEN t IS A Tree"
            , "      g IS A Grows OF NUMBER"
            , "GIVETH A NUMBER"
            , "f t g MEANS 1"
            ])
      KeyMap.lookup "properties" (jsonDefinition r "Tree")
        `shouldBe` Just (Aeson.object [("kids", Aeson.object [("items", Aeson.object [("$ref", "#/$defs/Tree")]), ("type", "array")])])
      KeyMap.lookup "properties" (jsonDefinition r "Grows OF NUMBER")
        `shouldBe` Just (Aeson.object
          [ ("v", Aeson.object (jsonType "number"))
          , ("next", Aeson.object [("anyOf", Aeson.toJSON [Aeson.object [("properties", Aeson.object []), ("type", "object")], Aeson.object (jsonType "null")])])
          ])

    -- A constructor that carries fields is tagged, {"Circle": {"radius": 2}},
    -- and one that carries none is its name, "Dot" (wire-form card J1, option
    -- A; HATBOX). A type with both is a oneOf of the two forms on both
    -- generators (MULLET). A @desc is carried as written, with the space after
    -- the keyword.
    it "a type with a constructor that carries fields and one that carries none is a oneOf of names and tagged objects" $ do
      let r = checked [] shapes
          d = jsonDefinition r "Figure"
          circle = Aeson.object
            [ ("properties", Aeson.object [("Circle", Aeson.object
                [ ("properties", Aeson.object [("radius", Aeson.object (jsonType "number"))])
                , ("required", Aeson.toJSON ["radius" :: Text])
                , ("type", "object") ])])
            , ("required", Aeson.toJSON ["Circle" :: Text])
            , ("type", "object") ]
      KeyMap.lookup "oneOf" d `shouldBe` Just (Aeson.toJSON
        [ Aeson.object [("enum", Aeson.toJSON ["Dot" :: Text]), ("type", "string")], circle ])
      KeyMap.lookup "description" d `shouldBe` Just " A shape that carries its size"
      let p = parameter r "f"
      p.parameterType `shouldBe` ""
      p.parameterDescription `shouldBe` " A shape that carries its size"
      p.parameterL4Type `shouldBe` Just "Figure"
      fmap (map (\m -> (m.parameterType, m.parameterEnum, fmap Map.keys m.parameterProperties))) p.parameterOneOf
        `shouldBe` Just [("string", ["Dot"], Nothing), ("object", [], Just ["Circle"])]
      fmap (map (\m -> (.parameterRequired) <$> (Map.lookup "Circle" =<< m.parameterProperties))) p.parameterOneOf
        `shouldBe` Just [Nothing, Just (Just ["radius"])]

    it "a type whose constructors all carry fields is the tagged object alone" $ do
      let r = checked [] (Text.unlines
            [ "DECLARE Cut IS ONE OF"
            , "  Slice HAS width IS A NUMBER"
            , "  Wedge HAS angle IS A NUMBER"
            , "@export cut"
            , "GIVEN c IS A Cut"
            , "GIVETH A NUMBER"
            , "cutting c MEANS 1"
            ])
          p = parameter r "c"
      (p.parameterType, p.parameterOneOf, fmap Map.keys p.parameterProperties) `shouldBe` ("object", Nothing, Just ["Slice", "Wedge"])
      KeyMap.lookup "oneOf" (jsonDefinition r "Cut") `shouldSatisfy` maybe False (\v -> case v of Aeson.Array a -> length a == 2; _ -> False)

    it "an enumeration whose constructors carry nothing is still the names" $ do
      let r = checked [] (Text.unlines
            [ "DECLARE Hue IS ONE OF Red, Blue"
            , "@export hue"
            , "GIVEN h IS A Hue"
            , "GIVETH A Hue"
            , "same h MEANS h"
            ])
          p = parameter r "h"
      (p.parameterType, p.parameterEnum, p.parameterOneOf) `shouldBe` ("string", ["Red", "Blue"], Nothing)

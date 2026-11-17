{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module SchemaSpec (spec) where

import Test.Hspec
import Test.QuickCheck (Arbitrary (..))
import qualified Test.QuickCheck as Q
import Test.QuickCheck.Instances ()

import Backend.Api
import Backend.DecisionQueryPlan (QueryAtom (..), QueryOutcome (..), QueryImpact (..), QueryInput (..), QueryAsk (..), QueryRefusal (..), QueryPlanResponse (..))
import qualified L4.Decision.QueryPlan as QP
import L4.FunctionSchema (Parameters (..), Parameter (..))
import Compiler (eventRecordParameter)
import ControlPlane (DeploymentStatusResponse (..))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as Aeson.KeyMap
import qualified Data.Map as Map
import qualified Data.Maybe as Maybe
import qualified Data.Text as Text
import Schema (serverOpenApi)
import Servant.API (FromHttpApiData (..))
import Types
import qualified Test.Hspec.QuickCheck as Hspec
import Test.QuickCheck.Property
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)

spec :: Spec
spec = do
  describe "Schema" do
    describe "BatchResponse" do
      it "describes the report every batch response states (UNKNOWN-EVALUATION-SPEC U7b)" do
        let at k v = case v of
              Aeson.Object o -> Aeson.KeyMap.lookup k o
              _              -> Nothing
            report = at "components" (Aeson.toJSON (serverOpenApi Nothing))
              >>= at "schemas" >>= at "BatchResponse" >>= at "properties" >>= at "report"
        (report >>= at "enum") `shouldBe` Just (Aeson.toJSON ["default" :: Text.Text])

    describe "Param Schema" do
      describe "FnLiteral" do
        Hspec.prop "Int" $ \(n :: Integer) ->
          parseQueryParam (Text.pack $ show n) === Right (FnLitInt n)
        Hspec.prop "Bool" $ \(n :: Bool) ->
          parseQueryParam (Text.pack $ show n) === Right (FnLitBool n)

    describe "Parameter x-l4-type" do
      it "serialises parameterL4Type as \"x-l4-type\" only when set" do
        let p = Parameter
              { parameterType = "object"
              , parameterAlias = Nothing
              , parameterFormat = Nothing
              , parameterEnum = []
              , parameterDescription = ""
              , parameterProperties = Nothing
              , parameterPropertyOrder = Nothing
              , parameterItems = Nothing
              , parameterRequired = Nothing
              , parameterL4Type = Just "Child Order"
              , parameterDefault = Nothing
              }
        case Aeson.toJSON p of
          Aeson.Object o ->
            Aeson.KeyMap.lookup "x-l4-type" o `shouldBe` Just (Aeson.String "Child Order")
          v -> expectationFailure ("Expected JSON object, got: " <> show v)
      it "omits x-l4-type when parameterL4Type is Nothing" do
        let p = Parameter "string" Nothing Nothing [] "" Nothing Nothing Nothing Nothing Nothing Nothing
        case Aeson.toJSON p of
          Aeson.Object o ->
            Aeson.KeyMap.member "x-l4-type" o `shouldBe` False
          v -> expectationFailure ("Expected JSON object, got: " <> show v)
      it "serialises parameterDefault as \"default\" only when set" do
        let p = (Parameter "boolean" Nothing Nothing [] "" Nothing Nothing Nothing Nothing Nothing Nothing)
                  { parameterDefault = Just (Aeson.Bool True) }
        case Aeson.toJSON p of
          Aeson.Object o ->
            Aeson.KeyMap.lookup "default" o `shouldBe` Just (Aeson.Bool True)
          v -> expectationFailure ("Expected JSON object, got: " <> show v)
      it "omits default when parameterDefault is Nothing" do
        let p = Parameter "boolean" Nothing Nothing [] "" Nothing Nothing Nothing Nothing Nothing Nothing
        case Aeson.toJSON p of
          Aeson.Object o ->
            Aeson.KeyMap.member "default" o `shouldBe` False
          v -> expectationFailure ("Expected JSON object, got: " <> show v)
      Hspec.prop "round-trips through JSON" $ \p ->
        Aeson.fromJSON (Aeson.toJSON (p :: Parameter)) === Aeson.Success p
      -- NOTHING is a default: a MAYBE input with TYPICALLY NOTHING publishes
      -- "default": null. Read back from the metadata cache it must still be a
      -- default, or a redeploy that changes it is not reported.
      it "reads an explicit null default back as a default, not as none" do
        let p = (Parameter "number" Nothing Nothing [] "" Nothing Nothing Nothing Nothing Nothing Nothing)
                  { parameterDefault = Just Aeson.Null }
        Aeson.fromJSON (Aeson.toJSON p) `shouldBe` Aeson.Success p
        (.parameterDefault) <$> (Aeson.eitherDecode "{\"type\":\"number\",\"default\":null}" :: Either String Parameter)
          `shouldBe` Right (Just Aeson.Null)
        (.parameterDefault) <$> (Aeson.eitherDecode "{\"type\":\"number\"}" :: Either String Parameter)
          `shouldBe` Right Nothing

    -- A batch case that failed is written with @error and no value, and read
    -- back as failed rather than as an answer whose result is named "@error".
    describe "OutputCase" do
      let errored = OutputCase
            { id = 1, attributes = Map.empty, graphviz = Nothing, presumed = []
            , outcome = CaseErrored "Parameter 'n': missing required parameter" }
          answered = OutputCase
            { id = 2, attributes = Map.singleton "value" (FnLitInt 8), graphviz = Nothing, presumed = []
            , outcome = CaseAnswered }
      it "writes an errored case as @id and @error" do
        Aeson.toJSON errored `shouldBe` Aeson.object
          [ "@id" Aeson..= (1 :: Int)
          , "@presumed" Aeson..= ([] :: [Text.Text])
          , "@error" Aeson..= ("Parameter 'n': missing required parameter" :: Text.Text) ]
      it "writes an answered case as @id and its result" do
        Aeson.toJSON answered `shouldBe` Aeson.object
          [ "@id" Aeson..= (2 :: Int), "@presumed" Aeson..= ([] :: [Text.Text]), "value" Aeson..= (8 :: Int) ]
      it "reads both back as they were written" do
        Aeson.fromJSON (Aeson.toJSON [errored, answered]) `shouldBe` Aeson.Success [errored, answered]

    -- O4 of the 2026-10-11 overnight bench: an event's record is written into
    -- the generated wrapper as source, not decoded, so its schema is not an
    -- argument's.
    describe "eventRecordParameter" do
      let param t = Parameter t Nothing Nothing [] "" Nothing Nothing Nothing Nothing Nothing Nothing
          withDefault v p = p { parameterDefault = Just v }
          record l4Type fields = (param "object")
            { parameterProperties = Just (Map.fromList fields)
            , parameterPropertyOrder = Just (map fst fields)
            , parameterRequired = Just [n | (n, p) <- fields, Maybe.isNothing p.parameterDefault]
            , parameterL4Type = Just l4Type
            }
          address = record "Address"
            [ ("zip", param "number")
            , ("floor", withDefault (Aeson.Number 1) (param "number"))
            ]
          driver = record "Driver"
            [ ("name", param "string")
            , ("licence", withDefault (Aeson.String "full") (param "string"))
            , ("homes", (param "array") { parameterItems = Just address })
            , ("zhome", address { parameterDescription = "where they live" })
            ]
          event = eventRecordParameter driver
          field name = Map.lookup name (Maybe.fromMaybe mempty event.parameterProperties)
          fieldOf name p = Map.lookup name (Maybe.fromMaybe mempty p.parameterProperties)

      it "requires every field, in declaration order, and takes the defaults off" do
        event.parameterRequired `shouldBe` Just ["name", "licence", "homes", "zhome"]
        field "licence" `shouldSatisfy` Maybe.isJust
        (field "licence" >>= (.parameterDefault)) `shouldBe` Nothing

      it "writes a nested record under its constructor's name, with every field required" do
        let wrapper = Maybe.fromJust (field "zhome")
        wrapper.parameterRequired `shouldBe` Just ["Address"]
        wrapper.parameterPropertyOrder `shouldBe` Just ["Address"]
        wrapper.parameterL4Type `shouldBe` Nothing
        wrapper.parameterDescription `shouldBe` "where they live. Written under its constructor's name: {\"Address\": {...}}."
        let inner = Maybe.fromJust (fieldOf "Address" wrapper)
        inner.parameterRequired `shouldBe` Just ["zip", "floor"]
        inner.parameterL4Type `shouldBe` Just "Address"
        inner.parameterDescription `shouldBe` ""
        (fieldOf "floor" inner >>= (.parameterDefault)) `shouldBe` Nothing

      it "writes a record in a list the same way" do
        let homes = Maybe.fromJust (field "homes")
            element = Maybe.fromJust homes.parameterItems
        element.parameterRequired `shouldBe` Just ["Address"]
        (fieldOf "Address" element >>= (.parameterRequired)) `shouldBe` Just ["zip", "floor"]

      it "writes the records of a party that is itself a list like a record in a list" do
        let party = eventRecordParameter ((param "array") { parameterItems = Just address })
            element = Maybe.fromJust party.parameterItems
        element.parameterRequired `shouldBe` Just ["Address"]
        (fieldOf "Address" element >>= (.parameterRequired)) `shouldBe` Just ["zip", "floor"]
        (fieldOf "Address" element >>= fieldOf "floor" >>= (.parameterDefault)) `shouldBe` Nothing
        -- a list of text has no fields to require
        eventRecordParameter ((param "array") { parameterItems = Just (param "string") })
          `shouldBe` (param "array") { parameterItems = Just (param "string") }

      it "tells a MAYBE field to be written as null, and leaves a record in it plain" do
        -- 'typeToParameter' publishes MAYBE x as x: such a field is out of the
        -- record's required list and has no default, or its default is null
        let person = (record "Person"
              [ ("name", param "string")
              , ("nick", param "string")
              , ("age", withDefault Aeson.Null (param "number"))
              , ("licence", withDefault (Aeson.String "full") (param "string"))
              , ("zhome", address)
              ]) { parameterRequired = Just ["name"] }
            event' = eventRecordParameter person
            described name = fmap (.parameterDescription) (fieldOf name event')
        event'.parameterRequired `shouldBe` Just ["name", "nick", "age", "licence", "zhome"]
        described "nick" `shouldSatisfy` maybe False (Text.isInfixOf "write null")
        described "age" `shouldSatisfy` maybe False (Text.isInfixOf "write null")
        described "zhome" `shouldSatisfy` maybe False (Text.isInfixOf "write null")
        described "name" `shouldBe` Just ""
        described "licence" `shouldBe` Just ""
        -- the record in the MAYBE is plain: no constructor wrapper, its fields all written
        (fieldOf "zhome" event' >>= fieldOf "Address") `shouldBe` Nothing
        (fieldOf "zhome" event' >>= (.parameterRequired)) `shouldBe` Just ["zip", "floor"]
        (fieldOf "zhome" event' >>= fieldOf "floor" >>= (.parameterDefault)) `shouldBe` Nothing

      it "leaves alone what is not a record" do
        let enum = (param "string") { parameterEnum = ["wear seatbelt", "drive"], parameterL4Type = Just "Driver Action" }
            stub = (param "object") { parameterL4Type = Just "Driver" }
        eventRecordParameter enum `shouldBe` enum
        eventRecordParameter (param "number") `shouldBe` param "number"
        -- a record cut short by the schema's own recursion guard has no fields to require
        eventRecordParameter stub `shouldBe` stub

-- ----------------------------------------------------------------------------
-- Arbitrary instances
-- ----------------------------------------------------------------------------

instance Arbitrary FnLiteral where
  arbitrary =
    Q.frequency
      [ (1, FnLitBool <$> arbitrary)
      , (4, FnLitDouble <$> arbitrary)
      , (4, FnLitString <$> arbitrary)
      , (4, FnLitInt <$> arbitrary)
      , (1, pure FnUnknown)
      , (1, pure FnUncertain)
      ]

instance Arbitrary Reasoning where
  arbitrary = Q.sized $ \n -> do
    k <- Q.chooseInt (0, n)
    go k
   where
    go n = do
      code <- arbitrary
      expl <- arbitrary
      pars <- arbPartition (n - 1)
      forest <- mapM go pars
      return Reasoning
        { exampleCode = code
        , explanation = expl
        , children = forest
        }

    arbPartition :: Int -> Q.Gen [Int]
    arbPartition k = case compare k 1 of
      LT -> pure []
      EQ -> pure [1]
      GT -> do
        first <- Q.chooseInt (1, k)
        rest <- arbPartition $ k - first
        Q.shuffle (first : rest)

instance Arbitrary ResponseWithReason where
  arbitrary = ResponseWithReason <$> arbitrary <*> pure emptyTree <*> pure Nothing <*> arbitrary

instance Arbitrary EvaluatorError where
  arbitrary = Q.oneof
    [ InterpreterError <$> arbitrary
    , EvaluatorLimited <$> Q.arbitraryBoundedEnum <*> arbitrary ]

instance Arbitrary SimpleResponse where
  arbitrary =
    Q.oneof
      [ SimpleResponse <$> arbitrary
      , SimpleError <$> arbitrary
      ]

instance Arbitrary Parameters where
  arbitrary = do
    params <- arbitrary
    pure $ MkParameters params (Map.keys params)

instance Arbitrary Parameter where
  arbitrary = Q.sized $ \n ->
    if n <= 0
      then Parameter <$> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary <*> pure Nothing <*> pure Nothing <*> pure Nothing <*> pure Nothing <*> pure Nothing <*> pure Nothing
      else
        Parameter
          <$> arbitrary
          <*> arbitrary
          <*> arbitrary
          <*> arbitrary
          <*> arbitrary
          <*> Q.resize (n `div` 4) arbitrary
          <*> Q.resize (n `div` 4) arbitrary
          <*> Q.resize (n `div` 4) arbitrary
          <*> Q.resize (n `div` 4) arbitrary
          <*> arbitrary
          <*> pure Nothing

instance Arbitrary Function where
  arbitrary = Types.Function <$> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary

instance Arbitrary EvalBackend where
  arbitrary = Q.chooseEnum (minBound, maxBound)

instance Arbitrary TraceEvent where
  arbitrary = TraceEvent <$> arbitrary <*> arbitrary <*> arbitrary

instance Arbitrary FnArguments where
  arbitrary = FnArguments <$> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary

instance Arbitrary Presumption where
  arbitrary = Q.chooseEnum (minBound, maxBound)

instance Arbitrary SimpleFunction where
  arbitrary = SimpleFunction <$> arbitrary <*> arbitrary

instance Arbitrary OutcomeStyle where
  arbitrary = Q.chooseEnum (ValueOnly, BaseAttributes)

instance Arbitrary OutcomeObject where
  arbitrary =
    OutcomeObject
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary

instance Arbitrary BatchRequest where
  arbitrary =
    BatchRequest
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary

instance Arbitrary BatchResponse where
  arbitrary =
    BatchResponse
      <$> arbitrary
      <*> arbitrary

instance Arbitrary Outcomes where
  arbitrary = Q.oneof [OutcomeAttribute <$> arbitrary, OutcomePropertyObject <$> arbitrary]

instance Arbitrary InputCase where
  arbitrary = InputCase <$> arbitrary <*> arbitrary

instance Arbitrary OutputCase where
  arbitrary =
    OutputCase
      <$> arbitrary
      <*> arbitrary
      <*> pure Nothing  -- Exclude GraphViz from QuickCheck
      <*> arbitrary
      <*> Q.oneof
            [ pure CaseAnswered, CaseRefused <$> arbitrary, CaseErrored <$> arbitrary
            , CaseLimited <$> Q.arbitraryBoundedEnum <*> arbitrary ]

instance Arbitrary OutputSummary where
  arbitrary =
    OutputSummary
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary

instance Arbitrary QueryAtom where
  arbitrary = QueryAtom <$> arbitrary <*> arbitrary <*> arbitrary <*> pure []

instance Arbitrary QP.Verdict where
  arbitrary = Q.elements [minBound .. maxBound]

instance Arbitrary QueryOutcome where
  arbitrary = QueryOutcome <$> arbitrary <*> arbitrary <*> arbitrary

instance Arbitrary QueryImpact where
  arbitrary = QueryImpact <$> arbitrary <*> arbitrary

instance Arbitrary QueryInput where
  arbitrary =
    QueryInput
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary

instance Arbitrary QueryAsk where
  arbitrary =
    QueryAsk
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary

instance Arbitrary QueryPlanResponse where
  arbitrary =
    QueryPlanResponse
      <$> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> arbitrary
      <*> pure Nothing

instance Arbitrary QueryRefusal where
  arbitrary = QueryRefusal <$> arbitrary <*> arbitrary

instance Arbitrary StateGraphInfo where
  arbitrary = StateGraphInfo <$> arbitrary <*> arbitrary

instance Arbitrary StateGraphListResponse where
  arbitrary = StateGraphListResponse <$> arbitrary

instance Arbitrary DeploymentMetadata where
  arbitrary = DeploymentMetadata
    <$> arbitrary
    <*> arbitrary
    <*> arbitrary
    <*> pure (UTCTime (fromGregorian 2025 1 1) 0)
    <*> arbitrary
    <*> arbitrary
    <*> arbitrary

instance Arbitrary FunctionSummary where
  arbitrary = FunctionSummary <$> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary

instance Arbitrary FileEntry where
  arbitrary = FileEntry <$> arbitrary <*> arbitrary

instance Arbitrary DeploymentStatusResponse where
  arbitrary = DeploymentStatusResponse
    <$> arbitrary
    <*> Q.elements ["compiling", "ready", "failed"]
    <*> arbitrary
    <*> arbitrary
    <*> arbitrary
